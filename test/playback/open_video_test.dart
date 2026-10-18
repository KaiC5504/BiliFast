import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player/playback_clock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player.dart';
import 'fakes.dart';

const bv = 'BV1GJ411x7h7';
const playerInfoPath = '/x/player/wbi/v2';

/// The canned playurl answer with Bilibili's saved progress for this account.
String playUrlSaved({required int seconds, required int cid}) => Canned.playUrl().replaceFirst(
  '"quality":120,',
  '"quality":120,"last_play_time":${seconds * 1000},"last_play_cid":$cid,',
);

/// A view of [bv] in one part.
const onePartView = '{"code":0,"data":{"bvid":"$bv","aid":1,"title":"单P","owner":{"mid":1,"name":"UP"},'
    '"pages":[{"cid":137649199,"page":1,"part":"","duration":712}]}}';

void main() {
  late CannedHttp http;
  late FakeEngine engine;
  late FakePlayer player;
  late ManualClock time;
  late MemorySink logs;

  setUp(() {
    http = Canned.http();
    engine = FakeEngine();
    player = FakePlayer();
    time = ManualClock(10000);
    logs = MemorySink();
  });

  PlaybackController make() {
    final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
    final logger = Logger(session: 'test')..add(logs);
    final client = BiliClient(transport: http, cookies: CookieJar(Canned.cookies), now: () => now, logger: logger);
    return PlaybackController(
      client: client,
      engine: engine,
      player: player,
      clock: time.clock,
      now: () => now,
      startTimer: FakeTimers().start,
      logger: logger,
    );
  }

  Map<String, Object> fieldsOf(String msg) => {
        for (final MapEntry(:key, :value) in logs.events.singleWhere((event) => event.msg == msg).f.entries)
          key: switch (value) {
            LogInt(:final value) => value,
            LogString(:final value) => value,
            _ => '$value',
          },
      };

  /// Playing at 45 s of 712.
  void playAt45() {
    player.emit(const StatusChanged(PlayerStatus.playing));
    time.advance(PlaybackClock.jumpSettleMs);
    player.emit(PositionChanged(seconds: 45, hostMs: time.clock.nowMs(), rate: 1));
    player.emit(const DurationChanged(712));
  }

  test('without a part, a video in parts plays the one Bilibili saw last, from where it saw it', () async {
    http.routes[playerInfoPath] = (200, '{"code":0,"data":{"last_play_cid":137649200,"view_points":[]}}');
    http.routes[Canned.playUrlPath] = (200, playUrlSaved(seconds: 30, cid: 137649200));
    final controller = make();
    await controller.openVideo(bv);
    expect(http.to(playerInfoPath).single.url.queryParameters['cid'], '137649199', reason: 'asked with P1');
    expect(controller.page?.page, 2);
    expect(http.to(Canned.playUrlPath).single.url.queryParameters['cid'], '137649200');
    expect(player.loaded?.startSeconds, 30);
  });

  test('a part given plays from its saved position; near the end or saved on another part, from 0', () async {
    http.routes[Canned.playUrlPath] = (200, playUrlSaved(seconds: 300, cid: 137649199));
    final controller = make();
    await controller.openVideo(bv, cid: 137649199);
    expect(http.to(playerInfoPath), isEmpty);
    expect(player.loaded?.startSeconds, 300);

    http.routes[Canned.playUrlPath] = (200, playUrlSaved(seconds: 709, cid: 137649199));
    await controller.openVideo(bv, cid: 137649199);
    expect(player.loaded?.startSeconds, 0, reason: 'finished: the last 5 s start again at 0');

    http.routes[Canned.playUrlPath] = (200, playUrlSaved(seconds: 50, cid: 137649199));
    await controller.openVideo(bv, cid: 137649200);
    expect(player.loaded?.startSeconds, 0, reason: 'the saved position belongs to P1');
  });

  test('a start given wins over the saved position, and a restart keeps the playhead', () async {
    http.routes[Canned.playUrlPath] = (200, playUrlSaved(seconds: 300, cid: 137649199));
    final controller = make();
    await controller.openVideo(bv, cid: 137649199, start: 12);
    expect(player.loaded?.startSeconds, 12);
    await controller.setMode(PlaybackMode.direct);
    expect(player.loaded?.startSeconds, 12, reason: 'the saved position is only for the open');
  });

  test('without the player info, a video in parts plays P1 and logs which', () async {
    final controller = make();
    await controller.openVideo(bv);
    expect(controller.page?.page, 1);
    expect(controller.phase, isNot(PlaybackPhase.failed));
    expect(fieldsOf('player info failed, playing P1'), allOf(containsPair('bvid', bv), containsPair('cid', 137649199)));
  });

  test('a part the video does not have plays P1 and logs which', () async {
    final controller = make();
    await controller.openVideo(bv, cid: 42);
    expect(controller.page?.page, 1);
    expect(fieldsOf('part not in the video, playing P1'), {'bvid': bv, 'cid': 42});
  });

  test('a one-part video does not ask for the player info', () async {
    http.routes[Canned.signedViewPath] = (200, onePartView);
    final controller = make();
    await controller.openVideo(bv);
    expect(http.to(playerInfoPath), isEmpty);
    expect(controller.page?.cid, 137649199);
  });

  test('close stops playback and forgets the video; opens are counted', () async {
    final controller = make();
    await controller.openVideo(bv, cid: 137649199);
    expect(controller.opens, 1);
    controller.close();
    expect(controller.video, isNull);
    expect(controller.page, isNull);
    expect(controller.phase, PlaybackPhase.idle);
    expect(engine.released, isNotEmpty);
    await controller.open(bv);
    expect(controller.opens, 2);
  });

  test('close unloads the player and puts the playhead at 0; the next open still loads', () async {
    final controller = make();
    await controller.openVideo(bv, cid: 137649199, start: 0);
    playAt45();
    expect(controller.currentSeconds, closeTo(45, 1e-6));
    controller.close();
    await settle();
    expect(player.calls.sublist(player.calls.lastIndexOf('pause')), ['pause', 'unload']);
    expect(controller.clock.seconds, 0);
    expect(controller.currentSeconds, 0);
    expect(controller.duration.value, 0);

    await controller.openVideo(bv, cid: 137649199, start: 0);
    expect(player.calls.last, 'load ${FakeEngine.masterOf('tok2')}');
    expect(controller.phase, PlaybackPhase.loading);
  });

  test('a new open reads 0 s from its start, not the last video\'s time until its load', () async {
    final controller = make();
    await controller.openVideo(bv, cid: 137649199, start: 0);
    playAt45();
    final gate = http.gates[Canned.playUrlPath] = Completer<void>();
    final opening = controller.openVideo(bv, cid: 137649200, start: 0);
    await settle();
    expect(controller.page?.page, 2, reason: 'the page shows the player from here');
    expect(controller.clock.seconds, 0);
    expect(controller.currentSeconds, 0);
    expect(controller.duration.value, 0);
    gate.complete();
    await opening;
    expect(player.loaded?.startSeconds, 0);
  });
}
