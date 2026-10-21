import 'json.dart';

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

  /// The uploader's default tab; the app opens on 投稿 regardless (KaiC: only 投稿 is built).
  final SpaceTabKind defaultTab;

  /// 投稿's chips, 视频 first.
  final List<SpaceChip> chips;
  final List<SpaceOrder> orders;

  /// `/x/v2/space`'s `data`. Only the card's mid is required; the rest reads leniently, so one odd field costs
  /// that field, not the space.
  static SpaceProfile fromJson(Object? json) {
    final data = JsonObject.from(json, 'space');
    final card = data.nested('card') ?? (throw const DecodeError('missing card'));
    final mid = _id(card.map['mid']) ?? (throw const DecodeError('missing mid'));
    final level = card.nested('level_info');
    final vip = card.nested('vip');
    final verify = card.nested('official_verify');
    final official = switch (asInt(verify?.map['type'])) {
      0 => SpaceOfficial.person,
      1 => SpaceOfficial.organisation,
      _ => SpaceOfficial.none,
    };
    final archive = data.nested('archive');
    final tabs = data.lenientList('tab2', (json) => JsonObject.from(json));
    final contribute = tabs.where((tab) => tab.text('param') == 'contribute').firstOrNull;
    final orders = archive?.lenientList('order', _order) ?? const <SpaceOrder>[];
    return SpaceProfile(
      mid: mid,
      name: card.text('name') ?? '',
      face: _secure(card.text('face') ?? ''),
      sign: card.text('sign') ?? '',
      level: level?.count('current_level') ?? 0,
      // The app's card marks 硬核会员 with identity 2; the web card's flag is read too, should it ever come.
      seniorMember: asInt(level?.map['identity']) == 2 || card.flag('is_senior_member'),
      vip: vip?.count('vipStatus', 'status') == 1,
      vipLabel: _picture(vip?.nested('label')?.text('image')),
      official: official,
      officialTitle: official == SpaceOfficial.none ? '' : verify?.text('splice_title') ?? '',
      fans: card.count('fans'),
      following: card.count('attention'),
      likes: card.nested('likes')?.count('like_num') ?? 0,
      videoCount: archive?.count('count') ?? 0,
      banner: _picture(data.nested('images')?.text('imgUrl')),
      tagLines: card.lenientList('space_tag', _tagLine),
      entries: data.lenientList('space_button_list', _entry),
      chargeable: data.nested('elec')?.flag('show') ?? false,
      tabs: lossy(tabs, _tab),
      defaultTab: switch (_tabKind(data.text('default_tab'))) {
        SpaceTabKind.other => SpaceTabKind.contribute,
        final kind => kind,
      },
      chips: contribute?.lenientList('items', _chip) ?? const [],
      orders: orders.isEmpty ? const [SpaceOrder.latest, SpaceOrder.mostPlayed] : orders,
    );
  }
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

  /// The `data` of 投稿's `/x/v2/space/archive/cursor`, a 合集's `/x/v2/space/season/videos` or a 系列's
  /// `/x/v2/space/series`. 投稿 pages by `has_next` and the last item's aid, a 系列 by its `next` (0 at the end),
  /// and a 合集 comes whole.
  static SpaceVideoPage fromArchive(Object? json) {
    final data = JsonObject.from(json, 'page');
    final rows = data.lenientList('item', (json) => json);
    String? next;
    if (rows.isNotEmpty) {
      if (data.map.containsKey('has_next')) {
        // The raw last row, not the last decoded one: a row that fails to decode must not be fetched again.
        final last = rows.last;
        final cursor = last is Map<String, Object?> ? _id(last['param']) ?? _id(last['aid']) : null;
        if (data.flag('has_next') && cursor != null) next = '$cursor';
      } else {
        final page = _id(data.map['next']);
        if (page != null && page > 0) next = '$page';
      }
    }
    return SpaceVideoPage(
      items: lossy(rows, _video),
      hasMore: next != null,
      next: next,
      total: _id(data.map['total']) ?? _id(data.map['count']),
    );
  }
}

SpaceVideo _video(Object? json) {
  final object = JsonObject.from(json, 'video');
  // 投稿 also lists the uploader's 课堂 courses (goto "cheese"), which don't open as a video page.
  final goto = object.text('goto');
  if (goto != null && goto != 'av') throw DecodeError('not a video: $goto');
  final aid = _id(object.map['param']) ?? _id(object.map['aid']);
  if (aid == null || aid <= 0) throw const DecodeError('missing param');
  final bvid = _filled(object.text('bvid')) ?? (throw const DecodeError('missing bvid'));
  final ctime = object.count('ctime');
  return SpaceVideo(
    aid: aid,
    bvid: bvid,
    title: object.text('title') ?? '',
    cover: _secure(object.text('cover') ?? ''),
    duration: object.count('duration'),
    play: object.count('play'),
    danmaku: object.count('danmaku'),
    published: ctime > 0 ? DateTime.fromMillisecondsSinceEpoch(ctime * 1000) : null,
    publishedText: object.text('publish_time_text') ?? '',
    badges: object.lenientList('badges', (json) => _filled(JsonObject.from(json).text('text')) ?? _noText()),
  );
}

SpaceTabKind _tabKind(String? param) => switch (param) {
  'home' => SpaceTabKind.home,
  'dynamic' => SpaceTabKind.dynamic,
  'contribute' || 'archive' || 'video' => SpaceTabKind.contribute,
  'shop' || 'mall' => SpaceTabKind.shop,
  'favorite' || 'favourite' => SpaceTabKind.favourite,
  _ => SpaceTabKind.other,
};

SpaceTab _tab(Object? json) {
  final object = JsonObject.from(json, 'tab');
  return SpaceTab(kind: _tabKind(object.text('param')), title: _filled(object.text('title')) ?? _noText());
}

SpaceChip _chip(Object? json) {
  final object = JsonObject.from(json, 'chip');
  final title = _filled(object.text('title')) ?? _noText();
  switch (object.text('param')) {
    case 'video':
      return SpaceChip(kind: SpaceChipKind.video, title: title);
    case 'opus' || 'article':
      return SpaceChip(kind: SpaceChipKind.article, title: title);
    case 'season_video':
      final id = _id(object.map['season_id']);
      if (id == null || id <= 0) throw const DecodeError('missing season_id');
      return SpaceChip(kind: SpaceChipKind.season, title: title, seasonId: id);
    case 'series':
      final id = _id(object.map['series_id']);
      if (id == null || id <= 0) throw const DecodeError('missing series_id');
      return SpaceChip(kind: SpaceChipKind.series, title: title, seriesId: id);
    default:
      return SpaceChip(kind: SpaceChipKind.other, title: title);
  }
}

SpaceOrder _order(Object? json) {
  final value = JsonObject.from(json, 'order').text('value');
  return SpaceOrder.values.where((order) => order.value == value).firstOrNull ??
      (throw const DecodeError('unknown order'));
}

/// The line's own link (`uri`) is only noted, never kept.
SpaceTagLine _tagLine(Object? json) {
  final object = JsonObject.from(json, 'tag');
  return SpaceTagLine(
    text: _filled(object.text('title')) ?? _noText(),
    icon: _picture(object.text('icon')),
    link: _filled(object.text('uri')) != null,
  );
}

/// `space_button_list`'s cards; 大航海 and anything else unknown is left out.
SpaceEntry _entry(Object? json) {
  final object = JsonObject.from(json, 'entry');
  final kind = switch (object.text('module_type')) {
    'goods' || 'shop' => SpaceEntryKind.shop,
    'charge' => SpaceEntryKind.charge,
    _ => throw const DecodeError('unknown module_type'),
  };
  return SpaceEntry(
    kind: kind,
    title: _filled(object.text('title')) ?? _noText(),
    note: object.text('sub_title') ?? '',
  );
}

Never _noText() => throw const DecodeError('missing text');

/// Ids come as numbers or, like the card's mid and an item's param, as strings.
int? _id(Object? value) => asInt(value) ?? (value is String ? int.tryParse(value) : null);

String? _filled(String? text) => text == null || text.isEmpty ? null : text;

/// Pictures come as http or protocol-relative.
String _secure(String url) {
  if (url.startsWith('//')) return 'https:$url';
  if (url.startsWith('http://')) return 'https://${url.substring(7)}';
  return url;
}

String? _picture(String? url) => switch (_filled(url)) {
  final url? => _secure(url),
  null => null,
};
