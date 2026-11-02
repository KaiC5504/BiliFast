/// 开发者's 节点测速: the same range of one stream fetched from each CDN node in turn.
library;

import 'dart:async';
import 'dart:io' show HandshakeException, HttpException, SocketException, TlsException;
import 'dart:math';

import '../devlog/log_event.dart';
import '../devlog/logger.dart';
import '../shared/byte_range.dart';
import '../shared/clock.dart';
import 'cancel.dart';
import 'node_catalog.dart';
import 'transport.dart';

/// 设置's two node sets: what BTR asks in each CDN 节点 mode.
enum NodeGroup {
  mainland,
  overseas;

  NodeMode get mode => this == mainland ? NodeMode.mainland : NodeMode.overseas;
}

enum NodeProbeFailureKind { timeout, status, refused, unresolved, tls, network, other }

final class NodeProbeFailure {
  const NodeProbeFailure(this.kind, {this.status, this.detail});

  const NodeProbeFailure.status(int this.status) : kind = NodeProbeFailureKind.status, detail = null;

  static const timeout = NodeProbeFailure(NodeProbeFailureKind.timeout);

  final NodeProbeFailureKind kind;
  final int? status;

  /// The error's type for [NodeProbeFailureKind.other]: never its text, which may carry the signed address.
  final String? detail;

  /// dart:io's errors; another transport's are [NodeProbeFailureKind.other] unless the probe is given a classifier.
  static NodeProbeFailure of(Object error) => switch (error) {
    SocketException(:final message, :final osError) when _refused(message, osError?.errorCode) =>
      const NodeProbeFailure(NodeProbeFailureKind.refused),
    SocketException(:final message) when message.contains('host lookup') =>
      const NodeProbeFailure(NodeProbeFailureKind.unresolved),
    HandshakeException() || TlsException() => const NodeProbeFailure(NodeProbeFailureKind.tls),
    SocketException() || HttpException() => const NodeProbeFailure(NodeProbeFailureKind.network),
    RipperError(:final status?) => NodeProbeFailure.status(status),
    _ => NodeProbeFailure(NodeProbeFailureKind.other, detail: '${error.runtimeType}'),
  };

  /// ECONNREFUSED on Linux and Apple, WSAECONNREFUSED and ERROR_CONNECTION_REFUSED on Windows.
  static bool _refused(String message, int? code) =>
      const {111, 61, 10061, 1225}.contains(code) || message.toLowerCase().contains('refused');

  @override
  bool operator ==(Object other) =>
      other is NodeProbeFailure && other.kind == kind && other.status == status && other.detail == detail;

  @override
  int get hashCode => Object.hash(kind, status, detail);

  @override
  String toString() => switch (kind) {
    NodeProbeFailureKind.status => 'http $status',
    NodeProbeFailureKind.other => detail ?? 'other',
    _ => kind.name,
  };
}

/// One node to ask: [url] is the signed address on that node, so it stays in memory and out of every log.
final class NodeProbeTarget {
  const NodeProbeTarget({required this.group, required this.node, required this.url});

  final NodeGroup group;

  /// Host, with the port when it has one.
  final String node;
  final String url;

  String get name => NodeProbe.shortName(node);
}

final class NodeProbeResult {
  const NodeProbeResult({
    required this.group,
    required this.node,
    this.firstByteMs,
    this.bytes = 0,
    this.transferMs,
    this.complete = false,
    this.failure,
  });

  final NodeGroup group;
  final String node;

  /// From the request to the response's headers, on a connection of its own.
  final double? firstByteMs;

  /// Body bytes read.
  final int bytes;

  /// From the headers to the body's end, or to the timeout when the body was [complete] only in part.
  final double? transferMs;

  /// False when the timeout cut the body short: its speed is then over what came.
  final bool complete;
  final NodeProbeFailure? failure;

  bool get ok => failure == null;

  String get name => NodeProbe.shortName(node);

  /// MiB per second, as the stats overlay counts them.
  double? get mbps {
    final transfer = transferMs;
    if (!ok || bytes <= 0 || transfer == null) return null;
    // A loopback answer can arrive within the same millisecond as its headers.
    return bytes / 1048576 / (max(transfer, 1) / 1000);
  }
}

/// Each node's first byte and speed on the same range of one stream, one node at a time, so no two compete for the
/// line. Every node gets a fresh connection, so the first byte carries the DNS, TCP and TLS round trips a node costs
/// when the engine first meets it.
final class NodeProbe {
  NodeProbe({
    required this.transport,
    this.bytes = defaultBytes,
    this.timeout = defaultTimeout,
    this.policy = MediaURLPolicy.bilibili,
    Map<NodeGroup, NodeMode>? groups,
    NodeProbeFailure Function(Object error)? classify,
    MonotonicClock? clock,
    Logger? logger,
  }) : groups = groups ?? {for (final group in NodeGroup.values) group: group.mode},
       _classify = classify ?? NodeProbeFailure.of,
       _clock = clock ?? MonotonicClock.system,
       _logger = logger ?? Logger.shared;

  /// Long enough that the speed isn't all slow start, short enough for twelve nodes on a phone's data.
  static const defaultBytes = 4 << 20;
  static const defaultTimeout = Duration(seconds: 8);

  final RangeTransport transport;
  final int bytes;

  /// For the whole of one node: the connection, the first byte and the body.
  final Duration timeout;
  final MediaURLPolicy policy;

  /// The node set each group stands for; tests give loopback nodes.
  final Map<NodeGroup, NodeMode> groups;
  final NodeProbeFailure Function(Object error) _classify;
  final MonotonicClock _clock;
  final Logger _logger;

  /// Each group's addresses as the engine builds them for that mode (Bilibili's own that suit it, then the signed
  /// address moved onto each of its nodes), one per node, mainland first. A node in both groups is asked once.
  List<NodeProbeTarget> targets({required String primary, required List<String> backups}) {
    final targets = <NodeProbeTarget>[];
    final seen = <String>{};
    for (final MapEntry(key: group, value: mode) in groups.entries) {
      for (final url in NodeCatalog.representationURLs(primary: primary, backups: backups, mode: mode, policy: policy)) {
        final node = NodeCatalog.nodeKey(url);
        if (seen.add(node)) targets.add(NodeProbeTarget(group: group, node: node, url: url));
      }
    }
    return targets;
  }

  /// One result per target, in order. Cancelling [cancel], or the subscription, stops at once and the node being
  /// asked then reports nothing.
  Stream<NodeProbeResult> run(List<NodeProbeTarget> targets, {CancelToken? cancel}) {
    final token = CancelToken(cancel);
    late final StreamController<NodeProbeResult> results;
    Future<void> work() async {
      try {
        for (final target in targets) {
          if (token.isCancelled) break;
          final result = await _probe(target, token);
          if (result == null || token.isCancelled) break;
          _log(result);
          results.add(result);
        }
      } finally {
        token.dispose();
        unawaited(results.close());
      }
    }

    results = StreamController(onListen: () => unawaited(work()), onCancel: token.cancel);
    return results.stream;
  }

  /// Null when the run was cancelled meanwhile.
  Future<NodeProbeResult?> _probe(NodeProbeTarget target, CancelToken run) async {
    final token = CancelToken(run);
    var timedOut = false;
    final timer = Timer(timeout, () {
      timedOut = true;
      token.cancel();
    });
    final start = _clock.nowMs();
    double? headers;
    var received = 0;
    var complete = false;
    NodeProbeFailure? failure;
    try {
      final response = await transport.fetch(Uri.parse(target.url), ByteRange(0, bytes - 1), cancel: token);
      headers = _clock.nowMs() - start;
      if (response.status != 206 && response.status != 200) {
        unawaited(response.body.listen(null).cancel().catchError((Object _) {}));
        failure = NodeProbeFailure.status(response.status);
      } else {
        await for (final chunk in response.body) {
          received += chunk.length;
          // A 200 is the whole file.
          if (received >= bytes) break;
        }
        received = min(received, bytes);
        complete = true;
      }
    } on Object catch (error) {
      if (run.isCancelled) return null;
      if (!timedOut) failure = _classify(error);
    } finally {
      timer.cancel();
      token.dispose();
    }
    final elapsed = _clock.nowMs() - start;
    if (failure == null && (headers == null || (timedOut && received == 0))) failure = NodeProbeFailure.timeout;
    return NodeProbeResult(
      group: target.group,
      node: target.node,
      firstByteMs: headers,
      bytes: received,
      transferMs: headers == null ? null : elapsed - headers,
      complete: complete,
      failure: failure,
    );
  }

  void _log(NodeProbeResult result) {
    final mbps = result.mbps;
    _logger.info(LogCategory.engine, 'node probe', {
      'host': result.node,
      'group': result.group.name,
      'firstByteMs': ?result.firstByteMs?.round(),
      'mbps': ?(mbps == null ? null : (mbps * 100).round() / 100),
      'bytes': result.bytes,
      'complete': result.complete,
      'failure': ?result.failure?.toString(),
    });
  }

  /// The node's distinctive part, as 开发者 lists it: ali, cosov, akam, hk-eq-01-01.
  static String shortName(String node) {
    final host = node.split(':').first;
    if (RegExp(r'^[\d.]+$').hasMatch(host)) return node;
    final label = host.split('.').first;
    final upos = RegExp(r'^upos-[a-z0-9]+-(?:mirror)?(.+)$').firstMatch(label);
    if (upos != null) return upos[1]!;
    return label.startsWith('cn-') ? label.substring(3) : label;
  }
}

/// Per group, the median speed of the nodes that answered, how many did, and which group and node came out fastest.
final class NodeProbeSummary {
  NodeProbeSummary._(this.medianMbps, this.answered, this.asked, this.fastest);

  factory NodeProbeSummary.of(List<NodeProbeResult> results) {
    final speeds = <NodeGroup, List<double>>{for (final group in NodeGroup.values) group: []};
    final asked = <NodeGroup, int>{for (final group in NodeGroup.values) group: 0};
    NodeProbeResult? fastest;
    for (final result in results) {
      asked[result.group] = asked[result.group]! + 1;
      final mbps = result.mbps;
      if (mbps == null) continue;
      speeds[result.group]!.add(mbps);
      if (fastest == null || mbps > fastest.mbps!) fastest = result;
    }
    return NodeProbeSummary._(
      {for (final MapEntry(:key, :value) in speeds.entries) key: _median(value)},
      {for (final MapEntry(:key, :value) in speeds.entries) key: value.length},
      asked,
      fastest,
    );
  }

  /// Null for a group none of whose nodes answered.
  final Map<NodeGroup, double?> medianMbps;
  final Map<NodeGroup, int> answered;
  final Map<NodeGroup, int> asked;
  final NodeProbeResult? fastest;

  /// The group with the higher median; null until one of them has one.
  NodeGroup? get faster {
    final mainland = medianMbps[NodeGroup.mainland];
    final overseas = medianMbps[NodeGroup.overseas];
    if (mainland == null) return overseas == null ? null : NodeGroup.overseas;
    if (overseas == null) return NodeGroup.mainland;
    return overseas >= mainland ? NodeGroup.overseas : NodeGroup.mainland;
  }

  static double? _median(List<double> values) {
    if (values.isEmpty) return null;
    final sorted = [...values]..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
  }
}
