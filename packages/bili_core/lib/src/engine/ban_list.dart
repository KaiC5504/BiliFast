// Port of Bilibili-thread-ripper (see LICENSE-BTR.txt), by way of BiliNative's BanList.swift.

import 'dart:math';

import '../shared/clock.dart';
import 'node_catalog.dart';

enum BanKind { node, address, pair }

final class _Turn {
  _Turn(this.at, this.intervalMs);

  double at;
  double intervalMs;
}

/// BiliFast: when a node banned for silent failures may carry one backup copy, so that a success can lift the ban
/// ([BanList.success] heals silent strikes). The first turn comes [firstMs] after the ban and each turn taken
/// doubles the wait, up to [capMs]. Build 100 banned Akamai, the fastest node, about 96 s into a video and stalled
/// 7 times after; one Swift cold jump banned both of the fastest nodes for the rest of the video.
final class BanProbation {
  BanProbation({MonotonicClock? clock, this.firstMs = 15000, this.capMs = 120000})
      : _clock = clock ?? MonotonicClock.system;

  final double firstMs;
  final double capMs;
  final MonotonicClock _clock;
  final _turns = <String, _Turn>{};

  void _start(String node) => _turns[node] = _Turn(_clock.nowMs() + firstMs, firstMs);

  /// Started at the ban; lazily for a ban from before probation was switched on.
  _Turn _turn(String node) => _turns.putIfAbsent(node, () => _Turn(_clock.nowMs() + firstMs, firstMs));

  bool _due(String node) => _clock.nowMs() >= _turn(node).at;

  void _take(String node) {
    final turn = _turn(node);
    turn
      ..intervalMs = min(capMs, turn.intervalMs * 2)
      ..at = _clock.nowMs() + turn.intervalMs;
  }
}

/// BTR `createBanList`. A node that twice fails without sending a byte is skipped for the rest of
/// the video. For HTTP 4xx, what has delivered decides who is blamed: a refusal by a node that
/// serves other addresses blames the address; a refusal of an address other nodes serve blames
/// only that node and address pair.
final class BanList {
  BanList({int limit = 2}) : _limit = limit < 1 ? 1 : limit;

  /// Losses within this long of the first one of a moment are that moment. BTR's retry rounds pause at least
  /// 500 ms, so a node that drops every request is still struck again by the next round.
  static const lossMomentMs = 250.0;

  final int _limit;
  var _emptyReplies = <String, int>{};
  var _goodNodes = <String>{};
  var _goodAddresses = <String>{};
  var _reported = <String>{};
  var _banned = <String>{};
  var _lossMomentAt = double.negativeInfinity;

  void Function(String node, int strikes, BanKind kind)? onBan;

  /// Null (Swift): a banned node gets no more work for the rest of the video.
  BanProbation? probation;

  /// [lostAt] (monotonic ms) is when a request lost its connection before any byte. Requests that lose it at
  /// one moment are one strike, whatever their nodes: a network blip or a pool of connections torn down at once,
  /// not a node failing twice. Two Akamai requests lost theirs 2 ms apart and banned the fastest node for the
  /// rest of the video (phone, 2026-10-17).
  bool record(String url, {required int receivedBytes, int? status, double? lostAt}) {
    if (receivedBytes != 0) return false;
    final node = NodeCatalog.nodeKey(url);
    if (node.isEmpty) return false;
    final refused = status != null && status >= 400 && status < 500;
    final key = '$node\n${NodeCatalog.address(url)}\n${refused ? 'refused' : ''}';
    if (lostAt != null) {
      if (lostAt - _lossMomentAt < lossMomentMs) return false;
      _lossMomentAt = lostAt;
    }
    _emptyReplies[key] = (_emptyReplies[key] ?? 0) + 1;
    final added = _judge();
    _report(added, url);
    return added.isNotEmpty;
  }

  void success(String url) {
    final node = NodeCatalog.nodeKey(url);
    final address = NodeCatalog.address(url);
    if (node.isEmpty) return;
    // Deviation from BTR: blip strikes heal on success, so a local network drop cannot ban the fastest nodes for good.
    final silent = _emptyReplies.keys.where((key) => key.startsWith('$node\n') && key.endsWith('\n')).toList();
    for (final key in silent) {
      _emptyReplies.remove(key);
    }
    if (silent.isEmpty && _goodNodes.contains(node) && _goodAddresses.contains(address)) return;
    _goodNodes.add(node);
    _goodAddresses.add(address);
    final added = _judge();
    if (silent.isNotEmpty) {
      _reported = _reported.where((key) => !key.startsWith('node:') || _banned.contains(key)).toSet();
    }
    _report(added, url);
  }

  bool allows(String url) {
    final node = NodeCatalog.nodeKey(url);
    final address = NodeCatalog.address(url);
    return !_banned.contains('node:$node') && !_banned.contains('address:$address') &&
        !_banned.contains('pair:$node $address');
  }

  bool allowsNode(String url) => !_banned.contains('node:${NodeCatalog.nodeKey(url)}');

  bool hasDelivered(String url) => _goodNodes.contains(NodeCatalog.nodeKey(url));

  bool allowsAddress(String url) => !_banned.contains('address:${NodeCatalog.address(url)}');

  List<String> bannedNodes() =>
      [for (final key in _banned) if (key.startsWith('node:')) key.substring(5)]..sort();

  /// [url]'s node is banned for silent failures alone (its address and pair are not) and, with [probation] on, its
  /// next turn for a backup copy has come.
  bool probationDue(String url) {
    final probation = this.probation;
    if (probation == null || allowsNode(url) || !_allowsAddressAndPair(url)) return false;
    return probation._due(NodeCatalog.nodeKey(url));
  }

  /// A backup copy on [url] is under way: the node's next turn waits twice as long (up to the cap).
  void takeProbation(String url) => probation?._take(NodeCatalog.nodeKey(url));

  bool _allowsAddressAndPair(String url) {
    final node = NodeCatalog.nodeKey(url);
    final address = NodeCatalog.address(url);
    return !_banned.contains('address:$address') && !_banned.contains('pair:$node $address');
  }

  void reset() {
    _emptyReplies = {};
    _goodNodes = {};
    _goodAddresses = {};
    _reported = {};
    _banned = {};
    _lossMomentAt = double.negativeInfinity;
    probation?._turns.clear();
  }

  List<(String, int)> _judge() {
    final strikes = <String, int>{};
    for (final MapEntry(:key, value: count) in _emptyReplies.entries) {
      final parts = key.split('\n');
      final node = parts[0];
      final address = parts[1];
      final refused = parts[2] == 'refused';
      final String blamed;
      if (!refused) {
        blamed = 'node:$node';
      } else if (_goodNodes.contains(node)) {
        blamed = _goodAddresses.contains(address) ? 'pair:$node $address' : 'address:$address';
      } else if (_goodAddresses.contains(address)) {
        // Deviation from BTR, which blames the node: a refused address can be that node's alone (Akamai
        // refusing os=cosovbv but serving os=akam), and a banned node never gets to prove its other
        // addresses. Counting refused addresses per node would not help: both tracks and every new
        // signature are further addresses.
        blamed = 'pair:$node $address';
      } else {
        blamed = '';
      }
      if (blamed.isNotEmpty) strikes[blamed] = (strikes[blamed] ?? 0) + count;
    }
    _banned = {for (final MapEntry(:key, :value) in strikes.entries) if (value >= _limit) key};
    final added = <(String, int)>[];
    for (final key in _banned.toList()..sort()) {
      if (_reported.add(key)) added.add((key, strikes[key] ?? 0));
    }
    final probation = this.probation;
    if (probation != null) {
      probation._turns.removeWhere((node, _) => !_banned.contains('node:$node'));
      // A node banned again after a probation success starts over from the first wait.
      for (final (key, _) in added) {
        if (key.startsWith('node:')) probation._start(key.substring(5));
      }
    }
    return added;
  }

  void _report(List<(String, int)> added, String url) {
    final handler = onBan;
    if (handler == null) return;
    for (final (key, strikes) in added) {
      if (key.startsWith('node:')) {
        handler(key.substring(5), strikes, BanKind.node);
      } else if (key.startsWith('pair:')) {
        // Another node's success can complete a pair ban, so the node comes from the key, not the URL.
        final rest = key.substring(5);
        final space = rest.indexOf(' ');
        handler(space < 0 ? rest : rest.substring(0, space), strikes, BanKind.pair);
      } else {
        handler(NodeCatalog.nodeKey(url), strikes, BanKind.address);
      }
    }
  }
}
