import 'dart:typed_data';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bili_core/src/engine/attempt.dart';
import 'package:bili_core/src/engine/ban_list.dart';
import 'package:bili_core/src/engine/connection_pool.dart';
import 'package:bili_core/src/engine/piece_downloader.dart';
import 'package:bili_core/src/engine/resolver.dart';
import 'package:test/test.dart';

import 'support/fake_cdn.dart';

const _segmentBytes = 512 * 1024;

RipperSession _session(FakeCDN cdn, {RipperConfig config = TestEngine.config, int segments = 0}) {
  final session = RipperSession(
    sources: {TrackKind.video: (primary: TestEngine.primary, backups: const [])},
    mode: NodeMode.overseas,
    transport: cdn,
    config: config,
    logger: Logger(session: 'test'),
  );
  session.setSegments(TrackKind.video, [
    for (var index = 0; index < segments; index++)
      MediaSegment(
        index: index,
        range: ByteRange(index * _segmentBytes, (index + 1) * _segmentBytes - 1),
        startTime: index * 2.0,
        duration: 2,
      ),
  ]);
  return session;
}

ByteRange _segment(int index) => ByteRange(index * _segmentBytes, (index + 1) * _segmentBytes - 1);

Future<Uint8List> _read(RipperSession session, ByteRange range) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in session.read(TrackKind.video, range)) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

Uint8List _expected(FakeCDN cdn, ByteRange range) => Uint8List.sublistView(cdn.content, range.start, range.end + 1);

void main() {
  test('reads come back byte-exact and in order across many pieces and nodes', () async {
    // Different speeds finish the pieces out of order.
    final cdn = FakeCDN(size: 8 * _segmentBytes, behaviors: {
      TestEngine.cosov: const NodeBehavior(bytesPerSecond: 20e6),
      TestEngine.aliov: const NodeBehavior(bytesPerSecond: 40e6, firstByteMs: 6),
      TestEngine.hk1: const NodeBehavior(bytesPerSecond: 80e6, firstByteMs: 1),
    });
    final session = _session(cdn, config: const RipperConfig(fixedConcurrency: 16, hedgeDelayMs: 100), segments: 8);
    addTearDown(session.close);
    for (var index = 0; index < 8; index++) {
      expect(await _read(session, _segment(index)), _expected(cdn, _segment(index)), reason: 'segment $index');
    }
    expect(cdn.urls.length, greaterThan(40));
    expect(cdn.nodes.toSet(), hasLength(4));
    expect(session.seekCount, 1);
    final stats = session.stats();
    expect(stats.deliveredBytes, 8 * _segmentBytes);
    expect(stats.nodeStates.map((status) => status.node), NodeCatalog.overseas);
  });

  test('an unaligned range spanning segments is delivered whole', () async {
    final cdn = FakeCDN(size: 4 * _segmentBytes);
    final session = _session(cdn, segments: 4);
    addTearDown(session.close);
    final range = ByteRange(12345, 3 * _segmentBytes + 999);
    expect(await _read(session, range), _expected(cdn, range));
  });

  test('cancelling the subscription cancels every piece at once', () async {
    final cdn = FakeCDN(size: 4 * _segmentBytes);
    final session = _session(cdn, config: const RipperConfig(fixedConcurrency: 8, stallTimeoutMs: 2000), segments: 4);
    addTearDown(session.close);
    await _read(session, _segment(0));
    for (final node in NodeCatalog.overseas) {
      cdn.set(node, const NodeBehavior(bytesPerSecond: 50e3));
    }
    final subscription = session.read(TrackKind.video, _segment(1)).listen((_) {});
    expect(await eventually(() => cdn.inflight >= 4), isTrue);
    final requests = cdn.urls.length;
    final clock = Stopwatch()..start();
    await subscription.cancel();
    expect(await eventually(() => cdn.inflight == 0, seconds: 0.5), isTrue);
    expect(clock.elapsedMilliseconds, lessThan(200));
    expect(cdn.cancelled, greaterThanOrEqualTo(4));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(cdn.urls.length, requests, reason: 'nothing new starts after the cancel');
  });

  test('misbehaving nodes are routed around: refusal, truncation, stall', () async {
    final cdn = FakeCDN(size: 4 * _segmentBytes, behaviors: {
      TestEngine.cosov: const NodeBehavior(status: 403),
      TestEngine.aliov: const NodeBehavior(truncateAfter: 1000),
      TestEngine.hk1: const NodeBehavior(stallAfter: 2000),
    });
    final session = _session(cdn, segments: 4);
    addTearDown(session.close);
    for (var index = 0; index < 4; index++) {
      expect(await _read(session, _segment(index)), _expected(cdn, _segment(index)));
    }
    expect(session.stats().failures, greaterThan(0));
  });

  test('a node that drops its connections is struck and the others finish the read', () async {
    final cdn = FakeCDN(size: 4 * _segmentBytes, behaviors: {
      TestEngine.cosov: const NodeBehavior(connectionLost: true),
    });
    final session = _session(cdn, segments: 4);
    addTearDown(session.close);
    expect(await _read(session, _segment(0)), _expected(cdn, _segment(0)));
    final struck = cdn.requestsTo(TestEngine.cosov);
    expect(struck, greaterThan(0));
    for (var index = 1; index < 4; index++) {
      expect(await _read(session, _segment(index)), _expected(cdn, _segment(index)));
    }
    final cosov = NodeStatus.best(TestEngine.cosov, session.stats().nodeStates)!;
    expect(cosov.state, anyOf('blocked', 'banned'));
    expect(cdn.requestsTo(TestEngine.cosov), struck, reason: 'left out of the reads after its failures');
    expect(cdn.requestsTo(TestEngine.hk3), greaterThan(0));
  });

  test('replaceUrls takes effect on the next read', () async {
    final cdn = FakeCDN(size: 4 * _segmentBytes);
    final session = _session(cdn, segments: 4);
    addTearDown(session.close);
    await _read(session, _segment(0));
    final before = cdn.urls.length;
    const fresh = 'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/v.m4s?deadline=99&os=cosbv';
    session.replaceUrls(TrackKind.video, primary: fresh, backups: const []);
    // The old signature has expired.
    for (final node in NodeCatalog.overseas) {
      cdn.set(node, const NodeBehavior(refusedQueries: ['deadline=9&']));
    }
    expect(await _read(session, _segment(1)), _expected(cdn, _segment(1)));
    final after = cdn.urls.sublist(before);
    expect(after, isNotEmpty);
    expect(after.every((url) => url.contains('deadline=99&')), isTrue);
  });

  test('a read inside the loaded headers is served from memory', () async {
    final cdn = FakeCDN(size: 4 * _segmentBytes);
    final session = _session(cdn, segments: 4);
    addTearDown(session.close);
    final headers = await session.loadHeaders(TrackKind.video, through: 4095);
    expect(headers.bytes, _expected(cdn, ByteRange(0, 4095)));
    expect(headers.totalSize, 4 * _segmentBytes);
    final requests = cdn.urls.length;
    expect(await _read(session, ByteRange(100, 999)), _expected(cdn, ByteRange(100, 999)));
    expect(cdn.urls.length, requests);
  });

  test('reads after close fail as closed', () async {
    final cdn = FakeCDN(size: _segmentBytes);
    final session = _session(cdn)..close();
    await expectLater(_read(session, ByteRange(0, 99)), throwsA(const RipperError(RipperErrorKind.closed)));
    await expectLater(session.loadHeaders(TrackKind.video, through: 99), throwsA(const RipperError(RipperErrorKind.closed)));
  });

  group('hedging', () {
    // Long timeouts, so only a hedged copy can save the piece in time.
    const config = RipperConfig(firstByteTimeoutMs: 5000, stallTimeoutMs: 5000, hedgeDelayMs: 100);

    Future<(AttemptOutput, int)> download(FakeCDN cdn, {bool hurry = false}) async {
      final ctx = EngineContext(transport: cdn, pool: ConnectionPool(8), config: config, logger: Logger(session: 'test'));
      final resolver = Resolver(primary: TestEngine.primary, backups: const [], mode: NodeMode.overseas, bans: BanList());
      final clock = Stopwatch()..start();
      final output = await PieceDownloader(ctx).download(
        piece: ByteRange(0, 65535),
        index: 0,
        resolver: resolver,
        preferred: [TestEngine.on(TestEngine.cosov), TestEngine.on(TestEngine.aliov)],
        mode: PieceMode.normal,
        priority: 50,
        hurry: () => hurry,
      );
      return (output, clock.elapsedMilliseconds);
    }

    test('a node slow to its first byte gets a second copy on another node', () async {
      final cdn = FakeCDN(size: 1 << 20, behaviors: {TestEngine.cosov: const NodeBehavior(firstByteMs: 2000)});
      final (output, ms) = await download(cdn);
      expect(NodeCatalog.nodeKey(output.url), TestEngine.aliov);
      expect(output.bytes, _expected(cdn, ByteRange(0, 65535)));
      expect(ms, lessThan(1000));
      expect(await eventually(() => cdn.inflight == 0), isTrue, reason: 'the losing copy is cancelled');
      expect(cdn.cancelled, 1);
    });

    test('in a hurry the copy goes after 250 ms without a first byte', () async {
      final cdn = FakeCDN(size: 1 << 20, behaviors: {TestEngine.cosov: const NodeBehavior(firstByteMs: 2000)});
      final (output, ms) = await download(cdn, hurry: true);
      expect(NodeCatalog.nodeKey(output.url), TestEngine.aliov);
      expect(ms, inInclusiveRange(240, 1000));
    });

    test('a node that trickles is hedged too', () async {
      final cdn = FakeCDN(size: 1 << 20, behaviors: {TestEngine.cosov: const NodeBehavior(bytesPerSecond: 20e3)});
      final (output, ms) = await download(cdn, hurry: true);
      expect(NodeCatalog.nodeKey(output.url), TestEngine.aliov);
      expect(ms, lessThan(2000));
    });
  });

  group('bans', () {
    String url(String node) => TestEngine.on(node);

    test('two 0-byte replies at different moments ban the node, which drops out of the candidates', () {
      final clock = ManualClock(10000);
      final bans = BanList();
      final resolver = Resolver(
          primary: TestEngine.primary, backups: const [], mode: NodeMode.overseas, bans: bans, clock: clock.clock);
      resolver.failure(url(TestEngine.cosov), receivedBytes: 0);
      expect(bans.allows(url(TestEngine.cosov)), isTrue);
      clock.advance(300);
      resolver.failure(url(TestEngine.cosov), receivedBytes: 0);
      expect(bans.allows(url(TestEngine.cosov)), isFalse);
      expect(resolver.urls().map(NodeCatalog.nodeKey), isNot(contains(TestEngine.cosov)));
      expect(NodeStatus.best(TestEngine.cosov, resolver.status())!.state, 'banned');
    });

    test('a transfer cut off after some bytes is no strike', () {
      final clock = ManualClock(10000);
      final bans = BanList();
      final resolver = Resolver(
          primary: TestEngine.primary, backups: const [], mode: NodeMode.overseas, bans: bans, clock: clock.clock);
      for (var round = 0; round < 3; round++) {
        resolver.failure(url(TestEngine.cosov), receivedBytes: 1000, range: ByteRange(0, 65535));
        clock.advance(300);
      }
      expect(bans.allows(url(TestEngine.cosov)), isTrue);
    });

    test('a failure blocks the node briefly; a network change clears the block', () {
      final clock = ManualClock(10000);
      final resolver = Resolver(
          primary: TestEngine.primary, backups: const [], mode: NodeMode.overseas, bans: BanList(), clock: clock.clock);
      resolver.failure(url(TestEngine.cosov), status: 503, receivedBytes: 0);
      expect(NodeStatus.best(TestEngine.cosov, resolver.status())!.state, 'blocked');
      expect(resolver.rescueCandidates().map(NodeCatalog.nodeKey), isNot(contains(TestEngine.cosov)));
      clock.advance(6001);
      expect(resolver.rescueCandidates().map(NodeCatalog.nodeKey), contains(TestEngine.cosov));
      final hk1 = url(TestEngine.hk1);
      resolver.failure(hk1, status: 503, receivedBytes: 0);
      expect(NodeStatus.best(TestEngine.hk1, resolver.status())!.state, 'blocked');
      resolver.resetHealth(clearMeasurements: false);
      expect(NodeStatus.best(TestEngine.hk1, resolver.status())!.state, 'untested');
    });
  });
}
