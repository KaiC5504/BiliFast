import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/favourites/fake_favourites_api.dart';
import 'package:bilifast/favourites/favourites_page.dart';
import 'package:bilifast/favourites/folder_page.dart';
import 'package:bilifast/favourites/new_folder_page.dart';
import 'package:bilifast/shared/loading_tv.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../home/fake_login_gate.dart';
import 'favourites_support.dart';

void main() {
  late List<VideoRoute> opened;
  late List<Uri> shared;
  late FakeLoginGate gate;

  setUp(() {
    opened = [];
    shared = [];
    gate = FakeLoginGate();
    favouritesLayout = FavouritesLayout.cards;
  });

  FakeFavouritesApi demo() => FakeFavouritesApi(
    folders: [
      favFolder(1, '默认收藏夹', isDefault: true),
      favFolder(2, '私密的', count: 25, private: true),
      favFolder(3, '公开的', count: 2),
    ],
    contents: {
      1: const [],
      2: [for (var i = 0; i < 25; i++) favVideo(i, title: '私密视频 $i')],
      3: [favVideo(100, title: '公开视频 一'), favVideo(101, title: '公开视频 二')],
    },
  );

  Future<AppServices> show(WidgetTester tester, Widget page, FakeFavouritesApi api, {bool loggedIn = true}) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    final services = await favouritesServices(loggedIn: loggedIn, api: api, gate: gate);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppScope(services: services, child: child!),
        home: page,
      ),
    );
    await settle(tester);
    return services;
  }

  Widget favourites(FakeFavouritesApi api) => FavouritesPage(
    api: api,
    loginGate: gate,
    share: (link) async {
      shared.add(link);
      return true;
    },
    open: (context, route) => opened.add(route),
  );

  Widget folderPage(FakeFavouritesApi api, FavFolder folder) => FolderPage(
    folder: folder,
    api: api,
    loginGate: gate,
    share: (link) async {
      shared.add(link);
      return true;
    },
    open: (context, route) => opened.add(route),
  );

  Future<void> expectSoon(WidgetTester tester, Finder control) async {
    await tester.tap(control);
    await tester.pump();
    expect(find.text('暂未开放'), findsOneWidget, reason: '$control');
    await toastGone(tester);
  }

  group('收藏夹 (80)', () {
    testWidgets('one card per folder, with its count, a lock only when private, and covers only for full ones', (
      tester,
    ) async {
      final api = demo();
      await show(tester, favourites(api), api);
      expect(find.byKey(const ValueKey('fav-folder-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('fav-folder-2')), findsOneWidget);
      expect(find.text('0个内容'), findsOneWidget);
      expect(find.text('25个内容'), findsOneWidget);
      expect(find.text('2个内容'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('fav-folder-2')),
          matching: find.byKey(const ValueKey('fav-card-lock')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('fav-folder-3')),
          matching: find.byKey(const ValueKey('fav-card-lock')),
        ),
        findsNothing,
      );
      expect(find.text('私密视频 0'), findsOneWidget);
      expect(find.text('私密视频 2'), findsOneWidget);
      expect(find.text('私密视频 3'), findsNothing, reason: 'three covers at most');
      expect(find.text('公开视频 二'), findsOneWidget);
      // The empty default folder asks for no covers, so its card is shorter: no titles row.
      expect(api.calls, [
        'folders mid=12345',
        'folderVideos folder=2 page=1 size=3',
        'folderVideos folder=3 page=1 size=3',
      ]);
      expect(
        tester.getSize(find.byKey(const ValueKey('fav-folder-1'))).height,
        lessThan(tester.getSize(find.byKey(const ValueKey('fav-folder-2'))).height),
      );
      expect(find.byKey(const ValueKey('fav-new-folder')), findsOneWidget);
    });

    testWidgets('only cards on screen ask for their covers', (tester) async {
      final api = FakeFavouritesApi(
        folders: [for (var i = 1; i <= 12; i++) favFolder(i, '收藏夹 $i', count: 1)],
        contents: {
          for (var i = 1; i <= 12; i++) i: [favVideo(i)],
        },
      );
      await show(tester, favourites(api), api);
      final asked = api.calls.where((call) => call.startsWith('folderVideos')).length;
      expect(asked, lessThan(12));
      expect(asked, greaterThan(0));
    });

    testWidgets('追更 and 🔍 say 暂未开放', (tester) async {
      final api = demo();
      await show(tester, favourites(api), api);
      await expectSoon(tester, find.byKey(const ValueKey('fav-tab-following')));
      await expectSoon(tester, find.byKey(const ValueKey('fav-tool-search')));
    });

    testWidgets('a card opens its folder; a removal there follows back to the card', (tester) async {
      final api = demo();
      await show(tester, favourites(api), api);
      await tester.tap(find.byKey(const ValueKey('fav-folder-3')));
      await settle(tester, 20);
      expect(find.byType(FolderPage), findsOneWidget);
      expect(find.text('2 个内容'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('fav-folder-more-7100')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('fav-sheet-remove')));
      await settle(tester);
      expect(find.text('1 个内容'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('fav-folder-back')));
      await settle(tester, 20);
      expect(find.text('1个内容'), findsOneWidget);
      expect(find.text('公开视频 一'), findsNothing);
    });

    testWidgets('logged out the page asks for a login, which loads it', (tester) async {
      final api = demo();
      await show(tester, favourites(api), api, loggedIn: false);
      expect(find.byKey(const ValueKey('fav-folders-logged-out')), findsOneWidget);
      expect(api.calls, isEmpty);
      await tester.tap(find.byKey(const ValueKey('fav-folders-login')));
      await settle(tester);
      expect(gate.requests, 1);
    });

    testWidgets('the first load shows the TV; a failure shows why with 重试', (tester) async {
      final api = demo();
      final hold = api.holds['folders'] = Completer<void>();
      await show(tester, favourites(api), api);
      expect(find.byKey(const ValueKey('fav-folders-loading')), findsOneWidget);
      expect(find.byType(LoadingTvState), findsOneWidget);
      api.failures['folders'] = const BiliError.http(500);
      hold.complete();
      await settle(tester);
      expect(find.text('网络请求失败（HTTP 500）'), findsOneWidget);
      api.failures.clear();
      await tester.tap(find.byKey(const ValueKey('fav-folders-retry')));
      await settle(tester);
      expect(find.byKey(const ValueKey('fav-folder-2')), findsOneWidget);
    });
  });

  group('the list layout (99)', () {
    testWidgets('the toggle turns the cards into the list and back, its glyph following', (tester) async {
      final api = demo();
      await show(tester, favourites(api), api);
      expect(find.byKey(const ValueKey('fav-layout-cards')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('fav-tool-layout')));
      await settle(tester);
      expect(find.byKey(const ValueKey('fav-layout-list')), findsOneWidget);
      expect(find.text('私密视频 0'), findsNothing, reason: 'no cover titles in the list');
      expect(find.text('25个内容'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('fav-folder-2')),
          matching: find.byKey(const ValueKey('fav-row-lock')),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('fav-play-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('fav-play-1')), findsNothing, reason: 'an empty folder’s 播放 is pale');
      await tester.tap(find.byKey(const ValueKey('fav-tool-layout')));
      await settle(tester);
      expect(find.byKey(const ValueKey('fav-layout-cards')), findsOneWidget);
      expect(find.text('私密视频 0'), findsOneWidget);
    });

    testWidgets('the list asks only for the folders, covers included', (tester) async {
      favouritesLayout = FavouritesLayout.list;
      final api = FakeFavouritesApi(
        folders: [favFolder(1, '默认收藏夹', isDefault: true), favFolder(2, '有封面', count: 1)],
        contents: {
          1: const [],
          2: [favVideo(1, cover: 'https://i0.hdslb.com/bfs/archive/test.jpg')],
        },
      );
      await show(tester, favourites(api), api);
      expect(api.calls, ['folders mid=12345']);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('fav-folder-2')),
          matching: find.byKey(const ValueKey('fav-row-cover')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('fav-folder-1')),
          matching: find.byKey(const ValueKey('fav-row-cover')),
        ),
        findsNothing,
      );
    });

    testWidgets('the choice holds for the next 我的收藏 while the app runs', (tester) async {
      final api = demo();
      await show(tester, favourites(api), api);
      await tester.tap(find.byKey(const ValueKey('fav-tool-layout')));
      await settle(tester);
      await tester.pumpWidget(const SizedBox());
      await show(tester, favourites(api), api);
      expect(find.byKey(const ValueKey('fav-layout-list')), findsOneWidget);
    });

    testWidgets('播放 opens the folder’s newest video; a card opens the folder', (tester) async {
      favouritesLayout = FavouritesLayout.list;
      final api = demo();
      await show(tester, favourites(api), api);
      await tester.tap(find.byKey(const ValueKey('fav-play-3')));
      await settle(tester);
      expect(opened.single.bvid, bvidOf(7100));
      expect(api.calls.last, 'folderVideos folder=3 page=1 size=3');
      await tester.tap(find.byKey(const ValueKey('fav-folder-3')));
      await settle(tester, 20);
      expect(find.byType(FolderPage), findsOneWidget);
    });

    testWidgets('a refused 播放 says why', (tester) async {
      favouritesLayout = FavouritesLayout.list;
      final api = demo()..failures['folderVideos'] = const BiliError.http(500);
      await show(tester, favourites(api), api);
      await tester.tap(find.byKey(const ValueKey('fav-play-2')));
      await tester.pump();
      await tester.pump();
      expect(find.text('网络请求失败（HTTP 500）'), findsOneWidget);
      expect(opened, isEmpty);
      await toastGone(tester);
    });
  });

  group('创建 from 我的收藏 (100)', () {
    Future<void> create(WidgetTester tester, String name) async {
      expect(find.byType(NewFolderPage), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('fav-new-title')), name);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('fav-new-done')));
      await settle(tester, 20);
    }

    testWidgets('+ opens 创建, and the folder made joins the list after the default one without a reload', (
      tester,
    ) async {
      final api = demo();
      await show(tester, favourites(api), api);
      await tester.tap(find.byKey(const ValueKey('fav-tool-new')));
      await settle(tester, 20);
      await create(tester, '新的收藏夹');
      expect(find.byType(NewFolderPage), findsNothing);
      expect(api.calls.where((call) => call.startsWith('folders')), hasLength(1));
      expect(api.calls, contains('createFolder title=新的收藏夹 intro= private=false cover='));
      final made = api.folderList[1];
      expect(made.title, '新的收藏夹');
      expect(
        tester.getTopLeft(find.byKey(ValueKey('fav-folder-${made.id}'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('fav-folder-2'))).dy),
      );
      expect(
        tester.getTopLeft(find.byKey(ValueKey('fav-folder-${made.id}'))).dy,
        greaterThan(tester.getTopLeft(find.byKey(const ValueKey('fav-folder-1'))).dy),
      );
    });

    testWidgets('+ 新建收藏夹 under the folders opens 创建 too, and backing out makes nothing', (tester) async {
      final api = demo();
      await show(tester, favourites(api), api);
      await tester.tap(find.byKey(const ValueKey('fav-new-folder')));
      await settle(tester, 20);
      expect(find.byType(NewFolderPage), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('fav-new-back')));
      await settle(tester, 20);
      expect(find.byType(NewFolderPage), findsNothing);
      expect(api.calls.where((call) => call.startsWith('createFolder')), isEmpty);
    });

    testWidgets('logged out, + asks for the login instead', (tester) async {
      final api = demo();
      await show(tester, favourites(api), api, loggedIn: false);
      await tester.tap(find.byKey(const ValueKey('fav-tool-new')));
      await settle(tester);
      expect(gate.requests, 1);
      expect(find.byType(NewFolderPage), findsNothing);
    });
  });

  group('视频 (83, 84)', () {
    testWidgets('the chip lists every favourite once and ends with 84’s note', (tester) async {
      final api = demo();
      await show(tester, favourites(api), api);
      await tester.tap(find.byKey(const ValueKey('fav-chip-videos')));
      await settle(tester);
      expect(find.byKey(const ValueKey('fav-tool-layout')), findsNothing);
      expect(find.byKey(const ValueKey('fav-videos-row-7000')), findsOneWidget);
      expect(find.byKey(const ValueKey('fav-videos-progress-7000')), findsOneWidget, reason: '视频 gives progress');
      final list = tester.state<ScrollableState>(
        find.descendant(of: find.byKey(const ValueKey('fav-videos-list')), matching: find.byType(Scrollable)),
      );
      for (var i = 0; i < 5 && find.byKey(const ValueKey('fav-videos-end')).evaluate().isEmpty; i++) {
        list.position.jumpTo(list.position.maxScrollExtent);
        await settle(tester);
      }
      expect(find.text('仅展示本App中可查看的稿件'), findsOneWidget);
      expect(api.calls.where((call) => call.startsWith('allVideos')), hasLength(2), reason: '27 videos, 20 a page');
      expect(api.calls.where((call) => call == 'videosTab'), hasLength(1));
    });

    testWidgets('🔍 and multi-select say 暂未开放', (tester) async {
      final api = demo();
      await show(tester, favourites(api), api);
      await tester.tap(find.byKey(const ValueKey('fav-chip-videos')));
      await settle(tester);
      await expectSoon(tester, find.byKey(const ValueKey('fav-tool-search')));
      await expectSoon(tester, find.byKey(const ValueKey('fav-tool-select')));
    });

    testWidgets('a row opens its video to resume; ⋮ → 取消收藏 takes it out of every folder', (tester) async {
      final api = demo();
      await show(tester, favourites(api), api);
      await tester.tap(find.byKey(const ValueKey('fav-chip-videos')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('fav-videos-row-7000')));
      expect(opened.single.bvid, bvidOf(7000));
      expect(opened.single.start, isNull);
      await tester.tap(find.byKey(const ValueKey('fav-videos-more-7000')));
      await settle(tester);
      expect(find.byKey(const ValueKey('fav-sheet')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('fav-sheet-remove')));
      await settle(tester);
      expect(find.byKey(const ValueKey('fav-videos-row-7000')), findsNothing);
      expect(api.calls.last, 'removeEverywhere aid=7000');
      // Back on 收藏夹 the counts are asked again.
      await tester.tap(find.byKey(const ValueKey('fav-chip-folders')));
      await settle(tester);
      expect(find.text('24个内容'), findsOneWidget);
    });

    testWidgets('a refused 取消收藏 brings the row back with a toast', (tester) async {
      final api = demo()..failures['removeEverywhere'] = const BiliError.http(500);
      await show(tester, favourites(api), api);
      await tester.tap(find.byKey(const ValueKey('fav-chip-videos')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('fav-videos-more-7000')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('fav-sheet-remove')));
      await tester.pump();
      await tester.pump();
      expect(find.text('取消收藏失败，请稍后重试'), findsOneWidget);
      await settle(tester);
      expect(find.byKey(const ValueKey('fav-videos-row-7000')), findsOneWidget);
      await toastGone(tester);
    });
  });

  group('a folder (81, 82)', () {
    testWidgets('the header, 20 rows a page to the end note, and a row opens its video', (tester) async {
      final api = demo();
      await show(tester, folderPage(api, favFolder(2, '私密的', count: 25, private: true)), api);
      expect(find.text('私密的'), findsOneWidget);
      expect(find.text('创建者：测试账号'), findsOneWidget);
      expect(find.text('25 个内容'), findsOneWidget);
      expect(find.byKey(const ValueKey('fav-folder-progress-7000')), findsNothing, reason: 'the web list gives none');
      expect(find.text('00:11'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('fav-folder-row-7001')));
      expect(opened.single.bvid, bvidOf(7001));
      final list = tester.state<ScrollableState>(
        find.descendant(of: find.byKey(const ValueKey('fav-folder-list')), matching: find.byType(Scrollable)),
      );
      for (var i = 0; i < 5 && find.byKey(const ValueKey('fav-folder-end')).evaluate().isEmpty; i++) {
        list.position.jumpTo(list.position.maxScrollExtent);
        await settle(tester);
      }
      expect(find.text('仅展示本App中可查看的稿件'), findsOneWidget);
      expect(api.calls, ['folderVideos folder=2 page=1 size=20', 'folderVideos folder=2 page=2 size=20']);
    });

    testWidgets('loading more shows the small spinner', (tester) async {
      final api = demo();
      final first = api.holds['folderVideos'] = Completer<void>();
      await show(tester, folderPage(api, favFolder(2, '私密的', count: 25, private: true)), api);
      final second = api.holds['folderVideos'] = Completer<void>();
      first.complete();
      await settle(tester);
      final list = tester.state<ScrollableState>(
        find.descendant(of: find.byKey(const ValueKey('fav-folder-list')), matching: find.byType(Scrollable)),
      );
      list.position.jumpTo(list.position.maxScrollExtent);
      await settle(tester);
      expect(api.calls.last, 'folderVideos folder=2 page=2 size=20');
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.byType(LoadingTvState), findsNothing);
      second.complete();
      await settle(tester);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    });

    testWidgets('an empty folder says so', (tester) async {
      final api = demo();
      await show(tester, folderPage(api, favFolder(1, '默认收藏夹', isDefault: true)), api);
      expect(find.text('0 个内容'), findsOneWidget);
      expect(find.byKey(const ValueKey('fav-folder-empty')), findsOneWidget);
    });

    testWidgets('🔍, multi-select, ⋮, 点赞 and 收藏 say 暂未开放; 分享 shares the folder’s link', (tester) async {
      final api = demo();
      await show(tester, folderPage(api, favFolder(3, '公开的', count: 2)), api);
      for (final key in [
        'fav-folder-search',
        'fav-folder-select',
        'fav-folder-more',
        'fav-folder-like',
        'fav-folder-favourite',
      ]) {
        await expectSoon(tester, find.byKey(ValueKey(key)));
      }
      await tester.tap(find.byKey(const ValueKey('fav-folder-share')));
      await settle(tester);
      expect(shared, [Uri.parse('https://www.bilibili.com/medialist/detail/ml3')]);
    });

    testWidgets('82: ⋮ opens 取消收藏 and 取消; 取消 and the dim close it without a call', (tester) async {
      final api = demo();
      await show(tester, folderPage(api, favFolder(3, '公开的', count: 2)), api);
      await tester.tap(find.byKey(const ValueKey('fav-folder-more-7100')));
      await settle(tester);
      expect(find.text('取消收藏'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('fav-sheet-cancel')));
      await settle(tester);
      expect(find.byKey(const ValueKey('fav-sheet')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('fav-folder-more-7100')));
      await settle(tester);
      await tester.tapAt(const Offset(220, 300));
      await settle(tester);
      expect(find.byKey(const ValueKey('fav-sheet')), findsNothing);
      expect(api.calls.where((call) => call.startsWith('remove')), isEmpty);
    });

    testWidgets('取消收藏 takes the row off and the count with it; a refusal brings both back with a toast', (
      tester,
    ) async {
      final api = demo();
      await show(tester, folderPage(api, favFolder(3, '公开的', count: 2)), api);
      await tester.tap(find.byKey(const ValueKey('fav-folder-more-7100')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('fav-sheet-remove')));
      await settle(tester);
      expect(find.byKey(const ValueKey('fav-folder-row-7100')), findsNothing);
      expect(find.text('1 个内容'), findsOneWidget);
      expect(api.calls.last, 'removeFromFolder folder=3 aid=7100');

      api.failures['removeFromFolder'] = const BiliError.http(500);
      await tester.tap(find.byKey(const ValueKey('fav-folder-more-7101')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('fav-sheet-remove')));
      await tester.pump();
      await tester.pump();
      expect(find.text('取消收藏失败，请稍后重试'), findsOneWidget);
      await settle(tester);
      expect(find.byKey(const ValueKey('fav-folder-row-7101')), findsOneWidget);
      expect(find.text('1 个内容'), findsOneWidget);
      await toastGone(tester);
    });

    testWidgets('a -101 turns the page to its login', (tester) async {
      final api = demo()..failures['folderVideos'] = const BiliError.api(code: -101, message: '账号未登录');
      await show(tester, folderPage(api, favFolder(3, '公开的', count: 2)), api);
      expect(find.byKey(const ValueKey('fav-folder-logged-out')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('fav-folder-login')));
      await settle(tester);
      expect(gate.requests, 1);
    });
  });
}
