import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/dynamic/fake_dynamic_api.dart';
import 'package:bilifast/dynamic/following/following_route.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/skin/skin.dart';
import 'package:bilifast/space/fake_space_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/fake_keychain.dart';
import '../../home/fake_login_gate.dart';
import '../../playback/fakes.dart';
import '../../video/mixed_lines.dart' show appTheme;

/// The app's services over [api], logged in as Canned's account (mid 12345) or logged out; UP主空间 answers from its
/// demo fake, so a row's space opens without the network. With [checked] false the account is still unknown, as at
/// launch before the check answers; [http] answers that check.
Future<AppServices> followingServices({
  required FakeDynamicApi api,
  bool loggedIn = true,
  bool checked = true,
  CannedHttp? http,
  LoginGate? loginGate,
}) async {
  final logger = Logger(session: 'test');
  final environment = await AppEnvironment.load(
    keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
    http: http ?? Canned.http(loggedIn: loggedIn),
    logger: logger,
  );
  if (checked) await environment.refreshAccount();
  final playback = AppPlayback(() async => throw UnimplementedError());
  addTearDown(playback.dispose);
  return AppServices(
    environment: environment,
    playback: playback,
    recents: await RecentStore.load(null, logger: logger),
    loginGate: loginGate ?? FakeLoginGate(),
    dynamicApi: api,
    spaceApi: FakeSpaceApi.demo(),
  );
}

/// A page with one button that opens 我的关注 as the 关注 tab's 更多 does.
class FollowingLauncher extends StatelessWidget {
  const FollowingLauncher({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: GestureDetector(
      key: const ValueKey('open-following'),
      behavior: HitTestBehavior.opaque,
      onTap: () => openFollowingList(context),
      child: const SizedBox.square(dimension: 80),
    ),
  );
}

/// The app at the phone's size over [services], [home] first; the RepaintBoundary keyed `shot` holds the screen.
Future<void> pumpFollowingApp(WidgetTester tester, AppServices services, {Widget home = const FollowingLauncher()}) =>
    tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => RepaintBoundary(
          key: const ValueKey('shot'),
          child: AppScope(services: services, child: child!),
        ),
        home: home,
      ),
    );

/// Lets the route come in and the fake's answers land.
Future<void> settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

FollowingUser followingUser(int mid, {String? name, bool vipPink = false, DynamicVerify verify = DynamicVerify.none}) =>
    FollowingUser(mid: mid, name: name ?? '关注$mid', face: '', verify: verify, vipPink: vipPink);

/// [count] people, mids from 1.
List<FollowingUser> followingUsers(int count) => [for (var i = 1; i <= count; i++) followingUser(i)];

/// A skin like 129's: a light second-page colour and black text.
final violetSkin = Skin(
  equip: const SkinEquip(
    id: 1,
    name: '测试装扮',
    ver: 1,
    packageUrl: '',
    packageMd5: '',
    colors: SkinColors(color: 0xFF000000, colorSecondPage: 0xFFD9E8D3, lightText: true),
  ),
);

ValueListenable<Skin?> skinOf(Skin? skin) => ValueNotifier<Skin?>(skin);
