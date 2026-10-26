/// 动态 from the website's polymer calls (`/x/polymer/web-dynamic/v1/…`), asked with the web login's cookies and
/// the `itemOpusStyle` feature, so pictures and text of 图文 posts come as `major.opus`.
library;

import 'dart:convert' show jsonDecode;

import 'bvid.dart';
import 'json.dart';
import 'skin_models.dart' show argbColour;

/// What a post is, from its `type` (`DYNAMIC_TYPE_…`). [live] and [pgc] (直播, 番剧, 课程) and [other] (音频, deleted,
/// unknown kinds) have no screenshot yet: drawn with their author, text and counts only, logged by their
/// [DynamicItem.typeName].
enum DynamicKind { video, draw, word, forward, article, live, pgc, other }

/// Which feed 关注 shows: 全部 or 视频.
enum DynamicFeedType {
  all('all'),
  video('video');

  const DynamicFeedType(this.rawValue);

  final String rawValue;
}

/// Where a post's comments live: `basic.comment_id_str` and `basic.comment_type` (1 a video's aid, 11 a picture
/// post's rid, 12 an article, 17 a text post or repost's own id). Feed items sometimes send type 0; the decoder then
/// takes a video's aid (1), a picture post's `rid_str` (11) or a text post or repost's own id (17).
final class CommentArea {
  const CommentArea({required this.oid, required this.type});

  final int oid;
  final int type;

  @override
  bool operator ==(Object other) => other is CommentArea && other.oid == oid && other.type == type;

  @override
  int get hashCode => Object.hash(oid, type);
}

enum DynamicVerify { none, personal, organisation }

/// The fan-number card beside the author (127's 000011 with its art): `decoration_card`.
final class DynamicDecoration {
  const DynamicDecoration({required this.cardUrl, this.number = '', this.colour});

  final String cardUrl;

  /// `fan.num_desc`, drawn over the card; empty for a card without one.
  final String number;

  /// `fan.color` as 0xAARRGGBB, null to use the card's default.
  final int? colour;
}

final class DynamicAuthor {
  const DynamicAuthor({
    required this.mid,
    required this.name,
    required this.face,
    this.pubTime = '',
    this.pubAction = '',
    this.location = '',
    this.vipPink = false,
    this.verify = DynamicVerify.none,
    this.decoration,
    this.pendant = '',
    this.following = true,
  });

  final int mid;
  final String name;
  final String face;

  /// `pub_time` as the server writes it: 3小时前, 2026年10月26日 15:00 (detail), 2025年6月27日.
  final String pubTime;

  /// `pub_action`: 发布了动态视频, 投稿了视频; empty for most posts.
  final String pubAction;

  /// `pub_location_text`: the IP属地 the detail shows (132, 140); empty when not sent.
  final String location;

  /// 大会员 (`vip.status` 1 with a type): the name drawn pink.
  final bool vipPink;
  final DynamicVerify verify;
  final DynamicDecoration? decoration;

  /// The avatar frame (头像框, `pendant.image`) drawn around the face (136); empty without one.
  final String pendant;
  final bool following;
}

/// A run of a post's text (`rich_text_nodes`). Every node keeps the [text] the server shows.
sealed class DynamicNode {
  const DynamicNode(this.text);

  final String text;
}

final class DynamicTextNode extends DynamicNode {
  const DynamicTextNode(super.text);
}

final class DynamicEmojiNode extends DynamicNode {
  const DynamicEmojiNode(super.text, {required this.url, this.large = false});

  final String url;

  /// `emoji.size` 2: drawn 28 pt.
  final bool large;
}

final class DynamicMentionNode extends DynamicNode {
  const DynamicMentionNode(super.text, {required this.mid});

  final int mid;
}

final class DynamicTopicNode extends DynamicNode {
  const DynamicTopicNode(super.text);
}

final class DynamicLinkNode extends DynamicNode {
  const DynamicLinkNode(super.text, {required this.url});

  final String url;
}

/// A video link in the text (▶ 「…」, 131): opens the video.
final class DynamicVideoLinkNode extends DynamicNode {
  const DynamicVideoLinkNode(super.text, {required this.bvid});

  final String bvid;
}

/// 🎁 互动抽奖, 投票, goods and any other kind: drawn as a link, tapped to a toast.
final class DynamicBadgeNode extends DynamicNode {
  const DynamicBadgeNode(super.text, {required this.kind});

  /// `lottery`, `vote`, `goods` or the raw node type.
  final String kind;
}

/// A post's body (`major`).
sealed class DynamicMajor {
  const DynamicMajor();
}

/// `major.archive` (and `ugc_season`): the cover box with its length, plays and danmaku.
final class DynamicVideo extends DynamicMajor {
  const DynamicVideo({
    required this.aid,
    required this.bvid,
    required this.title,
    required this.cover,
    this.durationText = '',
    this.duration = 0,
    this.plays = '',
    this.danmaku = '',
    this.badge = '',
  });

  final int aid;
  final String bvid;
  final String title;
  final String cover;

  /// `duration_text` as sent (00:56, 21:50).
  final String durationText;

  /// Seconds, from [durationText]; 0 when unknown.
  final int duration;

  /// `stat.play` and `stat.danmaku` as sent (37.1万).
  final String plays;
  final String danmaku;

  /// `badge.text`: 动态视频 (pink, 128); 投稿视频 is sent as empty.
  final String badge;
}

final class DynamicPicture {
  const DynamicPicture({required this.url, this.width = 0, this.height = 0});

  final String url;
  final int width;
  final int height;
}

/// `major.opus`: a 图文 post's pictures, and an article's [title].
final class DynamicPictures extends DynamicMajor {
  const DynamicPictures({required this.pictures, this.title = ''});

  final List<DynamicPicture> pictures;
  final String title;
}

/// Any other `major` (live, 番剧, music, a deleted original): nothing drawn but what the decoder knows.
final class DynamicOtherMajor extends DynamicMajor {
  const DynamicOtherMajor({required this.typeName, this.title = '', this.cover = ''});

  /// `MAJOR_TYPE_…`, for the log.
  final String typeName;
  final String title;
  final String cover;
}

/// UP主的推荐 (`additional.goods`, 127, 135): drawn, its 去看看 toasts.
final class DynamicGoods {
  const DynamicGoods({required this.headText, required this.items});

  final String headText;
  final List<DynamicGoodsItem> items;
}

final class DynamicGoodsItem {
  const DynamicGoodsItem({required this.name, required this.cover, this.brief = '', this.jumpText = ''});

  final String name;
  final String cover;

  /// 最高26888元.
  final String brief;

  /// 去看看.
  final String jumpText;
}

final class DynamicStat {
  const DynamicStat({this.forward = 0, this.comment = 0, this.like = 0, this.liked = false, this.favourite});

  final int forward;
  final int comment;
  final int like;
  final bool liked;

  /// ⭐ on the post page (131, 140); null when the post has none (132).
  final int? favourite;

  DynamicStat copyWith({int? like, bool? liked}) => DynamicStat(
    forward: forward,
    comment: comment,
    like: like ?? this.like,
    liked: liked ?? this.liked,
    favourite: favourite,
  );
}

/// ⋮'s rows (`module_more.three_point_items`).
enum DynamicMenuItem { unfollow, report, other }

final class DynamicItem {
  const DynamicItem({
    required this.id,
    required this.kind,
    required this.author,
    this.typeName = '',
    this.nodes = const [],
    this.major,
    this.goods,
    this.stat = const DynamicStat(),
    this.original,
    this.comments,
    this.menu = const [DynamicMenuItem.unfollow, DynamicMenuItem.report],
    this.pinned = false,
    this.foldedLines = false,
  });

  /// `id_str`.
  final String id;
  final DynamicKind kind;

  /// `DYNAMIC_TYPE_…`, for the log.
  final String typeName;
  final DynamicAuthor author;

  /// The text: `desc` or, for 图文, `major.opus.summary`.
  final List<DynamicNode> nodes;
  final DynamicMajor? major;
  final DynamicGoods? goods;
  final DynamicStat stat;

  /// A repost's original (`orig`), drawn in the grey block; null when not a repost.
  final DynamicItem? original;

  /// Null when the decoder couldn't place them; the post page then takes the detail's.
  final CommentArea? comments;
  final List<DynamicMenuItem> menu;

  /// 置顶 (`module_tag`).
  final bool pinned;

  /// The server cut the text (`has_more` on `desc` or the opus summary): the card ends it with … 全文 (展开 on a video
  /// post).
  final bool foldedLines;

  /// What 分享 hands the share sheet.
  Uri get shareLink => Uri.parse('https://www.bilibili.com/opus/$id');

  DynamicItem copyWith({DynamicStat? stat}) => DynamicItem(
    id: id,
    kind: kind,
    author: author,
    typeName: typeName,
    nodes: nodes,
    major: major,
    goods: goods,
    stat: stat ?? this.stat,
    original: original,
    comments: comments,
    menu: menu,
    pinned: pinned,
    foldedLines: foldedLines,
  );
}

/// A page of posts; [offset] goes with the next ask, which stops once [hasMore] is false or a page comes back empty.
final class DynamicPage {
  const DynamicPage({required this.items, this.offset = '', this.hasMore = false, this.skipped = const {}});

  final List<DynamicItem> items;
  final String offset;
  final bool hasMore;

  /// Items dropped while decoding, by `type`, and reposts whose original was reduced to its kind, by `orig:<type>`,
  /// for the log.
  final Map<String, int> skipped;
}

/// A 最常访问 face (`up_list.items`).
final class DynamicUp {
  const DynamicUp({required this.mid, required this.name, required this.face, this.hasUpdate = false});

  final int mid;
  final String name;
  final String face;

  /// The pink dot.
  final bool hasUpdate;
}

final class DynamicUpList {
  const DynamicUpList({required this.ups, this.offset = '', this.hasMore = false});

  final List<DynamicUp> ups;
  final String offset;
  final bool hasMore;
}

/// 我的关注's sort (130). 推荐排序 has no known web call and asks as 最常访问 does (KaiC's call, 2026-10-26).
enum FollowingOrder {
  recommended('attention'),
  mostVisited('attention'),
  recent('');

  const FollowingOrder(this.rawValue);

  /// `order_type`.
  final String rawValue;
}

/// A 我的关注 row (`/x/relation/followings`).
final class FollowingUser {
  const FollowingUser({
    required this.mid,
    required this.name,
    required this.face,
    this.sign = '',
    this.verify = DynamicVerify.none,
    this.vipPink = false,
  });

  final int mid;
  final String name;
  final String face;
  final String sign;
  final DynamicVerify verify;
  final bool vipPink;
}

final class FollowingPage {
  const FollowingPage({required this.users, this.total = 0, this.hasMore = false});

  final List<FollowingUser> users;
  final int total;
  final bool hasMore;
}

/// A 我的追番 · 追剧 poster (`/x/space/bangumi/follow/list`).
final class FollowedBangumi {
  const FollowedBangumi({required this.seasonId, required this.title, required this.cover, this.progress = ''});

  final int seasonId;
  final String title;
  final String cover;

  /// `new_ep.index_show`: 全23话, 更新至第5话.
  final String progress;
}

final class FollowedBangumiPage {
  const FollowedBangumiPage({required this.items, this.total = 0, this.hasMore = false});

  final List<FollowedBangumi> items;
  final int total;
  final bool hasMore;
}

/// The decoders, filled in by the 动态 client: every one takes the envelope's `data`.
abstract final class DynamicDecode {
  /// An item that won't decode costs only itself, counted in [DynamicPage.skipped].
  static DynamicPage page(Object? json) {
    final data = JsonObject.from(json, 'dynamic page');
    final items = <DynamicItem>[];
    final skipped = <String, int>{};
    for (final entry in _list(data.map['items'])) {
      try {
        items.add(_item(entry, skipped: skipped));
      } on DecodeError {
        final type = switch (entry) {
          {'type': final String type} when type.isNotEmpty => type,
          _ => 'unknown',
        };
        skipped[type] = (skipped[type] ?? 0) + 1;
      }
    }
    return DynamicPage(
      items: items,
      offset: _string(data.map['offset']),
      hasMore: data.flag('has_more'),
      skipped: skipped,
    );
  }

  /// The detail's `data.item`.
  static DynamicItem detail(Object? json) {
    final data = JsonObject.from(json, 'dynamic detail');
    return _item(data.map['item'] ?? data.map);
  }

  /// The portal's `up_list` or uplist's `data`.
  static DynamicUpList ups(Object? json) {
    final data = JsonObject.from(json, 'up list');
    final list = data.nested('up_list') ?? data;
    return DynamicUpList(
      ups: list.lenientList('items', _up),
      offset: _string(list.map['offset']),
      hasMore: list.flag('has_more'),
    );
  }

  /// An empty page has no more after it, whatever `total` says, so paging can't loop.
  static FollowingPage followings(Object? json, {required int page, required int pageSize}) {
    final data = JsonObject.from(json, 'followings');
    final raw = _list(data.map['list']);
    final total = data.count('total');
    return FollowingPage(
      users: lossy(raw, _following),
      total: total,
      hasMore: raw.isNotEmpty && (total > 0 ? page * pageSize < total : raw.length >= pageSize),
    );
  }

  static FollowedBangumiPage bangumi(Object? json, {required int page, required int pageSize}) {
    final data = JsonObject.from(json, 'followed bangumi');
    final raw = _list(data.map['list']);
    final total = data.count('total');
    return FollowedBangumiPage(
      items: lossy(raw, _bangumi),
      total: total,
      hasMore: raw.isNotEmpty && page * pageSize < total,
    );
  }
}

/// [original] is a repost's `orig`, which may come without its id, author or anything else (a deleted original);
/// a feed item without them is dropped. Whatever can drop the item comes before [_original], so an original reduced
/// to its kind is counted in [skipped] only for a repost that is kept.
DynamicItem _item(Object? json, {bool original = false, Map<String, int>? skipped}) {
  final item = JsonObject.from(json, 'dynamic item');
  final id = _string(item.map['id_str']);
  if (id.isEmpty && !original) throw const DecodeError('dynamic item: missing id_str');
  final typeName = item.text('type') ?? '';
  final kind = _kind(typeName);
  final modules = item.nested('modules');
  final authorJson = modules?.nested('module_author');
  if (authorJson == null && !original) throw const DecodeError('dynamic item: missing module_author');
  final author = authorJson == null ? _nobody : _author(authorJson, strict: !original);
  final content = modules?.nested('module_dynamic');
  final majorJson = content?.nested('major');
  final major = majorJson == null ? null : _major(majorJson, kind);
  final (nodes, folded) = _text(content);
  final orig = item.map['orig'];
  return DynamicItem(
    id: id,
    kind: kind,
    typeName: typeName,
    author: author,
    nodes: nodes,
    major: major,
    goods: _goods(content?.nested('additional')),
    stat: _stat(modules?.nested('module_stat')),
    original: orig == null ? null : _original(orig, skipped),
    comments: _comments(item.nested('basic'), id: id, kind: kind, major: major),
    menu: _menu(modules?.nested('module_more')),
    pinned: modules?.nested('module_tag')?.text('text') == '置顶',
    foldedLines: folded,
  );
}

const _nobody = DynamicAuthor(mid: 0, name: '', face: '');

/// A repost keeps its place even when its original won't decode: the grey block then has nothing but its kind.
DynamicItem _original(Object? json, Map<String, int>? skipped) {
  try {
    return _item(json, original: true, skipped: skipped);
  } on DecodeError {
    final (id, typeName) = switch (json) {
      {'id_str': final String id, 'type': final String type} => (id, type),
      {'type': final String type} => ('', type),
      _ => ('', ''),
    };
    if (skipped != null) {
      final key = 'orig:${typeName.isEmpty ? 'unknown' : typeName}';
      skipped[key] = (skipped[key] ?? 0) + 1;
    }
    return DynamicItem(id: id, kind: _kind(typeName), typeName: typeName, author: _nobody, menu: const []);
  }
}

DynamicKind _kind(String type) => switch (type) {
  'DYNAMIC_TYPE_AV' || 'DYNAMIC_TYPE_UGC_SEASON' => DynamicKind.video,
  'DYNAMIC_TYPE_DRAW' => DynamicKind.draw,
  'DYNAMIC_TYPE_WORD' => DynamicKind.word,
  'DYNAMIC_TYPE_FORWARD' => DynamicKind.forward,
  'DYNAMIC_TYPE_ARTICLE' => DynamicKind.article,
  'DYNAMIC_TYPE_LIVE' || 'DYNAMIC_TYPE_LIVE_RCMD' => DynamicKind.live,
  'DYNAMIC_TYPE_PGC' || 'DYNAMIC_TYPE_PGC_UNION' || 'DYNAMIC_TYPE_COURSES_SEASON' => DynamicKind.pgc,
  _ => DynamicKind.other,
};

DynamicAuthor _author(JsonObject author, {required bool strict}) {
  final mid = _int(author.map['mid']);
  if (mid == null && strict) throw const DecodeError('module_author: missing mid');
  final vip = author.nested('vip');
  final card = author.nested('decoration_card') ?? author.nested('decorate_card') ?? author.nested('decorate');
  return DynamicAuthor(
    mid: mid ?? 0,
    name: author.text('name') ?? '',
    face: author.text('face') ?? '',
    pubTime: author.text('pub_time') ?? '',
    pubAction: author.text('pub_action') ?? '',
    location: author.text('pub_location_text') ?? '',
    vipPink: _vipPink(status: vip?.map['status'], type: vip?.map['type']),
    verify: _verify(author.nested('official_verify')?.map['type']),
    decoration: card == null ? null : _decoration(card),
    pendant: author.nested('pendant')?.text('image') ?? '',
    following: switch (author.map['following']) {
      final bool following => following,
      _ => true,
    },
  );
}

bool _vipPink({required Object? status, required Object? type}) => _int(status) == 1 && (_int(type) ?? 0) > 0;

DynamicVerify _verify(Object? type) => switch (_int(type)) {
  0 => DynamicVerify.personal,
  1 => DynamicVerify.organisation,
  _ => DynamicVerify.none,
};

DynamicDecoration? _decoration(JsonObject card) {
  final url = card.text('card_url') ?? '';
  if (url.isEmpty) return null;
  final fan = card.nested('fan');
  return DynamicDecoration(
    cardUrl: url,
    number: fan?.text('num_desc') ?? fan?.text('num_str') ?? '',
    colour: argbColour(fan?.map['color']),
  );
}

/// The text from `desc`, or a 图文 post's `major.opus.summary`; true when the server cut it (`has_more`). An opus
/// `fold_action` isn't a cut: every opus carries one (展开/收起), however short its text.
(List<DynamicNode>, bool) _text(JsonObject? content) {
  final desc = content?.nested('desc');
  final descNodes = desc == null ? const <DynamicNode>[] : _nodes(desc);
  if (desc != null && descNodes.isNotEmpty) return (descNodes, desc.flag('has_more'));
  final summary = content?.nested('major')?.nested('opus')?.nested('summary');
  if (summary == null) return (descNodes, false);
  return (_nodes(summary), summary.flag('has_more'));
}

List<DynamicNode> _nodes(JsonObject text) {
  final nodes = lossy(_list(text.map['rich_text_nodes']), _node);
  if (nodes.isNotEmpty) return nodes;
  final plain = text.text('text') ?? '';
  return plain.isEmpty ? const [] : [DynamicTextNode(plain)];
}

DynamicNode _node(Object? json) {
  final node = JsonObject.from(json, 'rich text node');
  final text = node.text('text') ?? node.text('orig_text') ?? '';
  return switch (node.text('type') ?? '') {
    'RICH_TEXT_NODE_TYPE_TEXT' || '' => DynamicTextNode(text),
    'RICH_TEXT_NODE_TYPE_EMOJI' => _emoji(text, node.nested('emoji')),
    'RICH_TEXT_NODE_TYPE_AT' => switch (_int(node.map['rid'])) {
      final mid? when mid > 0 => DynamicMentionNode(text, mid: mid),
      _ => DynamicTextNode(text),
    },
    'RICH_TEXT_NODE_TYPE_TOPIC' => DynamicTopicNode(text),
    'RICH_TEXT_NODE_TYPE_WEB' => switch (_https(node.text('jump_url') ?? '')) {
      '' => DynamicTextNode(text),
      final url => DynamicLinkNode(text, url: url),
    },
    'RICH_TEXT_NODE_TYPE_BV' => switch (_bvid(node.map['rid'])) {
      final bvid? => DynamicVideoLinkNode(text, bvid: bvid),
      null => DynamicTextNode(text),
    },
    'RICH_TEXT_NODE_TYPE_LOTTERY' => DynamicBadgeNode(text, kind: 'lottery'),
    'RICH_TEXT_NODE_TYPE_VOTE' => DynamicBadgeNode(text, kind: 'vote'),
    'RICH_TEXT_NODE_TYPE_GOODS' => DynamicBadgeNode(text, kind: 'goods'),
    final type => DynamicBadgeNode(text, kind: type),
  };
}

DynamicNode _emoji(String text, JsonObject? emoji) {
  final url = [
    emoji?.text('webp_url'),
    emoji?.text('gif_url'),
    emoji?.text('icon_url'),
  ].firstWhere((url) => url != null && url.isNotEmpty, orElse: () => null);
  if (emoji == null || url == null) return DynamicTextNode(text);
  return DynamicEmojiNode(text, url: url, large: _int(emoji.map['size']) == 2);
}

/// A BV node's `rid`: the bvid, or an aid written as a number or `av…`.
String? _bvid(Object? rid) {
  final aid = _int(rid);
  if (aid != null) return aid > 0 ? avToBv(aid) : null;
  if (rid is! String) return null;
  if (rid.length > 2 && rid.substring(0, 2).toLowerCase() == 'bv') return rid;
  if (rid.length > 2 && rid.substring(0, 2).toLowerCase() == 'av') {
    final number = int.tryParse(rid.substring(2));
    if (number != null && number > 0) return avToBv(number);
  }
  return null;
}

String _https(String url) => url.startsWith('//') ? 'https:$url' : url;

DynamicMajor? _major(JsonObject major, DynamicKind kind) {
  switch (kind) {
    case DynamicKind.video:
      if (major.nested('archive') ?? major.nested('ugc_season') case final archive?) return _video(archive);
    case DynamicKind.draw || DynamicKind.word || DynamicKind.article || DynamicKind.forward:
      if (major.nested('opus') case final opus?) {
        return _pictures(_list(opus.map['pics']), url: 'url', title: opus.text('title') ?? '');
      }
      if (major.nested('draw') case final draw?) return _pictures(_list(draw.map['items']), url: 'src');
    case DynamicKind.live || DynamicKind.pgc || DynamicKind.other:
      break;
  }
  return _otherMajor(major);
}

DynamicVideo _video(JsonObject archive) {
  final aid = _int(archive.map['aid']) ?? 0;
  final bvid = archive.text('bvid') ?? '';
  if (bvid.isEmpty && aid <= 0) throw const DecodeError('archive: no aid or bvid');
  final durationText = archive.text('duration_text') ?? '';
  final stat = archive.nested('stat');
  final badge = archive.nested('badge')?.text('text') ?? '';
  return DynamicVideo(
    aid: aid,
    bvid: bvid.isNotEmpty ? bvid : avToBv(aid),
    title: archive.text('title') ?? '',
    cover: archive.text('cover') ?? '',
    durationText: durationText,
    duration: _seconds(durationText),
    plays: _string(stat?.map['play']),
    danmaku: _string(stat?.map['danmaku']),
    badge: badge == '投稿视频' ? '' : badge,
  );
}

/// "00:56" or "1:02:03" in seconds; 0 when it isn't one.
int _seconds(String text) {
  if (text.isEmpty) return 0;
  var total = 0;
  for (final part in text.split(':')) {
    final value = int.tryParse(part.trim());
    if (value == null || value < 0) return 0;
    total = total * 60 + value;
  }
  return total;
}

/// Null when there is neither a picture nor a title: a text post's opus carries only its text.
DynamicPictures? _pictures(List<Object?> pictures, {required String url, String title = ''}) {
  final decoded = lossy(pictures, (json) {
    final picture = JsonObject.from(json, 'picture');
    final address = picture.text(url) ?? '';
    if (address.isEmpty) throw const DecodeError('picture: no url');
    return DynamicPicture(
      url: address,
      width: _int(picture.map['width']) ?? 0,
      height: _int(picture.map['height']) ?? 0,
    );
  });
  if (decoded.isEmpty && title.isEmpty) return null;
  return DynamicPictures(pictures: decoded, title: title);
}

/// Its title and cover from the object the type names (`MAJOR_TYPE_LIVE_RCMD` → `live_rcmd`); 直播推荐 sends its
/// own as a JSON string.
DynamicOtherMajor _otherMajor(JsonObject major) {
  final type = major.text('type') ?? '';
  const prefix = 'MAJOR_TYPE_';
  final key = type.startsWith(prefix) ? type.substring(prefix.length).toLowerCase() : '';
  var body = key.isEmpty ? null : major.nested(key);
  if (key == 'live_rcmd' && body != null) body = _livePlayInfo(body.text('content')) ?? body;
  return DynamicOtherMajor(
    typeName: type,
    title: body?.text('title') ?? body?.text('tips') ?? '',
    cover: body?.text('cover') ?? '',
  );
}

JsonObject? _livePlayInfo(String? content) {
  if (content == null || content.isEmpty) return null;
  try {
    final decoded = jsonDecode(content);
    return decoded is Map<String, Object?> ? JsonObject(decoded).nested('live_play_info') : null;
  } on FormatException {
    return null;
  }
}

DynamicGoods? _goods(JsonObject? additional) {
  if (additional?.text('type') != 'ADDITIONAL_TYPE_GOODS') return null;
  final goods = additional?.nested('goods');
  if (goods == null) return null;
  final items = goods.lenientList('items', (json) {
    final item = JsonObject.from(json, 'goods item');
    return DynamicGoodsItem(
      name: item.text('name') ?? '',
      cover: item.text('cover') ?? '',
      brief: item.text('brief') ?? '',
      jumpText: item.text('jump_desc') ?? '',
    );
  });
  return items.isEmpty ? null : DynamicGoods(headText: goods.text('head_text') ?? '', items: items);
}

DynamicStat _stat(JsonObject? stat) {
  if (stat == null) return const DynamicStat();
  final like = stat.nested('like');
  return DynamicStat(
    forward: _count(stat.nested('forward')),
    comment: _count(stat.nested('comment')),
    like: _count(like),
    liked: switch (like?.map['status']) {
      final bool liked => liked,
      final int status => status == 1,
      'STATE_LIKE' => true,
      _ => false,
    },
    favourite: switch (stat.nested('favorite')) {
      final favourite? => _count(favourite),
      null => null,
    },
  );
}

int _count(JsonObject? stat) {
  final count = stat?.count('count') ?? 0;
  return count < 0 ? 0 : count;
}

List<DynamicMenuItem> _menu(JsonObject? more) => [
  for (final type
      in more?.lenientList('three_point_items', (json) => JsonObject.from(json).text('type') ?? '') ?? const <String>[])
    switch (type) {
      'THREE_POINT_FOLLOWING' => DynamicMenuItem.unfollow,
      'THREE_POINT_REPORT' => DynamicMenuItem.report,
      _ => DynamicMenuItem.other,
    },
];

/// `basic`'s area; when it says type 0, a video's aid (1), a picture post's `rid_str` (11) or a text post or
/// repost's own [id] (17), else null.
CommentArea? _comments(
  JsonObject? basic, {
  required String id,
  required DynamicKind kind,
  required DynamicMajor? major,
}) {
  final oid = _int(basic?.map['comment_id_str']) ?? 0;
  final type = _int(basic?.map['comment_type']) ?? 0;
  if (oid > 0 && type > 0) return CommentArea(oid: oid, type: type);
  if (major case DynamicVideo(:final aid) when aid > 0) return CommentArea(oid: aid, type: 1);
  switch (kind) {
    case DynamicKind.draw:
      final rid = _int(basic?.map['rid_str']) ?? 0;
      if (rid > 0) return CommentArea(oid: rid, type: 11);
    case DynamicKind.word || DynamicKind.forward:
      final own = _int(id) ?? 0;
      if (own > 0) return CommentArea(oid: own, type: 17);
    case DynamicKind.video || DynamicKind.article || DynamicKind.live || DynamicKind.pgc || DynamicKind.other:
      break;
  }
  return null;
}

DynamicUp _up(Object? json) {
  final up = JsonObject.from(json, 'up');
  final mid = _int(up.map['mid']);
  if (mid == null) throw const DecodeError('up: missing mid');
  return DynamicUp(
    mid: mid,
    name: up.text('uname') ?? '',
    face: up.text('face') ?? '',
    hasUpdate: up.flag('has_update'),
  );
}

FollowingUser _following(Object? json) {
  final user = JsonObject.from(json, 'following');
  final mid = _int(user.map['mid']);
  if (mid == null) throw const DecodeError('following: missing mid');
  final vip = user.nested('vip');
  return FollowingUser(
    mid: mid,
    name: user.text('uname') ?? '',
    face: user.text('face') ?? '',
    sign: user.text('sign') ?? '',
    verify: _verify(user.nested('official_verify')?.map['type']),
    vipPink: _vipPink(
      status: vip?.map['vipStatus'] ?? vip?.map['status'],
      type: vip?.map['vipType'] ?? vip?.map['type'],
    ),
  );
}

FollowedBangumi _bangumi(Object? json) {
  final season = JsonObject.from(json, 'bangumi');
  final seasonId = _int(season.map['season_id']);
  if (seasonId == null) throw const DecodeError('bangumi: missing season_id');
  return FollowedBangumi(
    seasonId: seasonId,
    title: season.text('title') ?? '',
    cover: season.text('cover') ?? '',
    progress: season.nested('new_ep')?.text('index_show') ?? '',
  );
}

List<Object?> _list(Object? value) => value is List ? List<Object?>.of(value) : const [];

/// Ids and counts come as numbers or as strings of digits, depending on the call.
int? _int(Object? value) => asInt(value) ?? (value is String ? int.tryParse(value.trim()) : null);

String _string(Object? value) => switch (value) {
  final String text => text,
  final int number => '$number',
  _ => '',
};
