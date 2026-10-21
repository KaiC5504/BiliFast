import 'dart:async';
import 'dart:io';

import 'package:bili_core/api.dart' show SpaceProfile, SpaceVideo, UploaderCard;
import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart' show ManualClock;
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/route_observer.dart';
import 'package:bilifast/app/swipe_back_route.dart';
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/device/player_device.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/shared/remote_image.dart' show DefaultAvatar;
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/space/fake_space_api.dart';
import 'package:bilifast/space/uploader_sheet_grid.dart';
import 'package:bilifast/space/uploader_tap.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/page_session.dart' show SessionOpen;
import 'package:bilifast/video/page_tabs.dart';
import 'package:bilifast/video/player_session.dart';
import 'package:bilifast/video/video_page.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../device/fake_orientation_host.dart' show FakeOrientationHost;
import '../playback/fakes.dart';
import '../support/fake_player.dart';
import '../support/fake_player_session.dart';
import '../support/fake_video_actions.dart';
import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import '../video/mixed_lines.dart' show appTheme;

class _NoLogin implements LoginGate {
  @override
  Future<bool> request(BuildContext context) async => false;
}

const _playing = 'BV1GJ411x7h7';

SpaceVideo _video(String bvid, String title, {int play = 0, String date = '', int duration = 0}) =>
    SpaceVideo(aid: 1, bvid: bvid, title: title, cover: '', duration: duration, play: play, publishedText: date);

/// 68's uploader, made up: the same glyph counts, counts and lengths.
final _top = FakeSpaceApi(
  profileFor: (mid) => SpaceProfile(mid: mid, name: '七七七七七七七星光', face: '', fans: 30000, videoCount: 71, likes: 969000),
  videoList: [
    _video('BV1sheet0001', '“春天的花开在每一个角落”', play: 22000, date: '10月2日', duration: 37),
    _video(_playing, '“少年，我的故事从这里开始”', play: 13000, date: '10月1日', duration: 32),
    _video('BV1sheet0003', '“全世界只对你有好感~”', play: 1972, date: '9月24日', duration: 40),
    _video('BV1sheet0004', '“老了就回家”', play: 3452, date: '9月13日', duration: 28),
    _video('BV1sheet0005', '“那一年冰场上来了一位11岁的天才”', play: 6027, date: '9月12日', duration: 32),
    _video('BV1sheet0006', '“这首歌光是前奏就已经打动到我了!!!”', play: 7792, date: '9月5日', duration: 90),
    _video('BV1sheet0007', '“一个演示视频的标题”', play: 1000, date: '9月1日', duration: 60),
    _video('BV1sheet0008', '“另一个演示视频的标题”', play: 1000, date: '8月30日', duration: 60),
  ],
);

/// 76's uploader at the end of their videos, made up the same way: nine videos, so the last row holds one.
final _bottom = FakeSpaceApi(
  profileFor: (mid) =>
      SpaceProfile(mid: mid, name: 'KxCyberDemo', face: '', fans: 23000, videoCount: 269, likes: 583000),
  videoList: [
    for (var i = 0; i < 4; i++) _video('BV1filler000$i', '演示视频 第${i + 1}期', play: 100, date: '2020年5月1日', duration: 60),
    _video('BV1sheet0011', '【演示线4】Demo Racer 4 几辆最喜欢的车（技术菜别笑话我）', play: 105, date: '2020年4月7日', duration: 1285),
    _video('BV1sheet0012', '【演示召唤16】主线剧情战役 自清门户', play: 54, date: '2020年4月6日', duration: 373),
    _video('BV1sheet0013', '【演示大镖客2】当学会万象天引神罗天征后 用非人的手短整治小屁孩们', play: 207, date: '2020年4月6日', duration: 1266),
    _video('BV1sheet0014', '【演示大镖客2】亚瑟的结局 救赎', play: 408, date: '2020年3月13日', duration: 1409),
    _video('BV1sheet0015', '某某某某某大学签售会演唱【Let It Go】', play: 13000, date: '2019年11月16日', duration: 214),
  ],
);

/// The uploader sheet over the video page as KaiC's iPhone draws it, under the system font, against 68 (the grid's top,
/// the playing video pink) and 76 (scrolled to 已经到底啦~). Our sheet starts at the 16:9 player's bottom (309.5); 68
/// and 76 show a portrait video whose box ends at 315.67, so the shots are compared from each sheet's top. With
/// BILIFAST_SHOTS naming a folder outside the repo, the 3× shots are saved there for tools/screen_diff.py.
void main() {
  Future<NavigatorState> render(WidgetTester tester, FakeSpaceApi spaceApi) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester);

    final orientation = OrientationController(host: FakeOrientationHost());
    final logger = Logger(session: 'test');
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: Canned.http(),
      logger: logger,
    );
    final player = FakePlayer();
    final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
    final controller = PlaybackController(
      client: environment.client,
      engine: FakeEngine(),
      player: player,
      clock: ManualClock(10000).clock,
      now: () => now,
      startTimer: FakeTimers().start,
      logger: logger,
    );
    final playback = AppPlayback(() async => controller);
    addTearDown(playback.dispose);
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      device: PlayerDevice(orientation: orientation, controls: NoDeviceControls()),
      loginGate: _NoLogin(),
      pageApi: FakePageApi(
        uploader: const UploaderCard(mid: 1, name: '', face: '', fans: 0, videos: 0, isVip: false, following: false),
      ),
      spaceApi: spaceApi,
    );
    BiliFonts.family = BiliFonts.system;

    PlayerSession session({
      required PlaybackController controller,
      required AppServices services,
      required SessionOpen open,
      required void Function(double seconds) onSeeked,
      required VoidCallback requestLogin,
      required VoidCallback willPlay,
    }) => FakePlayerSession(player: player);

    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('screen'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(),
          navigatorKey: nav,
          navigatorObservers: [pageRoutes],
          // Still, for a shot to measure.
          builder: (context, child) => AppScope(
            services: services,
            child: MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
          ),
          home: const SizedBox(),
        ),
      ),
    );
    unawaited(
      nav.currentState!.push(
        SwipeBackPageRoute<void>(
          builder: (_) => VideoPage(
            route: const VideoRoute(bvid: _playing, cid: 137649199, start: 0),
            createSession: session,
            createDetails: ({
              required session,
              required services,
              required toast,
              required requestLogin,
              required logins,
            }) => FakePageDetails(),
          ),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final page = tester.element(find.byType(PageTabs));
    // Asset decoding needs real async; without it the shot has no face.
    await tester.runAsync(() => precacheImage(const AssetImage(DefaultAvatar.asset), page));
    openUploader(page, const UploaderRef(mid: 7));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return nav.currentState!;
  }

  Future<void> leave(WidgetTester tester, NavigatorState nav) async {
    nav.pop();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('screen')), '$shots/$name.png');
  }

  Rect rect(WidgetTester tester, String key) => tester.getRect(find.byKey(ValueKey(key)));

  testWidgets('68: the header, the grid\'s first rows and the playing video pink', (tester) async {
    final nav = await render(tester, _top);
    final sheet = rect(tester, 'uploader-sheet');
    // The 16:9 player's bottom.
    expect(sheet.top, 62 + 440 / BiliMetrics.videoAspect);
    expect(sheet.bottom, 956);
    final top = sheet.top;
    // Measured on 68 from the sheet's top: the face 16 in and 31 down, + 关注 23.67 down and 9 after the name, the
    // chevron ending 16.33 from the right, the first cover 77 down.
    final face = tester.getRect(
      find.descendant(of: find.byKey(const ValueKey('uploader-sheet-face')), matching: find.byType(ClipOval)),
    );
    expect(face, Rect.fromLTWH(16, top + 31, 34, 34));
    final follow = rect(tester, 'uploader-sheet-follow');
    expect(follow.size, const Size(60, 24));
    expect(follow.top - top, closeTo(23.67, 0.5));
    expect(follow.left - rect(tester, 'uploader-sheet-name').right, 9);
    expect(tester.getRect(find.byType(UploaderVideoCard).first), Rect.fromLTWH(8, top + 77, 208, 117 + 52));
    expect(find.byKey(const ValueKey('uploader-sheet-playing')), findsOneWidget);
    await shoot(tester, '68-ours');
    await leave(tester, nav);
  });

  testWidgets('76: scrolled to its end, 已经到底啦~ under the last row', (tester) async {
    final nav = await render(tester, _bottom);
    final grid = tester.state<ScrollableState>(
      find.descendant(of: find.byKey(const ValueKey('uploader-sheet-grid')), matching: find.byType(Scrollable)),
    );
    grid.position.jumpTo(grid.position.maxScrollExtent);
    await tester.pump();
    // 76: the line's middle 54 above the screen's bottom, the last row's cover ending 126 above it.
    expect(tester.getCenter(find.text('已经到底啦~')).dy, 956 - 54);
    expect(tester.getRect(find.byType(UploaderVideoCard).last).top, 956 - 243);
    await shoot(tester, '76-ours');
    await leave(tester, nav);
  });
}
