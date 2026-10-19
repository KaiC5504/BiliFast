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
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/panels/panel_layer.dart';
import 'package:bilifast/player_ui/panels/panel_parts.dart';
import 'package:bilifast/player_ui/player_ui.dart';
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

/// The small player's box, with the status bar above it.
const smallBox = Rect.fromLTWH(0, 0, 440, 62 + 440 / BiliMetrics.videoAspect);

/// Frames of the turn before iOS hands over the turned size, about half of it.
const half = 8;

/// The player grows over the whole turn from the presentation's change, while the page lays out by the screen's
/// shape, which iOS hands over only halfway through the rotation (01 in local/differences).
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
  Rect box(WidgetTester tester) => tester.getRect(find.byKey(const ValueKey('page-player')));
  Rect tabRow(WidgetTester tester) => tester.getRect(find.byType(PageTabRow));
  Color background(WidgetTester tester) =>
      tester.widget<Scaffold>(find.ancestor(of: find.byType(VideoPlayerArea), matching: find.byType(Scaffold))).backgroundColor!;
  Finder backdrop() => find.byKey(const ValueKey('page-turn-backdrop'));

  Offset centre(WidgetTester tester) =>
      (tester.view.physicalSize / tester.view.devicePixelRatio).center(Offset.zero);

  /// The box about the screen's centre: where it is on the glass, whichever size iOS has handed over.
  Rect onGlass(WidgetTester tester) => box(tester).shift(-centre(tester));

  void expectRect(Rect actual, Rect expected, {String? reason}) {
    for (final (a, b) in [
      (actual.left, expected.left),
      (actual.top, expected.top),
      (actual.right, expected.right),
      (actual.bottom, expected.bottom),
    ]) {
      expect(a, closeTo(b, 0.01), reason: '$reason: $actual, not $expected');
    }
  }

  /// The tab row rides on the box's bottom edge at its upright width, centred under it.
  void expectBodyRides(WidgetTester tester, {String? reason}) {
    final row = tabRow(tester);
    expect(row.top, closeTo(box(tester).bottom, 0.01), reason: reason);
    expect(row.width, portrait.width, reason: reason);
    expect(row.center.dx, closeTo(centre(tester).dx, 0.01), reason: reason);
  }

  Future<void> frame(WidgetTester tester) => tester.pump(const Duration(milliseconds: 16));

  /// The rest of the turn.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(RotationTheme.grow);
    await tester.pump();
  }

  testWidgets('the player grows from the start of the turn while the screen is still upright: past the upright '
      "page's sides, over the upright layout, with the body riding its bottom edge", (tester) async {
    await openPage(tester);
    orientation.enterLandscape();
    await tester.pump();
    expect(orientation.presentation, Presentation.landscape);
    expectRect(box(tester), smallBox, reason: 'the first frame starts where the player was');

    var last = box(tester);
    for (var i = 0; i < half; i++) {
      await frame(tester);
      final now = box(tester);
      expect(now.width, greaterThan(last.width), reason: 'frame $i grows');
      expect(now.height, greaterThan(last.height), reason: 'frame $i grows');
      expectBodyRides(tester, reason: 'frame $i');
      last = now;
    }
    expect(last.width, greaterThan(portrait.width), reason: "past the upright page's sides");
    expect(last.center.dy, greaterThan(smallBox.center.dy), reason: "on its way to the screen's centre");
    expect(find.byType(PortraitControls), findsOneWidget, reason: 'laid out upright while the screen is');
    expect(find.byType(LandscapeChrome), findsNothing);
    expect(find.byType(PageTabs), findsOneWidget);
    expect(backdrop(), findsOneWidget, reason: 'black where the box has moved off');
    screen(tester, landscape, landscapeInsets);
    await settle(tester);
    await leave(tester);
  });

  testWidgets('nothing moves as the turned size comes, and the player grows on to full screen, keeping the native '
      'view, the danmaku and the area', (tester) async {
    await openPage(tester);
    final video = tester.element(find.byKey(const ValueKey('fake-video')));
    final danmaku = tester.element(find.byType(DanmakuLayer));
    final areaElement = tester.element(find.byType(VideoPlayerArea));
    orientation.enterLandscape();
    await tester.pump();
    for (var i = 0; i < half; i++) {
      await frame(tester);
    }
    final before = onGlass(tester);

    screen(tester, landscape, landscapeInsets);
    await tester.pump();
    expectRect(onGlass(tester), before, reason: 'centre-anchored across the size flip');
    expectBodyRides(tester, reason: 'at the size flip');
    expect(find.byType(LandscapeChrome), findsOneWidget, reason: "laid out for the screen's new shape");
    expect(
      tester.getSize(find.byType(DanmakuLayer)),
      full.size,
      reason: 'the danmaku lay out once at the size they end at, scaled to the box meanwhile',
    );

    var last = before;
    for (var i = 0; i < 6; i++) {
      await frame(tester);
      final now = onGlass(tester);
      expect(now.width, greaterThan(last.width), reason: 'frame $i grows');
      expect(now.height, greaterThan(last.height), reason: 'frame $i grows');
      expectBodyRides(tester, reason: 'frame $i');
      last = now;
    }
    expect(last.width, lessThan(full.width));

    await tester.pump(RotationTheme.grow);
    await tester.pump();
    expect(area(tester), full);
    expect(find.byType(PageTabRow), findsNothing, reason: 'offstage');
    expect(backdrop(), findsNothing);
    expect(background(tester), BiliColors.videoBackground);
    expect(identical(tester.element(find.byKey(const ValueKey('fake-video'))), video), isTrue);
    expect(identical(tester.element(find.byType(DanmakuLayer)), danmaku), isTrue);
    expect(identical(tester.element(find.byType(VideoPlayerArea)), areaElement), isTrue);
    await leave(tester);
  });

  testWidgets('a window that flips at once (Windows) grows the player from the small spot mapped about the centre to '
      'full screen', (tester) async {
    await openPage(tester);
    orientation.enterLandscape();
    screen(tester, landscape, landscapeInsets);
    await tester.pump();
    expectRect(onGlass(tester), smallBox.shift(-portrait.center(Offset.zero)), reason: 'the first frame');
    expectBodyRides(tester, reason: 'the first frame');
    expect(find.byType(LandscapeChrome), findsOneWidget);

    var last = box(tester);
    for (var i = 0; i < 12; i++) {
      await frame(tester);
      final now = box(tester);
      expect(now.width, greaterThan(last.width), reason: 'frame $i grows');
      expectBodyRides(tester, reason: 'frame $i');
      last = now;
    }
    await settle(tester);
    expect(area(tester), full);
    expect(find.byType(PageTabRow), findsNothing);
    await leave(tester);
  });

  testWidgets('with Reduce Motion nothing grows: the small player until the screen is landscape, then full screen',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await openPage(tester);
    orientation.enterLandscape();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(area(tester), small);
    expect(backdrop(), findsNothing);
    screen(tester, landscape, landscapeInsets);
    await tester.pump();
    expect(area(tester), full);
    expect(find.byType(PageTabRow), findsNothing);

    orientation.exitToInline();
    await tester.pump();
    expect(area(tester), full);
    screen(tester, portrait, portraitInsets);
    await tester.pump();
    expect(area(tester), small);
    await leave(tester);
  });

  testWidgets('going back, the player shrinks from the start of the turn over the landscape layout, the body riding '
      'in on its bottom edge, and on across the size flip to the small player', (tester) async {
    await openPage(tester);
    orientation.enterLandscape();
    await tester.pump();
    screen(tester, landscape, landscapeInsets);
    await settle(tester);

    orientation.exitToInline();
    await tester.pump();
    expect(orientation.presentation, Presentation.inline);
    expect(area(tester), full, reason: 'the first frame starts at full screen');
    var last = box(tester);
    for (var i = 0; i < half; i++) {
      await frame(tester);
      final now = box(tester);
      expect(now.width, lessThan(last.width), reason: 'frame $i shrinks');
      expect(now.height, lessThan(last.height), reason: 'frame $i shrinks');
      expectBodyRides(tester, reason: 'frame $i');
      last = now;
    }
    expect(find.byType(LandscapeChrome), findsOneWidget, reason: 'laid out for landscape while the screen is');
    expect(background(tester), BiliColors.videoBackground);
    final before = onGlass(tester);

    screen(tester, portrait, portraitInsets);
    await tester.pump();
    expectRect(onGlass(tester), before, reason: 'centre-anchored across the size flip');
    expectBodyRides(tester, reason: 'at the size flip');
    expect(find.byType(PortraitControls), findsOneWidget);
    expect(backdrop(), findsOneWidget);

    await tester.pump(RotationTheme.grow);
    await tester.pump();
    expect(area(tester), small);
    expect(tabRow(tester).top, small.bottom);
    expect(backdrop(), findsNothing);
    expect(background(tester), BiliColors.card);
    await leave(tester);
  });

  testWidgets('turned back upright after the size flip, the player shrinks from where it is drawn', (tester) async {
    await openPage(tester);
    orientation.enterLandscape();
    await tester.pump();
    for (var i = 0; i < half; i++) {
      await frame(tester);
    }
    screen(tester, landscape, landscapeInsets);
    await tester.pump();
    await frame(tester);
    await frame(tester);
    final mid = onGlass(tester);
    expect(mid.width, allOf(greaterThan(small.width), lessThan(full.width)));

    orientation.exitToInline();
    await tester.pump();
    expectRect(onGlass(tester), mid, reason: 'no jump to full screen or to the small spot');
    await frame(tester);
    final shrinking = onGlass(tester);
    expect(shrinking.width, lessThan(mid.width));

    screen(tester, portrait, portraitInsets);
    await tester.pump();
    expectRect(onGlass(tester), shrinking, reason: 'centre-anchored across the size flip back');
    await tester.pump(RotationTheme.grow);
    await tester.pump();
    expect(area(tester), small);
    expect(tabRow(tester).top, small.bottom);
    expect(find.byType(PortraitControls), findsOneWidget);
    await leave(tester);
  });

  testWidgets('a turn refused before the screen turned goes back from where the player is, and a wide screen then '
      'stays inline', (tester) async {
    await openPage(tester);
    orientation.enterLandscape();
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await frame(tester);
    }
    final mid = box(tester);
    expect(mid.width, greaterThan(portrait.width));

    orientation.exitToInline();
    await tester.pump();
    expectRect(box(tester), mid, reason: 'no jump');
    var last = mid;
    for (var i = 0; i < 4; i++) {
      await frame(tester);
      final now = box(tester);
      expect(now.width, lessThan(last.width), reason: 'frame $i shrinks back');
      expectBodyRides(tester, reason: 'frame $i');
      expect(find.byType(LandscapeChrome), findsNothing);
      last = now;
    }
    await settle(tester);
    expectRect(box(tester), smallBox, reason: 'back at the small player');
    expect(area(tester), small);
    expect(backdrop(), findsNothing);

    screen(tester, landscape, landscapeInsets);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(LandscapeChrome), findsNothing, reason: 'inline stays inline on a wide screen');
    expect(backdrop(), findsNothing);
    screen(tester, portrait, portraitInsets);
    await tester.pump();
    await leave(tester);
  });

  PlayerUi ui(WidgetTester tester) => tester.widget<PanelLayer>(find.byType(PanelLayer)).ui;
  bool panelLandscape(WidgetTester tester) => tester.widget<PanelScope>(find.byType(PanelScope)).landscape;

  testWidgets('a panel open in the small player stays the portrait sheet until the screen is landscape', (
    tester,
  ) async {
    await openPage(tester);
    ui(tester).panels.open(PlayerPanel.quality);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('panel-grabber')), findsOneWidget);

    orientation.enterLandscape();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(ui(tester).presentation, Presentation.inline, reason: 'drawn upright while the screen is');
    expect(panelLandscape(tester), isFalse);
    expect(find.byKey(const ValueKey('panel-grabber')), findsOneWidget);

    screen(tester, landscape, landscapeInsets);
    await settle(tester);
    expect(ui(tester).presentation, Presentation.landscape);
    expect(panelLandscape(tester), isTrue);
    expect(find.byKey(const ValueKey('panel-grabber')), findsNothing);
    ui(tester).panels.close();
    await tester.pump(const Duration(milliseconds: 400));
    await leave(tester);
  });

  testWidgets('弹幕设置 open while turning back stays the landscape strip, then is the light sheet from the small '
      "player's bottom", (tester) async {
    await openPage(tester);
    orientation.enterLandscape();
    await tester.pump();
    screen(tester, landscape, landscapeInsets);
    await settle(tester);
    ui(tester).panels.open(PlayerPanel.danmakuSettings);
    await tester.pump(const Duration(milliseconds: 400));
    expect(panelLandscape(tester), isTrue);

    orientation.exitToInline();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(panelLandscape(tester), isTrue, reason: 'the screen is still sideways');
    expect(find.byKey(const ValueKey('panel-sheet-dim')), findsNothing);

    screen(tester, portrait, portraitInsets);
    await tester.pump();
    expect(panelLandscape(tester), isFalse);
    expect(tester.getSize(find.byKey(const ValueKey('panel-sheet-dim'))).height, portrait.height - small.bottom);
    await settle(tester);
    expect(tester.getSize(find.byKey(const ValueKey('panel-sheet-dim'))).height, portrait.height - small.bottom);
    ui(tester).panels.close();
    await tester.pump(const Duration(milliseconds: 400));
    await leave(tester);
  });

  testWidgets('添加屏蔽词 gives way to 弹幕设置 once the page is laid out upright, not before', (tester) async {
    await openPage(tester);
    orientation.enterLandscape();
    await tester.pump();
    screen(tester, landscape, landscapeInsets);
    await settle(tester);
    final panels = ui(tester).panels..open(PlayerPanel.blockWords);
    await tester.pump(const Duration(milliseconds: 400));

    orientation.exitToInline();
    await tester.pump();
    expect(panels.value, PlayerPanel.blockWords, reason: 'still laid out for landscape');
    screen(tester, portrait, portraitInsets);
    await tester.pump();
    expect(panels.value, PlayerPanel.danmakuSettings);
    panels.close();
    await tester.pump(const Duration(milliseconds: 400));
    await leave(tester);
  });
}

class _NoLogin implements LoginGate {
  @override
  Future<bool> request(BuildContext context) async => false;
}
