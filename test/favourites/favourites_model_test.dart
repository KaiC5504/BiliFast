import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/favourites/fake_favourites_api.dart';
import 'package:bilifast/favourites/favourites_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'favourites_support.dart';

void main() {
  final logger = Logger(session: 'test');
  final rows45 = [for (var i = 0; i < 45; i++) favVideo(i)];

  FakeFavouritesApi api45() => FakeFavouritesApi(
    folders: [favFolder(1, '默认收藏夹', isDefault: true), favFolder(2, '满的', count: 45)],
    contents: {1: const [], 2: rows45},
  );

  group('FavouriteRow', () {
    test('a folder video words its length and counts, with no line', () {
      final row = FavouriteRow.fromFolder(favVideo(1, duration: 3725, play: 21000, danmaku: 3));
      expect(row.length, '01:02:05');
      expect(row.plays, '2.1万');
      expect(row.danmaku, '3');
      expect(row.progress, 0);
      expect(FavouriteRow.fromFolder(favVideo(2, duration: 11)).length, '00:11');
    });

    test('a 视频 item keeps its own words and its progress', () {
      const item = FavTabVideo(
        aid: 80433022,
        bvid: 'BV1GJ411x7h7',
        title: '标题',
        cid: 9,
        progress: 55,
        progressText: '00:53',
        plays: '2.1万',
        danmaku: '1',
      );
      final row = FavouriteRow.fromTab(item);
      expect(row.progress, 0.55);
      expect(row.length, '00:53');
      expect(row.route.bvid, 'BV1GJ411x7h7');
      expect(row.route.cid, 9);
      expect(row.route.start, isNull, reason: 'the page resumes from Bilibili’s last position, as 历史记录’s rows do');
    });

    test('the folder link and the count words', () {
      expect(FavouriteFormat.folderLink(1000201).toString(), 'https://www.bilibili.com/medialist/detail/ml1000201');
      expect(FavouriteFormat.cardCount(0), '0个内容');
      expect(FavouriteFormat.folderCount(8), '8 个内容');
    });
  });

  group('FolderVideosModel', () {
    FolderVideosModel model(FakeFavouritesApi api, {void Function(int)? onRemoved, bool loggedIn = true}) =>
        FolderVideosModel(
          api: api,
          folder: favFolder(2, '满的', count: 45),
          isLoggedIn: () => loggedIn,
          onRemoved: onRemoved,
          logger: logger,
        );

    test('pages 20 at a time to the end', () async {
      final api = api45();
      final folder = model(api);
      await folder.start();
      expect(folder.rows, hasLength(20));
      expect(folder.isEnd, isFalse);
      await folder.loadMore();
      await folder.loadMore();
      expect(folder.rows, hasLength(45));
      expect(folder.isEnd, isTrue);
      await folder.loadMore();
      expect(api.calls, [
        'folderVideos folder=2 page=1 size=20',
        'folderVideos folder=2 page=2 size=20',
        'folderVideos folder=2 page=3 size=20',
      ]);
      expect(folder.info.ownerName, '测试账号');
    });

    test('logged out it asks nothing and waits for a login', () async {
      final api = api45();
      final folder = model(api, loggedIn: false);
      await folder.start();
      expect(folder.needsLogin, isTrue);
      expect(api.calls, isEmpty);
    });

    test('a refused first page reads as words to retry, a -101 as the login', () async {
      final api = api45()..failures['folderVideos'] = const BiliError.http(500);
      final folder = model(api);
      await folder.start();
      expect(folder.error, '网络请求失败（HTTP 500）');
      api.failures['folderVideos'] = const BiliError.api(code: -101, message: '账号未登录');
      await folder.loadMore();
      expect(folder.needsLogin, isTrue);
    });

    test('取消收藏 takes the row off at once, the count follows, and the folder list hears', () async {
      final api = api45();
      final removed = <int>[];
      final folder = model(api, onRemoved: removed.add);
      await folder.start();
      final hold = api.holds['removeFromFolder'] = Completer<void>();
      final target = folder.rows[3];
      final removing = folder.remove(target);
      expect(folder.rows.any((row) => row.aid == target.aid), isFalse);
      expect(folder.info.count, 44);
      hold.complete();
      expect(await removing, isNull);
      expect(removed, [target.aid]);
      expect(api.calls.last, 'removeFromFolder folder=2 aid=${target.aid}');
      expect(api.videosIn(2).any((video) => video.aid == target.aid), isFalse);
    });

    test('a refused 取消收藏 puts the row back where it was and the count with it', () async {
      final api = api45()..failures['removeFromFolder'] = const BiliError.http(500);
      final removed = <int>[];
      final folder = model(api, onRemoved: removed.add);
      await folder.start();
      final before = [for (final row in folder.rows) row.aid];
      final message = await folder.remove(folder.rows[3]);
      expect(message, FavouriteRowsModel.removeFailed);
      expect([for (final row in folder.rows) row.aid], before);
      expect(folder.info.count, 45);
      expect(removed, isEmpty);
    });

    test('a 取消收藏 refused with -101 turns to the login', () async {
      final api = api45()..failures['removeFromFolder'] = const BiliError.api(code: -101, message: '');
      final folder = model(api);
      await folder.start();
      expect(await folder.remove(folder.rows.first), isNull);
      expect(folder.needsLogin, isTrue);
    });

    test('a removed row does not come back with a later page', () async {
      final api = FakeFavouritesApi(contents: {2: rows45}, pageSize: 20);
      final folder = model(api);
      await folder.start();
      api.holds['removeFromFolder'] = Completer<void>();
      final target = folder.rows.first;
      unawaited(folder.remove(target));
      await folder.reload();
      expect(folder.rows.where((row) => row.aid == target.aid), isEmpty);
    });

    test('an empty folder ends at once', () async {
      final api = FakeFavouritesApi(folders: [favFolder(1, '默认收藏夹')], contents: {1: const []});
      final folder = FolderVideosModel(api: api, folder: favFolder(1, '默认收藏夹'), isLoggedIn: () => true);
      await folder.start();
      expect(folder.rows, isEmpty);
      expect(folder.isEnd, isTrue);
      expect(folder.error, isNull);
    });
  });

  group('AllVideosModel', () {
    test('asks the tab once, then pages by the answer’s cursor', () async {
      final api = api45();
      final videos = AllVideosModel(api: api, isLoggedIn: () => true, logger: logger);
      await videos.start();
      await videos.loadMore();
      await videos.loadMore();
      expect(videos.rows, hasLength(45));
      expect(videos.isEnd, isTrue);
      expect(api.calls, [
        'videosTab',
        'allVideos tab=12 after=null',
        'allVideos tab=12 after=20',
        'allVideos tab=12 after=40',
      ]);
    });

    test('no 视频 tab in the answer reads as a failure', () async {
      final api = FakeFavouritesApi(videosTabId: null);
      final videos = AllVideosModel(api: api, isLoggedIn: () => true, logger: logger);
      await videos.start();
      expect(videos.error, '加载失败，请稍后重试');
    });

    test('取消收藏 takes the video out of every folder; a refusal puts it back', () async {
      final api = api45();
      final removed = <int>[];
      final videos = AllVideosModel(api: api, isLoggedIn: () => true, onRemoved: removed.add, logger: logger);
      await videos.start();
      final first = videos.rows.first;
      expect(await videos.remove(first), isNull);
      expect(api.calls.last, 'removeEverywhere aid=${first.aid}');
      expect(removed, [first.aid]);
      api.failures['removeEverywhere'] = const BiliError.http(500);
      final second = videos.rows.first;
      expect(await videos.remove(second), FavouriteRowsModel.removeFailed);
      expect(videos.rows.first.aid, second.aid);
    });
  });

  group('FavouriteFoldersModel', () {
    FavouriteFoldersModel model(FakeFavouritesApi api, {int? mid = 12345}) =>
        FavouriteFoldersModel(api: api, mid: () => mid, isLoggedIn: () => mid != null, logger: logger);

    test('the folders come in one call', () async {
      final api = api45();
      final folders = model(api);
      await folders.start();
      expect([for (final folder in folders.folders) folder.title], ['默认收藏夹', '满的']);
      expect(api.calls, ['folders mid=12345']);
    });

    test('covers are asked one card at a time, only for cards that ask, and never for an empty folder', () async {
      final api = FakeFavouritesApi(
        folders: [favFolder(1, '空', isDefault: true), favFolder(2, '甲', count: 3), favFolder(3, '乙', count: 2)],
        contents: {
          1: const [],
          2: [favVideo(1), favVideo(2), favVideo(3)],
          3: [favVideo(4), favVideo(5)],
        },
      );
      final folders = model(api);
      await folders.start();
      api.calls.clear();
      final hold = api.holds['folderVideos'] = Completer<void>();
      folders
        ..wantPreview(folders.folders[0])
        ..wantPreview(folders.folders[1])
        ..wantPreview(folders.folders[2]);
      await pumpEventQueue();
      expect(api.calls, ['folderVideos folder=2 page=1 size=3'], reason: 'one at a time; the empty one asks nothing');
      expect(folders.preview(1), isA<PreviewReady>().having((ready) => ready.videos, 'videos', isEmpty));
      expect(folders.preview(2), isA<PreviewLoading>());
      hold.complete();
      await pumpEventQueue();
      expect(api.calls, ['folderVideos folder=2 page=1 size=3', 'folderVideos folder=3 page=1 size=3']);
      expect((folders.preview(2)! as PreviewReady).videos, hasLength(3));
    });

    test('a card that left the screen before its turn asks nothing', () async {
      final api = FakeFavouritesApi(
        folders: [favFolder(2, '甲', count: 1), favFolder(3, '乙', count: 1)],
        contents: {
          2: [favVideo(1)],
          3: [favVideo(2)],
        },
      );
      final folders = model(api);
      await folders.start();
      api.calls.clear();
      final hold = api.holds['folderVideos'] = Completer<void>();
      folders
        ..wantPreview(folders.folders[0])
        ..wantPreview(folders.folders[1])
        ..dropPreview(3);
      hold.complete();
      await pumpEventQueue();
      expect(api.calls, ['folderVideos folder=2 page=1 size=3']);
      expect(folders.preview(3), isNull);
    });

    test('a failed cover stays grey and is not asked again', () async {
      final api = FakeFavouritesApi(
        folders: [favFolder(2, '甲', count: 1)],
        contents: {
          2: [favVideo(1)],
        },
      );
      final folders = model(api);
      await folders.start();
      api.failures['folderVideos'] = const BiliError.http(500);
      folders.wantPreview(folders.folders.first);
      await pumpEventQueue();
      folders.wantPreview(folders.folders.first);
      await pumpEventQueue();
      expect(folders.preview(2), isA<PreviewFailed>());
      expect(api.calls.where((call) => call.startsWith('folderVideos')), hasLength(1));
    });

    test('logged out it asks nothing', () async {
      final api = api45();
      final folders = model(api, mid: null);
      await folders.start();
      expect(folders.needsLogin, isTrue);
      expect(api.calls, isEmpty);
    });

    test('a failure with nothing shown reads as words; a -101 as the login', () async {
      final api = api45()..failures['folders'] = const BiliError.http(500);
      final folders = model(api);
      await folders.start();
      expect(folders.error, '网络请求失败（HTTP 500）');
      api.failures['folders'] = const BiliError.api(code: -101, message: '');
      await folders.reload();
      expect(folders.needsLogin, isTrue);
    });

    test('a removal in a folder takes one off its count and its cover off the card', () async {
      final api = FakeFavouritesApi(
        folders: [favFolder(2, '甲', count: 2)],
        contents: {
          2: [favVideo(1), favVideo(2)],
        },
      );
      final folders = model(api);
      await folders.start();
      folders.wantPreview(folders.folders.first);
      await pumpEventQueue();
      folders.removedFrom(2, 7001);
      expect(folders.folders.first.count, 1);
      expect([for (final video in (folders.preview(2)! as PreviewReady).videos) video.aid], [7002]);
    });

    test('a removal from 视频 asks the folders again when they next show, keeping the covers', () async {
      final api = FakeFavouritesApi(
        folders: [favFolder(2, '甲', count: 2)],
        contents: {
          2: [favVideo(1), favVideo(2)],
        },
      );
      final folders = model(api);
      await folders.start();
      folders.wantPreview(folders.folders.first);
      await pumpEventQueue();
      await api.removeEverywhere(aid: 7001);
      folders.removedEverywhere(7001);
      expect(folders.stale, isTrue);
      api.calls.clear();
      await folders.refreshIfStale();
      expect(api.calls, ['folders mid=12345']);
      expect(folders.folders.first.count, 1);
      expect([for (final video in (folders.preview(2)! as PreviewReady).videos) video.aid], [7002]);
      await folders.refreshIfStale();
      expect(api.calls, hasLength(1));
    });
  });
}
