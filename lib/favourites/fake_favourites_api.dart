import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/logic.dart' show CountFormat;

import 'favourites_api.dart';

/// Answers from memory, for tests and `--fake-account`: nothing leaves the machine. Folders hold [contents] (newest
/// first), and 视频 lists every video once, newest first, [pageSize] at a time. [calls] lists what was asked, in
/// order; [holds] keeps a call waiting and [failures] makes it throw, both by method name.
class FakeFavouritesApi implements FavouritesApi {
  FakeFavouritesApi({
    List<FavFolder> folders = const [],
    Map<int, List<FavVideo>> contents = const {},
    this.ownerName = '测试账号',
    this.pageSize = 20,
    this.videosTabId = 12,
  }) : _folders = [...folders],
       _contents = {
         for (final MapEntry(:key, :value) in contents.entries) key: [...value],
       };

  /// The PC's `--fake-account` run: the default folder empty, a private one with 45 videos (two pages and the end), a
  /// public one with 2, and one with exactly 3. Covers are empty so nothing is fetched.
  factory FakeFavouritesApi.demo() {
    FavVideo video(int i, {int? duration}) => FavVideo(
      aid: 9000 + i,
      bvid: bvidOf(9000 + i),
      title: i.isEven ? '演示收藏 第${i + 1}个' : '演示收藏 第${i + 1}个：一个长一点的标题，好看看两行之后怎么截断',
      duration: duration ?? 8 + i * 41,
      ownerMid: 500 + i % 4,
      ownerName: '演示UP主${i % 4 + 1}',
      play: (i * 7919) % 120000,
      danmaku: (i * 31) % 300,
      favTime: 1760000000 - i * 3600,
    );
    final private = [for (var i = 0; i < 45; i++) video(i)];
    return FakeFavouritesApi(
      folders: const [
        FavFolder(id: 101, title: '默认收藏夹', count: 0, isPrivate: false, contains: false, isDefault: true),
        FavFolder(id: 102, title: '演示收藏夹', count: 45, isPrivate: true, contains: false, isDefault: false),
        FavFolder(id: 103, title: '公开的收藏', count: 2, isPrivate: false, contains: false, isDefault: false),
        FavFolder(id: 104, title: '刚好三个', count: 3, isPrivate: false, contains: false, isDefault: false),
      ],
      contents: {
        101: const [],
        102: private,
        103: [video(50, duration: 3725), private[1]],
        104: [video(60), video(61), video(62)],
      },
    );
  }

  final List<FavFolder> _folders;
  final Map<int, List<FavVideo>> _contents;
  final String ownerName;
  final int pageSize;

  /// What `/x/v3/fav/tab` answers as 视频's id; null for an answer without it.
  final int? videosTabId;

  final calls = <String>[];
  final holds = <String, Completer<void>>{};
  final failures = <String, Object>{};

  Future<T> _answer<T>(String name, String call, T Function() value) async {
    calls.add(call);
    if (holds[name] case final hold?) await hold.future;
    if (failures[name] case final failure?) throw failure;
    return value();
  }

  /// A folder's videos as they stand now.
  List<FavVideo> videosIn(int folderId) => List.unmodifiable(_contents[folderId] ?? const []);

  @override
  Future<List<FavFolder>> folders({required int mid}) => _answer(
    'folders',
    'folders mid=$mid',
    () => [
      for (final folder in _folders)
        FavFolder(
          id: folder.id,
          title: folder.title,
          count: _contents[folder.id]?.length ?? folder.count,
          isPrivate: folder.isPrivate,
          contains: false,
          isDefault: folder.isDefault,
        ),
    ],
  );

  @override
  Future<FavFolderPage> folderVideos({required int folderId, required int page, int pageSize = 20}) =>
      _answer('folderVideos', 'folderVideos folder=$folderId page=$page size=$pageSize', () {
        final all = _contents[folderId] ?? const <FavVideo>[];
        final folder = _folders.where((folder) => folder.id == folderId).firstOrNull;
        final start = (page - 1) * pageSize;
        final rows = start >= all.length
            ? const <FavVideo>[]
            : all.sublist(start, (start + pageSize).clamp(0, all.length));
        return FavFolderPage(
          info: FavFolderInfo(
            id: folderId,
            title: folder?.title ?? '',
            count: all.length,
            ownerMid: 1,
            ownerName: ownerName,
            isPrivate: folder?.isPrivate ?? false,
          ),
          videos: rows,
          hasMore: start + rows.length < all.length,
        );
      });

  @override
  Future<void> removeFromFolder({required int folderId, required int aid}) =>
      _answer('removeFromFolder', 'removeFromFolder folder=$folderId aid=$aid', () {
        _contents[folderId]?.removeWhere((video) => video.aid == aid);
      });

  @override
  Future<int?> videosTab() => _answer('videosTab', 'videosTab', () => videosTabId);

  @override
  Future<FavTabPage> allVideos({required int tabId, FavTabCursor? after}) =>
      _answer('allVideos', 'allVideos tab=$tabId after=${after?.score}', () {
        final seen = <int>{};
        final every = [
          for (final videos in _contents.values)
            for (final video in videos)
              if (seen.add(video.aid)) video,
        ]..sort((a, b) => b.favTime.compareTo(a.favTime));
        final start = after?.score ?? 0;
        final end = (start + pageSize).clamp(0, every.length);
        final rows = start >= every.length ? const <FavVideo>[] : every.sublist(start, end);
        final hasMore = end < every.length;
        return FavTabPage(
          items: [for (final (index, video) in rows.indexed) _tabVideo(video, start + index)],
          hasMore: hasMore,
          next: hasMore ? FavTabCursor(oid: rows.last.aid, otype: 2, score: end) : null,
          total: every.length,
        );
      });

  static FavTabVideo _tabVideo(FavVideo video, int index) => FavTabVideo(
    aid: video.aid,
    bvid: video.bvid,
    title: video.title,
    cover: video.cover,
    ownerMid: video.ownerMid,
    ownerName: video.ownerName,
    progress: const [100, 12, 100, 0, 55][index % 5],
    progressText: _clock(video.duration),
    plays: CountFormat.short(video.play),
    danmaku: CountFormat.short(video.danmaku),
  );

  static String _clock(int seconds) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = seconds ~/ 3600, m = seconds % 3600 ~/ 60, s = seconds % 60;
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  Future<void> removeEverywhere({required int aid}) => _answer('removeEverywhere', 'removeEverywhere aid=$aid', () {
    for (final videos in _contents.values) {
      videos.removeWhere((video) => video.aid == aid);
    }
  });
}
