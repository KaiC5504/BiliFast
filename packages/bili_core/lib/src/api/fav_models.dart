/// 我的收藏's folders and their videos.
library;

import 'action_models.dart';
import 'json.dart';

/// A page of the account's own folders, the default first: `/x/v3/fav/folder/created/list`'s `data`, which unlike
/// `list-all` carries each folder's cover.
final class FavFolderListPage {
  const FavFolderListPage({required this.folders, this.covers = const {}, required this.hasMore});

  factory FavFolderListPage.fromJson(Object? json) {
    final data = JsonObject.from(json, 'folders');
    final covers = <int, String>{};
    final folders = data.lossyList('list', (json) {
      final folder = FavFolder.fromJson(json);
      final cover = JsonObject.from(json).text('cover') ?? '';
      if (cover.isNotEmpty) covers[folder.id] = cover;
      return folder;
    });
    return FavFolderListPage(folders: folders, covers: covers, hasMore: data.flag('has_more'));
  }

  static const empty = FavFolderListPage(folders: [], hasMore: false);

  final List<FavFolder> folders;

  /// Each folder's cover by its id: the one picked for it, else its newest video's. A folder without one is absent.
  final Map<int, String> covers;
  final bool hasMore;
}

/// Where an uploaded cover went: `/x/upload/web/image`'s `data.location`.
String decodeUploadedCover(Object? json) {
  final data = JsonObject.from(json, 'upload');
  final location = data.required(data.string('location'), 'location');
  if (location.isEmpty) throw const DecodeError('empty location');
  return location;
}

/// A folder's own line on its page (81): `/x/v3/fav/resource/list`'s `info`.
final class FavFolderInfo {
  const FavFolderInfo({
    required this.id,
    required this.title,
    required this.count,
    this.ownerMid = 0,
    this.ownerName = '',
    this.isPrivate = false,
  });

  factory FavFolderInfo.fromJson(Object? json) {
    final object = JsonObject.from(json, 'folder');
    final upper = object.nested('upper');
    return FavFolderInfo(
      id: object.required(object.integer('id'), 'id'),
      title: object.string('title') ?? '',
      count: object.count('media_count'),
      ownerMid: upper?.integer('mid') ?? 0,
      ownerName: upper?.string('name') ?? '',
      // As the folder list's attr: bit 0 marks a private folder.
      isPrivate: object.count('attr') & 1 == 1,
    );
  }

  final int id;
  final String title;
  final int count;
  final int ownerMid;
  final String ownerName;
  final bool isPrivate;

  FavFolderInfo withCount(int count) =>
      FavFolderInfo(id: id, title: title, count: count, ownerMid: ownerMid, ownerName: ownerName, isPrivate: isPrivate);
}

/// A video in a folder (81): one of `/x/v3/fav/resource/list`'s `medias`.
final class FavVideo {
  const FavVideo({
    required this.aid,
    required this.bvid,
    required this.title,
    this.cover = '',
    this.duration = 0,
    this.ownerMid = 0,
    this.ownerName = '',
    this.play = 0,
    this.danmaku = 0,
    this.favTime = 0,
    this.invalid = false,
  });

  /// Null for what isn't a video (audio, 番剧, articles), which the app can't open.
  static FavVideo? fromJson(Object? json) {
    final object = JsonObject.from(json, 'media');
    if (object.count('type') != _videoType) return null;
    final aid = object.required(object.integer('id'), 'id');
    final upper = object.nested('upper');
    final counts = object.nested('cnt_info');
    final bvid = object.string('bvid', 'bv_id') ?? '';
    return FavVideo(
      aid: aid,
      bvid: bvid.isEmpty ? bvidOf(aid) : bvid,
      title: object.string('title') ?? '',
      cover: object.string('cover') ?? '',
      duration: object.count('duration'),
      ownerMid: upper?.integer('mid') ?? 0,
      ownerName: upper?.string('name') ?? '',
      play: counts?.count('play') ?? 0,
      danmaku: counts?.count('danmaku') ?? 0,
      favTime: object.count('fav_time'),
      // 1: taken down, 9: deleted by its uploader (PiliPlus's reading).
      invalid: const {1, 9}.contains(object.count('attr')),
    );
  }

  static const _videoType = 2;

  final int aid;
  final String bvid;
  final String title;
  final String cover;

  /// Seconds.
  final int duration;
  final int ownerMid;
  final String ownerName;
  final int play;
  final int danmaku;
  final int favTime;
  final bool invalid;
}

/// A page of a folder's videos, with the folder's [info] on every page.
final class FavFolderPage {
  const FavFolderPage({this.info, required this.videos, required this.hasMore});

  /// The `data` of `/x/v3/fav/resource/list`; an empty folder answers no `medias`.
  factory FavFolderPage.fromJson(Object? json) {
    final data = JsonObject.from(json, 'page');
    final info = data.nested('info');
    return FavFolderPage(
      info: info == null ? null : attempt(() => FavFolderInfo.fromJson(info.map)),
      videos: [for (final video in data.lenientList('medias', FavVideo.fromJson)) ?video],
      hasMore: data.flag('has_more'),
    );
  }

  static const empty = FavFolderPage(videos: [], hasMore: false);

  final FavFolderInfo? info;
  final List<FavVideo> videos;
  final bool hasMore;
}

/// Where 视频's next page starts: the last page's `next_oid`, `next_otype` and `next_score`.
final class FavTabCursor {
  const FavTabCursor({required this.oid, required this.otype, required this.score});

  final int oid;
  final int otype;
  final int score;

  @override
  bool operator ==(Object other) =>
      other is FavTabCursor && other.oid == oid && other.otype == otype && other.score == score;

  @override
  int get hashCode => Object.hash(oid, otype, score);
}

/// A video in 视频 (83): one of `/x/v3/fav/tab/fav`'s items, read with the official app's own field names
/// (`FavoritesMediasItem`). The cover's corner shows [progressText] and its pink line [progress] per cent; the counts
/// come already worded.
final class FavTabVideo {
  const FavTabVideo({
    required this.aid,
    required this.bvid,
    required this.title,
    this.cover = '',
    this.cid = 0,
    this.ownerMid = 0,
    this.ownerName = '',
    this.progress = 0,
    this.progressText = '',
    this.plays = '',
    this.danmaku = '',
    this.invalid = false,
  });

  /// Null for what isn't a video.
  static FavTabVideo? fromJson(Object? json) {
    final object = JsonObject.from(json, 'item');
    if (object.count('otype') != _videoType) return null;
    final aid = object.required(object.integer('oid'), 'oid');
    final upper = object.nested('upper');
    return FavTabVideo(
      aid: aid,
      bvid: bvidOf(aid),
      title: object.string('title') ?? '',
      cover: object.string('cover') ?? '',
      cid: object.nested('ugc')?.integer('first_cid') ?? 0,
      ownerMid: upper?.integer('mid') ?? 0,
      ownerName: upper?.string('name') ?? '',
      progress: object.count('playback_position').clamp(0, 100),
      progressText: object.text('playback_desc') ?? '',
      plays: object.text('left_text') ?? '',
      danmaku: object.text('right_text') ?? '',
      invalid: object.flag('is_invalid'),
    );
  }

  static const _videoType = 2;

  final int aid;
  final String bvid;
  final String title;
  final String cover;
  final int cid;
  final int ownerMid;
  final String ownerName;

  /// How much has been watched, 0-100; 0 draws no line.
  final int progress;
  final String progressText;
  final String plays;
  final String danmaku;
  final bool invalid;
}

/// A page of 视频. [next] is passed back for the page after; null when [hasMore] is false.
final class FavTabPage {
  const FavTabPage({required this.items, required this.hasMore, this.next, this.total = 0, this.listed = 0});

  /// The `data` of `/x/v3/fav/tab/fav` (`FavoritesTabList`).
  factory FavTabPage.fromJson(Object? json) {
    final data = JsonObject.from(json, 'page');
    final hasMore = data.flag('has_more');
    final listed = data.lenientList('list', FavTabVideo.fromJson);
    return FavTabPage(
      items: [for (final item in listed) ?item],
      listed: listed.length,
      hasMore: hasMore,
      next: hasMore
          ? FavTabCursor(oid: data.count('next_oid'), otype: data.count('next_otype'), score: data.count('next_score'))
          : null,
      total: data.count('total'),
    );
  }

  static const empty = FavTabPage(items: [], hasMore: false);

  final List<FavTabVideo> items;
  final bool hasMore;
  final FavTabCursor? next;
  final int total;

  /// The items the page listed that could be read, videos or not.
  final int listed;
}

/// 视频's id among `/x/v3/fav/tab`'s tabs (`FavoritesTabs`): any object in the answer named 视频 under a key that
/// names (`tab_name`, `sub_tab_name`, `title`…), its id under a key ending in `id`, as a number or a string; null when
/// the answer has none. On 1.0.0 (22) and (23) the phone's answer held only 收藏=1 and 追更=2, whatever `tab_id` asked.
int? favVideosTabId(Object? json) {
  int? found;
  void visit(Object? node) {
    if (found != null) return;
    if (node is Map) {
      if (_names(node).any((name) => name.trim() == _videosTabName)) found = _tabId(node);
      for (final value in node.values) {
        visit(value);
      }
    } else if (node is List) {
      for (final value in node) {
        visit(value);
      }
    }
  }

  visit(json);
  return found;
}

/// 收藏's id by its name, else the answer's `default_tab`: the list 视频 falls back to when no tab is named 视频.
int? favCollectTabId(Object? json) {
  if (json is! Map) return null;
  final tabs = json['tabs'];
  if (tabs is List) {
    for (final tab in tabs) {
      if (tab is Map && _names(tab).any((name) => name.trim() == '收藏')) return _tabId(tab);
    }
  }
  return _tabId({'tab_id': json['default_tab']});
}

/// The whole answer's shape for the log when [favVideosTabId] finds nothing: every key, numbers as they are, strings
/// cut short and links as `url`, lists to their first [_outlineItems], within [_outlineLength] characters.
String favTabsOutline(Object? json) {
  if (json == null) return 'no data';
  String shape(Object? node) => switch (node) {
    Map() => '{${[for (final MapEntry(:key, :value) in node.entries) '$key:${shape(value)}'].join(',')}}',
    List() => '[${[
      for (final value in node.take(_outlineItems)) shape(value),
      if (node.length > _outlineItems) '…${node.length}',
    ].join(',')}]',
    String() when node.contains('://') => 'url',
    String() when node.length > 16 => '${node.substring(0, 16)}…',
    _ => '$node',
  };
  final text = shape(json);
  return text.length > _outlineLength ? '${text.substring(0, _outlineLength)}…' : text;
}

const _outlineLength = 1500;
const _outlineItems = 6;

Iterable<String> _names(Map<Object?, Object?> tab) sync* {
  for (final MapEntry(:key, :value) in tab.entries) {
    if (key is String && value is String && (key.endsWith('name') || key.endsWith('title') || key == 'text')) {
      yield value;
    }
  }
}

int? _tabId(Map<Object?, Object?> tab) {
  int? read(Object? id) => switch (id) {
    final int id => id,
    final String id => int.tryParse(id),
    _ => null,
  };
  final named = read(tab['tab_id'] ?? tab['sub_tab_id'] ?? tab['id']);
  if (named != null) return named;
  for (final MapEntry(:key, :value) in tab.entries) {
    if (key is! String || !key.endsWith('id')) continue;
    if (read(value) case final int id) return id;
  }
  return null;
}

const _videosTabName = '视频';

/// The BV id Bilibili gives the video [aid] (the 54-bit scheme of 2024, which the 2020 ids also follow).
String bvidOf(int aid) {
  const alphabet = 'FcwAPNKTMug3GV5Lj7EJnHpWsx4tb8haYeviqBz6rkCy12mUSDQX9RdoZf';
  const xorCode = 23442827791579;
  const maxAid = 1 << 51;
  final chars = 'BV1000000000'.split('');
  var rest = (maxAid | aid) ^ xorCode;
  for (var at = chars.length - 1; rest > 0; at--) {
    chars[at] = alphabet[rest % alphabet.length];
    rest ~/= alphabet.length;
  }
  void swap(int a, int b) {
    final kept = chars[a];
    chars[a] = chars[b];
    chars[b] = kept;
  }

  swap(3, 9);
  swap(4, 7);
  return chars.join();
}
