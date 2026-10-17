import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bili_core/src/engine/ban_list.dart';
import 'package:bili_core/src/engine/hurry_placement.dart';
import 'package:bili_core/src/engine/node_stats.dart';
import 'package:bili_core/src/engine/primary_assigner.dart';
import 'package:bili_core/src/engine/range_downloader.dart';
import 'package:bili_core/src/engine/resolver.dart';
import 'package:test/test.dart';

import 'support/sim_cdn.dart';

const _hour = 3600 * 1000.0;
const _cosov = 'upos-sz-mirrorcosov.bilivideo.com';
const _aliov = 'upos-sz-mirroraliov.bilivideo.com';
const _hk1 = 'cn-hk-eq-01-01.bilivideo.com';
const _hk3 = 'cn-hk-eq-01-03.bilivideo.com';
const _akamai = 'upos-hz-mirrorakam.akamaized.net';
const _primary = 'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/v.m4s?deadline=9&os=cosbv';
const _akamaiURL = 'https://$_akamai/upgcxcode/1/2/3/v.m4s?deadline=9&os=akam';

String _on(String node) => NodeCatalog.swapHost(_primary, NodeAddress(node))!;

/// The phone's overseas nodes as the Swift logs measured them (13.9k pieces): first byte p50 and body speed.
final _phone = NodePriors.fixed({
  _akamai: const NodePrior(ttfbMs: 29, bps: 17.5e6),
  _aliov: const NodePrior(ttfbMs: 232, bps: 4.4e6),
  _cosov: const NodePrior(ttfbMs: 658, bps: 1.5e6),
  _hk1: const NodePrior(ttfbMs: 1000, bps: 0.2e6),
  _hk3: const NodePrior(ttfbMs: 1000, bps: 0.2e6),
});

/// Records each request's node and range on its way to the simulated CDN.
final class _Recording implements RangeTransport {
  _Recording(this.cdn);

  final SimCDN cdn;
  final requests = <({String node, ByteRange range})>[];

  @override
  int? get connectionsPerHost => cdn.connectionsPerHost;

  @override
  String get name => 'recording';

  @override
  void close() {}

  @override
  Future<TransportResponse> fetch(Uri url, ByteRange range, {CancelToken? cancel}) {
    requests.add((node: NodeCatalog.nodeKey(url.toString()), range: range));
    return cdn.fetch(url, range, cancel: cancel);
  }
}

void main() {
  group('NodeMemory', () {
    var now = 1.7e12;
    late NodeMemory memory;

    setUp(() {
      now = 1.7e12;
      memory = NodeMemory(wallClockMs: () => now)..signature = 'wifi';
    });

    test('keeps each network apart and stays off without one', () {
      memory.record(_aliov, ttfbMs: 30, bps: 17.5e6);
      expect(memory.prior(_aliov)?.ttfbMs, 30);
      expect(memory.prior(_aliov)?.bps, 17.5e6);
      expect(memory.prior(_aliov)?.bpsWeight, 1);
      memory.signature = 'cellular';
      expect(memory.prior(_aliov), isNull);
      memory.record(_aliov, bps: 1e6);
      memory.signature = 'wifi';
      expect(memory.prior(_aliov)?.bps, 17.5e6);
      memory.signature = '';
      expect(memory.prior(_aliov), isNull);
      memory.record(_cosov, bps: 1e6);
      memory.signature = 'wifi';
      expect(memory.prior(_cosov), isNull, reason: 'nothing is recorded on an unnamed network');
    });

    test('an estimate counts for half after 12 hours and is dropped after two days', () {
      memory.record(_aliov, ttfbMs: 230, bps: 4.4e6);
      now += 12 * _hour;
      expect(memory.prior(_aliov)!.bpsWeight, closeTo(0.5, 1e-9));
      now += 12 * _hour;
      expect(memory.prior(_aliov)!.bpsWeight, closeTo(0.25, 1e-9));
      expect(memory.prior(_aliov)!.bps, 4.4e6, reason: 'the value stays; only its weight falls');
      now += 23 * _hour;
      expect(memory.prior(_aliov), isNotNull, reason: '47 hours old');
      now += 2 * _hour;
      expect(memory.prior(_aliov), isNull, reason: '49 hours old');
    });

    test('each field ages from its own measurement', () {
      memory.record(_cosov, bps: 1.5e6);
      now += 30 * _hour;
      memory.record(_cosov, ttfbMs: 650);
      expect(memory.prior(_cosov)!.ttfbWeight, 1);
      expect(memory.prior(_cosov)!.bpsWeight, closeTo(0.177, 0.001));
      now += 20 * _hour;
      final prior = memory.prior(_cosov)!;
      expect(prior.bps, 0, reason: 'the speed is 50 hours old');
      expect(prior.ttfbMs, 650);
    });

    test('a clock set back counts as no time passed', () {
      memory.record(_aliov, bps: 4.4e6);
      now -= 5 * _hour;
      expect(memory.prior(_aliov)!.bpsWeight, 1);
    });

    test('survives a launch through JSON', () {
      memory
        ..record(_aliov, ttfbMs: 232, bps: 4.4e6)
        ..record(_hk1, bps: 0.2e6)
        ..signature = 'cellular'
        ..record(_cosov, ttfbMs: 900);
      now += _hour;
      final saved = jsonDecode(jsonEncode(memory.toJson()));
      final loaded = NodeMemory.fromJson(saved, wallClockMs: () => now)..signature = 'wifi';
      expect(loaded.prior(_aliov)?.ttfbMs, 232);
      expect(loaded.prior(_aliov)?.bps, 4.4e6);
      expect(loaded.prior(_aliov)?.bpsWeight, closeTo(0.944, 0.001), reason: 'an hour old');
      expect(loaded.prior(_hk1)?.bps, 0.2e6);
      expect(loaded.prior(_hk1)?.ttfbMs, 0);
      expect(loaded.prior(_cosov), isNull);
      loaded.signature = 'cellular';
      expect(loaded.prior(_cosov)?.ttfbMs, 900);
    });

    test('reads past what it cannot use', () {
      for (final json in <Object?>[
        null,
        'x',
        {'version': 2, 'networks': <String, Object?>{}},
        {'version': 1, 'networks': 'x'},
      ]) {
        final loaded = NodeMemory.fromJson(json, wallClockMs: () => now)..signature = 'wifi';
        expect(loaded.prior(_aliov), isNull, reason: '$json');
      }
      final loaded = NodeMemory.fromJson({
        'version': 1,
        'networks': {
          'wifi': {
            _aliov: {'bps': 'fast', 'bpsAt': now},
            _cosov: {'bps': 1.5e6, 'bpsAt': now, 'ttfbMs': -3, 'ttfbAt': now},
            '': {'bps': 1e6, 'bpsAt': now},
            _hk1: 'x',
          },
          '': {
            _hk3: {'bps': 1e6, 'bpsAt': now},
          },
        },
      }, wallClockMs: () => now)..signature = 'wifi';
      expect(loaded.prior(_aliov), isNull);
      expect(loaded.prior(_cosov)?.bps, 1.5e6);
      expect(loaded.prior(_cosov)?.ttfbMs, 0);
      expect(loaded.prior(_hk1), isNull);
      loaded.signature = '';
      expect(loaded.prior(_hk3), isNull);
    });

    test('saves nothing older than two days', () {
      memory
        ..record(_aliov, bps: 4.4e6)
        ..signature = 'cellular'
        ..record(_cosov, bps: 1.5e6);
      now += 25 * _hour;
      memory.record(_hk1, bps: 0.2e6);
      now += 25 * _hour;
      expect(memory.toJson(), {
        'version': 1,
        'networks': {
          'cellular': {
            _hk1: {'bps': 0.2e6, 'bpsAt': now - 25 * _hour},
          },
        },
      });
    });

    test('keeps the eight most recently used networks', () {
      for (var index = 0; index < NodeMemory.maxNetworks; index++) {
        memory
          ..signature = 'net$index'
          ..record(_aliov, bps: index + 1.0);
      }
      memory
        ..signature = 'net0'
        ..signature = 'net8'
        ..record(_aliov, bps: 9);
      final networks = (memory.toJson()['networks']! as Map).keys.toList();
      expect(networks, hasLength(NodeMemory.maxNetworks));
      expect(networks, isNot(contains('net1')), reason: 'the least recently used');
      expect(networks, containsAll(['net0', 'net8']));
      final loaded = NodeMemory.fromJson(memory.toJson(), wallClockMs: () => now)..signature = 'net0';
      expect(loaded.prior(_aliov)?.bps, 1);
    });

    test('priors follow the current network', () {
      memory.record(_aliov, bps: 4.4e6);
      final priors = memory.priors;
      expect(priors.of(_aliov)?.bps, 4.4e6);
      memory.signature = 'cellular';
      expect(priors.of(_aliov), isNull);
      expect(NodePriors.empty.isEmpty, isTrue);
      expect(priors.isEmpty, isFalse);
    });

    test('a prior blends with the first measurement by its weight', () {
      expect(NodePrior.blend(10e6, 1, 2e6), closeTo(10e6 * 0.7 + 2e6 * 0.3, 1e-3));
      expect(NodePrior.blend(10e6, 0.25, 2e6), closeTo(10e6 * 0.175 + 2e6 * 0.825, 1e-3));
      expect(NodePrior.blend(0, 1, 2e6), 2e6);
      expect(NodePrior.blend(10e6, 0, 2e6), 2e6);
      // 512 KiB at 4 MiB/s is 125 ms, plus the first byte.
      expect(const NodePrior(ttfbMs: 100, bps: 4 * 1024 * 1024).routeBps, closeTo(524288 * 1000 / 225, 1e-6));
      expect(const NodePrior(ttfbMs: 100).routeBps, 0);
    });
  });

  group('NodeStats with priors', () {
    final cosov = _on(_cosov);

    test('a remembered node is known before its first piece', () {
      final stats = NodeStats(priors: NodePriors.fixed({_cosov: const NodePrior(ttfbMs: 100, bps: 2e6)}));
      expect(stats.isKnown(cosov), isTrue);
      expect(stats.ttfbMs(cosov), 100);
      expect(stats.bps(cosov), 2e6);
      expect(stats.expectedMs(cosov, pieceBytes: 1000000), closeTo(600, 0.5));
      expect(stats.isKnown(_on(_aliov)), isFalse);
      expect(NodeStats().isKnown(cosov), isFalse, reason: 'no priors: as Swift');
    });

    test('the first measurement is blended with the prior, later ones smoothed as usual', () {
      final stats = NodeStats(
        priors: NodePriors.fixed({
          _cosov: const NodePrior(ttfbMs: 100, bps: 2e6, ttfbWeight: 0.5, bpsWeight: 0.5),
        }),
      );
      stats
        ..begin(cosov)
        ..firstByte(cosov, ms: 300)
        ..body(cosov, bytes: 1000000, ms: 1000)
        ..end(cosov, receiving: true);
      expect(stats.ttfbMs(cosov), closeTo(100 * 0.35 + 300 * 0.65, 1e-9));
      expect(stats.bps(cosov), closeTo(2e6 * 0.35 + 1e6 * 0.65, 1e-6));
      stats
        ..begin(cosov)
        ..firstByte(cosov, ms: 100)
        ..end(cosov, receiving: true);
      expect(stats.ttfbMs(cosov), closeTo(230 * 0.7 + 100 * 0.3, 1e-9));
    });

    test('outrun and crawl start from the prior', () {
      final stats = NodeStats(priors: NodePriors.fixed({_cosov: const NodePrior(ttfbMs: 100, bps: 2e6)}));
      stats.outrun(cosov, waitedMs: 50);
      expect(stats.ttfbMs(cosov), 100, reason: 'shorter than the prior first byte');
      stats.outrun(cosov, waitedMs: 1100);
      expect(stats.ttfbMs(cosov), closeTo(100 * 0.7 + 1100 * 0.3, 1e-9));
      stats.crawl(cosov, bytes: 100000, ms: 1000);
      expect(stats.bps(cosov), closeTo(2e6 * 0.7 + 1e5 * 0.3, 1e-6));
    });

    test('a network change falls back to the priors', () {
      final stats = NodeStats(priors: NodePriors.fixed({_cosov: const NodePrior(ttfbMs: 100, bps: 2e6)}));
      stats
        ..begin(cosov)
        ..firstByte(cosov, ms: 20)
        ..body(cosov, bytes: 1000000, ms: 100)
        ..end(cosov, receiving: true)
        ..reset();
      expect(stats.bps(cosov), 2e6);
      expect(stats.ttfbMs(cosov), 100);
    });

    test('measurements reach the memory, and the next session starts from them', () {
      var now = 1.7e12;
      final memory = NodeMemory(wallClockMs: () => now)..signature = 'wifi';
      final stats = NodeStats(priors: memory.priors, onMeasured: memory.record);
      stats
        ..begin(cosov)
        ..firstByte(cosov, ms: 40)
        ..body(cosov, bytes: 16 * 1024, ms: 1)
        ..end(cosov, receiving: true);
      expect(memory.prior(_cosov)?.ttfbMs, 40);
      expect(memory.prior(_cosov)?.bps, 0, reason: 'a small body says nothing about speed');
      stats
        ..begin(cosov)
        ..firstByte(cosov, ms: 40)
        ..body(cosov, bytes: 1000000, ms: 250)
        ..end(cosov, receiving: true)
        ..outrun(cosov, waitedMs: 1040);
      expect(memory.prior(_cosov)?.bps, 4e6);
      expect(memory.prior(_cosov)?.ttfbMs, closeTo(40 * 0.7 + 1040 * 0.3, 1e-9));
      now += _hour;
      final next = NodeStats(priors: memory.priors);
      expect(next.isKnown(cosov), isTrue);
      expect(next.expectedMs(cosov, pieceBytes: 1000000), closeTo(340 + 250, 1e-6));
    });
  });

  // In a hurry every copy on an HK node was outrun, so it is remembered by its slow first byte alone.
  test('with priors, a node of unknown speed costs at least its first byte in a hurry', () {
    final aliov = _on(_aliov);
    final cosov = _on(_cosov);
    final hk = _on(_hk1);
    List<String> place(NodePriors priors) {
      final stats = NodeStats(priors: priors);
      for (final (url, ttfb, bps) in [(aliov, 45.0, 7.1e6), (cosov, 229.0, 1e6)]) {
        stats
          ..begin(url)
          ..firstByte(url, ms: ttfb)
          ..body(url, bytes: 1000000, ms: 1e9 / bps)
          ..end(url, receiving: true);
      }
      stats.outrun(hk, waitedMs: 505);
      return HurryPlacement.assign(
        urls: [aliov, cosov, hk],
        count: 8,
        pieceBytes: 142 * 1024,
        nodes: stats,
        delivered: (_) => true,
      );
    }

    expect(place(NodePriors.empty), contains(hk), reason: 'Swift: twice the best node, about 130 ms');
    final placed = place(NodePriors.fixed({_hk1: const NodePrior(ttfbMs: 505)}));
    expect(placed, isNot(contains(hk)));
    expect(placed.where((url) => url == cosov), isNotEmpty, reason: 'no node takes more than half');
  });

  group('Resolver with priors', () {
    late ManualClock manual;

    Resolver resolver({NodePriors priors = NodePriors.empty, bool exploreInHurry = true}) => Resolver(
      primary: _primary,
      backups: const [_akamaiURL],
      mode: NodeMode.overseas,
      bans: BanList(),
      clock: manual.clock,
      priors: priors,
      exploreInHurry: exploreInHurry,
    );

    setUp(() => manual = ManualClock(100000));

    test('a prior gives the speed until this session measures it', () {
      final remembered = resolver(priors: _phone);
      final aliov = _on(_aliov);
      expect(remembered.speed(aliov), closeTo(const NodePrior(ttfbMs: 232, bps: 4.4e6).routeBps, 1e-6));
      remembered.success(aliov, bps: 3e6);
      expect(remembered.speed(aliov), 3e6);
      manual.advance(Resolver.measurementTTL + 1);
      expect(remembered.speed(aliov), closeTo(const NodePrior(ttfbMs: 232, bps: 4.4e6).routeBps, 1e-6));
      expect(resolver().speed(aliov), 0, reason: 'no priors: as Swift');
    });

    test('remembered nodes lead the ranges, fastest first', () {
      final remembered = resolver(priors: _phone);
      expect(remembered.rangeCandidates().map(NodeCatalog.nodeKey), [_akamai, _aliov, _cosov, _hk1, _hk3]);
      expect(remembered.rescueCandidates().first, _akamaiURL);
    });

    // The phone's HK nodes, at 0.2 MB/s, got the trial pieces from the end of every range after each 90 s expiry.
    test('nodes remembered as far slower get no pieces outside a hurry', () {
      final remembered = resolver(priors: _phone);
      final urls = remembered.rangeCandidates();
      final primaries = PrimaryAssigner().assign(urls: urls, count: 24, speed: remembered.speed, trialKey: remembered);
      expect(primaries.map(NodeCatalog.nodeKey).toSet(), {_akamai, _aliov});
      final plain = resolver();
      final explored =
          PrimaryAssigner().assign(urls: plain.rangeCandidates(), count: 24, speed: plain.speed, trialKey: plain);
      expect(explored.map(NodeCatalog.nodeKey).toSet(), containsAll([_hk1, _hk3]), reason: 'no priors: as Swift');
    });

    test('with a node remembered, the warm-up does not go wide', () {
      final nodes = [for (var port = 9001; port <= 9008; port++) NodeAddress('127.0.0.1', port: port)];
      Resolver custom(NodePriors priors) => Resolver(
        primary: 'http://127.0.0.1:9001/v.mp4?deadline=1',
        backups: const [],
        mode: CustomNodes(nodes),
        policy: MediaURLPolicy.any,
        bans: BanList(),
        clock: manual.clock,
        priors: priors,
      );
      final plain = custom(NodePriors.empty);
      final remembered = custom(
        NodePriors.fixed({
          '127.0.0.1:9007': const NodePrior(ttfbMs: 20, bps: 9e6),
          '127.0.0.1:9008': const NodePrior(ttfbMs: 20, bps: 8e6),
        }),
      );
      plain.rangeCandidates();
      remembered.rangeCandidates();
      // The second range: the warm-up takes the first six; with priors the remembered two lead and the six places
      // are shared with four explorers.
      expect(
        plain.rangeCandidates().map(NodeCatalog.nodeKey),
        [for (var port = 9001; port <= 9006; port++) '127.0.0.1:$port'],
      );
      final second = remembered.rangeCandidates().map(NodeCatalog.nodeKey).toList();
      expect(second.take(2), ['127.0.0.1:9007', '127.0.0.1:9008']);
      expect(second, hasLength(6));
    });
  });

  // Every first range ran the 64 KiB probe race before other pieces started, because the index fetch never made a
  // node known (phone, Swift).
  test('remembered nodes spare a startup range in a hurry the probe race', () async {
    Future<int> firstRequests(NodePriors priors) async {
      final transport = _Recording(SimCDN(size: 2000000));
      final ctx = TestEngine.context(transport)..nodes.priors = priors;
      final range = ByteRange(1000, 600000);
      final bytes = BytesBuilder(copy: false);
      await RangeDownloader(ctx).stream(
        range,
        TestEngine.resolver(),
        startup: true,
        priority: 50,
        hurry: () => true,
        emit: bytes.add,
      );
      expect(bytes.length, range.length);
      return transport.requests.where((request) => request.range.start == range.start).length;
    }

    expect(await firstRequests(NodePriors.empty), greaterThanOrEqualTo(4), reason: 'the head raced over every node');
    expect(
      await firstRequests(
        NodePriors.fixed({
          TestEngine.cosov: const NodePrior(ttfbMs: 20, bps: 10e6),
          TestEngine.aliov: const NodePrior(ttfbMs: 20, bps: 10e6),
        }),
      ),
      lessThan(4),
      reason: 'the first piece and at most two backup copies (one, unless the machine stalls for 250 ms)',
    );
  });
}
