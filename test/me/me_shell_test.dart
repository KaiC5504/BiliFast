import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/home_tab_bar.dart';
import 'package:bilifast/home/main_shell.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/me/fake_me_api.dart';
import 'package:bilifast/search/fake_search_api.dart';
import 'package:bilifast/settings/font_store.dart';
import 'package:bilifast/settings/settings_page.dart';
import 'package:bilifast/shared/loading_tv.dart';
import 'package:bilifast/space/fake_space_api.dart';
import 'package:bilifast/space/space_page.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../home/fake_login_gate.dart';
import '../home/feed_fakes.dart';
import '../playback/fakes.dart';
import '../video/mixed_lines.dart';

const _loggedOutCookies = {'buvid3': 'b3', 'buvid4': 'b4'};

/// Logs in as the login page would: Bilibili sets SESSDATA, then didLogin.
final class _LoginByPage implements LoginGate {
  _LoginByPage(this.http);

  final FeedHttp http;
  late AppEnvironment environment;
  int requests = 0;

  @override
  Future<bool> request(BuildContext context) async {
    requests++;
    http.canned.routes[Canned.navPath] = (200, Canned.navLoggedIn);
    return environment.didLogin({'SESSDATA': 's', 'bili_jct': 'j'});
  }
}

/// 我的 in the real shell, on the real model and environment, over fake calls.
void main() {
  late FeedHttp http;
  late FakeMeApi me;
  late AppEnvironment environment;

  setUp(() {
    http = FeedHttp()..pages[1] = [for (var i = 0; i < 20; i++) feedItem('BV1c$i')];
    me = FakeMeApi.demo();
  });

  Future<void> show(WidgetTester tester, {Map<String, String> cookies = Canned.cookies, LoginGate? gate}) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: 62, bottom: 34)
      ..viewPadding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    final logger = Logger(session: 'test');
    environment = await AppEnvironment.load(keychain: FakeKeychain(StoredCookies(cookies)), http: http, logger: logger);
    if (gate is _LoginByPage) gate.environment = environment;
    await environment.refreshAccount();
    final playback = AppPlayback(() => throw StateError('no playback here'));
    addTearDown(playback.dispose);
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      fonts: FontStore.memory(),
      searchApi: FakeSearchApi(defaultWord: 'w'),
      meApi: me,
      pageApi: FakePageApi(),
      spaceApi: FakeSpaceApi(),
      loginGate: gate ?? FakeLoginGate(),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => AppScope(services: services, child: child!),
        home: const MainShell(),
      ),
    );
  }

  Future<void> settle(WidgetTester tester, [int frames = 10]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> openMine(WidgetTester tester) async {
    await tester.tap(find.byKey(ValueKey('home-tab-${HomeTab.mine.name}')));
    await tester.pump();
  }

  /// Past the trigger at about 1500 px/s, held.
  Future<TestGesture> pullAndHold(WidgetTester tester, Finder list) async {
    final finger = await tester.startGesture(tester.getCenter(list));
    for (var i = 0; i < 12; i++) {
      await finger.moveBy(const Offset(0, 25));
      await tester.pump(const Duration(microseconds: 16667));
    }
    return finger;
  }

  final meList = find.byKey(const ValueKey('me-list'));

  testWidgets('a pull on 我的 while the showing\'s load is out joins it: no second nav, the TV until it lands', (
    tester,
  ) async {
    final hold = me.holds['nav'] = Completer<void>();
    await show(tester);
    await settle(tester, 40);
    await openMine(tester);
    await settle(tester, 4);
    expect(me.calls, unorderedEquals(['nav', 'stat']));
    expect(find.text('测试账号'), findsNothing, reason: 'still loading');

    final finger = await pullAndHold(tester, meList);
    await finger.up();
    await settle(tester, 20);
    expect(me.calls, hasLength(2), reason: 'joined');
    expect(find.descendant(of: meList, matching: find.byType(LoadingTv)), findsOneWidget, reason: 'the gap holds');

    hold.complete();
    await settle(tester, 30);
    expect(find.text('测试账号'), findsOneWidget);
    expect(find.byType(LoadingTv), findsNothing);
    expect(me.calls, hasLength(2));
  });

  testWidgets('点击登录 on 我的 logs in and the page turns to the account with one load', (tester) async {
    http.canned.routes[Canned.navPath] = (200, Canned.navLoggedOut);
    final gate = _LoginByPage(http);
    await show(tester, cookies: _loggedOutCookies, gate: gate);
    await settle(tester, 20);
    expect(environment.account, isA<LoggedOut>());
    await openMine(tester);
    await settle(tester, 10);
    expect(find.text('点击登录'), findsOneWidget);
    expect(me.calls, isEmpty);

    await tester.tap(find.byKey(const ValueKey('me-login')));
    await settle(tester, 40);
    expect(gate.requests, 1);
    expect(environment.account, isA<LoggedIn>());
    expect(find.text('点击登录'), findsNothing);
    expect(find.text('测试账号'), findsOneWidget);
    expect(me.calls, unorderedEquals(['nav', 'stat']), reason: 'one load for the login');
  });

  testWidgets('我的 → 设置 → 退出登录 → 确定 lands back on 我的, logged out', (tester) async {
    await show(tester);
    await settle(tester, 40);
    await openMine(tester);
    await settle(tester, 20);
    expect(find.text('测试账号'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('me-settings')));
    await settle(tester, 20);
    expect(find.byType(SettingsPage), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('settings-logout')));
    await settle(tester, 10);
    await tester.tap(find.byKey(const ValueKey('settings-logout')));
    await settle(tester, 10);
    await tester.tap(find.byKey(const ValueKey('settings-confirm-确定')));
    await settle(tester, 40);

    expect(environment.account, isA<LoggedOut>());
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.text('点击登录'), findsOneWidget);
    expect(find.text('测试账号'), findsNothing);
    await settle(tester, 60);
  });

  testWidgets('the avatar on 我的 opens the account\'s own space (mid 1)', (tester) async {
    await show(tester);
    await settle(tester, 40);
    await openMine(tester);
    await settle(tester, 20);
    await tester.tap(find.byKey(const ValueKey('me-avatar')));
    await settle(tester, 20);
    expect(tester.widget<SpacePage>(find.byType(SpacePage)).uploader.mid, 1);
  });

  testWidgets('a failed first load on 我的 toasts its reason, and a pull on it says it again', (tester) async {
    me.failures['nav'] = const BiliError.network('SocketException');
    await show(tester);
    await settle(tester, 40);
    await openMine(tester);
    await settle(tester, 4);
    expect(find.text('测试账号'), findsNothing);
    final reason = find.text('网络连接失败，请检查网络后重试');
    expect(reason, findsOneWidget);
    await settle(tester, 80);
    expect(reason, findsNothing);

    final finger = await pullAndHold(tester, meList);
    await finger.up();
    await settle(tester, 10);
    expect(reason, findsOneWidget);
    expect(me.calls.where((call) => call == 'nav'), hasLength(2));
    await settle(tester, 80);
  });

  testWidgets('a login whose 我的 load fails behind 首页 toasts nothing there; showing 我的 retries and says why', (
    tester,
  ) async {
    me.failures['nav'] = const BiliError.network('SocketException');
    await show(tester, cookies: _loggedOutCookies);
    await settle(tester, 40);
    http.canned.routes[Canned.navPath] = (200, Canned.navLoggedIn);
    await environment.didLogin({'SESSDATA': 's', 'bili_jct': 'j'});
    await settle(tester, 10);
    final reason = find.text('网络连接失败，请检查网络后重试');
    expect(me.calls.where((call) => call == 'nav'), hasLength(1), reason: 'the login loads 我的 at once');
    expect(reason, findsNothing, reason: '首页 is in front');

    await openMine(tester);
    await settle(tester, 4);
    expect(me.calls.where((call) => call == 'nav'), hasLength(2), reason: 'a failed page retries inside the gap');
    expect(reason, findsOneWidget);
    await settle(tester, 80);
  });
}
