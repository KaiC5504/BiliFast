import 'dart:typed_data';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bili_core/src/engine/hurry_placement.dart';
import 'package:bili_core/src/engine/node_stats.dart';
import 'package:test/test.dart';

import 'support/sim_cdn.dart';

String _url(String host, [String query = 'os=cosovbv']) => 'https://$host/upgcxcode/1/2/3/v.m4s?$query';

final _akamai = _url('upos-hz-mirrorakam.akamaized.net', 'os=akam');
final _aliov = _url(TestEngine.aliov);
final _cosov = _url(TestEngine.cosov);
final _hk = _url(TestEngine.hk1);

/// One finished transfer of [bytes].
void _measure(NodeStats stats, String url, {required double ttfbMs, required double bytesPerSecond, int? bytes}) {
  final size = bytes ?? 1000000;
  stats
    ..begin(url)
    ..firstByte(url, ms: ttfbMs)
    ..body(url, bytes: size, ms: size / bytesPerSecond * 1000)
    ..end(url, receiving: true);
}

/// The phone as 1.0.0 (1) saw it: cosov's whole piece arrives at once after its first byte, so by body speed it
/// is the fastest node.
NodeStats _phone({required bool keepsOffSlow}) {
  final stats = NodeStats(connectionsPerHost: 8, exploreInHurry: false, keepsOffSlow: keepsOffSlow);
  _measure(stats, _akamai, ttfbMs: 21, bytesPerSecond: 16e6);
  _measure(stats, _aliov, ttfbMs: 219, bytesPerSecond: 2.9e6);
  _measure(stats, _cosov, ttfbMs: 1245, bytesPerSecond: 20e6);
  _measure(stats, _hk, ttfbMs: 360, bytesPerSecond: 0.15e6);
  return stats;
}

const _size = 4 * 1024 * 1024;
const _headerEnd = 1023;
const _segment = 262144;

/// Twelve 2-second segments of 256 KiB after a 1 KiB header.
final _segments = [
  for (var index = 0; index < 12; index++)
    MediaSegment(
      index: index,
      range: ByteRange(_headerEnd + 1 + index * _segment, _headerEnd + (index + 1) * _segment),
      startTime: index * 2.0,
      duration: 2,
    ),
];

RipperSession _session(RangeTransport transport, RipperConfig config, {Logger? logger}) => RipperSession(
  sources: {TrackKind.video: (primary: TestEngine.primary, backups: const <String>[])},
  mode: CustomNodes([NodeAddress('upos-sz-mirrorcos.bilivideo.com')]),
  config: config,
  transport: transport,
  logger: logger ?? Logger(session: 'test'),
)..setSegments(TrackKind.video, _segments);

Future<Uint8List> _read(RipperSession session, ByteRange range) async {
  final builder = BytesBuilder(copy: false);
  await session.read(TrackKind.video, range).forEach(builder.add);
  return builder.takeBytes();
}

Uint8List _bytes(SimCDN cdn, ByteRange range) => Uint8List.sublistView(cdn.content, range.start, range.end + 1);

void main() {
  group('hurryKeepsOffSlow', () {
    test('slow nodes are judged by the time a piece takes, first byte included', () {
      expect(
        HurryPlacement.kept([_akamai, _aliov, _cosov, _hk], _phone(keepsOffSlow: false)),
        contains(_cosov),
        reason: 'by body speed alone cosov is the fastest',
      );
      expect(HurryPlacement.kept([_akamai, _aliov, _cosov, _hk], _phone(keepsOffSlow: true)), [_akamai, _aliov]);
    });

    test('with Akamai full, the overflow goes to aliov rather than past it to cosov', () {
      List<String> overflow({required bool keepsOffSlow}) {
        final stats = _phone(keepsOffSlow: keepsOffSlow)..exploreInHurry = true;
        for (var index = 0; index < 8; index++) {
          stats.begin(_akamai);
        }
        return HurryPlacement.assign(
          urls: [_akamai, _aliov, _cosov],
          count: 24,
          pieceBytes: 64 * 1024,
          nodes: stats,
          delivered: (_) => true,
        );
      }

      expect(overflow(keepsOffSlow: false), contains(_cosov), reason: 'no node may carry more than half');
      expect(overflow(keepsOffSlow: true), isNot(contains(_cosov)));
    });

    test('a node not measured yet keeps its share until two nodes are known', () {
      final stats = NodeStats(exploreInHurry: false, keepsOffSlow: true);
      _measure(stats, _akamai, ttfbMs: 21, bytesPerSecond: 16e6);
      expect(HurryPlacement.kept([_akamai, _aliov, _cosov], stats), [_akamai, _aliov, _cosov]);
    });
  });

  group('medianEstimates', () {
    test('a fifth of cache misses do not move the first byte estimate', () {
      for (final median in [false, true]) {
        final stats = NodeStats(median: median);
        for (final ms in <double>[20, 22, 450, 19, 21, 20, 480, 23, 20, 21]) {
          stats
            ..begin(_akamai)
            ..firstByte(_akamai, ms: ms)
            ..end(_akamai, receiving: true);
        }
        if (median) {
          expect(stats.ttfbMs(_akamai), 21);
        } else {
          expect(stats.ttfbMs(_akamai), greaterThan(60), reason: 'the even average still carries the last miss');
        }
      }
    });

    test('one burst does not make a node that waits a second look fast', () {
      final stats = NodeStats(median: true);
      for (var index = 0; index < 4; index++) {
        _measure(stats, _cosov, ttfbMs: 1200, bytesPerSecond: 0.2e6, bytes: 64 * 1024);
      }
      _measure(stats, _cosov, ttfbMs: 1200, bytesPerSecond: 50e6, bytes: 64 * 1024);
      expect(stats.bps(_cosov), lessThan(1e6));
    });
  });

  group('seekHurriesPrefetch', () {
    // One node sending 256 KiB a second per request: after the first read the prefetch of the next segments is
    // still running when the seek lands on one of them.
    Future<(Uint8List, List<LogEvent>)> seekOntoPrefetch({required bool on}) async {
      final cdn = SimCDN(
        size: _size,
        behaviors: {'upos-sz-mirrorcos.bilivideo.com': NodeBehavior(bytesPerSecond: _segment.toDouble())},
      );
      final logs = MemorySink();
      final session = _session(
        cdn,
        TestEngine.slowConfig.copyWith(seekHurriesPrefetch: on, streamAdopted: true),
        logger: Logger(session: 'test')..add(logs),
      );
      addTearDown(session.close);
      await _read(session, _segments[0].range);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(session.prefetchedBytes(TrackKind.video), greaterThan(0));
      session.updatePlayhead(seconds: _segments[3].startTime, rate: 1);
      final bytes = await _read(session, _segments[3].range);
      expect(bytes, _bytes(cdn, _segments[3].range));
      return (bytes, logs.events.toList());
    }

    test('a seek onto a running prefetch keeps its bytes and fetches the rest as a seek', () async {
      final (_, before) = await seekOntoPrefetch(on: false);
      expect(before.where((event) => event.msg == 'seek hurried prefetch'), isEmpty);
      final (_, after) = await seekOntoPrefetch(on: true);
      final hurried = after.where((event) => event.msg == 'seek hurried prefetch').toList();
      expect(hurried, hasLength(1));
      expect((hurried.single.f['segment']! as LogInt).value, 3);
    });
  });

  group('trimOnMemoryWarning', () {
    Future<RipperSession> readSix(SimCDN cdn, {required bool trim}) async {
      final session = _session(
        cdn,
        TestEngine.config.copyWith(
          keepBehindSeconds: 30,
          keepBehindBytes: 8 << 20,
          prefetchVideoBytes: 0,
          trimOnMemoryWarning: trim,
        ),
      );
      for (var index = 0; index < 6; index++) {
        session.updatePlayhead(seconds: index * 2.0, rate: 1);
        await _read(session, _segments[index].range);
      }
      session.updatePlayhead(seconds: 14, rate: 1);
      return session;
    }

    test('a memory warning keeps what is near the playhead', () async {
      final trimmed = await readSix(SimCDN(size: _size), trim: true);
      addTearDown(trimmed.close);
      trimmed.dropCache();
      expect(
        [for (final segment in _segments.take(6)) trimmed.isCached(TrackKind.video, segment.range)],
        [false, true, true, true, true, true],
        reason: 'only the segment that ended over 10 s behind goes',
      );

      final cleared = await readSix(SimCDN(size: _size), trim: false);
      addTearDown(cleared.close);
      cleared.dropCache();
      expect([
        for (final segment in _segments.take(6)) cleared.isCached(TrackKind.video, segment.range),
      ], List.filled(6, false));
    });
  });
}
