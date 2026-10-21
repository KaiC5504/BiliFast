import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/favourites/fake_favourites_api.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../home/fake_login_gate.dart';
import '../playback/fakes.dart';

/// The app's services over [api], logged in as Canned's account (mid 12345) or logged out; nothing reaches the
/// network.
Future<AppServices> favouritesServices({
  required bool loggedIn,
  required FakeFavouritesApi api,
  LoginGate? gate,
}) async {
  final environment = await AppEnvironment.load(
    keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
    http: Canned.http(loggedIn: loggedIn),
    logger: Logger(session: 'test'),
  );
  await environment.refreshAccount();
  final playback = AppPlayback(() async => throw UnimplementedError());
  addTearDown(playback.dispose);
  return AppServices(
    environment: environment,
    playback: playback,
    recents: await RecentStore.load(null, logger: Logger(session: 'test')),
    loginGate: gate ?? FakeLoginGate(),
    favouritesApi: api,
  );
}

FavVideo favVideo(
  int i, {
  String? title,
  String owner = '测试UP主',
  int duration = 11,
  int play = 8040,
  int danmaku = 0,
}) => FavVideo(
  aid: 7000 + i,
  bvid: bvidOf(7000 + i),
  title: title ?? '测试收藏 $i',
  duration: duration,
  ownerMid: 600 + i,
  ownerName: owner,
  play: play,
  danmaku: danmaku,
  favTime: 1760000000 - i,
);

FavFolder favFolder(int id, String title, {int count = 0, bool private = false, bool isDefault = false}) =>
    FavFolder(id: id, title: title, count: count, isPrivate: private, contains: false, isDefault: isDefault);

/// Lets a toast run out, so its timer is not left pending.
Future<void> settle(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> toastGone(WidgetTester tester) => settle(tester, 60);
