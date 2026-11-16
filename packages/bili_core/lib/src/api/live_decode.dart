part of 'live_models.dart';

/// The decoders of `BiliClientLive`'s answers, each taking the envelope's `data`. Rows decode leniently: one that
/// won't costs only itself, and a field of an unexpected shape reads as absent.
abstract final class LiveDecode {
  /// `index/feed`'s `card_list`: each entry's `card_type` names the key its `card_data` holds it under.
  static LiveFeedPage feed(Object? json, {required int page}) {
    final data = JsonObject.from(json, 'live feed');
    final bigCards = <LiveBigCard>[];
    final following = <LiveCard>[];
    var followingTotal = 0;
    final areas = <LiveArea>[];
    final cards = <LiveCard>[];
    for (final entry in data.lenientList('card_list', _object)) {
      final type = entry.text('card_type') ?? '';
      final body = _cardBody(entry, type);
      if (body == null) continue;
      switch (type) {
        case 'my_idol_v1':
          following.addAll(body.lenientList('list', _card));
          followingTotal = body.nested('extra_info')?.count('total_count') ?? 0;
        case 'area_entrance_v3':
          areas.addAll([
            for (final area in body.lenientList('list', _area))
              if (!area.isRecommend) area,
          ]);
        case 'small_card_v1':
          if (attempt(() => _card(body.map)) case final card?) cards.add(card);
        default:
          if (_isCarousel(type)) bigCards.addAll(_bigCards(body));
      }
    }
    return LiveFeedPage(
      page: page,
      bigCards: bigCards,
      following: following,
      followingTotal: followingTotal > 0 ? followingTotal : following.length,
      areas: page == 1 || areas.isNotEmpty ? [LiveArea.recommend, ...areas] : const [],
      cards: cards,
      hasMore: cards.isNotEmpty && data.flag('has_more'),
    );
  }

  /// Each feed entry's `card_type`, in order, to log: names only.
  static List<String> cardTypes(Object? json) {
    if (json is! Map<String, Object?>) return const [];
    return [for (final entry in JsonObject(json).lenientList('card_list', _object)) entry.text('card_type') ?? '?'];
  }

  /// `second/getList`; [pageSize] rows make a full page.
  static LiveCardPage areaPage(Object? json, {required int page, required int pageSize}) {
    final data = JsonObject.from(json, 'live area page');
    final raw = data.lenientList('list', (json) => json);
    final cards = lossy(raw, _card);
    final count = data.count('count');
    final more = data.map['has_more'] != null
        ? data.flag('has_more')
        : (count > 0 ? page * pageSize < count : raw.length >= pageSize);
    return LiveCardPage(page: page, cards: cards, total: count, hasMore: raw.isNotEmpty && more);
  }

  /// `web-ucenter/user/following`: live rooms come first, so a page with one that isn't live ends the list.
  static LiveCardPage following(Object? json, {required int page}) {
    final data = JsonObject.from(json, 'live following');
    final rows = data.lenientList('list', _object);
    final live = [
      for (final row in rows)
        if (_int(row.map['live_status']) == 1) ?attempt(() => _followingCard(row)),
    ];
    final pages = data.count('totalPage');
    return LiveCardPage(
      page: page,
      cards: live,
      total: data.count('live_count'),
      hasMore: rows.isNotEmpty && live.length == rows.length && page < pages,
    );
  }

  /// `getRoomPlayInfo`: the stream is [qn]'s when a candidate plays it, else the first candidate's own.
  static LivePlayInfo playInfo(Object? json, {int? qn}) {
    final data = JsonObject.from(json, 'live play info');
    final roomId = _int(data.map['room_id']) ?? (throw const DecodeError('live play info: missing room_id'));
    final playurl = data.nested('playurl_info')?.nested('playurl');
    final stream = _pickStream(playurl, qn);
    final names = {
      for (final desc in playurl?.lenientList('g_qn_desc', _object) ?? const <JsonObject>[])
        ?_int(desc.map['qn']): desc.text('desc') ?? '',
    };
    final liveTime = _int(data.map['live_time']) ?? 0;
    return LivePlayInfo(
      roomId: roomId,
      shortId: _int(data.map['short_id']) ?? 0,
      uid: _int(data.map['uid']) ?? 0,
      status: switch (_int(data.map['live_status'])) {
        1 => LiveStatus.live,
        2 => LiveStatus.rotating,
        _ => LiveStatus.offline,
      },
      portrait: data.flag('is_portrait'),
      liveTime: liveTime > 0 ? _seconds(liveTime) : null,
      url: stream?.url,
      qualities: [
        for (final qn in stream?.accept ?? const <int>[])
          LiveQuality(qn: qn, name: (names[qn] ?? '').isEmpty ? '$qn' : names[qn]!),
      ],
      currentQn: stream?.current ?? 0,
    );
  }

  /// `getInfoByRoom`. [LiveRoomInfo.following] is left false: the answer doesn't say it.
  static LiveRoomInfo roomInfo(Object? json) {
    final data = JsonObject.from(json, 'live room info');
    final room = data.nested('room_info') ?? (throw const DecodeError('live room info: missing room_info'));
    final roomId = _int(room.map['room_id']) ?? (throw const DecodeError('live room info: missing room_id'));
    final anchor = data.nested('anchor_info')?.nested('base_info');
    final pendants = room.nested('pendants');
    final gold = data.nested('online_gold_rank_info_v2');
    return LiveRoomInfo(
      roomId: roomId,
      uid: _int(room.map['uid']) ?? 0,
      title: room.text('title') ?? '',
      cover: room.text('cover') ?? '',
      anchorName: anchor?.text('uname') ?? '',
      anchorFace: anchor?.text('face') ?? '',
      anchorFrame: _firstText([
        pendants?.nested('mobile_frame')?.text('value'),
        pendants?.nested('frame')?.text('value'),
      ]),
      verify: _verify(anchor?.nested('official_info')),
      description: _plainText(data.nested('news_info')?.text('content') ?? ''),
      areaName: room.text('area_name') ?? '',
      likeCount: data.nested('like_info_v3')?.count('total_likes') ?? 0,
      watchedText: _watched(data.nested('watched_show'), large: true),
      onlineCount: room.count('online'),
      topFaces: [
        for (final row in gold?.lenientList('list', _object) ?? const <JsonObject>[])
          if (row.text('face') case final face? when face.isNotEmpty) face,
      ].take(3).toList(),
      rankChips: _rankChips(data, room),
    );
  }

  /// `getDanmuInfo`: hosts without a name or a port are dropped.
  static LiveDanmuInfo danmuInfo(Object? json) {
    final data = JsonObject.from(json, 'live danmu info');
    final token = data.text('token') ?? (throw const DecodeError('live danmu info: missing token'));
    return LiveDanmuInfo(
      token: token,
      hosts: [
        for (final host in data.lenientList('host_list', _object))
          if ((host.text('host') ?? '').isNotEmpty && (_int(host.map['wss_port']) ?? 0) > 0)
            LiveSocketHost(host: host.text('host')!, wssPort: _int(host.map['wss_port'])!),
      ],
    );
  }

  /// `dM/gethistory`'s `room`, oldest first as answered; the admins' own list is left out, as the website's chat does.
  static List<LiveChatMessage> history(Object? json) {
    final data = JsonObject.from(json, 'live history');
    return data.lenientList('room', _historyMessage);
  }

  /// One 醒目留言: a row of [superChats]' list, or the socket's `SUPER_CHAT_MESSAGE` data.
  static LiveSuperChat superChat(Object? json) => _superChat(json);

  /// `SuperChat/getMessageList`'s `list`, those still showing at [now].
  static List<LiveSuperChat> superChats(Object? json, {required DateTime now}) {
    final data = JsonObject.from(json, 'live super chats');
    return [
      for (final chat in data.lenientList('list', _superChat))
        if (chat.end.isAfter(now)) chat,
    ];
  }

  /// `queryContributionRank`: `own_info` is the viewer's row, its rank 0 when unranked.
  static LiveRankPage rank(Object? json, {required int page, required int pageSize}) {
    final data = JsonObject.from(json, 'live rank');
    final raw = data.lenientList('item', (json) => json);
    final entries = lossy(raw, _rankEntry);
    final count = data.count('count');
    final own = data.nested('own_info');
    return LiveRankPage(
      entries: entries,
      own: own == null || (_int(own.map['uid']) ?? 0) <= 0 ? null : attempt(() => _rankEntry(own.map)),
      count: count,
      hasMore: raw.isNotEmpty && (count > 0 ? page * pageSize < count : raw.length >= pageSize),
    );
  }

  /// `guardTab/topListNew`: page 1 answers the first three apart (`top3`) and its `list` goes on from 4th.
  static LiveGuardPage guards(Object? json, {required int page, required int pageSize}) {
    final data = JsonObject.from(json, 'live guards');
    final list = data.lenientList('list', _guardEntry);
    final entries = [if (page == 1) ...data.lenientList('top3', _guardEntry), ...list];
    final total = data.nested('info')?.count('num') ?? 0;
    final last = entries.lastOrNull?.rank ?? 0;
    final leader = data.nested('guard_leader');
    final leaderUser = leader?.nested('uinfo') ?? leader?.nested('user');
    return LiveGuardPage(
      entries: entries,
      total: total,
      topText: leader == null ? '' : _firstText([leader.text('text'), leader.text('title'), leader.text('desc')]),
      topUser: leaderUser == null ? null : attempt(() => _user(leaderUser)),
      hasMore: list.isNotEmpty && (total > 0 && last > 0 ? last < total : list.length >= pageSize),
    );
  }

  /// `GetEmoticons`' packages, less the emotes the viewer can't send (`perm` 0) and packages left empty.
  static List<LiveEmotePackage> emotes(Object? json) {
    final data = JsonObject.from(json, 'live emotes');
    return [
      for (final package in data.lenientList('data', _emotePackage))
        if (package.emotes.isNotEmpty) package,
    ];
  }
}

JsonObject _object(Object? json) => JsonObject.from(json);

/// Ids and counts come as numbers or as strings of digits, depending on the call.
int? _int(Object? value) => asInt(value) ?? (value is String ? int.tryParse(value.trim()) : null);

DateTime _seconds(int seconds) => DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

String _firstText(List<String?> texts) =>
    texts.firstWhere((text) => text != null && text.isNotEmpty, orElse: () => '')!;

/// A feed entry's body: `card_data` holds it under the entry's own `card_type`.
JsonObject? _cardBody(JsonObject entry, String type) {
  final data = entry.nested('card_data');
  if (data == null) return null;
  final named = data.nested(type);
  if (named != null) return named;
  final maps = data.map.values.whereType<Map<String, Object?>>().toList();
  return maps.length == 1 ? JsonObject(maps.single) : null;
}

/// The carousel at the tab's top: PiliPlus reads no card of it, so every banner-like type is tried and only items
/// naming a room are kept.
bool _isCarousel(String type) => type.startsWith('banner') || type.startsWith('big_card') || type.contains('carousel');

List<LiveBigCard> _bigCards(JsonObject body) {
  final items = body.map['list'] is List ? body.lenientList('list', _object) : [body];
  return [
    for (final item in items)
      if (_roomOfBigCard(item) case final roomId? when roomId > 0)
        ?attempt(
          () => LiveBigCard(
            card: _card(item.map, roomId: roomId),
            rankText: _rankText(item),
            rankValue: _rankValue(item),
          ),
        ),
  ];
}

final _roomLink = RegExp(r'(?:bilibili://live/|live\.bilibili\.com/(?:h5/)?)(\d+)');

/// A banner's `id` is the banner's own, so the room comes only from a room field or its link.
int? _roomOfBigCard(JsonObject item) {
  final direct = _int(item.map['roomid']) ?? _int(item.map['room_id']);
  if (direct != null) return direct;
  final link = _firstText([item.text('link'), item.text('jump_url'), item.text('uri'), item.text('url')]);
  final match = _roomLink.firstMatch(link);
  return match == null ? null : int.tryParse(match[1]!);
}

const _rankFields = ['rank_info', 'rank', 'hot_rank_info', 'popular_rank_info'];

String _rankText(JsonObject item) {
  for (final key in _rankFields) {
    final rank = item.nested(key);
    if (rank == null) continue;
    final text = _firstText([rank.text('text'), rank.text('rank_name'), rank.text('title'), rank.text('desc')]);
    if (text.isNotEmpty) return text;
  }
  return _firstText([item.text('rank_text'), item.text('rank_desc')]);
}

String _rankValue(JsonObject item) {
  for (final key in _rankFields) {
    final rank = item.nested(key);
    if (rank == null) continue;
    final value = _firstText([rank.text('value'), rank.text('value_text'), rank.text('score_text')]);
    if (value.isNotEmpty) return value;
  }
  return _firstText([item.text('rank_value'), item.text('score_text')]);
}

/// A room card in the feed or an area list. A card with no room id is no room.
LiveCard _card(Object? json, {int? roomId}) {
  final card = JsonObject.from(json, 'live card');
  final id = roomId ?? _int(card.map['roomid']) ?? _int(card.map['room_id']) ?? _int(card.map['id']);
  if (id == null || id <= 0) throw const DecodeError('live card: missing room id');
  return LiveCard(
    roomId: id,
    uid: _int(card.map['uid']) ?? 0,
    title: card.text('title') ?? '',
    cover: _firstText([card.text('system_cover'), card.text('cover'), card.text('pic'), card.text('img')]),
    uname: _firstText([card.text('uname'), card.text('name')]),
    face: card.text('face') ?? '',
    areaName: _firstText([card.text('area_name'), card.text('area_v2_name')]),
    watchedText: _watched(card.nested('watched_show'), large: false),
    likeText: _likeText(card),
    badge: _badge(card),
    cornerIcon: _cornerIcon(card),
    verify: _cardVerify(card),
  );
}

LiveCard _followingCard(JsonObject row) {
  final id = _int(row.map['roomid']) ?? (throw const DecodeError('live following: missing roomid'));
  return LiveCard(
    roomId: id,
    uid: _int(row.map['uid']) ?? 0,
    title: row.text('title') ?? '',
    cover: row.text('room_cover') ?? '',
    uname: row.text('uname') ?? '',
    face: row.text('face') ?? '',
    areaName: _firstText([row.text('area_name_v2'), row.text('area_name')]),
    watchedText: row.text('text_small') ?? '',
  );
}

LiveArea _area(Object? json) {
  final area = JsonObject.from(json, 'live area');
  final name = _firstText([area.text('title'), area.text('name'), area.text('area_name')]);
  if (name.isEmpty) throw const DecodeError('live area: missing name');
  return LiveArea(
    id: _int(area.map['area_v2_id']) ?? _int(area.map['area_id']) ?? 0,
    parentId: _int(area.map['area_v2_parent_id']) ?? _int(area.map['parent_area_id']) ?? 0,
    name: name,
  );
}

/// The 👁 count: the cards show `text_small` (9.1万); the website's `text_large` adds 人看过.
String _watched(JsonObject? show, {required bool large}) {
  if (show == null) return '';
  final small = show.text('text_small');
  final big = show.text('text_large');
  return large ? _firstText([big, small]) : _firstText([small, big]);
}

/// No capture names the 👍 field yet; these are the likely spellings.
String _likeText(JsonObject card) => _firstText([
  card.nested('like_info')?.text('text'),
  card.nested('like_info_v3')?.text('text'),
  card.text('like_text'),
  card.text('like_count_text'),
]);

/// The cover's top-left tag, from the first place that names one: the app's `cover_left_style`, its `new_pendants`,
/// or the website's `pendant_info` (keyed by position).
LiveBadge? _badge(JsonObject card) {
  final pendants = card.nested('new_pendants');
  for (final candidate in [
    card.nested('cover_left_style'),
    pendants?.nested('mobile_badge'),
    pendants?.nested('badge'),
    ..._pendantInfo(card),
  ]) {
    final badge = candidate == null ? null : _badgeOf(candidate);
    if (badge != null) return badge;
  }
  return null;
}

List<JsonObject> _pendantInfo(JsonObject card) {
  final info = card.nested('pendant_info') ?? card.nested('pendant_Info');
  if (info == null) return const [];
  final entries = info.map.entries.where((entry) => entry.value is Map<String, Object?>).toList()
    ..sort((a, b) => (int.tryParse(a.key) ?? 0).compareTo(int.tryParse(b.key) ?? 0));
  return [for (final entry in entries) JsonObject(entry.value! as Map<String, Object?>)];
}

LiveBadge? _badgeOf(JsonObject style) {
  final text = _firstText([style.text('text'), style.text('desc'), style.text('name'), style.text('title')]);
  if (text.isEmpty) return null;
  final icon = _firstText([style.text('icon'), style.text('pic'), style.text('icon_url'), style.text('value')]);
  final colors = [
    for (final key in const [
      'bg_color_start',
      'start_color',
      'bg_start_color',
      'bg_color',
      'bg_color_end',
      'end_color',
    ])
      ?_appColor(style.map[key]),
  ];
  return LiveBadge(text: text, icon: icon.startsWith('http') ? icon : '', colors: colors.take(2).toList());
}

String _cornerIcon(JsonObject card) {
  final icon = _firstText([
    card.nested('cover_right_style')?.text('pic'),
    card.nested('cover_right_style')?.text('icon'),
    card.text('corner_icon'),
    card.text('top_right_icon'),
    card.text('right_top_icon'),
  ]);
  return icon.startsWith('http') ? icon : '';
}

LiveVerify _cardVerify(JsonObject card) {
  for (final key in const ['verify', 'official_info', 'official_verify']) {
    final verify = card.nested(key);
    if (verify != null) return _verify(verify);
  }
  return switch (_int(card.map['official_type'])) {
    0 => LiveVerify.personal,
    1 => LiveVerify.organization,
    _ => LiveVerify.none,
  };
}

/// `type` 0 is a person's verification, 1 an organisation's, -1 none.
LiveVerify _verify(JsonObject? official) => switch (_int(official?.map['type'])) {
  0 => LiveVerify.personal,
  1 => LiveVerify.organization,
  _ => LiveVerify.none,
};

/// `#RRGGBB`, or the app's `#AARRGGBB`, as ARGB.
int? _appColor(Object? value) => _hex(value, alphaLast: false);

/// The website's `#RRGGBB`, or its `#RRGGBBAA` (the v2 medal colours), as ARGB.
int? _webColor(Object? value) => _hex(value, alphaLast: true);

int? _hex(Object? value, {required bool alphaLast}) {
  if (value is! String) return null;
  final hex = value.trim().replaceFirst('#', '');
  final parsed = int.tryParse(hex, radix: 16);
  if (parsed == null) return null;
  return switch (hex.length) {
    6 => 0xFF000000 | parsed,
    8 => alphaLast ? ((parsed & 0xFF) << 24) | (parsed >> 8) : parsed,
    _ => null,
  };
}

/// An RGB integer (`color_start` 398668) as opaque ARGB; 0 stays 0.
int _rgb(Object? value) {
  final rgb = _int(value) ?? 0;
  return rgb <= 0 ? 0 : 0xFF000000 | (rgb & 0xFFFFFF);
}

/// The website's `stream` list in its pick order: HLS only, fmp4 HEVC, fmp4 AVC, then ts AVC (AVPlayer plays no HEVC
/// in TS).
({Uri? url, List<int> accept, int current})? _pickStream(JsonObject? playurl, int? qn) {
  final hls = [
    for (final stream in playurl?.lenientList('stream', _object) ?? const <JsonObject>[])
      if (stream.text('protocol_name') == 'http_hls') stream,
  ];
  final candidates = <({JsonObject codec, Uri url})>[];
  for (final (format, codecs) in const [('fmp4', ['hevc', 'avc']), ('ts', ['avc'])]) {
    for (final codecName in codecs) {
      for (final stream in hls) {
        for (final entry in stream.lenientList('format', _object)) {
          if (entry.text('format_name') != format) continue;
          for (final codec in entry.lenientList('codec', _object)) {
            if (codec.text('codec_name') != codecName) continue;
            if (_streamUrl(codec) case final url?) candidates.add((codec: codec, url: url));
          }
        }
      }
    }
  }
  if (candidates.isEmpty) return null;
  final chosen = candidates.firstWhere(
    (candidate) => qn != null && _int(candidate.codec.map['current_qn']) == qn,
    orElse: () => candidates.first,
  );
  final current = _int(chosen.codec.map['current_qn']) ?? 0;
  final accept = [for (final value in chosen.codec.lenientList('accept_qn', (json) => json)) ?_int(value)];
  return (url: chosen.url, accept: accept.isEmpty && current > 0 ? [current] : accept, current: current);
}

/// The first host's `host + base_url + extra`.
Uri? _streamUrl(JsonObject codec) {
  final base = codec.text('base_url');
  if (base == null || base.isEmpty) return null;
  for (final info in codec.lenientList('url_info', _object)) {
    final host = info.text('host');
    if (host == null || host.isEmpty) continue;
    final url = Uri.tryParse('$host$base${info.text('extra') ?? ''}');
    if (url != null && url.hasScheme && url.host.isNotEmpty) return url;
  }
  return null;
}

final _tag = RegExp(r'<[^>]*>');
final _lineBreak = RegExp(r'<br\s*/?>|</p>', caseSensitive: false);

/// The announcement is HTML on the website (`<p>…</p>`, `<br>`, entities).
String _plainText(String html) {
  final text = html
      .replaceAll(_lineBreak, '\n')
      .replaceAll(_tag, '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');
  return text.trim();
}

/// 207's chips: 热门榜 (or 全站第 N while ranked) first, then the area's rank (网游人气第 28). The field names are the
/// website's; which of them 207 draws from is a guess until a capture.
List<String> _rankChips(JsonObject data, JsonObject room) {
  final chips = <String>[];
  final popular = data.nested('popular_rank_info') ?? data.nested('hot_rank_info');
  if (popular != null) {
    final rank = _int(popular.map['rank']) ?? 0;
    chips.add(rank > 0 ? '全站第 $rank' : _firstText([popular.text('on_rank_name'), '热门榜']));
  }
  String? area;
  for (final item in data.nested('new_area_rank_info')?.lenientList('items', _object) ?? const <JsonObject>[]) {
    final rank = _int(item.map['rank']) ?? 0;
    final name = (item.text('rank_name') ?? '').replaceFirst(RegExp(r'榜$'), '');
    if (rank > 0 && name.isNotEmpty) {
      area = '$name第 $rank';
      break;
    }
  }
  if (area == null) {
    final rank = _int(data.nested('area_rank_info')?.nested('areaRank')?.map['rank']) ?? 0;
    final parent = room.text('parent_area_name') ?? '';
    if (rank > 0) area = '$parent人气第 $rank';
  }
  if (area != null) chips.add(area);
  return chips;
}

/// A fan medal from `uinfo.medal` (or `user.medal`); the v2 colours win over the RGB integers. None without a name.
LiveMedal? _medal(JsonObject? medal) {
  if (medal == null) return null;
  final name = _firstText([medal.text('name'), medal.text('medal_name')]);
  if (name.isEmpty) return null;
  return LiveMedal(
    name: name,
    level: _int(medal.map['level']) ?? _int(medal.map['medal_level']) ?? 0,
    colorStart:
        _webColor(medal.map['v2_medal_color_start']) ??
        _rgb(medal.map['color_start'] ?? medal.map['medal_color_start']),
    colorEnd:
        _webColor(medal.map['v2_medal_color_end']) ?? _rgb(medal.map['color_end'] ?? medal.map['medal_color_end']),
    border:
        _webColor(medal.map['v2_medal_color_border']) ??
        _rgb(medal.map['color_border'] ?? medal.map['medal_color_border']),
    guardLevel: _int(medal.map['guard_level']) ?? 0,
    lit: (_int(medal.map['is_light']) ?? _int(medal.map['is_lighted']) ?? 1) == 1,
  );
}

/// A sender from the website's `uinfo` shape (`uid`, `base`, `medal`, `wealth`, `guard`, `uhead_frame`).
LiveUser _user(JsonObject info, {int? uid, String? name, String? face, int wealth = 0, int guard = 0}) {
  final base = info.nested('base');
  return LiveUser(
    uid: _int(info.map['uid']) ?? uid ?? 0,
    name: _firstText([base?.text('name'), name]),
    face: _firstText([base?.text('face'), face]),
    faceFrame: _firstText([info.nested('uhead_frame')?.text('frame_img'), info.nested('uhead_frame')?.text('url')]),
    medal: _medal(info.nested('medal')),
    wealthLevel: _int(info.nested('wealth')?.map['level']) ?? wealth,
    guardLevel: _int(info.nested('guard')?.map['level']) ?? guard,
    nameColor: _webColor(base?.text('name_color_str')) ?? 0,
  );
}

final _beijing = RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$');

/// `check_info.ts`, else `timeline`, which is Beijing time.
DateTime _historyTime(JsonObject row) {
  final ts = _int(row.nested('check_info')?.map['ts']) ?? 0;
  if (ts > 0) return _seconds(ts);
  final match = _beijing.firstMatch(row.text('timeline') ?? '');
  if (match == null) return DateTime.fromMillisecondsSinceEpoch(0);
  int part(int index) => int.parse(match[index]!);
  return DateTime.utc(part(1), part(2), part(3), part(4) - 8, part(5), part(6));
}

LiveChatMessage _historyMessage(Object? json) {
  final row = JsonObject.from(json, 'live history row');
  final text = row.text('text') ?? (throw const DecodeError('live history row: missing text'));
  final time = _historyTime(row);
  final uid = _int(row.map['uid']) ?? 0;
  final user = _user(
    row.nested('user') ?? const JsonObject({}),
    uid: uid,
    name: row.text('nickname'),
    wealth: _int(row.map['wealth_level']) ?? 0,
    guard: _int(row.map['guard_level']) ?? 0,
  );
  final emoticon = row.nested('emoticon');
  final reply = row.nested('reply');
  return LiveChatMessage(
    id: _firstText([row.text('id_str'), '${user.uid}-${time.millisecondsSinceEpoch}']),
    user: user,
    text: text,
    time: time,
    emotes: _inlineEmotes(row.nested('emots')),
    bigEmote: (emoticon?.text('emoticon_unique') ?? '').isEmpty ? null : _emote(emoticon!, text: text),
    replyTo: (_int(reply?.map['reply_mid']) ?? 0) > 0 ? reply?.text('reply_uname') ?? '' : '',
  );
}

/// `emots` maps the text an emote replaces ([dog]) to it.
Map<String, LiveEmote> _inlineEmotes(JsonObject? emots) => {
  for (final MapEntry(:key, :value) in emots?.map.entries ?? const <MapEntry<String, Object?>>[])
    if (value is Map<String, Object?>) key: ?attempt(() => _emote(JsonObject(value), text: key)),
};

LiveEmote _emote(JsonObject emote, {required String text}) {
  final url = emote.text('url') ?? '';
  if (url.isEmpty) throw const DecodeError('live emote: missing url');
  return LiveEmote(
    text: _firstText([text, emote.text('emoji'), emote.text('text')]),
    url: url,
    unique: _firstText([emote.text('emoticon_unique'), emote.text('emotion_unique')]),
    width: _int(emote.map['width']) ?? 0,
    height: _int(emote.map['height']) ?? 0,
  );
}

/// A 醒目留言, from the room's list or the socket's `SUPER_CHAT_MESSAGE` (the same shape). `background_color` is the
/// card's top, `background_bottom_color` its message band; the header colour is a guess at `background_color_start`.
LiveSuperChat _superChat(Object? json) {
  final chat = JsonObject.from(json, 'super chat');
  final id = _int(chat.map['id']) ?? (throw const DecodeError('super chat: missing id'));
  final start =
      _int(chat.map['start_time']) ?? _int(chat.map['ts']) ?? (throw const DecodeError('super chat: missing start_time'));
  final info = chat.nested('user_info');
  final medal = _medal(chat.nested('medal_info'));
  final user = _user(
    chat.nested('uinfo') ?? const JsonObject({}),
    uid: _int(chat.map['uid']),
    name: info?.text('uname'),
    face: info?.text('face'),
    guard: _int(info?.map['guard_level']) ?? medal?.guardLevel ?? 0,
  );
  final price = chat.map['price'];
  final background = _anyColor(chat.map['background_color']);
  return LiveSuperChat(
    id: id,
    user: LiveUser(
      uid: user.uid,
      name: user.name,
      face: user.face,
      faceFrame: _firstText([info?.text('face_frame'), user.faceFrame]),
      medal: user.medal ?? medal,
      wealthLevel: user.wealthLevel,
      guardLevel: user.guardLevel,
      nameColor: user.nameColor != 0 ? user.nameColor : _anyColor(info?.map['name_color']) ?? 0,
    ),
    message: chat.text('message') ?? '',
    price: price is num ? price.round() : _int(price) ?? 0,
    start: _seconds(start),
    end: _seconds(_int(chat.map['end_time']) ?? start + (_int(chat.map['time']) ?? 0)),
    background: background ?? 0,
    backgroundBottom: _anyColor(chat.map['background_bottom_color']) ?? 0,
    headerColor: _anyColor(chat.map['background_color_start']) ?? background ?? 0,
    priceColor: _anyColor(chat.map['background_price_color']) ?? 0,
  );
}

/// A colour written either way the answers write them: `#RRGGBB(AA)` or an RGB number; null for none or 0.
int? _anyColor(Object? value) {
  if (value is String) return _webColor(value);
  final rgb = _rgb(value);
  return rgb == 0 ? null : rgb;
}

LiveRankEntry _rankEntry(Object? json) {
  final row = JsonObject.from(json, 'live rank row');
  final medalInfo = row.nested('medal_info') ?? row.nested('medalInfo');
  final user = _user(
    row.nested('uinfo') ?? const JsonObject({}),
    uid: _int(row.map['uid']),
    name: row.text('name') ?? row.text('uname'),
    face: row.text('face'),
    wealth: _int(row.map['wealth_level']) ?? 0,
    guard: _int(row.map['guard_level']) ?? 0,
  );
  if (user.uid <= 0) throw const DecodeError('live rank row: missing uid');
  final rank = _int(row.map['rank']) ?? _int(row.map['userRank']) ?? 0;
  return LiveRankEntry(
    rank: rank > 0 ? rank : 0,
    user: user.medal != null || medalInfo == null ? user : _withMedal(user, _medal(medalInfo)),
    score: _int(row.map['score']) ?? 0,
  );
}

LiveUser _withMedal(LiveUser user, LiveMedal? medal) => LiveUser(
  uid: user.uid,
  name: user.name,
  face: user.face,
  faceFrame: user.faceFrame,
  medal: medal,
  wealthLevel: user.wealthLevel,
  guardLevel: user.guardLevel,
  nameColor: user.nameColor,
);

LiveRankEntry _guardEntry(Object? json) {
  final row = JsonObject.from(json, 'live guard row');
  final uinfo = row.nested('uinfo') ?? (throw const DecodeError('live guard row: missing uinfo'));
  final user = _user(uinfo, guard: _int(uinfo.nested('medal')?.map['guard_level']) ?? 0);
  if (user.uid <= 0) throw const DecodeError('live guard row: missing uid');
  return LiveRankEntry(rank: _int(row.map['rank']) ?? 0, user: user);
}

LiveEmotePackage _emotePackage(Object? json) {
  final package = JsonObject.from(json, 'live emote package');
  return LiveEmotePackage(
    id: _int(package.map['pkg_id']) ?? 0,
    name: package.text('pkg_name') ?? '',
    icon: package.text('current_cover') ?? '',
    emotes: [
      for (final emote in package.lenientList('emoticons', _object))
        if ((_int(emote.map['perm']) ?? 1) != 0 && (emote.text('emoticon_unique') ?? '').isNotEmpty)
          ?attempt(() => _emote(emote, text: emote.text('emoji') ?? '')),
    ],
  );
}
