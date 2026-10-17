// Port of BiliNative's RangeDownloaderTests.swift.

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bili_core/src/engine/attempt.dart';
import 'package:bili_core/src/engine/ban_list.dart';
import 'package:bili_core/src/engine/connection_pool.dart';
import 'package:bili_core/src/engine/engine_stats.dart';
import 'package:bili_core/src/engine/meter.dart';
import 'package:bili_core/src/engine/piece_downloader.dart';
import 'package:bili_core/src/engine/range_downloader.dart';
import 'package:bili_core/src/engine/resolver.dart';
import 'package:test/test.dart';

import 'support/sim_cdn.dart';

typedef Request = ({String node, ByteRange range});

/// Records every request on its way to the simulated CDN.
final class RecordingTransport implements RangeTransport {
  RecordingTransport(this.cdn);

  final SimCDN cdn;
  final requests = <Request>[];

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

const _akamai = 'upos-hz-mirrorakam.akamaized.net';
final _mebibyte = ByteRange(0, 1048575);

String _url(String node) => TestEngine.primary.replaceAll('upos-sz-mirrorcos.bilivideo.com', node);

Uint8List _slice(SimCDN cdn, ByteRange range) => Uint8List.sublistView(cdn.content, range.start, range.end + 1);

/// Byte-for-byte equality that reports the first difference instead of printing megabytes.
void _expectBytes(List<int> actual, List<int> expected) {
  expect(actual.length, expected.length, reason: 'length');
  for (var index = 0; index < actual.length; index++) {
    if (actual[index] != expected[index]) fail('first difference at byte $index');
  }
}

EngineSnapshot _snapshot(EngineContext ctx) => ctx.stats.snapshot(concurrency: ctx.pool.limit, nodeStates: const []);

EngineContext _context(RangeTransport transport, {RipperConfig config = TestEngine.config}) => EngineContext(
  transport: transport,
  pool: ConnectionPool(config.fixedConcurrency ?? 8),
  config: config,
  meter: Meter(),
  stats: EngineStats(),
  clock: MonotonicClock.system,
  logger: Logger(session: 'test'),
);

Future<Uint8List> _read(
  RangeDownloader downloader,
  ByteRange range,
  Resolver resolver, {
  bool startup = false,
  double priority = 50,
  double Function()? deadline,
  bool Function()? hurry,
}) async {
  final builder = BytesBuilder(copy: false);
  await downloader.stream(
    range,
    resolver,
    startup: startup,
    priority: priority,
    deadline: deadline,
    hurry: hurry,
    emit: builder.add,
  );
  return builder.takeBytes();
}

Future<Uint8List> _collect(
  SimCDN cdn,
  ByteRange range, {
  Resolver? resolver,
  bool startup = false,
  AutoConcurrency? auto,
  RipperConfig config = TestEngine.config,
}) => _read(
  RangeDownloader(TestEngine.context(cdn, config: config, auto: auto)),
  range,
  resolver ?? TestEngine.resolver(),
  startup: startup,
);

/// A fixed-size test context on a hand-driven clock, for the hedging rules.
PieceDownloader _pieces(ManualClock clock, {RipperConfig config = TestEngine.config, Meter? meter}) => PieceDownloader(
  EngineContext(
    transport: SimCDN(size: 1),
    pool: ConnectionPool(1),
    config: config,
    meter: meter ?? Meter(),
    stats: EngineStats(),
    clock: clock.clock,
    logger: Logger(session: 'test'),
  ),
);

/// A node measured at [ttfbMs] to its first byte and [bytes] per [ms] for one piece.
void _measure(EngineContext ctx, String url, {required double ttfbMs, required int bytes, required double ms}) {
  ctx.nodes
    ..begin(url)
    ..firstByte(url, ms: ttfbMs)
    ..body(url, bytes: bytes, ms: ms)
    ..end(url, receiving: true);
}

int _countOf(List<String> list, String value) => list.where((each) => each == value).length;

void main() {
  test('all fast nodes deliver exact bytes in order', () async {
    final cdn = SimCDN(size: 2000000);
    final bytes = await _collect(cdn, _mebibyte);
    _expectBytes(bytes, _slice(cdn, _mebibyte));
    expect(cdn.requests.toSet().length, greaterThan(1), reason: 'pieces should spread over several nodes');
  });

  test('startup probe then pieces', () async {
    final cdn = SimCDN(size: 2000000);
    final range = ByteRange(1000, 900000);
    final bytes = await _collect(cdn, range, startup: true);
    _expectBytes(bytes, _slice(cdn, range));
  });

  test('a refusing node is routed around and banned', () async {
    final cdn = SimCDN(size: 2000000, behaviors: {TestEngine.cosov: const NodeBehavior(status: 403)});
    final resolver = TestEngine.resolver();
    final bytes = await _collect(cdn, _mebibyte, resolver: resolver);
    _expectBytes(bytes, _slice(cdn, _mebibyte));
    expect(resolver.allows(_url(TestEngine.cosov)), isFalse);
  });

  // The overseas Akamai node of 2026-10-16: it refuses the primary `os=cosovbv` address at the edge and serves the
  // `os=akam` backup, slow to start while cold and then far faster than every mirror. The mirrors serve both.
  test('an address refused on the fastest node drops only that pair', () async {
    const address = 'https://$_akamai/upgcxcode/1/2/3/v.m4s?deadline=9';
    const refused = '$address&os=cosovbv';
    const served = '$address&os=akam';
    final behaviors = <String, NodeBehavior>{
      _akamai: const NodeBehavior(
        firstByteMs: 20,
        bytesPerSecond: 40000000,
        coldRequests: 2,
        coldFirstByteMs: 400,
        refusedQueries: ['os=cosovbv'],
      ),
    };
    for (final node in NodeCatalog.overseas) {
      behaviors[node] = const NodeBehavior(firstByteMs: 5, bytesPerSecond: 400000);
    }
    final cdn = SimCDN(size: 6500000, behaviors: behaviors);
    final config = TestEngine.slowConfig.copyWith(firstByteTimeoutMs: 1000);
    final clock = ManualClock(1000000);
    final bans = BanList();
    final resolver = Resolver(
      primary: refused,
      backups: const [served],
      mode: NodeMode.overseas,
      bans: bans,
      clock: clock.clock,
    );
    final downloader = RangeDownloader(TestEngine.context(cdn, config: config));
    await downloader.meta(ByteRange(0, 1023), resolver);
    // Unproven, the Akamai node gets work only after the four warm-up ranges (BTR's exploration order).
    for (var index = 0; index < 12; index++) {
      // Playback time passes between segments, so the refused address's backoff runs out.
      clock.advance(7000);
      final range = ByteRange(1024 + (index << 19), 1023 + ((index + 1) << 19));
      final bytes = await _read(downloader, range, resolver, startup: index == 0);
      _expectBytes(bytes, _slice(cdn, range));
    }
    expect(bans.allowsNode(served), isTrue, reason: 'a refusal of one address must not ban the node');
    expect(resolver.allows(served), isTrue);
    expect(bans.allows(refused), isFalse, reason: 'the refusing node and address pair is dropped');
    expect(bans.allowsAddress(refused), isTrue, reason: 'the mirrors serve that address');
    final sent = <String, int>{};
    for (final MapEntry(key: url, value: bytes) in cdn.deliveredBytes.entries) {
      final node = NodeCatalog.nodeKey(url);
      sent[node] = (sent[node] ?? 0) + bytes;
    }
    final mirrorMost = sent.entries.where((entry) => entry.key != _akamai).map((entry) => entry.value).fold(0, max);
    expect(sent[_akamai] ?? 0, greaterThan(mirrorMost), reason: 'the fastest node carries the most bytes: $sent');
  });

  // Akamai's copy of KaiC's q80 file, 2026-10-16: bytes 109972 through the end of the first MiB were missing, the
  // rest was whole and far faster than any mirror.
  test('a node with a damaged span keeps serving the rest', () async {
    final missing = ByteRange(109972, 1048575);
    final behaviors = <String, NodeBehavior>{
      TestEngine.aliov: NodeBehavior(firstByteMs: 20, bytesPerSecond: 40000000, missing: missing),
    };
    for (final node in [TestEngine.cosov, TestEngine.hk1, TestEngine.hk3]) {
      behaviors[node] = const NodeBehavior(bytesPerSecond: 1000000);
    }
    final cdn = SimCDN(size: 6500000, behaviors: behaviors);
    final transport = RecordingTransport(cdn);
    final resolver = TestEngine.resolver();
    final downloader = RangeDownloader(_context(transport, config: TestEngine.slowConfig));
    Future<void> read(int index) async {
      final range = ByteRange(1024 + (index << 19), 1023 + ((index + 1) << 19));
      final bytes = await _read(downloader, range, resolver, startup: index == 0);
      _expectBytes(bytes, _slice(cdn, range));
    }

    await downloader.meta(ByteRange(0, 1023), resolver);
    for (var index = 0; index < 12; index++) {
      await read(index);
    }
    final aliovURL = _url(TestEngine.aliov);
    expect(resolver.bans?.allowsNode(aliovURL) ?? false, isTrue);
    expect(resolver.allows(aliovURL), isTrue);
    final sent = cdn.deliveredBytes;
    final total = sent.values.fold(0, (sum, bytes) => sum + bytes);
    expect(sent[aliovURL] ?? 0, greaterThan(total ~/ 2), reason: 'the fast node carries most bytes: $sent');

    // Seeking back: the damaged span is not asked of that node again.
    final asked = transport.requests.length;
    for (var index = 0; index < 2; index++) {
      await read(index);
    }
    final again = transport.requests
        .skip(asked)
        .where(
          (request) =>
              request.node == TestEngine.aliov &&
              request.range.end >= missing.start &&
              request.range.start <= missing.end,
        )
        .toList();
    expect(again, isEmpty, reason: '${again.map((request) => request.range)}');
  });

  test('broken nodes never corrupt the output', () async {
    final cdn = SimCDN(
      size: 2000000,
      behaviors: {
        TestEngine.cosov: const NodeBehavior(wrongRange: true),
        TestEngine.aliov: const NodeBehavior(truncateAfter: 10000),
        TestEngine.hk1: const NodeBehavior(stallAfter: 16384),
      },
    );
    final bytes = await _collect(cdn, _mebibyte);
    _expectBytes(bytes, _slice(cdn, _mebibyte));
  });

  test('a slow first byte is hedged', () async {
    final cdn = SimCDN(size: 2000000, behaviors: {TestEngine.cosov: const NodeBehavior(firstByteMs: 1000)});
    final started = Stopwatch()..start();
    final bytes = await _collect(cdn, _mebibyte);
    _expectBytes(bytes, _slice(cdn, _mebibyte));
    expect(started.elapsedMilliseconds, lessThan(3000));
  });

  test('every node refusing fails', () async {
    final cdn = SimCDN(
      size: 2000000,
      behaviors: {for (final node in NodeCatalog.overseas) node: const NodeBehavior(status: 403)},
    );
    await expectLater(_collect(cdn, ByteRange(0, 99999)), throwsA(isA<RipperError>()));
  });

  // Review focus 5: a Wi-Fi to cellular switch makes every node fail for a moment.
  test('a short network blip is ridden out', () async {
    final cdn = SimCDN(
      size: 2000000,
      behaviors: {for (final node in NodeCatalog.overseas) node: const NodeBehavior(failForMs: 400)},
    );
    final bytes = await _collect(cdn, ByteRange(0, 299999));
    _expectBytes(bytes, _slice(cdn, ByteRange(0, 299999)));
  });

  test('a rate limit pushes connections down', () async {
    final cdn = SimCDN(size: 2000000, behaviors: {TestEngine.aliov: const NodeBehavior(status: 429)});
    final auto = AutoConcurrency();
    auto.newSession();
    expect(auto.threads, 16);
    // TestEngine.config without its fixed connection count, which copyWith can't clear.
    const config = RipperConfig(
      firstByteTimeoutMs: 300,
      stallTimeoutMs: 300,
      attemptTimeoutMs: 3000,
      hedgeDelayMs: 100,
      retryWindowMs: 5000,
    );
    await _collect(cdn, _mebibyte, auto: auto, config: config);
    expect(auto.threads, lessThan(16));
  }, skip: 'needs AutoConcurrency port');

  test('the meta race returns the whole range', () async {
    final cdn = SimCDN(size: 50000, behaviors: {TestEngine.cosov: const NodeBehavior(firstByteMs: 200)});
    final downloader = RangeDownloader(TestEngine.context(cdn));
    final output = await downloader.meta(ByteRange(0, 4999), TestEngine.resolver());
    _expectBytes(output.bytes, _slice(cdn, ByteRange(0, 4999)));
    expect(output.total, 50000);
  });

  // One round's walk over the nodes takes about 0.4 s on Windows, which can hide a 0.4 s blip by itself. This one
  // is longer than a round but shorter than the 0.5 s + 1 s pauses before round 3.
  test('a blip is ridden out by the retry rounds alone', () async {
    SimCDN blip() => SimCDN(
      size: 2000000,
      behaviors: {for (final node in NodeCatalog.overseas) node: const NodeBehavior(failForMs: 1400)},
    );
    final range = ByteRange(0, 299999);
    final oneRound = TestEngine.config.copyWith(pieceRounds: 1);
    await expectLater(
      _collect(blip(), range, config: oneRound),
      throwsA(anything),
      reason: 'a single round cannot outlast the blip',
    );

    final cdn = blip();
    final ctx = _context(cdn);
    final bytes = await _read(RangeDownloader(ctx), range, TestEngine.resolver());
    _expectBytes(bytes, _slice(cdn, range));
    expect(_snapshot(ctx).failures, greaterThan(0), reason: 'the blip must have hit the first round');
  });

  test('fails only after every round', () async {
    final cdn = SimCDN(
      size: 2000000,
      behaviors: {for (final node in NodeCatalog.overseas) node: const NodeBehavior(status: 403)},
    );
    final started = Stopwatch()..start();
    await expectLater(_collect(cdn, ByteRange(0, 99999)), throwsA(const RipperError.badResponse(403)));
    expect(started.elapsedMilliseconds, greaterThanOrEqualTo(1400), reason: 'rounds pause 0.5 s and 1 s');
    for (final node in NodeCatalog.overseas) {
      expect(_countOf(cdn.requests, node), greaterThanOrEqualTo(3), reason: '$node is asked in every round');
    }
  });

  test('a banned node gets no more work', () async {
    final cdn = SimCDN(size: 2000000, behaviors: {TestEngine.cosov: const NodeBehavior(status: 403)});
    final resolver = TestEngine.resolver();
    await _collect(cdn, _mebibyte, resolver: resolver);
    expect(resolver.allows(_url(TestEngine.cosov)), isFalse);
    final asked = _countOf(cdn.requests, TestEngine.cosov);
    final range = ByteRange(1048576, 1999999);
    final bytes = await _collect(cdn, range, resolver: resolver);
    _expectBytes(bytes, _slice(cdn, range));
    expect(_countOf(cdn.requests, TestEngine.cosov), asked);
  });

  test('different total sizes fail the range', () async {
    final cdn = SimCDN(size: 2000000, behaviors: {TestEngine.cosov: const NodeBehavior(totalSize: 2000001)});
    // No backup copies: with no speeds known, every node wins the pieces it was assigned.
    final config = TestEngine.config.copyWith(hedgeDelayMs: 60000);
    await expectLater(
      _collect(cdn, _mebibyte, config: config),
      throwsA(const RipperError(RipperErrorKind.totalMismatch)),
    );
    expect(cdn.requests, contains(TestEngine.cosov));
  });

  test('a mismatched piece is never yielded', () async {
    final cdn = SimCDN(size: 2000000, behaviors: {TestEngine.cosov: const NodeBehavior(totalSize: 2000001)});
    final transport = RecordingTransport(cdn);
    // No backup copies: every piece is served by the node it was assigned to.
    final config = TestEngine.config.copyWith(hedgeDelayMs: 60000);
    final downloader = RangeDownloader(_context(transport, config: config));
    var yielded = 0;
    await expectLater(
      downloader.stream(
        _mebibyte,
        TestEngine.resolver(),
        startup: false,
        priority: 50,
        expectedTotal: 2000000,
        emit: (chunk) => yielded += chunk.length,
      ),
      throwsA(const RipperError(RipperErrorKind.totalMismatch)),
    );
    final lies = transport.requests.where((request) => request.node == TestEngine.cosov).map((r) => r.range.start);
    final firstLie = lies.isEmpty ? null : lies.reduce(min);
    expect(firstLie, isNotNull);
    expect(yielded, lessThanOrEqualTo(firstLie ?? 0), reason: 'no byte from the mismatched piece or after it');
  });

  test('the startup head is checked against the expected total', () async {
    final cdn = SimCDN(
      size: 2000000,
      behaviors: {for (final node in NodeCatalog.overseas) node: const NodeBehavior(totalSize: 2000001)},
    );
    final downloader = RangeDownloader(TestEngine.context(cdn));
    var yielded = 0;
    await expectLater(
      downloader.stream(
        _mebibyte,
        TestEngine.resolver(),
        startup: true,
        priority: 50,
        expectedTotal: 2000000,
        emit: (chunk) => yielded += chunk.length,
      ),
      throwsA(const RipperError(RipperErrorKind.totalMismatch)),
    );
    expect(yielded, 0);
  });

  test('hedgeDue rules', () {
    final clock = ManualClock();
    PieceDownloader downloader({required double usualBps}) {
      final meter = Meter();
      if (usualBps > 0) meter.record(bytes: usualBps.toInt(), elapsedMs: 1000);
      return _pieces(clock, meter: meter);
    }

    AttemptProgress copy({required int received}) {
      final progress = AttemptProgress();
      clock.set(0);
      progress.begin(at: 0, length: 1000000, base: Prefix.empty);
      if (received > 0) progress.append(Uint8List(received), at: 0);
      return progress;
    }

    final unknownUsual = downloader(usualBps: 0);

    final silent = copy(received: 0);
    clock.set(100);
    expect(
      unknownUsual.hedgeDue(silent, delayMs: 250, deadlineAt: 60000, copyBps: 0),
      isFalse,
      reason: 'before the delay',
    );
    clock.set(300);
    expect(
      unknownUsual.hedgeDue(silent, delayMs: 250, deadlineAt: 60000, copyBps: 0),
      isTrue,
      reason: 'no bytes after the delay',
    );

    final stuck = copy(received: 100000);
    clock.set(100);
    unknownUsual.hedgeDue(stuck, delayMs: 250, deadlineAt: 60000, copyBps: 0);
    clock.set(400);
    expect(
      unknownUsual.hedgeDue(stuck, delayMs: 250, deadlineAt: 60000, copyBps: 0),
      isTrue,
      reason: 'no progress for a whole delay',
    );

    // 500,000 of 1,000,000 bytes in 300 ms: done at 600 ms.
    bool onPace(PieceDownloader pieces, {required double deadlineAt, required double copyBps}) {
      final progress = copy(received: 500000);
      clock.set(300);
      return pieces.hedgeDue(progress, delayMs: 250, deadlineAt: deadlineAt, copyBps: copyBps);
    }

    expect(onPace(unknownUsual, deadlineAt: 2200, copyBps: 10000000), isFalse, reason: 'on pace with 1.5 s to spare');
    expect(
      onPace(unknownUsual, deadlineAt: 1000, copyBps: 4000000),
      isTrue,
      reason: "the copy's node is over 1.5x faster",
    );
    expect(
      onPace(downloader(usualBps: 10000000), deadlineAt: 1000, copyBps: 2000000),
      isTrue,
      reason: 'under 0.6x the usual connection',
    );
    expect(
      onPace(downloader(usualBps: 2000000), deadlineAt: 1000, copyBps: 2000000),
      isFalse,
      reason: "the copy's node is no faster",
    );
    expect(
      onPace(downloader(usualBps: 2000000), deadlineAt: 1000, copyBps: 0),
      isTrue,
      reason: 'an unmeasured node is worth a try',
    );
  });

  test('a finite deadline hedges a slow first byte', () async {
    final cdn = SimCDN(size: 2000000, behaviors: {TestEngine.cosov: const NodeBehavior(firstByteMs: 2000)});
    // Only a backup copy, not the first-byte timeout, can rescue cosov's pieces.
    final config = TestEngine.config.copyWith(firstByteTimeoutMs: 5000);
    final deadlineAt = MonotonicClock.system.nowMs() + 10000;
    final started = Stopwatch()..start();
    final bytes = await _read(
      RangeDownloader(TestEngine.context(cdn, config: config)),
      _mebibyte,
      TestEngine.resolver(),
      deadline: () => deadlineAt,
    );
    _expectBytes(bytes, _slice(cdn, _mebibyte));
    expect(cdn.requests, contains(TestEngine.cosov));
    expect(started.elapsedMilliseconds, lessThan(1500), reason: "cosov's pieces are hedged, not waited out");
  });

  test('cancelling the consumer stops all work', () async {
    final cdn = SimCDN(
      size: 2000000,
      behaviors: {for (final node in NodeCatalog.overseas) node: const NodeBehavior(bytesPerSecond: 250000)},
    );
    final ctx = TestEngine.context(cdn, config: TestEngine.slowConfig);
    final downloader = RangeDownloader(ctx);
    var received = 0;
    final consumer = CancelToken();
    // Startup mode yields the 64 KiB head long before the rest of the range is in.
    final stream = downloader
        .stream(
          _mebibyte,
          TestEngine.resolver(),
          startup: true,
          priority: 50,
          cancel: consumer,
          emit: (chunk) => received += chunk.length,
        )
        .then<void>((_) {}, onError: (Object _) {});
    final waitStarted = Stopwatch()..start();
    while (received == 0 && waitStarted.elapsedMilliseconds < 5000) {
      await sleepMs(5);
    }
    consumer.cancel();
    await stream;
    expect(received, greaterThan(0));
    expect(received, lessThan(_mebibyte.length));

    final idleStarted = Stopwatch()..start();
    while (ctx.pool.active > 0 && idleStarted.elapsedMilliseconds < 3000) {
      await sleepMs(10);
    }
    expect(ctx.pool.active, 0);
    expect(ctx.pool.queued, 0);
    final asked = cdn.requestCount;
    await sleepMs(500);
    expect(cdn.requestCount, asked, reason: 'no new requests once the consumer is gone');
  });

  test('an urgent range overtakes queued work', () async {
    final cdn = SimCDN(
      size: 4000000,
      behaviors: {for (final node in NodeCatalog.overseas) node: const NodeBehavior(bytesPerSecond: 250000)},
    );
    final downloader = RangeDownloader(TestEngine.context(cdn, config: TestEngine.slowConfig));
    final resolver = TestEngine.resolver();
    final finished = <String>[];
    Future<void> drain(String name, ByteRange range, {required double priority}) async {
      await downloader.stream(range, resolver, startup: false, priority: priority, emit: (_) {});
      finished.add(name);
    }

    // Three 7-piece ranges queue more pieces than the 8 connections can run.
    final low = [
      for (var index = 0; index < 3; index++)
        drain('low', ByteRange(index * 458752, (index + 1) * 458752 - 1), priority: 10),
    ];
    await sleepMs(30);
    final urgent = drain('urgent', ByteRange(2000000, 2458751), priority: 50);
    await Future.wait([...low, urgent]);
    final position = finished.indexOf('urgent');
    expect(
      position < 0 ? 99 : position,
      lessThanOrEqualTo(1),
      reason: 'only a range already fully running may finish first: $finished',
    );
  });

  test('a resume only starts from a prefix of at least 32 KiB', () async {
    for (final (cut, resumedAt) in [(40000, 40000), (10000, 0)]) {
      final cdn = SimCDN(size: 300000, behaviors: {TestEngine.cosov: NodeBehavior(truncateAfter: cut)});
      final transport = RecordingTransport(cdn);
      // The backup copy starts only once the first fails.
      final config = TestEngine.config.copyWith(hedgeDelayMs: 60000);
      final output = await PieceDownloader(_context(transport, config: config)).download(
        piece: ByteRange(0, 199999),
        index: 0,
        resolver: TestEngine.resolver(),
        preferred: [_url(TestEngine.cosov)],
        mode: PieceMode.normal,
        priority: 50,
      );
      _expectBytes(output.bytes, _slice(cdn, ByteRange(0, 199999)));
      final requests = transport.requests;
      expect(requests.firstOrNull?.node, TestEngine.cosov);
      expect(requests.skip(1).firstOrNull?.range, ByteRange(resumedAt, 199999), reason: 'cut after $cut');
    }
  });

  test('the resume base prefers the longest valid prefix', () {
    Prefix prefix(int bytes) => Prefix(bytes: bytes, chunks: [List.filled(bytes, 1)]);
    expect(PieceDownloader.resumeBase(prefix: prefix(20000), live: null, pieceLength: 100000).bytes, 0);
    expect(PieceDownloader.resumeBase(prefix: prefix(40000), live: null, pieceLength: 100000).bytes, 40000);
    expect(PieceDownloader.resumeBase(prefix: prefix(40000), live: prefix(60000), pieceLength: 100000).bytes, 60000);
    expect(PieceDownloader.resumeBase(prefix: prefix(40000), live: prefix(20000), pieceLength: 100000).bytes, 40000);
    expect(PieceDownloader.resumeBase(prefix: Prefix.empty, live: prefix(100000), pieceLength: 100000).bytes, 0);
  });

  test('a losing copy is cancelled and sampled, not punished', () async {
    final cdn = SimCDN(size: 600000, behaviors: {TestEngine.cosov: const NodeBehavior(bytesPerSecond: 200000)});
    final transport = RecordingTransport(cdn);
    final config = TestEngine.slowConfig.copyWith(hedgeDelayMs: 500);
    final ctx = _context(transport, config: config);
    final resolver = TestEngine.resolver();
    final cosovURL = _url(TestEngine.cosov);
    final started = Stopwatch()..start();
    final output = await PieceDownloader(ctx).download(
      piece: ByteRange(0, 399999),
      index: 0,
      resolver: resolver,
      preferred: [cosovURL],
      mode: PieceMode.normal,
      priority: 50,
    );
    _expectBytes(output.bytes, _slice(cdn, ByteRange(0, 399999)));
    expect(output.url, isNot(cosovURL));
    expect(started.elapsedMilliseconds, lessThan(1500), reason: 'cosov alone needs 2 s');
    final backup = transport.requests.where((request) => request.node != TestEngine.cosov).firstOrNull;
    expect(
      backup?.range.start ?? 0,
      greaterThanOrEqualTo(PieceDownloader.resumeMinBytes),
      reason: "the backup resumes from the first copy's bytes",
    );
    expect(resolver.allows(cosovURL), isTrue);
    expect(_snapshot(ctx).failures, 0);
    expect(resolver.speed(cosovURL), greaterThan(0), reason: 'the cancelled copy still measures its node');
  });

  test('a losing copy marks its node slow', () async {
    final cdn = SimCDN(size: 600000, behaviors: {TestEngine.cosov: const NodeBehavior(bytesPerSecond: 200000)});
    final config = TestEngine.slowConfig.copyWith(hedgeDelayMs: 500);
    final ctx = _context(RecordingTransport(cdn), config: config);
    final cosovURL = _url(TestEngine.cosov);
    _measure(ctx, cosovURL, ttfbMs: 5, bytes: 4000000, ms: 1000);
    final output = await PieceDownloader(ctx).download(
      piece: ByteRange(0, 399999),
      index: 0,
      resolver: TestEngine.resolver(),
      preferred: [cosovURL],
      mode: PieceMode.normal,
      priority: 50,
    );
    expect(output.url, isNot(cosovURL));
    expect(ctx.nodes.bps(cosovURL), lessThan(4000000), reason: 'cosov was still sending when the other copy won');
    expect(ctx.nodes.inflight(cosovURL), 0);
  });

  test('the piece event names the copy only for copies after the first', () async {
    final cdn = SimCDN(size: 600000, behaviors: {TestEngine.cosov: const NodeBehavior(bytesPerSecond: 200000)});
    final config = TestEngine.slowConfig.copyWith(hedgeDelayMs: 500);
    final ctx = _context(RecordingTransport(cdn), config: config);
    final sink = MemorySink();
    ctx.logger.add(sink);
    final cosovURL = _url(TestEngine.cosov);
    await PieceDownloader(ctx).download(
      piece: ByteRange(0, 399999),
      index: 0,
      resolver: TestEngine.resolver(),
      preferred: [cosovURL],
      mode: PieceMode.normal,
      priority: 50,
    );
    final pieces = sink.events.where((event) => event.msg == 'piece').toList();
    expect(pieces, hasLength(1), reason: 'only the copy that finished logs a piece');
    expect(pieces.first.f['copy'], const LogInt(2));
    expect(sink.events.where((event) => event.msg == 'copy'), isEmpty);
  });

  test('a hurry uses small pieces', () async {
    final cdn = SimCDN(size: 8000000);
    final transport = RecordingTransport(cdn);
    final downloader = RangeDownloader(_context(transport));
    final resolver = TestEngine.resolver();
    await _read(downloader, ByteRange(0, 4 * 1048576 - 1), resolver);
    final asked = transport.requests.length;
    final range = ByteRange(4 * 1048576, 6 * 1048576 - 1);
    final bytes = await _read(downloader, range, resolver, hurry: () => true);
    _expectBytes(bytes, _slice(cdn, range));
    // 2 MiB over the 7 connections left beside the rescue slot, not the warm meter's larger pieces.
    final pieces = transport.requests.skip(asked).map((request) => request.range).toList();
    expect(pieces.map((piece) => piece.start).toSet().length, greaterThanOrEqualTo(7), reason: '$pieces');
    for (final piece in pieces) {
      expect(piece.length, lessThanOrEqualTo(300 * 1024), reason: '$piece');
    }
  });

  test('warm nodes skip the probe head', () async {
    final cdn = SimCDN(size: 4000000);
    final transport = RecordingTransport(cdn);
    final downloader = RangeDownloader(_context(transport));
    final resolver = TestEngine.resolver();
    Future<List<Request>> read(ByteRange range) async {
      final asked = transport.requests.length;
      final bytes = await _read(downloader, range, resolver, startup: true, hurry: () => true);
      _expectBytes(bytes, _slice(cdn, range));
      return transport.requests.sublist(asked);
    }

    ByteRange head(ByteRange range) => ByteRange(range.start, range.start + 65535);

    // Review focus 3: with no node known the head is still raced over every node.
    final first = _mebibyte;
    final cold = await read(first);
    expect(
      cold.where((request) => request.range == head(first)).length,
      greaterThan(1),
      reason: '${cold.map((request) => request.range)}',
    );

    final second = ByteRange(2000000, 3048575);
    final warm = await read(second);
    expect(
      warm.any((request) => request.range == head(second)),
      isFalse,
      reason: '${warm.map((request) => request.range)}',
    );
    expect(
      warm.where((request) => request.range.start == second.start).length,
      1,
      reason: 'one ordinary piece starts the range',
    );
  });

  test('hurry hedge budgets', () {
    final clock = ManualClock();
    final pieces = _pieces(clock);
    const length = 1000000;
    AttemptProgress copy({int received = 0, bool headers = false}) {
      final progress = AttemptProgress();
      progress.begin(at: 0, length: length, base: Prefix.empty);
      if (headers) progress.headers(at: 0);
      if (received > 0) progress.append(Uint8List(received), at: 0);
      return progress;
    }

    bool due(AttemptProgress progress, String url, {required double at}) {
      clock.set(at);
      return pieces.hurryHedgeDue(progress, url: url, pieceLength: length);
    }

    // No first byte yet: twice the node's usual first byte, kept within 250-600 ms; 250 ms when unknown.
    final unknown = _url(TestEngine.cosov);
    expect(due(copy(), unknown, at: 200), isFalse);
    expect(due(copy(), unknown, at: 260), isTrue);
    final ttfb = {100.0: _url(TestEngine.aliov), 200.0: _url(TestEngine.hk1), 400.0: _url(TestEngine.hk3)};
    for (final MapEntry(key: ms, value: url) in ttfb.entries) {
      pieces.ctx.nodes.firstByte(url, ms: ms);
    }
    expect(due(copy(), ttfb[100]!, at: 240), isFalse);
    expect(due(copy(), ttfb[100]!, at: 260), isTrue, reason: 'budget 250');
    expect(due(copy(), ttfb[200]!, at: 390), isFalse);
    expect(due(copy(), ttfb[200]!, at: 410), isTrue, reason: 'budget 400');
    expect(due(copy(), ttfb[400]!, at: 590), isFalse);
    expect(due(copy(), ttfb[400]!, at: 610), isTrue, reason: 'budget 600, the cap');

    // Bytes stopped arriving: 1 s since the last one, though 80% is in.
    final stopped = copy(received: 800000, headers: true);
    expect(due(stopped, unknown, at: 990), isFalse);
    expect(due(stopped, unknown, at: 1000), isTrue);

    // Slow: 100 ms first byte and 5 MB/s make 300 ms expected for the piece, so a copy is due from 600 ms while
    // under 75% has arrived.
    final measured = _url('cn-hk-eq-01-02.bilivideo.com');
    _measure(pieces.ctx, measured, ttfbMs: 100, bytes: 1000000, ms: 200);
    expect(pieces.ctx.nodes.expectedMs(measured, pieceBytes: length), closeTo(300, 0.5));
    bool slow({required int received, required double at}) {
      final progress = copy(received: received, headers: true);
      progress.append(const [], at: at - 100);
      return due(progress, measured, at: at);
    }

    expect(slow(received: 500000, at: 550), isFalse);
    expect(slow(received: 700000, at: 610), isTrue);
    expect(slow(received: 800000, at: 610), isFalse, reason: 'most of the piece is in');
  });

  test('requests losing their connection together do not ban the node', () async {
    // cosov drops every request of the first moment, as a Wi-Fi blip or a pool of connections torn down at once
    // does. Building the content takes part of the 600 ms. No backup copies, so every loss falls in one moment.
    final cdn = SimCDN(size: 1100000, behaviors: {TestEngine.cosov: const NodeBehavior(failForMs: 600)});
    final config = TestEngine.config.copyWith(hedgeDelayMs: 5000);
    final bans = BanList();
    final banned = <String>[];
    bans.onBan = (node, _, _) => banned.add(node);
    final resolver = Resolver(
      primary: _url(TestEngine.cosov),
      backups: const [],
      mode: CustomNodes([NodeAddress(TestEngine.cosov), NodeAddress(TestEngine.aliov)]),
      bans: bans,
    );
    final ctx = _context(cdn, config: config);
    final bytes = await _read(RangeDownloader(ctx), _mebibyte, resolver);
    _expectBytes(bytes, _slice(cdn, _mebibyte));
    final cosovFailures =
        _snapshot(ctx).nodes.where((node) => node.node == TestEngine.cosov).firstOrNull?.failures ?? 0;
    expect(cosovFailures, greaterThanOrEqualTo(2), reason: 'the test needs requests that fail together');
    expect(banned, isEmpty);
  });

  test('a hurry hedge holds an unmeasured node to the best known one', () {
    final clock = ManualClock();
    final pieces = _pieces(clock, config: TestEngine.config.copyWith(hedgeDelayMs: 900));
    const length = 1000000;
    final unknown = _url(TestEngine.aliov);
    final known = _url('cn-hk-eq-01-02.bilivideo.com');
    // 100 ms first byte and 5 MB/s make 300 ms for the piece.
    _measure(pieces.ctx, known, ttfbMs: 100, bytes: 1000000, ms: 200);
    bool due({required double at, required List<String> candidates}) {
      final progress = AttemptProgress();
      progress.begin(at: 0, length: length, base: Prefix.empty);
      progress.headers(at: 0);
      progress.append(Uint8List(100000), at: at - 100);
      clock.set(at);
      return pieces.hurryHedgeDue(progress, url: unknown, pieceLength: length, candidates: candidates);
    }

    expect(due(at: 550, candidates: [unknown, known]), isFalse);
    expect(due(at: 610, candidates: [unknown, known]), isTrue, reason: 'twice the 300 ms the known node needs');
    expect(
      due(at: 1790, candidates: [unknown]),
      isFalse,
      reason: 'no node known: twice the 900 ms hedge delay, as before',
    );
    expect(due(at: 1810, candidates: [unknown]), isTrue);
  });

  test('in a hurry an unmeasured node that trickles gets a copy soon', () async {
    final cdn = SimCDN(size: 600000, behaviors: {TestEngine.aliov: const NodeBehavior(bytesPerSecond: 50000)});
    final config = TestEngine.slowConfig.copyWith(hedgeDelayMs: 900);
    final ctx = _context(RecordingTransport(cdn), config: config);
    final resolver = Resolver(
      primary: _url(TestEngine.cosov),
      backups: const [],
      mode: CustomNodes([NodeAddress(TestEngine.aliov), NodeAddress(TestEngine.cosov)]),
      bans: BanList(),
    );
    final cosovURL = _url(TestEngine.cosov);
    _measure(ctx, cosovURL, ttfbMs: 20, bytes: 4000000, ms: 1000);
    final started = Stopwatch()..start();
    final output = await PieceDownloader(ctx).download(
      piece: ByteRange(0, 262143),
      index: 0,
      resolver: resolver,
      preferred: [_url(TestEngine.aliov)],
      mode: PieceMode.normal,
      priority: 50,
      hurry: () => true,
    );
    expect(output.url, cosovURL);
    expect(started.elapsedMilliseconds, lessThan(1200), reason: 'the 1.8 s of twice the hedge delay');
  });

  group('a cold range', () {
    // Two fast nodes both slow over a part of the file they have not served lately, a third one normal.
    final coldSpan = ByteRange(2000000, 4000000);
    final hurryRange = ByteRange(2000000, 3048575);

    // The first byte of a cold request takes 1.5 s and the transfer pauses between chunks; the timeouts leave
    // that to the copies. Room for three copies of every 64 KiB piece of a 1 MiB range.
    final coldConfig = TestEngine.slowConfig.copyWith(
      firstByteTimeoutMs: 5500,
      attemptTimeoutMs: 15000,
      fixedConcurrency: 64,
    );

    Future<(double, List<Request>)> coldRangeRun({bool Function()? hurry, RipperConfig? config}) async {
      final cold = NodeBehavior(coldRange: coldSpan, coldRangeFirstByteMs: 1500, coldRangeBytesPerSecond: 100000);
      final cdn = SimCDN(
        size: 6000000,
        behaviors: {
          TestEngine.cosov: cold,
          _akamai: cold,
          TestEngine.aliov: const NodeBehavior(bytesPerSecond: 4000000),
        },
      );
      final transport = RecordingTransport(cdn);
      final cosovURL = _url(TestEngine.cosov);
      final resolver = Resolver(
        primary: cosovURL,
        backups: const [],
        mode: CustomNodes([NodeAddress(TestEngine.cosov), NodeAddress(_akamai), NodeAddress(TestEngine.aliov)]),
        bans: BanList(),
      );
      expect(resolver.urls().map(NodeCatalog.nodeKey), [TestEngine.cosov, _akamai, TestEngine.aliov]);
      final downloader = RangeDownloader(_context(transport, config: config ?? coldConfig));
      await _read(downloader, _mebibyte, resolver);
      expect(resolver.speed(_url(TestEngine.cosov)), greaterThan(resolver.speed(_url(TestEngine.aliov))));
      final asked = transport.requests.length;
      final started = Stopwatch()..start();
      final bytes = await _read(downloader, hurryRange, resolver, hurry: hurry);
      final seconds = started.elapsedMicroseconds / 1e6;
      _expectBytes(bytes, _slice(cdn, hurryRange));
      return (seconds, transport.requests.sublist(asked));
    }

    // Requests per piece, by the piece's end: a backup copy resumes partway, but ends where the piece ends.
    Map<int, List<String>> copiesByPiece(List<Request> requests) {
      final pieces = <int, List<String>>{};
      for (final request in requests) {
        (pieces[request.range.end] ??= []).add(request.node);
      }
      return pieces;
    }

    test('on the two fastest nodes is fetched from a third in a hurry', () async {
      final (seconds, requests) = await coldRangeRun(hurry: () => true);
      expect(seconds, lessThan(1.4), reason: 'the old path needs at least 1.5 s');
      final pieces = copiesByPiece(requests);
      final rescued = pieces.values.where(
        (nodes) => [TestEngine.cosov, _akamai].contains(nodes.first) && nodes.contains(TestEngine.aliov),
      );
      expect(rescued, isNotEmpty, reason: '$pieces');
      expect(pieces.values.any((nodes) => nodes.length == 3), isTrue, reason: 'a third copy reached aliov: $pieces');
      expect(pieces.values.every((nodes) => nodes.length <= 3), isTrue, reason: '$pieces');
    });

    // Review focus 4: outside a hurry a piece never gets a third copy.
    test('without a hurry gets no third copy', () async {
      final (_, requests) = await coldRangeRun();
      final pieces = copiesByPiece(requests);
      expect(pieces.values.every((nodes) => nodes.length <= 2), isTrue, reason: '$pieces');
    });

    test('with hurry off in the config keeps the old timing', () async {
      final (seconds, requests) = await coldRangeRun(hurry: () => true, config: coldConfig.copyWith(hurry: false));
      expect(seconds, greaterThanOrEqualTo(1.5));
      expect(
        copiesByPiece(requests).values.every((nodes) => nodes.length <= 2),
        isTrue,
        reason: '${requests.map((request) => '${request.node} ${request.range}')}',
      );
    });
  });

  group('a busy node', () {
    // cosov is sending its first piece slowly, so its later requests wait behind it and miss the first-byte
    // timeout. That is the node being busy, not silent: it must not be banned.
    SimCDN slowBusyCosov({required int size, required double bytesPerSecond}) => SimCDN(
      size: size,
      behaviors: {
        TestEngine.cosov: NodeBehavior(
          bytesPerSecond: bytesPerSecond,
          coldFirstByteMs: 2500,
          lateFirstByteFromRequest: 2,
        ),
      },
    );

    test('is not banned for silent requests', () async {
      final cdn = slowBusyCosov(size: 5000000, bytesPerSecond: 220000);
      // Not Resolver's default list: the first piece of cosov finishing heals its strikes, so only the ban event
      // itself shows that the node was ever banned.
      final bans = BanList();
      final banned = <String>[];
      bans.onBan = (node, _, _) => banned.add(node);
      final resolver = Resolver(primary: TestEngine.primary, backups: const [], mode: NodeMode.overseas, bans: bans);
      final config = TestEngine.slowConfig.copyWith(hedgeDelayMs: 5000, fixedConcurrency: 16);
      final range = ByteRange(0, 4 * 1048576 - 1);
      final bytes = await _collect(cdn, range, resolver: resolver, config: config);
      _expectBytes(bytes, _slice(cdn, range));
      expect(
        _countOf(cdn.requests, TestEngine.cosov),
        greaterThanOrEqualTo(2),
        reason: 'the test needs requests that wait behind the first one',
      );
      expect(banned, isEmpty, reason: 'a node that is sending other pieces was banned');
    });

    test('that never answers new requests still lets the range finish', () async {
      final cdn = slowBusyCosov(size: 9000000, bytesPerSecond: 1600000);
      final config = TestEngine.slowConfig.copyWith(hedgeDelayMs: 5000);
      final ctx = TestEngine.context(cdn, config: config);
      final cosovURL = _url(TestEngine.cosov);
      var sawFull = false;
      final watcher = Timer.periodic(const Duration(milliseconds: 10), (_) {
        if (ctx.nodes.isFull(cosovURL)) sawFull = true;
      });
      addTearDown(watcher.cancel);
      final range = ByteRange(0, 8 * 1048576 - 1);
      final started = Stopwatch()..start();
      final bytes = await _read(RangeDownloader(ctx), range, TestEngine.resolver());
      _expectBytes(bytes, _slice(cdn, range));
      expect(
        started.elapsedMilliseconds,
        lessThan(6000),
        reason: "cosov's own piece takes about 1 s; the bound only catches an endless loop",
      );
      expect(sawFull, isTrue, reason: 'cosov is capped at the one piece it was sending');
    });
  });

  group('an HTTP/1.1 host', () {
    // Akamai, the fastest node and HTTP/1.1, then cosov and aliov. Scaled down from the phone's 8 connections to 4.
    Resolver akamaiFirstResolver() {
      final resolver = Resolver(
        primary: _url(TestEngine.cosov),
        backups: const [],
        mode: CustomNodes([NodeAddress(_akamai), NodeAddress(TestEngine.cosov), NodeAddress(TestEngine.aliov)]),
        bans: BanList(),
      );
      resolver.success(_url(_akamai), bps: 8000000);
      resolver.success(_url(TestEngine.cosov), bps: 2000000);
      resolver.success(_url(TestEngine.aliov), bps: 2000000);
      expect(resolver.rangeCandidates().map(NodeCatalog.nodeKey), [_akamai, TestEngine.cosov, TestEngine.aliov]);
      return resolver;
    }

    // The phone on 2026-10-17: by speed Akamai got most pieces of the video and audio ranges, 48-61 requests at
    // once over URLSession's 8 connections, and 38 timed out waiting for one while the mirrors sat idle.
    test('sends requests beyond its connections to nodes with room', () async {
      final cdn = SimCDN(
        size: 4000000,
        behaviors: {
          _akamai: const NodeBehavior(bytesPerSecond: 1000000),
          TestEngine.cosov: const NodeBehavior(bytesPerSecond: 1000000),
          TestEngine.aliov: const NodeBehavior(bytesPerSecond: 1000000),
        },
        connectionsPerHost: 4,
      );
      final config = TestEngine.slowConfig.copyWith(fixedConcurrency: 24);
      final ctx = TestEngine.context(cdn, config: config);
      final downloader = RangeDownloader(ctx);
      final resolver = akamaiFirstResolver();
      // Two ranges placed at the same moment, as a track's prefetch and the other track's read are.
      final ranges = [ByteRange(0, 1048575), ByteRange(2000000, 3048575)];
      await Future.wait([
        for (final range in ranges)
          _read(downloader, range, resolver).then((bytes) => _expectBytes(bytes, _slice(cdn, range))),
      ]);
      expect(cdn.peakWaiting(_akamai), 0, reason: "requests waited behind Akamai's connections");
      expect(_countOf(cdn.requests, _akamai), greaterThanOrEqualTo(4), reason: 'Akamai still takes what it can carry');
      expect(_snapshot(ctx).failures, 0);
    });

    test('is skipped by a backup copy while another node has room', () async {
      final cdn = SimCDN(
        size: 600000,
        behaviors: {TestEngine.cosov: const NodeBehavior(bytesPerSecond: 200000)},
        connectionsPerHost: 4,
      );
      final transport = RecordingTransport(cdn);
      final ctx = _context(transport, config: TestEngine.slowConfig);
      final akamaiURL = _url(_akamai);
      // Other pieces hold all four of Akamai's connections.
      for (var index = 0; index < 4; index++) {
        ctx.nodes.begin(akamaiURL);
      }
      final output = await PieceDownloader(ctx).download(
        piece: ByteRange(0, 399999),
        index: 0,
        resolver: akamaiFirstResolver(),
        preferred: [_url(TestEngine.cosov)],
        mode: PieceMode.normal,
        priority: 50,
      );
      expect(output.url, _url(TestEngine.aliov));
      expect(
        transport.requests.any((request) => request.node == _akamai),
        isFalse,
        reason: '${transport.requests.map((request) => request.node)}',
      );
    });

    test('still takes a backup copy when every node is full', () async {
      final cdn = SimCDN(
        size: 600000,
        behaviors: {TestEngine.cosov: const NodeBehavior(bytesPerSecond: 200000)},
        connectionsPerHost: 4,
      );
      final ctx = _context(RecordingTransport(cdn), config: TestEngine.slowConfig);
      final akamaiURL = _url(_akamai);
      final aliovURL = _url(TestEngine.aliov);
      for (var index = 0; index < 4; index++) {
        ctx.nodes.begin(akamaiURL);
      }
      // aliov went silent while sending a piece, so it is capped at that one.
      ctx.nodes
        ..begin(aliovURL)
        ..firstByte(aliovURL, ms: 5)
        ..silent(aliovURL, waitedMs: 5500);
      expect(ctx.nodes.isFull(aliovURL), isTrue);
      final started = Stopwatch()..start();
      final output = await PieceDownloader(ctx).download(
        piece: ByteRange(0, 399999),
        index: 0,
        resolver: akamaiFirstResolver(),
        preferred: [_url(TestEngine.cosov)],
        mode: PieceMode.normal,
        priority: 50,
      );
      expect(output.url, isNot(_url(TestEngine.cosov)));
      expect(started.elapsedMilliseconds, lessThan(1500), reason: 'cosov alone needs 2 s');
    });
  });

  // The phone's start on 2026-10-17: cosov had the higher speed per connection, so backups went there and waited
  // 661-673 ms for a first byte while Akamai answered in 15-24 ms.
  test('in a hurry a backup copy goes to the node expected to finish first', () async {
    final cdn = SimCDN(
      size: 600000,
      behaviors: {
        TestEngine.aliov: const NodeBehavior(firstByteMs: 1500),
        TestEngine.cosov: const NodeBehavior(firstByteMs: 400),
        _akamai: const NodeBehavior(firstByteMs: 15),
      },
    );
    final transport = RecordingTransport(cdn);
    final config = TestEngine.slowConfig.copyWith(firstByteTimeoutMs: 5500);
    final ctx = _context(transport, config: config);
    final resolver = Resolver(
      primary: _url(TestEngine.cosov),
      backups: const [],
      mode: CustomNodes([NodeAddress(TestEngine.aliov), NodeAddress(TestEngine.cosov), NodeAddress(_akamai)]),
      bans: BanList(),
    );
    void measure(String node, {required double ttfbMs, required double bps}) {
      final url = _url(node);
      resolver.success(url, bps: bps);
      _measure(ctx, url, ttfbMs: ttfbMs, bytes: bps.toInt(), ms: 1000);
    }

    measure(TestEngine.cosov, ttfbMs: 660, bps: 8000000);
    measure(_akamai, ttfbMs: 20, bps: 4000000);
    final output = await PieceDownloader(ctx).download(
      piece: ByteRange(0, 65535),
      index: 0,
      resolver: resolver,
      preferred: [_url(TestEngine.aliov)],
      mode: PieceMode.normal,
      priority: 50,
      hurry: () => true,
    );
    expect(output.url, _url(_akamai));
    expect(
      transport.requests.any((request) => request.node == TestEngine.cosov),
      isFalse,
      reason: '${transport.requests.map((request) => request.node)}',
    );
  });

  test('outside a hurry backup copies keep the speed order', () async {
    final cdn = SimCDN(size: 600000, behaviors: {TestEngine.aliov: const NodeBehavior(firstByteMs: 1500)});
    final transport = RecordingTransport(cdn);
    final ctx = _context(transport, config: TestEngine.slowConfig);
    final resolver = Resolver(
      primary: _url(TestEngine.cosov),
      backups: const [],
      mode: CustomNodes([NodeAddress(TestEngine.aliov), NodeAddress(TestEngine.cosov), NodeAddress(_akamai)]),
      bans: BanList(),
    );
    resolver.success(_url(TestEngine.cosov), bps: 8000000);
    resolver.success(_url(_akamai), bps: 4000000);
    _measure(ctx, _url(_akamai), ttfbMs: 20, bytes: 4000000, ms: 1000);
    final output = await PieceDownloader(ctx).download(
      piece: ByteRange(0, 65535),
      index: 0,
      resolver: resolver,
      preferred: [_url(TestEngine.aliov)],
      mode: PieceMode.normal,
      priority: 50,
    );
    expect(output.url, _url(TestEngine.cosov));
  });
}
