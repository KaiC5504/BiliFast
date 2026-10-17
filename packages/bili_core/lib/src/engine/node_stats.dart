// Port of Bilibili-thread-ripper (see LICENSE-BTR.txt), by way of BiliNative's NodeStats.swift.

import 'dart:math';

import 'meter.dart';
import 'node_catalog.dart';
import 'node_memory.dart';

const _unlimited = 1 << 62;

final class _Node {
  _Node(this.connections) : limit = connections;

  int inflight = 0;
  int receiving = 0;

  /// Measured since the session began (or the last [NodeStats.reset]); 0 until then, when the prior stands in.
  double ttfbMs = 0;
  double bps = 0;
  double load = 0;

  /// What the transport sends the node at once.
  final int connections;
  int limit;
}

/// What the downloads have measured about each node: how long its first byte takes, how fast one
/// connection runs and how many it carries at once (BTR PR 11 `createNodeStats`). One record is shared
/// by every track, so the audio track and the range after a seek start from what is already known.
final class NodeStats {
  /// Akamai answers only HTTP/1.1, so it is full at the transport's connections per host from the start:
  /// a request beyond them would wait inside the transport with its first-byte clock running.
  NodeStats({
    int? connectionsPerHost,
    this.priors = NodePriors.empty,
    this.onMeasured,
    this.exploreInHurry = true,
    this.tailBackups = false,
  }) : _akamaiConnections = connectionsPerHost ?? _unlimited;

  final int _akamaiConnections;
  final _nodes = <String, _Node>{};

  /// What earlier sessions measured (`NodeMemory.priors`): a node with a prior speed is known before its first
  /// piece, so a startup range skips the probe race and hurry placement uses the prior's expected time. The first
  /// measurement of each field is blended with the prior by its weight. Read on every use, so a session follows a
  /// change of network at once.
  NodePriors priors;

  /// Called with the node's estimate whenever a measurement changes it (the changed field only), for
  /// `NodeMemory.record`.
  void Function(String node, {double? ttfbMs, double? bps})? onMeasured;

  /// Off: in a hurry, nodes under 1/`HurryPlacement.slowShare` of the best known speed take no pieces, and nodes not
  /// known yet take none once two known nodes are left; both go last for backup copies. Exploring belongs to
  /// prefetch, where nobody waits. On (Swift): an unknown node takes a share at twice the best cost.
  bool exploreInHurry;

  /// On: `HurryPlacement.tailBackupDue` may give the last piece of a hurried range an early backup copy.
  bool tailBackups;

  _Node _fresh(String url) => _Node(NodeCatalog.isAkamai(url) ? _akamaiConnections : _unlimited);

  _Node _node(String url) => _nodes.putIfAbsent(NodeCatalog.nodeKey(url), () => _fresh(url));

  _Node _peek(String url) => _nodes[NodeCatalog.nodeKey(url)] ?? _fresh(url);

  NodePrior? _prior(String url) => priors.isEmpty ? null : priors.of(NodeCatalog.nodeKey(url));

  double _ttfb(String url, _Node node) => node.ttfbMs > 0 ? node.ttfbMs : _prior(url)?.ttfbMs ?? 0;

  double _bps(String url, _Node node) => node.bps > 0 ? node.bps : _prior(url)?.bps ?? 0;

  void _setTtfb(String url, _Node node, double sample) {
    if (node.ttfbMs > 0) {
      node.ttfbMs = smoothed(node.ttfbMs, sample);
    } else {
      final prior = _prior(url);
      node.ttfbMs = prior == null ? sample : NodePrior.blend(prior.ttfbMs, prior.ttfbWeight, sample);
    }
    onMeasured?.call(NodeCatalog.nodeKey(url), ttfbMs: node.ttfbMs);
  }

  void _setBps(String url, _Node node, double sample) {
    if (node.bps > 0) {
      node.bps = smoothed(node.bps, sample);
    } else {
      final prior = _prior(url);
      node.bps = prior == null ? sample : NodePrior.blend(prior.bps, prior.bpsWeight, sample);
    }
    onMeasured?.call(NodeCatalog.nodeKey(url), bps: node.bps);
  }

  void begin(String url) => _node(url).inflight += 1;

  /// Counts a request on the first of [urls] (not empty) whose node has room, or on the first when every one
  /// is full, and returns it.
  String beginFirstOpen(List<String> urls) {
    final url =
        urls.where((url) {
          final node = _peek(url);
          return node.inflight < node.limit;
        }).firstOrNull ??
        urls.first;
    _node(url).inflight += 1;
    return url;
  }

  void firstByte(String url, {required double ms}) {
    final node = _node(url);
    node.receiving += 1;
    _setTtfb(url, node, max(1, ms));
  }

  void end(String url, {required bool receiving}) {
    final node = _node(url);
    node.inflight = max(0, node.inflight - 1);
    if (receiving) node.receiving = max(0, node.receiving - 1);
  }

  void body(String url, {required int bytes, required double ms}) {
    // An index of a few KiB arrives in one packet and says nothing about speed.
    if (bytes < 32 * 1024) return;
    final node = _node(url);
    _setBps(url, node, bytes / max(0.02, ms / 1000));
    node.load = smoothed(node.load, node.inflight.toDouble());
  }

  /// No first byte in time. While the node was sending other pieces the request was only queued behind
  /// them (HTTP/1.1 allows a few connections per host), so the node is capped at what it was carrying;
  /// otherwise the node itself is slow to answer (BTR PR 11).
  void silent(String url, {required double waitedMs}) {
    final node = _node(url);
    if (node.receiving > 0) {
      node.limit = min(node.limit, node.receiving);
    } else {
      _setTtfb(url, node, waitedMs);
    }
  }

  /// The other copy of the piece won before this node had sent anything; how long this copy had
  /// waited is the least its first byte would have taken.
  void outrun(String url, {required double waitedMs}) {
    final node = _node(url);
    if (waitedMs > _ttfb(url, node)) _setTtfb(url, node, waitedMs);
  }

  /// The other copy won while this node was still sending. An outrun transfer never reaches [body], so a
  /// node that answers at once and then trickles would keep the speed it showed on a part of the file
  /// it had ready, and keep getting most of the pieces.
  void crawl(String url, {required int bytes, required double ms}) {
    final node = _node(url);
    final bps = bytes / max(0.02, ms / 1000);
    if (ms >= 300 && bps < _bps(url, node)) _setBps(url, node, bps);
  }

  /// A node that is sending other pieces is alive, whatever happened to this one.
  bool isBusy(String url) => _peek(url).receiving > 0;

  bool isFull(String url, {int extraInflight = 0}) {
    final node = _peek(url);
    return node.inflight + extraInflight >= node.limit;
  }

  /// Its speed is measured or known from a prior.
  bool isKnown(String url) => _bps(url, _peek(url)) > 0;

  int inflight(String url) => _peek(url).inflight;

  double ttfbMs(String url) => _ttfb(url, _peek(url));

  double bps(String url) => _bps(url, _peek(url));

  /// First byte plus the transfer at the speed one connection would get if [extraInflight] more pieces
  /// joined the ones already running. The speed was measured while the node carried `load` connections;
  /// beyond that it is assumed to share the same total, and a node that keeps its speed raises `load` with the
  /// next measurements. A node is taken to carry at least four at full speed, which is the reason to split a
  /// download at all. Null until a speed is known.
  double? expectedMs(String url, {required int pieceBytes, int extraInflight = 0}) {
    final node = _peek(url);
    final prior = node.bps > 0 && node.ttfbMs > 0 ? null : _prior(url);
    final bps = node.bps > 0 ? node.bps : prior?.bps ?? 0;
    if (bps <= 0) return null;
    final ttfb = node.ttfbMs > 0 ? node.ttfbMs : prior?.ttfbMs ?? 0;
    final width = max(4.0, node.load);
    final perConnection = bps * width / max(width, (node.inflight + extraInflight + 1).toDouble());
    return ttfb + pieceBytes / perConnection * 1000;
  }

  /// The network path changed: what was measured on the old one is dropped (the priors, which follow the
  /// network's signature, stand in again). Transfers still running stay counted, so their [end] balances.
  void reset() {
    for (final MapEntry(:key, value: node) in _nodes.entries.toList()) {
      _nodes[key] = _Node(node.connections)
        ..inflight = node.inflight
        ..receiving = node.receiving;
    }
  }
}
