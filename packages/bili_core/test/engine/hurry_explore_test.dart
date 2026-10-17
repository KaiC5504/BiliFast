import 'dart:typed_data';

import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bili_core/src/engine/ban_list.dart';
import 'package:bili_core/src/engine/hurry_placement.dart';
import 'package:bili_core/src/engine/node_stats.dart';
import 'package:bili_core/src/engine/range_downloader.dart';
import 'package:bili_core/src/engine/resolver.dart';
import 'package:test/test.dart';

import 'support/sim_cdn.dart';

const _piece = 64 * 1024;

String _url(String host, [String query = 'os=cosovbv']) => 'https://$host/upgcxcode/1/2/3/v.m4s?$query';

final _akamai = _url('upos-hz-mirrorakam.akamaized.net', 'os=akam');
final _aliov = _url('upos-sz-mirroraliov.bilivideo.com');
final _cosov = _url('upos-sz-mirrorcosov.bilivideo.com');
final _hk = _url('cn-hk-eq-01-01.bilivideo.com');
final _unknown = _url('cn-hk-eq-01-03.bilivideo.com');

/// One finished transfer: the node is known, with `load` 1.
void _measure(NodeStats stats, String url, {required double ttfbMs, required double bytesPerSecond}) {
  stats
    ..begin(url)
    ..firstByte(url, ms: ttfbMs)
    ..body(url, bytes: 1000000, ms: 1000000 / bytesPerSecond * 1000)
    ..end(url, receiving: true);
}

/// The phone's overseas nodes as the Swift logs measured them (13.9k pieces): first byte p50 and body speed.
NodeStats _phone({bool exploreInHurry = false, bool tailBackups = false}) {
  final stats = NodeStats(exploreInHurry: exploreInHurry, tailBackups: tailBackups);
  _measure(stats, _akamai, ttfbMs: 29, bytesPerSecond: 17.5e6);
  _measure(stats, _aliov, ttfbMs: 232, bytesPerSecond: 4.4e6);
  _measure(stats, _cosov, ttfbMs: 658, bytesPerSecond: 1.5e6);
  _measure(stats, _hk, ttfbMs: 1000, bytesPerSecond: 0.2e6);
  return stats;
}

Map<String, int> _counts(List<String> primaries) {
  final counts = <String, int>{};
  for (final url in primaries) {
    counts[url] = (counts[url] ?? 0) + 1;
  }
  return counts;
}

bool _always(String _) => true;

List<String> _assign(List<String> urls, NodeStats stats, {required int count}) =>
    HurryPlacement.assign(urls: urls, count: count, pieceBytes: _piece, nodes: stats, delivered: _always);

void main() {
  group('no exploring in a hurry', () {
    test('nodes far slower than the best take no piece', () {
      final stats = _phone();
      expect(HurryPlacement.kept([_akamai, _aliov, _cosov, _hk], stats), [_akamai, _aliov]);
      // With three hosts no node takes more than half, so in Swift cosov takes what Akamai may not.
      final urls = [_akamai, _cosov, _hk];
      stats.exploreInHurry = true;
      final halved = _assign(urls, stats, count: 16);
      expect(_counts(halved)[_cosov] ?? 0, greaterThanOrEqualTo(7), reason: 'Swift: ${_counts(halved)}');
      stats.exploreInHurry = false;
      final settled = _assign(urls, stats, count: 16);
      expect(settled, List.filled(16, _akamai));
    });

    test('unknown nodes take no piece once two nodes are known', () {
      final stats = _phone()..exploreInHurry = true;
      final urls = [_akamai, _aliov, _unknown];
      final exploring = _assign(urls, stats, count: 8);
      expect(_counts(exploring)[_unknown] ?? 0, greaterThan(0), reason: 'Swift: a share at twice the best cost');
      stats.exploreInHurry = false;
      final settled = _assign(urls, stats, count: 8);
      expect(_counts(settled)[_unknown] ?? 0, 0, reason: '${_counts(settled)}');
    });

    test('with one node known, unknown nodes keep their share', () {
      final stats = NodeStats(exploreInHurry: false);
      _measure(stats, _aliov, ttfbMs: 40, bytesPerSecond: 4e6);
      final urls = [_aliov, _cosov, _unknown];
      expect(HurryPlacement.kept(urls, stats), urls);
      final primaries = _assign(urls, stats, count: 8);
      expect(_counts(primaries).keys.toSet(), urls.toSet());
      expect(HurryPlacement.kept(urls, NodeStats(exploreInHurry: false)), urls, reason: 'nothing known');
    });

    test('two addresses of one node are one known node', () {
      final stats = NodeStats(exploreInHurry: false);
      final twin = _url('upos-hz-mirrorakam.akamaized.net', 'os=cosovbv');
      _measure(stats, _akamai, ttfbMs: 29, bytesPerSecond: 17.5e6);
      expect(HurryPlacement.kept([_akamai, twin, _unknown], stats), [_akamai, twin, _unknown]);
    });

    test('priors are enough to keep the far slower nodes out', () {
      final stats = NodeStats(
        exploreInHurry: false,
        priors: NodePriors.fixed({
          'upos-hz-mirrorakam.akamaized.net': const NodePrior(ttfbMs: 29, bps: 17.5e6),
          'upos-sz-mirroraliov.bilivideo.com': const NodePrior(ttfbMs: 232, bps: 4.4e6),
          'cn-hk-eq-01-01.bilivideo.com': const NodePrior(ttfbMs: 1000, bps: 0.2e6),
        }),
      );
      final primaries = HurryPlacement.assign(
        urls: [_hk, _unknown, _aliov, _akamai],
        count: 12,
        pieceBytes: _piece,
        nodes: stats,
        delivered: _always,
      );
      expect(primaries.toSet().difference({_akamai, _aliov}), isEmpty);
    });

    test('backup copies go to known nodes first, unknown ones next, far slower ones last', () {
      final stats = _phone(exploreInHurry: true);
      final urls = [_hk, _unknown, _aliov, _akamai];
      // Akamai about 33 ms for 64 KiB; unknown twice that; aliov about 247 ms.
      expect(
        HurryPlacement.byExpectedFinish(urls, pieceBytes: _piece, nodes: stats, delivered: _always),
        [_akamai, _unknown, _aliov, _hk],
        reason: 'Swift',
      );
      stats.exploreInHurry = false;
      expect(
        HurryPlacement.byExpectedFinish(urls, pieceBytes: _piece, nodes: stats, delivered: _always),
        [_akamai, _aliov, _unknown, _hk],
      );
    });

    group('Resolver', () {
      const primary = 'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/v.m4s?deadline=9&os=cosbv';
      late ManualClock manual;

      Resolver resolver({required bool exploreInHurry}) => Resolver(
        primary: primary,
        backups: const [],
        mode: NodeMode.overseas,
        bans: BanList(),
        clock: manual.clock,
        exploreInHurry: exploreInHurry,
      );

      setUp(() => manual = ManualClock(100000));

      test('a range in a hurry goes to the measured nodes only', () {
        for (final exploreInHurry in [true, false]) {
          final r = resolver(exploreInHurry: exploreInHurry);
          final urls = r.urls();
          r
            ..success(urls[0], bps: 4e6)
            ..success(urls[1], bps: 2e6);
          for (var range = 0; range < 4; range++) {
            r.rangeCandidates();
          }
          expect(r.rangeCandidates(), hasLength(4), reason: 'prefetch still explores ($exploreInHurry)');
          expect(
            r.rangeCandidates(hurried: true),
            exploreInHurry ? hasLength(4) : [urls[0], urls[1]],
            reason: 'exploreInHurry: $exploreInHurry',
          );
        }
      });

      test('a range in a hurry with nothing measured goes wide as before', () {
        final r = resolver(exploreInHurry: false);
        expect(r.rangeCandidates(hurried: true), hasLength(4));
        r.success(r.urls()[2], bps: 1e6);
        manual.advance(Resolver.measurementTTL + 1);
        expect(r.rangeCandidates(hurried: true), hasLength(4), reason: 'the measurement went stale');
      });
    });

    // The phone: once Akamai carried half a hurried range, the HK nodes, never measured, cost twice Akamai's time
    // and took the next pieces ahead of aliov at 232 ms to its first byte.
    test('a hurried range keeps off unknown nodes once two are known', () async {
      Future<SimCDN> run({required bool exploreInHurry}) async {
        final cdn = SimCDN(size: 3000000);
        final ctx = TestEngine.context(cdn)..nodes.exploreInHurry = exploreInHurry;
        _measure(ctx.nodes, TestEngine.on(TestEngine.cosov), ttfbMs: 5, bytesPerSecond: 20e6);
        _measure(ctx.nodes, TestEngine.on(TestEngine.aliov), ttfbMs: 100, bytesPerSecond: 20e6);
        final range = ByteRange(1000, 1000000);
        final bytes = BytesBuilder(copy: false);
        await RangeDownloader(ctx).stream(
          range,
          TestEngine.resolver(),
          startup: false,
          priority: 50,
          hurry: () => true,
          emit: bytes.add,
        );
        expect(bytes.length, range.length);
        return cdn;
      }

      final exploring = await run(exploreInHurry: true);
      expect(exploring.requestsTo(TestEngine.hk1) + exploring.requestsTo(TestEngine.hk3), greaterThan(0));
      final settled = await run(exploreInHurry: false);
      expect(settled.requestsTo(TestEngine.hk1) + settled.requestsTo(TestEngine.hk3), 0, reason: '${settled.requests}');
    });
  });

  group('tail backups', () {
    bool due(
      NodeStats stats, {
      required String url,
      required String backup,
      int pieceBytes = _piece,
      double elapsedMs = 0,
      double? receivingMs,
      int receivedBytes = 0,
      int resumedBytes = 0,
    }) => HurryPlacement.tailBackupDue(
      url: url,
      backupURL: backup,
      nodes: stats,
      pieceBytes: pieceBytes,
      elapsedMs: elapsedMs,
      receivingMs: receivingMs,
      receivedBytes: receivedBytes,
      resumedBytes: resumedBytes,
    );

    test('off unless switched on', () {
      expect(due(_phone(), url: _cosov, backup: _akamai, elapsedMs: 100), isFalse);
    });

    // cosov and the HK nodes finished the last piece of 16% of segments, 0.8-1.8 s at p50 (phone, Swift).
    test("a slow node's copy waiting for its first byte is backed up at once", () {
      final stats = _phone(tailBackups: true);
      // cosov: 558 ms more to its usual first byte and 44 ms of body; Akamai about 33 ms.
      expect(due(stats, url: _cosov, backup: _akamai, elapsedMs: 100), isTrue);
      expect(due(stats, url: _hk, backup: _akamai, elapsedMs: 0), isTrue);
      expect(due(stats, url: _akamai, backup: _aliov, elapsedMs: 0), isFalse, reason: 'already the fastest');
    });

    test('a node late past its usual first byte still owes the transfer', () {
      final stats = _phone(tailBackups: true);
      // Akamai's first byte is 29 ms; past it, 3.7 ms of transfer are left against aliov's 247 ms.
      expect(due(stats, url: _akamai, backup: _aliov, elapsedMs: 400), isFalse);
      // A 1 MiB piece on cosov, past its first byte: about 700 ms of body against Akamai's 89 ms.
      expect(due(stats, url: _cosov, backup: _akamai, pieceBytes: 1 << 20, elapsedMs: 2000), isTrue);
    });

    test('a receiving copy is judged by its own rate', () {
      final stats = _phone(tailBackups: true);
      // 16 KiB in a second: three more seconds for the rest.
      expect(
        due(stats, url: _aliov, backup: _akamai, elapsedMs: 1232, receivingMs: 1000, receivedBytes: 16384),
        isTrue,
      );
      // 60 kB in 200 ms: 18 ms left.
      expect(due(stats, url: _aliov, backup: _akamai, elapsedMs: 432, receivingMs: 200, receivedBytes: 60000), isFalse);
      // Too soon to tell from the rate: the node's speed stands in (aliov, 15 ms for 64 KiB).
      expect(due(stats, url: _aliov, backup: _akamai, elapsedMs: 240, receivingMs: 8, receivedBytes: 1000), isFalse);
    });

    test('nearly done is left alone; a backup resumes from what has arrived', () {
      final stats = _phone(tailBackups: true);
      // 900 KiB of 1 MiB on cosov at 1.5 MB/s: 83 ms left, against Akamai's 36 ms for the rest.
      expect(
        due(
          stats,
          url: _cosov,
          backup: _akamai,
          pieceBytes: 1 << 20,
          elapsedMs: 1300,
          receivingMs: 614,
          receivedBytes: 900 * 1024,
        ),
        isFalse,
      );
      // The same prefix resumed into a crawling copy: 124 KiB at 20 KB/s.
      expect(
        due(
          stats,
          url: _cosov,
          backup: _akamai,
          pieceBytes: 1 << 20,
          elapsedMs: 2000,
          receivingMs: 1000,
          receivedBytes: 20000,
          resumedBytes: 880 * 1024,
        ),
        isTrue,
      );
    });

    test('no backup to the same node, an unknown node, or for an unknown node', () {
      final stats = _phone(tailBackups: true);
      final twin = _url('upos-sz-mirrorcosov.bilivideo.com', 'os=akam');
      expect(due(stats, url: _cosov, backup: twin, elapsedMs: 100), isFalse);
      expect(due(stats, url: _cosov, backup: _unknown, elapsedMs: 100), isFalse);
      expect(due(stats, url: _unknown, backup: _akamai, elapsedMs: 100), isFalse);
      expect(
        due(stats, url: _cosov, backup: _akamai, receivingMs: 50, receivedBytes: _piece),
        isFalse,
        reason: 'all in',
      );
    });
  });
}
