// A session loaded ahead for 竖屏's next video (RipperSession(warm: true)), and its promotion when the video opens.

import 'dart:math';
import 'dart:typed_data';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:test/test.dart';

import 'support/sim_cdn.dart';

const _size = 4 * 1024 * 1024;
const _headerEnd = 1023;
const _segment = 262144;

List<MediaSegment> _segments() => [
  for (var index = 0; index < 12; index++)
    MediaSegment(
      index: index,
      range: ByteRange(_headerEnd + 1 + index * _segment, _headerEnd + (index + 1) * _segment),
      startTime: index * 2.0,
      duration: 2,
    ),
];

/// Records every range asked for.
final class _Recorder implements RangeTransport {
  _Recorder(this.cdn);

  final SimCDN cdn;
  final ranges = <ByteRange>[];

  @override
  int? get connectionsPerHost => cdn.connectionsPerHost;

  @override
  String get name => 'recorder';

  @override
  void close() {}

  @override
  Future<TransportResponse> fetch(Uri url, ByteRange range, {CancelToken? cancel}) {
    ranges.add(range);
    return cdn.fetch(url, range, cancel: cancel);
  }

  int requestedBytes(ByteRange segment) {
    var sum = 0;
    for (final range in ranges) {
      final overlap = min(range.end, segment.end) - max<int>(range.start, segment.start) + 1;
      if (overlap > 0) sum += overlap;
    }
    return sum;
  }
}

/// [TestEngine.config] without its fixed connection count, so AutoConcurrency decides.
final _automatic = RipperConfig(
  firstByteTimeoutMs: TestEngine.config.firstByteTimeoutMs,
  stallTimeoutMs: TestEngine.config.stallTimeoutMs,
  attemptTimeoutMs: TestEngine.config.attemptTimeoutMs,
  hedgeDelayMs: TestEngine.config.hedgeDelayMs,
  retryWindowMs: TestEngine.config.retryWindowMs,
  prefetchOnPrime: true,
);

RipperSession _session(
  RangeTransport transport, {
  bool warm = false,
  AutoConcurrency? auto,
  RipperConfig? config,
  Logger? logger,
}) {
  final session = RipperSession(
    sources: {TrackKind.video: (primary: TestEngine.primary, backups: const <String>[])},
    mode: NodeMode.overseas,
    transport: transport,
    auto: auto,
    config: config ?? _automatic,
    logger: logger ?? Logger(session: 'test'),
    warm: warm,
  );
  session.setSegments(TrackKind.video, _segments());
  return session;
}

Future<Uint8List> _read(RipperSession session, ByteRange range) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in session.read(TrackKind.video, range)) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

Future<void> _until(bool Function() condition) async {
  expect(await eventually(condition, seconds: 5), isTrue, reason: 'timed out waiting');
}

void main() {
  final all = _segments();

  test('a warm session leaves the app-wide count alone: no handler taken, no startup climb, three connections', () {
    final auto = AutoConcurrency();
    final threads = auto.threads;
    final alone = _session(SimCDN(size: _size), warm: true, auto: auto);
    addTearDown(alone.close);
    expect(alone.isWarm, isTrue);
    expect(auto.onChange, isNull, reason: 'nobody took the handler');
    expect(auto.threads, threads, reason: 'a new session would have climbed to the startup level');
    expect(alone.stats().concurrency, RipperSession.warmConcurrency);

    final playing = _session(SimCDN(size: _size), auto: auto);
    addTearDown(playing.close);
    final handler = auto.onChange;
    final playingThreads = playing.stats().concurrency;
    final next = _session(SimCDN(size: _size), warm: true, auto: auto);
    addTearDown(next.close);
    expect(identical(auto.onChange, handler), isTrue, reason: 'the playback on screen keeps the handler');
    auto.pushback(status: 429);
    expect(playing.stats().concurrency, auto.threads, reason: 'and follows the count');
    expect(playing.stats().concurrency, isNot(playingThreads));
    expect(next.stats().concurrency, RipperSession.warmConcurrency);
  });

  test('promoted, it takes the handler and the count over as a new session does; a fixed count is its own', () {
    final auto = AutoConcurrency();
    final threads = auto.threads;
    final session = _session(SimCDN(size: _size), warm: true, auto: auto);
    addTearDown(session.close);
    session.promote();
    expect(session.isWarm, isFalse);
    expect(auto.onChange, isNotNull);
    expect(auto.threads, greaterThan(threads), reason: 'a new session starts high');
    expect(session.stats().concurrency, auto.threads);
    auto.pushback(status: 429);
    expect(session.stats().concurrency, auto.threads);

    final fixed = _session(SimCDN(size: _size), warm: true, auto: auto, config: TestEngine.config);
    addTearDown(fixed.close);
    expect(fixed.stats().concurrency, RipperSession.warmConcurrency);
    fixed.promote();
    expect(fixed.stats().concurrency, TestEngine.config.fixedConcurrency);
  });

  test('a warm prime downloads its segment and nothing after it, never in a hurry; promoted, it hurries and prefetches',
      () async {
    final logs = MemorySink();
    final cdn = _Recorder(SimCDN(size: _size));
    final session = _session(cdn, warm: true, logger: Logger(session: 'test')..add(logs));
    addTearDown(session.close);

    session.prime(TrackKind.video, seconds: 0);
    expect(session.priming(TrackKind.video, all[0].range), isTrue);
    expect(session.hurries(TrackKind.video, all[0].range), isFalse);
    expect(session.prefetchesRunning(TrackKind.video), 1, reason: 'the prime alone');
    await _until(() => session.isCached(TrackKind.video, all[0].range));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(session.prefetchesRunning(TrackKind.video), 0);
    expect(cdn.requestedBytes(all[1].range), 0, reason: 'no prefetch while warm');
    final prime = logs.events.singleWhere((event) => event.msg == 'prime');
    expect(prime.f['warm'], const LogBool(true));
    expect(prime.f['outcome'], const LogString('done'));

    session.promote();
    expect(session.hurries(TrackKind.video, all[0].range), isTrue);
    // The engine primes again at the open's start: the segment is in, so only the prefetch after it starts.
    session.prime(TrackKind.video, seconds: 0);
    expect(session.prefetchesRunning(TrackKind.video), greaterThan(0));
    final bytes = await _read(session, all[0].range);
    expect(bytes, Uint8List.sublistView(cdn.cdn.content, all[0].range.start, all[0].range.end + 1));
    expect(session.stats().cacheHits, 1, reason: 'the warm prime served the read');
    expect(cdn.requestedBytes(all[0].range), _segment, reason: 'downloaded once');
    await _until(() => cdn.requestedBytes(all[1].range) > 0);
    final promoted = logs.events.singleWhere((event) => event.msg == 'promoted');
    expect(promoted.f.keys.toSet(), {'threads', 'cachedBytes'});
    expect(promoted.f['cachedBytes'], const LogInt(_segment));
  });

  test('promoted where its prime is not, the open\'s start is primed at once as a normal prime', () async {
    final cdn = _Recorder(SimCDN(size: _size));
    final session = _session(cdn, warm: true);
    addTearDown(session.close);
    session.promote();
    session.prime(TrackKind.video, seconds: 4.5);
    expect(session.priming(TrackKind.video, all[2].range), isTrue);
    expect(session.hurries(TrackKind.video, all[2].range), isTrue);
    await _until(() => cdn.requestedBytes(all[3].range) > 0);
  });

  test('a warm prime still downloading at the promotion is hurried from then on, and the read takes it over', () async {
    final logs = MemorySink();
    final cdn = _Recorder(SimCDN(size: _size, behaviors: {
      'upos-sz-mirrorcos.bilivideo.com': const NodeBehavior(firstByteMs: 60),
    }));
    final session = _session(cdn, warm: true, logger: Logger(session: 'test')..add(logs));
    addTearDown(session.close);
    session.prime(TrackKind.video, seconds: 0);
    session.promote();
    expect(session.hurries(TrackKind.video, all[0].range), isTrue);
    final bytes = await _read(session, all[0].range);
    expect(bytes, Uint8List.sublistView(cdn.cdn.content, all[0].range.start, all[0].range.end + 1));
    await _until(() => logs.events.any((event) => event.msg == 'prime'));
    final prime = logs.events.singleWhere((event) => event.msg == 'prime');
    expect(prime.f['adopted'], const LogBool(true));
    expect(prime.f['warm'], const LogBool(true));
  });
}
