import 'dart:async';

import 'package:bili_core/api.dart';

import 'watch_later_api.dart';

/// Answers from memory, for tests and `--fake-account`: a server-side list that removing, clearing and moving change,
/// paged and filtered as the website does.
class FakeWatchLaterApi implements WatchLaterApi {
  FakeWatchLaterApi({List<WatchLaterItem> items = const [], this.folderList = const [], this.delay = Duration.zero})
    : items = [...items];

  /// 23 made-up videos, newest added first, so paging, both chips, both orders and every progress label show; covers
  /// are empty so nothing is fetched.
  factory FakeWatchLaterApi.demo() {
    final rows = [
      for (var i = 1; i <= 23; i++)
        WatchLaterItem(
          aid: 81000000 + i,
          bvid: 'BV1later${i.toString().padLeft(4, '0')}',
          cid: 140000000 + i,
          title: i == 1 ? '测试视频标题一！说明很长的标题！会换到第二行-再来几个字最后【演示用】' : '稍后再看演示视频 $i',
          cover: '',
          ownerMid: 700 + i,
          ownerName: 'UP主$i',
          duration: 412 + i * 37,
          progress: switch (i % 4) {
            0 => -1,
            1 => i,
            2 => 0,
            _ => 60,
          },
          play: 104000 + i * 1300,
          danmaku: 175 + i,
        ),
    ];
    return FakeWatchLaterApi(
      items: rows,
      folderList: const [
        FavFolder(id: 9001, title: '默认收藏夹', count: 0, isPrivate: false, contains: false, isDefault: true),
        FavFolder(id: 9002, title: '演示收藏夹', count: 8, isPrivate: true, contains: false, isDefault: false),
      ],
      delay: const Duration(milliseconds: 300),
    )..invalid.add(81000000 + 23);
  }

  /// The list as the server holds it, newest added first.
  final List<WatchLaterItem> items;

  /// Aids whose video is gone (一键清除已失效视频 takes them).
  final Set<int> invalid = {};
  final List<FavFolder> folderList;
  Duration delay;

  /// Every call, in words a test can read.
  final List<String> calls = [];

  /// A call named here throws this instead of answering.
  final Map<String, Object> failures = {};

  /// A call named here waits for its completer, as if the server hadn't answered.
  final Map<String, Completer<void>> holds = {};

  /// The 收藏 folders' contents, as copy and move leave them.
  final Map<int, List<int>> folderContents = {};

  Future<T> _answer<T>(String name, String call, T Function() value) async {
    calls.add(call);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (holds[name] case final hold?) await hold.future;
    if (failures[name] case final failure?) throw failure;
    return value();
  }

  @override
  Future<WatchLaterListPage> list({required WatchLaterFilter filter, required bool oldestFirst, required int page}) =>
      _answer('list', 'list ${filter.name} ${oldestFirst ? 'oldest' : 'newest'} page=$page', () {
        final kept = [
          for (final item in oldestFirst ? items.reversed : items)
            if (filter == WatchLaterFilter.all || item.progress != -1) item,
        ];
        const size = 20;
        final start = (page - 1) * size;
        final rows = kept.skip(start).take(size).toList();
        return WatchLaterListPage(
          items: rows,
          total: kept.length,
          hasMore: rows.isNotEmpty && page * size < kept.length,
        );
      });

  @override
  Future<void> remove({required List<int> aids}) =>
      _answer('remove', 'remove ${aids.join(',')}', () => items.removeWhere((item) => aids.contains(item.aid)));

  @override
  Future<void> clear(WatchLaterClean kind) => _answer('clear', 'clear ${kind.name}', () {
    items.removeWhere(
      (item) => switch (kind) {
        WatchLaterClean.watched => item.progress == -1,
        WatchLaterClean.invalid => invalid.contains(item.aid),
      },
    );
  });

  @override
  Future<List<FavFolder>> folders({required int mid, required int aid}) =>
      _answer('folders', 'folders mid=$mid aid=$aid', () => folderList);

  @override
  Future<void> copyToFolder({required List<int> aids, required int folderId, required int mid}) => _answer(
    'copyToFolder',
    'copy ${aids.join(',')} to=$folderId mid=$mid',
    () => (folderContents[folderId] ??= []).addAll(aids),
  );

  @override
  Future<void> moveToFolder({required List<int> aids, required int folderId}) =>
      _answer('moveToFolder', 'move ${aids.join(',')} to=$folderId', () {
        (folderContents[folderId] ??= []).addAll(aids);
        items.removeWhere((item) => aids.contains(item.aid));
      });
}
