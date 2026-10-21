import 'json.dart';

/// Text from a search answer, split where Bilibili marks the keyword (`<em class="keyword">`), with HTML entities
/// decoded.
final class HighlightedText {
  const HighlightedText(this.runs);

  HighlightedText.plain(String text) : runs = [HighlightRun(text)];

  /// [text] with every occurrence of [term] marked, whatever its case, as a suggestion draws what was typed.
  factory HighlightedText.marking(String text, String term) {
    final needle = term.trim();
    final pieces = <HighlightRun>[];
    var start = 0;
    if (needle.isNotEmpty) {
      for (final match in RegExp(RegExp.escape(needle), caseSensitive: false).allMatches(text)) {
        pieces.add(HighlightRun(text.substring(start, match.start)));
        pieces.add(HighlightRun(match[0]!, highlighted: true));
        start = match.end;
      }
    }
    pieces.add(HighlightRun(text.substring(start)));
    return HighlightedText(_merged(pieces));
  }

  final List<HighlightRun> runs;

  String get text => runs.map((run) => run.text).join();

  /// Any `<em …>` marks (the results' `keyword`, the suggestions' `suggest_high_light`); other tags are dropped.
  static HighlightedText parse(String html) {
    final pieces = <HighlightRun>[];
    var depth = 0;
    var start = 0;
    for (final tag in _tag.allMatches(html)) {
      pieces.add(HighlightRun(_decodeEntities(html.substring(start, tag.start)), highlighted: depth > 0));
      start = tag.end;
      if (tag[2]!.toLowerCase() != 'em' || tag[0]!.endsWith('/>')) continue;
      if (tag[1] == '/') {
        if (depth > 0) depth--;
      } else {
        depth++;
      }
    }
    pieces.add(HighlightRun(_decodeEntities(html.substring(start)), highlighted: depth > 0));
    return HighlightedText(_merged(pieces));
  }

  /// A tag must start with a letter, so "1<2" or "<3" in a title stays text.
  static final _tag = RegExp(r'<(/?)([A-Za-z][A-Za-z0-9]*)(?=[\s/>])[^<>]*>');
  static final _entity = RegExp(r'&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[A-Za-z]+);');
  static const _named = {'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' '};

  static String _decodeEntities(String text) {
    if (!text.contains('&')) return text;
    return text.replaceAllMapped(_entity, (match) {
      final body = match[1]!;
      if (!body.startsWith('#')) return _named[body] ?? match[0]!;
      final hex = body.length > 1 && (body[1] == 'x' || body[1] == 'X');
      final code = int.tryParse(body.substring(hex ? 2 : 1), radix: hex ? 16 : 10);
      if (code == null || code == 0 || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)) return match[0]!;
      return String.fromCharCode(code);
    });
  }

  static List<HighlightRun> _merged(List<HighlightRun> pieces) {
    final runs = <HighlightRun>[];
    for (final piece in pieces) {
      if (piece.text.isEmpty) continue;
      final last = runs.isEmpty ? null : runs.last;
      if (last != null && last.highlighted == piece.highlighted) {
        runs[runs.length - 1] = HighlightRun(last.text + piece.text, highlighted: last.highlighted);
      } else {
        runs.add(piece);
      }
    }
    return runs;
  }

  @override
  bool operator ==(Object other) => other is HighlightedText && listEquals(other.runs, runs);

  @override
  int get hashCode => Object.hashAll(runs);

  @override
  String toString() => 'HighlightedText($runs)';
}

final class HighlightRun {
  const HighlightRun(this.text, {this.highlighted = false});

  final String text;
  final bool highlighted;

  @override
  bool operator ==(Object other) => other is HighlightRun && other.text == text && other.highlighted == highlighted;

  @override
  int get hashCode => Object.hash(text, highlighted);

  @override
  String toString() => highlighted ? '<$text>' : text;
}

/// One of bilibili热搜's words (52); [icon] is the picture of its 热 or 新 badge, if it has one.
final class HotWord {
  const HotWord({required this.keyword, required this.showName, this.icon});

  factory HotWord.fromJson(Object? json) {
    final object = JsonObject.from(json);
    final keyword = _keyword(object);
    final icon = _filled(object.text('icon'));
    return HotWord(
      keyword: keyword,
      showName: _filled(object.text('show_name')) ?? keyword,
      icon: icon == null ? null : _secure(icon),
    );
  }

  final String keyword;
  final String showName;
  final String? icon;

  @override
  bool operator ==(Object other) =>
      other is HotWord && other.keyword == keyword && other.showName == showName && other.icon == icon;

  @override
  int get hashCode => Object.hash(keyword, showName, icon);
}

/// One of 搜索发现's words (52).
final class DiscoveryWord {
  const DiscoveryWord({required this.keyword, required this.showName, this.suffix = ''});

  /// The grey part is `recommend_reason` ("·昨天更新", as PiliPlus reads it), else `pub_time`.
  factory DiscoveryWord.fromJson(Object? json) {
    final object = JsonObject.from(json);
    final keyword = _keyword(object);
    final reason = _undotted(object.text('recommend_reason')) ?? _undotted(object.text('pub_time'));
    return DiscoveryWord(
      keyword: keyword,
      showName: _filled(object.text('show_name')) ?? keyword,
      suffix: reason ?? '',
    );
  }

  static String? _undotted(String? text) {
    final trimmed = text?.trim();
    if (trimmed == null) return null;
    return _filled(trimmed.startsWith('·') ? trimmed.substring(1).trim() : trimmed);
  }

  final String keyword;
  final String showName;

  /// The grey part after a ·, as 52's 绝区零·昨天更新; '' when there is none.
  final String suffix;

  @override
  bool operator ==(Object other) =>
      other is DiscoveryWord && other.keyword == keyword && other.showName == showName && other.suffix == suffix;

  @override
  int get hashCode => Object.hash(keyword, showName, suffix);
}

/// A suggestion while typing (55): [keyword] is searched, [text] is drawn with the typed part marked.
final class SearchSuggestion {
  const SearchSuggestion({required this.keyword, required this.text});

  /// [term] is what was typed; it is marked in `value` unless the answer's `name` already carries marks.
  factory SearchSuggestion.fromJson(Object? json, String term) {
    final object = JsonObject.from(json);
    final keyword = _filled(object.text('value')) ?? _filled(object.text('term'));
    if (keyword == null || keyword.trim().isEmpty) throw const DecodeError('missing value');
    final name = object.text('name');
    return SearchSuggestion(
      keyword: keyword,
      text: name != null && _emOpen.hasMatch(name)
          ? HighlightedText.parse(name)
          : HighlightedText.marking(keyword, term),
    );
  }

  static final _emOpen = RegExp(r'<em[\s>]', caseSensitive: false);

  final String keyword;
  final HighlightedText text;

  @override
  bool operator ==(Object other) => other is SearchSuggestion && other.keyword == keyword && other.text == text;

  @override
  int get hashCode => Object.hash(keyword, text);
}

/// A video row of 综合 (56).
final class SearchVideo {
  const SearchVideo({
    required this.aid,
    required this.bvid,
    required this.title,
    required this.author,
    required this.mid,
    required this.cover,
    required this.play,
    required this.danmaku,
    required this.duration,
    required this.published,
  });

  factory SearchVideo.fromJson(Object? json) {
    final object = JsonObject.from(json);
    // 综合's video group also carries live rooms and courses, which have no bvid to open.
    final type = object.text('type');
    if (type != null && type != 'video') throw DecodeError('not a video: $type');
    final bvid = _filled(object.text('bvid'));
    if (bvid == null) throw const DecodeError('missing bvid');
    final pubdate = object.count('pubdate');
    return SearchVideo(
      aid: object.count('aid', 'id'),
      bvid: bvid,
      title: HighlightedText.parse(object.text('title') ?? ''),
      author: object.text('author') ?? '',
      mid: object.count('mid'),
      cover: _secure(object.text('pic') ?? ''),
      play: object.count('play'),
      danmaku: object.count('video_review', 'danmaku'),
      duration: _seconds(object.map['duration']),
      published: pubdate > 0 ? DateTime.fromMillisecondsSinceEpoch(pubdate * 1000) : null,
    );
  }

  final int aid;
  final String bvid;
  final HighlightedText title;
  final String author;
  final int mid;

  /// An https URL; the answer's are protocol-relative.
  final String cover;
  final int play;
  final int danmaku;

  /// In seconds; the answer writes "3:7" for 3:07 and "1234:56" for 20:34:56.
  final int duration;
  final DateTime? published;

  static int _seconds(Object? value) {
    final whole = asInt(value);
    if (whole != null) return whole;
    if (value is! String || value.isEmpty) return 0;
    var total = 0;
    for (final part in value.split(':')) {
      final number = int.tryParse(part.trim());
      if (number == null || number < 0) return 0;
      total = total * 60 + number;
    }
    return total;
  }

  @override
  bool operator ==(Object other) =>
      other is SearchVideo &&
      other.aid == aid &&
      other.bvid == bvid &&
      other.title == title &&
      other.author == author &&
      other.mid == mid &&
      other.cover == cover &&
      other.play == play &&
      other.danmaku == danmaku &&
      other.duration == duration &&
      other.published == published;

  @override
  int get hashCode => Object.hash(aid, bvid, title, author, mid, cover, play, danmaku, duration, published);
}

/// An uploader row of 用户 (60).
final class SearchUser {
  const SearchUser({
    required this.mid,
    required this.name,
    required this.face,
    required this.fans,
    required this.videos,
    required this.level,
    required this.sign,
    this.officialType,
    this.officialDesc = '',
    this.following = false,
  });

  /// The web search names no relation, so [following] is false unless an answer carries `is_atten`.
  factory SearchUser.fromJson(Object? json) {
    final object = JsonObject.from(json);
    final mid = object.count('mid');
    if (mid <= 0) throw const DecodeError('missing mid');
    final official = object.nested('official_verify');
    // Unverified accounts come as 127 here and -1 elsewhere.
    final type = asInt(official?.map['type']);
    return SearchUser(
      mid: mid,
      name: object.text('uname') ?? '',
      face: _secure(object.text('upic') ?? ''),
      fans: object.count('fans'),
      videos: object.count('videos'),
      level: object.count('level'),
      sign: object.text('usign') ?? '',
      officialType: type == 0 || type == 1 ? type : null,
      officialDesc: official?.text('desc') ?? '',
      following: object.flag('is_atten'),
    );
  }

  final int mid;
  final String name;

  /// An https URL.
  final String face;
  final int fans;
  final int videos;
  final int level;
  final String sign;

  /// 0 for a person (the yellow ⚡ on the avatar), 1 for an organisation (blue); null when not verified.
  final int? officialType;
  final String officialDesc;
  final bool following;

  @override
  bool operator ==(Object other) =>
      other is SearchUser &&
      other.mid == mid &&
      other.name == name &&
      other.face == face &&
      other.fans == fans &&
      other.videos == videos &&
      other.level == level &&
      other.sign == sign &&
      other.officialType == officialType &&
      other.officialDesc == officialDesc &&
      other.following == following;

  @override
  int get hashCode => Object.hash(mid, name, face, fans, videos, level, sign, officialType, officialDesc, following);
}

/// One page of a search; pages count from 1.
final class SearchPage<T> {
  const SearchPage({required this.items, required this.page, required this.pages});

  final List<T> items;
  final int page;
  final int pages;

  bool get hasMore => page < pages;
}

/// `order` of a video search (58's 排序方式).
enum SearchOrder { totalrank, pubdate, click, dm }

/// `duration` of a video search; the index is the value sent.
enum SearchDuration { any, under10, from10to30, from30to60, over60 }

String _keyword(JsonObject object) => _filled(object.string('keyword')) ?? (throw const DecodeError('missing keyword'));

String? _filled(String? text) => text == null || text.isEmpty ? null : text;

/// Pictures come protocol-relative ("//i0.hdslb.com/…") or as http.
String _secure(String url) {
  if (url.startsWith('//')) return 'https:$url';
  if (url.startsWith('http://')) return 'https://${url.substring(7)}';
  return url;
}
