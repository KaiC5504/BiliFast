import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/swipe_back_route.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/shared/loading_tv.dart';
import 'package:bilifast/space/fake_space_api.dart';
import 'package:bilifast/space/space_page.dart';
import 'package:bilifast/space/uploader_tap.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../home/fake_login_gate.dart';
import '../playback/fakes.dart';

const _mid = 4242;

const _tabs = [
  SpaceTab(kind: SpaceTabKind.home, title: '主页'),
  SpaceTab(kind: SpaceTabKind.dynamic, title: '动态'),
  SpaceTab(kind: SpaceTabKind.contribute, title: '投稿'),
];

SpaceProfile _profile({
  List<SpaceTab> tabs = _tabs,
  SpaceTabKind defaultTab = SpaceTabKind.contribute,
  String? banner,
  bool chargeable = true,
}) => SpaceProfile(
  mid: _mid,
  name: '演示UP主',
  face: '',
  sign: '一句简介',
  level: 6,
  fans: 178000,
  following: 18,
  likes: 2841000,
  banner: banner,
  tagLines: const [SpaceTagLine(text: 'IP属地：广东'), SpaceTagLine(text: '某某大学', link: true)],
  entries: const [
    SpaceEntry(kind: SpaceEntryKind.shop, title: '小店', note: '1件商品'),
    SpaceEntry(kind: SpaceEntryKind.charge, title: '充电', note: '5人充电'),
  ],
  chargeable: chargeable,
  tabs: tabs,
  defaultTab: defaultTab,
);

UploaderCard _card({bool following = false}) =>
    UploaderCard(mid: _mid, name: '演示UP主', face: '', fans: 1, videos: 1, isVip: false, following: following);

class _Harness {
  _Harness(this.spaceApi, this.pageApi, this.gate, this.services);

  final FakeSpaceApi spaceApi;
  final FakePageApi pageApi;
  final FakeLoginGate gate;
  final AppServices services;
}

void main() {
  final navigator = GlobalKey<NavigatorState>();
  final logger = Logger(session: 'test')..add(MemorySink());

  Finder key(String value) => find.byKey(ValueKey(value));

  Future<void> frames(WidgetTester tester, [int count = 10]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// The space pushed over a home screen at the iPhone's size; [hold] keeps the profile's call waiting.
  Future<_Harness> show(
    WidgetTester tester, {
    SpaceProfile? profile,
    bool loggedIn = true,
    bool following = false,
    bool hold = false,
    Object? failure,
  }) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: 62, bottom: 34)
      ..viewPadding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: Canned.http(loggedIn: loggedIn),
      logger: logger,
    );
    if (loggedIn) {
      environment.useFakeAccount();
    } else {
      await environment.refreshAccount();
    }
    final playback = AppPlayback(() => Completer<PlaybackController>().future);
    addTearDown(playback.dispose);
    final spaceApi = FakeSpaceApi(profileFor: (_) => profile ?? _profile());
    if (hold) spaceApi.holds['profile'] = Completer<void>();
    if (failure != null) spaceApi.failures['profile'] = failure;
    final pageApi = FakePageApi(uploader: _card(following: following));
    final gate = FakeLoginGate();
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      pageApi: pageApi,
      spaceApi: spaceApi,
      loginGate: gate,
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => AppScope(services: services, child: child!),
        home: const Text('home'),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        SwipeBackPageRoute<void>(
          builder: (_) => const SpacePage(uploader: UploaderRef(mid: _mid, name: '演示UP主', face: '')),
        ),
      ),
    );
    if (hold || failure != null) {
      await frames(tester);
    } else {
      await tester.pumpAndSettle();
    }
    return _Harness(spaceApi, pageApi, gate, services);
  }

  /// [message] is up as a toast; then it is waited out, so no timer outlives the test.
  Future<void> expectToast(WidgetTester tester, String message) async {
    expect(find.descendant(of: key('toast'), matching: find.text(message)), findsOneWidget);
    // In frames: the fade has to finish before the toast's own two seconds start.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(key('toast'), findsNothing);
  }

  double barOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(find.ancestor(of: key('space-bar'), matching: find.byType(AnimatedOpacity)).first)
      .opacity;

  SystemUiOverlayStyle statusStyle(WidgetTester tester) => tester
      .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.descendant(of: find.byType(SpacePage), matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>)),
      )
      .value;

  testWidgets('the loading TV under the tapped face and name, then the header', (tester) async {
    final harness = await show(tester, hold: true);
    expect(find.byType(LoadingTvState), findsOneWidget);
    expect(find.descendant(of: key('space-loading-title'), matching: find.text('演示UP主')), findsOneWidget);
    expect(key('space-header'), findsNothing);
    expect(harness.spaceApi.calls, ['profile mid=$_mid']);

    harness.spaceApi.holds['profile']!.complete();
    await frames(tester);
    expect(find.byType(LoadingTvState), findsNothing);
    expect(key('space-header'), findsOneWidget);
    expect(find.text('17.8万'), findsOneWidget);
    expect(find.text('粉丝'), findsOneWidget);
    expect(find.text('284.1万'), findsOneWidget);
    expect(key('space-follow'), findsOneWidget);
    expect(key('space-charge'), findsOneWidget, reason: 'the uploader takes 充电');
    expect(key('space-loading-title'), findsNothing);
  });

  testWidgets('a failed load offers a retry, which loads the space', (tester) async {
    final harness = await show(tester, failure: const BiliError.http(500));
    expect(key('space-retry'), findsOneWidget);
    expect(find.byType(LoadingTvState), findsNothing);

    harness.spaceApi.failures.remove('profile');
    await tester.tap(key('space-retry'));
    await frames(tester);
    expect(key('space-retry'), findsNothing);
    expect(key('space-header'), findsOneWidget);
    expect(harness.spaceApi.calls, ['profile mid=$_mid', 'profile mid=$_mid']);
  });

  testWidgets('+ 关注 follows at once, toasts 关注成功 and shows 已关注 with ▽', (tester) async {
    final harness = await show(tester);
    expect(harness.pageApi.calls, contains('uploaderCard mid=$_mid'));
    await tester.tap(key('space-follow'));
    await frames(tester);
    expect(harness.pageApi.calls, contains('follow on=true'));
    expect(key('space-followed'), findsOneWidget);
    expect(key('space-follow-more'), findsOneWidget);
    expect(key('space-follow'), findsNothing);
    expect(harness.services.follows.last, (mid: _mid, following: true));
    await expectToast(tester, '关注成功');
  });

  testWidgets('已关注 opens the sheet; 取消关注 unfollows and toasts 取消关注成功', (tester) async {
    final harness = await show(tester, following: true);
    expect(key('space-followed'), findsOneWidget);
    await tester.tap(key('space-followed'));
    await tester.pumpAndSettle();
    expect(key('space-sheet'), findsOneWidget);
    for (final label in ['加入特别关注', '设置分组', '取消关注', '取消']) {
      expect(find.descendant(of: key('space-sheet'), matching: find.text(label)), findsOneWidget);
    }
    expect(harness.pageApi.calls, isNot(contains('follow on=false')), reason: 'opening the sheet changes nothing');

    await tester.tap(key('space-sheet-unfollow'));
    await tester.pump();
    expect(harness.pageApi.calls, contains('follow on=false'));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(key('space-sheet'), findsNothing);
    expect(key('space-follow'), findsOneWidget);
    await expectToast(tester, '取消关注成功');
  });

  testWidgets('取消, the dim and back close the sheet without unfollowing', (tester) async {
    final harness = await show(tester, following: true);
    for (final close in ['space-sheet-cancel', 'space-sheet-dim', 'back']) {
      await tester.tap(key('space-followed'));
      await tester.pumpAndSettle();
      expect(key('space-sheet'), findsOneWidget);
      if (close == 'back') {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tapAt(tester.getTopLeft(key(close)) + const Offset(20, 20));
      }
      await tester.pumpAndSettle();
      expect(key('space-sheet'), findsNothing, reason: close);
      expect(find.byType(SpacePage), findsOneWidget, reason: '$close leaves the page up');
    }
    expect(harness.pageApi.calls, isNot(contains('follow on=false')));
  });

  testWidgets('logged out, + 关注 asks for the login and calls nothing', (tester) async {
    final harness = await show(tester, loggedIn: false);
    expect(harness.pageApi.calls, isEmpty, reason: 'logged out the card is not asked');
    await tester.tap(key('space-follow'));
    await frames(tester);
    expect(harness.gate.requests, 1);
    expect(harness.pageApi.calls, isEmpty);
    expect(key('space-follow'), findsOneWidget);
  });

  testWidgets('a 关注 made on another page shows here', (tester) async {
    final harness = await show(tester);
    expect(key('space-follow'), findsOneWidget);
    harness.services.follows.changed(_mid, following: true);
    await tester.pump();
    expect(key('space-followed'), findsOneWidget);
    harness.services.follows.changed(_mid + 1, following: false);
    await tester.pump();
    expect(key('space-followed'), findsOneWidget, reason: 'another uploader');
    harness.services.follows.changed(_mid, following: false);
    await tester.pump();
    expect(key('space-follow'), findsOneWidget);
  });

  testWidgets('past the name the white bar comes in; scrolled on, the tabs pin under it', (tester) async {
    await show(tester);
    expect(barOpacity(tester), 0);
    expect(statusStyle(tester), SystemUiOverlayStyle.dark, reason: 'over the light default banner');
    final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;

    // The name's line centres 292.5 down; the bar waits until it is under the 62 pt status bar.
    position.jumpTo(292.5 - 62 - 1);
    await tester.pumpAndSettle();
    expect(barOpacity(tester), 0);
    position.jumpTo(292.5 - 62 + 1);
    await tester.pumpAndSettle();
    expect(barOpacity(tester), 1);
    expect(key('space-pill'), findsOneWidget);

    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.getRect(key('space-tabs')).top, moreOrLessEquals(62 + 32));
    expect(tester.getRect(key('space-bar')).bottom, 62 + 32);
    expect(statusStyle(tester), SystemUiOverlayStyle.dark);

    // The bar's pill follows like the header's button.
    await tester.tap(key('space-pill'));
    await frames(tester);
    expect(find.descendant(of: key('space-pill'), matching: find.text('已关注')), findsOneWidget);
    await expectToast(tester, '关注成功');

    position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(barOpacity(tester), 0);
  });

  testWidgets('a picture banner has the status bar light until the bar comes in', (tester) async {
    await show(tester, profile: _profile(banner: 'https://i0.hdslb.com/bfs/space/banner.png'));
    expect(statusStyle(tester), SystemUiOverlayStyle.light);
    final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(statusStyle(tester), SystemUiOverlayStyle.dark);
  });

  testWidgets('a pull past the top stretches the banner', (tester) async {
    await show(tester);
    final banner = tester.getRect(key('space-banner-default'));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 120));
    await tester.pump();
    final pulled = tester.getRect(key('space-banner-default'));
    expect(pulled.top, banner.top);
    expect(pulled.height, greaterThan(banner.height + 40));
    await tester.pumpAndSettle();
    expect(tester.getRect(key('space-banner-default')), banner);
  });

  testWidgets('tabs other than 投稿 toast and stay unselected', (tester) async {
    await show(tester);
    for (final kind in ['home', 'dynamic']) {
      await tester.tap(key('space-tab-$kind'));
      await tester.pump();
      await expectToast(tester, '暂未开放');
      expect(tester.getSemantics(key('space-tab-$kind')), isSemantics(hasSelectedState: true, isSelected: false));
    }
    expect(tester.getSemantics(key('space-tab-contribute')), isSemantics(hasSelectedState: true, isSelected: true));
    await tester.tap(key('space-tab-contribute'));
    await tester.pump();
    expect(key('toast'), findsNothing);
  });

  testWidgets('a space opening on 主页 still shows 投稿', (tester) async {
    await show(tester, profile: _profile(defaultTab: SpaceTabKind.home));
    expect(tester.getSemantics(key('space-tab-contribute')), isSemantics(hasSelectedState: true, isSelected: true));
    expect(tester.getSemantics(key('space-tab-home')), isSemantics(hasSelectedState: true, isSelected: false));
    final indicator = tester.getRect(key('space-tab-indicator'));
    expect(indicator.center.dx, moreOrLessEquals(tester.getRect(key('space-tab-contribute')).center.dx));
  });

  testWidgets('a space whose tabs have no 投稿 shows one, selected', (tester) async {
    await show(
      tester,
      profile: _profile(tabs: const [SpaceTab(kind: SpaceTabKind.home, title: '主页')]),
    );
    expect(find.descendant(of: key('space-tabs'), matching: find.text('投稿')), findsOneWidget);
    expect(tester.getSemantics(key('space-tab-contribute')), isSemantics(hasSelectedState: true, isSelected: true));
  });

  testWidgets('私信, search, ⋮, 详情, 充电, the cards and link tags toast 暂未开放', (tester) async {
    await show(tester);
    for (final target in [
      'space-chat',
      'space-search',
      'space-more',
      'space-detail',
      'space-charge',
      'space-entry-shop',
      'space-entry-charge',
    ]) {
      await tester.tap(key(target));
      await tester.pump();
      await expectToast(tester, '暂未开放');
    }
    await tester.tap(find.text('某某大学'));
    await tester.pump();
    await expectToast(tester, '暂未开放');
  });

  testWidgets('▽ and the sheet\'s 加入特别关注 and 设置分组 toast 暂未开放', (tester) async {
    final harness = await show(tester, following: true);
    await tester.tap(key('space-follow-more'));
    await tester.pump();
    await expectToast(tester, '暂未开放');
    for (final row in ['space-sheet-special', 'space-sheet-group']) {
      await tester.tap(key('space-followed'));
      await tester.pumpAndSettle();
      await tester.tap(key(row));
      await tester.pump();
      await expectToast(tester, '暂未开放');
      await tester.pumpAndSettle();
      expect(key('space-sheet'), findsNothing);
    }
    expect(harness.pageApi.calls, isNot(contains('follow on=false')));
  });

  testWidgets('〈 goes back', (tester) async {
    await show(tester);
    await tester.tap(key('space-back'));
    await tester.pumpAndSettle();
    expect(find.byType(SpacePage), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('〈 goes back while the space loads too', (tester) async {
    final harness = await show(tester, hold: true);
    await tester.tap(key('space-back'));
    await frames(tester, 20);
    expect(find.byType(SpacePage), findsNothing);
    harness.spaceApi.holds['profile']!.complete();
    await frames(tester);
  });
}
