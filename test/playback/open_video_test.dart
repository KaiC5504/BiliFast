import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/playback/playback_controller.dart';
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

void main() {
  late CannedHttp http;
  late FakeEngine engine;
  late FakePlayer player;

  setUp(() {
    http = Canned.http();
    engine = FakeEngine();
    player = FakePlayer();
  });

  PlaybackController make() {
    final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
    final logger = Logger(session: 'test');
    final client = BiliClient(transport: http, cookies: CookieJar(Canned.cookies), now: () => now, logger: logger);
    return PlaybackController(
      client: client,
      engine: engine,
      player: player,
      clock: ManualClock(10000).clock,
      now: () => now,
      startTimer: FakeTimers().start,
      logger: logger,
    );
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

  test('without the player info, a video in parts plays P1', () async {
    final controller = make();
    await controller.openVideo(bv);
    expect(controller.page?.page, 1);
    expect(controller.phase, isNot(PlaybackPhase.failed));
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
}
