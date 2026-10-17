// Port of BTR's createResolver (see LICENSE-BTR.txt), by way of BiliNative's Resolver.swift and BanList.swift.
// Left out for the spike: damaged-span avoidance, address-scoped bans, network-change resets.

import 'dart:math';

import 'node_catalog.dart';

double nowMs() => DateTime.now().microsecondsSinceEpoch / 1000.0;

class _Health {
  int failures = 0;
  double blockedUntil = 0;
}

class _Route {
  double lastSuccessAt = 0;
  double lastMeasuredAt = 0;
  double bps = 0;
}

/// One per track: which addresses to ask, fastest first, and which to rest.
class Resolver {
  Resolver(this.primary, this.backups, this.mode, this.bans);

  String primary;
  List<String> backups;
  final NodeMode mode;
  final BanList bans;
  final _health = <String, _Health>{};
  final _routes = <String, _Route>{};
  int _cursor = 0;
  int _mediaRangeCount = 0;
  int _rangeCursor = 0;

  /// A node left out for being slow goes back to the untested ones after this.
  static const measurementTtl = 90000.0;

  List<String> allUrls() => NodeCatalog.representationUrls(primary, backups, mode);

  List<String> urls() {
    final all = allUrls();
    final allowed = all.where(bans.allows).toList();
    return allowed.isEmpty ? all : allowed;
  }

  bool allows(String url) => bans.allows(url);

  static String _routeKey(String url) {
    final uri = Uri.tryParse(url);
    return uri == null ? url : NodeCatalog.nodeKey(url) + uri.path;
  }

  bool _measuredNow(String url, double now) {
    final r = _routes[_routeKey(url)];
    return r != null && r.lastMeasuredAt > 0 && now - r.lastMeasuredAt < measurementTtl;
  }

  int _fasterFirst(String a, String b) {
    final l = _routes[_routeKey(a)];
    final r = _routes[_routeKey(b)];
    final lp = (l?.lastSuccessAt ?? 0) > 0;
    final rp = (r?.lastSuccessAt ?? 0) > 0;
    if (lp != rp) return lp ? -1 : 1;
    return (r?.bps ?? 0).compareTo(l?.bps ?? 0);
  }

  bool _open(String url, double now) => (_health[url]?.blockedUntil ?? 0) <= now;

  List<String> ordered({int pieceIndex = 0}) {
    final list = urls();
    final now = nowMs();
    final available = list.where((u) => _open(u, now)).toList();
    final pool = available.isEmpty ? list : available;
    if (pool.isEmpty) return const [];
    final offset = (_cursor + pieceIndex) % pool.length;
    _cursor = (_cursor + 1) % pool.length;
    return [...pool.sublist(offset), ...pool.sublist(0, offset)];
  }

  /// The nodes for one media range. The first four ranges go wide to measure; afterwards measured
  /// nodes carry the work, fastest first, and one unmeasured or stale node rides along to explore.
  List<String> rangeCandidates() {
    final list = urls();
    final now = nowMs();
    final pool = list.where((u) => _open(u, now)).toList()..sort(_fasterFirst);
    if (pool.isEmpty) return list;
    final width = min(_mediaRangeCount == 0 ? pool.length : 6, pool.length);
    List<String> selected;
    if (_mediaRangeCount < 4) {
      selected = pool.take(width).toList();
      _rangeCursor = width % pool.length;
    } else {
      final measured = pool.where((u) => _measuredNow(u, now)).toList();
      final rest = pool.where((u) => !_measuredNow(u, now)).toList();
      final places = min(rest.length, max(1, width - measured.length));
      final explore = [for (var i = 0; i < places; i++) rest[(_rangeCursor + i) % rest.length]];
      _rangeCursor = (_rangeCursor + places) % max(1, pool.length);
      selected = [...measured.take(max(0, width - explore.length)), ...explore];
      for (final u in pool) {
        if (selected.length >= min(3, pool.length)) break;
        if (!selected.contains(u)) selected.add(u);
      }
    }
    _mediaRangeCount++;
    return selected;
  }

  /// The first request of a track races Bilibili's own addresses too.
  List<String> startupCandidates() {
    final now = nowMs();
    final originals = [primary, ...backups].where(NodeCatalog.allows);
    final seen = <String>{};
    final merged = [for (final u in [...originals, ...allUrls()]) if (seen.add(u)) u];
    final allowed = merged.where(bans.allows).toList();
    return (allowed.isEmpty ? merged : allowed).where((u) => _open(u, now)).take(8).toList();
  }

  List<String> rescueCandidates() {
    final now = nowMs();
    return urls().where((u) => _open(u, now)).toList()..sort(_fasterFirst);
  }

  void success(String url, double bps) {
    bans.success(url);
    final now = nowMs();
    _health.remove(url);
    final r = _routes.putIfAbsent(_routeKey(url), _Route.new);
    r.lastSuccessAt = now;
    if (bps > 0) {
      r.lastMeasuredAt = now;
      r.bps = r.bps > 0 ? r.bps * 0.65 + bps * 0.35 : bps;
    }
  }

  /// The speed of a transfer cut off before its end (it lost a race).
  void sample(String url, double bps) {
    if (bps <= 0) return;
    final r = _routes.putIfAbsent(_routeKey(url), _Route.new);
    r.lastMeasuredAt = nowMs();
    r.bps = r.bps > 0 ? r.bps * 0.65 + bps * 0.35 : bps;
  }

  void failure(String url, {int? status, required int receivedBytes}) {
    bans.record(url, receivedBytes: receivedBytes, status: status);
    final h = _health.putIfAbsent(url, _Health.new);
    h.failures++;
    h.blockedUntil = nowMs() + min(60000, 3000 * pow(2, min(h.failures, 4)).toDouble());
  }

  /// Measured bytes per second of one connection to this node, 0 when unknown or stale.
  double speed(String url) => _measuredNow(url, nowMs()) ? (_routes[_routeKey(url)]?.bps ?? 0) : 0;

  Map<String, double> nodeSpeeds() => {
        for (final u in allUrls()) NodeCatalog.nodeKey(u): _routes[_routeKey(u)]?.bps ?? 0,
      };
}

/// BTR bans: a node that fails twice without ever delivering is left out; a success heals it.
/// A 4xx on one address from a node that has not delivered yet drops only that node and address pair.
class BanList {
  final _strikes = <String, int>{};
  final _banned = <String>{};
  final _bannedPairs = <String>{};
  final _delivered = <String>{};
  void Function(String node)? onBan;

  static String _pair(String url) {
    final uri = Uri.tryParse(url);
    return '${NodeCatalog.nodeKey(url)}${uri?.path ?? url}';
  }

  bool allows(String url) => !_banned.contains(NodeCatalog.nodeKey(url)) && !_bannedPairs.contains(_pair(url));

  bool hasDelivered(String url) => _delivered.contains(NodeCatalog.nodeKey(url));

  void success(String url) {
    final node = NodeCatalog.nodeKey(url);
    _delivered.add(node);
    _strikes.remove(node);
    _banned.remove(node);
  }

  void record(String url, {required int receivedBytes, int? status}) {
    final node = NodeCatalog.nodeKey(url);
    if (status != null && status >= 400 && status < 500 && !_delivered.contains(node)) {
      _bannedPairs.add(_pair(url));
      return;
    }
    if (receivedBytes > 0) return;
    final strikes = (_strikes[node] ?? 0) + 1;
    _strikes[node] = strikes;
    if (strikes >= 2 && _banned.add(node)) onBan?.call(node);
  }
}
