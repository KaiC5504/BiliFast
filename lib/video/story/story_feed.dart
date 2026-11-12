import 'package:bili_core/api.dart' show PlaySource, StoryItem, VideoCard, VideoDetail;
import 'package:flutter/foundation.dart';

import '../page_playback.dart';

/// A video in 竖屏's feed: what its page draws before the video opens (a neighbour under the finger, or the page just
/// swiped to while its details load), and what its plays report. [width] and [height] are 0 when the shape isn't
/// known, which draws as a wide video.
@immutable
final class StoryEntry {
  const StoryEntry({
    required this.bvid,
    required this.title,
    required this.cover,
    required this.ownerMid,
    required this.ownerName,
    required this.source,
    this.aid = 0,
    this.cid,
    this.firstFrame,
    this.duration = 0,
    this.width = 0,
    this.height = 0,
    this.ownerFace = '',
    this.ownerFans = 0,
    this.ownerVip,
    this.following = false,
    this.views = 0,
    this.likes = 0,
    this.replies = 0,
    this.coins = 0,
    this.favourites = 0,
    this.shares = 0,
    this.danmaku = 0,
    this.seasonTitle,
    this.seasonIndex,
    this.seasonTotal,
  });

  factory StoryEntry.fromItem(StoryItem item, {required PlaySource source}) => StoryEntry(
    bvid: item.bvid,
    aid: item.aid,
    cid: item.cid,
    title: item.title,
    cover: item.cover,
    firstFrame: item.firstFrame,
    duration: item.duration,
    width: item.width,
    height: item.height,
    ownerMid: item.ownerMid,
    ownerName: item.ownerName,
    ownerFace: item.ownerFace,
    ownerFans: item.ownerFans,
    ownerVip: item.ownerVip,
    following: item.following,
    views: item.views,
    likes: item.likes,
    replies: item.replies,
    coins: item.coins,
    favourites: item.favourites,
    shares: item.shares,
    danmaku: item.danmaku,
    seasonTitle: item.seasonTitle,
    seasonIndex: item.seasonIndex,
    seasonTotal: item.seasonTotal,
    source: source,
  );

  /// A related video, for a feed without the official one.
  factory StoryEntry.fromCard(VideoCard card, {required PlaySource source}) => StoryEntry(
    bvid: card.bvid,
    aid: card.aid,
    cid: card.cid == 0 ? null : card.cid,
    title: card.title,
    cover: card.cover,
    firstFrame: card.firstFrame,
    duration: card.duration,
    width: card.width,
    height: card.height,
    ownerMid: card.ownerMid,
    ownerName: card.ownerName,
    ownerFace: card.ownerFace,
    views: card.views,
    likes: card.likes,
    replies: card.replies,
    coins: card.coins,
    favourites: card.favourites,
    shares: card.shares,
    danmaku: card.danmaku,
    source: source,
  );

  /// The video playing on the page as 竖屏 begins.
  factory StoryEntry.fromDetail(VideoDetail detail, {required PlaySource source, int? cid}) => StoryEntry(
    bvid: detail.bvid,
    aid: detail.aid,
    cid: cid,
    title: detail.title,
    cover: detail.cover,
    duration: detail.duration,
    width: detail.width,
    height: detail.height,
    ownerMid: detail.owner.mid,
    ownerName: detail.owner.name,
    ownerFace: detail.owner.face,
    views: detail.stat.view,
    likes: detail.stat.like,
    replies: detail.stat.reply,
    coins: detail.stat.coin,
    favourites: detail.stat.favorite,
    shares: detail.stat.share,
    danmaku: detail.stat.danmaku,
    source: source,
  );

  final String bvid;
  final int aid;

  /// The part to open; null opens the video's first.
  final int? cid;
  final String title;
  final String cover;

  /// The video's first frame where the answer had one; the page shows it, else [cover], until the video plays.
  final String? firstFrame;
  final int duration;
  final int width;
  final int height;
  final int ownerMid;
  final String ownerName;
  final String ownerFace;
  final int ownerFans;

  /// The uploader is a 大会员; null where the source doesn't say (the related lists).
  final bool? ownerVip;
  final bool following;
  final int views;
  final int likes;
  final int replies;
  final int coins;
  final int favourites;
  final int shares;
  final int danmaku;
  final String? seasonTitle;
  final int? seasonIndex;
  final int? seasonTotal;

  /// What this video's plays report.
  final PlaySource source;

  /// The picture the page holds until the video plays.
  String get still => firstFrame ?? cover;

  /// Taller than wide, or square: its last bottom button is 清屏, not 横屏全屏.
  bool get upright => width > 0 && height >= width;
}

/// 竖屏's videos: the one it was entered on first, then the official feed's (under an iPhone token) or the entered
/// video's related list, more asked as the user nears the end. Moving opens the video on the page's playback; the
/// pager calls [moveNext] and [movePrevious] once the page has settled on the neighbour.
abstract class StoryFeed extends ChangeNotifier {
  List<StoryEntry> get entries;

  /// The entry playing; 0 is the one 竖屏 was entered on.
  int get index;

  /// More videos are being asked for.
  bool get loading;

  /// Null only while the entered video's details aren't in.
  StoryEntry? get current => index < entries.length ? entries[index] : null;
  StoryEntry? get next => index + 1 < entries.length ? entries[index + 1] : null;
  StoryEntry? get previous => index > 0 ? entries[index - 1] : null;

  /// Opens the next video on the page; false with none known yet, and nothing moves.
  bool moveNext();

  /// Opens the video before; false on the first.
  bool movePrevious();

  /// The user swiped on past the last video known: a feed that stopped asking after a failure may ask again.
  void wantMore() {}
}

/// Makes 竖屏's feed for [playback]'s video as 竖屏 begins.
typedef StoryFeedFactory = StoryFeed Function(PagePlayback playback);
