import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/swipe_back_route.dart';
import 'package:bilifast/friends/fake_friends_api.dart';
import 'package:bilifast/friends/friends_page.dart';
import 'package:bilifast/friends/friends_route.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/space/fake_space_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../home/fake_login_gate.dart';
import '../playback/fakes.dart';
import '../video/mixed_lines.dart' show appTheme;

/// The app's services, logged in as Canned's account (mid 12345) or logged out; UP主空间 answers from its demo fake, so
/// a row's space opens without the network.
Future<AppServices> friendsServices({bool loggedIn = true, LoginGate? loginGate}) async {
  final logger = Logger(session: 'test');
  final environment = await AppEnvironment.load(
    keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
    http: Canned.http(loggedIn: loggedIn),
    logger: logger,
  );
  await environment.refreshAccount();
  final playback = AppPlayback(() async => throw UnimplementedError());
  addTearDown(playback.dispose);
  return AppServices(
    environment: environment,
    playback: playback,
    recents: await RecentStore.load(null, logger: logger),
    loginGate: loginGate ?? FakeLoginGate(),
    spaceApi: FakeSpaceApi.demo(),
  );
}

/// A page with one button that pushes 我的好友 over [api] on [tab], as [openFriends] does.
class FriendsLauncher extends StatelessWidget {
  const FriendsLauncher({super.key, required this.api, this.tab = FriendsTab.following});

  final FakeFriendsApi api;
  final FriendsTab tab;

  @override
  Widget build(BuildContext context) => Center(
    child: GestureDetector(
      key: const ValueKey('open-friends'),
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(
        context,
      ).push(SwipeBackPageRoute<void>(builder: (_) => FriendsPage(initialTab: tab, api: api))),
      child: const SizedBox.square(dimension: 80),
    ),
  );
}

/// The app over [services] with [home] first, at the phone's size unless [sized] is false (the look check sizes it
/// itself); the RepaintBoundary keyed `shot` holds the screen.
Future<void> pumpFriendsApp(WidgetTester tester, AppServices services, Widget home, {bool sized = true}) async {
  if (sized) {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      builder: (context, child) => RepaintBoundary(
        key: const ValueKey('shot'),
        child: AppScope(services: services, child: child!),
      ),
      home: home,
    ),
  );
}

/// Opens 我的好友 over [api] on [tab]; returns the services.
Future<AppServices> openFriendsPage(
  WidgetTester tester,
  FakeFriendsApi api, {
  FriendsTab tab = FriendsTab.following,
  bool loggedIn = true,
  LoginGate? loginGate,
}) async {
  final services = await friendsServices(loggedIn: loggedIn, loginGate: loginGate);
  await pumpFriendsApp(tester, services, FriendsLauncher(api: api, tab: tab));
  await tester.tap(find.byKey(const ValueKey('open-friends')));
  await settle(tester);
  return services;
}

/// Lets the route come in and the fake's answers land.
Future<void> settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

FollowingUser friend(
  int mid, {
  String? name,
  String sign = '',
  bool vipPink = false,
  DynamicVerify verify = DynamicVerify.none,
}) => FollowingUser(mid: mid, name: name ?? '好友$mid', face: '', sign: sign, verify: verify, vipPink: vipPink);

/// [count] people, mids from 1.
List<FollowingUser> friends(int count) => [for (var i = 1; i <= count; i++) friend(i)];

Finder byKey(String key) => find.byKey(ValueKey(key));

int callCount(FakeFriendsApi api, String prefix) => api.calls.where((call) => call.startsWith(prefix)).length;
