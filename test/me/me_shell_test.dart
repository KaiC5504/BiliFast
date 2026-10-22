import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/route_observer.dart';
import 'package:bilifast/home/home_tab_bar.dart';
import 'package:bilifast/home/main_shell.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/me/fake_me_api.dart';
import 'package:bilifast/me/me_model.dart';
import 'package:bilifast/me/me_profile_store.dart';
import 'package:bilifast/search/fake_search_api.dart';
import 'package:bilifast/settings/font_store.dart';
import 'package:bilifast/settings/settings_page.dart';
import 'package:bilifast/shared/loading_tv.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:bilifast/space/fake_space_api.dart';
import 'package:bilifast/space/own/own_space_page.dart';
import 'package:bilifast/space/space_page.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../home/fake_login_gate.dart';
import '../home/feed_fakes.dart';
import '../playback/fakes.dart';
import '../shared/stored_pictures.dart';
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
  late AppServices services;

  setUp(() {
    http = FeedHttp()..pages[1] = [for (var i = 0; i < 20; i++) feedItem('BV1c$i')];
    me = FakeMeApi.demo();
  });

  /// [checked] false leaves the launch's account check unasked, as on a phone whose check is still out.
  Future<void> show(
    WidgetTester tester, {
    Map<String, String> cookies = Canned.cookies,
    LoginGate? gate,
    MeProfileStore? kept,
    bool checked = true,
  }) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: 62, bottom: 34)
      ..viewPadding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    final logger = Logger(session: 'test');
    environment = await AppEnvironment.load(keychain: FakeKeychain(StoredCookies(cookies)), http: http, logger: logger);
    if (gate is _LoginByPage) gate.environment = environment;
    if (checked) await environment.refreshAccount();
    final playback = AppPlayback(() => throw StateError('no playback here'));
    addTearDown(playback.dispose);
    services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      fonts: FontStore.memory(),
      searchApi: FakeSearchApi(defaultWord: 'w'),
      meApi: me,
      pageApi: FakePageApi(),
      spaceApi: FakeSpaceApi(),
      loginGate: gate ?? FakeLoginGate(),
      meProfile: kept,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        navigatorObservers: [pageRoutes],
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
    expect(services.meProfile.kept?.view.profile.name, '测试账号');

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
    expect(services.meProfile.kept, isNull, reason: 'the logout deletes the kept account');
    await settle(tester, 60);
  });

  testWidgets('the avatar on 我的 opens the account\'s own space (mid 1)', (tester) async {
    // The login's mid is 我的's, so the space is the account's own.
    http.canned.routes[Canned.navPath] = (200, Canned.navLoggedIn.replaceFirst('"mid":12345', '"mid":1'));
    await show(tester);
    await settle(tester, 40);
    await openMine(tester);
    await settle(tester, 20);
    await tester.tap(find.byKey(const ValueKey('me-avatar')));
    await settle(tester, 20);
    expect(tester.widget<OwnSpacePage>(find.byType(OwnSpacePage)).uploader.mid, 1);
    expect(find.byType(SpacePage), findsNothing);
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

  group('at launch', () {
    const keptName = '上次的名字';
    const kept = MeShown(
      MeProfile(
        mid: 12345,
        name: keptName,
        face: 'https://i0.hdslb.com/bfs/face/kept.jpg',
        pendant: 'https://i2.hdslb.com/bfs/garb/item/kept-frame.png',
        level: 6,
        coins: 100,
        bcoin: 0,
      ),
      MeCounts(dynamics: 1, following: 2, followers: 3),
    );
    const loginCookies = {...Canned.cookies, 'DedeUserID': '12345'};
    // Canned's account with a frame on.
    final navWithFrame = Canned.navLoggedIn.replaceFirst(
      '"vipStatus"',
      '"pendant":{"image":"https://i2.hdslb.com/bfs/garb/item/frame.png"},"vipStatus"',
    );

    Finder inAvatar(Finder matching) => find.descendant(of: find.byKey(const ValueKey('me-avatar')), matching: matching);

    /// The face and frame drawn whole the frame 我的 opens: pictures in, no default face, nothing fading.
    void expectDrawnAtOnce(WidgetTester tester) {
      expect(inAvatar(find.byKey(const ValueKey('default-avatar'))), findsNothing);
      expect(inAvatar(find.byKey(const ValueKey('me-avatar-blank'))), findsNothing);
      final face = inAvatar(find.byType(RemoteImage));
      expect(face, findsOneWidget);
      expect(tester.widget<RawImage>(find.descendant(of: face, matching: find.byType(RawImage))).image, isNotNull);
      expect(find.descendant(of: face, matching: find.byType(AnimatedOpacity)), findsNothing, reason: 'no fade');
      final frame = find.byKey(const ValueKey('me-pendant'));
      expect(tester.widget<RawImage>(find.descendant(of: frame, matching: find.byType(RawImage))).image, isNotNull);
      expect(find.descendant(of: frame, matching: find.byType(AnimatedOpacity)), findsNothing, reason: 'no fade');
    }

    testWidgets('the kept account is there the moment 我的 opens, before any answer; the load then replaces it', (
      tester,
    ) async {
      final hold = me.holds['nav'] = Completer<void>();
      await show(tester, cookies: loginCookies, checked: false, kept: MeProfileStore.memory()..save(12345, kept));
      await openMine(tester);
      expect(find.text(keptName), findsOneWidget);
      expect(find.byKey(const ValueKey('me-avatar-blank')), findsNothing);
      expect(me.calls, unorderedEquals(['nav', 'stat']), reason: 'the showing still loads');

      hold.complete();
      await settle(tester, 10);
      expect(find.text(keptName), findsNothing);
      expect(find.text('测试账号'), findsOneWidget);
      expect(services.meProfile.kept?.view.profile.name, '测试账号');
    });

    testWidgets('logged out, the kept account never shows', (tester) async {
      http.canned.routes[Canned.navPath] = (200, Canned.navLoggedOut);
      final store = MeProfileStore.memory()..save(12345, kept);
      await show(tester, cookies: _loggedOutCookies, kept: store);
      await openMine(tester);
      expect(find.text(keptName), findsNothing);
      expect(find.text('点击登录'), findsOneWidget);
      expect(store.kept, isNull);
    });

    testWidgets('hidden, 我的 loads once about 3 s in, stat only after the fresh account check; opening it asks nothing', (
      tester,
    ) async {
      await show(tester);
      await settle(tester, 58);
      expect(me.calls, isEmpty, reason: '推荐 and playback go first');
      await settle(tester, 4);
      expect(me.calls, ['stat'], reason: 'the account check answered nav just now');

      await settle(tester, 100);
      expect(me.calls, ['stat'], reason: 'once');
      await openMine(tester);
      await settle(tester, 10);
      expect(me.calls, ['stat'], reason: 'opening within 30 s asks nothing');
      expect(find.text('测试用户'), findsOneWidget, reason: "the account check's account");
      expect(services.meProfile.kept?.view.profile.name, '测试用户');

      final finger = await pullAndHold(tester, meList);
      await finger.up();
      await settle(tester, 30);
      expect(me.calls, unorderedEquals(['stat', 'nav', 'stat']), reason: 'a pull asks both');
    });

    testWidgets('logged out, the background load asks nothing', (tester) async {
      http.canned.routes[Canned.navPath] = (200, Canned.navLoggedOut);
      await show(tester, cookies: _loggedOutCookies);
      await settle(tester, 100);
      expect(me.calls, isEmpty);
    });

    testWidgets('a page over the shell holds the background load until 3 s after it leaves', (tester) async {
      await show(tester);
      await settle(tester, 20);
      final navigator = Navigator.of(tester.element(find.byType(MainShell)));
      unawaited(navigator.push(MaterialPageRoute<void>(builder: (_) => const ColoredBox(color: Color(0xFFFFFFFF)))));
      await settle(tester, 80);
      expect(me.calls, isEmpty);

      navigator.pop();
      await settle(tester, 50);
      expect(me.calls, isEmpty);
      await settle(tester, 20);
      expect(me.calls, ['stat']);
    });

    testWidgets('after the background load, 我的 opens with the face and frame drawn on its first frame', (tester) async {
      final pictures = await StoredPictures.keep(tester);
      http.canned.routes[Canned.navPath] = (200, navWithFrame);
      await show(tester);
      await settle(tester, 64);
      expect(me.calls, ['stat']);
      await StoredPictures.arrive(tester);
      expect(
        pictures.downloads.where((url) => url.contains('/bfs/face/test.jpg') || url.contains('/garb/item/frame.png')),
        hasLength(2),
        reason: 'both downloaded while 我的 was hidden',
      );

      await openMine(tester);
      expectDrawnAtOnce(tester);
      await pictures.drop(tester);
    });

    testWidgets('with the kept account, the face and frame are ready the moment 我的 first opens', (tester) async {
      final pictures = await StoredPictures.keep(tester);
      me.holds['nav'] = Completer<void>();
      await show(tester, cookies: loginCookies, checked: false, kept: MeProfileStore.memory()..save(12345, kept));
      await StoredPictures.arrive(tester);
      expect(me.calls, isEmpty);

      await openMine(tester);
      expectDrawnAtOnce(tester);
      expect(find.text(keptName), findsOneWidget);
      await pictures.drop(tester);
    });
  });
}
