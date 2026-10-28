import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:bili_core/api.dart' show Comment, CommentMember, TextRun, VideoCard, VideoDetail, VideoOwner, VideoStat;
import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart' show ManualClock;
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/form_factor.dart';
import 'package:bilifast/app/route_observer.dart';
import 'package:bilifast/app/swipe_back_route.dart';
import 'package:bilifast/app/zoom_back_route.dart';
import 'package:bilifast/comments/comment_overlays.dart';
import 'package:bilifast/comments/comment_row.dart';
import 'package:bilifast/comments/comments_tab.dart';
import 'package:bilifast/danmaku/danmaku_layer.dart';
import 'package:bilifast/danmaku/danmaku_overlays.dart';
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/device/player_device.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/panels/panel_layer.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/space/uploader_sheet.dart';
import 'package:bilifast/video/actions/action_overlays.dart';
import 'package:bilifast/video/actions/video_actions.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/intro/intro_tab.dart';
import 'package:bilifast/video/intro/related_list.dart';
import 'package:bilifast/video/pad/pad_body.dart';
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
  var withActions = false;

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
  }) => FakePageDetails(actions: withActions ? FakeVideoActions() : null);

  /// [systemFont] renders under the stand-ins for the iPad's system font, set once the app's font store has loaded.
  Future<void> host(WidgetTester tester, {bool landscape = true, bool phone = false, bool systemFont = false}) async {
    if (phone) {
      showAsPhone(tester);
    } else {
      showAsPad(tester, landscape: landscape);
      expect(FormFactor.device, FormFactor.pad, reason: 'the orientation rules are the iPad\'s');
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
      expect(find.byType(PadIntroHead), findsOneWidget);
      expect(find.byType(PadCommentsHeader), findsOneWidget, reason: '热门评论 inline under 简介');
      expect(
        tester.getTopLeft(find.byType(PadCommentsHeader)).dy,
        tester.getBottomLeft(find.byType(PadIntroHead)).dy,
        reason: 'right under the head',
      );
      expect(tester.getRect(find.byType(PadCommentsHeader)).width, column);
      expect(find.text('热门评论'), findsOneWidget);
      expect(find.text('查看 30 条评论'), findsOneWidget);
      expect(find.byType(PageTabRow), findsNothing);
      expect(find.byType(PadPageTabRow), findsNothing, reason: 'no tabs sideways');
      expect(
        find.descendant(of: find.byType(PadIntroHead), matching: find.byType(PadDanmakuCapsule)),
        findsOneWidget,
        reason: '点我发弹幕 on the uploader row, drawn by the head',
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
      expect(find.byType(IntroTab), findsOneWidget);
      expect(find.byType(PadIntroHead), findsOneWidget);
      expect(find.byType(RelatedSliver), findsOneWidget);
      expect(find.byType(PadRelatedColumn), findsNothing);
      expect(
        tester.getRect(find.descendant(of: find.byType(PadPageTabRow), matching: find.byType(PadDanmakuCapsule))).right,
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

    testWidgets('under the iPad\'s rules 竖屏 is full screen, and turning the iPad never changes it', (tester) async {
      await host(tester, landscape: false);
      await opened(tester);
      orientation.enterVertical();
      await tester.pump();
      await tester.pump(PadPageTheme.fullScreenGrow);
      expect(orientation.presentation, Presentation.landscape);
      expect(area(tester), Offset.zero & tall);
      await turn(tester, wide);
      expect(orientation.presentation, Presentation.landscape);
      expect(area(tester), Offset.zero & wide);
      orientation.exitToInline();
      await tester.pump();
      await tester.pump(PadPageTheme.fullScreenGrow + const Duration(milliseconds: 50));
      expect(area(tester), const Rect.fromLTWH(0, band, column, column / BiliMetrics.videoAspect));
      await back(tester);
    });

    testWidgets('评论 from full screen goes back to the page with the column where it was', (tester) async {
      await host(tester);
      await opened(tester);
      orientation.enterLandscape();
      await tester.pump();
      await tester.pump(PadPageTheme.fullScreenGrow);
      ui(tester).onComments!();
      await tester.pump();
      await tester.pump(PadPageTheme.fullScreenGrow + const Duration(milliseconds: 50));
      expect(orientation.presentation, Presentation.inline);
      expect(columnScroll(tester).pixels, 0);
      await back(tester);
    });

    testWidgets('the danmaku layer lays out for the iPad, as the chrome does', (tester) async {
      await host(tester);
      await opened(tester);
      expect(tester.widget<DanmakuLayer>(find.byKey(const ValueKey('video-danmaku'))).formFactor, FormFactor.pad);
      orientation.enterLandscape();
      await tester.pump();
      await tester.pump(PadPageTheme.fullScreenGrow);
      expect(tester.widget<DanmakuLayer>(find.byKey(const ValueKey('video-danmaku'))).formFactor, FormFactor.pad);
      orientation.exitToInline();
      await tester.pump();
      await tester.pump(PadPageTheme.fullScreenGrow + const Duration(milliseconds: 50));
      await back(tester);
    });

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

  group('turning keeps the page where it was (23)', () {
    ScrollPosition tabScroll(WidgetTester tester, Type tab) => tester
        .state<ScrollableState>(find.descendant(of: find.byType(tab), matching: find.byType(Scrollable)).first)
        .position;
    Rect collapseBar(WidgetTester tester) => tester.getRect(find.byKey(const ValueKey('collapse-bar')));
    const sidewaysReserve = column / BiliMetrics.videoAspect - PadPageTheme.barHeight;
    const uprightReserve = 834 / BiliMetrics.videoAspect - PadPageTheme.barHeight;

    testWidgets('upright 评论 keeps its place through a turn sideways and back', (tester) async {
      await host(tester, landscape: false);
      await opened(tester);
      await tester.tap(find.byKey(const ValueKey('tab-comments')));
      await frames(tester, 20);
      tabScroll(tester, CommentsTab).jumpTo(600);
      await frames(tester, 2);
      await turn(tester, wide);
      await turn(tester, tall);
      await frames(tester, 4);
      expect(tabScroll(tester, CommentsTab).pixels, 600);
      expect(find.byType(CommentsTab).hitTestable(), findsOneWidget, reason: 'still on 评论');
      await back(tester);
    });

    testWidgets('the sideways column keeps its place through a turn upright and back, upright 简介 its own', (tester) async {
      await host(tester);
      await opened(tester);
      columnScroll(tester).jumpTo(300);
      await frames(tester, 2);
      await turn(tester, tall);
      expect(
        tabScroll(tester, IntroTab).pixels,
        closeTo(300 * uprightReserve / sidewaysReserve, 0.01),
        reason: 'inside the reserve, in proportion',
      );
      await turn(tester, wide);
      expect(columnScroll(tester).pixels, closeTo(300, 0.01));

      columnScroll(tester).jumpTo(sidewaysReserve + 100);
      await frames(tester, 2);
      await turn(tester, tall);
      expect(tabScroll(tester, IntroTab).pixels, closeTo(uprightReserve + 100, 0.01), reason: 'past it, one for one');
      tabScroll(tester, IntroTab).jumpTo(250);
      await frames(tester, 2);
      await turn(tester, wide);
      await turn(tester, tall);
      expect(tabScroll(tester, IntroTab).pixels, closeTo(250, 0.01));
      await back(tester);
    });

    testWidgets('paused sideways as the bar with the strip, two turns keep the bar, the strip and the scroll',
        (tester) async {
      await host(tester);
      await opened(tester);
      player.emit(const StatusChanged(PlayerStatus.paused));
      await frames(tester, 2);
      await tester.timedDragFrom(const Offset(300, 700), const Offset(0, -600), const Duration(milliseconds: 300));
      await frames(tester, 60);
      final scrolled = columnScroll(tester).pixels;
      expect(find.byKey(const ValueKey('pad-pinned-strip')), findsOneWidget);
      await turn(tester, tall);
      expect(collapseBar(tester), const Rect.fromLTWH(0, band, 834, PadPageTheme.barHeight));
      await turn(tester, wide);
      await frames(tester, 2);
      expect(columnScroll(tester).pixels, closeTo(scrolled, 0.01));
      expect(collapseBar(tester), const Rect.fromLTWH(0, band, column, PadPageTheme.barHeight));
      expect(
        tester.getRect(find.byKey(const ValueKey('page-player'))).height,
        band + PadPageTheme.barHeight,
        reason: 'still the bar while paused',
      );
      expect(find.byKey(const ValueKey('pad-pinned-strip')), findsOneWidget);
      expect(find.byKey(const ValueKey('pad-comment-bar')), findsOneWidget);
      await back(tester);
    });

    testWidgets('paused upright on 简介 as the bar, sideways shows the bar over a column scrolled to match',
        (tester) async {
      await host(tester, landscape: false);
      await opened(tester);
      player.emit(const StatusChanged(PlayerStatus.paused));
      await frames(tester, 2);
      tabScroll(tester, IntroTab).jumpTo(1200);
      await frames(tester, 4);
      expect(collapseBar(tester).height, PadPageTheme.barHeight);
      await turn(tester, wide);
      await frames(tester, 2);
      expect(columnScroll(tester).pixels, closeTo(1200 - uprightReserve + sidewaysReserve, 0.01));
      expect(collapseBar(tester), const Rect.fromLTWH(0, band, column, PadPageTheme.barHeight));
      expect(find.byKey(const ValueKey('pad-pinned-strip')), findsOneWidget, reason: 'the head is under the bar');
      expect(find.byKey(const ValueKey('pad-comment-bar')), findsOneWidget);
      await back(tester);
    });

    testWidgets('paused upright on 评论 as the bar: sideways follows 简介, and back upright 评论 is the bar again',
        (tester) async {
      await host(tester, landscape: false);
      await opened(tester);
      await tester.tap(find.byKey(const ValueKey('tab-comments')));
      await frames(tester, 20);
      player.emit(const StatusChanged(PlayerStatus.paused));
      await frames(tester, 2);
      tabScroll(tester, CommentsTab).jumpTo(600);
      await frames(tester, 4);
      expect(collapseBar(tester).height, PadPageTheme.barHeight);
      await turn(tester, wide);
      await frames(tester, 2);
      expect(columnScroll(tester).pixels, 0);
      expect(find.byKey(const ValueKey('collapse-bar')), findsNothing, reason: '简介 is at its top');
      await turn(tester, tall);
      await frames(tester, 4);
      expect(tabScroll(tester, CommentsTab).pixels, 600);
      expect(collapseBar(tester), const Rect.fromLTWH(0, band, 834, PadPageTheme.barHeight));
      await back(tester);
    });

    testWidgets('a turn remounts none of the page\'s layers', (tester) async {
      await host(tester);
      await opened(tester);
      final layers = [CommentOverlays, PanelLayer, ActionOverlays, UploaderSheetLayer, DanmakuOverlays];
      final before = [for (final type in layers) tester.element(find.byType(type))];
      for (final size in [tall, wide]) {
        await turn(tester, size);
        for (final (i, type) in layers.indexed) {
          expect(identical(tester.element(find.byType(type)), before[i]), isTrue, reason: '$type at $size');
        }
      }
      await back(tester);
    });
  });

  group('the sideways column\'s scrolling', () {
    testWidgets('rebuilds neither the head nor the comments frame by frame, playing or paused', (tester) async {
      await host(tester);
      await opened(tester);
      var heads = 0;
      var rows = 0;
      var pages = 0;
      // A list row built for the first time as it scrolls in isn't a rebuild.
      final seen = <Element>{};
      final saved = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, _) {
        if (element.widget is VideoPage) pages++;
        if (element.widget is! PadIntroHead && element.widget is! CommentRow) return;
        if (!seen.add(element)) {
          if (element.widget is PadIntroHead) heads++;
          if (element.widget is CommentRow) rows++;
        }
      };
      addTearDown(() => debugOnRebuildDirtyWidget = saved);
      await tester.timedDragFrom(const Offset(300, 700), const Offset(0, -300), const Duration(milliseconds: 300));
      await frames(tester);
      expect((heads, rows, pages), (0, 0, 0), reason: 'playing');
      columnScroll(tester).jumpTo(0);
      await frames(tester, 2);
      player.emit(const StatusChanged(PlayerStatus.paused));
      await frames(tester, 2);
      heads = 0;
      rows = 0;
      pages = 0;
      await tester.timedDragFrom(const Offset(300, 700), const Offset(0, -600), const Duration(milliseconds: 400));
      await frames(tester);
      expect(find.byKey(const ValueKey('pad-pinned-strip')), findsOneWidget);
      // The page itself rebuilds where the shrink starts and where it becomes the bar, not on every frame.
      expect(pages, lessThanOrEqualTo(2));
      expect(heads, lessThanOrEqualTo(pages));
      expect(rows, lessThanOrEqualTo(pages * 10));
      debugOnRebuildDirtyWidget = saved;
      await back(tester);
    });
  });

  group('an upright video (a guess: no iPad screenshot)', () {
    for (final (name, size, width) in [('sideways', wide, column), ('upright', tall, 834.0)]) {
      testWidgets('$name: the box stays 16:9', (tester) async {
        await host(tester, landscape: size == wide);
        await opened(tester);
        sessions.single
          ..videoShape = (width: 1080, height: 1920)
          ..changed();
        await frames(tester, 10);
        expect(area(tester), Rect.fromLTWH(0, band, width, width / BiliMetrics.videoAspect));
        await tester.timedDragFrom(const Offset(300, 700), const Offset(0, -300), const Duration(milliseconds: 300));
        await frames(tester);
        expect(area(tester).top, band, reason: 'playing, the video follows the box: nothing cut at the top');
        expect(area(tester).height, width / BiliMetrics.videoAspect);
        await back(tester);
      });
    }
  });

  group('the page\'s sheets and the send bar (a guess: no iPad screenshot has one open)', () {
    Finder dimIn(Type layer) => find.descendant(of: find.byType(layer), matching: find.byType(PadSheetDim));
    Finder relatedCard(String bvid) =>
        find.byWidgetPredicate((widget) => switch (widget.key) {
          ValueKey<(int, String)>(value: (_, final b)) => b == bvid,
          _ => false,
        });
    final otherPage = find.byWidgetPredicate((widget) => widget is VideoPage && widget.route.bvid != bv);
    ActionOverlayController actionOverlays(WidgetTester tester) =>
        tester.widget<ActionOverlays>(find.byType(ActionOverlays)).controller;

    Future<void> openWithActions(WidgetTester tester, Size size) async {
      withActions = true;
      addTearDown(() => withActions = false);
      await host(tester, landscape: size == wide);
      await opened(tester);
    }

    /// Taps [at], beside the player, and checks it closed what [isOpen] reads and opened no video.
    Future<void> tapClosesOnly(WidgetTester tester, Offset at, bool Function() isOpen, String reason) async {
      expect(isOpen(), isTrue, reason: reason);
      await tester.tapAt(at);
      await frames(tester, 10);
      expect(isOpen(), isFalse, reason: reason);
      expect(otherPage, findsNothing, reason: '$reason: no video opened');
    }

    for (final (name, size, width) in [('sideways', wide, column), ('upright', tall, 834.0)]) {
      // Sideways a related card where it sits beside the player; upright the band over the player.
      Offset outside(WidgetTester tester) {
        if (size != wide) return const Offset(400, band / 2);
        final card = tester.getRect(relatedCard('BV1r0'));
        return Offset(card.center.dx, (card.top + math.min(card.bottom, area(tester).bottom)) / 2);
      }

      testWidgets('$name: the send bar is the column\'s width, all but the player dims, and a tap there closes it',
          (tester) async {
        await openWithActions(tester, size);
        if (size == wide) {
          expect(tester.getRect(relatedCard('BV1r0')).top, lessThan(area(tester).bottom), reason: 'beside the player');
        }
        final danmaku = ui(tester).danmaku!..openSend();
        await frames(tester, 4);
        final bar = tester.getRect(find.byKey(const ValueKey('danmaku-send-bar')));
        expect((bar.left, bar.width), (0.0, width));
        expect(tester.widget<PadSheetDim>(dimIn(DanmakuOverlays)).player, area(tester));
        expect(tester.getRect(dimIn(DanmakuOverlays)), Offset.zero & size);
        await tester.tapAt(area(tester).center);
        await frames(tester, 4);
        expect(danmaku.sendOpen.value, isTrue, reason: 'the player itself takes its own taps');
        await tapClosesOnly(tester, outside(tester), () => danmaku.sendOpen.value, 'send bar');
        await back(tester);
      });

      for (final panel in [PlayerPanel.more, PlayerPanel.speed, PlayerPanel.danmakuSettings, PlayerPanel.episodes]) {
        testWidgets('$name: ${panel.name} is the column\'s width under the player, all but the player dims, and a tap '
            'there closes it', (tester) async {
          await openWithActions(tester, size);
          final panels = ui(tester).panels..open(panel);
          await frames(tester, 10);
          final sheet = tester.getRect(find.byKey(const ValueKey('panel-frame')));
          expect((sheet.left, sheet.width, sheet.bottom), (0.0, width, size.height));
          expect(sheet.top, greaterThanOrEqualTo(area(tester).bottom - 0.01));
          expect(tester.widget<PadSheetDim>(dimIn(PanelLayer)).player, area(tester));
          expect(tester.getRect(dimIn(PanelLayer)), Offset.zero & size);
          await tapClosesOnly(tester, outside(tester), () => panels.value != null, panel.name);
          await back(tester);
        });
      }

      testWidgets('$name: 收藏 is the column\'s width from the player down, all but the player dims, and a tap there '
          'closes it', (tester) async {
        await openWithActions(tester, size);
        final controller = actionOverlays(tester)..value = ActionPrompt.favourites;
        await frames(tester, 10);
        final sheet = tester.getRect(find.byKey(const ValueKey('favourite-sheet')));
        expect(sheet, Rect.fromLTRB(0, area(tester).bottom, width, size.height));
        expect(tester.widget<PadSheetDim>(dimIn(ActionOverlays)).player, area(tester));
        expect(tester.getRect(dimIn(ActionOverlays)), Offset.zero & size);
        await tapClosesOnly(tester, outside(tester), () => controller.value != null, '收藏');
        await back(tester);
      });
    }

    testWidgets('with nothing up, the related card beside the player opens its video', (tester) async {
      await host(tester);
      await opened(tester);
      await tester.tap(relatedCard('BV1r0'));
      await frames(tester, 20);
      expect(otherPage, findsOneWidget, reason: 'so the taps above reached the dim, not the card');
    });

    testWidgets('the iPhone\'s sheets and send bar keep the full width and dim nothing above the player', (tester) async {
      withActions = true;
      addTearDown(() => withActions = false);
      await host(tester, phone: true);
      await opened(tester);
      final player = area(tester);
      ui(tester).danmaku!.openSend();
      await frames(tester, 4);
      expect(find.byType(PadSheetDim), findsNothing);
      expect(tester.getRect(find.byKey(const ValueKey('danmaku-send-dim'))), Rect.fromLTRB(0, player.bottom, 440, 956));
      expect(tester.getRect(find.byKey(const ValueKey('danmaku-send-bar'))).width, 440);
      ui(tester).danmaku!.closeSend();
      await frames(tester, 4);
      final panels = ui(tester).panels..open(PlayerPanel.danmakuSettings);
      await frames(tester, 10);
      expect(find.byType(PadSheetDim), findsNothing);
      expect(tester.getRect(find.byKey(const ValueKey('panel-sheet-dim'))), Rect.fromLTRB(0, player.bottom, 440, 956));
      expect(tester.getRect(find.byKey(const ValueKey('panel-frame'))).width, 440);
      panels.close();
      await frames(tester, 10);
      actionOverlays(tester).value = ActionPrompt.favourites;
      await frames(tester, 10);
      expect(find.byType(PadSheetDim), findsNothing);
      expect(tester.getRect(find.byKey(const ValueKey('favourite-sheet'))).width, 440);
      await back(tester);
    });
  });

  group('05\'s strip and 发条评论 bar', () {
    Future<void> collapsed(WidgetTester tester) async {
      withActions = true;
      addTearDown(() => withActions = false);
      await host(tester, systemFont: true);
      await opened(tester);
      player.emit(const StatusChanged(PlayerStatus.paused));
      await frames(tester, 2);
      await tester.timedDragFrom(const Offset(300, 700), const Offset(0, -600), const Duration(milliseconds: 300));
      await frames(tester);
    }

    testWidgets('the strip\'s actions at a 62 pt pitch from 79.75', (tester) async {
      await collapsed(tester);
      final strip = find.byKey(const ValueKey('pad-pinned-strip'));
      final keys = ['action-like', 'action-dislike', 'action-coin', 'action-favourite', 'action-share'];
      for (final (i, key) in keys.indexed) {
        final cell = find.descendant(of: strip, matching: find.byKey(ValueKey(key)));
        expect(tester.getCenter(cell).dx, closeTo(79.75 + 31 + 62 * i, 0.01), reason: key);
      }
      await back(tester);
    });

    testWidgets('the bar: the rule at 788.5, the 32 pt field, the face inside it and ↑ back to the top', (tester) async {
      await collapsed(tester);
      final bar = find.byKey(const ValueKey('pad-comment-bar'));
      expect(tester.getRect(bar), const Rect.fromLTWH(0, 788.5, column, 45.5));
      final field = find.descendant(of: bar, matching: find.byKey(const ValueKey('comment-field-box')));
      expect(tester.getRect(field), const Rect.fromLTRB(20, 795.5, column - 47.75, 827.5));
      final face = find.descendant(of: bar, matching: find.byKey(const ValueKey('comment-emotes')));
      expect(tester.getCenter(face), const Offset(column - 47.75 - 15.75, 811.5));
      final top = find.descendant(of: bar, matching: find.byKey(const ValueKey('comment-top')));
      expect(tester.getCenter(top), const Offset(column - 23.5, 811.5));
      final prompt = find.descendant(of: bar, matching: find.byType(Text));
      expect(tester.widget<Text>(prompt).style!.fontSize, PadPageTheme.commentPromptText);
      expect(tester.getTopLeft(prompt).dx, 40);
      expect(find.byType(CommentWriteBar), findsNothing, reason: 'not the iPhone\'s bar');
      await tester.tap(top);
      await frames(tester, 20);
      expect(columnScroll(tester).pixels, 0);
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
      expect(find.byType(PadIntroHead), findsNothing);
      expect(area(tester).top, 62);
      expect(tester.widget<DanmakuLayer>(find.byKey(const ValueKey('video-danmaku'))).formFactor, FormFactor.phone);
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
