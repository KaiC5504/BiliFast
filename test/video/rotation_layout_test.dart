import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart' show ManualClock;
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/route_observer.dart';
import 'package:bilifast/app/swipe_back_route.dart';
import 'package:bilifast/danmaku/danmaku_layer.dart';
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/device/player_device.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player_ui/landscape_chrome.dart';
import 'package:bilifast/player_ui/portrait_controls.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/page_session.dart' show SessionOpen;
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

const bv = 'BV1GJ411x7h7';
const portrait = Size(440, 956);
const landscape = Size(956, 440);
const portraitInsets = FakeViewPadding(top: 62, bottom: 34);
const landscapeInsets = FakeViewPadding(left: 62, right: 62, bottom: 21);

const small = Rect.fromLTWH(0, 62, 440, 440 / BiliMetrics.videoAspect);
const full = Rect.fromLTWH(0, 0, 956, 440);

/// iOS sends the turned size only halfway through the rotation, so the page lays out by the screen's shape and grows
/// the player from its small spot to full screen once the size has come (01 in local/differences).
void main() {
  late FakePlayer player;
  late OrientationController orientation;
  late List<FakePlayerSession> sessions;
  late GlobalKey<NavigatorState> nav;

  setUp(() {
    player = FakePlayer();
    orientation = OrientationController();
    sessions = [];
    nav = GlobalKey<NavigatorState>();
  });

  void screen(WidgetTester tester, Size size, FakeViewPadding insets) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = insets;
    tester.view.viewPadding = insets;
  }

  PlayerSession fakeSession({
    required PlaybackController controller,
    required AppServices services,
    required SessionOpen open,
    required void Function(double seconds) onSeeked,
    required VoidCallback requestLogin,
  }) {
    final session = FakePlayerSession(player: player);
    sessions.add(session);
    return session;
  }

  /// A video page with its video loaded, owning the orientation, on the upright phone.
  Future<void> openPage(WidgetTester tester) async {
    screen(tester, portrait, portraitInsets);
    addTearDown(tester.view.reset);
    final logger = Logger(session: 'test');
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: Canned.http(),
      logger: logger,
    );
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
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        navigatorObservers: [pageRoutes],
        builder: (context, child) => AppScope(services: services, child: child!),
        home: const SizedBox(),
      ),
    );
    unawaited(
      nav.currentState!.push(
        SwipeBackPageRoute<void>(
          builder: (_) => VideoPage(
            route: const VideoRoute(bvid: bv, cid: 137649199, start: 0),
            createSession: fakeSession,
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
    sessions.single
      ..video = controller.video
      ..isVertical = false
      ..changed();
    await tester.pump();
  }

  /// Back to the small player and off the page, so nothing of it is left running.
  Future<void> leave(WidgetTester tester) async {
    orientation.exitToInline();
    screen(tester, portrait, portraitInsets);
    nav.currentState!.pop();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Rect area(WidgetTester tester) => tester.getRect(find.byType(VideoPlayerArea));
  Rect tabRow(WidgetTester tester) => tester.getRect(find.byType(PageTabRow));
  Color background(WidgetTester tester) =>
      tester.widget<Scaffold>(find.ancestor(of: find.byType(VideoPlayerArea), matching: find.byType(Scaffold))).backgroundColor!;

  /// The turn's second half: the screen has its new size, and the player grows.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(RotationTheme.grow);
    await tester.pump();
  }

  testWidgets('landscape while the screen is still upright keeps the upright page: the small player, the tab row and '
      'the list, which then turn as one piece', (tester) async {
    await openPage(tester);
    orientation.enterLandscape();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(orientation.presentation, Presentation.landscape);
    expect(area(tester), small);
    expect(tabRow(tester).top, small.bottom);
    expect(find.byType(PageTabs), findsOneWidget);
    expect(find.byType(PortraitControls), findsOneWidget);
    expect(find.byType(LandscapeChrome), findsNothing);
    expect(background(tester), BiliColors.card);
    await leave(tester);
  });

  testWidgets('once the screen is landscape, full screen is laid out: the player fills it and the body is out of '
      'sight', (tester) async {
    await openPage(tester);
    orientation.enterLandscape();
    await tester.pump();
    screen(tester, landscape, landscapeInsets);
    await settle(tester);
    expect(area(tester), full);
    expect(find.byType(LandscapeChrome), findsOneWidget);
    expect(find.byType(PortraitControls), findsNothing);
    expect(find.byType(PageTabRow), findsNothing, reason: 'offstage');
    expect(background(tester), BiliColors.videoBackground);
    await leave(tester);
  });

  testWidgets('the player grows from its small spot to full screen with the tab row on its bottom edge, keeping the '
      'native view, the danmaku and the area', (tester) async {
    await openPage(tester);
    final video = tester.element(find.byKey(const ValueKey('fake-video')));
    final danmaku = tester.element(find.byType(DanmakuLayer));
    final areaElement = tester.element(find.byType(VideoPlayerArea));
    orientation.enterLandscape();
    await tester.pump();
    screen(tester, landscape, landscapeInsets);
    await tester.pump();
    expect(area(tester), small, reason: 'the first frame at the new size starts where the player was');
    expect(tabRow(tester).top, small.bottom);

    var last = area(tester);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 25));
      final now = area(tester);
      expect(now.width, greaterThanOrEqualTo(last.width));
      expect(now.height, greaterThanOrEqualTo(last.height));
      expect(tabRow(tester).top, now.bottom, reason: 'the body rides on the player');
      expect(tabRow(tester).width, 440, reason: 'at its upright size');
      last = now;
    }
    expect(last.width, allOf(greaterThan(small.width), lessThan(full.width)));
    expect(last.height, allOf(greaterThan(small.height), lessThan(full.height)));
    expect(
      tester.getSize(find.byType(DanmakuLayer)),
      full.size,
      reason: 'the danmaku lay out once at the size they end at, scaled to the box meanwhile',
    );

    await tester.pump(RotationTheme.grow);
    await tester.pump();
    expect(area(tester), full);
    expect(find.byType(PageTabRow), findsNothing);
    expect(identical(tester.element(find.byKey(const ValueKey('fake-video'))), video), isTrue);
    expect(identical(tester.element(find.byType(DanmakuLayer)), danmaku), isTrue);
    expect(identical(tester.element(find.byType(VideoPlayerArea)), areaElement), isTrue);
    await leave(tester);
  });

  testWidgets('with Reduce Motion the player is full screen at once', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await openPage(tester);
    orientation.enterLandscape();
    await tester.pump();
    screen(tester, landscape, landscapeInsets);
    await tester.pump();
    expect(area(tester), full);
    expect(find.byType(PageTabRow), findsNothing);

    orientation.exitToInline();
    screen(tester, portrait, portraitInsets);
    await tester.pump();
    expect(area(tester), small);
    await leave(tester);
  });

  testWidgets('going back, landscape stays laid out until the screen is upright, then the player shrinks back over '
      'the body', (tester) async {
    await openPage(tester);
    orientation.enterLandscape();
    await tester.pump();
    screen(tester, landscape, landscapeInsets);
    await settle(tester);

    orientation.exitToInline();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(orientation.presentation, Presentation.inline);
    expect(area(tester), full);
    expect(find.byType(LandscapeChrome), findsOneWidget);
    expect(find.byType(PageTabRow), findsNothing);

    screen(tester, portrait, portraitInsets);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 50));
    final mid = area(tester);
    expect(mid.height, allOf(lessThan(full.height), greaterThan(small.height)));
    expect(find.byType(PortraitControls), findsOneWidget);
    expect(tabRow(tester).top, mid.bottom);

    await tester.pump(RotationTheme.grow);
    await tester.pump();
    expect(area(tester), small);
    expect(tabRow(tester).top, small.bottom);
    expect(background(tester), BiliColors.card);
    await leave(tester);
  });
}

class _NoLogin implements LoginGate {
  @override
  Future<bool> request(BuildContext context) async => false;
}
