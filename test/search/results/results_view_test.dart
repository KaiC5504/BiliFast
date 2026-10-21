import 'dart:async';

import 'package:bili_core/api.dart' hide RichText;
import 'package:bili_core/devlog.dart';
import 'package:bilifast/comments/comment_badges.dart' show LevelBadge;
import 'package:bilifast/search/results/filter_panel.dart';
import 'package:bilifast/search/results/results_view.dart';
import 'package:bilifast/search/fake_search_api.dart';
import 'package:bilifast/search/search_filters.dart';
import 'package:bilifast/search/search_history_store.dart';
import 'package:bilifast/search/search_model.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/gestures.dart' show kPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../home/fake_login_gate.dart';
import 'results_support.dart';

void main() {
  late StubSearchModel model;
  late FakePageApi api;
  late FakeLoginGate gate;
  late List<SearchVideo> opened;
  late List<SearchUser> openedUsers;
  late List<SearchVideo> more;

  setUp(() {
    model = StubSearchModel();
    api = FakePageApi();
    gate = FakeLoginGate();
    opened = [];
    openedUsers = [];
    more = [];
  });

  Future<void> show(WidgetTester tester, {bool loggedIn = true}) async {
    final services = await resultServices(loggedIn: loggedIn, api: api, gate: gate);
    await pumpInApp(
      tester,
      services,
      ResultsView(model: model, onOpenVideo: opened.add, onOpenUser: openedUsers.add, onMore: more.add),
    );
    await settle(tester);
  }

  List<SearchVideo> videos(int count) => [for (var i = 0; i < count; i++) video(i)];

  Finder tab(SearchTab tab) => find.byKey(ValueKey('search-tab-${tab.name}'));

  group('tabs', () {
    testWidgets('综合 and 用户 only, 综合 pink with the bar under it, 54 apart from the left edge', (tester) async {
      model.videosValue = SearchResults(items: videos(3), loaded: true);
      await show(tester);
      expect(find.text('番剧'), findsNothing);
      expect(find.text('直播'), findsNothing);
      final all = tester.widget<RichText>(find.descendant(of: tab(SearchTab.all), matching: find.byType(RichText)));
      final users = tester.widget<RichText>(find.descendant(of: tab(SearchTab.users), matching: find.byType(RichText)));
      expect(all.text.style?.color, SearchResultTheme.tabSelected);
      expect(all.text.style?.fontSize, SearchResultTheme.tabSelectedText);
      expect(users.text.style?.color, SearchResultTheme.tabInk);
      expect(users.text.style?.fontSize, SearchResultTheme.tabText);
      expect(tester.getCenter(find.text('综合')).dx, closeTo(27, 0.5));
      expect(tester.getCenter(find.text('用户')).dx, closeTo(81, 0.5));
      final bar = tester.getRect(find.byKey(const ValueKey('search-tab-indicator')));
      expect(bar.center.dx, closeTo(27, 0.5));
      expect(bar.size, const Size(SearchResultTheme.indicatorWidth, SearchResultTheme.indicatorHeight));
      expect(find.byKey(const ValueKey('search-filter')), findsOneWidget);
    });

    testWidgets('a tap on 用户 selects it; the funnel goes and the sort row shows, its choices toasting 暂未开放', (
      tester,
    ) async {
      model.videosValue = SearchResults(items: videos(3), loaded: true);
      model.usersValue = SearchResults(items: [user(1)], loaded: true);
      await show(tester);
      await tester.tap(tab(SearchTab.users));
      await settle(tester);
      expect(model.tabs, [SearchTab.users]);
      expect(find.byKey(const ValueKey('search-filter')), findsNothing);
      expect(tester.getCenter(find.byKey(const ValueKey('search-tab-indicator'))).dx, closeTo(81, 0.5));
      expect(tester.getCenter(find.text('默认排序')).dx, lessThan(220));
      expect(tester.getCenter(find.text('全部用户')).dx, greaterThan(220));
      await tester.tap(find.byKey(const ValueKey('search-sort-默认排序')));
      await tester.pump();
      expect(find.text('暂未开放'), findsOneWidget);
      await toastGone(tester);
      await tester.tap(find.byKey(const ValueKey('search-sort-全部用户')));
      await tester.pump();
      expect(find.text('暂未开放'), findsOneWidget);
      await toastGone(tester);
      // The selected tab again does nothing.
      await tester.tap(tab(SearchTab.users));
      await settle(tester);
      expect(model.tabs, [SearchTab.users]);
    });

    testWidgets('the hairline under the tab row is lighter than the rows\' own', (tester) async {
      model.videosValue = SearchResults(items: videos(2), loaded: true);
      await show(tester);
      Iterable<Color> inks(double height) => find
          .byType(ColoredBox)
          .evaluate()
          .where((element) => element.size?.height == height)
          .map((element) => (element.widget as ColoredBox).color);
      final hairlines = inks(SearchResultTheme.hairline).toList();
      expect(hairlines, contains(const Color(0xFFE3E5E7)));
      expect(hairlines.where((ink) => ink == const Color(0xFFD9DBDE)), hasLength(2));
    });

    testWidgets('every control answers accessibility presses', (tester) async {
      final semantics = tester.ensureSemantics();
      model.videosValue = SearchResults(items: videos(1), loaded: true);
      await show(tester);
      tester.semantics.tap(find.semantics.byLabel('用户'));
      await settle(tester);
      expect(model.tabs, [SearchTab.users]);
      tester.semantics.tap(find.semantics.byLabel('综合'));
      await settle(tester);
      tester.semantics.tap(find.semantics.byLabel('筛选'));
      await settle(tester);
      expect(find.byType(SearchFilterPanel), findsOneWidget);
      tester.semantics.tap(find.semantics.byLabel('关闭筛选'));
      await settle(tester);
      expect(find.byType(SearchFilterPanel), findsNothing);
      tester.semantics.tap(find.semantics.byLabel('更多操作'));
      expect(more, hasLength(1));
      tester.semantics.tap(find.semantics.byLabel('测试视频标题 0，测试作者，2:42，9.2万'));
      expect(opened, hasLength(1));
      semantics.dispose();
    });

    testWidgets('while 筛选 is open, only it, its dim and the tab row are read', (tester) async {
      final semantics = tester.ensureSemantics();
      model.videosValue = SearchResults(items: videos(3), loaded: true);
      await show(tester);
      final row = find.semantics.byLabel('测试视频标题 0，测试作者，2:42，9.2万');
      expect(row, findsOne);
      await tester.tap(find.byKey(const ValueKey('search-filter')));
      await settle(tester);
      expect(row, findsNothing);
      expect(find.semantics.byLabel('关闭筛选'), findsOne);
      expect(find.semantics.byLabel('默认排序'), findsOne);
      expect(find.semantics.byLabel('筛选'), findsOne);
      await tester.tap(find.byKey(const ValueKey('search-filter')));
      await settle(tester);
      expect(row, findsOne);
      semantics.dispose();
    });

    testWidgets('the tab row leaves as the rows scroll up and comes back when they scroll down', (tester) async {
      model.videosValue = SearchResults(items: videos(20), loaded: true, exhausted: true);
      await show(tester);
      double top() => tester.getTopLeft(find.byKey(const ValueKey('search-tab-all'))).dy;
      expect(top(), 0);
      await tester.drag(find.byKey(const ValueKey('search-list-all')), const Offset(0, -300));
      await settle(tester);
      expect(top(), lessThanOrEqualTo(-SearchResultTheme.tabRowHeight));
      await tester.drag(find.byKey(const ValueKey('search-list-all')), const Offset(0, 30));
      await tester.pump();
      expect(top(), inExclusiveRange(-SearchResultTheme.tabRowHeight, 0));
      await tester.drag(find.byKey(const ValueKey('search-list-all')), const Offset(0, 100));
      await settle(tester);
      expect(top(), 0);
    });

    group('let go half shown, the header goes on to the nearer end', () {
      Future<double Function()> scrolledPast(WidgetTester tester, {bool still = false}) async {
        model.videosValue = SearchResults(items: videos(20), loaded: true, exhausted: true);
        final services = await resultServices(loggedIn: true, api: api, gate: gate);
        await pumpInApp(
          tester,
          services,
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: still),
              child: ResultsView(model: model, onOpenVideo: opened.add, onOpenUser: openedUsers.add, onMore: more.add),
            ),
          ),
        );
        await settle(tester);
        await tester.drag(find.byKey(const ValueKey('search-list-all')), const Offset(0, -400));
        await settle(tester);
        return () => tester.getTopLeft(find.byKey(const ValueKey('search-tab-all'))).dy;
      }

      const header = SearchResultTheme.tabRowHeight + SearchResultTheme.hairline;

      testWidgets('mostly shown, it comes all the way back', (tester) async {
        final top = await scrolledPast(tester);
        await tester.drag(find.byKey(const ValueKey('search-list-all')), const Offset(0, 50));
        await tester.pump();
        expect(top(), inExclusiveRange(-header, 0));
        await settle(tester);
        expect(top(), 0);
      });

      testWidgets('mostly hidden, it goes', (tester) async {
        final top = await scrolledPast(tester);
        await tester.drag(find.byKey(const ValueKey('search-list-all')), const Offset(0, 28));
        await tester.pump();
        expect(top(), inExclusiveRange(-header, 0));
        await settle(tester);
        expect(top(), closeTo(-header, 0.01));
      });

      testWidgets('under Reduce Motion, at once', (tester) async {
        final top = await scrolledPast(tester, still: true);
        await tester.drag(find.byKey(const ValueKey('search-list-all')), const Offset(0, 50));
        await tester.pump();
        expect(top(), 0);
      });
    });

    testWidgets('each tab keeps its own place', (tester) async {
      model.videosValue = SearchResults(items: videos(20), loaded: true, exhausted: true);
      model.usersValue = SearchResults(items: [for (var i = 0; i < 20; i++) user(i)], loaded: true, exhausted: true);
      await show(tester);
      await tester.drag(find.byKey(const ValueKey('search-list-all')), const Offset(0, -500));
      await settle(tester);
      await tester.drag(find.byKey(const ValueKey('search-list-all')), const Offset(0, 80));
      await settle(tester);
      final before = tester.getTopLeft(find.byKey(const ValueKey('search-row-BV1search5'))).dy;
      await tester.tap(tab(SearchTab.users));
      await settle(tester);
      expect(tester.getTopLeft(find.byKey(const ValueKey('search-row-user-700'))).dy, closeTo(80, 0.01));
      await tester.tap(tab(SearchTab.all));
      await settle(tester);
      expect(tester.getTopLeft(find.byKey(const ValueKey('search-row-BV1search5'))).dy, before);
    });

    testWidgets('a new search starts from the top', (tester) async {
      model.videosValue = SearchResults(items: videos(20), loaded: true, exhausted: true);
      await show(tester);
      await tester.drag(find.byKey(const ValueKey('search-list-all')), const Offset(0, -800));
      await settle(tester);
      expect(find.byKey(const ValueKey('search-row-BV1search0')), findsNothing);
      model.update(() => model.keywordValue = '别的');
      await settle(tester);
      expect(find.byKey(const ValueKey('search-row-BV1search0')), findsOneWidget);
    });

    testWidgets('the same word searched again starts from the top, the tab row shown', (tester) async {
      model.videosValue = SearchResults(items: videos(20), loaded: true, exhausted: true);
      await show(tester);
      await tester.drag(find.byKey(const ValueKey('search-list-all')), const Offset(0, -800));
      await settle(tester);
      expect(find.byKey(const ValueKey('search-row-BV1search0')), findsNothing);
      model.update(() => model.searchesValue++);
      await settle(tester);
      expect(find.byKey(const ValueKey('search-row-BV1search0')), findsOneWidget);
      expect(tester.getTopLeft(find.byKey(const ValueKey('search-tab-all'))).dy, 0);
    });
  });

  group('video rows', () {
    testWidgets('cover, length, title with the search in pink, UP, plays and date; ⋮ and the row\'s tap', (
      tester,
    ) async {
      final now = DateTime.now();
      model.videosValue = SearchResults(
        items: [
          video(
            1,
            title: const HighlightedText([HighlightRun('星神'), HighlightRun('测试', highlighted: true)]),
            author: '作者甲',
            play: 92000,
            duration: 162,
            published: now.subtract(const Duration(hours: 23, minutes: 5)),
          ),
        ],
        loaded: true,
      );
      await show(tester);
      expect(find.text('2:42'), findsOneWidget);
      expect(find.text('作者甲'), findsOneWidget);
      expect(find.text('9.2万 · 23小时前'), findsOneWidget);
      expect(find.byKey(const ValueKey('search-cover-placeholder')), findsOneWidget);
      final title = tester.widget<RichText>(
        find.descendant(of: find.byKey(const ValueKey('search-title-BV1search1')), matching: find.byType(RichText)),
      );
      final runs = <(String, Color?)>[];
      title.text.visitChildren((span) {
        if (span is TextSpan && span.text != null) runs.add((span.text!, span.style?.color));
        return true;
      });
      expect(runs, [('星神', null), ('测试', SearchResultTheme.highlight)]);
      expect(tester.getRect(find.byKey(const ValueKey('search-row-BV1search1'))).height, closeTo(121, 0.01));

      await tester.tap(find.byKey(const ValueKey('search-more-BV1search1')));
      expect(more.single.bvid, 'BV1search1');
      expect(opened, isEmpty);
      await tester.tap(find.byKey(const ValueKey('search-video-BV1search1')));
      expect(opened.single.bvid, 'BV1search1');
    });

    testWidgets('a long title stops at two lines with …', (tester) async {
      model.videosValue = SearchResults(items: [video(1, title: HighlightedText.plain('很长的标题' * 20))], loaded: true);
      await show(tester);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: find.byKey(const ValueKey('search-title-BV1search1')), matching: find.byType(RichText)),
      );
      expect(paragraph.maxLines, 2);
      expect(paragraph.overflow, TextOverflow.ellipsis);
      expect(paragraph.didExceedMaxLines, isTrue);
    });
  });

  group('paging', () {
    testWidgets('the first page shows a spinner', (tester) async {
      model.videosValue = const SearchResults(loading: true);
      await show(tester);
      expect(find.byKey(const ValueKey('search-first-spinner')), findsOneWidget);
      expect(find.byKey(const ValueKey('search-empty')), findsNothing);
    });

    testWidgets('no results say 没有找到相关内容', (tester) async {
      model.videosValue = const SearchResults(loaded: true, exhausted: true);
      await show(tester);
      expect(find.text('没有找到相关内容'), findsOneWidget);
      expect(find.byKey(const ValueKey('search-first-spinner')), findsNothing);
    });

    testWidgets('a failed first page shows why with 重试', (tester) async {
      model.videosValue = const SearchResults(loaded: true, error: '网络连接失败，请检查网络后重试');
      await show(tester);
      expect(find.text('网络连接失败，请检查网络后重试'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('search-retry')));
      expect(model.retries, 1);
    });

    testWidgets('scrolling near the end asks for the next page, with a spinner at the end while it loads', (
      tester,
    ) async {
      model.videosValue = SearchResults(items: videos(20), loaded: true);
      await show(tester);
      expect(model.loadMores, 0, reason: 'the end is far below');
      await tester.fling(find.byKey(const ValueKey('search-list-all')), const Offset(0, -3000), 3000);
      await settle(tester, 40);
      expect(model.loadMores, greaterThan(0));
      model.update(() => model.videosValue = SearchResults(items: videos(20), loaded: true, loading: true));
      await tester.pump();
      expect(find.byKey(const ValueKey('search-more-spinner')), findsOneWidget);
    });

    testWidgets('a short first page asks for the next at once', (tester) async {
      model.videosValue = SearchResults(items: videos(2), loaded: true);
      await show(tester);
      model.update(() {});
      await settle(tester);
      expect(model.loadMores, greaterThan(0));
    });

    testWidgets('an exhausted list asks for nothing more', (tester) async {
      model.videosValue = SearchResults(items: videos(2), loaded: true, exhausted: true);
      await show(tester);
      model.update(() {});
      await settle(tester);
      expect(model.loadMores, 0);
    });

    testWidgets('a stalled load asks for nothing by itself; 加载更多 under the rows asks again', (tester) async {
      model.videosValue = SearchResults(items: videos(2), loaded: true, stalled: true);
      await show(tester);
      model.update(() {});
      await settle(tester);
      expect(model.loadMores, 0);
      await tester.tap(find.byKey(const ValueKey('search-load-more')));
      expect(model.loadMores, 1);
    });

    testWidgets('stalled with no rows yet, 加载更多 shows in the middle', (tester) async {
      model.videosValue = const SearchResults(loaded: true, stalled: true);
      await show(tester);
      model.update(() {});
      await settle(tester);
      expect(model.loadMores, 0);
      expect(find.text('没有找到相关内容'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('search-load-more')));
      expect(model.loadMores, 1);
    });

    testWidgets('重试 shrinks while pressed', (tester) async {
      model.videosValue = const SearchResults(loaded: true, error: '加载失败，请稍后重试');
      await show(tester);
      double scale() => tester
          .widget<AnimatedScale>(
            find.descendant(of: find.byKey(const ValueKey('search-retry')), matching: find.byType(AnimatedScale)),
          )
          .scale;
      expect(scale(), 1);
      final press = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('search-retry'))));
      // A tap inside the scrolling list is a press only after the press timeout.
      await tester.pump(kPressTimeout * 2);
      expect(scale(), SearchResultTheme.followPressedScale);
      await press.up();
      await settle(tester);
      expect(scale(), 1);
      expect(model.retries, 1);
    });

    testWidgets('a failed next page shows why under the rows with 重试', (tester) async {
      model.videosValue = SearchResults(items: videos(2), loaded: true, error: '加载失败，请稍后重试');
      await show(tester);
      model.update(() {});
      await settle(tester);
      expect(model.loadMores, 0, reason: 'only 重试 asks again');
      expect(find.text('加载失败，请稍后重试'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('search-retry')));
      expect(model.retries, 1);
    });
  });

  group('筛选', () {
    testWidgets('the funnel opens the panel under the tab row over a dim; the dim or the funnel closes it', (
      tester,
    ) async {
      model.videosValue = SearchResults(items: videos(5), loaded: true);
      await show(tester);
      expect(find.byType(SearchFilterPanel), findsNothing);
      await tester.tap(find.byKey(const ValueKey('search-filter')));
      await settle(tester);
      expect(find.byType(SearchFilterPanel), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(SearchFilterPanel)).dy,
        closeTo(SearchResultTheme.tabRowHeight + SearchResultTheme.hairline, 0.01),
      );
      final dim = tester.getRect(find.byKey(const ValueKey('search-filter-dim')));
      expect(dim.top, closeTo(SearchResultTheme.tabRowHeight + SearchResultTheme.hairline, 0.01));
      await tester.tapAt(Offset(220, dim.bottom - 40));
      await settle(tester);
      expect(find.byType(SearchFilterPanel), findsNothing);
      expect(opened, isEmpty, reason: 'the dim takes the tap, not the row under it');

      await tester.tap(find.byKey(const ValueKey('search-filter')));
      await settle(tester);
      expect(find.byType(SearchFilterPanel), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('search-filter')));
      await settle(tester);
      expect(find.byType(SearchFilterPanel), findsNothing);
    });

    testWidgets('the page shares whether it is open, and closing it there closes it', (tester) async {
      final open = ValueNotifier(false);
      addTearDown(open.dispose);
      model.videosValue = SearchResults(items: videos(5), loaded: true);
      final services = await resultServices(loggedIn: true, api: api, gate: gate);
      await pumpInApp(
        tester,
        services,
        ResultsView(
          model: model,
          filterOpen: open,
          onOpenVideo: opened.add,
          onOpenUser: openedUsers.add,
          onMore: more.add,
        ),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('search-filter')));
      await settle(tester);
      expect(open.value, isTrue);
      open.value = false;
      await settle(tester);
      expect(find.byType(SearchFilterPanel), findsNothing);
      open.value = true;
      await settle(tester);
      expect(find.byType(SearchFilterPanel), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('search-filter-dim')));
      await settle(tester);
      expect(open.value, isFalse);
    });

    testWidgets('a choice goes to the model; 用户 closes the panel', (tester) async {
      model.videosValue = SearchResults(items: videos(5), loaded: true);
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('search-filter')));
      await settle(tester);
      tester
          .widget<SearchFilterPanel>(find.byType(SearchFilterPanel))
          .onChanged(const SearchFilters(order: FilterOrder.newest));
      await settle(tester);
      expect(model.filterChanges, [const SearchFilters(order: FilterOrder.newest)]);
      await tester.tap(tab(SearchTab.users));
      await settle(tester);
      expect(find.byType(SearchFilterPanel), findsNothing);
    });
  });

  group('on the real model', () {
    Future<(SearchModel, FakeSearchApi)> showReal(WidgetTester tester, {int videoCount = 25}) async {
      final search = FakeSearchApi(
        videos: [for (var i = 0; i < videoCount; i++) video(i)],
        users: [user(1), user(2, following: true)],
        pageSize: 10,
      );
      final real = SearchModel(
        api: search,
        history: SearchHistoryStore.memory(),
        placeholder: '默认',
        searchGap: Duration.zero,
      );
      addTearDown(real.dispose);
      final services = await resultServices(loggedIn: true, api: api, gate: gate);
      await pumpInApp(
        tester,
        services,
        ResultsView(model: real, onOpenVideo: opened.add, onOpenUser: openedUsers.add, onMore: more.add),
      );
      real.search('测试');
      await settle(tester);
      return (real, search);
    }

    testWidgets('pages through 综合 as it scrolls, then 用户 on its tab', (tester) async {
      final (real, search) = await showReal(tester);
      expect(real.videos.items, hasLength(10));
      for (var i = 0; i < 6; i++) {
        await tester.fling(find.byKey(const ValueKey('search-list-all')), const Offset(0, -2000), 3000);
        await settle(tester, 30);
      }
      expect(real.videos.items, hasLength(25));
      expect(real.videos.exhausted, isTrue);
      expect(find.byKey(const ValueKey('search-row-BV1search24')), findsOneWidget);
      await tester.drag(find.byKey(const ValueKey('search-list-all')), const Offset(0, 100));
      await settle(tester);
      await tester.tap(tab(SearchTab.users));
      await settle(tester);
      expect(search.calls.where((call) => call.startsWith('users')), hasLength(1));
      expect(find.text('已关注'), findsOneWidget);
    });

    testWidgets('settled 综合 asks for no more frames while 用户 has not loaded behind it', (tester) async {
      final (real, _) = await showReal(tester);
      expect(real.users.loaded, isFalse);
      await settle(tester);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('a 筛选 that cuts every row stops after one load and asks again only on 加载更多', (tester) async {
      // 40 one-row pages of videos under two hours, which 120分钟+ cuts on our side.
      final search = FakeSearchApi(videos: [for (var i = 0; i < 40; i++) video(i, duration: 600)], pageSize: 1);
      final real = SearchModel(
        api: search,
        history: SearchHistoryStore.memory(),
        placeholder: '默认',
        searchGap: Duration.zero,
      );
      addTearDown(real.dispose);
      final services = await resultServices(loggedIn: true, api: api, gate: gate);
      await pumpInApp(
        tester,
        services,
        ResultsView(model: real, onOpenVideo: opened.add, onOpenUser: openedUsers.add, onMore: more.add),
      );
      real.setFilters(const SearchFilters(length: FilterLength.over120));
      real.search('测试');
      await settle(tester, 40);
      int asked() => search.calls.where((call) => call.startsWith('videos')).length;
      expect(asked(), SearchModel.pagesPerLoad);
      expect(real.videos.stalled, isTrue);
      expect(real.videos.loading, isFalse);
      expect(find.byType(CupertinoActivityIndicator), findsNothing, reason: 'no spinner left ticking');
      await settle(tester, 40);
      expect(asked(), SearchModel.pagesPerLoad, reason: 'nothing more by itself');
      await tester.tap(find.byKey(const ValueKey('search-load-more')));
      await settle(tester, 40);
      expect(asked(), SearchModel.pagesPerLoad * 2);
    });

    testWidgets('a failed first page retries with 重试', (tester) async {
      final search = FakeSearchApi(videos: [video(1)])..failNext('videos');
      final real = SearchModel(
        api: search,
        history: SearchHistoryStore.memory(),
        placeholder: '默认',
        searchGap: Duration.zero,
      );
      addTearDown(real.dispose);
      final services = await resultServices(loggedIn: true, api: api, gate: gate);
      await pumpInApp(
        tester,
        services,
        ResultsView(model: real, onOpenVideo: opened.add, onOpenUser: openedUsers.add, onMore: more.add),
      );
      real.search('测试');
      await settle(tester);
      expect(find.byKey(const ValueKey('search-retry')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('search-retry')));
      await settle(tester);
      expect(find.byKey(const ValueKey('search-row-BV1search1')), findsOneWidget);
    });

    testWidgets('关注 on the real model turns and rolls back', (tester) async {
      final (real, _) = await showReal(tester);
      await tester.tap(tab(SearchTab.users));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('search-follow-701')));
      await settle(tester);
      expect(real.users.items.first.following, isTrue);
      api.failures['follow'] = const BiliAPIError(code: -400, message: '关注失败了');
      await tester.tap(find.byKey(const ValueKey('search-follow-702')));
      await settle(tester);
      expect(real.users.items[1].following, isTrue);
      expect(find.text('关注失败了'), findsOneWidget);
      await toastGone(tester);
    });

    testWidgets('no results say 没有找到相关内容', (tester) async {
      await showReal(tester, videoCount: 0);
      expect(find.text('没有找到相关内容'), findsOneWidget);
    });
  });

  group('用户 rows', () {
    Future<void> showUsers(WidgetTester tester, List<SearchUser> users, {bool loggedIn = true}) async {
      model.tabValue = SearchTab.users;
      model.usersValue = SearchResults(items: users, loaded: true, exhausted: true);
      await show(tester, loggedIn: loggedIn);
    }

    testWidgets('name and level, fans alone with no videos, fans · videos, the verification line and marks', (
      tester,
    ) async {
      await showUsers(tester, [
        user(1, fans: 8),
        user(2, fans: 1481234, videos: 539, officialType: 0, officialDesc: '知名UP主'),
        user(3, fans: 12000, videos: 79, officialType: 1),
      ]);
      expect(find.text('测试用户1'), findsOneWidget);
      expect(find.text('8粉丝'), findsOneWidget);
      expect(find.text('148.1万粉丝 · 539个视频'), findsOneWidget);
      expect(find.text('知名UP主'), findsOneWidget);
      expect(find.text('1.2万粉丝 · 79个视频'), findsOneWidget);
      expect(tester.widgetList<LevelBadge>(find.byType(LevelBadge)).map((badge) => badge.level), [2, 2, 2]);
      expect(find.byKey(const ValueKey('search-verified-701')), findsNothing);
      expect(find.byKey(const ValueKey('search-verified-702')), findsOneWidget);
      expect(find.byKey(const ValueKey('search-verified-703')), findsOneWidget);
      expect(find.text('关注'), findsNWidgets(3));
      await tester.tap(find.byKey(const ValueKey('search-user-701')));
      expect(openedUsers.single.mid, 701);
    });

    testWidgets('logged out, 关注 opens the login page and follows no one', (tester) async {
      await showUsers(tester, [user(1)], loggedIn: false);
      await tester.tap(find.byKey(const ValueKey('search-follow-701')));
      await settle(tester);
      expect(gate.requests, 1);
      expect(model.follows, isEmpty);
      expect(api.calls.where((call) => call.startsWith('follow')), isEmpty);
      expect(openedUsers, isEmpty);
    });

    testWidgets('logged in, 关注 turns at once and follows; again unfollows', (tester) async {
      await showUsers(tester, [user(1)]);
      await tester.tap(find.byKey(const ValueKey('search-follow-701')));
      await settle(tester);
      expect(model.follows, [(701, true)]);
      expect(api.calls, contains('follow on=true'));
      expect(find.text('已关注'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('search-follow-701')));
      await settle(tester);
      expect(model.follows, [(701, true), (701, false)]);
      expect(api.calls, contains('follow on=false'));
      expect(find.text('已关注'), findsNothing);
    });

    testWidgets('a press while 关注 is out is ignored, so a failure rolls back to where it started', (tester) async {
      final hold = Completer<void>();
      api.holds['follow'] = hold;
      await showUsers(tester, [user(1)]);
      await tester.tap(find.byKey(const ValueKey('search-follow-701')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('search-follow-701')));
      await settle(tester);
      expect(api.calls.where((call) => call.startsWith('follow')), hasLength(1));
      expect(model.follows, [(701, true)]);
      api.failures['follow'] = const BiliAPIError(code: -400, message: '关注失败了');
      hold.complete();
      await settle(tester);
      expect(model.follows, [(701, true), (701, false)]);
      expect(find.text('已关注'), findsNothing);
      await toastGone(tester);
      api.failures.remove('follow');
      api.holds.remove('follow');
      await tester.tap(find.byKey(const ValueKey('search-follow-701')));
      await settle(tester);
      expect(find.text('已关注'), findsOneWidget, reason: 'once answered, presses count again');
    });

    testWidgets('the pill fades and grows in as 简介\'s does', (tester) async {
      await showUsers(tester, [user(1)]);
      await tester.tap(find.byKey(const ValueKey('search-follow-701')));
      await tester.pump();
      await tester.pump(SearchResultTheme.followMotion ~/ 2);
      final grow = tester.widget<ScaleTransition>(
        find.ancestor(of: find.text('已关注'), matching: find.byType(ScaleTransition)).first,
      );
      expect(grow.scale.value, inExclusiveRange(SearchResultTheme.followSwapScale, 1));
      await settle(tester);
    });

    testWidgets('a failed 关注 logs the error\'s kind, not its words, which can carry the request', (tester) async {
      final sink = MemorySink();
      Logger.shared.add(sink);
      addTearDown(() => Logger.shared.remove(sink));
      api.failures['follow'] = Exception('GET https://api.bilibili.com/x/relation/modify?keyword=秘密');
      await showUsers(tester, [user(1)]);
      await tester.tap(find.byKey(const ValueKey('search-follow-701')));
      await settle(tester);
      final logged = sink.events.singleWhere((event) => event.msg == 'search follow failed');
      expect('${logged.f['error']}', contains('_Exception'));
      expect('${logged.f}', isNot(contains('bilibili.com')));
      await toastGone(tester);
    });

    testWidgets('a refused 关注 turns back with a toast', (tester) async {
      api.failures['follow'] = BiliAPIError(code: 22001, message: '不能关注自己');
      await showUsers(tester, [user(1)]);
      await tester.tap(find.byKey(const ValueKey('search-follow-701')));
      await settle(tester);
      expect(model.follows, [(701, true), (701, false)]);
      expect(find.text('已关注'), findsNothing);
      expect(find.text('不能关注自己'), findsOneWidget);
      await toastGone(tester);
    });
  });
}
