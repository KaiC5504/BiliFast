import 'dart:math';

/// What was known about a node before this session measured it, in `NodeStats`'s units: the first byte and the
/// body speed of one connection. A weight says how much each still counts: 1 when just measured, less with age.
final class NodePrior {
  const NodePrior({this.ttfbMs = 0, this.bps = 0, this.ttfbWeight = 1, this.bpsWeight = 1});

  /// 0 when unknown.
  final double ttfbMs;

  /// Bytes per second of one connection once the body flows; 0 when unknown.
  final double bps;
  final double ttfbWeight;
  final double bpsWeight;

  /// Pieces outside a hurry run from about 256 KiB to 1 MiB (`Meter.adaptiveMinChunk`).
  static const routeReferenceBytes = 512 * 1024;

  /// What `Resolver` measures, a whole request's bytes per second with its first byte, for a typical piece.
  double get routeBps => bps > 0 ? routeReferenceBytes * 1000 / (ttfbMs + routeReferenceBytes * 1000 / bps) : 0;

  /// A first measurement taken over from a prior: a fresh prior weighs what an established estimate does in
  /// `smoothed` (0.7), an old one less, so a day-old guess gives way to what the node does now.
  static double blend(double prior, double weight, double sample) {
    if (prior <= 0 || weight <= 0) return sample;
    final keep = 0.7 * min(1.0, weight);
    return prior * keep + sample * (1 - keep);
  }
}

/// Where `NodeStats` and `Resolver` look up a node (by `NodeCatalog.nodeKey`) before they have measured it.
/// [empty] keeps Swift's behaviour: every node starts unknown.
final class NodePriors {
  const NodePriors._(this._lookup);

  NodePriors(NodePrior? Function(String node) lookup) : _lookup = lookup;

  NodePriors.fixed(Map<String, NodePrior> priors) : _lookup = ((node) => priors[node]);

  static const empty = NodePriors._(null);

  final NodePrior? Function(String node)? _lookup;

  bool get isEmpty => _lookup == null;

  NodePrior? of(String node) => _lookup?.call(node);
}

final class _Estimate {
  double ttfbMs = 0;
  double ttfbAt = 0;
  double bps = 0;
  double bpsAt = 0;

  bool get isEmpty => ttfbMs <= 0 && bps <= 0;
}

double _systemNowMs() => DateTime.now().millisecondsSinceEpoch.toDouble();

/// What the engine has measured about each node, kept across sessions and videos and, through [toJson] and
/// [NodeMemory.fromJson], across launches. Speeds belong to a network: the caller names the current one in
/// [signature], and nothing is looked up or recorded while it is empty.
///
/// `NodeStats` reports each new estimate through its `onMeasured` hook ([record]); [priors] is a live view of the
/// current network's estimates for the next session's `NodeStats` and `Resolver`. Without it every session on the
/// phone measured every node from nothing (stats per session, speeds expiring after 90 s): every first range ran the
/// probe race, and the warm-up sent the first four ranges to every node, the 0.2 MB/s HK ones included.
final class NodeMemory {
  NodeMemory({double Function()? wallClockMs, this.halfLifeMs = defaultHalfLifeMs})
    : _now = wallClockMs ?? _systemNowMs;

  factory NodeMemory.fromJson(Object? json, {double Function()? wallClockMs, double halfLifeMs = defaultHalfLifeMs}) {
    final memory = NodeMemory(wallClockMs: wallClockMs, halfLifeMs: halfLifeMs);
    if (json is! Map || json['version'] != version) return memory;
    final networks = json['networks'];
    if (networks is! Map) return memory;
    for (final MapEntry(key: signature, value: nodes) in networks.entries) {
      if (signature is! String || signature.isEmpty || nodes is! Map) continue;
      final estimates = <String, _Estimate>{};
      for (final MapEntry(key: node, value: fields) in nodes.entries) {
        if (node is! String || node.isEmpty || fields is! Map) continue;
        final estimate = _Estimate()
          ..ttfbMs = _number(fields['ttfbMs'])
          ..ttfbAt = _number(fields['ttfbAt'])
          ..bps = _number(fields['bps'])
          ..bpsAt = _number(fields['bpsAt']);
        if (!estimate.isEmpty) estimates[node] = estimate;
      }
      if (estimates.isNotEmpty) memory._networks[signature] = estimates;
    }
    while (memory._networks.length > maxNetworks) {
      memory._networks.remove(memory._networks.keys.first);
    }
    return memory;
  }

  static const version = 1;

  /// The node ranking held for a month (PC 2026-09-19, phone 2026-10-17: Akamai, then aliov, cosov, the HK nodes
  /// last), so yesterday's estimate still orders the nodes and spares the probe race. Their speeds hold less well:
  /// hot and cold content differ several-fold. At 12 hours an estimate from the same evening counts nearly in full,
  /// yesterday's for a quarter (its first fresh measurement moves it 82% of the way), and one two days old is dropped
  /// ([minWeight]).
  static const defaultHalfLifeMs = 12 * 3600 * 1000.0;

  static const minWeight = 1 / 16;

  /// Home Wi-Fi, cellular and a few other places.
  static const maxNetworks = 8;

  final double halfLifeMs;
  final double Function() _now;
  String _signature = '';

  /// Least recently used first.
  final _networks = <String, Map<String, _Estimate>>{};

  String get signature => _signature;

  /// Names the network the phone is on now; an empty name turns the memory off until a real one is set.
  set signature(String value) {
    _signature = value;
    final nodes = _networks.remove(value);
    if (nodes != null) _networks[value] = nodes;
  }

  /// Live: always reads the current network's estimates as they are now.
  NodePriors get priors => NodePriors(prior);

  /// What the current network has seen of [node], fields that have aged past [minWeight] left out.
  NodePrior? prior(String node) {
    if (_signature.isEmpty) return null;
    final estimate = _networks[_signature]?[node];
    if (estimate == null) return null;
    final ttfbWeight = estimate.ttfbMs > 0 ? _weight(estimate.ttfbAt) : 0.0;
    final bpsWeight = estimate.bps > 0 ? _weight(estimate.bpsAt) : 0.0;
    final ttfbKnown = ttfbWeight >= minWeight;
    final bpsKnown = bpsWeight >= minWeight;
    if (!ttfbKnown && !bpsKnown) return null;
    return NodePrior(
      ttfbMs: ttfbKnown ? estimate.ttfbMs : 0,
      bps: bpsKnown ? estimate.bps : 0,
      ttfbWeight: ttfbKnown ? ttfbWeight : 0,
      bpsWeight: bpsKnown ? bpsWeight : 0,
    );
  }

  /// `NodeStats`'s estimate of [node] after a measurement, the field that changed only. It is already smoothed
  /// there (and blended with the prior), so it replaces the stored one.
  void record(String node, {double? ttfbMs, double? bps}) {
    if (_signature.isEmpty || node.isEmpty) return;
    var nodes = _networks[_signature];
    if (nodes == null) {
      nodes = _networks[_signature] = {};
      while (_networks.length > maxNetworks) {
        _networks.remove(_networks.keys.first);
      }
    }
    final estimate = nodes.putIfAbsent(node, _Estimate.new);
    final now = _now();
    if (ttfbMs != null && ttfbMs > 0) {
      estimate
        ..ttfbMs = ttfbMs
        ..ttfbAt = now;
    }
    if (bps != null && bps > 0) {
      estimate
        ..bps = bps
        ..bpsAt = now;
    }
  }

  /// Fields past [minWeight] are dropped, so the saved file stays small.
  Map<String, Object?> toJson() {
    final networks = <String, Object?>{};
    for (final MapEntry(key: signature, value: nodes) in _networks.entries) {
      final saved = <String, Object?>{};
      for (final MapEntry(key: node, value: estimate) in nodes.entries) {
        final ttfb = estimate.ttfbMs > 0 && _weight(estimate.ttfbAt) >= minWeight;
        final bps = estimate.bps > 0 && _weight(estimate.bpsAt) >= minWeight;
        if (!ttfb && !bps) continue;
        saved[node] = {
          if (ttfb) 'ttfbMs': estimate.ttfbMs,
          if (ttfb) 'ttfbAt': estimate.ttfbAt,
          if (bps) 'bps': estimate.bps,
          if (bps) 'bpsAt': estimate.bpsAt,
        };
      }
      if (saved.isNotEmpty) networks[signature] = saved;
    }
    return {'version': version, 'networks': networks};
  }

  /// A clock set back makes an estimate no older than now.
  double _weight(double at) {
    if (at <= 0) return 0;
    return pow(0.5, max(0.0, _now() - at) / halfLifeMs).toDouble();
  }

  static double _number(Object? value) => value is num && value.isFinite && value > 0 ? value.toDouble() : 0;
}
