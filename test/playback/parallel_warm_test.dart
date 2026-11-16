import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player.dart';
import 'fakes.dart';

const bv = 'BV1GJ411x7h7';
const p1 = 137649199;
const p2 = 137649200;
const playerInfoPath = '/x/player/wbi/v2';

/// A view of [bv] in one part.
const onePartView = '{"code":0,"data":{"bvid":"$bv","aid":1,"title":"单P","owner":{"mid":1,"name":"UP"},'
    '"pages":[{"cid":$p1,"page":1,"part":"","duration":712}]}}';

String playUrlSaved({required int seconds, required int cid}) => Canned.playUrl().replaceFirst(
  '"quality":120,',
  '"quality":120,"last_play_time":${seconds * 1000},"last_play_cid":$cid,',
);

/// The open's own warm: with the part known up front, its playurl call and prepare run beside the view call.
void main() {
  late CannedHttp http;
  late FakeEngine engine;
  late FakePlayer player;
  late ManualClock time;
  late MemorySink logs;
  late List<PlaybackController> made;

  setUp(() {
    http = Canned.http();
    engine = FakeEngine();
    player = FakePlayer();
    time = ManualClock(10000);
    logs = MemorySink();
    made = [];
  });

  tearDown(() {
    for (final controller in made) {
      controller.dispose();
    }
  });

  PlaybackController make() {
    final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 3 * 3600) * 1000);
    final logger = Logger(session: 'test')..add(logs);
    final client = BiliClient(transport: http, cookies: CookieJar(Canned.cookies), now: () => now, logger: logger);
    final controller = PlaybackController(
      client: client,
      engine: engine,
      player: player,
      clock: time.clock,
      now: () => now,
      startTimer: FakeTimers().start,
      logger: logger,
    );
    made.add(controller);
    return controller;
  }

  int playUrls() => http.to(Canned.playUrlPath).length;

  List<Map<String, Object?>> lines(String msg) => [
    for (final event in logs.events)
      if (event.msg == msg) {for (final MapEntry(:key, :value) in event.f.entries) key: value.toJson()},
  ];

  Object? parallelField() => lines('load').last['parallel'];

  /// The view held until the test lets it answer, so the warm runs while it is out.
  Completer<void> holdView() => http.gates[Canned.signedViewPath] = Completer<void>();

  test('kept: the playurl call and the prepare go out while the view is out, and the open makes neither again',
      () async {
    http.routes[Canned.signedViewPath] = (200, onePartView);
    final view = holdView();
    final controller = make();
    final opening = controller.openVideo(bv, cidHint: p1);
    await settle();
    expect(controller.video, isNull, reason: 'the view is still out');
    expect(http.to(Canned.playUrlPath).single.url.queryParameters['cid'], '$p1');
    expect(engine.prepared, hasLength(1));
    expect(engine.prepared.single.warm, isFalse, reason: 'the video is about to play: an ordinary prepare');
    expect(engine.preconnects, hasLength(1));
    view.complete();
    await opening;
    expect(playUrls(), 1);
    expect(engine.prepared, hasLength(1));
    expect(engine.preconnects, hasLength(1));
    expect(engine.promoted, isEmpty);
    expect(player.loaded?.master, FakeEngine.masterOf('tok1'));
    expect(controller.page?.cid, p1);
    expect(parallelField(), 'kept');
    expect(lines('load').last['warm'], isNull, reason: 'no story warm was in play');
    expect(lines('open warm').single.keys, ['ms']);
  });

  test('the resume point still comes from the view\'s part, and a start given wins', () async {
    http.routes[Canned.signedViewPath] = (200, onePartView);
    http.routes[Canned.playUrlPath] = (200, playUrlSaved(seconds: 30, cid: p1));
    final controller = make();
    await controller.openVideo(bv, cidHint: p1);
    expect(engine.prepared.single.startSeconds, 30);
    expect(player.loaded?.startSeconds, 30);
    expect(parallelField(), 'kept');

    await controller.openVideo(bv, cidHint: p1, start: 12);
    expect(engine.prepared.last.startSeconds, 12);
    expect(player.loaded?.startSeconds, 12);
    expect(parallelField(), 'kept');
  });

  test('the first frame is timed from the open, the view call included', () async {
    final view = holdView();
    final controller = make();
    final frames = <FirstFrame>[];
    controller.marks.listen((mark) {
      if (mark is FirstFrame) frames.add(mark);
    });
    final opening = controller.openVideo(bv, cid: p1);
    await settle();
    time.advance(200);
    view.complete();
    await opening;
    time.advance(100);
    player.emit(const StatusChanged(PlayerStatus.playing));
    await settle();
    expect(frames.single.ms, 300);
  });

  test('dropped when the view plays another part: its source goes, and the open asks for its own part', () async {
    http.routes[playerInfoPath] = (200, '{"code":0,"data":{"last_play_cid":$p1,"view_points":[]}}');
    final controller = make();
    await controller.openVideo(bv, cidHint: p2);
    expect(controller.page?.cid, p1, reason: 'a hint chooses nothing: the part Bilibili saw last plays');
    expect([for (final request in http.to(Canned.playUrlPath)) request.url.queryParameters['cid']], ['$p2', '$p1'],
        reason: 'one call more than without the hint, never more');
    expect(engine.released, ['tok1']);
    expect(player.loaded?.master, FakeEngine.masterOf('tok2'));
    expect(parallelField(), 'dropped part');
  });

  test('dropped on a failed view: the view\'s failure is shown, and nothing is loaded', () async {
    const gone = '{"code":-404,"message":"啥都木有"}';
    http.routes[Canned.signedViewPath] = (200, gone);
    final plain = make();
    await plain.openVideo(bv);
    final expected = plain.error;
    expect(expected, isNotNull);

    // The warm's own call failing too doesn't take the view's place.
    http.routes[Canned.playUrlPath] = (200, '{"code":-352,"message":"-352"}');
    final view = holdView();
    final controller = make();
    final opening = controller.openVideo(bv, cidHint: p1);
    await settle();
    view.complete();
    await opening;
    expect(controller.phase, PlaybackPhase.failed);
    expect(controller.error, expected);
    expect(player.loaded, isNull);
    expect(lines('open warm dropped').single, {'why': 'view'});

    http.routes[Canned.playUrlPath] = (200, Canned.playUrl());
    final other = make();
    await other.openVideo(bv, cidHint: p1);
    expect(other.error, expected);
    await settle();
    expect(engine.released, contains('tok1'), reason: 'a warm source nobody plays is released');
    expect(player.loaded, isNull);
  });

  test('dropped on a redirect (番剧): unsupported, and its source released', () async {
    http.routes[Canned.signedViewPath] =
        (200, onePartView.replaceFirst('"pages"', '"redirect_url":"https://www.bilibili.com/bangumi/play/ep1","pages"'));
    final controller = make();
    await controller.openVideo(bv, cidHint: p1);
    await settle();
    expect(controller.error, PlaybackFailure.unsupported.userMessage);
    expect(engine.released, ['tok1']);
    expect(player.loaded, isNull);
    expect(lines('open warm dropped').single, {'why': 'redirect'});
  });

  test('its playurl failing after a good view is the open\'s failure: the open doesn\'t ask again', () async {
    http.routes[Canned.signedViewPath] = (200, onePartView);
    http.routes[Canned.playUrlPath] = (200, '{"code":-352,"message":"-352"}');
    final controller = make();
    await controller.openVideo(bv, cidHint: p1);
    expect(playUrls(), 1);
    expect(controller.phase, PlaybackPhase.failed);
    expect(engine.prepared, isEmpty);
    expect(lines('open warm').single, containsPair('skipped', 'failed'));
  });

  test('none in direct mode, for a view in hand, or without a part', () async {
    final controller = make();
    await controller.openVideo(bv);
    await controller.openVideo(bv, cidHint: p1, view: controller.video);
    await controller.setMode(PlaybackMode.direct);
    await controller.openVideo(bv, cidHint: p1);
    expect(lines('open warm'), isEmpty);
    expect([for (final line in lines('load')) line['parallel']], everyElement(isNull));
  });

  test('its lines name no video, part, address or token', () async {
    http.routes[playerInfoPath] = (200, '{"code":0,"data":{"last_play_cid":$p1,"view_points":[]}}');
    final controller = make();
    await controller.openVideo(bv, cidHint: p1);
    await controller.openVideo(bv, cidHint: p2);
    http.routes[Canned.signedViewPath] = (200, '{"code":-404,"message":"啥都木有"}');
    await controller.openVideo('BV1Other4y1z', cidHint: 9);
    final values = [
      for (final line in lines('open warm')) ...line.values,
      for (final line in lines('open warm dropped')) ...line.values,
      for (final line in lines('load')) line['parallel'],
    ];
    expect(values, isNotEmpty);
    for (final value in values) {
      for (final secret in ['BV1', '$p1', '$p2', 'http', 'upos', 'tok', 'deadline']) {
        expect('$value', isNot(contains(secret)));
      }
    }
  });

  group('idle', () {
    test('a new source prepared while idle is told so too (a quality change), and not once shown again', () async {
      final controller = make();
      await controller.openVideo(bv, cid: p1);
      controller.setIdle(true);
      expect(engine.idles, [(token: 'tok1', idle: true)]);
      await controller.setQuality(80);
      expect(player.loaded?.master, FakeEngine.masterOf('tok2'));
      expect(engine.idles.last, (token: 'tok2', idle: true));
      controller.setIdle(false);
      await controller.setCodec(VideoCodec.avc);
      expect(engine.idles.last, (token: 'tok2', idle: false), reason: 'tok3 starts busy, as every token does');
    });

    test('a reload in place (a mode change) keeps it idle', () async {
      final controller = make();
      await controller.openVideo(bv, cid: p1);
      controller.setIdle(true);
      await controller.setMode(PlaybackMode.direct);
      await controller.setMode(PlaybackMode.btr);
      expect(engine.idles.last, (token: 'tok3', idle: true));
    });
  });
}
