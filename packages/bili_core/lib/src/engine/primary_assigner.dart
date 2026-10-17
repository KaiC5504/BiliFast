// Port of Bilibili-thread-ripper (see LICENSE-BTR.txt), by way of BiliNative's PrimaryAssigner.swift.

import 'dart:math';

import 'node_catalog.dart';

final class _TrialState {
  int waited = 0;
  int cursor = 0;
}

/// BTR `assignPrimaries` (port of PrimaryAssigner.swift): which node each piece tries first. Faster nodes get
/// more pieces in smooth weighted turns; a node under a twelfth of the fastest gets none; unmeasured nodes get a
/// trial piece or two from the end of the range. A full node (`isFull`, given the pieces placed on it so far)
/// sits its turns out while another node has room.
final class PrimaryAssigner {
  int _turn = 0;
  final _trials = <Object, _TrialState>{};

  List<String> assign({
    required List<String> urls,
    required int count,
    required double Function(String url) speed,
    required Object trialKey,
    bool Function(String url, int placed)? isFull,
  }) {
    final full = isFull ?? (_, _) => false;
    var candidates = urls;
    var remaining = count;
    if (candidates.isEmpty || remaining <= 0) return const [];
    if (candidates.length == 1) return List.filled(remaining, candidates.first);
    final turn = _turn;
    _turn = (_turn + 1) % 4096;
    var known = candidates.map(speed).toList();
    final top = known.reduce(max);
    if (top <= 0) return _turns(candidates, [for (final _ in candidates) 1.0], remaining, turn, full);
    final eligible = [
      for (var index = 0; index < candidates.length; index++)
        if (known[index] == 0 || known[index] >= top / 12) candidates[index],
    ];
    if (eligible.isNotEmpty && eligible.length < candidates.length) {
      candidates = eligible;
      known = candidates.map(speed).toList();
    }
    final unknown = [
      for (var index = 0; index < candidates.length; index++)
        if (known[index] == 0) candidates[index],
    ];
    final spare = min(unknown.length * 2, remaining ~/ 4);
    final trialState = _trials.putIfAbsent(trialKey, _TrialState.new);
    var trials = spare;
    // Small ranges never have a piece to spare; every fourth one gives up its last piece for a trial.
    if (trials == 0 && unknown.isNotEmpty && remaining >= 2) {
      trialState.waited += 1;
      if (trialState.waited >= 4) trials = 1;
    }
    if (trials > 0) trialState.waited = 0;
    final trialCursor = trialState.cursor;
    trialState.cursor = (trialState.cursor + trials) % 4096;
    if (unknown.isNotEmpty) {
      candidates = [
        for (var index = 0; index < candidates.length; index++)
          if (known[index] > 0) candidates[index],
      ];
      known = candidates.map(speed).toList();
      remaining -= trials;
    }
    final primaries = _turns(
      candidates,
      [for (final value in known) max(value, top * 0.05)],
      max(0, remaining),
      turn,
      full,
    );
    for (var index = 0; index < trials; index++) {
      primaries.add(unknown[(index + trialCursor) % unknown.length]);
    }
    return primaries;
  }

  /// Only the nodes taking turns earn credit, so the pieces a full node cannot take are shared out by weight.
  static List<String> _turns(
    List<String> urls,
    List<double> weights,
    int count,
    int turn,
    bool Function(String url, int placed) isFull,
  ) {
    if (urls.isEmpty) return [];
    final keys = urls.map(NodeCatalog.nodeKey).toList();
    final credit = List<double>.filled(urls.length, 0);
    final placed = <String, int>{};
    final order = [for (var index = 0; index < urls.length; index++) (index + turn) % urls.length];
    final primaries = <String>[];
    for (var piece = 0; piece < count; piece++) {
      final open = order.where((index) => !isFull(urls[index], placed[keys[index]] ?? 0)).toList();
      final taking = open.isEmpty ? order : open;
      var best = taking.first;
      for (final index in taking) {
        credit[index] += weights[index];
        if (credit[index] > credit[best]) best = index;
      }
      credit[best] -= taking.fold(0.0, (sum, index) => sum + weights[index]);
      placed[keys[best]] = (placed[keys[best]] ?? 0) + 1;
      primaries.add(urls[best]);
    }
    return primaries;
  }
}
