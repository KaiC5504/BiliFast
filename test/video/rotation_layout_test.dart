import 'dart:async';
import 'dart:math' show atan2, pi;

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
import 'package:bilifast/player_ui/vertical_chrome.dart';
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
import '../device/fake_orientation_host.dart' show FakeOrientationHost;
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
    required VoidCallback willPlay,
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

  /// The tab row rides on the box's bottom edge at its upright width, hanging from its bottom-left corner as the
  /// official body does.
  void expectBodyRides(WidgetTester tester, {String? reason}) {
    final row = tabRow(tester);
    expect(row.top, closeTo(box(tester).bottom, 0.01), reason: reason);
    expect(row.width, portrait.width, reason: reason);
    expect(row.left, closeTo(box(tester).left, 0.01), reason: reason);
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

  /// Whether the player's chrome is painted; it stays laid out either way.
  bool chromeDrawn(WidgetTester tester) => tester
      .widget<Visibility>(
        find.descendant(of: find.byKey(const ValueKey('video-chrome')), matching: find.byType(Visibility)).first,
      )
      .visible;

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

  group('turns the page draws itself (旋转动画)', () {
    late FakeOrientationHost host;

    /// The page with the system's turns taken over, as the 开发者 switch leaves it on iOS.
    Future<void> openTakenOver(WidgetTester tester, {bool takeover = true}) async {
      host = FakeOrientationHost();
      orientation = OrientationController(host: host);
      await orientation.setTurnTakeover(takeover);
      await openPage(tester);
    }

    double angle(WidgetTester tester) {
      final matrix = tester.widget<Transform>(find.byKey(const ValueKey('page-turn'))).transform;
      return atan2(matrix.entry(1, 0), matrix.entry(0, 0));
    }

    /// Where [rect] on the screen of size [from] is on the glass once the screen is [to] and the page is drawn turned
    /// by [by] about its centre.
    Rect onTurned(Rect rect, {required Size from, required Size to, required double by}) => MatrixUtils.transformRect(
      Matrix4.translationValues(to.width / 2, to.height / 2, 0)
          .multiplied(Matrix4.rotationZ(by))
          .multiplied(Matrix4.translationValues(-from.width / 2, -from.height / 2, 0)),
      rect,
    );

    /// A touch on the player reaches it.
    bool touches(WidgetTester tester) => tester
        .hitTestOnBinding(box(tester).center)
        .path
        .any((entry) => entry.target == tester.renderObject(find.byType(VideoPlayerArea)));

    /// The turn into landscape full screen as iOS takes it over: the turned size first, then the turn.
    Future<void> turnToLandscape(WidgetTester tester) async {
      orientation.enterLandscape();
      await tester.pump();
      screen(tester, landscape, landscapeInsets);
      await tester.pump();
      host.startTurn(pi / 2);
      await tester.pump();
    }

    testWidgets('the size flips at once and the first frame is the upright page drawn turned by −angle where it sat; '
        'it turns upright as the player grows to full screen, reported drawn once', (tester) async {
      await openTakenOver(tester);
      final box0 = box(tester);
      final row0 = tabRow(tester);
      orientation.enterLandscape();
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await frame(tester);
      }
      expectRect(box(tester), box0, reason: "the player waits for the system's turn");
      expect(angle(tester), 0);

      screen(tester, landscape, landscapeInsets);
      await tester.pump();
      expect(host.drawn, 0, reason: 'nothing turned is drawn before the turn is known');
      host.startTurn(pi / 2);
      await tester.pump();
      expect(angle(tester), closeTo(-pi / 2, 1e-9));
      expectRect(box(tester), onTurned(box0, from: portrait, to: landscape, by: -pi / 2), reason: 'the box');
      expectRect(tabRow(tester), onTurned(row0, from: portrait, to: landscape, by: -pi / 2), reason: 'the tab row');
      expect(tester.getSize(find.byType(PageTabRow)), row0.size, reason: 'the body keeps its upright size');
      expect(backdrop(), findsOneWidget);
      expect(host.drawn, 0, reason: 'not before the frame is on the screen');
      await frame(tester);
      expect(host.drawn, 1);

      var last = angle(tester).abs();
      var width = box(tester).width;
      for (var i = 0; i < 10; i++) {
        await frame(tester);
        final now = angle(tester).abs();
        expect(now, lessThan(last), reason: 'frame $i turns upright');
        expect(box(tester).width, isNot(width), reason: 'frame $i grows');
        last = now;
        width = box(tester).width;
      }
      await tester.pump(RotationTheme.grow);
      await frame(tester);
      expect(angle(tester), 0);
      expect(area(tester), full);
      expect(find.byType(PageTabRow), findsNothing);
      expect(backdrop(), findsNothing);
      expect(find.byType(LandscapeChrome), findsOneWidget);
      expect(host.drawn, 1, reason: 'once per turn');
      await leave(tester);
    });

    testWidgets('turned back, the landscape page is drawn turned where it sat and shrinks to the small player as it '
        'turns upright', (tester) async {
      await openTakenOver(tester);
      await turnToLandscape(tester);
      await tester.pump(RotationTheme.grow);
      await frame(tester);
      expect(area(tester), full);

      orientation.exitToInline();
      await tester.pump();
      await frame(tester);
      expect(area(tester), full, reason: "the player waits for the system's turn");
      screen(tester, portrait, portraitInsets);
      await tester.pump();
      host.startTurn(-pi / 2);
      await tester.pump();
      expect(angle(tester), closeTo(pi / 2, 1e-9));
      expectRect(box(tester), onTurned(full, from: landscape, to: portrait, by: pi / 2), reason: 'the box');
      expect(tester.getRect(find.byType(PageTabRow)).intersect(Offset.zero & portrait).isEmpty, isTrue,
          reason: 'the body is off the glass, beside the full-screen player');
      await frame(tester);
      expect(host.drawn, 2);

      await tester.pump(RotationTheme.grow);
      await frame(tester);
      expect(angle(tester), 0);
      expect(area(tester), small);
      expect(tabRow(tester).top, small.bottom);
      expect(backdrop(), findsNothing);
      expect(background(tester), BiliColors.card);
      expect(host.drawn, 2);
      await leave(tester);
    });

    testWidgets('the chrome is put away from the change of presentation to the end of the turn and comes back as it '
        'was; touches reach nothing while the page turns', (tester) async {
      await openTakenOver(tester);
      ui(tester).chrome.show();
      await tester.pump();
      expect(chromeDrawn(tester), isTrue);
      expect(touches(tester), isTrue);

      orientation.enterLandscape();
      await tester.pump();
      expect(chromeDrawn(tester), isFalse, reason: "so the host's still picture has none either");
      screen(tester, landscape, landscapeInsets);
      await tester.pump();
      host.startTurn(pi / 2);
      await tester.pump();
      expect(chromeDrawn(tester), isFalse);
      expect(find.byType(DanmakuLayer), findsOneWidget, reason: 'the danmaku keep flowing');
      expect(touches(tester), isFalse);
      await tester.pump(const Duration(milliseconds: 140));
      expect(touches(tester), isFalse);
      await tester.pump(RotationTheme.grow);
      await frame(tester);
      expect(chromeDrawn(tester), isTrue);
      expect(ui(tester).chrome.visible, isTrue, reason: 'shown before, shown after');
      expect(touches(tester), isTrue);

      ui(tester).chrome.hide();
      orientation.exitToInline();
      await tester.pump();
      screen(tester, portrait, portraitInsets);
      await tester.pump();
      host.startTurn(-pi / 2);
      await tester.pump();
      expect(chromeDrawn(tester), isFalse);
      await tester.pump(RotationTheme.grow);
      await frame(tester);
      expect(chromeDrawn(tester), isTrue);
      expect(ui(tester).chrome.visible, isFalse, reason: 'hidden before, hidden after');
      await leave(tester);
    });

    testWidgets('a turn the page did not ask for is not drawn, only reported drawn', (tester) async {
      await openTakenOver(tester);
      host.startTurn(pi / 2);
      await tester.pump();
      expect(angle(tester), 0);
      expectRect(box(tester), smallBox);
      await tester.pump(RotationTheme.takeoverWait);
      await tester.pump();
      expect(angle(tester), 0);
      expect(host.drawn, 1, reason: "the host's picture never stays up");

      // Refused: back to the small player before its turn, which comes late.
      orientation.enterLandscape();
      await tester.pump();
      orientation.exitToInline();
      await tester.pump();
      expect(chromeDrawn(tester), isTrue, reason: 'no turn to wait for');
      host.startTurn(pi / 2);
      await tester.pump();
      await frame(tester);
      expect(angle(tester), 0);
      expectRect(box(tester), smallBox);
      await tester.pump(RotationTheme.takeoverWait);
      await tester.pump();
      expect(host.drawn, 2);
      await leave(tester);
    });

    testWidgets('with no turn from the system the player grows on its own after a short wait', (tester) async {
      await openTakenOver(tester);
      orientation.enterLandscape();
      await tester.pump();
      await tester.pump(RotationTheme.takeoverWait - const Duration(milliseconds: 20));
      expectRect(box(tester), smallBox, reason: 'still waiting');
      await tester.pump(const Duration(milliseconds: 40));
      await frame(tester);
      final growing = box(tester);
      expect(growing.width, greaterThan(smallBox.width));
      expect(angle(tester), 0);
      screen(tester, landscape, landscapeInsets);
      await settle(tester);
      expect(area(tester), full);
      expect(chromeDrawn(tester), isTrue);
      expect(host.drawn, 0);
      await leave(tester);
    });

    testWidgets('with Reduce Motion the turn jumps, and is still reported drawn', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await openTakenOver(tester);
      await turnToLandscape(tester);
      expect(angle(tester), 0);
      expect(area(tester), full);
      expect(backdrop(), findsNothing);
      await frame(tester);
      expect(host.drawn, 1);

      orientation.exitToInline();
      await tester.pump();
      screen(tester, portrait, portraitInsets);
      await tester.pump();
      host.startTurn(-pi / 2);
      await tester.pump();
      expect(angle(tester), 0);
      expect(area(tester), small);
      await frame(tester);
      expect(host.drawn, 2);
      expect(chromeDrawn(tester), isTrue);
      await leave(tester);
    });

    testWidgets('with the switch off the player grows from the change of presentation, as before', (tester) async {
      await openTakenOver(tester, takeover: false);
      orientation.enterLandscape();
      await tester.pump();
      await frame(tester);
      expect(box(tester).width, greaterThan(smallBox.width));
      expect(angle(tester), 0);
      screen(tester, landscape, landscapeInsets);
      await settle(tester);
      expect(area(tester), full);
      expect(host.drawn, 0);
      await leave(tester);
    });

    Rect video(WidgetTester tester) => tester.getRect(find.byKey(const ValueKey('fake-video')));
    bool danmakuShown(WidgetTester tester) => tester
        .widget<Visibility>(
          find.ancestor(of: find.byKey(const ValueKey('video-danmaku-area')), matching: find.byType(Visibility)).first,
        )
        .visible;
    const upright = Rect.fromLTWH(0, 0, 440, 956);

    testWidgets('竖屏 → 横屏全屏 turns the page from where 竖屏 sat, its box going from the upright screen to the '
        'landscape one about the centre, the video in its band', (tester) async {
      await openTakenOver(tester);
      orientation.enterVertical();
      await tester.pump();
      expect(area(tester), upright);
      final video0 = video(tester);
      expect(video0.height, lessThan(upright.height), reason: "a landscape video sits in 竖屏's band (09)");
      expect(danmakuShown(tester), isTrue);

      orientation.enterLandscape();
      await tester.pump();
      expect(find.byType(VerticalChrome), findsOneWidget, reason: '竖屏 stays laid out while the screen is upright');
      expect(find.byType(PortraitControls), findsNothing);
      expectRect(box(tester), upright, reason: "the box waits for the system's turn where it is");
      expectRect(video(tester), video0, reason: 'the video too');
      expect(chromeDrawn(tester), isFalse);
      expect(danmakuShown(tester), isFalse, reason: "put away from the change, so the host's picture has none either");
      expect(find.byType(PageTabRow), findsNothing, reason: '竖屏 has no body to bare');

      screen(tester, landscape, landscapeInsets);
      await tester.pump();
      host.startTurn(pi / 2);
      await tester.pump();
      expect(angle(tester), closeTo(-pi / 2, 1e-9));
      expectRect(box(tester), onTurned(upright, from: portrait, to: landscape, by: -pi / 2), reason: 'the box');
      expectRect(box(tester), full, reason: 'turned, the upright box covers the whole glass, as 竖屏 did');
      expectRect(video(tester), onTurned(video0, from: portrait, to: landscape, by: -pi / 2), reason: 'the video');
      expect(find.byType(PageTabRow), findsNothing);
      await frame(tester);
      expect(host.drawn, 1);

      var last = angle(tester).abs();
      for (var i = 0; i < 10; i++) {
        await frame(tester);
        final now = angle(tester).abs();
        expect(now, lessThan(last), reason: 'frame $i turns upright');
        expect(box(tester).center, offsetMoreOrLessEquals(landscape.center(Offset.zero)), reason: 'about the centre');
        expect(danmakuShown(tester), isFalse);
        last = now;
      }
      await tester.pump(RotationTheme.grow);
      await frame(tester);
      expect(angle(tester), 0);
      expect(area(tester), full);
      expect(video(tester), full, reason: 'the band gone, the video fills full screen');
      expect(find.byType(LandscapeChrome), findsOneWidget);
      expect(chromeDrawn(tester), isTrue);
      expect(danmakuShown(tester), isTrue);
      expect(host.drawn, 1);

      // And back, should 竖屏 be asked for from landscape.
      orientation.enterVertical();
      await tester.pump();
      expectRect(box(tester), full, reason: 'the landscape layout holds while the screen is wide');
      expect(find.byType(LandscapeChrome), findsOneWidget);
      screen(tester, portrait, portraitInsets);
      await tester.pump();
      host.startTurn(-pi / 2);
      await tester.pump();
      expect(angle(tester), closeTo(pi / 2, 1e-9));
      expectRect(box(tester), onTurned(full, from: landscape, to: portrait, by: pi / 2), reason: 'the box');
      expectRect(video(tester), onTurned(full, from: landscape, to: portrait, by: pi / 2), reason: 'the video');
      await tester.pump(RotationTheme.grow);
      await frame(tester);
      expect(angle(tester), 0);
      expect(area(tester), upright);
      expectRect(video(tester), video0, reason: "back in 竖屏's band");
      expect(find.byType(VerticalChrome), findsOneWidget);
      expect(danmakuShown(tester), isTrue);
      expect(host.drawn, 2);
      await leave(tester);
    });

    testWidgets('turning back, the page takes no swipe back until its turn is over', (tester) async {
      await openTakenOver(tester);
      await turnToLandscape(tester);
      await tester.pump(RotationTheme.grow);
      await frame(tester);
      bool canPop() => tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>).last).canPop;
      bool swipe() => ModalRoute.of(tester.element(find.byType(VideoPage)))!.popGestureEnabled;

      orientation.exitToInline();
      await tester.pump();
      expect(canPop(), isFalse);
      screen(tester, portrait, portraitInsets);
      await tester.pump();
      expect(canPop(), isFalse, reason: 'upright already, with the turn still to come');
      expect(swipe(), isFalse);
      host.startTurn(-pi / 2);
      await tester.pump();
      expect(canPop(), isFalse);
      await tester.pump(const Duration(milliseconds: 140));
      expect(canPop(), isFalse, reason: 'mid-turn');
      expect(swipe(), isFalse);
      await tester.pump(RotationTheme.grow);
      expect(canPop(), isTrue, reason: 'the page builds again as the turn ends');
      expect(swipe(), isTrue);
      await leave(tester);
    });

    testWidgets('a turn the page did not ask for, whose size a frame was already built at, is reported drawn at once',
        (tester) async {
      await openTakenOver(tester);
      screen(tester, landscape, landscapeInsets);
      await tester.pump();
      await frame(tester);
      host.startTurn(pi / 2);
      await tester.pump();
      await frame(tester);
      expect(host.drawn, 1, reason: 'not after a wait for a shape it has already');
      expect(angle(tester), 0);
      screen(tester, portrait, portraitInsets);
      await tester.pump();
      await leave(tester);
    });

    testWidgets('the turn being waited for is drawn whichever comes first, its start or its size', (tester) async {
      await openTakenOver(tester);
      final box0 = box(tester);
      orientation.enterLandscape();
      await tester.pump();
      host.startTurn(pi / 2);
      await tester.pump();
      await frame(tester);
      expect(angle(tester), 0, reason: 'nothing turned before the size');
      expectRect(box(tester), box0);
      expect(host.drawn, 0);

      screen(tester, landscape, landscapeInsets);
      await tester.pump();
      expect(angle(tester), closeTo(-pi / 2, 1e-9));
      expectRect(box(tester), onTurned(box0, from: portrait, to: landscape, by: -pi / 2));
      await frame(tester);
      expect(host.drawn, 1);
      await tester.pump(RotationTheme.grow);
      await frame(tester);
      expect(area(tester), full);
      await leave(tester);
    });

    testWidgets('with Reduce Motion the chrome stays through a change of presentation: there is no turn to wait for',
        (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await openTakenOver(tester);
      ui(tester).chrome.show();
      await tester.pump();
      orientation.enterLandscape();
      await tester.pump();
      expect(chromeDrawn(tester), isTrue);
      expect(area(tester), small);
      screen(tester, landscape, landscapeInsets);
      await tester.pump();
      host.startTurn(pi / 2);
      await tester.pump();
      await frame(tester);
      expect(host.drawn, 1);
      expect(chromeDrawn(tester), isTrue);
      expect(area(tester), full);
      await leave(tester);
    });

    testWidgets('a refusal after the player started growing without its turn shrinks it back at once, the chrome '
        'back once it is small', (tester) async {
      await openTakenOver(tester);
      orientation.enterLandscape();
      await tester.pump();
      await tester.pump(RotationTheme.takeoverWait);
      for (var i = 0; i < 4; i++) {
        await frame(tester);
      }
      final grown = box(tester);
      expect(grown.width, greaterThan(smallBox.width), reason: 'growing on its own');

      host.refuse(host.lastRequest);
      await tester.pump();
      expect(orientation.presentation, Presentation.inline);
      var last = grown;
      for (var i = 0; i < 3; i++) {
        await frame(tester);
        final now = box(tester);
        expect(now.width, lessThan(last.width), reason: 'frame $i shrinks: no turn to wait for');
        last = now;
      }
      await tester.pump(RotationTheme.grow);
      await frame(tester);
      expectRect(box(tester), smallBox);
      expect(chromeDrawn(tester), isTrue);
      expect(host.drawn, 0);
      await leave(tester);
    });
  });

  testWidgets("竖屏 → 横屏全屏 turned by the system stays 竖屏 until the screen is landscape, then is full screen at once",
      (tester) async {
    await openPage(tester);
    orientation.enterVertical();
    await tester.pump();
    orientation.enterLandscape();
    await tester.pump();
    await frame(tester);
    expect(find.byType(VerticalChrome), findsOneWidget);
    expect(area(tester), const Rect.fromLTWH(0, 0, 440, 956));
    expect(find.byType(PageTabRow), findsNothing, reason: 'no body bared');
    screen(tester, landscape, landscapeInsets);
    await tester.pump();
    expect(area(tester), full);
    expect(find.byType(LandscapeChrome), findsOneWidget);
    await leave(tester);
  });

  testWidgets("the system's grow puts the chrome away, stretched as it would be, and brings it back", (tester) async {
    await openPage(tester);
    expect(chromeDrawn(tester), isTrue);
    orientation.enterLandscape();
    await tester.pump();
    expect(chromeDrawn(tester), isFalse);
    expect(find.byType(PortraitControls), findsOneWidget, reason: 'kept laid out');
    screen(tester, landscape, landscapeInsets);
    await tester.pump();
    expect(chromeDrawn(tester), isFalse);
    await settle(tester);
    await frame(tester);
    expect(chromeDrawn(tester), isTrue);
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
