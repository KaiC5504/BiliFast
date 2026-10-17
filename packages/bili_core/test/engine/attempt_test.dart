// Port of BiliNative's AttemptTests.swift.

import 'dart:typed_data';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bili_core/src/engine/attempt.dart';
import 'package:bili_core/src/engine/connection_pool.dart';
import 'package:bili_core/src/engine/engine_stats.dart';
import 'package:bili_core/src/engine/meter.dart';
import 'package:bili_core/src/engine/resolver.dart';
import 'package:test/test.dart';

import 'support/sim_cdn.dart';

String _url(String node) => TestEngine.primary.replaceAll('upos-sz-mirrorcos.bilivideo.com', node);

Future<AttemptOutput> _run(
  EngineContext ctx, {
  required String node,
  required ByteRange range,
  Resolver? resolver,
  AttemptProgress? progress,
  Prefix Function()? resumeBase,
  CancelToken? cancel,
}) => AttemptRunner(ctx).runAt(
  _url(node),
  piece: range,
  progress: progress ?? AttemptProgress(),
  resolver: resolver ?? TestEngine.resolver(),
  priority: 0,
  queueClass: QueueClass.ordinary,
  resumeBase: resumeBase ?? () => Prefix.empty,
  cancel: cancel,
);

Uint8List _slice(SimCDN cdn, int start, int end) => Uint8List.sublistView(cdn.content, start, end + 1);

EngineSnapshot _snapshot(EngineContext ctx) => ctx.stats.snapshot(concurrency: ctx.pool.limit, nodeStates: const []);

void main() {
  test('delivers exact bytes and measures the node', () async {
    final cdn = SimCDN(size: 300000);
    final resolver = TestEngine.resolver();
    final range = ByteRange(1000, 200999);
    final output = await _run(TestEngine.context(cdn), node: TestEngine.cosov, range: range, resolver: resolver);
    expect(output.bytes, _slice(cdn, 1000, 200999));
    expect(output.total, 300000);
    expect(resolver.speed(_url(TestEngine.cosov)), greaterThan(0));
  });

  test('rejects wrong status and range', () async {
    final cdn = SimCDN(
      size: 100000,
      behaviors: {
        TestEngine.cosov: const NodeBehavior(status: 200),
        TestEngine.aliov: const NodeBehavior(wrongRange: true),
      },
    );
    for (final node in [TestEngine.cosov, TestEngine.aliov]) {
      await expectLater(
        _run(TestEngine.context(cdn), node: node, range: ByteRange(0, 9999)),
        throwsA(isA<RipperError>().having((error) => error.status, 'status', isNotNull)),
        reason: 'expected a failure for $node',
      );
    }
  });

  test('a missing Content-Range is a bad response', () async {
    final cdn = SimCDN(size: 100000, behaviors: {TestEngine.cosov: const NodeBehavior(omitContentRange: true)});
    await expectLater(
      _run(TestEngine.context(cdn), node: TestEngine.cosov, range: ByteRange(0, 9999)),
      throwsA(const RipperError.badResponse(206)),
    );
  });

  test('a truncated body is a length mismatch', () async {
    final cdn = SimCDN(size: 100000, behaviors: {TestEngine.cosov: const NodeBehavior(truncateAfter: 20000)});
    final ctx = TestEngine.context(cdn);
    final sink = MemorySink();
    ctx.logger.add(sink);
    await expectLater(
      _run(ctx, node: TestEngine.cosov, range: ByteRange(0, 49999)),
      throwsA(const RipperError.lengthMismatch(got: 20000, expected: 50000)),
    );
    final failed = sink.events.where((event) => event.msg == 'attempt failed').firstOrNull;
    expect(failed?.f['range'], const LogString('0-49999'));
    expect(failed?.f['node'], const LogString(TestEngine.cosov));
    expect(failed?.f['bytes'], const LogInt(20000));
  });

  test('an overlong body is a length mismatch', () async {
    final cdn = SimCDN(size: 100000, behaviors: {TestEngine.cosov: const NodeBehavior(extraBytes: 5000)});
    await expectLater(
      _run(TestEngine.context(cdn), node: TestEngine.cosov, range: ByteRange(0, 49999)),
      throwsA(const RipperError.lengthMismatch(got: 55000, expected: 50000)),
    );
  });

  test('the advertised total is passed on', () async {
    final cdn = SimCDN(size: 100000, behaviors: {TestEngine.cosov: const NodeBehavior(totalSize: 500000)});
    final output = await _run(TestEngine.context(cdn), node: TestEngine.cosov, range: ByteRange(0, 9999));
    expect(output.total, 500000);
  });

  test('timeouts', () async {
    final cdn = SimCDN(
      size: 100000,
      behaviors: {
        TestEngine.cosov: const NodeBehavior(firstByteMs: 1000),
        TestEngine.aliov: const NodeBehavior(stallAfter: 16384),
      },
    );
    await expectLater(
      _run(TestEngine.context(cdn), node: TestEngine.cosov, range: ByteRange(0, 9999)),
      throwsA(const RipperError(RipperErrorKind.firstByteTimeout)),
    );
    await expectLater(
      _run(TestEngine.context(cdn), node: TestEngine.aliov, range: ByteRange(0, 49999)),
      throwsA(const RipperError(RipperErrorKind.stalled)),
    );
  });

  test('attempt timeout', () async {
    final config = TestEngine.slowConfig.copyWith(attemptTimeoutMs: 400);
    final cdn = SimCDN(size: 100000, behaviors: {TestEngine.cosov: const NodeBehavior(bytesPerSecond: 50000)});
    final ctx = TestEngine.context(cdn, config: config);
    await expectLater(
      _run(ctx, node: TestEngine.cosov, range: ByteRange(0, 99999)),
      throwsA(const RipperError(RipperErrorKind.attemptTimeout)),
    );
    expect(ctx.pool.active, 0);
  });

  test('a silent node after headers counts as slow', () async {
    final manual = ManualClock(100000);
    final auto = AutoConcurrency(clock: manual.clock);
    auto.demand(active: 8, limit: 8, queued: 1);
    manual.advance(5000);
    expect(auto.threads, 8);
    final cdn = SimCDN(size: 100000, behaviors: {TestEngine.cosov: const NodeBehavior(stallAfter: 0)});
    await expectLater(
      _run(
        TestEngine.context(cdn, auto: auto),
        node: TestEngine.cosov,
        range: ByteRange(0, 9999),
      ),
      throwsA(const RipperError(RipperErrorKind.stalled)),
    );
    expect(auto.threads, 12);
  }, skip: 'needs AutoConcurrency port');

  test('the resume base is prepended', () async {
    final cdn = SimCDN(size: 100000);
    final range = ByteRange(0, 99999);
    final base = Prefix(bytes: 40000, chunks: [_slice(cdn, 0, 39999)]);
    final output = await _run(TestEngine.context(cdn), node: TestEngine.cosov, range: range, resumeBase: () => base);
    expect(output.bytes, cdn.content);
  });

  test('a resume asks only for the missing tail', () async {
    final cdn = SimCDN(size: 100000);
    final base = Prefix(bytes: 40000, chunks: [_slice(cdn, 0, 39999)]);
    final progress = AttemptProgress();
    final output = await _run(
      TestEngine.context(cdn),
      node: TestEngine.cosov,
      range: ByteRange(0, 99999),
      progress: progress,
      resumeBase: () => base,
    );
    expect(output.bytes.length, 100000);
    expect(progress.received, 60000);
  });

  test('short transfers are not speed samples', () async {
    final cdn = SimCDN(size: 300000);
    final ctx = TestEngine.context(cdn);
    final resolver = TestEngine.resolver();
    final target = _url(TestEngine.cosov);
    await _run(ctx, node: TestEngine.cosov, range: ByteRange(0, Meter.sampleMinBytes - 2), resolver: resolver);
    expect(resolver.speed(target), 0);
    expect(ctx.meter.connectionBps, 0);
    await _run(ctx, node: TestEngine.cosov, range: ByteRange(0, Meter.sampleMinBytes - 1), resolver: resolver);
    expect(resolver.speed(target), greaterThan(0));
    expect(ctx.meter.connectionBps, greaterThan(0));
    final stats = _snapshot(ctx);
    expect(stats.requests, 2);
    expect(stats.failures, 0);
    expect(ctx.pool.active, 0);
  });

  test('a refusing node is struck', () async {
    final cdn = SimCDN(size: 100000, behaviors: {TestEngine.cosov: const NodeBehavior(failForMs: 60000)});
    final ctx = TestEngine.context(cdn);
    final resolver = TestEngine.resolver();
    final target = _url(TestEngine.cosov);
    expect(resolver.rescueCandidates(), contains(target));
    await expectLater(
      _run(ctx, node: TestEngine.cosov, range: ByteRange(0, 9999), resolver: resolver),
      throwsA(isA<ConnectionLost>()),
    );
    expect(resolver.rescueCandidates(), isNot(contains(target)));
    final stats = _snapshot(ctx);
    expect(stats.failures, 1);
    expect(stats.nodes.where((node) => node.node == TestEngine.cosov).firstOrNull?.failures, 1);
    expect(ctx.pool.active, 0);
  });

  test('a bad response strikes the node', () async {
    final cdn = SimCDN(size: 100000, behaviors: {TestEngine.cosov: const NodeBehavior(wrongRange: true)});
    final resolver = TestEngine.resolver();
    await expectLater(
      _run(TestEngine.context(cdn), node: TestEngine.cosov, range: ByteRange(0, 9999), resolver: resolver),
      throwsA(const RipperError.badResponse(206)),
    );
    expect(resolver.rescueCandidates(), isNot(contains(_url(TestEngine.cosov))));
  });

  test('pushback steps the connection count down', () async {
    final auto = AutoConcurrency();
    auto.newSession();
    expect(auto.threads, 16);
    final cdn = SimCDN(size: 100000, behaviors: {TestEngine.cosov: const NodeBehavior(status: 429)});
    await expectLater(
      _run(
        TestEngine.context(cdn, auto: auto),
        node: TestEngine.cosov,
        range: ByteRange(0, 9999),
      ),
      throwsA(const RipperError.badResponse(429)),
    );
    expect(auto.threads, 12);
  }, skip: 'needs AutoConcurrency port');

  test('a cancelled copy is sampled but not struck', () async {
    final cdn = SimCDN(size: 300000, behaviors: {TestEngine.cosov: const NodeBehavior(bytesPerSecond: 200000)});
    final ctx = TestEngine.context(cdn, config: TestEngine.slowConfig);
    final sink = MemorySink();
    ctx.logger.add(sink);
    final resolver = TestEngine.resolver();
    final progress = AttemptProgress();
    final target = _url(TestEngine.cosov);
    final cancel = CancelToken();
    final task = _run(
      ctx,
      node: TestEngine.cosov,
      range: ByteRange(0, 299999),
      resolver: resolver,
      progress: progress,
      cancel: cancel,
    );
    final giveUp = Stopwatch()..start();
    while (progress.received < Meter.sampleMinBytes && giveUp.elapsedMilliseconds < 5000) {
      await sleepMs(5);
    }
    cancel.cancel();
    await expectLater(task, throwsA(isA<CancelledException>()));
    expect(resolver.speed(target), greaterThan(0));
    expect(resolver.rescueCandidates(), contains(target));
    final stats = _snapshot(ctx);
    expect(stats.requests, 1);
    expect(stats.failures, 0);
    expect(stats.duplicateBytes, greaterThanOrEqualTo(Meter.sampleMinBytes));
    expect(ctx.pool.active, 0);
    final cancelled = sink.events.where((event) => event.msg == 'attempt cancelled').firstOrNull;
    expect(cancelled?.f['range'], const LogString('0-299999'));
    expect(cancelled?.f['node'], const LogString(TestEngine.cosov));
    expect(sink.events.where((event) => event.msg == 'attempt failed'), isEmpty);
    final gap = ByteRange(200000, 299999);
    resolver.failure(target, receivedBytes: 0, range: gap);
    resolver.failure(target, receivedBytes: 0, range: gap);
    expect(
      resolver.allows(target),
      isTrue,
      reason: 'a node that streamed bytes is up, so its empty replies are positional',
    );
  });

  test('the meter smooths and sizes pieces', () {
    final meter = Meter();
    expect(meter.adaptiveMinChunk(base: 65536, rangeLength: 4 << 20, pieceLimit: 16, hostCount: 4), 65536);
    expect(meter.hedgeDelayMs(900), 900);
    meter.record(bytes: Meter.sampleMinBytes - 1, elapsedMs: 10);
    expect(meter.connectionBps, 0);
    meter.record(bytes: 1000000, elapsedMs: 200);
    expect(meter.connectionBps, closeTo(5000000, 0.1));
    meter.record(bytes: 1000000, elapsedMs: 1000);
    expect(meter.connectionBps, closeTo(3800000, 0.1));
    expect(meter.pieceMs, closeTo(440, 0.001));
    expect(meter.adaptiveMinChunk(base: 65536, rangeLength: 4 << 20, pieceLimit: 16, hostCount: 4), 1 << 20);
    expect(meter.adaptiveMinChunk(base: 65536, rangeLength: 1 << 20, pieceLimit: 16, hostCount: 6), 174763);
    expect(meter.hedgeDelayMs(900), 660);
    expect(meter.hedgeDelayMs(500), 500);
  });

  test('the duplicate share', () {
    final stats = EngineStats();
    stats.delivered(300);
    stats.failed(TestEngine.cosov, wastedBytes: 100, cancelled: true);
    final snapshot = stats.snapshot(concurrency: 8, nodeStates: const []);
    expect(snapshot.duplicateShare, closeTo(0.25, 1e-9));
    expect(snapshot.failures, 0);
  });
}
