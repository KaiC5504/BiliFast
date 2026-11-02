import 'dart:async';
import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:test/test.dart';

import 'support/loopback_server.dart';
import 'support/sim_cdn.dart' show eventually;

const _cos = 'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/v.m4s?deadline=9&os=cosbv&upsig=x';
const _akamai = 'https://upos-hz-mirrorakam.akamaized.net/upgcxcode/1/2/3/v.m4s?deadline=9&os=akam&hdnts=x';

/// Never asked itself: every loopback node gets this address moved onto it.
const _origin = 'http://origin.test/v/x.m4s?sig=secret';
const _path = '/v/x.m4s';

void main() {
  test('each group is the engine\'s address list for its mode, one per node, with Bilibili\'s own first', () {
    final probe = NodeProbe(transport: _NoTransport());
    final targets = probe.targets(primary: _cos, backups: [_akamai]);
    expect(targets.where((target) => target.group == NodeGroup.mainland).map((target) => target.name), [
      'cos',
      'ali',
      'hw',
      'bos',
      '08c',
      'bd',
      '14b',
      'estgoss',
    ]);
    expect(targets.where((target) => target.group == NodeGroup.overseas).map((target) => target.name), [
      'akam',
      'cosov',
      'aliov',
      'hk-eq-01-01',
      'hk-eq-01-03',
    ]);
    expect(targets.first.url, _cos);
    expect(targets.firstWhere((target) => target.name == 'akam').url, _akamai);
    expect(
      targets.where((target) => target.name != 'akam').every((target) => target.url.endsWith(NodeCatalog.address(_cos))),
      isTrue,
      reason: 'every node is asked the signed address byte for byte',
    );
    expect(targets.map((target) => target.node).toSet(), hasLength(targets.length));
  });

  test('a node in both groups is asked once, and nothing that fails the policy is asked', () {
    final probe = NodeProbe(
      transport: _NoTransport(),
      policy: MediaURLPolicy.any,
      groups: {
        NodeGroup.mainland: CustomNodes([NodeAddress('127.0.0.1', port: 1)]),
        NodeGroup.overseas: CustomNodes([NodeAddress('127.0.0.1', port: 1), NodeAddress('127.0.0.1', port: 2)]),
      },
    );
    expect(probe.targets(primary: _origin, backups: const []).map((target) => (target.group, target.node)), [
      (NodeGroup.mainland, '127.0.0.1:1'),
      (NodeGroup.overseas, '127.0.0.1:2'),
    ]);
    expect(NodeProbe(transport: _NoTransport()).targets(primary: _origin, backups: const []), isEmpty);
  });

  test('short names keep what tells the nodes apart', () {
    expect(NodeProbe.shortName('upos-sz-mirroraliov.bilivideo.com'), 'aliov');
    expect(NodeProbe.shortName('upos-sz-estgoss.bilivideo.com'), 'estgoss');
    expect(NodeProbe.shortName('upos-hz-mirrorakam.akamaized.net'), 'akam');
    expect(NodeProbe.shortName('cn-hk-eq-01-03.bilivideo.com'), 'hk-eq-01-03');
    expect(NodeProbe.shortName('127.0.0.1:4000'), '127.0.0.1:4000');
  });

  group('against loopback nodes', () {
    final servers = <LoopbackServer>[];
    late MemorySink logs;
    late Logger logger;

    setUp(() {
      logs = MemorySink();
      logger = Logger(session: 'test')..add(logs);
    });

    tearDown(() async {
      for (final server in servers) {
        await server.stop();
      }
      servers.clear();
    });

    Future<NodeAddress> node(LoopbackRoute? route) async {
      final server = await LoopbackServer.start({_path: ?route});
      servers.add(server);
      return NodeAddress('127.0.0.1', port: server.port);
    }

    NodeProbe probeOf(
      RangeTransport transport, {
      required List<NodeAddress> mainland,
      required List<NodeAddress> overseas,
      Duration timeout = const Duration(milliseconds: 500),
    }) => NodeProbe(
      transport: transport,
      bytes: 256 * 1024,
      timeout: timeout,
      policy: MediaURLPolicy.any,
      // An empty custom mode means the mainland nodes, which a test must never reach.
      groups: {
        if (mainland.isNotEmpty) NodeGroup.mainland: CustomNodes(mainland),
        if (overseas.isNotEmpty) NodeGroup.overseas: CustomNodes(overseas),
      },
      logger: logger,
    );

    test('fast, failing, slow and silent nodes: speed, status, a cut speed and a timeout, each logged without its address', () async {
      final transport = _LoopbackOnly();
      addTearDown(transport.close);
      final fast = await node(const Complete(1 << 20));
      final failing = await node(null);
      final slow = await node(const Trickle(1 << 20));
      final silent = await node(const Hang());
      final probe = probeOf(transport, mainland: [fast, failing], overseas: [slow, silent]);

      final results = await probe.run(probe.targets(primary: _origin, backups: const [])).toList();
      expect(results.map((result) => (result.group, result.node)), [
        (NodeGroup.mainland, '$fast'),
        (NodeGroup.mainland, '$failing'),
        (NodeGroup.overseas, '$slow'),
        (NodeGroup.overseas, '$silent'),
      ]);
      final [quick, notFound, trickle, hung] = results;
      expect((quick.ok, quick.complete, quick.bytes), (true, true, 256 * 1024));
      expect(quick.firstByteMs, isNotNull);
      expect(quick.mbps, greaterThan(1));

      expect(notFound.failure, const NodeProbeFailure.status(404));
      expect(notFound.mbps, isNull);

      expect((trickle.ok, trickle.complete), (true, false), reason: 'the timeout cut it, so its speed is over what came');
      expect(trickle.bytes, inExclusiveRange(0, 256 * 1024));
      expect(trickle.mbps, inExclusiveRange(0, 1));

      expect(hung.failure, NodeProbeFailure.timeout);
      expect(hung.firstByteMs, isNull);
      expect(await eventually(() => servers[3].closes(_path) == 1), isTrue, reason: 'the timeout drops the request');

      final summary = NodeProbeSummary.of(results);
      expect(summary.medianMbps[NodeGroup.mainland], quick.mbps);
      expect(summary.medianMbps[NodeGroup.overseas], trickle.mbps);
      expect((summary.answered[NodeGroup.mainland], summary.asked[NodeGroup.overseas]), (1, 2));
      expect(summary.faster, NodeGroup.mainland);
      expect(summary.fastest, same(quick));

      final lines = logs.events.where((event) => event.msg == 'node probe').toList();
      expect(lines, hasLength(4));
      expect(lines.map((line) => line.f['host']), [for (final result in results) LogString(result.node)]);
      expect(lines.map((line) => line.f['group']), [
        const LogString('mainland'),
        const LogString('mainland'),
        const LogString('overseas'),
        const LogString('overseas'),
      ]);
      expect(lines[1].f['failure'], const LogString('http 404'));
      expect(lines[3].f['failure'], const LogString('timeout'));
      expect(lines.first.f['mbps'], isA<LogDouble>());
      for (final line in lines) {
        expect(line.f.values.whereType<LogString>().any((value) => value.value.contains('sig') || value.value.contains(_path)),
            isFalse);
      }
      expect(servers.first.headers(_path).single['range'], 'bytes=0-262143');
    });

    test('a node nothing listens on is refused', () async {
      final transport = _LoopbackOnly();
      addTearDown(transport.close);
      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close();
      // Windows takes about 2 s to report a refused connect.
      final probe = probeOf(transport, mainland: [NodeAddress('127.0.0.1', port: port)], overseas: const [],
          timeout: const Duration(seconds: 8));
      final results = await probe.run(probe.targets(primary: _origin, backups: const [])).toList();
      expect(results.single.failure?.kind, NodeProbeFailureKind.refused);
    });

    test('cancelling stops the node being asked at once, reports nothing for it and asks no further node', () async {
      final transport = _LoopbackOnly();
      addTearDown(transport.close);
      final silent = await node(const Hang());
      final next = await node(const Complete(1 << 20));
      final probe = probeOf(transport, mainland: [silent], overseas: [next], timeout: const Duration(seconds: 30));
      final cancel = CancelToken();
      final results = probe.run(probe.targets(primary: _origin, backups: const []), cancel: cancel).toList();
      expect(await eventually(() => servers.first.requests(_path) == 1), isTrue);
      final clock = Stopwatch()..start();
      cancel.cancel();
      expect(await results.timeout(const Duration(seconds: 2)), isEmpty);
      expect(clock.elapsedMilliseconds, lessThan(1000));
      expect(await eventually(() => servers.first.closes(_path) == 1), isTrue);
      expect(servers[1].requests(_path), 0);
      expect(logs.events.where((event) => event.msg == 'node probe'), isEmpty);
    });

    test('cancelling the subscription aborts the request too', () async {
      final transport = _LoopbackOnly();
      addTearDown(transport.close);
      final silent = await node(const Hang());
      final probe = probeOf(transport, mainland: [silent], overseas: const [], timeout: const Duration(seconds: 30));
      final subscription = probe.run(probe.targets(primary: _origin, backups: const [])).listen(null);
      expect(await eventually(() => servers.first.requests(_path) == 1), isTrue);
      await subscription.cancel();
      expect(await eventually(() => servers.first.closes(_path) == 1), isTrue);
    });
  });

  test('a transport\'s own errors go through the classifier given, dart:io\'s by default', () async {
    final probe = NodeProbe(
      transport: _FailingTransport(StateError('custom')),
      policy: MediaURLPolicy.any,
      groups: {NodeGroup.mainland: CustomNodes([NodeAddress('127.0.0.1', port: 1)])},
      classify: (error) => const NodeProbeFailure(NodeProbeFailureKind.refused),
    );
    final results = await probe.run(probe.targets(primary: _origin, backups: const [])).toList();
    expect(results.single.failure?.kind, NodeProbeFailureKind.refused);

    expect(NodeProbeFailure.of(const SocketException('Connection refused')).kind, NodeProbeFailureKind.refused);
    expect(NodeProbeFailure.of(const SocketException('x', osError: OSError('', 10061))).kind,
        NodeProbeFailureKind.refused);
    expect(NodeProbeFailure.of(const SocketException("Failed host lookup: 'x'")).kind, NodeProbeFailureKind.unresolved);
    expect(NodeProbeFailure.of(const HandshakeException('bad')).kind, NodeProbeFailureKind.tls);
    expect(NodeProbeFailure.of(const SocketException('Connection reset')).kind, NodeProbeFailureKind.network);
    expect(NodeProbeFailure.of(const RipperError.badResponse(0)), const NodeProbeFailure.status(0));
    expect(NodeProbeFailure.of(StateError('https://x/v.m4s?sig')).toString(), 'StateError',
        reason: 'the type, never the text');
  });

  group('the summary', () {
    NodeProbeResult ok(NodeGroup group, String node, double mbps) =>
        NodeProbeResult(group: group, node: node, firstByteMs: 100, bytes: 1048576, transferMs: 1000 / mbps, complete: true);
    NodeProbeResult failed(NodeGroup group, String node) =>
        NodeProbeResult(group: group, node: node, failure: NodeProbeFailure.timeout);

    test('medians over the nodes that answered, failures counted as asked only', () {
      final summary = NodeProbeSummary.of([
        ok(NodeGroup.mainland, 'a', 1),
        ok(NodeGroup.mainland, 'b', 3),
        failed(NodeGroup.mainland, 'c'),
        ok(NodeGroup.overseas, 'd', 2),
        ok(NodeGroup.overseas, 'e', 9),
        ok(NodeGroup.overseas, 'f', 4),
      ]);
      expect(summary.medianMbps[NodeGroup.mainland], closeTo(2, 1e-9));
      expect(summary.medianMbps[NodeGroup.overseas], closeTo(4, 1e-9));
      expect((summary.answered[NodeGroup.mainland], summary.asked[NodeGroup.mainland]), (2, 3));
      expect(summary.faster, NodeGroup.overseas);
      expect(summary.fastest?.node, 'e');
    });

    test('a group with no answer loses; with none at all there is no faster group', () {
      expect(NodeProbeSummary.of([failed(NodeGroup.overseas, 'a'), ok(NodeGroup.mainland, 'b', 0.5)]).faster,
          NodeGroup.mainland);
      final none = NodeProbeSummary.of([failed(NodeGroup.overseas, 'a'), failed(NodeGroup.mainland, 'b')]);
      expect((none.faster, none.fastest, none.medianMbps[NodeGroup.mainland]), (null, null, null));
      expect(NodeProbeSummary.of(const []).faster, isNull);
    });
  });
}

/// dart:io that refuses, unsent, anything but this machine.
final class _LoopbackOnly implements RangeTransport {
  final _io = IoRangeTransport();

  @override
  Future<TransportResponse> fetch(Uri url, ByteRange range, {CancelToken? cancel}) {
    if (url.host != '127.0.0.1') throw StateError('a test asked ${url.host}');
    return _io.fetch(url, range, cancel: cancel);
  }

  @override
  int? get connectionsPerHost => _io.connectionsPerHost;

  @override
  String get name => _io.name;

  @override
  void close() => _io.close();
}

final class _NoTransport implements RangeTransport {
  @override
  Future<TransportResponse> fetch(Uri url, ByteRange range, {CancelToken? cancel}) => throw UnimplementedError();

  @override
  int? get connectionsPerHost => null;

  @override
  String get name => 'none';

  @override
  void close() {}
}

final class _FailingTransport implements RangeTransport {
  _FailingTransport(this.error);

  final Object error;

  @override
  Future<TransportResponse> fetch(Uri url, ByteRange range, {CancelToken? cancel}) => Future.error(error);

  @override
  int? get connectionsPerHost => null;

  @override
  String get name => 'failing';

  @override
  void close() {}
}
