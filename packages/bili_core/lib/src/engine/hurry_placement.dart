import 'node_catalog.dart';
import 'node_stats.dart';

/// Which node each piece of a range in a hurry tries first: the one expected to deliver it first, counting
/// the pieces already placed on it (BTR PR 11 `pick`). One measurement must not decide where a whole segment
/// goes while the player is short of data: a node can take seconds over a part of the file it has not served
/// lately. So unknown nodes take a share and, with three or more hosts, no node takes more than half.
abstract final class HurryPlacement {
  static List<String> assign({
    required List<String> urls,
    required int count,
    required int pieceBytes,
    required NodeStats nodes,
    required bool Function(String url) delivered,
  }) {
    if (urls.isEmpty || count <= 0) return const [];
    final keys = urls.map(NodeCatalog.nodeKey).toList();
    final hosts = keys.toSet();
    final placed = <String, int>{};
    final primaries = <String>[];
    for (var piece = 0; piece < count; piece++) {
      final inflight = [
        for (var index = 0; index < urls.length; index++) nodes.inflight(urls[index]) + (placed[keys[index]] ?? 0),
      ];
      final expected = [
        for (var index = 0; index < urls.length; index++)
          nodes.expectedMs(urls[index], pieceBytes: pieceBytes, extraInflight: placed[keys[index]] ?? 0),
      ];
      final best = _min(expected);
      var carried = 0;
      for (final host in hosts) {
        carried += inflight[keys.indexOf(host)];
      }
      var chosen = 0;
      var chosenCost = double.infinity;
      for (var index = 0; index < urls.length; index++) {
        final url = urls[index];
        final cost = _cost(
          expected: expected[index],
          best: best,
          inflight: inflight[index],
          crowded: hosts.length > 2 && inflight[index] >= 2 && inflight[index] * 2 > carried,
          delivered: delivered(url),
          full: nodes.isFull(url, extraInflight: placed[keys[index]] ?? 0),
        );
        // Equal costs go to the node carrying less, so equally slow nodes share the overflow.
        if (cost < chosenCost || (cost == chosenCost && inflight[index] < inflight[chosen])) {
          chosen = index;
          chosenCost = cost;
        }
      }
      placed[keys[chosen]] = (placed[keys[chosen]] ?? 0) + 1;
      primaries.add(urls[chosen]);
    }
    return primaries;
  }

  /// The candidates for a later copy of a piece in a hurry, the one expected to deliver first first, at the costs
  /// [assign] gives unknown, full and not yet delivering nodes. A copy is one request, not a share of a segment, so
  /// a node carrying more than half may take it.
  static List<String> byExpectedFinish(
    List<String> urls, {
    required int pieceBytes,
    required NodeStats nodes,
    required bool Function(String url) delivered,
  }) {
    final expected = [for (final url in urls) nodes.expectedMs(url, pieceBytes: pieceBytes)];
    final best = _min(expected);
    final costs = [
      for (var index = 0; index < urls.length; index++)
        _cost(
          expected: expected[index],
          best: best,
          inflight: nodes.inflight(urls[index]),
          crowded: false,
          delivered: delivered(urls[index]),
          full: nodes.isFull(urls[index]),
        ),
    ];
    final order = List<int>.generate(urls.length, (index) => index)
      ..sort((a, b) {
        final byCost = costs[a].compareTo(costs[b]);
        return byCost != 0 ? byCost : a.compareTo(b);
      });
    return [for (final index in order) urls[index]];
  }

  static double? _min(List<double?> values) {
    double? best;
    for (final value in values) {
      if (value != null && (best == null || value < best)) best = value;
    }
    return best;
  }

  /// A node not measured yet costs twice the best known one, times its pieces in flight plus one.
  static double _cost({
    required double? expected,
    required double? best,
    required int inflight,
    required bool crowded,
    required bool delivered,
    required bool full,
  }) {
    var cost = expected ?? (best != null ? best * 2 * (inflight + 1) : inflight.toDouble());
    if (crowded) cost += 1e5;
    if (!delivered) cost += 1;
    if (full) cost += 1e6;
    return cost;
  }
}
