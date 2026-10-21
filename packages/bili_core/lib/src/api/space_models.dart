/// A space's tabs as the official app names them (`tab2`'s `param`). Anything else is [other], drawn but not opened.
enum SpaceTabKind { home, dynamic, contribute, shop, favourite, other }

final class SpaceTab {
  const SpaceTab({required this.kind, required this.title});

  final SpaceTabKind kind;
  final String title;
}

/// What a 投稿 chip lists: the uploader's videos, its 图文, or one 合集 ([seasonId]) or 系列 ([seriesId]).
enum SpaceChipKind { video, article, season, series, other }

final class SpaceChip {
  const SpaceChip({required this.kind, required this.title, this.seasonId, this.seriesId});

  final SpaceChipKind kind;
  final String title;
  final int? seasonId;
  final int? seriesId;
}

/// 投稿's sort: 最新发布 or 最多播放.
enum SpaceOrder {
  latest('pubdate'),
  mostPlayed('click');

  const SpaceOrder(this.value);

  final String value;
}

/// The official app's verification on the face: none, a person (yellow bolt) or an organisation (blue bolt).
enum SpaceOfficial { none, person, organisation }

/// A line under the bio: IP属地, a school, and the like. [link] lines draw a › after the text.
final class SpaceTagLine {
  const SpaceTagLine({required this.text, this.icon, this.link = false});

  final String text;

  /// The line's small icon as the answer gives it, if any.
  final String? icon;
  final bool link;
}

/// The cards under the header: 小店 with its note ("1件商品"), 充电 with its count ("5人充电").
enum SpaceEntryKind { shop, charge }

final class SpaceEntry {
  const SpaceEntry({required this.kind, required this.title, required this.note});

  final SpaceEntryKind kind;
  final String title;
  final String note;
}

/// An uploader's space from the official app's `/x/v2/space`, without the account's relation to them (the app API
/// knows the account only by an app token; following is the web card's).
final class SpaceProfile {
  const SpaceProfile({
    required this.mid,
    required this.name,
    required this.face,
    this.sign = '',
    this.level = 0,
    this.seniorMember = false,
    this.vip = false,
    this.vipLabel,
    this.official = SpaceOfficial.none,
    this.officialTitle = '',
    this.fans = 0,
    this.following = 0,
    this.likes = 0,
    this.videoCount = 0,
    this.banner,
    this.tagLines = const [],
    this.entries = const [],
    this.chargeable = false,
    this.tabs = const [],
    this.defaultTab = SpaceTabKind.contribute,
    this.chips = const [],
    this.orders = const [SpaceOrder.latest, SpaceOrder.mostPlayed],
  });

  final int mid;
  final String name;
  final String face;
  final String sign;
  final int level;

  /// 硬核会员: the level badge with its bolt.
  final bool seniorMember;

  /// 大会员, whose name draws pink.
  final bool vip;

  /// The 大会员 label's picture (年度大会员, 十年大会员), when it has one.
  final String? vipLabel;
  final SpaceOfficial official;

  /// "bilibili UP主认证：…", empty when unverified.
  final String officialTitle;
  final int fans;
  final int following;

  /// 获赞.
  final int likes;

  /// 投稿's videos, the sheet's N投稿.
  final int videoCount;

  /// The banner picture; null draws the official app's default.
  final String? banner;
  final List<SpaceTagLine> tagLines;
  final List<SpaceEntry> entries;

  /// Whether 充电 shows beside 关注.
  final bool chargeable;
  final List<SpaceTab> tabs;

  /// The tab the space opens on, the uploader's choice.
  final SpaceTabKind defaultTab;

  /// 投稿's chips, 视频 first.
  final List<SpaceChip> chips;
  final List<SpaceOrder> orders;

  static SpaceProfile fromJson(Object? json) => throw UnimplementedError('slice 12: SpaceProfile.fromJson');
}

/// One video of a space's lists. Only its ids and what is drawn are kept: the answer's `uri` carries a signed play
/// link, which must never be stored or logged.
final class SpaceVideo {
  const SpaceVideo({
    required this.aid,
    required this.bvid,
    required this.title,
    required this.cover,
    required this.duration,
    this.play = 0,
    this.danmaku = 0,
    this.published,
    this.publishedText = '',
    this.badges = const [],
  });

  final int aid;
  final String bvid;
  final String title;
  final String cover;

  /// Seconds.
  final int duration;
  final int play;
  final int danmaku;
  final DateTime? published;

  /// The date as the answer words it ("7月13日", "2024年8月26日").
  final String publishedText;

  /// The cover's tags (合作, 充电专属).
  final List<String> badges;
}

/// A page of a space's videos. [next] is passed back for the page after; null when [hasMore] is false.
final class SpaceVideoPage {
  const SpaceVideoPage({required this.items, required this.hasMore, this.next, this.total});

  final List<SpaceVideo> items;
  final bool hasMore;
  final String? next;
  final int? total;

  static SpaceVideoPage fromArchive(Object? json) => throw UnimplementedError('slice 12: SpaceVideoPage.fromArchive');
}
