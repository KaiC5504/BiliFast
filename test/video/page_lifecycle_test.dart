import 'dart:async';

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
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player_ui/panels/panel_layer.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/page_details.dart';
import 'package:bilifast/video/page_playback.dart';
import 'package:bilifast/video/page_session.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:bilifast/video/player_session.dart';
import 'package:bilifast/video/video_page.dart';
import 'package:bilifast/video/video_player_area.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/fake_player.dart';
import '../support/fake_video_actions.dart';

const heartbeatPath = '/x/click-interface/web/heartbeat';
const bv = 'BV1GJ411x7h7';
const other = 'BV1xx411c7mD';
const p1 = 137649199;
const p2 = 137649200;
const portrait = Size(440, 956);
const landscape = Size(956, 440);
const portraitInsets = FakeViewPadding(top: 62, bottom: 34);
const landscapeInsets = FakeViewPadding(left: 62, right: 62, bottom: 21);

/// The other video, with parts of its own, as the signed view answers for it.
final otherView = Canned.view
    .replaceAll(bv, other)
    .replaceAll('80433022', '80433023')
    .replaceAll('$p1', '237649199')
    .replaceAll('$p2', '237649200');

class _NoLogin implements LoginGate {
  @override
  Future<bool> request(BuildContext context) async => false;
}

/// Some listener is still on [notifier].
// ignore: invalid_use_of_protected_member
bool listened(ChangeNotifier notifier) => notifier.hasListeners;

/// Stacked video pages and the small window (BiliNative's PageLifecycle and PiPKeeper, phone checklist items 33-42
/// and 67): each page plays on a controller of its own with the app's own session; a covered page pauses and comes
/// back without a reload; a page popped while the small window plays it is kept until ✕, its restore button or
/// another video.
void main() {
  late CannedHttp http;
  late AppEnvironment environment;
  late AppPlayback playback;
  late AppServices services;
  late OrientationController orientation;
  late PlayerPrefs prefs;

  /// Each page's controller and player, in the order the pages started them.
  late List<PlaybackController> controllers;
  late List<FakePlayer> players;
  late List<PlayerSession> sessions;
  late List<FakePageDetails> detailsMade;

  /// Runs as each controller is made, before it is handed out.
  VoidCallback? onCreate;

  setUp(() {
    http = Canned.http()..routes[heartbeatPath] = (200, '{"code":0,"message":"0"}');
    orientation = OrientationController();
    controllers = [];
    players = [];
    sessions = [];
    detailsMade = [];
    onCreate = null;
    final saved = PlayerPrefs.shared;
    PlayerPrefs.shared = prefs = PlayerPrefs.memory();
    addTearDown(() => PlayerPrefs.shared = saved);
  });

  void screen(WidgetTester tester, Size size, FakeViewPadding insets) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = insets;
    tester.view.viewPadding = insets;
  }

  PlayerSession session({
    required PlaybackController controller,
    required AppServices services,
    required SessionOpen open,
    required void Function(double seconds) onSeeked,
    required VoidCallback requestLogin,
    required VoidCallback willPlay,
  }) {
    final made = pageSession(
      controller: controller,
      services: services,
      open: open,
      onSeeked: onSeeked,
      requestLogin: requestLogin,
      willPlay: willPlay,
    );
    sessions.add(made);
    return made;
  }

  PageDetails fakeDetails({
    required PlayerSession session,
    required AppServices services,
    required void Function(String message) toast,
    required VoidCallback requestLogin,
    required Listenable logins,
  }) {
    final details = FakePageDetails();
    detailsMade.add(details);
    return details;
  }

  /// With [realDetails] the page has the app's own details over a FakePageApi, as the app makes them.
  var realDetails = false;

  late VideoPageOpener openPage;
  Widget page(VideoRoute route) => VideoPage(
    route: route,
    createSession: session,
    createDetails: realDetails ? pageDetails : fakeDetails,
    openPage: openPage,
  );
  openPage = (context, route) => Navigator.of(context).push(SwipeBackPageRoute<void>(builder: (_) => page(route)));

  Future<void> host(WidgetTester tester, {bool real = false}) async {
    realDetails = real;
    screen(tester, portrait, portraitInsets);
    addTearDown(tester.view.reset);
    final logger = Logger(session: 'test');
    environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: http,
      logger: logger,
    );
    await environment.refreshAccount();
    final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
    final time = ManualClock(10000);
    playback = AppPlayback(() async {
      onCreate?.call();
      final player = FakePlayer();
      players.add(player);
      final controller = PlaybackController(
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
    });
    addTearDown(playback.dispose);
    services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      device: PlayerDevice(orientation: orientation, controls: NoDeviceControls()),
      loginGate: _NoLogin(),
      pageApi: FakePageApi(),
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: services.navigator,
        navigatorObservers: [pageRoutes],
        builder: (context, child) => AppScope(services: services, child: child!),
        home: const SizedBox(),
      ),
    );
  }

  Future<void> frames(WidgetTester tester, [int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  void push(VideoRoute route) =>
      unawaited(services.navigator.currentState!.push(SwipeBackPageRoute<void>(builder: (_) => page(route))));

  /// A page pushed, its video loaded and playing.
  Future<FakePlayer> open(WidgetTester tester, VideoRoute route) async {
    push(route);
    await frames(tester, 20);
    final player = players.last;
    player
      ..emit(const DurationChanged(712))
      ..emit(const StatusChanged(PlayerStatus.playing));
    await frames(tester, 2);
    return player;
  }

  Future<void> back(WidgetTester tester) async {
    unawaited(services.navigator.currentState!.maybePop());
    await frames(tester, 20);
  }

  PlayerUi ui(WidgetTester tester) => tester.widget<PanelLayer>(find.byType(PanelLayer).last).ui;

  void lifecycle(WidgetTester tester, List<AppLifecycleState> states) {
    for (final state in states) {
      // ignore: invalid_use_of_protected_member
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  void toBackground(WidgetTester tester) =>
      lifecycle(tester, [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]);

  void toForeground(WidgetTester tester) =>
      lifecycle(tester, [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]);

  List<String> loads(FakePlayer player) => [
    for (final call in player.calls)
      if (call.startsWith('load')) call,
  ];

  /// The ⋮ → 小窗播放 small window on [player], and the page popped under it.
  Future<void> popIntoPip(WidgetTester tester, FakePlayer player) async {
    player.emit(const PictureInPictureChanged(true));
    await back(tester);
  }

  testWidgets('items 33 and 35: popped in the small window the video plays on with no page; ✕ stops it, and the next '
      'video plays normally', (tester) async {
    await host(tester);
    final first = await open(tester, const VideoRoute(bvid: bv, cid: p1, start: 0));
    first.calls.clear();
    await popIntoPip(tester, first);
    expect(find.byType(VideoPage), findsNothing);
    expect(services.pipKeeper.kept, isNotNull);
    expect(first.calls, ['restorable true'], reason: 'no pause and no unload: the small window plays on');
    expect(first.disposed, isFalse);
    expect(playback.live, 1);
    expect(controllers.single.video?.bvid, bv);
    expect(sessions.single.ended, isFalse);

    first.emit(const PictureInPictureChanged(false));
    await tester.pump();
    expect(services.pipKeeper.kept, isNull);
    expect(first.calls.first, 'restorable true');
    expect(first.calls, containsAllInOrder(['restorable false', 'unload']));
    expect(first.disposed, isTrue);
    expect(playback.live, 0);

    final next = await open(tester, const VideoRoute(bvid: other, start: 0));
    expect(next.loaded?.autoplay, isTrue);
    expect(next.calls.skipWhile((call) => !call.startsWith('load')), isNot(contains('pause')));
    await back(tester);
    expect(playback.live, 0);
  });

  testWidgets('item 34: the restore button brings the same page back in place, its video in the player, with no '
      'reload', (tester) async {
    await host(tester);
    final first = await open(tester, const VideoRoute(bvid: bv, cid: p1, start: 0));
    final controller = controllers.single;
    final opens = controller.opens;
    final kept = sessions.single;
    await popIntoPip(tester, first);
    first.calls.clear();

    // AVKit's order: the restore request, then the window closing.
    first
      ..emit(const PictureInPictureRestore())
      ..emit(const PictureInPictureChanged(false));
    await tester.pump();
    final restored = find.byType(VideoPage);
    expect(restored, findsOneWidget);
    expect(ModalRoute.of(tester.element(restored)), isA<RestoredPageRoute<void>>());
    expect(tester.getRect(restored).left, 0, reason: 'in place at once, so the window lands on the player');
    expect(tester.widget<VideoPage>(restored).route.playback?.controller, same(controller));
    await tester.pump();
    expect(find.byKey(const ValueKey('fake-video')), findsOneWidget, reason: 'the video is back in the player');
    expect(ui(tester).session, same(kept));
    expect(services.pipKeeper.kept, isNull);
    expect(first.calls, ['restorable false']);

    await tester.pump(const Duration(seconds: 2));
    expect(controller.opens, opens);
    expect(loads(first), isEmpty);
    expect(first.disposed, isFalse);
    expect(sessions, hasLength(1), reason: 'the same session, the same position');
    expect(playback.live, 1);

    await back(tester);
    expect(first.disposed, isTrue);
    expect(playback.live, 0);
  });

  testWidgets('a restore that loses to the release starts the page over where the video stopped', (tester) async {
    await host(tester);
    final first = await open(tester, const VideoRoute(bvid: bv, cid: p2, start: 0));
    final playback0 = tester.widget<VideoPage>(find.byType(VideoPage)).route;
    expect(playback0.playback, isNull);
    await popIntoPip(tester, first);
    final kept = services.pipKeeper.kept! as PagePlayback;
    services.pipKeeper.release();
    await tester.pump();
    expect(first.disposed, isTrue);
    services.navigator.currentState!.push(RestoredPageRoute<void>(builder: (_) => page(
      VideoRoute(bvid: kept.bvid, playback: kept),
    )));
    await frames(tester, 20);
    expect(players, hasLength(2));
    expect(controllers.last.page?.cid, p2);
    expect(loads(players.last), hasLength(1));
    await back(tester);
  });

  testWidgets('item 36: another video closes the small window before it starts', (tester) async {
    await host(tester);
    final first = await open(tester, const VideoRoute(bvid: bv, cid: p1, start: 0));
    await popIntoPip(tester, first);
    first.calls.clear();
    List<String>? keptAtCreate;
    onCreate = () => keptAtCreate ??= [...first.calls];
    push(const VideoRoute(bvid: other, start: 0));
    await tester.pump();
    expect(keptAtCreate, ['restorable false', 'pip stop'],
        reason: 'the small window closed before the new page asked for its player');
    expect(services.pipKeeper.kept, isNull);
    expect(first.calls, contains('unload'));
    expect(first.disposed, isTrue);
    await frames(tester, 20);
    expect(players.last.loaded, isNotNull);
    await back(tester);
  });

  testWidgets('item 37: in the background the small window plays the next part, with no page', (tester) async {
    prefs.autoplay = true;
    await host(tester);
    final first = await open(tester, const VideoRoute(bvid: bv, cid: p1, start: 0));
    await popIntoPip(tester, first);
    toBackground(tester);
    first.calls.clear();
    first.emit(const StatusChanged(PlayerStatus.ended));
    await frames(tester, 20);
    expect(controllers.single.page?.cid, p2, reason: '自动连播 opened P2 on the same player');
    expect(loads(first), hasLength(1));
    first.calls.clear();
    first.emit(const StatusChanged(PlayerStatus.playing));
    await tester.pump(PagePlayerSession.backgroundGrace * 2);
    expect(first.calls, isNot(contains('pause')), reason: 'the small window keeps the sound');
    expect(services.pipKeeper.kept, isNotNull);

    first.emit(const PictureInPictureChanged(false));
    await tester.pump();
    expect(first.disposed, isTrue);
    toForeground(tester);
  });

  testWidgets('items 38 and 39: back from a related page in the small window leaves the first paused; its play closes '
      'the window', (tester) async {
    await host(tester);
    final first = await open(tester, const VideoRoute(bvid: bv, cid: p1, start: 0));
    http.routes[Canned.signedViewPath] = (200, otherView);
    final second = await open(tester, const VideoRoute(bvid: other, start: 0));
    expect(first.calls, containsAllInOrder(['pause', 'pip auto false']));
    // The player reports the pause the cover asked for.
    first.emit(const StatusChanged(PlayerStatus.paused));
    first.calls.clear();

    await popIntoPip(tester, second);
    expect(services.pipKeeper.kept, isNotNull);
    expect(second.disposed, isFalse);
    expect(first.calls, ['pip auto true'], reason: 'it stays paused beside the small window');

    first.calls.clear();
    ui(tester).session.togglePlay();
    await tester.pump();
    expect(services.pipKeeper.kept, isNull, reason: 'one video at a time');
    expect(second.disposed, isTrue);
    expect(first.calls, ['play']);
    expect(playback.live, 1);
    await back(tester);
  });

  testWidgets('item 41: a restore while the first page shows puts the second on top; back finds the first still '
      'paused', (tester) async {
    await host(tester);
    final first = await open(tester, const VideoRoute(bvid: bv, cid: p1, start: 0));
    http.routes[Canned.signedViewPath] = (200, otherView);
    final second = await open(tester, const VideoRoute(bvid: other, start: 0));
    first.emit(const StatusChanged(PlayerStatus.paused));
    await popIntoPip(tester, second);
    first.calls.clear();
    second.calls.clear();

    second
      ..emit(const PictureInPictureRestore())
      ..emit(const PictureInPictureChanged(false));
    await frames(tester, 2);
    expect(find.byType(VideoPage), findsNWidgets(1), reason: 'the first is covered, offstage');
    expect(find.byType(VideoPage, skipOffstage: false), findsNWidgets(2));
    expect(tester.widget<VideoPage>(find.byType(VideoPage)).route.bvid, other);
    expect(loads(second), isEmpty);
    expect(first.calls, ['pause', 'pip auto false']);
    first.calls.clear();

    await back(tester);
    expect(second.disposed, isTrue);
    expect(first.calls, ['pip auto true'], reason: 'still paused');
    await back(tester);
    expect(playback.live, 0);
  });

  testWidgets('item 42: the shown page\'s rotation rules apply: a vertical video, a landscape one above it, then back',
      (tester) async {
    await host(tester);
    final first = await open(tester, const VideoRoute(bvid: bv, cid: p1, start: 0));
    first.emit(const SizeChanged(width: 1080, height: 1920));
    await frames(tester, 2);
    expect(orientation.videoIsVertical, isTrue);
    http.routes[Canned.signedViewPath] = (200, otherView);
    final second = await open(tester, const VideoRoute(bvid: other, start: 0));
    second.emit(const SizeChanged(width: 1920, height: 1080));
    await frames(tester, 2);
    expect(orientation.videoIsVertical, isFalse);
    await back(tester);
    expect(orientation.videoIsVertical, isTrue);
    await back(tester);
  });

  group('the back swipe at a thumb\'s speed (about 1500 px/s)', () {
    /// From the left edge, 24 px every 16 ms, then held still for [hold] before letting go. Answers how far the top page
    /// had moved when let go.
    Future<double> swipe(WidgetTester tester, double distance, {Duration hold = Duration.zero}) async {
      final gesture = await tester.startGesture(const Offset(5, 700));
      var x = 5.0;
      var at = Duration.zero;
      while (x < 5 + distance) {
        x += 24;
        at += const Duration(milliseconds: 16);
        await gesture.moveTo(Offset(x, 700), timeStamp: at);
        await tester.pump(const Duration(milliseconds: 16));
      }
      if (hold > Duration.zero) {
        at += hold;
        await gesture.moveTo(Offset(x, 700), timeStamp: at);
        await tester.pump(hold);
      }
      final moved = tester.getRect(find.byType(VideoPage).last).left;
      await gesture.up(timeStamp: at);
      await frames(tester, 20);
      return moved;
    }

    testWidgets('item 40: a cancelled half swipe leaves the top page playing and turning; a full one resumes the '
        'first and stops the second', (tester) async {
      await host(tester);
      final first = await open(tester, const VideoRoute(bvid: bv, cid: p1, start: 0));
      http.routes[Canned.signedViewPath] = (200, otherView);
      final second = await open(tester, const VideoRoute(bvid: other, start: 0));
      first.calls.clear();
      second.calls.clear();

      expect(await swipe(tester, 150, hold: const Duration(milliseconds: 300)), greaterThan(100));
      expect(find.byType(VideoPage), findsOneWidget);
      expect(tester.widget<VideoPage>(find.byType(VideoPage)).route.bvid, other);
      expect(second.calls, isEmpty, reason: 'it plays on');
      expect(first.calls, isEmpty, reason: 'the page below stays paused');

      screen(tester, landscape, landscapeInsets);
      orientation.enterLandscape();
      await frames(tester, 20);
      expect(tester.widget<VideoPlayerArea>(find.byType(VideoPlayerArea)).presentation, Presentation.landscape);
      orientation.exitToInline();
      screen(tester, portrait, portraitInsets);
      await frames(tester, 20);

      await swipe(tester, 300);
      expect(tester.widget<VideoPage>(find.byType(VideoPage)).route.bvid, bv);
      expect(second.disposed, isTrue);
      expect(first.calls, ['pip auto true', 'play']);
      await back(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  });

  testWidgets('item 67: ten pages opened and closed, stacked and kept, leave nothing behind', (tester) async {
    await host(tester, real: true);
    final made = <PlaybackController>[];
    for (var i = 0; i < 4; i++) {
      await open(tester, VideoRoute(bvid: bv, cid: i.isEven ? p1 : p2, start: 0));
      await back(tester);
    }
    http.routes[Canned.signedViewPath] = (200, otherView);
    for (var i = 0; i < 3; i++) {
      await open(tester, VideoRoute(bvid: i.isEven ? bv : other, start: 0));
    }
    expect(playback.live, 3);
    for (var i = 0; i < 3; i++) {
      await back(tester);
    }
    final kept = await open(tester, const VideoRoute(bvid: other, start: 0));
    await popIntoPip(tester, kept);
    kept.emit(const PictureInPictureChanged(false));
    await tester.pump();
    final restored = await open(tester, const VideoRoute(bvid: other, start: 0));
    await popIntoPip(tester, restored);
    restored
      ..emit(const PictureInPictureRestore())
      ..emit(const PictureInPictureChanged(false));
    await frames(tester, 20);
    await back(tester);
    await tester.pump(const Duration(seconds: 2));
    made.addAll(controllers);

    expect(made, hasLength(9));
    expect(find.byType(VideoPage), findsNothing);
    expect(playback.live, 0);
    expect(services.pipKeeper.kept, isNull);
    for (final player in players) {
      expect(player.disposed, isTrue);
    }
    for (final controller in made) {
      expect(() => ChangeNotifier.debugAssertNotDisposed(controller), throwsFlutterError);
    }
    for (final session in sessions) {
      expect(() => ChangeNotifier.debugAssertNotDisposed(session as ChangeNotifier), throwsFlutterError);
    }

    services.dispose();
    expect(listened(environment), isFalse);
    expect(listened(environment.logins as ChangeNotifier), isFalse);
    expect(listened(orientation), isFalse);
    expect(listened(services.blockRules), isFalse);
    expect(listened(services.danmakuSettings), isFalse);
    expect(listened(services.recents), isFalse);
    expect(listened(services.fonts), isFalse);
  });
}
