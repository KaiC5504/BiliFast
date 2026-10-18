import 'dart:convert';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player/playback_clock.dart';
import 'package:bilifast/video/watch_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
