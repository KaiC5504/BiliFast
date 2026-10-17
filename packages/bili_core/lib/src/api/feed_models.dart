import 'json.dart';

final class FeedCard {
  const FeedCard({
    required this.aid,
    required this.bvid,
    required this.cid,
    required this.title,
    required this.cover,
    required this.duration,
    required this.views,
    required this.danmaku,
    required this.ownerName,
    required this.ownerMid,
    required this.reason,
    required this.isVertical,
  });

  factory FeedCard.fromJson(Object? json) {
    final object = JsonObject.from(json);
    final bvid = object.string('bvid');
    if (bvid == null || bvid.isEmpty) throw const DecodeError('missing bvid');
    final owner = object.nested('owner');
    final stat = object.nested('stat');
    final reason = object.nested('rcmd_reason')?.string('content');
    return FeedCard(
      // The web feed names the aid `id`.
      aid: object.integer('id', 'aid') ?? 0,
      bvid: bvid,
      cid: object.integer('cid') ?? 0,
      title: object.string('title') ?? '',
      cover: object.string('pic') ?? '',
      duration: object.integer('duration') ?? 0,
      views: stat?.count('view') ?? 0,
      danmaku: stat?.count('danmaku') ?? 0,
      ownerName: owner?.string('name') ?? '',
      ownerMid: owner?.integer('mid') ?? 0,
      reason: reason == null || reason.isEmpty ? null : reason,
      isVertical: attempt(() => _isVertical(object.nested('dimension'))) ?? false,
    );
  }

  /// A file stored rotated (`rotate == 1`) is shown with width and height swapped, as in `VideoDetail`.
  /// The web feed sends no `dimension` at all, so this is false for every card it returns today.
  static bool _isVertical(JsonObject? dimension) {
    final width = dimension?.integer('width') ?? 0;
    final height = dimension?.integer('height') ?? 0;
    final rotated = dimension?.integer('rotate') == 1;
    return rotated ? width > height : height > width;
  }

  final int aid;
  final String bvid;
  final int cid;
  final String title;
  final String cover;
  final int duration;
  final int views;
  final int danmaku;
  final String ownerName;
  final int ownerMid;

  /// `rcmd_reason.content`, such as "2万点赞"; null when the server gave no reason.
  final String? reason;
  final bool isVertical;

  String get id => bvid;

  @override
  bool operator ==(Object other) =>
      other is FeedCard &&
      other.aid == aid &&
      other.bvid == bvid &&
      other.cid == cid &&
      other.title == title &&
      other.cover == cover &&
      other.duration == duration &&
      other.views == views &&
      other.danmaku == danmaku &&
      other.ownerName == ownerName &&
      other.ownerMid == ownerMid &&
      other.reason == reason &&
      other.isVertical == isVertical;

  @override
  int get hashCode =>
      Object.hash(aid, bvid, cid, title, cover, duration, views, danmaku, ownerName, ownerMid, reason, isVertical);
}

enum HistoryDeviceKind { phone, pc, padOrTV }

final class HistoryItem {
  const HistoryItem({
    required this.bvid,
    required this.cid,
    required this.title,
    required this.cover,
    required this.ownerName,
    required this.progress,
    required this.duration,
    required this.viewAt,
    required this.device,
    required this.part,
  });

  factory HistoryItem.fromJson(Object? json) {
    final object = JsonObject.from(json);
    final history = object.nested('history');
    final bvid = history?.string('bvid');
    if (bvid == null || bvid.isEmpty) throw const DecodeError('missing bvid');
    // The request already asks for videos only; this keeps a bangumi or live row out if the filter is ever ignored.
    final business = history?.string('business');
    if (business != null && business.isNotEmpty && business != 'archive') {
      throw const DecodeError('missing archive business');
    }
    final part = history?.string('part');
    return HistoryItem(
      bvid: bvid,
      cid: history?.integer('cid') ?? 0,
      title: object.string('title') ?? '',
      cover: object.string('cover') ?? '',
      ownerName: object.string('author_name') ?? '',
      progress: object.integer('progress') ?? 0,
      duration: object.integer('duration') ?? 0,
      viewAt: object.integer('view_at') ?? 0,
      device: history?.integer('dt') ?? 0,
      part: part == null || part.isEmpty ? null : part,
    );
  }

  final String bvid;
  final int cid;
  final String title;
  final String cover;
  final String ownerName;

  /// Seconds watched; -1 means watched to the end.
  final int progress;
  final int duration;
  final int viewAt;

  /// `history.dt`, the platform the video was watched on.
  final int device;
  final String? part;

  /// One video can come back on two pages when it is watched again between loads, so the time is part of the identity.
  String get id => '$bvid@$viewAt';

  HistoryDeviceKind get deviceKind => switch (device) {
    1 || 3 || 5 || 7 => HistoryDeviceKind.phone,
    2 || 33 => HistoryDeviceKind.pc,
    _ => HistoryDeviceKind.padOrTV,
  };

  @override
  bool operator ==(Object other) =>
      other is HistoryItem &&
      other.bvid == bvid &&
      other.cid == cid &&
      other.title == title &&
      other.cover == cover &&
      other.ownerName == ownerName &&
      other.progress == progress &&
      other.duration == duration &&
      other.viewAt == viewAt &&
      other.device == device &&
      other.part == part;

  @override
  int get hashCode => Object.hash(bvid, cid, title, cover, ownerName, progress, duration, viewAt, device, part);
}

/// Where the next page of history starts: the last row's target id and view time.
final class HistoryCursor {
  const HistoryCursor({required this.max, required this.viewAt});

  final int max;
  final int viewAt;

  @override
  bool operator ==(Object other) => other is HistoryCursor && other.max == max && other.viewAt == viewAt;

  @override
  int get hashCode => Object.hash(max, viewAt);

  @override
  String toString() => 'HistoryCursor(max: $max, viewAt: $viewAt)';
}

final class HistoryPage {
  const HistoryPage({required this.items, required this.next});

  final List<HistoryItem> items;

  /// null once there is nothing further to load.
  final HistoryCursor? next;

  @override
  bool operator ==(Object other) => other is HistoryPage && listEquals(other.items, items) && other.next == next;

  @override
  int get hashCode => Object.hash(Object.hashAll(items), next);
}
