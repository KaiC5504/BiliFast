import 'json.dart';

/// One video of 竖屏's feed (`/x/v2/feed/index/story`, a `vertical_av` item): what a page in 竖屏 draws before its
/// video opens, and the track data its plays report. [width] and [height] are as shown, `rotate` already applied.
final class StoryItem {
  const StoryItem({
    required this.aid,
    required this.bvid,
    required this.cid,
    required this.title,
    required this.cover,
    required this.duration,
    required this.width,
    required this.height,
    required this.ownerMid,
    required this.ownerName,
    this.firstFrame,
    this.ownerFace = '',
    this.ownerFans = 0,
    this.following = false,
    this.views = 0,
    this.likes = 0,
    this.replies = 0,
    this.coins = 0,
    this.favourites = 0,
    this.shares = 0,
    this.danmaku = 0,
    this.trackId,
    this.flowData,
    this.idx,
    this.seasonTitle,
    this.seasonIndex,
    this.seasonTotal,
  });

  /// A `vertical_av` item; throws [DecodeError] without a bvid or a cid.
  factory StoryItem.fromJson(Object? json) {
    final object = JsonObject.from(json, 'story item');
    final bvid = object.text('bvid');
    if (bvid == null || bvid.isEmpty) throw const DecodeError('story item: missing bvid');
    final player = object.nested('player_args');
    final cid = _int(player?.map['cid']) ?? _int(object.map['cid']);
    if (cid == null || cid <= 0) throw const DecodeError('story item: missing cid');
    final dimension = object.nested('dimension');
    final rawWidth = _int(dimension?.map['width']) ?? 0;
    final rawHeight = _int(dimension?.map['height']) ?? 0;
    final rotated = _int(dimension?.map['rotate']) == 1;
    final owner = object.nested('owner');
    final relation = owner?.nested('relation');
    // The official app's relation status: 1 none, 2 following, 3 followed by them, 4 both ways.
    final status = _int(relation?.map['status']);
    final stat = object.nested('stat');
    final season = object.nested('season');
    return StoryItem(
      aid: _int(player?.map['aid']) ?? _int(object.map['aid']) ?? 0,
      bvid: bvid,
      cid: cid,
      title: object.text('title') ?? '',
      cover: object.text('cover') ?? '',
      duration: _int(object.map['duration']) ?? _int(player?.map['duration']) ?? 0,
      width: rotated ? rawHeight : rawWidth,
      height: rotated ? rawWidth : rawHeight,
      ownerMid: _int(owner?.map['mid']) ?? 0,
      ownerName: owner?.text('name') ?? '',
      firstFrame: _filled(object.text('ff_cover')),
      ownerFace: owner?.text('face') ?? '',
      ownerFans: owner?.count('fans') ?? 0,
      following: (relation?.flag('is_follow') ?? false) || status == 2 || status == 4,
      views: stat?.count('view') ?? 0,
      likes: stat?.count('like') ?? 0,
      replies: stat?.count('reply') ?? 0,
      coins: stat?.count('coin') ?? 0,
      favourites: stat?.count('favorite', 'fav') ?? 0,
      shares: stat?.count('share') ?? 0,
      danmaku: stat?.count('danmaku') ?? 0,
      trackId: _filled(object.text('track_id')),
      flowData: _filled(object.text('report_flow_data')),
      idx: _int(object.map['idx']),
      seasonTitle: _filled(season?.text('title')),
      seasonIndex: _int(season?.map['current_index']),
      seasonTotal: _int(season?.map['total']),
    );
  }

  /// A number, or one sent as a string.
  static int? _int(Object? value) => asInt(value) ?? (value is String ? int.tryParse(value) : null);

  static String? _filled(String? text) => text == null || text.isEmpty ? null : text;

  final int aid;
  final String bvid;
  final int cid;
  final String title;
  final String cover;

  /// `ff_cover`: the video's first frame.
  final String? firstFrame;
  final int duration;
  final int width;
  final int height;
  final int ownerMid;
  final String ownerName;
  final String ownerFace;
  final int ownerFans;

  /// `owner.relation.status` says the account follows the uploader.
  final bool following;
  final int views;
  final int likes;
  final int replies;
  final int coins;
  final int favourites;
  final int shares;
  final int danmaku;
  final String? trackId;

  /// `report_flow_data`, sent back as it came; not on every item.
  final String? flowData;
  final int? idx;

  /// 合集: its title, this video's place in it from 1, and its length.
  final String? seasonTitle;
  final int? seasonIndex;
  final int? seasonTotal;

  /// Taller than wide; a square video counts too, as the official app's 清屏 button shows for it.
  bool get upright => height >= width && width > 0;
}
