import 'bvid.dart';
import 'json.dart';
import 'skin_models.dart' show argbColour;

/// A space's tabs as the official app names them (`tab2`'s `param`). Anything else is [other], drawn but not opened.
enum SpaceTabKind { home, dynamic, contribute, shop, favourite, bangumi, other }

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
    this.own,
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

  /// The uploader's `default_tab`; each space page decides whether it opens there.
  final SpaceTabKind defaultTab;

  /// 投稿's chips, 视频 first.
  final List<SpaceChip> chips;
  final List<SpaceOrder> orders;

  /// What only the account's own space carries, asked with the app token; null for anyone else's.
  final OwnSpace? own;

  /// `/x/v2/space`'s `data`. Only the card's mid is required; the rest reads leniently, so one odd field costs
  /// that field, not the space.
  ///
  /// [own] reads the account's own space's extras into [SpaceProfile.own].
  static SpaceProfile fromJson(Object? json, {bool own = false}) {
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
      own: own ? _ownSpace(data, card) : null,
    );
  }
}

/// One of the own space's 主页 sections: its count, the few items the answer previews, and whether it is hidden from
/// others (`setting`'s flag false: the eye-slash after its title, 114).
final class SpaceSection<T> {
  const SpaceSection({this.count = 0, this.items = const [], this.hidden = false, this.dropped});

  final int count;
  final List<T> items;
  final bool hidden;

  /// Why the first item the answer listed was left out (a decode error's message, no values), for the phone's log.
  final String? dropped;
}

/// A folder of the own space's 收藏 (114, 116).
final class SpaceFolderCard {
  const SpaceFolderCard({
    required this.id,
    required this.title,
    required this.cover,
    required this.count,
    required this.isPrivate,
  });

  final int id;
  final String title;

  /// Empty for a folder without a cover, which draws the grey TV.
  final String cover;
  final int count;
  final bool isPrivate;
}

/// A 追番 poster (114, 117).
final class SpaceBangumiCard {
  const SpaceBangumiCard({required this.seasonId, required this.title, required this.cover, this.progress = ''});

  final int seasonId;
  final String title;
  final String cover;

  /// "全23话", or the answer's newest-episode line.
  final String progress;
}

/// A page of 追番 (`/x/v2/space/bangumi`).
final class SpaceBangumiPage {
  const SpaceBangumiPage({required this.items, required this.hasMore, this.total});

  final List<SpaceBangumiCard> items;
  final bool hasMore;
  final int? total;

  /// The `data` of [page] (from 1), asked [pageSize] at a time. The answer carries only `count` and the page's
  /// rows (a `has_next`, should one come, wins), so the list goes on while the rows so far are fewer than the
  /// count, or, without a count, until a page comes back empty, as the official app pages it.
  static SpaceBangumiPage fromJson(Object? json, {int page = 1, int pageSize = 20}) {
    final data = JsonObject.from(json, 'bangumi');
    final rows = data.lenientList('item', (json) => json);
    final total = _id(data.map['count']);
    final bool hasMore;
    if (rows.isEmpty) {
      hasMore = false;
    } else if (data.map['has_next'] != null) {
      hasMore = data.flag('has_next');
    } else {
      // Rows that fail to decode still count, or a bad row would end the list early.
      hasMore = total == null || (page - 1) * pageSize + rows.length < total;
    }
    return SpaceBangumiPage(items: lossy(rows, _bangumi), hasMore: hasMore, total: total);
  }
}

/// An owned 装扮 card of 拥有的个性装扮 (115), from `fans_dress.item`.
final class SpaceGarbCard {
  const SpaceGarbCard({
    required this.title,
    required this.image,
    this.fansNumber = '',
    this.numberColor,
    this.maskColor,
  });

  /// `garb_title`, the name under the picture.
  final String title;
  final String image;

  /// The card's NO., drawn in a pill when not empty.
  final String fansNumber;

  /// `fan_bg_color` for the number's pill and `suit_bg_color` for the gradient rising from the card's bottom,
  /// 0xAARRGGBB; null for the defaults.
  final int? numberColor;
  final int? maskColor;
}

/// The label on the own space's banner, "幸运塔罗星 金牛座" over "NO.000067" (108).
final class SpaceBannerLabel {
  const SpaceBannerLabel({required this.title, this.subtitle = '', this.subtitleColor});

  final String title;
  final String subtitle;

  /// 0xAARRGGBB, from the answer's colour; null draws white.
  final int? subtitleColor;
}

/// The own space's extras (108, 114-117).
final class OwnSpace {
  const OwnSpace({
    this.exp = 0,
    this.nextExp = 0,
    this.pendant,
    this.vipBadge = false,
    this.banner,
    this.bannerLabel,
    this.favourites = const SpaceSection(),
    this.bangumi = const SpaceSection(),
    this.coins = const SpaceSection(),
    this.likes = const SpaceSection(),
    this.garbs = const SpaceSection(),
    this.garbTotal = 0,
  });

  /// 14805/28800 under the level.
  final int exp;
  final int nextExp;

  /// The avatar's frame.
  final String? pendant;

  /// The 大 on the avatar.
  final bool vipBadge;

  /// The tall banner art: `images.collection_top_simple`'s first item (the equipped 空间头图); null without one (the
  /// header then draws [SpaceProfile.banner]).
  final String? banner;
  final SpaceBannerLabel? bannerLabel;
  final SpaceSection<SpaceFolderCard> favourites;
  final SpaceSection<SpaceBangumiCard> bangumi;

  /// 最近投币的视频 and 最近点赞的视频.
  final SpaceSection<SpaceVideo> coins;
  final SpaceSection<SpaceVideo> likes;

  /// 拥有的个性装扮 (`fans_dress`): [SpaceSection.count] owned of [garbTotal] (2/7779), at most 3 cards.
  final SpaceSection<SpaceGarbCard> garbs;
  final int garbTotal;
}

OwnSpace _ownSpace(JsonObject data, JsonObject card) {
  final level = card.nested('level_info');
  final banner = _bannerItem(data);
  final setting = data.nested('setting');
  final dress = data.nested('fans_dress');
  return OwnSpace(
    exp: level?.count('current_exp') ?? 0,
    // At the top level (6) next_exp reads "--".
    nextExp: level?.count('next_exp') ?? 0,
    pendant: _picture(card.nested('pendant')?.text('image')),
    vipBadge: _id(card.nested('vip')?.map['avatar_subscript']) == 1,
    banner: banner == null
        ? null
        : _picture(banner.nested('item')?.nested('image')?.text('default_image')) ?? _picture(banner.text('cover')),
    bannerLabel: banner == null ? null : _bannerLabel(banner.nested('title')),
    favourites: _section(data.nested('favourite2'), _folder, hidden: _hidden(setting, 'fav_video')),
    bangumi: _section(data.nested('season'), _bangumi, hidden: _hidden(setting, 'bangumi')),
    coins: _section(data.nested('coin_archive'), _previewVideo, hidden: _hidden(setting, 'coins_video')),
    likes: _section(data.nested('like_archive'), _previewVideo, hidden: _hidden(setting, 'likes_video')),
    garbs: _section(dress, _garb, hidden: _hidden(setting, 'dress_up'), limit: 3),
    garbTotal: dress?.count('total') ?? 0,
  );
}

/// The equipped 空间头图: `images.collection_top_simple.top.result`'s first item.
JsonObject? _bannerItem(JsonObject data) {
  final top = data.nested('images')?.nested('collection_top_simple')?.nested('top');
  return top?.lenientList('result', (json) => JsonObject.from(json)).firstOrNull;
}

SpaceBannerLabel? _bannerLabel(JsonObject? title) {
  final text = _filled(title?.text('title'));
  if (title == null || text == null) return null;
  final colours = title.nested('sub_title_color_format')?.lenientList('colors', (json) => json) ?? const [];
  return SpaceBannerLabel(
    title: text,
    subtitle: title.text('sub_title') ?? '',
    subtitleColor: colours.isEmpty ? null : argbColour(colours.last),
  );
}

SpaceSection<T> _section<T>(JsonObject? section, T Function(Object? json) decode, {required bool hidden, int? limit}) {
  final rows = section?.map['item'];
  final items = <T>[];
  String? dropped;
  for (final row in rows is List ? rows : const []) {
    try {
      items.add(decode(row));
    } on DecodeError catch (error) {
      dropped ??= error.message;
    }
  }
  return SpaceSection(
    count: section?.count('count') ?? 0,
    items: limit != null && items.length > limit ? items.sublist(0, limit) : items,
    hidden: hidden,
    dropped: dropped,
  );
}

/// `setting`'s flags are whether others may see a section; a missing one hides nothing.
bool _hidden(JsonObject? setting, String key) => switch (setting?.map[key]) {
  final bool shown => !shown,
  final value => asInt(value) == 0,
};

SpaceFolderCard _folder(Object? json) {
  final object = JsonObject.from(json, 'folder');
  final id = _id(object.map['media_id']);
  if (id == null || id <= 0) throw const DecodeError('missing media_id');
  return SpaceFolderCard(
    id: id,
    title: object.text('title') ?? '',
    cover: _secure(object.text('cover') ?? ''),
    count: object.count('count', 'media_count'),
    // The official app reads is_public 0 as public, so 1 is a private folder.
    isPrivate: object.flag('is_public'),
  );
}

SpaceBangumiCard _bangumi(Object? json) {
  final object = JsonObject.from(json, 'season');
  final id = _id(object.map['param']) ?? _id(object.map['season_id']);
  if (id == null || id <= 0) throw const DecodeError('missing param');
  return SpaceBangumiCard(
    seasonId: id,
    title: object.text('title') ?? '',
    cover: _secure(object.text('cover') ?? ''),
    progress: _progress(object),
  );
}

/// The poster's line as the official app words it.
String _progress(JsonObject season) {
  if (season.flag('finish')) {
    final total = _scalar(season.map['total_count']);
    return total == null ? '' : '全$total话';
  }
  if (!season.flag('is_started')) return '即将开播';
  return switch (_scalar(season.map['newest_ep_index'])) {
    null || '-1' => '连载中',
    final index when RegExp(r'^\d+$').hasMatch(index) => '更新至$index话',
    final index => '更新至$index',
  };
}

SpaceGarbCard _garb(Object? json) {
  final object = JsonObject.from(json, 'garb');
  return SpaceGarbCard(
    title: object.text('garb_title') ?? '',
    image: _picture(object.text('image')) ?? (throw const DecodeError('missing image')),
    fansNumber: _scalar(object.map['fans_number']) ?? '',
    numberColor: argbColour(object.map['fan_bg_color']),
    maskColor: argbColour(object.map['suit_bg_color']),
  );
}

/// A text the answer gives as a string or a number; null when empty or neither.
String? _scalar(Object? value) => switch (value) {
  final String text => _filled(text),
  final num number => '${asInt(number) ?? number}',
  _ => null,
};

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

/// 最近投币/点赞's previews: 投稿's rows in looser form. The phone's (26) found every one of them refused by [_video],
/// so the id is taken from `param` or `aid`, a missing `bvid` comes from the aid, `length` ("0:12") stands in for
/// `duration`, and only kinds known not to be videos are left out.
SpaceVideo _previewVideo(Object? json) {
  final object = JsonObject.from(json, 'video');
  final goto = object.text('goto');
  if (goto != null && _notVideos.contains(goto)) throw DecodeError('not a video: $goto');
  final aid = _id(object.map['param']) ?? _id(object.map['aid']);
  if (aid == null || aid <= 0) throw const DecodeError('missing param');
  final duration = object.count('duration');
  return SpaceVideo(
    aid: aid,
    bvid: _filled(object.text('bvid')) ?? avToBv(aid),
    title: object.text('title') ?? '',
    cover: _secure(object.text('cover') ?? ''),
    duration: duration > 0 ? duration : _seconds(object.text('length')),
    play: object.count('play'),
    danmaku: object.count('danmaku'),
  );
}

const _notVideos = {'cheese', 'pgc', 'bangumi', 'article', 'live', 'audio', 'pugv'};

/// "1:02:03" or "0:12" in seconds; 0 when it isn't one.
int _seconds(String? length) {
  if (length == null) return 0;
  var total = 0;
  for (final part in length.split(':')) {
    final value = int.tryParse(part.trim());
    if (value == null) return 0;
    total = total * 60 + value;
  }
  return total;
}

SpaceTabKind _tabKind(String? param) => switch (param) {
  'home' => SpaceTabKind.home,
  'dynamic' => SpaceTabKind.dynamic,
  'contribute' || 'archive' || 'video' => SpaceTabKind.contribute,
  'shop' || 'mall' => SpaceTabKind.shop,
  'favorite' || 'favourite' => SpaceTabKind.favourite,
  'bangumi' => SpaceTabKind.bangumi,
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
