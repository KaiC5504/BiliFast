import 'dart:math';

import '../shared/byte_range.dart';
import '../shared/clock.dart';
import 'ban_list.dart';
import 'node_catalog.dart';
import 'playback_engine.dart';

final class _Health {
  int failures = 0;
  double blockedUntil = 0;
}

/// Speed knowledge per node and file, without the query: a fresh signature is the same route.
final class _Route {
  double lastSuccessAt = 0;
  double lastMeasuredAt = 0;
  double bps = 0;
}

/// BTR `createResolver`, one per track (port of Resolver.swift).
final class Resolver {
  Resolver({
    required String primary,
    required List<String> backups,
    required this.mode,
    this.policy = MediaURLPolicy.bilibili,
    this.bans,
    MonotonicClock? clock,
  })  : _primary = primary,
        _backups = backups,
        _clock = clock ?? MonotonicClock.system;

  /// A node left out for being slow goes back to the untested ones after this and gets another try.
  static const measurementTTL = 90000.0;

  /// Akamai's damaged copy of one file (2026-10-16) failed from the first missing byte to the end of that MiB
  /// and served the next MiB whole, so an edge's damage is taken to end at the next MiB boundary.
  static const damageBlock = 1 << 20;

  /// Damage on more blocks of one file than this is a failing node, not a damaged copy.
  static const damagedBlockLimit = 2;

  final NodeMode mode;
  final MediaURLPolicy policy;
  final BanList? bans;
  final MonotonicClock _clock;

  String _primary;
  List<String> _backups;
  var _health = <String, _Health>{};
  final _routes = <String, _Route>{};
  int _cursor = 0;
  int _mediaRangeCount = 0;
  int _rangeCursor = 0;

  /// Per route: the first missing byte seen in each damaged block of that node's copy, by block index.
  var _damage = <String, Map<int, int>>{};

  /// Nodes that have sent bytes, even in copies that were cut or cancelled.
  final _streamed = <String>{};

  void replaceURLs({required String primary, required List<String> backups}) {
    _primary = primary;
    _backups = backups;
  }

  /// After a network change, failures seen on the old path say nothing about the new one. A new
  /// interface also invalidates the measured speeds, so the next ranges measure wide again.
  void resetHealth({required bool clearMeasurements}) {
    _health = {};
    _damage = {};
    if (!clearMeasurements) return;
    for (final route in _routes.values) {
      route
        ..bps = 0
        ..lastMeasuredAt = 0;
    }
    _mediaRangeCount = 0;
  }

  List<String> allURLs() =>
      NodeCatalog.representationURLs(primary: _primary, backups: _backups, mode: mode, policy: policy);

  /// Banned addresses are left out, unless that would leave none at all.
  List<String> urls() => _unbanned(allURLs());

  bool allows(String url) => bans?.allows(url) ?? true;

  List<String> _unbanned(List<String> list) {
    final bans = this.bans;
    if (bans == null) return list;
    final allowed = list.where(bans.allows).toList();
    return allowed.isEmpty ? list : allowed;
  }

  static String routeKey(String url) {
    final uri = Uri.tryParse(url);
    return uri == null ? url : NodeCatalog.nodeKey(url) + uri.path;
  }

  bool _measuredNow(String url, double now) {
    final route = _routes[routeKey(url)];
    return route != null && route.lastMeasuredAt > 0 && now - route.lastMeasuredAt < measurementTTL;
  }

  int _fasterFirst(String left, String right) {
    final l = _routes[routeKey(left)];
    final r = _routes[routeKey(right)];
    final lProven = (l?.lastSuccessAt ?? 0) > 0;
    final rProven = (r?.lastSuccessAt ?? 0) > 0;
    if (lProven != rProven) return lProven ? -1 : 1;
    return (r?.bps ?? 0).compareTo(l?.bps ?? 0);
  }

  bool _open(String url, double now) => (_health[url]?.blockedUntil ?? 0) <= now;

  /// Stable (List.sort does not promise it), so equally fast nodes keep the catalog's order.
  List<String> _sortedFasterFirst(Iterable<String> urls) {
    final list = urls.toList();
    final order = List<int>.generate(list.length, (index) => index)
      ..sort((a, b) {
        final bySpeed = _fasterFirst(list[a], list[b]);
        return bySpeed != 0 ? bySpeed : a.compareTo(b);
      });
    return [for (final index in order) list[index]];
  }

  List<String> ordered({int pieceIndex = 0, Set<String> excluding = const {}}) {
    final list = urls().where((url) => !excluding.contains(url)).toList();
    final now = _clock.nowMs();
    final available = list.where((url) => _open(url, now)).toList();
    final pool = available.isEmpty ? list : available;
    if (pool.isEmpty) return const [];
    final offset = (_cursor + pieceIndex) % pool.length;
    _cursor = (_cursor + 1) % pool.length;
    return [...pool.sublist(offset), ...pool.sublist(0, offset)];
  }

  /// The nodes for one media range. The first ranges (four overseas, one mainland) go wide to
  /// measure; afterwards measured nodes carry the work, fastest first, and one unmeasured or
  /// stale node rides along per range as exploration.
  List<String> rangeCandidates() {
    final list = urls();
    final now = _clock.nowMs();
    final warmup = mode is MainlandNodes ? 1 : 4;
    final pool = _sortedFasterFirst(list.where((url) => _open(url, now)));
    if (pool.isEmpty) return list;
    final width = min(_mediaRangeCount == 0 ? pool.length : 6, pool.length);
    List<String> selected;
    if (_mediaRangeCount < warmup) {
      selected = pool.take(width).toList();
      _rangeCursor = width % pool.length;
    } else {
      final measured = pool.where((url) => _measuredNow(url, now)).toList();
      final rest = pool.where((url) => !_measuredNow(url, now)).toList();
      final places = min(rest.length, max(1, width - measured.length));
      final explore = [for (var index = 0; index < places; index++) rest[(_rangeCursor + index) % rest.length]];
      _rangeCursor = (_rangeCursor + places) % max(1, pool.length);
      selected = [...measured.take(max(0, width - explore.length)), ...explore];
      for (final url in pool) {
        if (selected.length >= min(3, pool.length)) break;
        if (!selected.contains(url)) selected.add(url);
      }
    }
    _mediaRangeCount++;
    return selected;
  }

  /// The first request of a track races Bilibili's own addresses too (not in custom mode).
  List<String> startupCandidates() {
    final now = _clock.nowMs();
    final originals = mode is CustomNodes ? const <String>[] : [_primary, ..._backups].where(policy.allowsURL);
    final candidates = _unbanned(NodeCatalog.deduplicated([...originals, ...allURLs()]));
    return candidates.where((url) => _open(url, now)).take(8).toList();
  }

  List<String> rescueCandidates() {
    final now = _clock.nowMs();
    return _sortedFasterFirst(urls().where((url) => _open(url, now)));
  }

  void success(String url, {required double bps}) {
    bans?.success(url);
    final now = _clock.nowMs();
    _health.remove(url);
    final route = _routes.putIfAbsent(routeKey(url), _Route.new);
    route.lastSuccessAt = now;
    if (bps > 0) {
      route
        ..lastMeasuredAt = now
        ..bps = route.bps > 0 ? route.bps * 0.65 + bps * 0.35 : bps;
    }
  }

  /// The speed of a transfer cut off before its end (it lost a race): the node's speed, not proof
  /// that the address works.
  void sample(String url, {required double bps}) {
    if (bps <= 0) return;
    final route = _routes.putIfAbsent(routeKey(url), _Route.new);
    route
      ..lastMeasuredAt = _clock.nowMs()
      ..bps = route.bps > 0 ? route.bps * 0.65 + bps * 0.35 : bps;
  }

  /// The node's copy of this file is known to be damaged somewhere in [range].
  bool avoids(String url, ByteRange range) {
    final blocks = _damage[routeKey(url)];
    if (blocks == null) return false;
    return blocks.entries.any((entry) => range.start < (entry.key + 1) * damageBlock && range.end >= entry.value);
  }

  /// A copy of this node sent bytes before it was cancelled.
  void streamed(String url) => _streamed.add(NodeCatalog.nodeKey(url));

  /// [range] is the part this attempt asked for. A copy of a node that is up (it has sent bytes) which breaks
  /// off without a status, short of the end and not by a timeout, is a damaged copy at that position: the span
  /// is avoided on that node, without strikes or backoff. Damage in a third block is struck as before and not
  /// recorded. A network change forgets all damage.
  void failure(String url, {int? status, required int receivedBytes, ByteRange? range, bool timedOut = false}) {
    final delivered = bans?.hasDelivered(url) ?? false;
    final node = NodeCatalog.nodeKey(url);
    final key = routeKey(url);
    if (receivedBytes > 0) _streamed.add(node);
    if (range != null &&
        status == null &&
        !timedOut &&
        receivedBytes < range.length &&
        (delivered || _streamed.contains(node) || (_routes[key]?.lastSuccessAt ?? 0) > 0)) {
      final offset = range.start + receivedBytes;
      final blocks = _damage[key] ?? <int, int>{};
      final block = offset ~/ damageBlock;
      if (blocks[block] != null || blocks.length < damagedBlockLimit) {
        blocks[block] = min(blocks[block] ?? offset, offset);
        _damage[key] = blocks;
        return;
      }
    }
    final now = _clock.nowMs();
    bans?.record(url, receivedBytes: receivedBytes, status: status, lostAt: status == null && !timedOut ? now : null);
    final health = _health.putIfAbsent(url, _Health.new);
    health
      ..failures += 1
      ..blockedUntil = now + min(60000, 3000 * pow(2, min(health.failures, 4))).toDouble();
  }

  /// Measured bytes per second of one connection to this node, 0 when unknown or stale.
  double speed(String url) => _measuredNow(url, _clock.nowMs()) ? (_routes[routeKey(url)]?.bps ?? 0) : 0;

  List<NodeStatus> status() {
    final all = allURLs();
    final bans = this.bans;
    final usable = bans == null ? all : all.where(bans.allowsAddress).toList();
    final list = usable.isEmpty ? all : usable;
    final now = _clock.nowMs();
    return [
      for (final url in list)
        NodeStatus(
          node: NodeCatalog.nodeKey(url),
          state: !(bans?.allows(url) ?? true)
              ? 'banned'
              : (_health[url]?.blockedUntil ?? 0) > now
                  ? 'blocked'
                  : (_routes[routeKey(url)]?.lastSuccessAt ?? 0) > 0
                      ? 'healthy'
                      : 'untested',
          bps: _routes[routeKey(url)]?.bps ?? 0,
        ),
    ];
  }
}
