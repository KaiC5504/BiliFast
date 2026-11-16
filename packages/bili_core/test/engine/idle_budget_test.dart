import 'dart:typed_data';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:test/test.dart';

import 'support/sim_cdn.dart';

const _headerEnd = 1023;
const _segment = 262144;
const _count = 30;
const _size = _headerEnd + 1 + _count * _segment;

/// Thirty 2-second segments of 256 KiB after a 1 KiB header.
final _segments = [
  for (var index = 0; index < _count; index++)
    MediaSegment(
      index: index,
      range: ByteRange(_headerEnd + 1 + index * _segment, _headerEnd + (index + 1) * _segment),
      startTime: index * 2.0,
      duration: 2,
    ),
];

final _config = TestEngine.config.copyWith(keepBehindSeconds: 30, keepBehindBytes: 8 << 20);

RipperSession _session(RangeTransport transport, {RipperConfig? config, Logger? logger, bool warm = false}) =>
    RipperSession(
      sources: {TrackKind.video: (primary: TestEngine.primary, backups: const <String>[])},
      mode: CustomNodes([NodeAddress('upos-sz-mirrorcos.bilivideo.com')]),
      config: config ?? _config,
      transport: transport,
      logger: logger ?? Logger(session: 'test'),
      warm: warm,
    )..setSegments(TrackKind.video, _segments);

Future<void> _read(RipperSession session, int index) async {
  final builder = BytesBuilder(copy: false);
  await session.read(TrackKind.video, _segments[index].range).forEach(builder.add);
}

Future<void> _settle(RipperSession session) async {
  expect(await eventually(() => session.prefetchesRunning(TrackKind.video) == 0), isTrue);
}

List<int> _cached(RipperSession session) => [
  for (final segment in _segments)
    if (session.isCached(TrackKind.video, segment.range)) segment.index,
];

List<int> _range(int first, int last) => [for (var index = first; index <= last; index++) index];

/// Records the segment of every request.
final class _Recording implements RangeTransport {
  _Recording(this.cdn);

  final SimCDN cdn;
  final segments = <int>{};

  @override
  int? get connectionsPerHost => cdn.connectionsPerHost;

  @override
  String get name => 'recording';

  @override
  void close() {}

  @override
  Future<TransportResponse> fetch(Uri url, ByteRange range, {CancelToken? cancel}) {
    if (range.start > _headerEnd) segments.add((range.start - _headerEnd - 1) ~/ _segment);
    return cdn.fetch(url, range, cancel: cancel);
  }
}

void main() {
  group('an idle session', () {
    test('trims to 5 s behind and 10 s ahead of the playhead at once', () async {
      final sink = MemorySink();
      final logger = Logger(session: 'test')..add(sink);
      final session = _session(SimCDN(size: _size), config: _config.copyWith(prefetchVideoBytes: 0), logger: logger);
      addTearDown(session.close);
      for (var index = 0; index < 15; index++) {
        session.updatePlayhead(seconds: index * 2.0, rate: 1);
        await _read(session, index);
      }
      session.updatePlayhead(seconds: 20, rate: 1);
      expect(_cached(session), _range(0, 14));

      session.setIdle(true);
      expect(session.idle, isTrue);
      expect(_cached(session), _range(7, 14), reason: 'segments ending before 15 s go; 7-14 end at 16 s or later');
      expect(session.heldBytes, 8 * _segment);
      expect(sink.events.where((event) => event.msg == 'idle trimmed'), hasLength(1));
    });

    test('schedules no prefetch starting beyond 10 s ahead', () async {
      final session = _session(SimCDN(size: _size))..setIdle(true);
      addTearDown(session.close);
      await _read(session, 0);
      expect(session.prefetchedBytes(TrackKind.video), 5 * _segment, reason: 'segments 1-5 start within 10 s');
      await _settle(session);
      expect(_cached(session), _range(0, 5));
    });

    test('a read while idle refills only up to the window', () async {
      final cdn = _Recording(SimCDN(size: _size));
      final session = _session(cdn);
      addTearDown(session.close);
      await _read(session, 0);
      await _settle(session);
      expect(_cached(session), _range(0, 22), reason: 'in use, prefetch reaches 45 s');

      session
        ..setIdle(true)
        ..dropPrefetch();
      cdn.segments.clear();
      await _read(session, 0);
      await _settle(session);
      expect(_cached(session), _range(0, 5));
      expect(cdn.segments, _range(0, 5).toSet(), reason: 'nothing past 10 s is fetched again');

      session.updatePlayhead(seconds: 8, rate: 1);
      await _read(session, 4);
      await _settle(session);
      expect(_cached(session), _range(1, 9), reason: 'the window moves with the playhead: 3 s to 18 s');
      expect(cdn.segments.reduce((a, b) => a > b ? a : b), 9);
    });

    test('back in use, the next read prefetches as far as before', () async {
      final session = _session(SimCDN(size: _size))..setIdle(true);
      addTearDown(session.close);
      await _read(session, 0);
      await _settle(session);
      session.setIdle(false);
      expect(session.idle, isFalse);
      await _read(session, 1);
      expect(session.prefetchedBytes(TrackKind.video), 21 * _segment, reason: 'segments 2-22 start within 45 s');
    });
  });

  group('EngineBudget', () {
    test('sheds idle sessions least recently played first and leaves the rest', () async {
      final sink = MemorySink();
      final budget = EngineBudget(bytes: 13 * _segment, logger: Logger(session: 'test')..add(sink));
      final older = _session(SimCDN(size: _size));
      final newer = _session(SimCDN(size: _size));
      final playing = _session(SimCDN(size: _size), config: _config.copyWith(prefetchVideoBytes: 2 * _segment));
      addTearDown(older.close);
      addTearDown(newer.close);
      addTearDown(playing.close);
      for (final session in [older, newer, playing]) {
        await _read(session, 0);
        await _settle(session);
      }
      older.setIdle(true);
      newer.setIdle(true);
      expect([older.heldBytes, newer.heldBytes, playing.heldBytes], [6 * _segment, 6 * _segment, 3 * _segment]);

      expect(budget.check([newer, playing, older]), 6 * _segment);
      expect(older.heldBytes, 0, reason: 'idle the longest, it goes whole');
      expect(newer.heldBytes, 6 * _segment, reason: 'under three quarters of the budget once the older one is gone');
      expect(playing.heldBytes, 3 * _segment);
      expect(sink.events.where((event) => event.msg == 'engine budget shed'), hasLength(1));
    });

    test('never touches a playing session\'s prefetch, and logs one line while it stays over', () async {
      final sink = MemorySink();
      final budget = EngineBudget(bytes: 8 * _segment, logger: Logger(session: 'test')..add(sink));
      final session = _session(SimCDN(size: _size));
      addTearDown(session.close);
      for (var index = 0; index < 10; index++) {
        session.updatePlayhead(seconds: index * 2.0, rate: 1);
        await _read(session, index);
      }
      session.updatePlayhead(seconds: 18, rate: 1);
      await _settle(session);
      expect(_cached(session), _range(0, 29));
      final prefetched = session.prefetchedBytes(TrackKind.video);
      expect(prefetched, 20 * _segment, reason: 'segments 10-29 are prefetch');

      expect(budget.check([session]), 6 * _segment);
      expect(_cached(session), _range(6, 29), reason: 'read segments ending before 13 s go');
      expect(session.prefetchedBytes(TrackKind.video), prefetched);

      session.updatePlayhead(seconds: 26, rate: 1);
      expect(budget.check([session]), 4 * _segment, reason: 'segments 6-9 are now outside the window');
      expect(session.prefetchedBytes(TrackKind.video), prefetched);
      expect(budget.check([session]), 0);

      final lines = sink.events.where((event) => event.msg == 'engine budget shed').toList();
      expect(lines, hasLength(1));
      expect(lines.single.f['beforeBytes'], LogInt(30 * _segment));
      expect(lines.single.f['afterBytes'], LogInt(24 * _segment));
      expect(lines.single.f['sessions'], const LogInt(1));
    });

    test('under the budget it sheds nothing, and a later shed logs again', () async {
      final sink = MemorySink();
      final budget = EngineBudget(bytes: 8 * _segment, logger: Logger(session: 'test')..add(sink));
      final idle = _session(SimCDN(size: _size));
      addTearDown(idle.close);
      await _read(idle, 0);
      await _settle(idle);
      idle.setIdle(true);
      expect(budget.check([idle]), 0);
      expect(idle.heldBytes, 6 * _segment);

      final other = _session(SimCDN(size: _size));
      addTearDown(other.close);
      await _read(other, 0);
      await _settle(other);
      other.setIdle(true);
      expect(budget.check([idle, other]), 6 * _segment);
      expect(idle.heldBytes, 0);
      expect(budget.check([idle, other]), 0);

      final third = _session(SimCDN(size: _size));
      addTearDown(third.close);
      await _read(third, 0);
      await _settle(third);
      third.setIdle(true);
      expect(budget.check([idle, other, third]), 6 * _segment);
      expect(other.heldBytes, 0);
      expect(sink.events.where((event) => event.msg == 'engine budget shed'), hasLength(2));
    });

    test("a warm session's unread prime counts as in use and stays; an idle session over the budget goes whole",
        () async {
      // Under one segment, so the budget stays over even once the idle session is gone.
      final budget = EngineBudget(bytes: _segment ~/ 2, logger: Logger(session: 'test'));
      final warm = _session(SimCDN(size: _size), warm: true);
      addTearDown(warm.close);
      warm.prime(TrackKind.video, seconds: 0);
      expect(await eventually(() => warm.isCached(TrackKind.video, _segments[0].range)), isTrue);
      await _settle(warm);

      final idle = _session(SimCDN(size: _size));
      addTearDown(idle.close);
      await _read(idle, 0);
      await _settle(idle);
      idle.setIdle(true);
      expect([warm.heldBytes, idle.heldBytes], [_segment, 6 * _segment]);
      expect(warm.lastPlayed, lessThan(idle.lastPlayed), reason: 'the warm one would go first if it counted as idle');

      expect(budget.check([warm, idle]), 6 * _segment);
      expect(idle.heldBytes, 0);
      expect(warm.idle, isFalse);
      expect(warm.heldBytes, _segment, reason: 'the prime the player has not read yet stays');
      expect(warm.isCached(TrackKind.video, _segments[0].range), isTrue);
    });
  });
}
