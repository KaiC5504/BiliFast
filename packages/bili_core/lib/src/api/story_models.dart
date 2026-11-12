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
  factory StoryItem.fromJson(Object? json) => throw UnimplementedError('story-api');

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
