import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bilifast/shared/loading_tv.dart';
import 'package:bilifast/space/fake_space_api.dart';
import 'package:bilifast/space/own/own_bangumi_tab.dart';
import 'package:bilifast/space/own/own_tab_cards.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'own_tabs_support.dart';

void main() {
  late ScrollController scroll;

  setUp(() => scroll = ScrollController());
  tearDown(() => scroll.dispose());

  FakeSpaceApi api(int count, {int pageSize = 30}) =>
      FakeSpaceApi(bangumiList: [for (var i = 0; i < count; i++) ownBangumi(i)], bangumiPageSize: pageSize);

  Future<void> show(WidgetTester tester, FakeSpaceApi space, {bool settled = true}) async {
    final services = await ownTabServices(spaceApi: space);
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpOwnTab(tester, services, const OwnBangumiSliver(mid: ownMid), controller: scroll);
    if (settled) await settle(tester);
  }

  Finder poster(int i) => find.byKey(ValueKey('own-bangumi-${800 + i}'), skipOffstage: false);
  final end = find.byKey(const ValueKey('own-bangumi-end'), skipOffstage: false);

  Future<void> toEnd(WidgetTester tester) async {
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await settle(tester, 4);
  }

  testWidgets('the first load shows the TV, then the posters and 再怎么找也没有啦', (tester) async {
    final space = api(5)..holds['bangumi'] = Completer<void>();
    await show(tester, space, settled: false);
    await tester.pump();
    expect(find.byKey(const ValueKey('own-bangumi-loading')), findsOneWidget);
    expect(find.byType(LoadingTvState), findsOneWidget);

    space.holds['bangumi']!.complete();
    await settle(tester);
    expect(find.byType(LoadingTvState), findsNothing);
    expect(find.byType(OwnPoster), findsNWidgets(5));
    expect(find.text('测试番剧 0'), findsOneWidget);
    expect(find.text('全12话'), findsNWidgets(5));
    expect(find.text('再怎么找也没有啦'), findsOneWidget);
    expect(space.calls, ['bangumi mid=$ownMid page=1']);
  });

  testWidgets('117’s places: three a row 12 apart, the end line 21.17 under the last row', (tester) async {
    await show(tester, api(5));
    final rects = [for (var i = 0; i < 5; i++) tester.getRect(poster(i))];
    expect(rects.first.left, 12);
    expect(rects.first.top, moreOrLessEquals(34 / 3, epsilon: 0.01));
    expect(rects.first.width, moreOrLessEquals(392 / 3, epsilon: 0.01));
    expect(rects.first.height, moreOrLessEquals(175, epsilon: 0.01));
    expect(rects[1].left - rects[0].right, moreOrLessEquals(12, epsilon: 0.01));
    expect(rects[2].right, moreOrLessEquals(428, epsilon: 0.01));
    expect(rects[3].left, 12);
    expect(rects[3].top - rects[0].bottom, moreOrLessEquals(12, epsilon: 0.01));
    expect(tester.getCenter(end).dy - rects[4].bottom, moreOrLessEquals(127 / 6, epsilon: 0.01));
    expect(tester.getCenter(end).dx, 220);
  });

  testWidgets('a poster draws its title and progress over its bottom', (tester) async {
    await show(tester, api(1));
    final card = tester.getRect(poster(0));
    expect(tester.getCenter(find.text('测试番剧 0')).dy, moreOrLessEquals(card.bottom - 29.5, epsilon: 0.01));
    expect(
      tester.getCenter(find.text('全12话')).dy,
      moreOrLessEquals(card.bottom - OwnSpaceTabsTheme.posterProgressCentre, epsilon: 0.01),
    );
    expect(tester.getTopLeft(find.text('测试番剧 0')).dx, moreOrLessEquals(card.left + 16 / 3, epsilon: 0.01));
  });

  testWidgets('pages come as the list nears its end, the small spinner under it while one loads', (tester) async {
    final space = api(70);
    await show(tester, space);
    expect(space.calls, ['bangumi mid=$ownMid page=1']);
    expect(end, findsNothing);

    space.holds['bangumi'] = Completer<void>();
    await toEnd(tester);
    expect(space.calls.last, 'bangumi mid=$ownMid page=2');
    expect(find.byKey(const ValueKey('own-bangumi-more-spinner'), skipOffstage: false), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator, skipOffstage: false), findsOneWidget);

    space.holds.remove('bangumi')!.complete();
    await settle(tester);
    await toEnd(tester);
    await toEnd(tester);
    expect(space.calls, ['bangumi mid=$ownMid page=1', 'bangumi mid=$ownMid page=2', 'bangumi mid=$ownMid page=3']);
    expect(poster(69), findsOneWidget);
    expect(end, findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator, skipOffstage: false), findsNothing);
  });

  testWidgets('a page that adds nothing new ends the list', (tester) async {
    final repeating = FakeSpaceApi(bangumiList: [for (var i = 0; i < 60; i++) ownBangumi(i % 30)], bangumiPageSize: 30);
    await show(tester, repeating);
    await toEnd(tester);
    await toEnd(tester);
    await toEnd(tester);
    expect(repeating.calls, ['bangumi mid=$ownMid page=1', 'bangumi mid=$ownMid page=2']);
    expect(end, findsOneWidget);
  });

  testWidgets('a failed first load shows the retry line, which loads again', (tester) async {
    final space = api(4)..failures['bangumi'] = const BiliAPIError(code: -500, message: 'x');
    await show(tester, space);
    expect(find.byType(LoadingTvState), findsNothing);
    expect(find.text('加载失败，点击重试', findRichText: true), findsOneWidget);
    expect(end, findsNothing);

    space.failures.clear();
    await tester.tap(find.byKey(const ValueKey('own-bangumi-retry')));
    await settle(tester);
    expect(find.byType(OwnPoster), findsNWidgets(4));
    expect(space.calls, ['bangumi mid=$ownMid page=1', 'bangumi mid=$ownMid page=1']);
  });

  testWidgets('a failed later page waits under the posters for 点击重试', (tester) async {
    final space = api(45);
    await show(tester, space);
    space.failures['bangumi'] = const BiliAPIError(code: -500, message: 'x');
    await toEnd(tester);
    await toEnd(tester);
    expect(space.calls, ['bangumi mid=$ownMid page=1', 'bangumi mid=$ownMid page=2']);
    final retry = find.byKey(const ValueKey('own-bangumi-retry'), skipOffstage: false);
    expect(retry, findsOneWidget);
    expect(end, findsNothing);

    space.failures.clear();
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await settle(tester);
    expect(space.calls.last, 'bangumi mid=$ownMid page=2');
    await toEnd(tester);
    expect(end, findsOneWidget);
  });

  testWidgets('a poster says 暂未开放', (tester) async {
    await show(tester, api(3));
    await tester.tap(poster(1));
    await settle(tester, 2);
    expect(find.text('暂未开放'), findsOneWidget);
    await toastGone(tester);
  });

  testWidgets('no 追番 at all ends at once', (tester) async {
    await show(tester, api(0));
    expect(find.byType(OwnPoster), findsNothing);
    expect(end, findsOneWidget);
  });
}
