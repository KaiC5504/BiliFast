import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bilifast/home/hot/hot_api.dart';
import 'package:bilifast/home/hot/hot_list.dart';
import 'package:bilifast/home/hot/hot_row.dart';
import 'package:bilifast/shared/loading_tv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'hot_support.dart';

void main() {
  final list = find.byKey(const ValueKey('hot-list'));

  Future<HotHarness> show(WidgetTester tester, {FakeHotApi? api, bool active = true}) async {
    final harness = HotHarness(api: api)..active.value = active;
    await pumpHot(tester, await hotServices(), harness.list());
    await settle(tester);
    return harness;
  }

  ScrollPosition position(WidgetTester tester) => tester.state<ScrollableState>(find.byType(Scrollable).first).position;

  Future<void> pull(WidgetTester tester) async {
    final gesture = await tester.startGesture(tester.getTopLeft(list) + const Offset(220, 200));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(0, 15));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
  }

  testWidgets('nothing is asked until the page first shows; then the TV until the first page, then its rows', (
    tester,
  ) async {
    final api = FakeHotApi(videos: hotVideos(40));
    final hold = api.holds['page'] = Completer<void>();
    final harness = await show(tester, api: api, active: false);
    expect(api.calls, isEmpty);
    expect(find.byType(LoadingTvState), findsNothing);

    harness.active.value = true;
    await settle(tester);
    expect(api.calls, ['page=1']);
    expect(find.byType(LoadingTvState), findsOneWidget);

    hold.complete();
    api.holds.clear();
    await settle(tester);
    expect(find.byType(LoadingTvState), findsNothing);
    expect(find.byType(HotRow), findsWidgets);
    expect(find.text('测试热门视频 0'), findsOneWidget);
    expect(find.text('183.1万播放 · 22小时前', findRichText: true), findsWidgets);

    harness.active.value = false;
    await settle(tester);
    harness.active.value = true;
    await settle(tester);
    expect(api.calls, ['page=1'], reason: 'loaded once');
  });

  testWidgets('near the end the next page is asked once, the small spinner under the rows; the end says so', (
    tester,
  ) async {
    final api = FakeHotApi(videos: hotVideos(40));
    await show(tester, api: api);
    final hold = api.holds['page=2'] = Completer<void>();
    await tester.drag(list, const Offset(0, -1500));
    await settle(tester);
    expect(api.calls, ['page=1', 'page=2']);
    expect(find.byKey(const ValueKey('hot-more-spinner')), findsOneWidget);

    await tester.drag(list, const Offset(0, -50));
    await settle(tester);
    expect(api.calls, ['page=1', 'page=2'], reason: 'one call out at a time');

    hold.complete();
    await settle(tester);
    await tester.drag(list, const Offset(0, -4000));
    await settle(tester);
    expect(find.text('测试热门视频 39'), findsOneWidget);
    expect(find.byKey(const ValueKey('hot-end')), findsOneWidget);
    expect(api.calls, ['page=1', 'page=2']);
  });

  testWidgets('a pull refreshes on release, nothing while held; a failure over the rows keeps them and says why', (
    tester,
  ) async {
    final api = FakeHotApi(videos: hotVideos(40));
    await show(tester, api: api);

    final gesture = await tester.startGesture(tester.getTopLeft(list) + const Offset(220, 200));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(0, 15));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(api.calls, ['page=1'], reason: 'nothing while held');
    await gesture.up();
    await settle(tester, 30);
    expect(api.calls, ['page=1', 'page=1']);

    api.failures['page'] = const BiliError.api(code: -500, message: '服务器错误');
    await pull(tester);
    await settle(tester, 4);
    expect(find.text('B 站返回错误 -500：服务器错误'), findsOneWidget, reason: 'a toast');
    expect(find.text('测试热门视频 0'), findsOneWidget, reason: 'kept');
    expect(find.byKey(const ValueKey('hot-error')), findsNothing);
    await toastGone(tester);
  });

  testWidgets('a failed first page offers 重试, which loads it', (tester) async {
    final api = FakeHotApi(videos: hotVideos(40))..failures['page'] = const BiliError.api(code: -500, message: '服务器错误');
    await show(tester, api: api);
    expect(find.byKey(const ValueKey('hot-error')), findsOneWidget);
    expect(find.text('B 站返回错误 -500：服务器错误'), findsOneWidget);

    api.failures.clear();
    await tester.tap(find.byKey(const ValueKey('hot-retry')));
    await settle(tester);
    expect(api.calls, ['page=1', 'page=1']);
    expect(find.byKey(const ValueKey('hot-error')), findsNothing);
    expect(find.text('测试热门视频 0'), findsOneWidget);
  });

  testWidgets('a failed next page says why under the rows; 重试 asks it again', (tester) async {
    final api = FakeHotApi(videos: hotVideos(40))
      ..failures['page=2'] = const BiliError.api(code: -500, message: '服务器错误');
    await show(tester, api: api);
    await tester.drag(list, const Offset(0, -1500));
    await settle(tester);
    await tester.drag(list, const Offset(0, -400));
    await settle(tester);
    expect(find.byKey(const ValueKey('hot-error')), findsOneWidget);
    expect(api.calls, ['page=1', 'page=2'], reason: 'no loop');

    api.failures.clear();
    await tester.tap(find.byKey(const ValueKey('hot-retry')));
    await settle(tester);
    expect(api.calls, ['page=1', 'page=2', 'page=2']);
    await tester.drag(list, const Offset(0, -4000));
    await settle(tester);
    expect(find.text('测试热门视频 39'), findsOneWidget);
  });

  testWidgets('an empty list says so', (tester) async {
    await show(tester, api: FakeHotApi());
    expect(find.text(HotList.emptyMessage), findsOneWidget);
  });

  testWidgets("首页's tap: back to the top, the room held open until page 1 comes again", (tester) async {
    final api = FakeHotApi(videos: hotVideos(40));
    final harness = await show(tester, api: api);
    await tester.drag(list, const Offset(0, -600));
    await settle(tester);
    expect(harness.offset.value, greaterThan(0));

    final hold = api.holds['page=1'] = Completer<void>();
    harness.tapHome();
    await settle(tester, 20);
    expect(position(tester).pixels, 0);
    expect(harness.offset.value, 0);
    expect(api.calls.last, 'page=1');
    expect(find.byKey(const ValueKey('hot-reload')), findsOneWidget);

    harness.tapHome();
    await settle(tester);
    expect(api.calls.where((call) => call == 'page=1'), hasLength(2), reason: 'nothing more while it runs');

    hold.complete();
    await settle(tester, 20);
    expect(find.byKey(const ValueKey('hot-reload')), findsNothing);
  });

  testWidgets("首页's tap before the first show starts the list", (tester) async {
    final api = FakeHotApi(videos: hotVideos(5));
    final harness = await show(tester, api: api, active: false);
    harness.tapHome();
    await settle(tester);
    expect(api.calls, ['page=1']);
    expect(find.text('测试热门视频 0'), findsOneWidget);
  });

  testWidgets('the offset follows the scroll, which folds 首页\'s header', (tester) async {
    final harness = await show(tester);
    expect(harness.offset.value, 0);
    await tester.drag(list, const Offset(0, -300));
    await settle(tester);
    expect(harness.offset.value, moreOrLessEquals(position(tester).pixels));
    expect(harness.offset.value, greaterThan(200));
    await tester.drag(list, const Offset(0, 1000));
    await settle(tester, 20);
    expect(harness.offset.value, 0, reason: 'a bounce past the top folds nothing');
  });

  testWidgets("a row opens its video with its title and the part as a hint", (tester) async {
    final harness = await show(tester);
    await tester.tap(find.byKey(const ValueKey('hot-row-BV1hot2')));
    await settle(tester);
    final route = harness.opened.single;
    expect(
      (route.bvid, route.cidHint, route.cid, route.title, route.cover),
      ('BV1hot2', 17002, null, '测试热门视频 2', null),
    );
  });

  testWidgets("⋮ opens 217's sheet", (tester) async {
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('hot-more-BV1hot0')));
    await settle(tester);
    expect(find.byKey(const ValueKey('hot-share-sheet')), findsOneWidget);
    expect(find.text('分享'), findsOneWidget);
  });
}
