import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bili_core/src/engine/attempt.dart';
import 'package:bili_core/src/engine/connection_pool.dart';
import 'package:bili_core/src/engine/node_stats.dart';
import 'package:test/test.dart';

import 'support/sim_cdn.dart';

/// Swift's `AttemptTests.url`.
String _url(String node) => TestEngine.primary.replaceAll('upos-sz-mirrorcos.bilivideo.com', node);

/// Swift's `AttemptTests.run`.
Future<AttemptOutput> _run(
  EngineContext ctx, {
  required String node,
  required ByteRange range,
  AttemptProgress? progress,
  CancelToken? cancel,
}) => AttemptRunner(ctx).runAt(
  _url(node),
  piece: range,
  progress: progress ?? AttemptProgress(),
  resolver: TestEngine.resolver(),
  priority: 0,
  queueClass: QueueClass.ordinary,
  cancel: cancel,
);

/// Polls every 5 ms for up to five seconds, as the Swift tests' `giveUp` loops.
Future<void> _waitFor(bool Function() condition) async {
  final giveUp = DateTime.now().add(const Duration(seconds: 5));
  while (!condition() && DateTime.now().isBefore(giveUp)) {
    await sleepMs(5);
  }
}

void main() {
  test('expected time shares the node beyond its measured load', () {
    final stats = NodeStats();
    const url = 'https://upos-sz-mirrorcosov.bilivideo.com/v.m4s';
    expect(stats.expectedMs(url, pieceBytes: 1000000), isNull);
    stats
      ..begin(url)
      ..firstByte(url, ms: 100)
      ..body(url, bytes: 1000000, ms: 500)
      ..end(url, receiving: true);
    // 2 MB/s on one connection, ttfb 100 ms, load blended from 1 in flight; width = max(4, load) = 4.
    expect(stats.expectedMs(url, pieceBytes: 1000000)!, closeTo(600, 0.5));
    // Six more in flight: 2 MB/s × 4 / 7 per connection.
    expect(
      stats.expectedMs(url, pieceBytes: 1000000, extraInflight: 6)!,
      closeTo(100 + 1000000 / (2000000 * 4.0 / 7) * 1000, 0.5),
    );
  });

  test('small bodies say nothing about speed', () {
    final stats = NodeStats();
    const url = 'https://a.example/v';
    stats.body(url, bytes: 16 * 1024, ms: 10);
    expect(stats.isKnown(url), isFalse);
  });

  test('silence while receiving caps the node, otherwise raises its first-byte time', () {
    final stats = NodeStats();
    const busy = 'https://akam.example/v';
    const idle = 'https://cosov.example/v';
    stats
      ..begin(busy)
      ..firstByte(busy, ms: 50) // one transfer receiving
      ..begin(busy)
      ..begin(busy) // two more waiting
      ..silent(busy, waitedMs: 5500);
    expect(stats.isBusy(busy), isTrue);
    expect(stats.isFull(busy), isTrue, reason: 'limit = what it was receiving (1), and 3 are in flight');
    expect(stats.ttfbMs(busy), closeTo(50, 0.01), reason: "a queued request is not the node's first-byte time");
    stats.silent(idle, waitedMs: 2000);
    expect(stats.ttfbMs(idle), closeTo(2000, 0.01));
  });

  test('outrun and crawl only ever lower the estimate', () {
    final stats = NodeStats();
    const url = 'https://aliov.example/v';
    stats
      ..begin(url)
      ..firstByte(url, ms: 40)
      ..body(url, bytes: 4000000, ms: 1000)
      ..end(url, receiving: true)
      ..outrun(url, waitedMs: 30); // shorter than the known ttfb: ignored
    expect(stats.ttfbMs(url), closeTo(40, 0.01));
    stats.outrun(url, waitedMs: 1040); // blended up
    expect(stats.ttfbMs(url), closeTo(40 * 0.7 + 1040 * 0.3, 0.01));
    stats.crawl(url, bytes: 50000, ms: 200); // under 300 ms: ignored
    expect(stats.bps(url), closeTo(4000000, 1));
    stats.crawl(url, bytes: 100000, ms: 1000); // 100 KB/s trickle
    expect(stats.bps(url), closeTo(4000000 * 0.7 + 100000 * 0.3, 1));
  });

  test('records are keyed by node, not by address', () {
    final stats = NodeStats()..begin('https://a.example/one.m4s?sign=1');
    expect(stats.inflight('https://a.example/two.m4s?sign=2'), 1);
    expect(stats.inflight('https://b.example/one.m4s?sign=1'), 0);
    stats
      ..end('https://a.example/other.m4s', receiving: false)
      ..end('https://a.example/other.m4s', receiving: true);
    expect(stats.inflight('https://a.example/one.m4s'), 0, reason: 'an unmatched end never goes below zero');
  });

  test('reset forgets measurements but not running transfers', () {
    final stats = NodeStats();
    const url = 'https://a.example/v';
    stats
      ..begin(url)
      ..firstByte(url, ms: 80)
      ..body(url, bytes: 1000000, ms: 500)
      ..begin(url)
      ..silent(url, waitedMs: 1000)
      ..reset();
    expect(stats.isKnown(url), isFalse);
    expect(stats.ttfbMs(url), 0);
    expect(stats.inflight(url), 2);
    expect(stats.isBusy(url), isTrue);
    expect(stats.isFull(url), isFalse, reason: 'the limit learnt on the old path is dropped');
    stats
      ..end(url, receiving: true)
      ..end(url, receiving: false);
    expect(stats.inflight(url), 0);
    expect(stats.isBusy(url), isFalse);
  });

  test("Akamai is full at the transport's connections per host from the start", () {
    final stats = NodeStats(connectionsPerHost: 8);
    const akamai = 'https://upos-hz-mirrorakam.akamaized.net/v.m4s';
    const mirror = 'https://upos-sz-mirrorcosov.bilivideo.com/v.m4s';
    for (var index = 0; index < 7; index++) {
      stats
        ..begin(akamai)
        ..begin(mirror);
    }
    expect(stats.isFull(akamai), isFalse);
    expect(stats.isFull(akamai, extraInflight: 1), isTrue);
    stats
      ..begin(akamai)
      ..begin(mirror);
    expect(stats.isFull(akamai), isTrue, reason: 'a ninth request would wait inside the transport');
    expect(stats.isFull(mirror), isFalse, reason: 'HTTP/2 sends them all at once over one connection');
    stats.reset();
    expect(stats.isFull(akamai), isTrue, reason: "a network change does not lift the transport's limit");
    expect(NodeStats().isFull(akamai), isFalse, reason: 'no limit when the transport has none');
  });

  test('begin takes the first node with room', () {
    final stats = NodeStats(connectionsPerHost: 1);
    const akamai = 'https://upos-hz-mirrorakam.akamaized.net/v.m4s';
    const mirror = 'https://upos-sz-mirrorcosov.bilivideo.com/v.m4s';
    expect(stats.beginFirstOpen([akamai, mirror]), akamai);
    expect(stats.beginFirstOpen([akamai, mirror]), mirror);
    expect(stats.beginFirstOpen([akamai]), akamai, reason: 'the first one when every node is full');
    expect(stats.inflight(akamai), 2);
    expect(stats.inflight(mirror), 1);
  });

  test('the runner feeds the stats', () async {
    final cdn = SimCDN(size: 400000, behaviors: {TestEngine.aliov: const NodeBehavior(firstByteMs: 1000)});
    final ctx = TestEngine.context(cdn);
    final fast = _url(TestEngine.cosov);
    final silent = _url(TestEngine.aliov);

    await _run(ctx, node: TestEngine.cosov, range: ByteRange(0, 299999));
    expect(ctx.nodes.isKnown(fast), isTrue);
    expect(ctx.nodes.ttfbMs(fast), greaterThan(0));
    expect(ctx.nodes.inflight(fast), 0);
    expect(ctx.nodes.isBusy(fast), isFalse);

    await expectLater(
      _run(ctx, node: TestEngine.aliov, range: ByteRange(0, 299999)),
      throwsA(isA<RipperError>().having((error) => error.kind, 'kind', RipperErrorKind.firstByteTimeout)),
    );
    expect(ctx.nodes.ttfbMs(silent), greaterThanOrEqualTo(TestEngine.config.firstByteTimeoutMs));
    expect(ctx.nodes.isKnown(silent), isFalse);
    expect(ctx.nodes.inflight(silent), 0);
    expect(ctx.nodes.isBusy(silent), isFalse);
  });

  test('an outrun copy cancelled before any byte raises the first-byte time', () async {
    final config = TestEngine.slowConfig.copyWith(firstByteTimeoutMs: 5000);
    final cdn = SimCDN(size: 300000, behaviors: {TestEngine.cosov: const NodeBehavior(firstByteMs: 2000)});
    final ctx = TestEngine.context(cdn, config: config);
    final url = _url(TestEngine.cosov);
    ctx.nodes
      ..begin(url)
      ..firstByte(url, ms: 10)
      ..end(url, receiving: true);
    final progress = AttemptProgress();
    final cancel = CancelToken();
    final task = _run(ctx, node: TestEngine.cosov, range: ByteRange(0, 99999), progress: progress, cancel: cancel);
    await _waitFor(() => ctx.nodes.inflight(url) > 0);
    await sleepMs(200);
    progress.outrun = true;
    cancel.cancel();
    await expectLater(task, throwsA(isA<CancelledException>()));
    expect(ctx.nodes.ttfbMs(url), greaterThan(40), reason: '10 ms blended with the 200 ms or more it had waited');
    expect(ctx.nodes.inflight(url), 0);
  });

  test('an outrun copy cancelled while crawling lowers the speed', () async {
    final cdn = SimCDN(size: 300000, behaviors: {TestEngine.cosov: const NodeBehavior(bytesPerSecond: 100000)});
    final ctx = TestEngine.context(cdn, config: TestEngine.slowConfig);
    final url = _url(TestEngine.cosov);
    ctx.nodes
      ..begin(url)
      ..firstByte(url, ms: 5)
      ..body(url, bytes: 4000000, ms: 1000)
      ..end(url, receiving: true);
    final progress = AttemptProgress();
    final cancel = CancelToken();
    final task = _run(ctx, node: TestEngine.cosov, range: ByteRange(0, 299999), progress: progress, cancel: cancel);
    await _waitFor(() => progress.gotHeaders && progress.received > 0 && ctx.clock.nowMs() - progress.headersAt >= 400);
    expect(ctx.nodes.inflight(url), 1);
    expect(ctx.nodes.isBusy(url), isTrue);
    progress.outrun = true;
    cancel.cancel();
    await expectLater(task, throwsA(isA<CancelledException>()));
    expect(ctx.nodes.bps(url), lessThan(4000000));
    expect(ctx.nodes.bps(url), greaterThan(0));
    expect(ctx.nodes.inflight(url), 0);
    expect(ctx.nodes.isBusy(url), isFalse);
  });

  // A seek, a closed session or a cancelled player read ends a copy without any other copy having won.
  test('a copy cancelled for any other reason leaves the node estimates alone', () async {
    final config = TestEngine.slowConfig.copyWith(firstByteTimeoutMs: 5000);
    final cdn = SimCDN(
      size: 300000,
      behaviors: {
        TestEngine.cosov: const NodeBehavior(firstByteMs: 2000),
        TestEngine.aliov: const NodeBehavior(bytesPerSecond: 100000),
      },
    );
    final ctx = TestEngine.context(cdn, config: config);
    final waiting = _url(TestEngine.cosov);
    final crawling = _url(TestEngine.aliov);
    ctx.nodes
      ..begin(waiting)
      ..firstByte(waiting, ms: 10)
      ..end(waiting, receiving: true)
      ..begin(crawling)
      ..firstByte(crawling, ms: 5)
      ..body(crawling, bytes: 4000000, ms: 1000)
      ..end(crawling, receiving: true);

    final waitingProgress = AttemptProgress();
    final waitingCancel = CancelToken();
    final waitingTask = _run(
      ctx,
      node: TestEngine.cosov,
      range: ByteRange(0, 99999),
      progress: waitingProgress,
      cancel: waitingCancel,
    );
    final crawlingProgress = AttemptProgress();
    final crawlingCancel = CancelToken();
    final crawlingTask = _run(
      ctx,
      node: TestEngine.aliov,
      range: ByteRange(0, 299999),
      progress: crawlingProgress,
      cancel: crawlingCancel,
    );
    await _waitFor(
      () =>
          crawlingProgress.gotHeaders &&
          crawlingProgress.received > 0 &&
          ctx.clock.nowMs() - crawlingProgress.headersAt >= 400 &&
          waitingProgress.started,
    );
    await sleepMs(200);
    waitingCancel.cancel();
    crawlingCancel.cancel();
    for (final task in [waitingTask, crawlingTask]) {
      await expectLater(task, throwsA(isA<CancelledException>()));
    }
    expect(ctx.nodes.ttfbMs(waiting), closeTo(10, 0.01));
    expect(ctx.nodes.bps(crawling), closeTo(4000000, 1));
    expect(ctx.nodes.inflight(waiting), 0);
    expect(ctx.nodes.inflight(crawling), 0);
  });

  test('a network change forgets node stats', () async {
    final session = RipperSession(
      sources: {TrackKind.video: (primary: TestEngine.primary, backups: const [])},
      mode: NodeMode.overseas,
      config: TestEngine.config,
      transport: SimCDN(size: 1000000),
      logger: Logger(session: 'test'),
    );
    await session.read(TrackKind.video, ByteRange(2000, 400000)).drain<void>();
    final urls = NodeCatalog.representationURLs(
      primary: TestEngine.primary,
      backups: const [],
      mode: NodeMode.overseas,
      policy: MediaURLPolicy.bilibili,
    );
    final nodeStats = session.nodeStats;
    expect(urls.any(nodeStats.isKnown), isTrue, reason: 'the read measured at least one node');

    session.networkChanged(interfaceChanged: false);
    expect(urls.any(nodeStats.isKnown), isFalse);
  });
}
