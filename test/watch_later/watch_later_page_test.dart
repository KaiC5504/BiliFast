import 'package:bili_core/api.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/favourites/new_folder_page.dart';
import 'package:bilifast/home/feed_model.dart' show requestFailureMessage;
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:bilifast/watch_later/fake_watch_later_api.dart';
import 'package:bilifast/watch_later/watch_later_glyphs.dart';
import 'package:bilifast/watch_later/watch_later_model.dart';
import 'package:bilifast/watch_later/watch_later_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../home/fake_login_gate.dart';
import '../search/results/results_support.dart';
import 'watch_later_fakes.dart';

void main() {
  late FakeWatchLaterApi api;
  late FakeLoginGate gate;
  late AppServices services;
  late List<VideoRoute> opened;

  Future<void> show(
    WidgetTester tester, {
    List<WatchLaterItem>? items,
    bool loggedIn = true,
    Object? listFailure,
  }) async {
    api = FakeWatchLaterApi(items: items ?? laterItems(3), folderList: testFolders);
    if (listFailure != null) api.failures['list'] = listFailure;
    gate = FakeLoginGate();
    opened = [];
    services =
        await tester.runAsync(() => resultServices(loggedIn: loggedIn, api: FakePageApi(), gate: gate)) as AppServices;
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, page) => AppScope(services: services, child: page!),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => WatchLaterPage(api: api, open: (_, route) => opened.add(route)),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester, 20);
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await settle(tester, 20);
  }

  bool editing(WidgetTester tester) => find.text('取消管理').evaluate().isNotEmpty;

  testWidgets('a list shows each row’s progress, title and counts, and ends with the note', (tester) async {
    await show(tester, items: [laterItem(1, progress: 1, duration: 412), laterItem(2, progress: -1)]);
    expect(api.calls, ['list all newest page=1']);
    expect(find.text('00:01 / 06:52'), findsOneWidget);
    expect(find.text('已看完'), findsOneWidget);
    expect(find.text('测试视频 1'), findsOneWidget);
    expect(find.text('测试UP1'), findsOneWidget);
    expect(find.text(WatchLaterPage.note), findsOneWidget);
    expect(find.byType(EmptyTvArt), findsNothing);
  });

  testWidgets('a row opens its video at its progress', (tester) async {
    await show(tester, items: [laterItem(1, progress: 95)]);
    await tap(tester, 'later-open-BV1test1');
    expect(opened.single.bvid, 'BV1test1');
    expect(opened.single.start, 95);
  });

  testWidgets('an empty list shows the TV and its words; 管理, the sort and 播放全部 do nothing', (tester) async {
    await show(tester, items: const []);
    expect(find.byType(EmptyTvArt), findsOneWidget);
    expect(find.text(WatchLaterPage.emptyMessage), findsOneWidget);
    expect(find.text(WatchLaterPage.note), findsNothing);
    await tap(tester, 'later-manage');
    await tap(tester, 'later-sort');
    await tap(tester, 'later-play-all');
    expect(find.byKey(const ValueKey('later-manage-sheet')), findsNothing);
    expect(opened, isEmpty);
    expect(api.calls, ['list all newest page=1']);
  });

  testWidgets('the chips list with their filter', (tester) async {
    await show(tester, items: [laterItem(1, progress: -1), laterItem(2)]);
    await tap(tester, 'later-chip-unfinished');
    expect(api.calls.last, 'list unfinished newest page=1');
    expect(find.text('测试视频 1'), findsNothing);
    await tap(tester, 'later-chip-all');
    expect(api.calls.last, 'list all newest page=1');
    expect(find.text('测试视频 1'), findsOneWidget);
  });

  testWidgets('the sort turns 最近添加 into 最早添加, and 播放全部 opens the first in that order', (tester) async {
    await show(tester);
    expect(find.text('最近添加'), findsOneWidget);
    await tap(tester, 'later-play-all');
    expect(opened.last.bvid, 'BV1test1');
    await tap(tester, 'later-sort');
    expect(api.calls.last, 'list all oldest page=1');
    expect(find.text('最早添加'), findsOneWidget);
    await tap(tester, 'later-play-all');
    expect(opened.last.bvid, 'BV1test3');
  });

  testWidgets('scrolling near the end asks for the next page', (tester) async {
    await show(tester, items: laterItems(23));
    expect(api.calls, ['list all newest page=1']);
    await tester.drag(find.byKey(const ValueKey('later-list')), const Offset(0, -1500));
    await settle(tester, 20);
    expect(api.calls.last, 'list all newest page=2');
    expect(find.text('测试视频 23'), findsOneWidget);
    await tester.drag(find.byKey(const ValueKey('later-list')), const Offset(0, -3000));
    await settle(tester, 20);
    expect(find.byKey(const ValueKey('later-note')), findsOneWidget);
    expect(api.calls.length, 2, reason: 'the end asks nothing more');
  });

  testWidgets('管理 opens its sheet; 一键清除已看完视频 clears them and lists again', (tester) async {
    await show(tester, items: [laterItem(1, progress: -1), laterItem(2)]);
    await tap(tester, 'later-manage');
    for (final label in ['一键清除已看完视频', '一键清除已失效视频', '批量管理']) {
      expect(find.text(label), findsOneWidget);
    }
    await tap(tester, 'later-action-一键清除已看完视频');
    expect(api.calls.sublist(1), ['clear watched', 'list all newest page=1']);
    expect(find.byKey(const ValueKey('later-manage-sheet')), findsNothing);
    expect(find.text('测试视频 1'), findsNothing);
  });

  testWidgets('一键清除已失效视频 sends its kind; a failure toasts why', (tester) async {
    await show(tester);
    api.failures['clear'] = const BiliError.http(502);
    await tap(tester, 'later-manage');
    await tap(tester, 'later-action-一键清除已失效视频');
    expect(api.calls.last, 'clear invalid');
    expect(find.text(requestFailureMessage(const BiliError.http(502))), findsOneWidget);
    await toastGone(tester);
  });

  testWidgets('a tap on the dim or back closes a sheet first', (tester) async {
    await show(tester);
    await tap(tester, 'later-manage');
    await tap(tester, 'later-sheet-dim');
    expect(find.byKey(const ValueKey('later-manage-sheet')), findsNothing);
    await tap(tester, 'later-manage');
    await tester.binding.handlePopRoute();
    await settle(tester, 20);
    expect(find.byKey(const ValueKey('later-manage-sheet')), findsNothing);
    expect(find.byType(WatchLaterPage), findsOneWidget);
  });

  testWidgets('⋮’s 删除 takes the row off and posts it', (tester) async {
    await show(tester);
    await tap(tester, 'later-more-BV1test2');
    expect(find.byKey(const ValueKey('later-row-sheet')), findsOneWidget);
    await tap(tester, 'later-action-删除');
    expect(api.calls.last, 'remove 83000002');
    expect(find.text('测试视频 2'), findsNothing);
  });

  testWidgets('a 删除 that fails brings the row back and toasts why', (tester) async {
    await show(tester);
    api.failures['remove'] = const BiliError.api(code: -400, message: '请求错误');
    await tap(tester, 'later-more-BV1test2');
    await tap(tester, 'later-action-删除');
    expect(find.text('测试视频 2'), findsOneWidget);
    expect(find.text(requestFailureMessage(api.failures['remove']!)), findsOneWidget);
    await toastGone(tester);
  });

  testWidgets('批量管理: rows choose instead of opening, the bar counts them, and 删除 sends them at once', (tester) async {
    await show(tester);
    await tap(tester, 'later-manage');
    await tap(tester, 'later-action-批量管理');
    expect(editing(tester), isTrue);
    expect(find.byKey(const ValueKey('later-more-BV1test1')), findsNothing);
    expect(find.byType(ChoiceCircle), findsNWidgets(4), reason: 'one a row and 全选');
    expect(find.text('取消选择'), findsOneWidget);
    await tap(tester, 'later-edit-delete');
    expect(api.calls.length, 1, reason: 'nothing chosen does nothing');

    await tap(tester, 'later-open-BV1test1');
    expect(opened, isEmpty);
    expect(find.text('取消选择 (1)'), findsOneWidget);
    await tap(tester, 'later-edit-all');
    expect(find.text('取消选择 (3)'), findsOneWidget);
    await tap(tester, 'later-edit-clear');
    expect(find.text('取消选择'), findsOneWidget);
    await tap(tester, 'later-open-BV1test1');
    await tap(tester, 'later-open-BV1test3');
    await tap(tester, 'later-edit-delete');
    expect(api.calls.last, 'remove 83000001,83000003');
    expect(editing(tester), isFalse);
    expect(find.text('测试视频 2'), findsOneWidget);
    expect(find.text('测试视频 1'), findsNothing);
  });

  testWidgets('取消管理 and back leave the edit mode', (tester) async {
    await show(tester);
    await tap(tester, 'later-manage');
    await tap(tester, 'later-action-批量管理');
    await tap(tester, 'later-manage');
    expect(editing(tester), isFalse);
    await tap(tester, 'later-manage');
    await tap(tester, 'later-action-批量管理');
    await tap(tester, 'later-back');
    expect(editing(tester), isFalse);
    expect(find.byType(WatchLaterPage), findsOneWidget);
    await tap(tester, 'later-back');
    expect(find.byType(WatchLaterPage), findsNothing);
  });

  Future<void> chooseFirst(WidgetTester tester) async {
    await tap(tester, 'later-manage');
    await tap(tester, 'later-action-批量管理');
    await tap(tester, 'later-open-BV1test1');
  }

  testWidgets('复制到 lists the folders; one copies there, closes, ends the edit mode and toasts', (tester) async {
    await show(tester);
    await chooseFirst(tester);
    await tap(tester, 'later-edit-copy');
    expect(api.calls.last, startsWith('folders mid='));
    expect(find.text('选择收藏夹'), findsOneWidget);
    expect(find.text('公开 · 0个内容'), findsOneWidget);
    expect(find.text('私密 · 8个内容'), findsOneWidget);
    await tap(tester, 'later-folder-9102');
    expect(api.calls.where((call) => call.startsWith('copy')).single, startsWith('copy 83000001 to=9102 mid='));
    expect(find.text('选择收藏夹'), findsNothing);
    expect(editing(tester), isFalse);
    expect(api.calls.last, 'list all newest page=1');
    expect(find.text(WatchLaterModel.copied), findsOneWidget);
    expect(find.text('测试视频 1'), findsOneWidget);
    await toastGone(tester);
  });

  testWidgets('移动到 moves the chosen videos out of 稍后再看', (tester) async {
    await show(tester);
    await chooseFirst(tester);
    await tap(tester, 'later-edit-move');
    await tap(tester, 'later-folder-9101');
    expect(api.calls.where((call) => call.startsWith('move')).single, 'move 83000001 to=9101');
    expect(find.text(WatchLaterModel.moved), findsOneWidget);
    expect(find.text('测试视频 1'), findsNothing);
    await toastGone(tester);
  });

  testWidgets('a move that fails toasts why and keeps the edit mode', (tester) async {
    await show(tester);
    api.failures['moveToFolder'] = const BiliError.api(code: 11010, message: '收藏夹已满');
    await chooseFirst(tester);
    await tap(tester, 'later-edit-move');
    await tap(tester, 'later-folder-9101');
    expect(find.text(requestFailureMessage(api.failures['moveToFolder']!)), findsOneWidget);
    expect(editing(tester), isTrue);
    await toastGone(tester);
  });

  testWidgets('a 复制到 refused with -101 turns the page to its login state, with no toast', (tester) async {
    await show(tester);
    api.failures['copyToFolder'] = const BiliError.api(code: -101, message: '账号未登录');
    await chooseFirst(tester);
    await tap(tester, 'later-edit-copy');
    await tap(tester, 'later-folder-9102');
    expect(find.text(requestFailureMessage(api.failures['copyToFolder']!)), findsNothing);
    expect(find.text('选择收藏夹'), findsNothing);
    expect(find.text(WatchLaterPage.loggedOutMessage), findsOneWidget);
    expect(editing(tester), isFalse);
  });

  testWidgets('+ 新建收藏夹 opens 创建, which makes the folder; the folder joins the list after the default one', (
    tester,
  ) async {
    await show(tester);
    await chooseFirst(tester);
    await tap(tester, 'later-edit-copy');
    await tap(tester, 'later-new-folder');
    final page = tester.widget<NewFolderPage>(find.byType(NewFolderPage));
    final folder = await page.create(title: '新的收藏夹', intro: '简介', isPrivate: true);
    expect(api.calls.last, 'createFolder title=新的收藏夹 intro=简介 private=true cover=');
    Navigator.of(tester.element(find.byType(NewFolderPage))).pop(folder);
    await settle(tester, 20);
    expect(find.byType(NewFolderPage), findsNothing);
    expect(find.text('选择收藏夹'), findsOneWidget);
    final rows = [
      for (final id in [9101, folder.id, 9102]) tester.getTopLeft(find.byKey(ValueKey('later-folder-$id'))).dy,
    ];
    expect(rows, orderedEquals([...rows]..sort()));
    expect(api.calls.where((call) => call.startsWith('folders')).length, 1, reason: 'the list isn’t asked again');
    await tap(tester, 'later-folder-${folder.id}');
    expect(api.calls.where((call) => call.startsWith('copy')).single, startsWith('copy 83000001 to=${folder.id} '));
    await toastGone(tester);
  });

  testWidgets('the edit bar is in the semantics tree only while it shows', (tester) async {
    final handle = tester.ensureSemantics();
    bool listed(String label) => tester.semantics.simulatedAccessibilityTraversal().any((node) => node.label == label);
    await show(tester);
    expect(listed('全选'), isFalse);
    expect(listed('移动到'), isFalse);
    await tap(tester, 'later-manage');
    await tap(tester, 'later-action-批量管理');
    expect(listed('全选'), isTrue);
    await tap(tester, 'later-manage');
    expect(listed('全选'), isFalse);
    handle.dispose();
  });

  testWidgets('logged out asks nothing and offers the login page', (tester) async {
    await show(tester, loggedIn: false);
    expect(api.calls, isEmpty);
    expect(find.text(WatchLaterPage.loggedOutMessage), findsOneWidget);
    await tap(tester, 'later-login');
    expect(gate.requests, 1);
  });

  testWidgets('a failed first page offers 重试, which lists again', (tester) async {
    await show(tester, listFailure: const BiliError.http(500));
    expect(find.byKey(const ValueKey('later-failed')), findsOneWidget);
    api.failures.clear();
    await tap(tester, 'later-retry');
    expect(api.calls, ['list all newest page=1', 'list all newest page=1']);
    expect(find.text('测试视频 1'), findsOneWidget);
  });

  testWidgets('a failed pull keeps the rows and toasts why', (tester) async {
    await show(tester);
    api.failures['list'] = const BiliError.http(500);
    await tester.drag(find.byKey(const ValueKey('later-list')), const Offset(0, 300));
    await settle(tester, 40);
    // A failed pull keeps the rows and toasts.
    expect(find.text('测试视频 1'), findsOneWidget);
    await toastGone(tester);
  });

  testWidgets('every control answers an accessibility press', (tester) async {
    final handle = tester.ensureSemantics();
    await show(tester);
    final node = tester.getSemantics(find.byKey(const ValueKey('later-manage')));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    for (final key in ['later-sort', 'later-play-all', 'later-chip-unfinished', 'later-more-BV1test1']) {
      final data = tester.getSemantics(find.byKey(ValueKey(key))).getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue, reason: key);
    }
    handle.dispose();
  });
}
