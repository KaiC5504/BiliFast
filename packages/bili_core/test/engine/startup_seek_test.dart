// BiliFast's own startup and seek speed-ups (the RipperConfig knobs after hurryAheadSeconds); not in Swift.

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bili_core/src/engine/attempt.dart';
import 'package:bili_core/src/engine/connection_pool.dart';
import 'package:test/test.dart';

import 'support/sim_cdn.dart';

const _size = 4 * 1024 * 1024;
const _headerEnd = 1023;
const _segment = 262144;
const _audioPrimary = 'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/a.m4s?deadline=9&os=cosbv';
const _single = 'upos-sz-mirrorcos.bilivideo.com';

/// Twelve 2-second segments of 256 KiB after a 1 KiB header.
List<MediaSegment> _segments() => [
      for (var index = 0; index < 12; index++)
        MediaSegment(
          index: index,
          range: ByteRange(_headerEnd + 1 + index * _segment, _headerEnd + (index + 1) * _segment),
          startTime: index * 2.0,
          duration: 2,
        ),
    ];

/// The two tracks ask for different files, so a recording can tell them apart.
RipperSession _session(
  RangeTransport transport, {
  RipperConfig config = TestEngine.config,
  List<TrackKind> tracks = const [TrackKind.video],
  NodeMode mode = NodeMode.overseas,
  Logger? logger,
}) {
  final session = RipperSession(
    sources: {
      for (final track in tracks)
        track: (primary: track == TrackKind.video ? TestEngine.primary : _audioPrimary, backups: const <String>[]),
    },
    mode: mode,
    config: config,
    transport: transport,
    logger: logger ?? Logger(session: 'test'),
  );
  for (final track in tracks) {
    session.setSegments(track, _segments());
  }
  return session;
}

/// One node, so every byte is asked for once: no races, no backup copies.
final _oneNode = CustomNodes([NodeAddress(_single)]);

typedef _Timed = ({Uint8List bytes, int firstMs, int headMs, int doneMs});

/// Reads [range], timing its first chunk, its first 512 KiB and its end from the call.
Future<_Timed> _timedRead(RipperSession session, ByteRange range, [TrackKind track = TrackKind.video]) async {
  final clock = Stopwatch()..start();
  final builder = BytesBuilder(copy: false);
  int? first;
  int? head;
  await for (final chunk in session.read(track, range)) {
    first ??= clock.elapsedMilliseconds;
    builder.add(chunk);
    if (head == null && builder.length >= min(range.length, 512 * 1024)) head = clock.elapsedMilliseconds;
  }
  final done = clock.elapsedMilliseconds;
  return (bytes: builder.takeBytes(), firstMs: first ?? done, headMs: head ?? done, doneMs: done);
}

Future<Uint8List> _read(RipperSession session, ByteRange range, [TrackKind track = TrackKind.video]) async =>
    (await _timedRead(session, range, track)).bytes;

Uint8List _bytes(SimCDN cdn, ByteRange range) => Uint8List.sublistView(cdn.content, range.start, range.end + 1);

Future<void> _until(bool Function() condition, {double seconds = 10}) async {
  expect(await eventually(condition, seconds: seconds), isTrue, reason: 'timed out waiting');
}

Future<void> _sleep(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

/// Records every request; can hold requests (all, or from an offset on) and refuse the held ones it doomed.
final class _Recorder implements RangeTransport {
  _Recorder(this.cdn);

  final SimCDN cdn;
  final requests = <({String url, ByteRange range})>[];
  bool open = true;
  int? holdFrom;

  /// Requests from this offset on that arrive while [dooming] get a 403 once they are let through.
  int? doomFrom;
  bool dooming = false;

  @override
  int? get connectionsPerHost => cdn.connectionsPerHost;

  @override
  String get name => 'recorder';

  @override
  void close() {}

  @override
  Future<TransportResponse> fetch(Uri url, ByteRange range, {CancelToken? cancel}) async {
    requests.add((url: '$url', range: range));
    final doomed = dooming && range.start >= (doomFrom ?? 1 << 62);
    while (!open || range.start >= (holdFrom ?? 1 << 62)) {
      await cancellableSleep(5, cancel);
    }
    if (doomed) return TransportResponse(status: 403, headers: const {}, body: const Stream.empty());
    return cdn.fetch(url, range, cancel: cancel);
  }

  /// Bytes of [segment] asked for on the [path] file (`v.m4s` or `a.m4s`), over all requests.
  int requestedBytes(ByteRange segment, {String path = '/v.m4s'}) {
    var sum = 0;
    for (final request in requests) {
      if (!Uri.parse(request.url).path.endsWith(path)) continue;
      final overlap = min(request.range.end, segment.end) - max<int>(request.range.start, segment.start) + 1;
      if (overlap > 0) sum += overlap;
    }
    return sum;
  }
}

void main() {
  final all = _segments();

  group('prime', () {
    test('a primed segment downloads before the player asks, and the read takes it over', () async {
      // Every request waits 80 ms for its first byte, as a CDN does across the sea.
      final primedCdn = _Recorder(SimCDN(size: _size, behaviors: {_single: const NodeBehavior(firstByteMs: 80)}));
      final plainCdn = SimCDN(size: _size, behaviors: {_single: const NodeBehavior(firstByteMs: 80)});
      final primed = _session(primedCdn, config: TestEngine.slowConfig, mode: _oneNode);
      final plain = _session(plainCdn, config: TestEngine.slowConfig, mode: _oneNode);
      addTearDown(primed.close);
      addTearDown(plain.close);

      primed.prime(TrackKind.video, seconds: 0.5);
      expect(primed.priming(TrackKind.video, all[0].range), isTrue);
      expect(primed.mediaRequestCount, 0, reason: 'a prime is not a player request');
      expect(primed.seekCount, 0);
      // The player's first request comes a while after the headers (0.48 s on the phone).
      await _sleep(200);
      final fromPrime = await _timedRead(primed, all[0].range);
      final cold = await _timedRead(plain, all[0].range);

      expect(fromPrime.bytes, _bytes(primedCdn.cdn, all[0].range));
      expect(cold.bytes, _bytes(plainCdn, all[0].range));
      expect(cold.firstMs, greaterThanOrEqualTo(80));
      expect(fromPrime.firstMs, lessThan(cold.firstMs), reason: 'the primed read starts with bytes already in');
      expect(primedCdn.requestedBytes(all[0].range), _segment, reason: 'downloaded once, by the prime');
      expect(primed.stats().cacheHits, 1);
    });

    test('a first read elsewhere leaves the prime running, and its read still takes it over', () async {
      final cdn = _Recorder(SimCDN(size: _size));
      final session = _session(cdn, config: TestEngine.config.copyWith(prefetchVideoBytes: 0), mode: _oneNode);
      addTearDown(session.close);
      cdn.holdFrom = all[5].range.start;
      session.prime(TrackKind.video, seconds: all[5].startTime);
      // AVPlayer can ask for the first segment before its start seek lands.
      await _read(session, all[0].range);
      expect(session.priming(TrackKind.video, all[5].range), isTrue, reason: 'not dropped as a seek would drop it');
      cdn.holdFrom = null;
      expect(await _read(session, all[5].range), _bytes(cdn.cdn, all[5].range));
      expect(cdn.requestedBytes(all[5].range), _segment);
    });

    test('prefetchOnPrime prefetches the following segments at once', () {
      for (final on in [false, true]) {
        final cdn = _Recorder(SimCDN(size: _size))..open = false;
        final config = TestEngine.config.copyWith(prefetchVideoBytes: 3 * _segment, prefetchOnPrime: on);
        final session = _session(cdn, config: config);
        session.prime(TrackKind.video, seconds: 0);
        // The prime counts against the cap: two more fit.
        expect(session.prefetchesRunning(TrackKind.video), on ? 3 : 1);
        session.close();
      }
    });

    test('with seekBurst the prefetch after a prime waits until its head is in', () async {
      final cdn = _Recorder(SimCDN(size: _size))..open = false;
      final config =
          TestEngine.config.copyWith(prefetchVideoBytes: 3 * _segment, prefetchOnPrime: true, seekBurst: true);
      final session = _session(cdn, config: config);
      addTearDown(session.close);
      session.prime(TrackKind.video, seconds: 0);
      expect(session.prefetchesRunning(TrackKind.video), 1);
      await _sleep(50);
      expect(session.prefetchesRunning(TrackKind.video), 1, reason: 'held while the head is on its way');
      cdn.open = true;
      await _until(() => session.isCached(TrackKind.video, all[2].range));
      expect(session.isCached(TrackKind.video, all[1].range), isTrue);
    });

    test('a prime and the read that takes it over are logged with their timings', () async {
      final memory = MemorySink();
      final logger = Logger(session: 'test')..add(memory);
      final session = _session(SimCDN(size: _size), logger: logger);
      addTearDown(session.close);
      session.prime(TrackKind.video, seconds: 0);
      await _read(session, all[0].range);
      await _until(() => memory.events.any((event) => event.msg == 'prime'));
      final prime = memory.events.singleWhere((event) => event.msg == 'prime');
      expect(prime.level, LogLevel.info);
      expect(prime.f['outcome'], const LogString('done'));
      expect(prime.f['segment'], const LogInt(0));
      expect(prime.f.keys, containsAll(['firstByteMs', 'ms', 'bytes', 'adopted', 'track']));
      final read = memory.events.singleWhere((event) => event.msg == 'seek read');
      expect(read.level, LogLevel.info);
      expect(read.f['source'], anyOf(const LogString('prime'), const LogString('memory')));
      expect(read.f.keys, containsAll(['firstByteMs', 'ms', 'segment', 'first']));
    });
  });

  group('seek burst', () {
    // hk1 is by far the fastest node until the seek lands on a part of the file it has not served lately. The others
    // are slow enough that the gap shows through Windows' coarse timers.
    const megabyte = 1024 * 1024;
    final big = [
      for (var index = 0; index < 10; index++)
        MediaSegment(
          index: index,
          range: ByteRange(index * megabyte, (index + 1) * megabyte - 1),
          startTime: index * 2.0,
          duration: 2,
        ),
    ];

    Future<(_Timed, _Recorder)> coldSeek({required bool burst}) async {
      final cdn = _Recorder(SimCDN(size: 10 * megabyte, behaviors: {
        TestEngine.hk1: NodeBehavior(
          firstByteMs: 1,
          bytesPerSecond: 200e6,
          coldRange: big[8].range,
          coldRangeFirstByteMs: 1500,
        ),
        TestEngine.cosov: const NodeBehavior(firstByteMs: 40, bytesPerSecond: 2e6),
        TestEngine.aliov: const NodeBehavior(firstByteMs: 40, bytesPerSecond: 2e6),
        TestEngine.hk3: const NodeBehavior(firstByteMs: 40, bytesPerSecond: 2e6),
      }));
      final config = TestEngine.config
          .copyWith(firstByteTimeoutMs: 3000, stallTimeoutMs: 2000, prefetchVideoBytes: 0, seekBurst: burst);
      final session = RipperSession(
        sources: {TrackKind.video: (primary: TestEngine.primary, backups: const [])},
        mode: NodeMode.overseas,
        config: config,
        transport: cdn,
        logger: Logger(session: 'test'),
      )..setSegments(TrackKind.video, big);
      addTearDown(session.close);
      await _read(session, big[0].range);
      await _read(session, big[1].range);
      final before = cdn.requests.length;
      final seek = await _timedRead(session, big[8].range);
      expect(seek.bytes, _bytes(cdn.cdn, big[8].range));
      cdn.requests.removeRange(0, before);
      return (seek, cdn);
    }

    test('a cold seek races its head on several nodes at once instead of waiting for a second copy', () async {
      final (plain, _) = await coldSeek(burst: false);
      final (burst, cdn) = await coldSeek(burst: true);
      // Without the burst the first piece waits on hk1 until its second copy goes out 250 ms later.
      expect(plain.firstMs, greaterThanOrEqualTo(240));
      expect(burst.firstMs, lessThan(plain.firstMs - 150));
      expect(burst.headMs, lessThan(plain.headMs));
      final head = cdn.requests.where((request) => request.range.start < big[8].range.start + 512 * 1024).toList();
      expect(head.every((request) => request.range.length <= 64 * 1024), isTrue, reason: 'the head is 64 KiB pieces');
      final firstPiece = head.where((request) => request.range.start == big[8].range.start);
      expect(firstPiece.map((request) => NodeCatalog.nodeKey(request.url)).toSet().length, greaterThanOrEqualTo(3),
          reason: 'the first piece went to three nodes together');
    });

    test('prefetch scheduled while a seek head is on its way waits for it', () async {
      for (final burst in [false, true]) {
        final cdn = _Recorder(SimCDN(size: _size));
        final config = TestEngine.config
            .copyWith(prefetchVideoBytes: 2 * _segment, prefetchAudioBytes: 2 * _segment, seekBurst: burst);
        final session = _session(cdn, config: config, tracks: const [TrackKind.video, TrackKind.audio]);
        cdn.holdFrom = all[9].range.start;
        final seek = _read(session, all[9].range);
        await _until(() => session.mediaRequestCount == 1);
        await _read(session, all[0].range, TrackKind.audio);
        expect(session.prefetchesRunning(TrackKind.audio), burst ? 0 : greaterThan(0),
            reason: burst ? 'held behind the video head' : 'Swift prefetches at once');
        cdn.holdFrom = null;
        await seek;
        await _until(() => session.isCached(TrackKind.audio, all[1].range));
        session.close();
      }
    });
  });

  group('audio first', () {
    EngineContext context({bool audioFirst = true, int limit = 8}) => EngineContext(
          transport: SimCDN(size: 1),
          pool: ConnectionPool(limit),
          config: TestEngine.config.copyWith(audioFirst: audioFirst),
          logger: Logger(session: 'test'),
        );
    const video = RequestLane(track: TrackKind.video);
    const audio = RequestLane(track: TrackKind.audio, boost: 100, minClass: QueueClass.startup);

    test('while an audio read waits, video leaves two connections free for it', () async {
      final ctx = context();
      ctx.audioReadBegan();
      final videos = [
        for (var index = 0; index < 6; index++)
          await ctx.acquire(priority: 50, queueClass: QueueClass.startup, lane: video),
      ];
      Permit? seventh;
      final waiting = ctx.acquire(priority: 50, queueClass: QueueClass.startup, lane: video).then((p) => seventh = p);
      await pumpEventQueue();
      expect(seventh, isNull);
      expect(ctx.pool.active, 6);
      expect(ctx.videoGated, 1);
      final audios = [
        for (var index = 0; index < 2; index++)
          await ctx.acquire(priority: 50, queueClass: QueueClass.ordinary, lane: audio),
      ];
      expect(ctx.pool.active, 8);
      for (final permit in audios) {
        permit.release();
        ctx.released(audio);
      }
      ctx.audioReadEnded();
      await waiting;
      expect(seventh, isNotNull, reason: 'with no audio read waiting video takes every connection');
      expect(ctx.videoInPool, 7);
      for (final permit in [...videos, seventh!]) {
        permit.release();
        ctx.released(video);
      }
      expect(ctx.videoInPool, 0);
    });

    test('without audioFirst nothing is kept back', () async {
      final ctx = context(audioFirst: false);
      ctx.audioReadBegan();
      for (var index = 0; index < 8; index++) {
        await ctx.acquire(priority: 50, queueClass: QueueClass.startup, lane: video);
      }
      expect(ctx.pool.active, 8);
      expect(ctx.videoGated, 0);
    });

    test('a video request cancelled at the gate leaves it', () async {
      final ctx = context(limit: 3);
      ctx.audioReadBegan();
      await ctx.acquire(priority: 50, queueClass: QueueClass.startup, lane: video);
      final cancel = CancelToken();
      final gated = ctx.acquire(priority: 50, queueClass: QueueClass.startup, lane: video, cancel: cancel);
      await pumpEventQueue();
      expect(ctx.videoGated, 1);
      cancel.cancel();
      await expectLater(gated, throwsA(isA<CancelledException>()));
      expect(ctx.videoGated, 0);
      expect(ctx.videoInPool, 1);
    });

    test('an audio request goes before the video requests waiting in its class', () async {
      final ctx = context(limit: 1);
      final held = await ctx.acquire(priority: 50, queueClass: QueueClass.startup, lane: video);
      final order = <String>[];
      final videoWait = ctx.acquire(priority: 120, queueClass: QueueClass.startup, lane: video).then((permit) {
        order.add('video');
        return permit;
      });
      // An ordinary audio read climbs into the startup class with its boost.
      final audioWait = ctx.acquire(priority: 50, queueClass: QueueClass.ordinary, lane: audio).then((permit) {
        order.add('audio');
        return permit;
      });
      await pumpEventQueue();
      held.release();
      ctx.released(video);
      final first = await audioWait;
      expect(order, ['audio']);
      first.release();
      ctx.released(audio);
      (await videoWait).release();
      expect(order, ['audio', 'video']);
    });

    test('a small audio read is one piece raced over two nodes at once', () async {
      for (final on in [false, true]) {
        final cdn = _Recorder(SimCDN(size: _size));
        final config = TestEngine.config.copyWith(audioFirst: on, audioWholeBytes: 512 * 1024);
        final session = _session(cdn, config: config, tracks: const [TrackKind.video, TrackKind.audio]);
        expect(await _read(session, all[3].range, TrackKind.audio), _bytes(cdn.cdn, all[3].range));
        final audioRequests = cdn.requests.where((request) => request.url.contains('/a.m4s')).toList();
        if (on) {
          expect(audioRequests.take(2).map((request) => request.range), everyElement(all[3].range));
          expect(audioRequests.take(2).map((request) => NodeCatalog.nodeKey(request.url)).toSet(), hasLength(2));
          expect(cdn.cdn.peakInflight, greaterThanOrEqualTo(2), reason: 'both copies at once');
        } else {
          expect(audioRequests.first.range.length, 64 * 1024, reason: 'Swift probes, then splits');
        }
        session.close();
      }
    });

    test('an audio read behind queued video pieces gets the next connection', () async {
      Future<int> audioFirstByte({required bool on}) async {
        final cdn = SimCDN(size: _size, behaviors: {
          for (final node in NodeCatalog.overseas) node: const NodeBehavior(bytesPerSecond: 1e6),
        });
        final config = TestEngine.slowConfig
            .copyWith(fixedConcurrency: 2, prefetchVideoBytes: 0, prefetchAudioBytes: 0, audioFirst: on);
        final session = _session(cdn, config: config, tracks: const [TrackKind.video, TrackKind.audio]);
        addTearDown(session.close);
        await _read(session, all[0].range);
        await _read(session, all[3].range, TrackKind.audio);
        // Four video pieces for two connections: segment 2's take them, and segment 1's wait, overdue and so more
        // urgent than the next audio segment.
        session.updatePlayhead(seconds: 4.5, rate: 1);
        final videos = [_read(session, all[2].range), _read(session, all[1].range)];
        await _sleep(5);
        final audio = await _timedRead(session, all[4].range, TrackKind.audio);
        expect(audio.bytes, _bytes(cdn, all[4].range));
        await Future.wait(videos);
        return audio.firstMs;
      }

      final behind = await audioFirstByte(on: false);
      final first = await audioFirstByte(on: true);
      // A 128 KiB piece takes at least 128 ms at 1 MB/s: Swift's audio waited for two rounds of video pieces.
      expect(behind, greaterThanOrEqualTo(300));
      expect(first, lessThan(behind - 100));
    });
  });

  group('rate-aware prefetch', () {
    test('the look-ahead covers the same wall time at any rate up to 3x', () async {
      for (final on in [false, true]) {
        final config = TestEngine.config.copyWith(prefetchAheadSeconds: 5, prefetchFollowsRate: on);
        final session = _session(SimCDN(size: _size), config: config);
        await _read(session, all[0].range);
        await _until(() => session.prefetchesRunning(TrackKind.video) == 0);
        expect(session.cachedBytes(TrackKind.video), 2 * _segment, reason: 'segments at 2 and 4 s');
        session.updatePlayhead(seconds: 0, rate: 2);
        expect(session.lookAhead, on ? 10 : 5);
        await _read(session, all[1].range);
        await _until(() => session.prefetchesRunning(TrackKind.video) == 0);
        expect(session.isCached(TrackKind.video, all[5].range), on, reason: 'the segment at 10 s');
        session.updatePlayhead(seconds: 0, rate: 4);
        expect(session.lookAhead, on ? 15 : 5);
        session.close();
      }
    });

    test('the cap follows the stream\'s bitrate between the fixed cap and the max', () async {
      for (final ceiling in [null, 4 * 1024 * 1024]) {
        final config = ceiling == null
            ? TestEngine.config.copyWith(prefetchVideoBytes: _segment)
            : TestEngine.config.copyWith(prefetchVideoBytes: _segment, prefetchVideoMaxBytes: ceiling);
        final session = _session(SimCDN(size: _size), config: config);
        // 128 KiB/s over 45 s, a quarter more: about 7 MiB, held to the max.
        expect(session.prefetchCap(TrackKind.video), ceiling ?? _segment);
        await _read(session, all[0].range);
        await _until(() => session.prefetchesRunning(TrackKind.video) == 0);
        expect(session.cachedBytes(TrackKind.video), ceiling == null ? _segment : 11 * _segment);
        session.close();
      }
      final slow = _session(SimCDN(size: _size),
          config: TestEngine.config.copyWith(prefetchVideoBytes: 64 << 20, prefetchVideoMaxBytes: 256 << 20));
      expect(slow.prefetchCap(TrackKind.video), 64 << 20, reason: 'never below the fixed cap');
      slow.close();
    });
  });

  group('back buffer', () {
    Future<RipperSession> readFour(SimCDN cdn, RipperConfig config) async {
      final session = _session(cdn, config: config.copyWith(prefetchVideoBytes: 0));
      for (var index = 0; index < 4; index++) {
        session.updatePlayhead(seconds: index * 2.0, rate: 1);
        await _read(session, all[index].range);
      }
      return session;
    }

    test('segments the player read stay cached, so a jump back comes from memory', () async {
      for (final on in [false, true]) {
        final cdn = SimCDN(size: _size);
        final config = on
            ? TestEngine.config.copyWith(keepBehindSeconds: 30, keepBehindBytes: 8 << 20)
            : TestEngine.config.copyWith();
        final session = await readFour(cdn, config);
        expect(session.isCached(TrackKind.video, all[1].range), on);
        expect(session.prefetchedBytes(TrackKind.video), 0, reason: 'kept segments are not prefetch');
        final requests = cdn.requestCount;
        final hits = session.stats().cacheHits;
        expect(await _read(session, all[1].range), _bytes(cdn, all[1].range));
        expect(cdn.requestCount == requests, on);
        expect(session.stats().cacheHits, hits + (on ? 1 : 0));
        session.close();
      }
    });

    test('the kept bytes are capped, nearest the playhead kept, and they outlive a seek', () async {
      final cdn = SimCDN(size: _size);
      final session =
          await readFour(cdn, TestEngine.config.copyWith(keepBehindSeconds: 30, keepBehindBytes: 2 * _segment));
      addTearDown(session.close);
      expect([for (final segment in all.take(4)) session.isCached(TrackKind.video, segment.range)],
          [false, false, true, true]);
      await _read(session, all[9].range);
      expect(session.isCached(TrackKind.video, all[3].range), isTrue, reason: 'a seek drops prefetch, not these');
    });

    test('kept segments that ended over keepBehindSeconds ago are dropped', () async {
      final session = await readFour(
          SimCDN(size: _size), TestEngine.config.copyWith(keepBehindSeconds: 3, keepBehindBytes: 8 << 20));
      addTearDown(session.close);
      session.updatePlayhead(seconds: 9, rate: 1);
      expect([for (final segment in all.take(4)) session.isCached(TrackKind.video, segment.range)],
          [false, false, true, true]);
    });
  });

  group('hint', () {
    test('a hint downloads both tracks there without seeking; the seek takes it over and leaves the old prefetch',
        () async {
      final cdn = _Recorder(SimCDN(size: _size));
      final config = TestEngine.config.copyWith(prefetchVideoBytes: 2 * _segment, prefetchAudioBytes: 2 * _segment);
      final session = _session(cdn, config: config, tracks: const [TrackKind.video, TrackKind.audio], mode: _oneNode);
      addTearDown(session.close);
      await _read(session, all[0].range);
      await _read(session, all[0].range, TrackKind.audio);
      await _until(() => session.prefetchesRunning(TrackKind.video) + session.prefetchesRunning(TrackKind.audio) == 0);
      final seeks = session.seekCount;
      final generation = session.seekGeneration(TrackKind.video);

      session.hint(all[9].startTime + 0.5);
      expect(session.hinting(TrackKind.video, all[9].range), isTrue);
      expect(session.hinting(TrackKind.audio, all[9].range), isTrue);
      expect(session.seekCount, seeks, reason: 'not the player\'s seek yet');
      expect(session.seekGeneration(TrackKind.video), generation);
      expect(session.isCached(TrackKind.video, all[1].range), isTrue, reason: 'the old position stays until the seek');

      expect(await _read(session, all[9].range), _bytes(cdn.cdn, all[9].range));
      expect(cdn.requestedBytes(all[9].range), _segment, reason: 'downloaded once, by the hint');
      expect(session.seekCount, seeks + 1);
      expect(session.isCached(TrackKind.video, all[1].range), isFalse, reason: 'the seek left the old position');
      expect(session.isCached(TrackKind.audio, all[1].range), isTrue, reason: 'until audio seeks too');
    });

    test('a newer hint cancels the older one, and null cancels it', () async {
      final cdn = _Recorder(SimCDN(size: _size))..open = false;
      final session = _session(cdn, tracks: const [TrackKind.video, TrackKind.audio]);
      addTearDown(session.close);
      session.hint(all[5].startTime);
      expect(session.hinting(TrackKind.video, all[5].range), isTrue);
      session.hint(all[9].startTime);
      expect(session.hinting(TrackKind.video, all[5].range), isFalse);
      expect(session.hinting(TrackKind.video, all[9].range), isTrue);
      expect(session.prefetchesRunning(TrackKind.video), 1);
      expect(session.prefetchesRunning(TrackKind.audio), 1);
      session.hint(all[9].startTime + 1);
      expect(session.hinting(TrackKind.video, all[9].range), isTrue, reason: 'the same segment goes on');
      session.hint(null);
      expect(session.prefetchesRunning(TrackKind.video), 0);
      expect(session.prefetchesRunning(TrackKind.audio), 0);
    });

    test('a hinted seek shows its first bytes sooner', () async {
      Future<int> seekFirstByte({required bool hinted}) async {
        final cdn = SimCDN(size: _size, behaviors: {_single: const NodeBehavior(firstByteMs: 100)});
        final session = _session(cdn, config: TestEngine.slowConfig.copyWith(prefetchVideoBytes: 0), mode: _oneNode);
        addTearDown(session.close);
        await _read(session, all[0].range);
        if (hinted) session.hint(all[8].startTime);
        // The finger rests, then lifts.
        await _sleep(200);
        final seek = await _timedRead(session, all[8].range);
        expect(seek.bytes, _bytes(cdn, all[8].range));
        return seek.firstMs;
      }

      final plain = await seekFirstByte(hinted: false);
      final hinted = await seekFirstByte(hinted: true);
      expect(plain, greaterThanOrEqualTo(100));
      expect(hinted, lessThan(plain));
    });
  });

  group('streamed takeover', () {
    // One node sending 256 KiB a second per request: the prime's 64 KiB probe takes 250 ms, its other three
    // pieces another 250 ms together.
    Future<_Timed> takeOver({required bool stream}) async {
      final cdn = SimCDN(size: _size, behaviors: {_single: NodeBehavior(bytesPerSecond: _segment.toDouble())});
      final session =
          _session(cdn, config: TestEngine.slowConfig.copyWith(streamAdopted: stream), mode: _oneNode);
      addTearDown(session.close);
      session.prime(TrackKind.video, seconds: 0);
      await _sleep(100);
      final read = await _timedRead(session, all[0].range);
      expect(read.bytes, _bytes(cdn, all[0].range));
      return read;
    }

    test('a read that takes over a running prime gets its bytes as they arrive', () async {
      final whole = await takeOver(stream: false);
      final streamed = await takeOver(stream: true);
      expect(whole.firstMs, greaterThanOrEqualTo(300), reason: 'Swift hands the segment over once it is complete');
      expect(streamed.firstMs, lessThan(whole.firstMs - 100));
    });

    test('when the prime breaks off, the read fetches the rest and the bytes are exact', () async {
      final cdn = _Recorder(SimCDN(size: _size));
      // Long timeouts: the held pieces must fail by their 403, not by waiting.
      final config = TestEngine.config.copyWith(pieceRounds: 1, firstByteTimeoutMs: 3000, streamAdopted: true);
      final session = _session(cdn, config: config, mode: _oneNode);
      addTearDown(session.close);
      var fatal = false;
      session.onFatal = (_) => fatal = true;
      final segment = all[1];
      final brokenFrom = segment.range.start + 128 * 1024;
      cdn
        ..doomFrom = brokenFrom
        ..dooming = true
        ..holdFrom = brokenFrom;
      session.prime(TrackKind.video, seconds: segment.startTime);
      final received = BytesBuilder(copy: false);
      final done = Completer<void>();
      session
          .read(TrackKind.video, segment.range)
          .listen(received.add, onDone: done.complete, onError: done.completeError);
      await _until(() => received.length >= 128 * 1024);
      expect(received.length, 128 * 1024, reason: 'the front came from the prime before it broke off');
      cdn
        ..dooming = false
        ..holdFrom = null;
      await done.future;
      expect(received.takeBytes(), _bytes(cdn.cdn, segment.range));
      expect(fatal, isFalse);
      expect(cdn.requests.where((request) => request.range.start == brokenFrom), hasLength(greaterThanOrEqualTo(2)),
          reason: 'the prime\'s refused piece, then the read\'s own request for the rest');
    });
  });
}
