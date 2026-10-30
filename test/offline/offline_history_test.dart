import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_core/api.dart' show BiliNetworkError, PlayerInfo;
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
import 'package:bilifast/device/status_bar.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/offline/fake_offline_library.dart';
import 'package:bilifast/offline/offline_route.dart';
import 'package:bilifast/offline/page/offline_playback.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/history_outbox.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:bilifast/video/video_page.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/fake_player.dart';

const playerInfoPath = '/x/player/wbi/v2';
const heartbeatPath = '/x/click-interface/web/heartbeat';
const ok = '{"code":0,"message":"0"}';

class _NoLogin implements LoginGate {
  @override
  Future<bool> request(BuildContext context) async => false;
}

String _playerInfo({required int cid, required int ms}) =>
    '{"code":0,"message":"0","data":{"last_play_cid":$cid,"last_play_time":$ms,"view_points":[]}}';

/// A cached part's watch history: the offline page reports it as a video page does, and starts where the account
/// last stopped in it when Bilibili says so within a second, unless this phone's own report is still waiting.
void main() {
  group('offlineResume', () {
    late FakeOfflineLibrary library;
    late MemorySink logs;
    late Logger logger;

    setUp(() {
      library = FakeOfflineLibrary.demo();
      logs = MemorySink();
      logger = Logger(session: 'test')..add(logs);
    });

    Map<String, Object> line() {
      final event = logs.events.singleWhere((event) => event.msg == 'offline resume');
      return {for (final MapEntry(:key, :value) in event.f.entries) key: value.toJson()};
    }

    Future<double> resume(Future<PlayerInfo> Function() ask, {bool unsent = false, int cid = 7003}) =>
        offlineResume(library.item(cid)!, ask: ask, unsent: unsent, logger: logger);

    test('Bilibili\'s place in this part wins over the phone\'s', () async {
      expect(
        await resume(() async => const PlayerInfo(lastPlayCid: 7003, lastPlayTimeMs: 120400, chapters: [])),
        120.4,
      );
      expect(line(), {'cid': 7003, 'local': 23, 'server': 120, 'used': 120, 'source': 'server'});
    });

    test('within 5 s of the end it starts over, as the online page does', () async {
      expect(await resume(() async => const PlayerInfo(lastPlayCid: 7003, lastPlayTimeMs: 380000, chapters: [])), 0);
      expect(line(), {'cid': 7003, 'local': 23, 'server': 380, 'used': 0, 'source': 'server'});
    });

    test('a place in another part, or none, leaves the phone\'s', () async {
      expect(await resume(() async => const PlayerInfo(lastPlayCid: 7002, lastPlayTimeMs: 90000, chapters: [])), 23);
      expect(line(), {'cid': 7003, 'local': 23, 'server': 90, 'used': 23, 'source': 'other part'});
      logs = MemorySink();
      logger = Logger(session: 'test')..add(logs);
      expect(await resume(() async => const PlayerInfo(lastPlayCid: 7003, lastPlayTimeMs: 0, chapters: [])), 23);
      expect(line()['source'], 'unwatched');
    });

    test('a report of the part still waiting on the phone is newer: Bilibili isn\'t asked', () async {
      var asked = 0;
      expect(
        await resume(() async {
          asked++;
          return const PlayerInfo(lastPlayCid: 7003, lastPlayTimeMs: 120000, chapters: []);
        }, unsent: true),
        23,
      );
      expect(asked, 0);
      expect(line(), {'cid': 7003, 'local': 23, 'used': 23, 'source': 'unsent'});
    });

    test('no answer within the wait, or a failure, falls back to the phone\'s', () async {
      final never = Completer<PlayerInfo>();
      final watch = Stopwatch()..start();
      expect(
        await offlineResume(
          library.item(7003)!,
          ask: () => never.future,
          unsent: false,
          wait: const Duration(milliseconds: 30),
          logger: logger,
        ),
        23,
      );
      expect(line()['source'], 'timeout');
      never.complete(const PlayerInfo(lastPlayCid: 7003, lastPlayTimeMs: 120000, chapters: []));

      logs = MemorySink();
      logger = Logger(session: 'test')..add(logs);
      expect(await resume(() async => throw const BiliNetworkError('SocketException')), 23);
      expect(line(), {'cid': 7003, 'local': 23, 'used': 23, 'source': 'failed'});
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)), reason: 'a fast failure falls back at once');
    });
  });

  group('the offline page', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    late CannedHttp http;
    late AppServices services;
    late FakeOfflineLibrary library;
    late HistoryOutbox outbox;
    late List<FakePlayer> players;
    late int asked;

    setUp(() {
      http = Canned.http()
        ..routes[heartbeatPath] = (200, ok)
        ..routes[playerInfoPath] = (200, _playerInfo(cid: 7003, ms: 120000));
      players = [];
      library = FakeOfflineLibrary.demo();
      outbox = HistoryOutbox.memory(logger: Logger(session: 'test'));
      final saved = PlayerPrefs.shared;
      PlayerPrefs.shared = PlayerPrefs.memory();
      addTearDown(() => PlayerPrefs.shared = saved);
    });

    Future<void> host(WidgetTester tester, {CookieLoad stored = const StoredCookies(Canned.cookies)}) async {
      tester.view
        ..physicalSize = const Size(440, 956)
        ..devicePixelRatio = 1
        ..padding = const FakeViewPadding(top: 62, bottom: 34)
        ..viewPadding = const FakeViewPadding(top: 62, bottom: 34);
      addTearDown(tester.view.reset);
      final logger = Logger(session: 'test');
      final environment = await AppEnvironment.load(keychain: FakeKeychain(stored), http: http, logger: logger);
      await environment.refreshAccount();
      final time = ManualClock(10000);
      final playback = AppPlayback(() async {
        final player = FakePlayer();
        players.add(player);
        return PlaybackController(
          client: environment.client,
          engine: FakeEngine(),
          player: player,
          clock: time.clock,
          startTimer: FakeTimers().start,
          logger: logger,
        );
      });
      addTearDown(playback.dispose);
      services = AppServices(
        environment: environment,
        playback: playback,
        recents: await RecentStore.load(null, logger: logger),
        device: PlayerDevice(
          orientation: OrientationController(),
          controls: NoDeviceControls(),
          status: FixedStatusBarFeed(),
        ),
        loginGate: _NoLogin(),
        pageApi: FakePageApi(),
        offline: library,
        historyOutbox: outbox,
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

    void push(VideoRoute route) => unawaited(
      services.navigator.currentState!.push(
        SwipeBackPageRoute<void>(
          builder: (_) => VideoPage(route: route, createSession: offlinePageSession),
        ),
      ),
    );

    Future<FakePlayer> play(WidgetTester tester) async {
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

    List<String> calls() => [
      for (final path in http.paths.skip(asked))
        if (path != '/x/dm/filter/user') path,
    ];

    List<(String, String, String)> beats() => [
      for (final request in http.to(heartbeatPath))
        (
          Uri.splitQueryString(utf8.decode(request.body!))['bvid']!,
          Uri.splitQueryString(utf8.decode(request.body!))['cid']!,
          Uri.splitQueryString(utf8.decode(request.body!))['played_time']!,
        ),
    ];

    testWidgets('it reports what it plays, and starts where the account last stopped in the part', (tester) async {
      await host(tester);
      push(offlineRoute(library.item(7003)!));
      final player = await play(tester);
      expect(player.loaded?.startSeconds, 120);
      expect(http.to(playerInfoPath).single.url.queryParameters, containsPair('cid', '7003'));
      expect(beats(), [('BV1fake00003', '7003', '120')], reason: 'the start goes out once playing');
      await back(tester);
      expect(beats(), hasLength(2), reason: 'leaving reports where it stopped');
      expect(calls().toSet(), {playerInfoPath, heartbeatPath}, reason: 'nothing else is asked');
    });

    testWidgets('a place Bilibili keeps for another part is ignored', (tester) async {
      http.routes[playerInfoPath] = (200, _playerInfo(cid: 7002, ms: 120000));
      await host(tester);
      push(offlineRoute(library.item(7003)!));
      final player = await play(tester);
      expect(player.loaded?.startSeconds, 23);
      await back(tester);
    });

    testWidgets('a report of the part still waiting on the phone keeps the phone\'s place', (tester) async {
      http.errors[heartbeatPath] = const SocketException('offline');
      try {
        await outbox.send('BV1fake00003', 7003, 30, () async => throw const BiliNetworkError('SocketException'));
      } on BiliNetworkError {
        // It waits.
      }
      await host(tester);
      push(offlineRoute(library.item(7003)!));
      final player = await play(tester);
      expect(player.loaded?.startSeconds, 23);
      expect(http.to(playerInfoPath), isEmpty);
      await back(tester);
    });

    testWidgets('no answer within a second starts from the phone\'s place', (tester) async {
      final gate = http.gates[playerInfoPath] = Completer<void>();
      await host(tester);
      push(offlineRoute(library.item(7003)!));
      await frames(tester, 12);
      expect(http.to(playerInfoPath), hasLength(1));
      expect(players.single.loaded, isNull, reason: 'it waits for the answer, up to a second');
      await frames(tester, 12);
      final player = players.single;
      expect(player.loaded?.startSeconds, 23);
      gate.complete();
      await frames(tester, 2);
      expect(player.loaded?.startSeconds, 23, reason: 'a late answer changes nothing');
      await back(tester);
    });

    testWidgets('a start the route asks for wins, and Bilibili isn\'t asked', (tester) async {
      await host(tester);
      push(const VideoRoute(bvid: 'BV1fake00003', cid: 7003, start: 50, offline: true));
      final player = await play(tester);
      expect(player.loaded?.startSeconds, 50);
      expect(http.to(playerInfoPath), isEmpty);
      await back(tester);
    });

    testWidgets('with no network its reports wait in the outbox', (tester) async {
      http.errors[heartbeatPath] = const SocketException('offline');
      http.errors[playerInfoPath] = const SocketException('offline');
      await host(tester);
      push(offlineRoute(library.item(7003)!));
      final player = await play(tester);
      expect(player.loaded?.startSeconds, 23);
      expect(outbox.holds('BV1fake00003', 7003), isTrue);
      await back(tester);
      expect(outbox.reports.single.cid, 7003);
    });

    testWidgets('logged out it sends nothing at all', (tester) async {
      await host(tester, stored: const NoStoredCookies());
      expect(services.environment.account, isA<LoggedOut>());
      push(offlineRoute(library.item(7003)!));
      final player = await play(tester);
      expect(player.loaded?.startSeconds, 23);
      await back(tester);
      expect(calls(), isEmpty);
      expect(outbox.reports, isEmpty);
    });
  });
}
