/// 稍后再看's list.
library;

import 'json.dart';

/// The list's two chips; [viewed] is the website's `viewed` filter.
enum WatchLaterFilter {
  all(0),
  unfinished(2);

  const WatchLaterFilter(this.viewed);

  final int viewed;
}

/// What 一键清除 takes out; [cleanType] is the website's `clean_type`.
enum WatchLaterClean {
  invalid(1),
  watched(2);

  const WatchLaterClean(this.cleanType);

  final int cleanType;
}

final class WatchLaterItem {
  const WatchLaterItem({
    required this.aid,
    required this.bvid,
    required this.cid,
    required this.title,
    required this.cover,
    required this.ownerMid,
    required this.ownerName,
    required this.duration,
    required this.progress,
    required this.play,
    required this.danmaku,
  });

  /// Bangumi and courses share the list but only play in the official app, so they read as undecodable and drop out.
  factory WatchLaterItem.fromJson(Object? json) {
    final object = JsonObject.from(json);
    final bvid = object.string('bvid');
    if (bvid == null || bvid.isEmpty) throw const DecodeError('missing bvid');
    if (object.flag('is_pgc') || object.flag('is_pugv')) throw const DecodeError('not a plain video');
    final aid = object.integer('aid') ?? 0;
    if (aid <= 0) throw const DecodeError('missing aid');
    final owner = object.nested('owner');
    final stat = object.nested('stat');
    return WatchLaterItem(
      aid: aid,
      bvid: bvid,
      cid: object.integer('cid') ?? 0,
      title: object.string('title') ?? '',
      cover: object.string('pic') ?? '',
      ownerMid: owner?.integer('mid') ?? 0,
      ownerName: owner?.string('name') ?? '',
      duration: object.integer('duration') ?? 0,
      progress: object.integer('progress') ?? 0,
      play: stat?.count('view') ?? 0,
      danmaku: stat?.count('danmaku') ?? 0,
    );
  }

  final int aid;
  final String bvid;
  final int cid;
  final String title;
  final String cover;
  final int ownerMid;
  final String ownerName;

  /// Seconds.
  final int duration;

  /// Seconds watched; -1 means watched to the end, 0 not started.
  final int progress;
  final int play;
  final int danmaku;

  @override
  bool operator ==(Object other) =>
      other is WatchLaterItem &&
      other.aid == aid &&
      other.bvid == bvid &&
      other.cid == cid &&
      other.title == title &&
      other.cover == cover &&
      other.ownerMid == ownerMid &&
      other.ownerName == ownerName &&
      other.duration == duration &&
      other.progress == progress &&
      other.play == play &&
      other.danmaku == danmaku;

  @override
  int get hashCode => Object.hash(aid, bvid, cid, title, cover, ownerMid, ownerName, duration, progress, play, danmaku);

  @override
  String toString() => 'WatchLaterItem($bvid)';
}

final class WatchLaterListPage {
  const WatchLaterListPage({required this.items, required this.total, required this.hasMore});

  static const empty = WatchLaterListPage(items: [], total: 0, hasMore: false);

  /// The website's `ps`.
  static const size = 20;

  final List<WatchLaterItem> items;

  /// The server's count for the filter, rows that don't play here included.
  final int total;
  final bool hasMore;

  @override
  bool operator ==(Object other) =>
      other is WatchLaterListPage && listEquals(other.items, items) && other.total == total && other.hasMore == hasMore;

  @override
  int get hashCode => Object.hash(Object.hashAll(items), total, hasMore);
}
