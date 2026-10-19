import 'dart:convert';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player/playback_clock.dart';
import 'package:bilifast/video/watch_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/fake_player.dart';

const heartbeatPath = '/x/click-interface/web/heartbeat';

void main() {
  late CannedHttp http;
  late FakePlayer player;
  late ManualClock time;
  late BiliClient client;
  late PlaybackController controller;
  var loggedIn = true;

  setUp(() async {
    loggedIn = true;
    http = Canned.http()..routes[heartbeatPath] = (200, '{"code":0,"message":"0"}');
    player = FakePlayer();
    time = ManualClock(10000);
    final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
    final logger = Logger(session: 'test');
    client = BiliClient(transport: http, cookies: CookieJar(Canned.cookies), now: () => now, logger: logger);
    controller = PlaybackController(
      client: client,
      engine: FakeEngine(),
      player: player,
      clock: time.clock,
      now: () => now,
      startTimer: FakeTimers().start,
      logger: logger,
    );
    await controller.openVideo('BV1GJ411x7h7', cid: 137649199, start: 0);
  });

  WatchReporter make() => WatchReporter(controller: controller, client: client, loggedIn: () => loggedIn);

  /// What each heartbeat reported: (cid, played_time).
  List<(String, String)> sent() => [
    for (final request in http.to(heartbeatPath))
      (
        Uri.splitQueryString(utf8.decode(request.body!))['cid']!,
        Uri.splitQueryString(utf8.decode(request.body!))['played_time']!,
      ),
  ];

  void position(double seconds) {
    time.advance(PlaybackClock.jumpSettleMs);
    player.emit(PositionChanged(seconds: seconds, hostMs: time.clock.nowMs(), rate: 1));
  }

  Future<void> settle(WatchReporter reporter) async {
    await pumpEventQueue();
    await reporter.leave();
  }

  test('reports the start, every 15 s of playing, a pause, a seek, the end and leaving', () async {
    final reporter = make();
    player.emit(const StatusChanged(PlayerStatus.playing));
    position(5);
    position(14);
    position(16);
    position(25);
    player.emit(const StatusChanged(PlayerStatus.paused));
    await pumpEventQueue();
    reporter.seeked(300);
    player.emit(const StatusChanged(PlayerStatus.playing));
    position(301);
    player.emit(const StatusChanged(PlayerStatus.ended));
    await settle(reporter);
    expect(sent().map((each) => each.$2), ['0', '16', '25', '300', '-1']);
    expect(sent().map((each) => each.$1).toSet(), {'137649199'});
  });

  test('every report reaches onProgress, logged out too, and the end as the whole length', () async {
    loggedIn = false;
    final seen = <int>[];
    final reporter = WatchReporter(
      controller: controller,
      client: client,
      loggedIn: () => loggedIn,
      onProgress: (bvid, cid, seconds) => seen.add(seconds),
    );
    player.emit(const StatusChanged(PlayerStatus.playing));
    position(20);
    player.emit(const StatusChanged(PlayerStatus.ended));
    await settle(reporter);
    expect(sent(), isEmpty);
    expect(seen, [0, 20, controller.page!.duration]);
  });

  test('leaving mid-video reports where it stopped; logged out, nothing is sent', () async {
    final reporter = make();
    player.emit(const StatusChanged(PlayerStatus.playing));
    position(42);
    position(50);
    await settle(reporter);
    expect(sent().map((each) => each.$2), ['0', '42', '50'], reason: '42 is 15 s on; leaving says 50');

    http.requests.clear();
    loggedIn = false;
    final quiet = make();
    player.emit(const StatusChanged(PlayerStatus.paused));
    player.emit(const StatusChanged(PlayerStatus.playing));
    position(80);
    await settle(quiet);
    expect(sent(), isEmpty);
  });

  test('once a newer open has the player, its events are ignored and leaving reports this video where it was',
      () async {
    final reporter = make();
    player.emit(const StatusChanged(PlayerStatus.playing));
    position(10);
    await controller.openVideo('BV1GJ411x7h7', cid: 137649200, start: 0);
    player.emit(const StatusChanged(PlayerStatus.playing));
    position(50);
    player.emit(const StatusChanged(PlayerStatus.paused));
    reporter.seeked(60);
    await settle(reporter);
    expect(sent(), [('137649199', '0'), ('137649199', '10')]);
  });

  test('nothing is reported before playback starts, and a failed heartbeat does not stop the next', () async {
    final reporter = make();
    player.emit(const StatusChanged(PlayerStatus.paused));
    reporter.seeked(10);
    expect(sent(), isEmpty);
    http.routes[heartbeatPath] = (500, '');
    player.emit(const StatusChanged(PlayerStatus.playing));
    await pumpEventQueue();
    http.routes[heartbeatPath] = (200, '{"code":0,"message":"0"}');
    position(20);
    await settle(reporter);
    expect(sent().map((each) => each.$2), ['0', '20', '20']);
  });

  group('canReport', () {
    Future<AppEnvironment> environment({required CookieLoad stored, required (int, String)? nav}) async {
      final canned = Canned.http();
      if (nav != null) canned.routes[Canned.navPath] = nav;
      final environment =
          await AppEnvironment.load(keychain: FakeKeychain(stored), http: canned, logger: Logger(session: 'test'));
      if (nav != null) await environment.refreshAccount();
      return environment;
    }

    const session = StoredCookies(Canned.cookies);

    test('logged in, or unknown with a session in the jar', () async {
      expect(WatchReporter.canReport(await environment(stored: session, nav: (200, Canned.navLoggedIn))), isTrue);
      final failed = await environment(stored: session, nav: (500, ''));
      expect(failed.account, isA<AccountUnknown>());
      expect(WatchReporter.canReport(failed), isTrue);
      expect(WatchReporter.canReport(await environment(stored: session, nav: null)), isTrue,
          reason: 'the launch check has not answered yet');
    });

    test('not without a session, nor with one Bilibili refused', () async {
      expect(WatchReporter.canReport(await environment(stored: const NoStoredCookies(), nav: null)), isFalse);
      final out = await environment(stored: const NoStoredCookies(), nav: (500, ''));
      expect(out.account, isA<LoggedOut>());
      expect(WatchReporter.canReport(out), isFalse);
      final expired = await environment(stored: session, nav: (200, Canned.navLoggedOut));
      expect(expired.account, isA<LoginExpired>());
      expect(WatchReporter.canReport(expired), isFalse);
    });

    test('never in a --fake-account run, even with a session in the jar', () async {
      final faked = await environment(stored: session, nav: null);
      expect(WatchReporter.canReport(faked), isTrue);
      faked.useFakeAccount();
      expect(faked.account, isA<LoggedIn>());
      expect(WatchReporter.canReport(faked), isFalse);
    });
  });
}
