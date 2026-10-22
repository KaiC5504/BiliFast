import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/favourites/fake_favourites_api.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/space/fake_space_api.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/fake_keychain.dart';
import '../../home/fake_login_gate.dart';
import '../../playback/fakes.dart';

/// The own space's mid in these tests.
const ownMid = 4242;

/// The app's services for a tab body: logged in, 收藏's and the space's calls answered from memory.
Future<AppServices> ownTabServices({FakeSpaceApi? spaceApi, FakeFavouritesApi? favouritesApi}) async {
  final environment = await AppEnvironment.load(
    keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
    http: Canned.http(),
    logger: Logger(session: 'test'),
  );
  await environment.refreshAccount();
  final playback = AppPlayback(() async => throw UnimplementedError());
  addTearDown(playback.dispose);
  return AppServices(
    environment: environment,
    playback: playback,
    recents: await RecentStore.load(null, logger: Logger(session: 'test')),
    loginGate: FakeLoginGate(),
    pageApi: FakePageApi(),
    spaceApi: spaceApi ?? FakeSpaceApi(),
    favouritesApi: favouritesApi ?? FakeFavouritesApi(),
  );
}

/// [sliver] under a [top] tall stand-in for the page's header, in a scroll view of its own on the phone's 440 × 956 at
/// 1×, with its safe areas.
Future<void> pumpOwnTab(
  WidgetTester tester,
  AppServices services,
  Widget sliver, {
  double top = 0,
  ScrollController? controller,
}) async {
  tester.view
    ..physicalSize = const Size(440, 956)
    ..devicePixelRatio = 1
    ..padding = const FakeViewPadding(top: 62, bottom: 34);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, page) => AppScope(services: services, child: page!),
      home: Scaffold(
        backgroundColor: BiliColors.card,
        body: CustomScrollView(
          controller: controller,
          slivers: [
            SliverToBoxAdapter(child: SizedBox(height: top)),
            sliver,
          ],
        ),
      ),
    ),
  );
}

Future<void> settle(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lets a toast run out, so its timer is not left pending.
Future<void> toastGone(WidgetTester tester) => settle(tester, 60);

/// Made-up videos: no real titles or ids.
SpaceVideo ownVideo(int i, {String? title, int play = 37000, int danmaku = 0, int duration = 12}) => SpaceVideo(
  aid: 3000 + i,
  bvid: 'BV1owntest$i',
  title: title ?? '测试视频 $i',
  cover: '',
  duration: duration,
  play: play,
  danmaku: danmaku,
);

SpaceFolderCard ownFolder(int i, {int count = 0, bool isPrivate = false, String cover = '', String? title}) =>
    SpaceFolderCard(id: 100 + i, title: title ?? '测试收藏夹 $i', cover: cover, count: count, isPrivate: isPrivate);

SpaceBangumiCard ownBangumi(int i, {String progress = '全12话', String? title}) =>
    SpaceBangumiCard(seasonId: 800 + i, title: title ?? '测试番剧 $i', cover: '', progress: progress);

FavFolder favFolder(int i, {int count = 0, bool isPrivate = false, String? title}) => FavFolder(
  id: 100 + i,
  title: title ?? '测试收藏夹 $i',
  count: count,
  isPrivate: isPrivate,
  contains: false,
  isDefault: i == 0,
);

SpaceProfile ownProfile(OwnSpace? own, {int videoCount = 0}) =>
    SpaceProfile(mid: ownMid, name: '测试账号', face: '', videoCount: videoCount, own: own);
