import 'dart:async';
import 'dart:io' show SocketException;

import 'package:bili_core/api.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/swipe_back_route.dart';
import 'package:bilifast/dynamic/fake_dynamic_api.dart';
import 'package:bilifast/dynamic/following/following_page.dart';
import 'package:bilifast/shared/loading_tv.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/skin/skin.dart';
import 'package:bilifast/space/space_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../playback/fakes.dart' show Canned;
import 'following_support.dart';

Finder _key(String key) => find.byKey(ValueKey(key));

/// Opens 我的关注 over [api], with [services] made for it when given.
Future<FakeDynamicApi> _open(
  WidgetTester tester,
  FakeDynamicApi api, {
  bool loggedIn = true,
  AppServices? services,
}) async {
  tester.view
    ..physicalSize = const Size(440, 956)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpFollowingApp(tester, services ?? await followingServices(api: api, loggedIn: loggedIn));
  await tester.tap(_key('open-following'));
  await settle(tester);
  return api;
}

int _count(FakeDynamicApi api, String prefix) => api.calls.where((call) => call.startsWith(prefix)).length;

/// Counts the requests and runs [login] as the login page would before answering yes.
final class _LoggingInGate implements LoginGate {
  int requests = 0;
  VoidCallback? login;

  @override
  Future<bool> request(BuildContext context) async {
    requests++;
    login?.call();
    return true;
  }
}

void main() {
  testWidgets('opens on the app’s plain route, and ‹ goes back', (tester) async {
    await _open(tester, FakeDynamicApi(following: followingUsers(3)));
    expect(find.byType(FollowingListPage), findsOneWidget);
    expect(ModalRoute.of(tester.element(find.byType(FollowingListPage))), isA<SwipeBackPageRoute<void>>());
    expect(find.text('我的关注'), findsOneWidget);
    expect(find.text('搜索我的关注'), findsOneWidget);

    await tester.tap(_key('following-back'));
    await settle(tester);
    expect(find.byType(FollowingListPage), findsNothing);
  });

  testWidgets('the TV while the first page loads, then the rows with pink names and verified badges', (tester) async {
    final api = FakeDynamicApi(
      following: [
        followingUser(1, name: '粉色名字', vipPink: true, verify: DynamicVerify.personal),
        followingUser(2, name: '普通名字', verify: DynamicVerify.organisation),
        followingUser(3, name: '无认证'),
      ],
    );
    final hold = api.holds['followings'] = Completer<void>();
    await _open(tester, api);
    expect(find.byType(LoadingTvState), findsOneWidget);
    expect(_key('following-row-1'), findsNothing);

    api.holds.remove('followings');
    hold.complete();
    await settle(tester);
    expect(find.byType(LoadingTvState), findsNothing);
    expect(tester.widget<Text>(_key('following-name-1')).style?.color, FollowingListTheme.vipName);
    expect(tester.widget<Text>(_key('following-name-2')).style?.color, FollowingListTheme.name);
    expect(_key('following-verified-1'), findsOneWidget);
    expect(_key('following-verified-2'), findsOneWidget);
    expect(_key('following-verified-3'), findsNothing);
    expect(api.calls, ['followings recommended page=1', 'ups offset=']);
  });

  testWidgets('pink dots on the people the ups call says have new posts', (tester) async {
    final api = FakeDynamicApi(
      following: followingUsers(4),
      upList: const [
        DynamicUp(mid: 2, name: '', face: '', hasUpdate: true),
        DynamicUp(mid: 3, name: '', face: ''),
        DynamicUp(mid: 4, name: '', face: '', hasUpdate: true),
      ],
    );
    await _open(tester, api);
    expect(_key('following-dot-1'), findsNothing);
    expect(_key('following-dot-2'), findsOneWidget);
    expect(_key('following-dot-3'), findsNothing);
    expect(_key('following-dot-4'), findsOneWidget);
    expect(_count(api, 'ups'), 1);
  });

  testWidgets('pages on near the end, the small spinner while the next page loads', (tester) async {
    final api = FakeDynamicApi(following: followingUsers(45));
    await _open(tester, api);
    expect(_count(api, 'followings'), 1);

    final hold = api.holds['followings'] = Completer<void>();
    await tester.drag(_key('following-list'), const Offset(0, -900));
    await tester.pump();
    expect(api.calls.last, 'followings recommended page=2');
    await tester.pump();
    expect(_key('following-more-spinner'), findsOneWidget);

    api.holds.remove('followings');
    hold.complete();
    await settle(tester);
    expect(_key('following-more-spinner'), findsNothing);
    await tester.drag(_key('following-list'), const Offset(0, -1500));
    await settle(tester);
    await tester.drag(_key('following-list'), const Offset(0, -1500));
    await settle(tester);
    expect(api.calls.where((call) => call.startsWith('followings')), [
      'followings recommended page=1',
      'followings recommended page=2',
      'followings recommended page=3',
    ]);
    expect(_key('following-row-45'), findsOneWidget);
  });

  testWidgets('a failed page says so with 重试, and 重试 loads it', (tester) async {
    final api = FakeDynamicApi(following: followingUsers(3))
      ..failures['followings'] = const BiliError.api(code: -500, message: '服务器开小差了');
    await _open(tester, api);
    expect(_key('following-failed'), findsOneWidget);
    expect(find.text('B 站返回错误 -500：服务器开小差了'), findsOneWidget);

    api.failures.remove('followings');
    await tester.tap(_key('following-retry'));
    await settle(tester);
    expect(_key('following-failed'), findsNothing);
    expect(_key('following-row-3'), findsOneWidget);
  });

  testWidgets('a failed next page leaves 加载失败，点击重试 under the rows', (tester) async {
    final api = FakeDynamicApi(following: followingUsers(30));
    await _open(tester, api);
    api.failures['followings'] = const BiliError.api(code: -500, message: '服务器开小差了');
    await tester.drag(_key('following-list'), const Offset(0, -900));
    await settle(tester);
    expect(_key('following-footer-retry'), findsOneWidget);

    api.failures.remove('followings');
    await tester.tap(_key('following-footer-retry'));
    await settle(tester);
    expect(_key('following-footer-retry'), findsNothing);
    await tester.drag(_key('following-list'), const Offset(0, -900));
    await settle(tester);
    expect(_key('following-row-30'), findsOneWidget);
  });

  testWidgets('the sort menu opens under 排序方式, picks an order, and closes on a tap outside', (tester) async {
    final api = FakeDynamicApi(following: followingUsers(25));
    await _open(tester, api);
    expect(find.text('推荐排序'), findsOneWidget);
    expect(_key('following-sort-down'), findsOneWidget);

    await tester.tap(_key('following-sort'));
    await settle(tester);
    expect(_key('following-menu'), findsOneWidget);
    expect(_key('following-sort-up'), findsOneWidget);
    expect(find.text('最常访问'), findsOneWidget);
    expect(find.text('最近关注'), findsOneWidget);
    // ✓ sits 2/3 under its row's middle, the hairline counted in the first row.
    double rowMiddle(String order) => tester.getRect(_key('following-order-$order')).bottom - 20;
    expect(tester.getCenter(_key('following-order-check')).dy, closeTo(rowMiddle('recommended') + 2 / 3, 0.01));

    // The dimmed page below the menu closes it.
    await tester.tapAt(const Offset(220, 700));
    await settle(tester);
    expect(_key('following-menu'), findsNothing);
    expect(_count(api, 'followings'), 1);

    // So does anywhere above it, and ▽ itself.
    await tester.tap(_key('following-sort'));
    await settle(tester);
    await tester.tapAt(const Offset(220, 140));
    await settle(tester);
    expect(_key('following-menu'), findsNothing);
    await tester.tap(_key('following-sort'));
    await settle(tester);
    await tester.tap(_key('following-sort'), warnIfMissed: false);
    await settle(tester);
    expect(_key('following-menu'), findsNothing);

    await tester.tap(_key('following-sort'));
    await settle(tester);
    await tester.tap(_key('following-order-recent'));
    await settle(tester);
    expect(_key('following-menu'), findsNothing);
    expect(api.calls.last, 'followings recent page=1');
    expect(tester.widget<Text>(_key('following-sort-value')).data, '最近关注');
    // 最近关注 answers newest first.
    expect(tester.getTopLeft(_key('following-row-25')).dy, tester.getRect(_key('following-sort')).bottom);

    // The chosen order picked again changes nothing; 最常访问 reloads.
    await tester.tap(_key('following-sort'));
    await settle(tester);
    expect(tester.getCenter(_key('following-order-check')).dy, closeTo(rowMiddle('recent') + 2 / 3, 0.01));
    await tester.tap(_key('following-order-recent'));
    await settle(tester);
    expect(_count(api, 'followings'), 2);
    await tester.tap(_key('following-sort'));
    await settle(tester);
    await tester.tap(_key('following-order-mostVisited'));
    await settle(tester);
    expect(api.calls.last, 'followings mostVisited page=1');
    expect(tester.widget<Text>(_key('following-sort-value')).data, '最常访问');
  });

  testWidgets('back closes the menu before the page', (tester) async {
    await _open(tester, FakeDynamicApi(following: followingUsers(3)));
    await tester.tap(_key('following-sort'));
    await settle(tester);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(_key('following-menu'), findsNothing);
    expect(find.byType(FollowingListPage), findsOneWidget);
  });

  testWidgets('typing searches after the pause, one call at a time; clearing goes back to the list', (tester) async {
    final api = FakeDynamicApi(
      following: [
        followingUser(1, name: '小明同学'),
        followingUser(2, name: '小明'),
        followingUser(3, name: '小红'),
        ...[for (var i = 4; i <= 25; i++) followingUser(i)],
      ],
    );
    await _open(tester, api);
    final hold = api.holds['searchFollowings'] = Completer<void>();
    await tester.enterText(_key('following-search-field'), '小');
    await tester.pump(const Duration(milliseconds: 299));
    expect(_count(api, 'searchFollowings'), 0);
    expect(_key('following-sort'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(_count(api, 'searchFollowings'), 1);
    await tester.pump();
    expect(find.byType(LoadingTvState), findsOneWidget);
    expect(_key('following-sort'), findsNothing);

    await tester.enterText(_key('following-search-field'), '小明');
    await tester.pump(const Duration(milliseconds: 400));
    expect(_count(api, 'searchFollowings'), 1);

    api.holds.remove('searchFollowings');
    hold.complete();
    await settle(tester);
    expect(_count(api, 'searchFollowings'), 2);
    expect(_key('following-row-1'), findsOneWidget);
    expect(_key('following-row-2'), findsOneWidget);
    expect(_key('following-row-3'), findsNothing);

    await tester.tap(_key('following-search-clear'));
    await settle(tester);
    expect(_key('following-search-clear'), findsNothing);
    expect(_key('following-sort'), findsOneWidget);
    expect(_key('following-row-3'), findsOneWidget);
    expect(_count(api, 'followings'), 1);
    expect(_count(api, 'searchFollowings'), 2);
  });

  testWidgets('a search with no one found says so', (tester) async {
    final api = FakeDynamicApi(following: followingUsers(3));
    await _open(tester, api);
    await tester.enterText(_key('following-search-field'), '不存在');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
    expect(_count(api, 'searchFollowings'), 1);
    expect(find.text('没有找到相关的关注'), findsOneWidget);
  });

  testWidgets('a row opens that person’s space', (tester) async {
    final api = FakeDynamicApi(following: [followingUser(777, name: '某个UP主')]);
    await _open(tester, api);
    await tester.tap(_key('following-row-777'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final space = tester.widget<SpacePage>(find.byType(SpacePage));
    expect(space.uploader.mid, 777);
    expect(space.uploader.name, '某个UP主');
  });

  testWidgets('opened while the launch\'s account check is out: the TV and no call, then the list once it answers', (
    tester,
  ) async {
    final http = Canned.http();
    final check = http.gates[Canned.navPath] = Completer<void>();
    final api = FakeDynamicApi(following: followingUsers(3));
    final services = await followingServices(api: api, checked: false, http: http);
    unawaited(services.environment.refreshAccount());
    await _open(tester, api, services: services);
    expect(services.environment.account, isA<AccountUnknown>());
    expect(find.byType(LoadingTvState), findsOneWidget);
    expect(_key('following-logged-out'), findsNothing);
    expect(api.calls, isEmpty);

    check.complete();
    await settle(tester);
    expect(api.calls, ['followings recommended page=1', 'ups offset=']);
    expect(_key('following-row-3'), findsOneWidget);
  });

  testWidgets('a failed account check is asked again on opening; then 重试 asks it, and the list loads', (tester) async {
    final http = Canned.http()..errors[Canned.navPath] = const SocketException('down');
    final api = FakeDynamicApi(following: followingUsers(3));
    final services = await followingServices(api: api, http: http);
    expect(services.environment.accountCheckFailed, isTrue);
    await _open(tester, api, services: services);
    expect(http.to(Canned.navPath), hasLength(2));
    expect(_key('following-account-failed'), findsOneWidget);
    expect(find.text('账号确认失败'), findsOneWidget);
    expect(api.calls, isEmpty);

    http.errors.remove(Canned.navPath);
    tester.semantics.tap(find.semantics.byLabel('重试'));
    await settle(tester);
    expect(http.to(Canned.navPath), hasLength(3));
    expect(_key('following-account-failed'), findsNothing);
    expect(_key('following-row-3'), findsOneWidget);
  });

  testWidgets('logged out it asks nothing; 登录 goes through the login gate, and the login loads the list', (
    tester,
  ) async {
    final gate = _LoggingInGate();
    final api = FakeDynamicApi(following: followingUsers(3));
    final services = await followingServices(api: api, loggedIn: false, loginGate: gate);
    gate.login = services.environment.useFakeAccount;
    await _open(tester, api, services: services);
    expect(api.calls, isEmpty);
    expect(find.text('登录后查看我的关注'), findsOneWidget);
    expect(_key('following-retry'), findsNothing);

    tester.semantics.tap(find.semantics.byLabel('登录'));
    await settle(tester);
    expect(gate.requests, 1);
    expect(_key('following-logged-out'), findsNothing);
    expect(api.calls, ['followings recommended page=1', 'ups offset=']);
    expect(_key('following-row-3'), findsOneWidget);
  });

  testWidgets('logging out while it shows empties it to the 登录 prompt; logging in again asks page 1 again', (
    tester,
  ) async {
    final api = FakeDynamicApi(following: followingUsers(3));
    final services = await followingServices(api: api, loggedIn: false);
    services.environment.useFakeAccount();
    await _open(tester, api, services: services);
    expect(_key('following-row-3'), findsOneWidget);

    unawaited(services.environment.logout());
    await settle(tester);
    expect(_key('following-logged-out'), findsOneWidget);
    expect(_key('following-row-3'), findsNothing);

    services.environment.useFakeAccount();
    await settle(tester);
    expect(_key('following-row-3'), findsOneWidget);
    expect(_count(api, 'followings'), 2);
  });

  group('the bar', () {
    Skin skin({bool primaryOnly = false, int? secondPage = 0xFFD9E8D3, int? color = 0xFF000000}) => Skin(
      equip: SkinEquip(
        id: 1,
        name: '测试装扮',
        ver: 1,
        packageUrl: '',
        packageMd5: '',
        primaryOnly: primaryOnly,
        colors: SkinColors(color: color, colorSecondPage: secondPage, lightText: true),
      ),
    );

    test('takes the skin’s second-page colour and text colour', () {
      final look = FollowingBarLook.of(skin());
      expect(look.fill, const Color(0xFFD9E8D3));
      expect(look.ink, const Color(0xFF000000));
      expect(look.lightStatus, isFalse);
      expect(FollowingBarLook.of(skin(secondPage: 0xFF161513, color: null)).ink, FollowingListTheme.barLightInk);
      expect(FollowingBarLook.of(skin(secondPage: 0xFF161513)).lightStatus, isTrue);
    });

    test('is white without a skin, or for one that dresses only the main pages', () {
      for (final look in [
        FollowingBarLook.of(null),
        FollowingBarLook.of(skin(primaryOnly: true)),
        FollowingBarLook.of(skin(secondPage: null)),
      ]) {
        expect(look.fill, FollowingListTheme.bar);
        expect(look.ink, FollowingListTheme.barInk);
      }
    });

    testWidgets('draws in the skin and follows a change', (tester) async {
      tester.view
        ..physicalSize = const Size(440, 956)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final services = await followingServices(api: FakeDynamicApi());
      final equipped = ValueNotifier<Skin?>(skin());
      await pumpFollowingApp(tester, services, home: FollowingListPage(skin: equipped));
      await settle(tester);
      Color fill() => tester.widget<ColoredBox>(_key('following-bar')).color;
      expect(fill(), const Color(0xFFD9E8D3));
      equipped.value = null;
      await tester.pump();
      expect(fill(), FollowingListTheme.bar);
    });
  });

  testWidgets('Reduce Motion opens and closes the menu at once', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _open(tester, FakeDynamicApi(following: followingUsers(3)));
    await tester.tap(_key('following-sort'));
    await tester.pump();
    expect(
      tester
          .widget<FadeTransition>(
            find.ancestor(of: _key('following-menu'), matching: find.byType(FadeTransition)).first,
          )
          .opacity
          .value,
      1,
    );
    await tester.tap(_key('following-menu-dim'));
    await tester.pump();
    await tester.pump();
    expect(_key('following-menu'), findsNothing);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
  });
}
