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
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/device/player_device.dart';
import 'package:bilifast/device/turn_style.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
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

const portrait = Size(440, 956);
const landscape = Size(956, 440);
const portraitInsets = FakeViewPadding(top: 62, bottom: 34);
const landscapeInsets = FakeViewPadding(left: 62, right: 62, bottom: 21);

/// The small player's box, with the status bar above it, and full screen's.
const smallBox = Rect.fromLTWH(0, 0, 440, 62 + 440 / BiliMetrics.videoAspect);
const fullBox = Rect.fromLTWH(0, 0, 956, 440);

/// A video page on the upright phone with its video loaded, owning the orientation, its turns taken over by a
/// [FakeOrientationHost] in [style] as the 开发者 choice leaves them on iOS.
class TurnPage {
  final host = FakeOrientationHost();
  late final orientation = OrientationController(host: host);
  final _nav = GlobalKey<NavigatorState>();
  final _player = FakePlayer();
  final _sessions = <FakePlayerSession>[];

  /// Wrapped around the app, for a test that reads the whole screen's picture.
  static const shotKey = ValueKey('turn-shot');

  Future<void> open(WidgetTester tester, {TurnStyle style = const TurnStyle()}) async {
    await orientation.setTurnStyle(style);
    screen(tester, portrait);
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
      player: _player,
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
      RepaintBoundary(
        key: shotKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: _nav,
          navigatorObservers: [pageRoutes],
          builder: (context, child) => AppScope(services: services, child: child!),
          home: const SizedBox(),
        ),
      ),
    );
    unawaited(
      _nav.currentState!.push(
        SwipeBackPageRoute<void>(
          builder: (_) => VideoPage(
            route: const VideoRoute(bvid: 'BV1GJ411x7h7', cid: 137649199, start: 0),
            createSession: _session,
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
    _sessions.single
      ..video = controller.video
      ..isVertical = false
      ..changed();
    await tester.pump();
  }

  PlayerSession _session({
    required PlaybackController controller,
    required AppServices services,
    required SessionOpen open,
    required void Function(double seconds) onSeeked,
    required VoidCallback requestLogin,
    required VoidCallback willPlay,
  }) {
    final session = FakePlayerSession(player: _player);
    _sessions.add(session);
    return session;
  }

  void screen(WidgetTester tester, Size size) {
    final insets = size.width > size.height ? landscapeInsets : portraitInsets;
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1
      ..padding = insets
      ..viewPadding = insets;
  }

  /// Back to the small player and off the page, so nothing of it is left running.
  Future<void> leave(WidgetTester tester) async {
    orientation.exitToInline();
    screen(tester, portrait);
    _nav.currentState!.pop();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// The turn to landscape full screen as iOS takes it over: the turned size, then the turn; returns its id.
  Future<int> turnToLandscape(WidgetTester tester, {Duration duration = const Duration(milliseconds: 300)}) async {
    orientation.enterLandscape();
    await tester.pump();
    screen(tester, landscape);
    await tester.pump();
    final id = host.startTurn(pi / 2, duration: duration);
    await tester.pump();
    return id;
  }

  /// And back to the small player.
  Future<int> turnBack(WidgetTester tester, {Duration duration = const Duration(milliseconds: 300)}) async {
    orientation.exitToInline();
    await tester.pump();
    screen(tester, portrait);
    await tester.pump();
    final id = host.startTurn(-pi / 2, duration: duration);
    await tester.pump();
    return id;
  }

  /// The page's drawn turn, in radians.
  static double angle(WidgetTester tester) {
    final matrix = tester.widget<Transform>(find.byKey(const ValueKey('page-turn'))).transform;
    return atan2(matrix.entry(1, 0), matrix.entry(0, 0));
  }

  /// [finder]'s corners on the surface, in order top-left, top-right, bottom-right, bottom-left of the widget.
  static List<Offset> corners(WidgetTester tester, Finder finder) {
    final box = tester.renderObject<RenderBox>(finder);
    final transform = box.getTransformTo(null);
    final size = box.size;
    return [
      Offset.zero,
      size.topRight(Offset.zero),
      size.bottomRight(Offset.zero),
      size.bottomLeft(Offset.zero),
    ].map((corner) => MatrixUtils.transformPoint(transform, corner)).toList();
  }

  static Finder get box => find.byKey(const ValueKey('page-player'));
  static Finder get area => find.byType(VideoPlayerArea);
  static Finder get tabRow => find.byType(PageTabRow);
  static Finder get tabsArea => find.byKey(const ValueKey('page-tabs-area'));
  static Finder get backdrop => find.byKey(const ValueKey('page-turn-backdrop'));
}

class _NoLogin implements LoginGate {
  @override
  Future<bool> request(BuildContext context) async => false;
}
