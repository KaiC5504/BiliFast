// Port of Bilibili-thread-ripper (see LICENSE-BTR.txt), by way of BiliNative's HurryPlacement.swift.

import 'dart:math';

import 'node_catalog.dart';
import 'node_stats.dart';

/// Which node each piece of a range in a hurry tries first: the one expected to deliver it first, counting
/// the pieces already placed on it (BTR PR 11 `pick`). One measurement must not decide where a whole segment
/// goes while the player is short of data: a node can take seconds over a part of the file it has not served
/// lately. So unknown nodes take a share and, with three or more hosts, no node takes more than half.
abstract final class HurryPlacement {
  /// With `NodeStats.exploreInHurry` off, a node under this share of the best known speed stays out of a hurry. On
  /// the phone (Swift, 13.9k pieces) cosov ran at 1.5 MB/s and the HK nodes at 0.2 against Akamai's 17.5, aliov 4.4:
  /// cosov and the HK nodes finished the last piece of 16% of segments, taking 0.8-1.8 s at p50.
  static const slowShare = 8;

  /// A backup copy for the tail is due when the copy it backs up would need this many times as long as a fresh
  /// copy on the backup's node, and [tailMarginMs] more.
  static const tailFactor = 3;
  static const tailMarginMs = 150.0;

  static List<String> assign({
    required List<String> urls,
    required int count,
    required int pieceBytes,
    required NodeStats nodes,
    required bool Function(String url) delivered,
  }) {
    if (urls.isEmpty || count <= 0) return const [];
    if (!nodes.exploreInHurry) urls = kept(urls, nodes);
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
          firstByte: _firstByteFloor(url, nodes),
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
  /// a node carrying more than half may take it. Without exploring, the nodes [kept] leaves out go after the rest:
  /// unknown ones before full ones, far slower ones last.
  static List<String> byExpectedFinish(
    List<String> urls, {
    required int pieceBytes,
    required NodeStats nodes,
    required bool Function(String url) delivered,
  }) {
    final expected = [for (final url in urls) nodes.expectedMs(url, pieceBytes: pieceBytes)];
    final best = _min(expected);
    final settled = nodes.exploreInHurry ? null : kept(urls, nodes).toSet();
    double leftOut(String url) => settled == null || settled.contains(url) ? 0 : (nodes.isKnown(url) ? 1e7 : 1e5);
    final costs = [
      for (var index = 0; index < urls.length; index++)
        _cost(
              expected: expected[index],
              best: best,
              inflight: nodes.inflight(urls[index]),
              crowded: false,
              delivered: delivered(urls[index]),
              full: nodes.isFull(urls[index]),
              firstByte: _firstByteFloor(urls[index], nodes),
            ) +
            leftOut(urls[index]),
    ];
    final order = List<int>.generate(urls.length, (index) => index)
      ..sort((a, b) {
        final byCost = costs[a].compareTo(costs[b]);
        return byCost != 0 ? byCost : a.compareTo(b);
      });
    return [for (final index in order) urls[index]];
  }

  /// The candidates a hurry keeps to when it does not explore: nodes under 1/[slowShare] of the best known speed
  /// are left out, and nodes not known yet once two known nodes (hosts) remain. With nothing known, all of [urls].
  static List<String> kept(List<String> urls, NodeStats nodes) {
    final speeds = [for (final url in urls) nodes.bps(url)];
    final best = speeds.fold(0.0, max);
    if (best <= 0) return urls;
    final fast = [
      for (var index = 0; index < urls.length; index++)
        if (speeds[index] >= best / slowShare) urls[index],
    ];
    if (fast.map(NodeCatalog.nodeKey).toSet().length >= 2) return fast;
    // One measurement must not decide a whole segment: unknown nodes keep their share until a second node is known.
    return [
      for (var index = 0; index < urls.length; index++)
        if (speeds[index] <= 0 || speeds[index] >= best / slowShare) urls[index],
    ];
  }

  /// BiliFast: whether the copy of the last unfinished piece of a range in a hurry should get its backup copy on
  /// [backupURL] (where the next copy would go) now, because the copy on [url] is expected to finish more than
  /// [tailFactor] times later than a fresh copy there would. `PieceDownloader.hurryHedgeDue` holds a copy to its own
  /// node's expected time, so a slow node's copy waits up to 600 ms for its first byte and then twice its slow
  /// expected time, and not at all once three quarters are in: on the phone the last piece of a segment, when cosov
  /// or an HK node had it, took 0.8-1.8 s at p50 and up to 5.5 s at p90, while Akamai answers a 64 KiB piece in tens
  /// of milliseconds. [elapsedMs] runs from the copy's request; [receivingMs] from its first byte (null before it);
  /// [resumedBytes] is the prefix the copy resumed from and [receivedBytes] what it has received since. Off unless
  /// `NodeStats.tailBackups`.
  static bool tailBackupDue({
    required String url,
    required String backupURL,
    required NodeStats nodes,
    required int pieceBytes,
    required double elapsedMs,
    required double? receivingMs,
    required int receivedBytes,
    int resumedBytes = 0,
  }) {
    if (!nodes.tailBackups || NodeCatalog.nodeKey(url) == NodeCatalog.nodeKey(backupURL)) return false;
    final arrived = resumedBytes + receivedBytes;
    final left = pieceBytes - arrived;
    if (left <= 0) return false;
    final double remaining;
    if (receivingMs == null) {
      final expected = nodes.expectedMs(url, pieceBytes: left);
      if (expected == null) return false;
      final ttfb = nodes.ttfbMs(url);
      // Past its usual first byte the node is late by an unknown amount; at least the transfer is left.
      remaining = max(0.0, ttfb - elapsedMs) + (expected - ttfb);
    } else if (receivedBytes > 0 && receivingMs >= 100) {
      remaining = left * receivingMs / receivedBytes;
    } else {
      final bps = nodes.bps(url);
      if (bps <= 0) return false;
      remaining = left * 1000 / bps;
    }
    // A backup resumes from what has arrived once that is worth keeping (`PieceDownloader.resumeMinBytes`).
    final copy = nodes.expectedMs(backupURL, pieceBytes: arrived >= 32 * 1024 ? left : pieceBytes);
    if (copy == null) return false;
    return remaining >= max(copy * tailFactor, copy + tailMarginMs);
  }

  static double? _min(List<double?> values) {
    double? best;
    for (final value in values) {
      if (value != null && (best == null || value < best)) best = value;
    }
    return best;
  }

  /// With priors, a node whose speed is unknown still costs at least its known first byte. A node that never
  /// finishes a piece in a hurry (every copy outrun) is remembered by its first byte alone: priced at twice the best
  /// node's time, the HK nodes, ~500 ms to a first byte, kept taking pieces, now with a 600 ms hedge budget.
  static double _firstByteFloor(String url, NodeStats nodes) => nodes.priors.isEmpty ? 0 : nodes.ttfbMs(url);

  /// A node not measured yet costs twice the best known one, times its pieces in flight plus one.
  static double _cost({
    required double? expected,
    required double? best,
    required int inflight,
    required bool crowded,
    required bool delivered,
    required bool full,
    double firstByte = 0,
  }) {
    var cost = expected ?? (best != null ? max(best * 2 * (inflight + 1), firstByte) : inflight.toDouble());
    if (crowded) cost += 1e5;
    if (!delivered) cost += 1;
    if (full) cost += 1e6;
    return cost;
  }
}
