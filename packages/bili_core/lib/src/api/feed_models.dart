import 'bvid.dart';
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
    this.viewsText,
    this.danmakuText,
    this.dislike,
    this.big,
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

  /// A card of the official app's feed (`/x/v2/feed/index`), which the caller has already found to be a video.
  /// Its counts come as the cover's text ("10.4万", "-"), kept to show as sent.
  factory FeedCard.fromOfficial(Object? json) {
    final object = JsonObject.from(json);
    final player = object.nested('player_args');
    final args = object.nested('args');
    final param = int.tryParse(object.text('param') ?? '');
    final aid = asInt(player?.map['aid']) ?? param ?? asInt(args?.map['aid']) ?? 0;
    if (aid <= 0) throw const DecodeError('missing aid');
    final sentBvid = object.text('bvid');
    final views = object.text('cover_left_text_1');
    final danmaku = object.text('cover_left_text_2');
    var reason = object.text('rcmd_reason');
    final markedVertical = reason == '竖屏';
    if (markedVertical || reason != null && reason.isEmpty) reason = null;
    final goto = object.text('card_goto') ?? object.text('goto') ?? 'av';
    return FeedCard(
      aid: aid,
      bvid: sentBvid == null || sentBvid.isEmpty ? avToBv(aid) : sentBvid,
      cid: asInt(player?.map['cid']) ?? 0,
      title: object.text('title') ?? '',
      cover: object.text('cover') ?? '',
      duration: asInt(player?.map['duration']) ?? 0,
      views: parseCountText(views),
      danmaku: parseCountText(danmaku),
      ownerName: args?.text('up_name') ?? '',
      ownerMid: asInt(args?.map['up_id']) ?? 0,
      reason: reason,
      isVertical: markedVertical || _uriVertical(object.text('uri')),
      viewsText: views,
      danmakuText: danmaku,
      dislike: FeedDislike._from(object.map['three_point_v2'], goto: goto, id: param ?? aid),
    );
  }

  /// The official card's uri names the player's size, which is how the app itself tells a vertical video.
  static bool _uriVertical(String? uri) {
    if (uri == null) return false;
    final query = Uri.tryParse(uri)?.queryParameters ?? const {};
    final width = int.tryParse(query['player_width'] ?? '') ?? 0;
    final height = int.tryParse(query['player_height'] ?? '') ?? 0;
    final rotated = query['player_rotate'] == '1';
    return rotated ? width > height : height > width;
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

  /// The official card's counts as its cover shows them; null on web cards, whose counts are formatted here.
  final String? viewsText;
  final String? danmakuText;

  /// What ⋮'s 不感兴趣 sends; only official cards carry it.
  final FeedDislike? dislike;

  /// Set on the official feed's big card (`large_cover_v9`), drawn full width and playing inline; null on the rest.
  final FeedBig? big;

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
      other.isVertical == isVertical &&
      other.viewsText == viewsText &&
      other.danmakuText == danmakuText &&
      other.dislike == dislike &&
      other.big == big;

  @override
  int get hashCode => Object.hash(
    aid,
    bvid,
    cid,
    title,
    cover,
    duration,
    views,
    danmaku,
    ownerName,
    ownerMid,
    reason,
    isVertical,
    viewsText,
    danmakuText,
    dislike,
    big,
  );
}

/// What the official feed's big card (`inline_av_v2` / `large_cover_v9`) adds to a card: its 👍 and count.
final class FeedBig {
  const FeedBig({required this.likes, required this.showLikes});

  /// `like_button.count`.
  final int likes;

  /// `like_button.show_count`.
  final bool showLikes;

  @override
  bool operator ==(Object other) => other is FeedBig && other.likes == likes && other.showLikes == showLikes;

  @override
  int get hashCode => Object.hash(likes, showLikes);
}

/// A count as the official app writes it ("174", "10.4万", "1.2亿"); "-" and anything else unreadable is 0.
int parseCountText(String? text) {
  if (text == null) return 0;
  final match = RegExp(r'^\s*(\d+(?:\.\d+)?)\s*(万|亿)?').firstMatch(text);
  if (match == null) return 0;
  final scale = switch (match[2]) {
    '万' => 10000,
    '亿' => 100000000,
    _ => 1,
  };
  return (double.parse(match[1]!) * scale).round();
}

/// Which of ⋮'s lists a reason came from: 我不想看 (`dislike`, sent as `reason_id`) or 反馈 (`feedback`, sent as
/// `feedback_id`).
enum FeedReasonKind { dislike, feedback }

final class FeedReason {
  const FeedReason({required this.id, required this.name, required this.kind, this.toast});

  factory FeedReason._fromJson(Object? json, FeedReasonKind kind) {
    final object = JsonObject.from(json);
    final id = asInt(object.map['id']);
    final name = object.text('name');
    if (id == null || name == null || name.isEmpty) throw const DecodeError('reason without id or name');
    return FeedReason(id: id, name: name, kind: kind, toast: object.text('toast'));
  }

  final int id;
  final String name;
  final FeedReasonKind kind;
  final String? toast;

  @override
  bool operator ==(Object other) =>
      other is FeedReason && other.id == id && other.name == name && other.kind == kind && other.toast == toast;

  @override
  int get hashCode => Object.hash(id, name, kind, toast);

  @override
  String toString() => 'FeedReason(${kind.name} $id $name)';
}

/// A card's 不感兴趣 data from `three_point_v2`: what `/x/feed/dislike` names the card by ([goto], [id]) and the
/// reasons it offers.
final class FeedDislike {
  const FeedDislike({required this.goto, required this.id, required this.reasons, required this.feedbacks});

  /// Null when the card offers no reason at all.
  static FeedDislike? _from(Object? groups, {required String goto, required int id}) {
    final reasons = <FeedReason>[];
    final feedbacks = <FeedReason>[];
    for (final group in groups is List ? groups : const <Object?>[]) {
      if (group is! Map<String, Object?>) continue;
      final object = JsonObject(group);
      final kind = switch (object.text('type')) {
        'dislike' => FeedReasonKind.dislike,
        'feedback' => FeedReasonKind.feedback,
        _ => null,
      };
      if (kind == null) continue;
      final decoded = object.lenientList('reasons', (json) => FeedReason._fromJson(json, kind));
      (kind == FeedReasonKind.dislike ? reasons : feedbacks).addAll(decoded);
    }
    if (reasons.isEmpty && feedbacks.isEmpty) return null;
    return FeedDislike(goto: goto, id: id, reasons: reasons, feedbacks: feedbacks);
  }

  final String goto;
  final int id;

  /// 我不想看: the video (不感兴趣), the uploader (UP主:…), the channel and the like.
  final List<FeedReason> reasons;

  /// 反馈: 色情低俗, 标题党/封面党 and the like.
  final List<FeedReason> feedbacks;

  /// ⋮'s 不感兴趣：当前视频 (id 1 in PiliPlus's captures).
  FeedReason? get video =>
      reasons.where((reason) => reason.id == 1 || reason.name == '不感兴趣' || reason.name.contains('当前视频')).firstOrNull;

  /// ⋮'s 不感兴趣：UP (`UP主:<name>`, id 4).
  FeedReason? get uploader => reasons.where((reason) => reason.id == 4 || reason.name.startsWith('UP')).firstOrNull;

  /// The reasons sheet's last row, 该内容已推荐过, from whichever list carries it.
  FeedReason? get repeated => [...feedbacks, ...reasons].where((reason) => reason.name.contains('推荐过')).firstOrNull;

  /// The reasons sheet's tiles: every feedback but [repeated].
  List<FeedReason> get tiles => [
    for (final reason in feedbacks)
      if (!reason.name.contains('推荐过')) reason,
  ];

  @override
  bool operator ==(Object other) =>
      other is FeedDislike &&
      other.goto == goto &&
      other.id == id &&
      listEquals(other.reasons, reasons) &&
      listEquals(other.feedbacks, feedbacks);

  @override
  int get hashCode => Object.hash(goto, id, Object.hashAll(reasons), Object.hashAll(feedbacks));
}

enum HistoryDeviceKind { phone, pc, padOrTV }

final class HistoryItem {
  const HistoryItem({
    required this.aid,
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
      // `kid` is the row's id for 删除; for a video it is the aid, as `history.oid` is.
      aid: object.integer('kid') ?? history?.integer('oid') ?? 0,
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

  final int aid;
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
      other.aid == aid &&
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
  int get hashCode =>
      Object.hash(aid, bvid, cid, title, cover, ownerName, progress, duration, viewAt, device, part);
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
