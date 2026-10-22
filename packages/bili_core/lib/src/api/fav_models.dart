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
  const FavTabPage({required this.items, required this.hasMore, this.next, this.total = 0});

  /// The `data` of `/x/v3/fav/tab/fav` (`FavoritesTabList`).
  factory FavTabPage.fromJson(Object? json) {
    final data = JsonObject.from(json, 'page');
    final hasMore = data.flag('has_more');
    return FavTabPage(
      items: [for (final item in data.lenientList('list', FavTabVideo.fromJson)) ?item],
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
}

/// 视频's id among `/x/v3/fav/tab`'s tabs and their sub tabs (`FavoritesTabs`), found by its name at any depth, the
/// id as a number or a string; null when the answer has no such tab. 1.0.0 (21) found none with the stricter read.
int? favVideosTabId(Object? json) {
  int? found;
  void visit(Object? node) {
    if (found != null) return;
    if (node is Map) {
      if (_tabName(node)?.trim() == _videosTabName) found = _tabId(node);
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

/// The tabs' names and ids, nested as the answer has them, for the log when [favVideosTabId] finds nothing.
String favTabsOutline(Object? json) {
  if (json is! Map) return json == null ? 'no data' : json.runtimeType.toString();
  String tabs(Object? list) => list is List
      ? [
          for (final tab in list)
            if (tab is Map) '${_tabName(tab)}=${_tabId(tab)}${tab['sub_tabs'] == null ? '' : '[${tabs(tab['sub_tabs'])}]'}',
        ].join(', ')
      : '$list';
  return 'keys ${json.keys.join(',')}; tabs ${tabs(json['tabs'])}';
}

String? _tabName(Map<Object?, Object?> tab) => switch (tab['tab_name'] ?? tab['name'] ?? tab['title']) {
  final String name => name,
  _ => null,
};

int? _tabId(Map<Object?, Object?> tab) => switch (tab['tab_id'] ?? tab['sub_tab_id'] ?? tab['id']) {
  final int id => id,
  final String id => int.tryParse(id),
  _ => null,
};

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
