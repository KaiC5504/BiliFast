import 'dart:async';
import 'dart:io';

import 'package:bili_core/api.dart' show Comment, CommentMember, TextRun, VideoCard, VideoDetail, VideoOwner, VideoStat;
import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart' show ManualClock;
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/route_observer.dart';
import 'package:bilifast/app/swipe_back_route.dart';
import 'package:bilifast/app/zoom_back_route.dart';
import 'package:bilifast/comments/comment_overlays.dart';
import 'package:bilifast/comments/comments_tab.dart';
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/device/player_device.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player/playback_clock.dart';
import 'package:bilifast/player_ui/panels/panel_layer.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/collapsing_player.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/intro/related_list.dart';
import 'package:bilifast/video/pad/pad_body.dart';
import 'package:bilifast/video/pad/pad_page_layout.dart';
import 'package:bilifast/video/page_details.dart';
import 'package:bilifast/video/page_session.dart';
import 'package:bilifast/video/page_tabs.dart';
import 'package:bilifast/video/player_session.dart';
import 'package:bilifast/video/video_page.dart';
import 'package:bilifast/video/video_player_area.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/fake_player.dart';
import '../support/fake_player_session.dart';
import '../support/fake_video_actions.dart';
import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import 'mixed_lines.dart' show appTheme;

const bv = 'BV1GJ411x7h7';
const p1 = 137649199;

/// KaiC's iPad Pro 11" in points: 834 × 1194 upright, its page 32 pt down (03, 05, 06).
const wide = Size(1194, 834);
const tall = Size(834, 1194);
const band = PadPageTheme.statusBand;
const column = 1194 - PadPageTheme.relatedWidth - PadPageTheme.rule;

void main() {
  late PlaybackController controller;
  late FakePlayer player;
  late GlobalKey<NavigatorState> nav;
  late OrientationController orientation;
  late List<FakePlayerSession> sessions;
  late List<PlaybackController> controllers;

  setUp(() {
    sessions = [];
    controllers = [];
  });

  PlayerSession fakeSession({
    required PlaybackController controller,
    required AppServices services,
    required SessionOpen open,
    required void Function(double seconds) onSeeked,
    required VoidCallback requestLogin,
    required VoidCallback willPlay,
  }) {
    final session = FakePlayerSession(player: controller.player as FakePlayer);
    sessions.add(session);
    return session;
  }

  PageDetails fakeDetails({
    required PlayerSession session,
    required AppServices services,
    required void Function(String message) toast,
    required VoidCallback requestLogin,
    required Listenable logins,
  }) => FakePageDetails();

  /// [systemFont] renders under the stand-ins for the iPad's system font, set once the app's font store has loaded.
  Future<void> host(WidgetTester tester, {bool landscape = true, bool phone = false, bool systemFont = false}) async {
    if (phone) {
      showAsPhone(tester);
    } else {
      showAsPad(tester, landscape: landscape);
    }
    final logger = Logger(session: 'test');
    final http = Canned.http()..routes['/x/click-interface/web/heartbeat'] = (200, '{"code":0,"message":"0"}');
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: http,
      logger: logger,
    );
    await environment.refreshAccount();
    final time = ManualClock(10000);
    final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
    PlaybackController make() {
      player = FakePlayer();
      controller = PlaybackController(
        client: environment.client,
        engine: FakeEngine(),
        player: player,
        clock: time.clock,
        now: () => now,
        startTimer: FakeTimers().start,
        logger: logger,
      );
      controllers.add(controller);
      return controller;
    }

    make();
    final playback = AppPlayback(() async => make());
    addTearDown(playback.dispose);
    orientation = OrientationController();
    final api = FakePageApi()..commentList = [for (var i = 1; i <= 30; i++) comment(300 + i)];
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      device: PlayerDevice(orientation: orientation, controls: NoDeviceControls()),
      pageApi: api,
    );
    nav = services.navigator;
    if (systemFont) {
      final saved = BiliFonts.family;
      addTearDown(() => BiliFonts.family = saved);
      await tester.runAsync(loadSystemFontStandIns);
      BiliFonts.family = BiliFonts.system;
    }
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        navigatorObservers: [pageRoutes],
        theme: appTheme(),
        builder: (context, child) => RepaintBoundary(
          key: const ValueKey('screen'),
          child: AppScope(services: services, child: child!),
        ),
        home: const SizedBox(),
      ),
    );
  }

  Future<void> frames(WidgetTester tester, [int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Widget page(VideoRoute route) => VideoPage(route: route, createSession: fakeSession, createDetails: fakeDetails);

  /// A page with its video known, its detail and related videos in, playing.
  Future<void> opened(WidgetTester tester) async {
    unawaited(nav.currentState!.push(SwipeBackPageRoute<void>(builder: (_) => page(const VideoRoute(bvid: bv, cid: p1, start: 0)))));
    await frames(tester, 20);
    sessions.single
      ..video = controller.video
      ..detail = detail(bv)
      ..related = [for (var i = 0; i < 20; i++) quietCard('BV1r$i')]
      ..changed();
    player.emit(const StatusChanged(PlayerStatus.playing));
    await frames(tester, 20);
  }

  Future<void> turn(WidgetTester tester, Size to) async {
    tester.view.physicalSize = to * 2;
    await frames(tester, 4);
  }

  Rect area(WidgetTester tester) => tester.getRect(find.byType(VideoPlayerArea));
  ScrollPosition columnScroll(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(of: find.byKey(const ValueKey('pad-player-column')), matching: find.byType(Scrollable)).first,
      )
      .position;
  PlayerUi ui(WidgetTester tester) => tester.widget<PanelLayer>(find.byType(PanelLayer)).ui;

  Future<void> back(WidgetTester tester) async {
    unawaited(nav.currentState!.maybePop());
    await frames(tester, 20);
  }

  group('sideways (03, 05)', () {
    testWidgets('two columns: the 16:9 player over 简介 and 热门评论 on the left, the related videos on the right',
        (tester) async {
      await host(tester);
      await opened(tester);
      expect(area(tester), const Rect.fromLTWH(0, band, column, column / BiliMetrics.videoAspect));
      expect(tester.getRect(find.byKey(const ValueKey('pad-related-column'))), const Rect.fromLTRB(column, band, 1194, 834));
      expect(find.byType(PadRelatedColumn), findsOneWidget);
      expect(find.byType(PadIntroHead, skipOffstage: false), findsOneWidget, reason: 'the stub draws nothing yet');
      expect(find.byType(PadCommentsHeader), findsOneWidget, reason: '热门评论 inline under 简介');
      expect(tester.getRect(find.byType(PadCommentsHeader)).width, column);
      expect(find.text('热门评论'), findsOneWidget);
      expect(find.text('查看 30 条评论'), findsOneWidget);
      expect(find.byType(PageTabRow), findsNothing);
      expect(find.byType(PadPageTabRow), findsNothing, reason: 'no tabs sideways');
      expect(
        tester.getRect(find.byKey(const ValueKey('danmaku-capsule'))),
        Rect.fromLTWH(
          column - PadPageTheme.capsuleRight - PadPageTheme.capsuleWidth,
          band + column / BiliMetrics.videoAspect + PadPageTheme.capsuleCentreSideways - PadPageTheme.capsuleHeight / 2,
          PadPageTheme.capsuleWidth,
          PadPageTheme.capsuleHeight,
        ),
        reason: '点我发弹幕 on the uploader row',
      );
      await back(tester);
    });

    testWidgets('playing, the column scrolls under the player; paused, the player shrinks to the pink bar, the strip '
        'and the 发条评论 bar pinned, and a tap on the bar scrolls back up and plays', (tester) async {
      await host(tester);
      await opened(tester);
      const full = column / BiliMetrics.videoAspect;
      await tester.timedDragFrom(const Offset(300, 700), const Offset(0, -300), const Duration(milliseconds: 300));
      await frames(tester);
      expect(columnScroll(tester).pixels, greaterThan(100));
      expect(area(tester).height, full, reason: 'playing, it keeps its height');
      expect(find.text('立即播放'), findsNothing);
      columnScroll(tester).jumpTo(0);
      await tester.pump();

      player.emit(const StatusChanged(PlayerStatus.paused));
      await frames(tester, 2);
      final gesture = await tester.startGesture(const Offset(300, 700));
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -60));
      await tester.pump();
      final scrolled = columnScroll(tester).pixels;
      final box = tester.getRect(find.byKey(const ValueKey('page-player')));
      expect(box.height, closeTo(band + full - scrolled, 0.01));
      expect(area(tester).height, closeTo(full, 0.01), reason: 'the video keeps its size, its top going under the band');
      expect(area(tester).bottom, closeTo(box.bottom, 0.01));
      expect(find.text('立即播放'), findsOneWidget);
      await gesture.moveBy(const Offset(0, -500));
      await tester.pump();
      await gesture.up();
      await frames(tester);
      expect(tester.getRect(find.byKey(const ValueKey('collapse-bar'))), const Rect.fromLTWH(0, band, column, PadPageTheme.barHeight));
      expect(find.byKey(const ValueKey('pad-pinned-strip')), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const ValueKey('pad-pinned-strip'))),
        const Rect.fromLTWH(0, band + PadPageTheme.barHeight, column, PadPageTheme.stripHeight),
      );
      expect(find.byKey(const ValueKey('pad-comment-bar')), findsOneWidget);
      expect(tester.getRect(find.byKey(const ValueKey('pad-comment-bar'))).bottom, 834);

      final calls = sessions.single.calls.length;
      await tester.tap(find.byKey(const ValueKey('collapse-resume')));
      await tester.pump();
      expect(sessions.single.calls.sublist(calls), ['togglePlay']);
      player.emit(const StatusChanged(PlayerStatus.playing));
      await frames(tester, 10);
      expect(columnScroll(tester).pixels, 0);
      expect(area(tester), const Rect.fromLTWH(0, band, column, full));
      expect(find.text('立即播放'), findsNothing);
      expect(find.byKey(const ValueKey('pad-pinned-strip')), findsNothing);
      await back(tester);
    });

    testWidgets('on the bar ⋮ opens the ⋮ panel and ‹ leaves the page', (tester) async {
      await host(tester);
      await opened(tester);
      player.emit(const StatusChanged(PlayerStatus.paused));
      await frames(tester, 2);
      await tester.timedDragFrom(const Offset(300, 700), const Offset(0, -600), const Duration(milliseconds: 300));
      await frames(tester);
      await tester.tap(find.byKey(const ValueKey('collapse-more')));
      await frames(tester, 4);
      expect(ui(tester).panels.value, isNotNull);
      ui(tester).panels.close();
      await frames(tester, 10);
      await tester.tap(find.byKey(const ValueKey('collapse-back')));
      await frames(tester, 20);
      expect(find.byType(VideoPage), findsNothing);
    });

    testWidgets('查看N条评论 scrolls 热门评论 up under the player', (tester) async {
      await host(tester);
      await opened(tester);
      await tester.tap(find.byKey(const ValueKey('comments-see-all')));
      await frames(tester, 10);
      expect(
        tester.getTopLeft(find.byType(PadCommentsHeader)).dy,
        closeTo(band + column / BiliMetrics.videoAspect, 0.5),
      );
      await back(tester);
    });

    testWidgets('评论详情 rises from the player\'s bottom over the left column only', (tester) async {
      await host(tester);
      await opened(tester);
      final overlays = find.byType(CommentOverlays);
      expect(tester.widget<CommentOverlays>(overlays).threadTop, band + column / BiliMetrics.videoAspect);
      expect(tester.getRect(overlays).width, column);
      await back(tester);
    });
  });

  group('upright (06, 07)', () {
    testWidgets('one column: the player the screen\'s width, 简介 / 评论 (N) with 点我发弹幕, 简介 then the related videos',
        (tester) async {
      await host(tester, landscape: false);
      await opened(tester);
      const full = 834 / BiliMetrics.videoAspect;
      expect(area(tester), const Rect.fromLTWH(0, band, 834, full));
      expect(tester.getRect(find.byType(PadPageTabRow)), const Rect.fromLTWH(0, band + full, 834, PadPageTheme.tabRowHeight));
      expect(find.byType(PageTabRow), findsNothing);
      expect(find.byType(PadIntroTab), findsOneWidget);
      expect(find.byType(PadIntroHead, skipOffstage: false), findsOneWidget, reason: 'the stub draws nothing yet');
      expect(find.byType(RelatedSliver), findsOneWidget);
      expect(find.byType(PadRelatedColumn), findsNothing);
      expect(
        tester.getRect(find.byKey(const ValueKey('danmaku-capsule'))).right,
        834 - PadPageTheme.capsuleRight,
      );
      await tester.tap(find.byKey(const ValueKey('tab-comments')));
      await frames(tester, 20);
      expect(find.byType(CommentsTab), findsOneWidget, reason: 'the phone\'s 评论 at the iPad\'s width (a guess)');
      expect(find.text('评论 (30)'), findsOneWidget);
      await back(tester);
    });

    testWidgets('paused, the player shrinks to the pink bar with the tab row under it', (tester) async {
      await host(tester, landscape: false);
      await opened(tester);
      player.emit(const StatusChanged(PlayerStatus.paused));
      await frames(tester, 2);
      await tester.timedDragFrom(const Offset(400, 1000), const Offset(0, -700), const Duration(milliseconds: 300));
      await frames(tester);
      expect(tester.getRect(find.byKey(const ValueKey('collapse-bar'))), const Rect.fromLTWH(0, band, 834, PadPageTheme.barHeight));
      expect(tester.getRect(find.byType(PadPageTabRow)).top, band + PadPageTheme.barHeight);
      expect(find.text('立即播放'), findsOneWidget);
      await back(tester);
    });
  });

  group('turning the iPad (23)', () {
    testWidgets('reflows between one column and two, keeping the session, the player and the native view',
        (tester) async {
      await host(tester, landscape: false);
      await opened(tester);
      final video = tester.element(find.byKey(const ValueKey('fake-video')));
      void kept() => expect(identical(tester.element(find.byKey(const ValueKey('fake-video'))), video), isTrue);
      final calls = sessions.single.calls.length;
      final playing = controller;
      await turn(tester, wide);
      expect(find.byType(PadRelatedColumn), findsOneWidget);
      expect(area(tester), const Rect.fromLTWH(0, band, column, column / BiliMetrics.videoAspect));
      kept();
      await turn(tester, tall);
      expect(find.byType(PadPageTabRow), findsOneWidget);
      expect(area(tester), const Rect.fromLTWH(0, band, 834, 834 / BiliMetrics.videoAspect));
      kept();
      expect(sessions, hasLength(1));
      expect(controller, same(playing), reason: 'no second player');
      expect(controllers.last, same(playing));
      expect(sessions.single.calls.sublist(calls), isEmpty, reason: 'playback untouched');
      expect(orientation.presentation, Presentation.inline);
      await back(tester);
    });
  });

  group('full screen (22, 25)', () {
    for (final (name, size) in [('sideways', wide), ('upright', tall)]) {
      testWidgets('$name: the player grows to the whole screen and back to its place on exit', (tester) async {
        await host(tester, landscape: size == wide);
        await opened(tester);
        final inline = area(tester);
        orientation.enterLandscape();
        await tester.pump();
        await tester.pump(PadPageTheme.fullScreenGrow ~/ 2);
        final halfway = tester.getRect(find.byKey(const ValueKey('page-player')));
        expect(halfway.height, inExclusiveRange(inline.bottom, size.height), reason: 'on its way');
        await tester.pump(PadPageTheme.fullScreenGrow);
        expect(area(tester), Offset.zero & size);
        expect(tester.view.physicalSize, size * 2, reason: 'the iPad doesn\'t turn for it');
        orientation.exitToInline();
        await tester.pump();
        await tester.pump(PadPageTheme.fullScreenGrow + const Duration(milliseconds: 50));
        expect(area(tester), inline);
        await back(tester);
      });
    }

    testWidgets('turning while in full screen keeps the whole screen', (tester) async {
      await host(tester);
      await opened(tester);
      orientation.enterLandscape();
      await tester.pump();
      await tester.pump(PadPageTheme.fullScreenGrow);
      await turn(tester, tall);
      expect(area(tester), Offset.zero & tall);
      orientation.exitToInline();
      await tester.pump();
      await tester.pump(PadPageTheme.fullScreenGrow + const Duration(milliseconds: 50));
      expect(find.byType(PadPageTabRow), findsOneWidget);
      await back(tester);
    });
  });

  group('look-alike (03, 05, 06): with BILIFAST_SHOTS naming a folder outside the repo, the 2× shots are saved there',
      () {
    Future<void> shot(WidgetTester tester, String name) async {
      final shots = Platform.environment['BILIFAST_SHOTS'];
      if (shots != null) await saveShot(tester, find.byKey(const ValueKey('screen')), '$shots/$name.png', pixelRatio: 2);
    }

    testWidgets('03: the columns, the player box and the 热门评论 header', (tester) async {
      await host(tester, systemFont: true);
      await opened(tester);
      player.emit(const StatusChanged(PlayerStatus.paused));
      await frames(tester, 4);
      ui(tester).chrome.hide();
      await frames(tester, 4);
      final header = tester.getRect(find.byType(PadCommentsHeader));
      expect(tester.getCenter(find.text('热门评论')).dy - header.top, closeTo(PadPageTheme.headerCentre, 0.5));
      expect(tester.getTopLeft(find.text('热门评论')).dx, 20);
      expect(tester.getRect(find.byKey(const ValueKey('comments-see-all'))).right, closeTo(column - PadPageTheme.headerRight, 0.01));
      await shot(tester, 'pad-03');
    });

    testWidgets('05: the bar and the pinned strip', (tester) async {
      await host(tester, systemFont: true);
      await opened(tester);
      player.emit(const StatusChanged(PlayerStatus.paused));
      await frames(tester, 2);
      await tester.timedDragFrom(const Offset(300, 700), const Offset(0, -560), const Duration(milliseconds: 400));
      await frames(tester, 10);
      final label = tester.getRect(find.text('立即播放'));
      expect(label.center.dy, closeTo(band + PadPageTheme.barRowCentre, 0.5));
      await shot(tester, 'pad-05');
    });

    testWidgets('06: one column, the tab row', (tester) async {
      await host(tester, landscape: false, systemFont: true);
      await opened(tester);
      player.emit(const StatusChanged(PlayerStatus.paused));
      await frames(tester, 4);
      ui(tester).chrome.hide();
      await frames(tester, 4);
      expect(tester.getCenter(find.text('简介')).dy, closeTo(band + 834 / BiliMetrics.videoAspect + 30, 0.5));
      await shot(tester, 'pad-06');
    });
  });

  group('opening (21)', () {
    for (final phone in [false, true]) {
      testWidgets(phone ? 'a 推荐 card on the iPhone still zooms back into its card' : 'a 推荐 card on the iPad opens '
          'and swipes back with the plain slide', (tester) async {
        await host(tester, phone: phone);
        unawaited(openVideoPage(nav.currentContext!, VideoRoute(bvid: bv, zoomSource: () => null)));
        await tester.pump();
        await tester.pump();
        final route = ModalRoute.of(tester.element(find.byType(VideoPage)));
        expect(route, isA<SwipeBackPageRoute<void>>());
        expect(route is ZoomBackPageRoute<void>, phone);
        await frames(tester, 20);
        await back(tester);
      });
    }

    testWidgets('the iPhone keeps its own page: no iPad piece at 440 × 956', (tester) async {
      await host(tester, phone: true);
      await opened(tester);
      expect(find.byType(PageTabRow), findsOneWidget);
      expect(find.byType(PadPageTabRow), findsNothing);
      expect(find.byType(PadIntroTab), findsNothing);
      expect(area(tester).top, 62);
      await back(tester);
    });
  });
}

VideoCard quietCard(String bvid) => VideoCard(
  aid: 2,
  bvid: bvid,
  cid: 3,
  title: '相关视频',
  cover: '',
  duration: 60,
  ownerMid: 4,
  ownerName: 'UP',
  views: 1,
  danmaku: 1,
  likes: 1,
);

VideoDetail detail(String bvid) => VideoDetail(
  bvid: bvid,
  aid: 1,
  title: '测试视频',
  cover: '',
  pubdate: 0,
  duration: 712,
  desc: '',
  descParts: const [],
  copyright: 1,
  owner: const VideoOwner(mid: 9, name: 'UP主', face: ''),
  stat: VideoStat(view: 0, danmaku: 0, reply: 30, favorite: 0, coin: 0, share: 0, like: 0),
  pages: const [],
  season: null,
  staff: const [],
  width: 1920,
  height: 1080,
  honor: null,
  redirectURL: null,
);

Comment comment(int rpid) => Comment(
  rpid: rpid,
  oid: 1,
  mid: 2001,
  root: 0,
  parent: 0,
  ctime: rpid,
  likes: 10,
  replyCount: 0,
  member: CommentMember(mid: 2001, name: '测试用户$rpid', level: 5),
  message: '第$rpid条评论',
  runs: [TextRun('第$rpid条评论')],
  previewReplies: const [],
);
