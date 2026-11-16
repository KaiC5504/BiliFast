/// 直播: the tab's lists, a room's stream, info, chat, 醒目留言, 高能榜 and emotes.
library;

/// A room in a list (205's cards, 206, the 我的关注 strip).
final class LiveCard {
  const LiveCard({
    required this.roomId,
    required this.uid,
    required this.title,
    required this.cover,
    required this.uname,
    this.face = '',
    this.areaName = '',
    this.watchedText = '',
    this.likeText = '',
    this.badge,
    this.cornerIcon = '',
    this.verify = LiveVerify.none,
  });

  final int roomId;
  final int uid;
  final String title;
  final String cover;
  final String uname;
  final String face;

  /// The area at the cover's bottom right (无畏契约, 剑网3).
  final String areaName;

  /// The 👁 count as the answer words it (9.1万, 883); empty for none.
  final String watchedText;

  /// The 👍 count as the answer words it; empty for none.
  final String likeText;

  /// The tag at the cover's top left (TopStar, SS主播, 全站第5); null for none.
  final LiveBadge? badge;

  /// The picture at the cover's top right (百); empty for none.
  final String cornerIcon;

  /// The ⚡ on the face.
  final LiveVerify verify;
}

/// A cover's tag: [text] on [colors] (a gradient, left to right) with [icon] before it when given.
final class LiveBadge {
  const LiveBadge({required this.text, this.icon = '', this.colors = const []});

  final String text;
  final String icon;

  /// ARGB colours; empty leaves the theme's.
  final List<int> colors;
}

enum LiveVerify { none, personal, organization }

/// The carousel at the tab's top (205): a room and its rank line (人气榜TOP·2, 2009助力值).
final class LiveBigCard {
  const LiveBigCard({required this.card, this.rankText = '', this.rankValue = ''});

  final LiveCard card;
  final String rankText;
  final String rankValue;
}

/// An area tab under the 我的关注 strip (推荐, 聊天室, 颜值…); 推荐 is [LiveArea.recommend].
final class LiveArea {
  const LiveArea({required this.id, required this.parentId, required this.name});

  static const recommend = LiveArea(id: 0, parentId: 0, name: '推荐');

  final int id;
  final int parentId;
  final String name;

  bool get isRecommend => id == 0 && parentId == 0;
}

/// A page of the tab's feed, [page] from 1. The first page carries the carousel, the 我的关注 strip and the area tabs;
/// later pages only [cards].
final class LiveFeedPage {
  const LiveFeedPage({
    required this.page,
    this.bigCards = const [],
    this.following = const [],
    this.followingTotal = 0,
    this.areas = const [],
    this.cards = const [],
    this.hasMore = false,
  });

  final int page;
  final List<LiveBigCard> bigCards;

  /// The followed rooms live now, as many as the strip shows; [followingTotal] counts them all.
  final List<LiveCard> following;
  final int followingTotal;
  final List<LiveArea> areas;
  final List<LiveCard> cards;
  final bool hasMore;
}

/// A page of rooms: an area's list, or 206's followed rooms that are live.
final class LiveCardPage {
  const LiveCardPage({required this.page, required this.cards, this.total = 0, this.hasMore = false});

  final int page;
  final List<LiveCard> cards;

  /// 206's 人正在直播 count; 0 where the answer gives none.
  final int total;
  final bool hasMore;
}

enum LiveStatus {
  /// 未开播.
  offline,
  live,

  /// 轮播: a replay in the slot.
  rotating,
}

/// A quality the room offers: its `qn` and the answer's name for it (1080P 原画 (高帧率), 720P 超清).
final class LiveQuality {
  const LiveQuality({required this.qn, required this.name});

  final int qn;
  final String name;
}

/// `getRoomPlayInfo`: the real room id, its status and the stream to play at [currentQn].
final class LivePlayInfo {
  const LivePlayInfo({
    required this.roomId,
    required this.uid,
    required this.status,
    this.shortId = 0,
    this.portrait = false,
    this.liveTime,
    this.url,
    this.qualities = const [],
    this.currentQn = 0,
  });

  final int roomId;
  final int shortId;
  final int uid;
  final LiveStatus status;

  /// The anchor streams upright.
  final bool portrait;
  final DateTime? liveTime;

  /// The HLS playlist; null when the room isn't live or offers none. Signed: never log or keep it.
  final Uri? url;
  final List<LiveQuality> qualities;
  final int currentQn;
}

/// What a room's header and chat need besides its stream.
final class LiveRoomInfo {
  const LiveRoomInfo({
    required this.roomId,
    required this.uid,
    required this.title,
    this.cover = '',
    this.anchorName = '',
    this.anchorFace = '',
    this.anchorFrame = '',
    this.verify = LiveVerify.none,
    this.description = '',
    this.areaName = '',
    this.likeCount = 0,
    this.watchedText = '',
    this.onlineCount = 0,
    this.topFaces = const [],
    this.rankChips = const [],
    this.following = false,
  });

  final int roomId;
  final int uid;
  final String title;
  final String cover;
  final String anchorName;
  final String anchorFace;

  /// The frame around the anchor's face (207's crown); empty for none.
  final String anchorFrame;
  final LiveVerify verify;

  /// The anchor's announcement, under the title in the chat's room card (207).
  final String description;
  final String areaName;

  /// 点赞 under the name (12.4万点赞).
  final int likeCount;
  final String watchedText;

  /// The number after the three faces (9349); 0 until known.
  final int onlineCount;

  /// The 在线榜's first three faces.
  final List<String> topFaces;

  /// 热门榜, 网游人气第 28, 全站第 5: the chips under the header, in order.
  final List<String> rankChips;
  final bool following;
}

/// The danmaku socket's token and hosts (`getDanmuInfo`).
final class LiveDanmuInfo {
  const LiveDanmuInfo({required this.token, required this.hosts});

  final String token;
  final List<LiveSocketHost> hosts;
}

final class LiveSocketHost {
  const LiveSocketHost({required this.host, required this.wssPort});

  final String host;
  final int wssPort;
}

/// A fan medal (莲宝 p21): [level] on [colors], lit or greyed.
final class LiveMedal {
  const LiveMedal({
    required this.name,
    required this.level,
    this.colorStart = 0,
    this.colorEnd = 0,
    this.border = 0,
    this.guardLevel = 0,
    this.lit = true,
  });

  final String name;
  final int level;

  /// ARGB; 0 leaves the theme's.
  final int colorStart;
  final int colorEnd;
  final int border;

  /// 1 总督, 2 提督, 3 舰长, 0 none.
  final int guardLevel;
  final bool lit;
}

/// A sender as the chat draws them.
final class LiveUser {
  const LiveUser({
    required this.uid,
    required this.name,
    this.face = '',
    this.faceFrame = '',
    this.medal,
    this.wealthLevel = 0,
    this.guardLevel = 0,
    this.nameColor = 0,
  });

  final int uid;

  /// Masked by Bilibili for a logged-out viewer (b**).
  final String name;
  final String face;
  final String faceFrame;
  final LiveMedal? medal;

  /// 荣耀等级, the V chip (0 for none).
  final int wealthLevel;
  final int guardLevel;

  /// ARGB; 0 leaves the theme's.
  final int nameColor;
}

/// An emote inside a message (`emots`) or a whole-message one (`info[0][13]`).
final class LiveEmote {
  const LiveEmote({required this.text, required this.url, this.unique = '', this.width = 0, this.height = 0});

  /// The text it replaces ([doge]); for a whole-message emote, its name.
  final String text;
  final String url;

  /// `emoticon_unique`, what sending it names.
  final String unique;
  final int width;
  final int height;
}

/// A chat line: a danmaku from the socket or the history.
final class LiveChatMessage {
  const LiveChatMessage({
    required this.id,
    required this.user,
    required this.text,
    required this.time,
    this.emotes = const {},
    this.bigEmote,
    this.color = 0xFFFFFFFF,
    this.mode = 1,
    this.replyTo = '',
  });

  final String id;
  final LiveUser user;
  final String text;
  final DateTime time;

  /// Inline emotes by the text they replace.
  final Map<String, LiveEmote> emotes;

  /// The whole message is this emote.
  final LiveEmote? bigEmote;

  /// ARGB, for the danmaku over the video.
  final int color;

  /// 1 scrolling, 4 bottom, 5 top.
  final int mode;

  /// @name the message answers; empty for none.
  final String replyTo;
}

/// A 醒目留言 (228).
final class LiveSuperChat {
  const LiveSuperChat({
    required this.id,
    required this.user,
    required this.message,
    required this.price,
    required this.start,
    required this.end,
    this.background = 0,
    this.backgroundBottom = 0,
    this.headerColor = 0,
    this.priceColor = 0,
  });

  final int id;
  final LiveUser user;
  final String message;

  /// In 元; the card says 电池 (×10).
  final int price;
  final DateTime start;
  final DateTime end;

  /// ARGB; 0 leaves the theme's.
  final int background;
  final int backgroundBottom;
  final int headerColor;
  final int priceColor;

  int get batteries => price * 10;
}

/// A row of 高能榜.
final class LiveRankEntry {
  const LiveRankEntry({required this.rank, required this.user, this.score = 0});

  /// From 1; 0 for the viewer's own row when unranked (-).
  final int rank;
  final LiveUser user;

  /// 贡献值 (房间观众); unused in 大航海.
  final int score;
}

/// 房间观众's 在线榜 (230).
final class LiveRankPage {
  const LiveRankPage({required this.entries, this.own, this.count = 0, this.hasMore = false});

  final List<LiveRankEntry> entries;
  final LiveRankEntry? own;
  final int count;
  final bool hasMore;
}

enum LiveGuardTab { weekly, monthly, companion }

/// 大航海's list (231).
final class LiveGuardPage {
  const LiveGuardPage({required this.entries, this.total = 0, this.topText = '', this.topUser, this.hasMore = false});

  final List<LiveRankEntry> entries;

  /// The tab's title count (大航海 (3351)).
  final int total;

  /// 上周TOP1's words and who; empty / null for none.
  final String topText;
  final LiveUser? topUser;
  final bool hasMore;
}

/// An emote package in 227's bottom row; [emotes] in its order.
final class LiveEmotePackage {
  const LiveEmotePackage({required this.id, required this.name, required this.icon, required this.emotes});

  final int id;
  final String name;
  final String icon;
  final List<LiveEmote> emotes;
}
