import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bilifast/favourites/fake_favourites_api.dart';
import 'package:bilifast/favourites/folder_page.dart';
import 'package:bilifast/shared/loading_tv.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:bilifast/space/own/own_favourites_tab.dart';
import 'package:bilifast/space/own/own_tab_cards.dart';
import 'package:bilifast/space/own/own_tab_glyphs.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'own_tabs_support.dart';

void main() {
  late ScrollController scroll;

  setUp(() => scroll = ScrollController());
  tearDown(() => scroll.dispose());

  FakeFavouritesApi api(int folders, {int pageSize = 20, Map<int, String> covers = const {}}) => FakeFavouritesApi(
    folders: [for (var i = 0; i < folders; i++) favFolder(i, count: i * 3, isPrivate: i.isOdd)],
    covers: covers,
    folderPageSize: pageSize,
  );

  Future<void> show(WidgetTester tester, FakeFavouritesApi favourites, {int? count, bool settled = true}) async {
    final services = await ownTabServices(favouritesApi: favourites);
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpOwnTab(
      tester,
      services,
      OwnFavouritesSliver(mid: ownMid, count: count),
      controller: scroll,
    );
    if (settled) await settle(tester);
  }

  Finder row(int i) => find.byKey(ValueKey('own-favourites-row-${100 + i}'), skipOffstage: false);

  Future<void> toEnd(WidgetTester tester) async {
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await settle(tester, 4);
  }

  testWidgets('the first load shows the TV, then the rows', (tester) async {
    final favourites = api(2)..holds['folders'] = Completer<void>();
    await show(tester, favourites, settled: false);
    await tester.pump();
    expect(find.byKey(const ValueKey('own-favourites-loading')), findsOneWidget);
    expect(find.byType(LoadingTvState), findsOneWidget);
    expect(find.text('我创建的收藏夹'), findsOneWidget);

    favourites.holds['folders']!.complete();
    await settle(tester);
    expect(find.byType(LoadingTvState), findsNothing);
    expect(find.byType(OwnFolderRow), findsNWidgets(2));
    expect(find.text('测试收藏夹 0'), findsOneWidget);
    expect(find.text('0个内容 · 公开'), findsOneWidget);
    expect(find.text('3个内容 · 私密'), findsOneWidget);
    expect(favourites.calls, ['folders mid=$ownMid']);
  });

  testWidgets('the header counts the space’s folders, or the list once it is all in', (tester) async {
    await show(tester, api(2), count: 7);
    expect(tester.widget<Text>(find.byKey(const ValueKey('own-favourites-count'))).data, '7');

    await show(tester, api(3));
    expect(tester.widget<Text>(find.byKey(const ValueKey('own-favourites-count'))).data, '3');
  });

  testWidgets('116’s places: the header, the band, rows 12 apart', (tester) async {
    await show(tester, api(2), count: 2);
    expect(tester.getCenter(find.text('我创建的收藏夹')).dy, moreOrLessEquals(145 / 6, epsilon: 0.01));
    final first = tester.getRect(row(0));
    final second = tester.getRect(row(1));
    expect(first.top, moreOrLessEquals(145 / 3 + 1 + 12, epsilon: 0.01));
    expect(second.top - first.bottom, 12);
    expect(first.height, 73);
    final title = tester.getRect(find.text('测试收藏夹 0'));
    expect(title.left, 12 + 117 + 10);
    expect(title.center.dy - first.top, moreOrLessEquals(10, epsilon: 0.01));
  });

  testWidgets('a folder without a cover draws the TV, one with a cover its picture', (tester) async {
    await show(tester, api(2, covers: {101: 'https://i0.hdslb.com/bfs/test/folder.jpg'}));
    expect(find.descendant(of: row(0), matching: find.byType(CoverTv)), findsOneWidget);
    expect(
      tester.widget<RemoteImage>(find.descendant(of: row(1), matching: find.byType(RemoteImage))).url,
      'https://i0.hdslb.com/bfs/test/folder.jpg',
    );
  });

  testWidgets('pages come as the list nears its end, with the small spinner while one loads', (tester) async {
    final favourites = api(40, pageSize: 15);
    await show(tester, favourites);
    expect(favourites.calls, ['folders mid=$ownMid']);
    expect(row(9), findsOneWidget);

    favourites.holds['folders'] = Completer<void>();
    await toEnd(tester);
    expect(favourites.calls.last, 'folders mid=$ownMid page=2');
    expect(find.byKey(const ValueKey('own-favourites-more-spinner'), skipOffstage: false), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator, skipOffstage: false), findsOneWidget);

    favourites.holds.remove('folders')!.complete();
    await settle(tester);
    expect(row(15), findsOneWidget);
    await toEnd(tester);
    await toEnd(tester);
    expect(favourites.calls, ['folders mid=$ownMid', 'folders mid=$ownMid page=2', 'folders mid=$ownMid page=3']);
    expect(row(39), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator, skipOffstage: false), findsNothing);
    expect(tester.widget<Text>(find.byKey(const ValueKey('own-favourites-count'), skipOffstage: false)).data, '40');
  });

  testWidgets('the header folds the list and unfolds it, the chevron turning over', (tester) async {
    await show(tester, api(3));
    AnimatedRotation chevron() => tester.widget(find.byKey(const ValueKey('own-favourites-chevron')));
    expect(chevron().turns, 0);

    await tester.tap(find.byKey(const ValueKey('own-favourites-header')));
    await settle(tester);
    expect(find.byType(OwnFolderRow), findsNothing);
    expect(chevron().turns, 0.5);

    await tester.tap(find.byKey(const ValueKey('own-favourites-header')));
    await settle(tester);
    expect(find.byType(OwnFolderRow), findsNWidgets(3));
    expect(chevron().turns, 0);
  });

  testWidgets('folded, the list asks for no more; unfolded at the end, it does', (tester) async {
    final favourites = api(40, pageSize: 15);
    await show(tester, favourites);
    await tester.tap(find.byKey(const ValueKey('own-favourites-header')));
    await settle(tester);
    await toEnd(tester);
    expect(favourites.calls, ['folders mid=$ownMid']);

    await tester.tap(find.byKey(const ValueKey('own-favourites-header')));
    await settle(tester);
    await toEnd(tester);
    expect(favourites.calls, contains('folders mid=$ownMid page=2'));
  });

  testWidgets('a row opens its folder', (tester) async {
    final favourites = api(3);
    await show(tester, favourites);
    await tester.tap(row(1));
    await settle(tester, 20);
    final page = tester.widget<FolderPage>(find.byType(FolderPage));
    expect(page.folder.id, 101);
    expect(page.folder.isPrivate, isTrue);
    expect(page.api, same(favourites));
  });

  testWidgets('a failed first load shows the retry line, which loads again', (tester) async {
    final favourites = api(2)..failures['folders'] = const BiliAPIError(code: -500, message: 'x');
    await show(tester, favourites);
    expect(find.byType(LoadingTvState), findsNothing);
    expect(find.byKey(const ValueKey('own-favourites-retry')), findsOneWidget);
    expect(find.text('加载失败，点击重试', findRichText: true), findsOneWidget);

    favourites.failures.clear();
    await tester.tap(find.byKey(const ValueKey('own-favourites-retry')));
    await settle(tester);
    expect(find.byType(OwnFolderRow), findsNWidgets(2));
    expect(favourites.calls, ['folders mid=$ownMid', 'folders mid=$ownMid']);
  });

  testWidgets('a failed later page waits under the rows for 点击重试', (tester) async {
    final favourites = api(40, pageSize: 15);
    await show(tester, favourites);
    favourites.failures['folders'] = const BiliAPIError(code: -500, message: 'x');
    await toEnd(tester);
    await toEnd(tester);
    expect(favourites.calls, ['folders mid=$ownMid', 'folders mid=$ownMid page=2']);
    expect(row(14), findsOneWidget);
    final retry = find.byKey(const ValueKey('own-favourites-retry'), skipOffstage: false);
    expect(retry, findsOneWidget);

    favourites.failures.clear();
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await settle(tester);
    expect(favourites.calls.last, 'folders mid=$ownMid page=2');
    expect(row(15), findsOneWidget);
  });
}
