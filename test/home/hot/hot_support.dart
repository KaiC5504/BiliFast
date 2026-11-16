import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/hot/hot_api.dart';
import 'package:bilifast/home/hot/hot_list.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/space/fake_space_api.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/fake_keychain.dart';
import '../../playback/fakes.dart';
import '../fake_login_gate.dart';

/// The day every row's date counts back from.
final hotNow = DateTime(2026, 11, 16, 9, 59);

/// A made-up 热门 row: no real titles, names or ids.
PopularVideo hotVideo(
  int i, {
  String? title,
  String? owner,
  int ownerMid = 0,
  String face = '',
  String cover = '',
  int views = 1831000,
  int duration = 358,
  Duration age = const Duration(hours: 22, minutes: 39),
  int cid = 0,
}) => PopularVideo(
  card: VideoCard(
    aid: 7000 + i,
    bvid: 'BV1hot$i',
    cid: cid == 0 ? 17000 + i : cid,
    title: title ?? '测试热门视频 $i',
    cover: cover,
    duration: duration,
    ownerMid: ownerMid == 0 ? 600 + i : ownerMid,
    ownerName: owner ?? '测试UP主$i',
    ownerFace: face,
    views: views,
    danmaku: 10,
    likes: 0,
  ),
  published: hotNow.subtract(age),
);

List<PopularVideo> hotVideos(int count, {int from = 0}) => [for (var i = from; i < from + count; i++) hotVideo(i)];

/// The app's services as 热门 reaches them: the account logged in or out, the page's calls on [pageApi], spaces on the
/// space demo.
Future<AppServices> hotServices({bool loggedIn = true, FakePageApi? pageApi, FakeLoginGate? gate}) async {
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
    loginGate: gate ?? FakeLoginGate(),
    pageApi: pageApi ?? FakePageApi(),
    spaceApi: FakeSpaceApi.demo(),
  );
}

/// Records what the list hands out instead of pushing pages or the system share sheet.
class HotHarness {
  HotHarness({FakeHotApi? api}) : api = api ?? FakeHotApi(videos: hotVideos(40));

  final FakeHotApi api;
  final offset = ValueNotifier<double>(0);
  final reloads = ValueNotifier(0);
  final active = ValueNotifier(true);
  final opened = <VideoRoute>[];
  final shared = <Uri>[];

  /// Thrown by the share, when set.
  Object? shareError;

  Future<bool> share(Uri link) async {
    if (shareError case final error?) throw error;
    shared.add(link);
    return true;
  }

  void tapHome() => reloads.value++;

  Widget list() => ValueListenableBuilder(
    valueListenable: active,
    builder: (context, active, _) => HotList(
      active: active,
      scrollOffset: offset,
      reloads: reloads,
      api: api,
      share: share,
      openVideo: (context, route) => opened.add(route),
      now: () => hotNow,
    ),
  );
}

/// [child] filling a phone-sized view at 1× with the home indicator's inset, inside the app's scope and a page's
/// Material.
Future<void> pumpHot(WidgetTester tester, AppServices services, Widget child) async {
  tester.view
    ..physicalSize = const Size(440, 956)
    ..devicePixelRatio = 1
    ..padding = const FakeViewPadding(bottom: 34);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, page) => AppScope(services: services, child: page!),
      home: Scaffold(body: child),
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
