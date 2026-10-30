import 'dart:convert';
import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player/playback_clock.dart';
import 'package:bilifast/video/history_outbox.dart';
import 'package:bilifast/video/watch_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';
import '../support/fake_player.dart';

const heartbeatPath = '/x/click-interface/web/heartbeat';
const ok = '{"code":0,"message":"0"}';
const bv = 'BV1GJ411x7h7';
const cid = 137649199;

/// A video page's reports go through the outbox: with no network the latest waits there, one that goes through
/// clears it.
void main() {
  late CannedHttp http;
  late FakePlayer player;
  late ManualClock time;
  late BiliClient client;
  late PlaybackController controller;
  late HistoryOutbox outbox;
  var loggedIn = true;

  setUp(() async {
    loggedIn = true;
    http = Canned.http()..routes[heartbeatPath] = (200, ok);
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
    outbox = HistoryOutbox.memory(logger: logger);
    await controller.openVideo(bv, cid: cid, start: 0);
  });

  WatchReporter make({BiliClient? over}) =>
      WatchReporter(controller: controller, client: over ?? client, loggedIn: () => loggedIn, outbox: outbox);

  void position(double seconds) {
    time.advance(PlaybackClock.jumpSettleMs);
    player.emit(PositionChanged(seconds: seconds, hostMs: time.clock.nowMs(), rate: 1));
  }

  List<String> sent() => [
    for (final request in http.to(heartbeatPath)) Uri.splitQueryString(utf8.decode(request.body!))['played_time']!,
  ];

  List<(String, int, int)> waiting() => [for (final each in outbox.reports) (each.bvid, each.cid, each.played)];

  test('with no network the latest report waits; the next one that goes through clears it', () async {
    final reporter = make();
    http.errors[heartbeatPath] = const SocketException('offline');
    player.emit(const StatusChanged(PlayerStatus.playing));
    position(16);
    await pumpEventQueue();
    expect(waiting(), [(bv, cid, 16)]);
    player.emit(const StatusChanged(PlayerStatus.ended));
    await pumpEventQueue();
    expect(waiting(), [(bv, cid, -1)], reason: 'finished replaces it');

    http.errors.remove(heartbeatPath);
    reporter.seeked(30);
    await pumpEventQueue();
    expect(sent(), ['0', '16', '-1', '30']);
    expect(waiting(), isEmpty);
    await reporter.leave();
  });

  test('an answer is not the network: a refused report never waits', () async {
    final reporter = make();
    http.routes[heartbeatPath] = (200, '{"code":-400,"message":"请求错误"}');
    player.emit(const StatusChanged(PlayerStatus.playing));
    position(16);
    await pumpEventQueue();
    await reporter.leave();
    expect(sent(), ['0', '16', '16']);
    expect(waiting(), isEmpty);
  });

  test('the Windows guard\'s refusal never waits', () async {
    final guarded = BiliClient(
      transport: GuardedTransport(http, logger: Logger(session: 'test')),
      cookies: CookieJar(Canned.cookies),
      logger: Logger(session: 'test'),
    );
    final reporter = make(over: guarded);
    player.emit(const StatusChanged(PlayerStatus.playing));
    position(16);
    await pumpEventQueue();
    await reporter.leave();
    expect(sent(), isEmpty);
    expect(waiting(), isEmpty);
  });

  test('while the account may not report, nothing is sent or kept', () async {
    loggedIn = false;
    final reporter = make();
    http.errors[heartbeatPath] = const SocketException('offline');
    player.emit(const StatusChanged(PlayerStatus.playing));
    position(16);
    await pumpEventQueue();
    await reporter.leave();
    expect(http.to(heartbeatPath), isEmpty);
    expect(waiting(), isEmpty);
  });
}
