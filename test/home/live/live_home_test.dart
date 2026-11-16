import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/home_header.dart';
import 'package:bilifast/home/home_page.dart';
import 'package:bilifast/home/hot/hot_list.dart';
import 'package:bilifast/home/live/live_tab.dart';
import 'package:bilifast/home/main_shell.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/live/fake_live_api.dart';
import 'package:bilifast/search/fake_search_api.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/fake_keychain.dart';
import '../../playback/fakes.dart' show Canned;
import '../fake_login_gate.dart';
import '../feed_fakes.dart' show FeedHttp, feedItem;
import 'live_support.dart';

void main() {
  late FeedHttp http;
  late FakeLiveApi live;
  final pagesView = find.byKey(const ValueKey('home-pages'));

  setUp(() {
    http = FeedHttp();
    http.pages[1] = [for (var i = 0; i < 20; i++) feedItem('BV1c$i')];
    live = FakeLiveApi(feedPages: [liveFeedPage()]);
    LivePlayers();
  });

  Future<void> show(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final logger = Logger(session: 'test');
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: http,
      logger: logger,
    );
    await environment.refreshAccount();
    final playback = AppPlayback(() async => throw UnimplementedError());
    addTearDown(playback.dispose);
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      loginGate: FakeLoginGate(),
      searchApi: FakeSearchApi(defaultWord: '默认'),
      liveApi: live,
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppScope(services: services, child: child!),
        home: const MainShell(),
      ),
    );
    await settle(tester);
  }

  double page(WidgetTester tester) => tester.widget<PageView>(pagesView).controller!.page!;
  Finder label(HomeTopTab tab) => find.byKey(ValueKey(tab.keyName));
  LiveTab tab(WidgetTester tester) => tester.widget<LiveTab>(find.byType(LiveTab, skipOffstage: false));

  Future<void> swipe(WidgetTester tester, double dx) async {
    await tester.fling(pagesView, Offset(dx, 0), 1000);
    await settle(tester, 20);
  }

  testWidgets('直播 推荐 热门 in that order; 首页 opens on 推荐 and 直播 is built and asked only once reached', (tester) async {
    await show(tester);
    final xs = [for (final tab in HomeTopTab.values) tester.getCenter(label(tab)).dx];
    expect(xs, orderedEquals([...xs]..sort()));
    expect(HomeTopTab.live.page, 0);
    expect(HomeTopTab.recommend.page, 1);
    expect(HomeTopTab.hot.page, 2);
    expect(page(tester), 1);
    expect(tester.widget<Text>(label(HomeTopTab.recommend)).style!.color, BiliColors.pink);
    expect(find.byType(LiveTab, skipOffstage: false), findsNothing);
    expect(live.calls, isEmpty);

    await swipe(tester, 300);
    expect(page(tester), 0);
    expect(tab(tester).active, isTrue);
    expect(live.tabCalls, ['feed page=1']);
    expect(tester.widget<Text>(label(HomeTopTab.live)).style!.color, BiliColors.pink);
    expect(find.byKey(const ValueKey('live-carousel')), findsOneWidget);

    await swipe(tester, -300);
    expect(page(tester), 1);
    expect(tab(tester).active, isFalse, reason: '推荐 on screen');
    await swipe(tester, -300);
    expect(page(tester), 2);
    expect(find.byType(HotList), findsOneWidget);

    await tester.tap(label(HomeTopTab.live));
    await settle(tester, 20);
    expect(page(tester), 0);
    expect(live.tabCalls, ['feed page=1'], reason: 'kept alive: no refresh from the trips');
  });

  testWidgets('the header folds by 直播 while it shows, and opens again on 推荐 at its top', (tester) async {
    await show(tester);
    final open = tester.getRect(find.byType(HomeHeader)).bottom;
    await tester.tap(label(HomeTopTab.live));
    await settle(tester, 20);
    await tester.drag(find.byKey(const ValueKey('live-list')), const Offset(0, -300));
    await settle(tester, 20);
    expect(tester.getRect(find.byType(HomeHeader)).bottom, lessThan(open), reason: 'folded');

    await tester.tap(label(HomeTopTab.recommend));
    await settle(tester, 20);
    expect(tester.getRect(find.byType(HomeHeader)).bottom, open, reason: "推荐's own scroll");
  });

  testWidgets("首页's tap on 直播 refreshes 直播 alone", (tester) async {
    await show(tester);
    await tester.tap(label(HomeTopTab.live));
    await settle(tester, 20);
    final asked = List.of(http.asked);
    await tester.tap(find.byKey(const ValueKey('home-tab-home')));
    await settle(tester, 20);
    expect(live.tabCalls, ['feed page=1', 'feed page=1']);
    expect(http.asked, asked, reason: '推荐 untouched');
  });

  testWidgets('another place shown stills 直播', (tester) async {
    await show(tester);
    await tester.tap(label(HomeTopTab.live));
    await settle(tester, 20);
    await tester.tap(find.byKey(const ValueKey('home-tab-mine')));
    await settle(tester);
    expect(tab(tester).active, isFalse);
    await tester.tap(find.byKey(const ValueKey('home-tab-home')));
    await settle(tester);
    expect(tab(tester).active, isTrue);
    expect(find.byType(HomePage), findsOneWidget);
  });
}
