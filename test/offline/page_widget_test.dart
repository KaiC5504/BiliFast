import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart' show ManualClock;
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/route_observer.dart';
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/device/player_device.dart';
import 'package:bilifast/device/status_bar.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/offline/fake_offline_library.dart';
import 'package:bilifast/offline/offline_route.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player_ui/panels/panel_layer.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/page_playback.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:bilifast/video/video_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/fake_player.dart';

class _NoLogin implements LoginGate {
  @override
  Future<bool> request(BuildContext context) async => false;
}

/// The offline page (158-161): a cached part playing from the phone with the other cached videos under the player,
/// on the video page's own machinery (the small window, the panels, full screen), asking Bilibili for nothing.
void main() {
  late CannedHttp http;
  late AppPlayback playback;
  late AppServices services;
  late FakeOfflineLibrary library;
  late PlayerPrefs prefs;
  late List<PlaybackController> controllers;
  late List<FakePlayer> players;
  late List<FakeEngine> engines;
  late FixedStatusBarFeed status;

  /// The paths asked before the page opened: the account check.
  late int asked;

  setUp(() {
    http = Canned.http();
    controllers = [];
    players = [];
    engines = [];
    library = FakeOfflineLibrary.demo();
    status = FixedStatusBarFeed();
    final saved = PlayerPrefs.shared;
    PlayerPrefs.shared = prefs = PlayerPrefs.memory();
    addTearDown(() => PlayerPrefs.shared = saved);
  });

  Future<void> host(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: 62, bottom: 34)
      ..viewPadding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    final logger = Logger(session: 'test');
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: http,
      logger: logger,
    );
    await environment.refreshAccount();
    final time = ManualClock(10000);
    playback = AppPlayback(() async {
      final player = FakePlayer();
      players.add(player);
      final engine = FakeEngine();
      engines.add(engine);
      final controller = PlaybackController(
        client: environment.client,
        engine: engine,
        player: player,
        clock: time.clock,
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
      device: PlayerDevice(orientation: OrientationController(), controls: NoDeviceControls(), status: status),
      loginGate: _NoLogin(),
      pageApi: FakePageApi(),
      offline: library,
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: services.navigator,
        navigatorObservers: [pageRoutes],
        builder: (context, child) => AppScope(services: services, child: child!),
        home: const SizedBox(),
      ),
    );
    asked = http.requests.length;
  }

  Future<void> frames(WidgetTester tester, [int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// The offline page for [cid], loaded and playing.
  Future<FakePlayer> open(WidgetTester tester, int cid) async {
    unawaited(openOfflinePage(services.navigator.currentContext!, library.item(cid)!));
    await frames(tester, 20);
    final player = players.last;
    player
      ..emit(const DurationChanged(383))
      ..emit(const StatusChanged(PlayerStatus.playing));
    await frames(tester, 2);
    return player;
  }

  Future<void> back(WidgetTester tester) async {
    unawaited(services.navigator.currentState!.maybePop());
    await frames(tester, 20);
  }

  const history = {'/x/player/wbi/v2', '/x/click-interface/web/heartbeat'};

  /// What the page asked of the network after it opened, the account's own 屏蔽词 and the watch history aside.
  List<String> pageCalls() => [
    for (final path in http.paths.skip(asked))
      if (path != '/x/dm/filter/user' && !history.contains(path)) path,
  ];

  /// The watch history's calls after the page opened: where the account stopped, and the reports.
  List<String> historyCalls() => [
    for (final path in http.paths.skip(asked))
      if (history.contains(path)) path,
  ];

  PlayerUi ui(WidgetTester tester) => tester.widget<PanelLayer>(find.byType(PanelLayer).last).ui;

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await frames(tester, 10);
  }

  testWidgets('the page plays the part from its saved place, lists every finished part and asks Bilibili for nothing '
      'but the watch history', (tester) async {
    await host(tester);
    final player = await open(tester, 7003);
    final controller = controllers.single;
    expect(engines.single.localPrepared.single.videoPath, 'offline/7003/v.m4s');
    expect(engines.single.prepared, isEmpty);
    expect(player.loaded?.startSeconds, 23);
    expect(controller.isLocal, isTrue);
    expect(find.text('离线缓存'), findsOneWidget);
    expect(find.text('（3个视频）'), findsOneWidget, reason: 'the downloading part is left out');
    expect(find.byKey(const ValueKey('offline-row-7003')), findsOneWidget);
    expect(find.byKey(const ValueKey('offline-row-7002')), findsOneWidget);
    expect(find.byKey(const ValueKey('offline-row-7001')), findsOneWidget);
    expect(find.byKey(const ValueKey('offline-row-7004')), findsNothing);
    expect(find.text('仅展示本App中可查看的稿件'), findsOneWidget);
    expect(find.text('大会员专享 · 75.0M'), findsOneWidget);
    expect(find.text('78.4M'), findsOneWidget);
    expect(find.byKey(const ValueKey('offline-playing-bars')), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-intro')), findsNothing, reason: 'no 简介 or 评论');
    expect(ui(tester).details, isNull);
    expect(ui(tester).session.offline, isTrue);
    expect(ui(tester).session.episodes.map((episode) => episode.cid), [7003, 7002, 7001]);

    await frames(tester, 40);
    expect(pageCalls(), isEmpty, reason: 'no view, playurl, related, 看点, comments or details');
    expect(historyCalls(), ['/x/player/wbi/v2', '/x/click-interface/web/heartbeat']);
    await back(tester);
    expect(pageCalls(), isEmpty);
    expect(historyCalls().last, '/x/click-interface/web/heartbeat', reason: 'leaving reports where it stopped');
    expect(services.recents.items, isEmpty, reason: 'no 最近打开');
  });

  testWidgets('the small player\'s row has no 竖屏', (tester) async {
    await host(tester);
    await open(tester, 7003);
    ui(tester).chrome.show();
    await frames(tester, 2);
    expect(find.byKey(const ValueKey('portrait-vertical')), findsNothing);
    expect(find.byKey(const ValueKey('portrait-fullscreen')), findsOneWidget);
    expect(find.byKey(const ValueKey('portrait-play')), findsOneWidget);
    await back(tester);
  });

  testWidgets('the position is kept in the library and the next open starts there', (tester) async {
    await host(tester);
    final player = await open(tester, 7003);
    // The first reading lands near the start, as the player's does once its start seek is in.
    player
      ..emit(const PositionChanged(seconds: 24, hostMs: 0, rate: 1))
      ..emit(const PositionChanged(seconds: 30, hostMs: 0, rate: 1));
    expect(library.item(7003)!.position, 23, reason: 'not 10 s on yet');
    player.emit(const PositionChanged(seconds: 34, hostMs: 0, rate: 1));
    expect(library.item(7003)!.position, 34);
    player.emit(const PositionChanged(seconds: 36, hostMs: 0, rate: 1));
    player.emit(const StatusChanged(PlayerStatus.paused));
    expect(library.item(7003)!.position, closeTo(36, 1));
    await back(tester);
    expect(library.item(7003)!.position, closeTo(36, 1), reason: 'the leave keeps where it stopped');

    final next = await open(tester, 7003);
    expect(next.loaded?.startSeconds, closeTo(36, 1));
    await back(tester);
  });

  testWidgets('a row\'s tap plays that part in the same page', (tester) async {
    await host(tester);
    await open(tester, 7003);
    final controller = controllers.single;
    final engine = engines.single;
    await tap(tester, find.byKey(const ValueKey('offline-row-7001')));
    expect(controller.page?.cid, 7001);
    expect(engine.localPrepared.map((request) => request.videoPath), ['offline/7003/v.m4s', 'offline/7001/v.m4s']);
    expect(engine.released, contains('local1'));
    expect(players, hasLength(1), reason: 'the same player');
    expect(find.byKey(const ValueKey('offline-playing-bars')), findsOneWidget);
    final bars = find.byKey(const ValueKey('offline-playing-bars'));
    expect(
      find.ancestor(of: bars, matching: find.byKey(const ValueKey('offline-row-7001'))),
      findsOneWidget,
      reason: 'the bars moved to the row playing',
    );
    expect(pageCalls(), isEmpty);
    await back(tester);
  });

  testWidgets('自动连播 plays the next cached part at the end; off, the page stops there', (tester) async {
    prefs.autoplay = true;
    await host(tester);
    final player = await open(tester, 7003);
    final controller = controllers.single;
    player.emit(const StatusChanged(PlayerStatus.ended));
    await frames(tester, 10);
    expect(controller.page?.cid, 7002);
    expect(ui(tester).session.next?.cid, 7001);

    prefs.autoplay = false;
    player
      ..emit(const StatusChanged(PlayerStatus.loading))
      ..emit(const StatusChanged(PlayerStatus.playing))
      ..emit(const StatusChanged(PlayerStatus.ended));
    await frames(tester, 10);
    expect(controller.page?.cid, 7002);
    expect(ui(tester).session.ended, isTrue);
    expect(pageCalls(), isEmpty);
    await back(tester);
  });

  testWidgets('⋮ opens 查看详情页 and 取消; online 查看详情页 opens the video\'s own page', (tester) async {
    await host(tester);
    await open(tester, 7003);
    await tap(tester, find.byKey(const ValueKey('offline-row-more')).at(1));
    expect(find.byKey(const ValueKey('offline-sheet')), findsOneWidget);
    expect(find.text('查看详情页'), findsOneWidget);

    await tap(tester, find.byKey(const ValueKey('offline-sheet-cancel')));
    expect(find.byKey(const ValueKey('offline-sheet')), findsNothing);

    await tap(tester, find.byKey(const ValueKey('offline-row-more')).at(1));
    await tap(tester, find.byKey(const ValueKey('offline-sheet-details')));
    await frames(tester, 20);
    final pages = find.byType(VideoPage);
    expect(pages, findsOneWidget, reason: 'the offline page is covered');
    final route = tester.widget<VideoPage>(pages).route;
    expect((route.bvid, route.cid, route.offline), ('BV1fake00002', 7002, false));
    expect(players.first.calls, contains('pause'), reason: 'the covered offline page pauses');
    await back(tester);
    await back(tester);
  });

  testWidgets('offline, 查看详情页 says the network is gone and opens nothing', (tester) async {
    status.status.value = const DeviceStatus(battery: 1, charging: false, network: StatusNetwork.none);
    await host(tester);
    await open(tester, 7003);
    await tap(tester, find.byKey(const ValueKey('offline-row-more')).first);
    await tester.tap(find.byKey(const ValueKey('offline-sheet-details')));
    await tester.pump();
    expect(find.text('似乎已断开与互联网的连接'), findsOneWidget);
    await frames(tester, 20);
    expect(find.byType(VideoPage), findsOneWidget);
    expect(tester.widget<VideoPage>(find.byType(VideoPage)).route.offline, isTrue);
    expect(find.byKey(const ValueKey('offline-sheet')), findsNothing);
    expect(pageCalls(), isEmpty);
    await frames(tester, 80);
    await back(tester);
  });

  testWidgets('back closes the sheet before the page', (tester) async {
    await host(tester);
    await open(tester, 7003);
    await tap(tester, find.byKey(const ValueKey('offline-row-more')).first);
    await back(tester);
    expect(find.byType(VideoPage), findsOneWidget);
    expect(find.byKey(const ValueKey('offline-sheet')), findsNothing);
    await back(tester);
    expect(find.byType(VideoPage), findsNothing);
  });

  testWidgets('leaving releases the local source and the player', (tester) async {
    await host(tester);
    await open(tester, 7003);
    expect(playback.live, 1);
    await back(tester);
    expect(engines.single.released, ['local1']);
    expect(players.single.disposed, isTrue);
    expect(playback.live, 0);
  });

  testWidgets('popped in the small window it plays on; the restore brings the offline page back as it was', (
    tester,
  ) async {
    await host(tester);
    final player = await open(tester, 7003);
    final controller = controllers.single;
    player.emit(const PictureInPictureChanged(true));
    await back(tester);
    expect(find.byType(VideoPage), findsNothing);
    expect(services.pipKeeper.kept, isNotNull);
    expect(player.disposed, isFalse);

    player
      ..emit(const PictureInPictureRestore())
      ..emit(const PictureInPictureChanged(false));
    await frames(tester, 4);
    final restored = find.byType(VideoPage);
    expect(restored, findsOneWidget);
    expect(ModalRoute.of(tester.element(restored)), isA<RestoredPageRoute<void>>());
    final route = tester.widget<VideoPage>(restored).route;
    expect(route.offline, isTrue);
    expect(route.playback?.controller, same(controller));
    expect(find.text('离线缓存'), findsOneWidget);
    expect(engines.single.localPrepared, hasLength(1), reason: 'no reload');
    expect(pageCalls(), isEmpty);
    await back(tester);
    expect(playback.live, 0);
  });
}
