import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/playback/codec_memory.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player/playback_clock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player.dart';
import 'fakes.dart';

const playing = 'BV1GJ411x7h7';
const next = 'BV1Nx411c7mD';
const nextCid = 222;

/// The next video's signed view, asked ahead by 竖屏's feed: one part, or two.
VideoDetail nextDetail({bool twoParts = false}) => VideoDetail.fromJson({
  'bvid': next,
  'aid': 2,
  'title': '下一个',
  'owner': {'mid': 3, 'name': 'UP'},
  'pages': [
    {'cid': nextCid, 'page': 1, 'part': '', 'duration': 60},
    if (twoParts) {'cid': nextCid + 1, 'page': 2, 'part': '', 'duration': 60},
  ],
});

/// 竖屏's next video loaded while another plays ([PlaybackController.warm]), and the open that plays from it.
void main() {
  late CannedHttp http;
  late FakeEngine engine;
  late FakePlayer player;
  late ManualClock time;
  late MemorySink logs;
  late DateTime now;
  late CodecMemory memory;
  late List<PlaybackController> made;

  setUp(() {
    http = Canned.http();
    engine = FakeEngine();
    player = FakePlayer();
    time = ManualClock(10000);
    logs = MemorySink();
    // Three hours before the canned addresses' deadline.
    now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 3 * 3600) * 1000);
    memory = CodecMemory();
    made = [];
  });

  tearDown(() {
    for (final controller in made) {
      controller.dispose();
    }
  });

  PlaybackController make() {
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
      codecMemory: memory,
    );
    made.add(controller);
    return controller;
  }

  int playUrls() => http.to(Canned.playUrlPath).length;
  int views() => http.to(Canned.viewPath).length + http.to(Canned.signedViewPath).length;

  List<Map<String, Object?>> lines(String msg) => [
    for (final event in logs.events)
      if (event.msg == msg) {for (final MapEntry(:key, :value) in event.f.entries) key: value.toJson()},
  ];

  Object? lastWarmField() => lines('load').last['warm'];

  /// The page's video, playing.
  Future<PlaybackController> withPlaying() async {
    final controller = make();
    await controller.openVideo(playing, cid: 137649199);
    player.emit(const StatusChanged(PlayerStatus.playing));
    return controller;
  }

  group('the open of the warmed video', () {
    test('asks Bilibili nothing and prepares nothing: the warm source is promoted at its start and loaded', () async {
      final controller = await withPlaying();
      expect(engine.prepared, hasLength(1));
      await controller.warm(next, cid: nextCid, detail: nextDetail());
      expect(http.to(Canned.playUrlPath).last.url.queryParameters['cid'], '$nextCid');
      expect(engine.warmed, hasLength(1));
      expect(engine.warmed.single.mode, PlaybackMode.btr);
      expect(engine.promoted, isEmpty);
      expect(controller.video?.bvid, playing, reason: 'the page still plays its video');
      final asked = (playUrls: playUrls(), views: views());

      await controller.openVideo(next, cid: nextCid);
      expect(playUrls(), asked.playUrls, reason: 'the warm answer stands in for the playurl call');
      expect(views(), asked.views, reason: 'the warm detail stands in for the view');
      expect(engine.prepared, hasLength(2), reason: 'no prepare of its own');
      expect(engine.promoted.single, (token: 'tok2', startSeconds: 0));
      expect(player.loaded?.master, FakeEngine.masterOf('tok2'));
      expect(engine.released, ['tok1'], reason: 'the video before goes, the warm source plays');
      expect(controller.video?.bvid, next);
      expect(controller.detail?.bvid, next);
      expect(controller.page?.cid, nextCid);
      expect(lastWarmField(), 'hit');
      expect(lines('story warm').single.keys.toSet(), {'ms', 'segmentBytes'});
    });

    test('the playback on screen keeps its stats and engine reports while the warm exists; promoted, its are shown',
        () async {
      final controller = await withPlaying();
      await controller.warm(next, cid: nextCid, detail: nextDetail());
      engine.statsController
        ..add(const EngineSnapshot(token: 'tok1', downloadBps: 1000))
        ..add(const EngineSnapshot(token: 'tok2', downloadBps: 9999));
      expect(controller.stats.value.downloadBps, 1000, reason: 'the warm session is not this playback');
      time.advance(PlaybackClock.jumpSettleMs);
      player.emit(PositionChanged(seconds: 3, hostMs: time.clock.nowMs(), rate: 1));
      expect([...engine.playheads.map((report) => report.token), ...engine.buffers.map((report) => report.token)],
          everyElement('tok1'));

      await controller.openVideo(next, cid: nextCid);
      engine.statsController.add(const EngineSnapshot(token: 'tok2', downloadBps: 5000));
      expect(controller.stats.value.downloadBps, 5000);
    });

    test('a warm still on its way is waited for, not asked again', () async {
      final controller = await withPlaying();
      engine.prepareGate = Completer<void>();
      final warming = controller.warm(next, cid: nextCid, detail: nextDetail());
      await settle();
      final opening = controller.openVideo(next, cid: nextCid);
      await settle();
      expect(playUrls(), 2);
      expect(player.loaded?.master, FakeEngine.masterOf('tok1'));
      engine.prepareGate!.complete();
      await Future.wait([warming, opening]);
      expect(playUrls(), 2);
      expect(engine.prepared, hasLength(2));
      expect(player.loaded?.master, FakeEngine.masterOf('tok2'));
      expect(lastWarmField(), 'hit');
    });

    test('a start segment over the limit is warmed without its prime, and still opens from the warm', () async {
      engine.warmSegmentBytes = PlaybackRequest.warmPrimeMaxBytes + 1;
      final controller = await withPlaying();
      await controller.warm(next, cid: nextCid, detail: nextDetail());
      expect(lines('story warm').single, {
        'ms': isA<int>(),
        'segmentBytes': PlaybackRequest.warmPrimeMaxBytes + 1,
        'skipped': 'large',
      });
      await controller.openVideo(next, cid: nextCid);
      expect(engine.promoted.single.token, 'tok2', reason: 'promoted, the engine primes it there');
      expect(lastWarmField(), 'hit');
    });

    test('the open starts where the account left the video, and the warm primed there', () async {
      http.routes[Canned.playUrlPath] = (
        200,
        Canned.playUrl().replaceFirst('"quality":120,', '"quality":120,"last_play_time":30000,"last_play_cid":$nextCid,'),
      );
      final controller = await withPlaying();
      await controller.warm(next, detail: nextDetail());
      expect(engine.warmed.single.startSeconds, 30);
      await controller.openVideo(next);
      expect(engine.promoted.single, (token: 'tok2', startSeconds: 30));
      expect(player.loaded?.startSeconds, 30);
    });
  });

  group('a warm that no longer fits is let go and the open takes the usual path', () {
    test('the quality changed', () async {
      final controller = await withPlaying();
      await controller.warm(next, cid: nextCid, detail: nextDetail());
      await controller.setQuality(80);
      expect(engine.released, contains('tok2'));
      final asked = playUrls();
      await controller.openVideo(next, cid: nextCid);
      expect(playUrls(), asked + 1);
      expect(engine.promoted, isEmpty);
      expect(lastWarmField(), 'miss quality');
    });

    test('its codec was refused since: its answer stands, its source goes', () async {
      final controller = await withPlaying();
      await controller.warm(next, cid: nextCid, detail: nextDetail());
      memory.markFailed('hevc');
      final asked = playUrls();
      await controller.openVideo(next, cid: nextCid);
      expect(playUrls(), asked, reason: 'the answer is still good');
      expect(engine.prepared.last.warm, isFalse);
      expect(engine.prepared.last.choice.video.codecs, startsWith('avc1'));
      expect(engine.released, contains('tok2'));
      expect(engine.promoted, isEmpty);
      expect(lastWarmField(), 'miss refused');
    });

    test('its addresses are within five minutes of their deadline', () async {
      now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 20 * 60) * 1000);
      final controller = await withPlaying();
      await controller.warm(next, cid: nextCid, detail: nextDetail());
      now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 200) * 1000);
      final asked = playUrls();
      await controller.openVideo(next, cid: nextCid);
      expect(playUrls(), asked + 1);
      expect(engine.released, contains('tok2'));
      expect(lastWarmField(), 'miss expiring');
    });

    test('it was answered over half an hour ago', () async {
      final controller = await withPlaying();
      await controller.warm(next, cid: nextCid, detail: nextDetail());
      now = now.add(const Duration(minutes: 31));
      final asked = playUrls();
      await controller.openVideo(next, cid: nextCid);
      expect(playUrls(), asked + 1);
      expect(engine.released, contains('tok2'));
      expect(lastWarmField(), 'miss old');
    });

    test('another part of it opens', () async {
      final controller = await withPlaying();
      await controller.warm(next, cid: nextCid, detail: nextDetail(twoParts: true));
      final asked = playUrls();
      await controller.openVideo(next, cid: nextCid + 1, detail: nextDetail(twoParts: true));
      expect(playUrls(), asked + 1);
      expect(http.to(Canned.playUrlPath).last.url.queryParameters['cid'], '${nextCid + 1}');
      expect(engine.released, contains('tok2'));
      expect(lastWarmField(), 'miss part');
    });

    test('another video opens (the one before, swiped back to)', () async {
      final controller = await withPlaying();
      await controller.warm(next, cid: nextCid, detail: nextDetail());
      await controller.openVideo(playing, cid: 137649199);
      expect(engine.released, contains('tok2'));
      expect(lastWarmField(), 'miss other');
    });

    test('its prepare failed: its answer stands and the open prepares itself', () async {
      final controller = await withPlaying();
      engine.prepareErrors.add(const RipperError(RipperErrorKind.noNodes));
      await controller.warm(next, cid: nextCid, detail: nextDetail());
      expect(lines('story warm').single, containsPair('skipped', 'failed'));
      final asked = playUrls();
      await controller.openVideo(next, cid: nextCid);
      expect(playUrls(), asked);
      expect(engine.prepared.last.warm, isFalse);
      expect(lastWarmField(), 'miss failed');
    });

    test('the local server restarted before the open', () async {
      final controller = await withPlaying();
      await controller.warm(next, cid: nextCid, detail: nextDetail());
      engine.restartOnEnsure = true;
      await controller.openVideo(next, cid: nextCid);
      expect(engine.prepared.last.warm, isFalse);
      expect(engine.released, contains('tok2'));
      expect(lastWarmField(), 'miss restarted');
    });

    test('another page\'s probe restarted the local server: this open\'s own probe finds it answering', () async {
      final controller = await withPlaying();
      await controller.warm(next, cid: nextCid, detail: nextDetail());
      engine.serverGeneration++;
      await controller.openVideo(next, cid: nextCid);
      expect(engine.prepared.last.warm, isFalse);
      expect(player.loaded?.master, FakeEngine.masterOf('tok3'));
      expect(engine.released, contains('tok2'));
      expect(engine.promoted, isEmpty);
      expect(lastWarmField(), 'miss restarted');
    });

    test('the open took the warm while it prepared, and another page\'s probe restarted the server meanwhile',
        () async {
      final controller = await withPlaying();
      engine.prepareGate = Completer<void>();
      final warming = controller.warm(next, cid: nextCid, detail: nextDetail());
      await settle();
      final opening = controller.openVideo(next, cid: nextCid);
      await settle();
      engine.serverGeneration++;
      await controller.appResumed();
      engine.prepareGate!.complete();
      await Future.wait([warming, opening]);
      expect(engine.prepared.last.warm, isFalse);
      expect(engine.promoted, isEmpty);
      expect(engine.released, contains('tok2'));
      expect(lastWarmField(), 'miss restarted');
    });
  });

  group('the warm is let go', () {
    final paths = <(String, String, Future<void> Function(PlaybackController controller))>[
      ('on close', 'closed', (controller) async => controller.close()),
      ('on a change of mode', 'mode', (controller) => controller.setMode(PlaybackMode.direct)),
      ('on a change of quality', 'quality', (controller) => controller.setQuality(80)),
      ('on a change of codec', 'codec', (controller) => controller.setCodec(VideoCodec.avc)),
      ('on memory pressure', 'memory', (controller) async => controller.memoryPressure()),
      ('when the page is covered', 'covered', (controller) async => controller.dropPrefetch()),
      ('when the feed lets go of it', 'dropped', (controller) async => controller.dropWarm()),
      ('on a new engine', 'engine', (controller) => controller.useEngine(() async => FakeEngine())),
      ('when the local server restarted', 'restarted', (controller) async {
        engine.restartOnEnsure = true;
        await controller.appResumed();
      }),
      ('when another page\'s probe restarted the local server', 'restarted', (controller) async {
        engine.serverGeneration++;
        await controller.appResumed();
      }),
      ('for a cached part', 'local', (controller) => controller.openLocal(() async => null)),
      ('for the next warm', 'replaced', (controller) async {
        await controller.warm('BV1Other4y1z', cid: 9, detail: VideoDetail.fromJson({
          'bvid': 'BV1Other4y1z',
          'pages': [
            {'cid': 9, 'page': 1, 'part': '', 'duration': 10},
          ],
        }));
      }),
    ];
    for (final (name, reason, act) in paths) {
      test('$name, and the open of its video says why it missed', () async {
        final controller = await withPlaying();
        await controller.warm(next, cid: nextCid, detail: nextDetail());
        await act(controller);
        expect(engine.released, contains('tok2'));
        final asked = playUrls();
        await controller.openVideo(next, cid: nextCid, detail: nextDetail());
        expect(playUrls(), asked + 1);
        expect(engine.promoted, isEmpty);
        expect(lastWarmField(), 'miss $reason');
      });
    }

    test('on dispose', () async {
      final controller = await withPlaying();
      await controller.warm(next, cid: nextCid, detail: nextDetail());
      made.remove(controller);
      controller.dispose();
      await settle();
      expect(engine.released, contains('tok2'));
    });

    test('a warm let go while its prepare is out releases the source as it lands', () async {
      final controller = await withPlaying();
      engine.prepareGate = Completer<void>();
      final warming = controller.warm(next, cid: nextCid, detail: nextDetail());
      await settle();
      controller.dropWarm();
      engine.prepareGate!.complete();
      await warming;
      await settle();
      expect(engine.released, contains('tok2'));
      expect(lines('story warm').single, containsPair('skipped', 'dropped'));
    });
  });

  group('no warm', () {
    test('in direct mode, without the details, or without a part to name: one line, no call', () async {
      final controller = await withPlaying();
      final asked = playUrls();
      await controller.warm(next, cid: nextCid);
      await controller.warm(next, detail: nextDetail(twoParts: true));
      await controller.setMode(PlaybackMode.direct);
      await controller.warm(next, cid: nextCid, detail: nextDetail());
      expect([for (final line in lines('story warm')) line['skipped']], ['detail', 'part', 'mode']);
      expect(playUrls(), asked);
      expect(engine.warmed, isEmpty);
    });

    test('the same video again is the warm in hand', () async {
      final controller = await withPlaying();
      await controller.warm(next, cid: nextCid, detail: nextDetail());
      await controller.warm(next, cid: nextCid, detail: nextDetail());
      expect(engine.warmed, hasLength(1));
      expect(lines('story warm'), hasLength(1));
    });

    test('risk control on the playurl is thrown for the feed, and the open asks for itself', () async {
      final controller = await withPlaying();
      http.routes[Canned.playUrlPath] = (200, '{"code":-352,"message":"-352"}');
      await expectLater(
        controller.warm(next, cid: nextCid, detail: nextDetail()),
        throwsA(isA<BiliAPIError>().having((error) => error.code, 'code', -352)),
      );
      expect(lines('story warm').single, {'ms': isA<int>(), 'error': 'BiliAPIError', 'code': -352, 'skipped': 'failed'});
      expect(engine.warmed, isEmpty);
      http.routes[Canned.playUrlPath] = (200, Canned.playUrl());
      final asked = playUrls();
      await controller.openVideo(next, cid: nextCid, detail: nextDetail());
      expect(playUrls(), asked + 1);
      expect(lastWarmField(), 'miss failed');
    });
  });

  test('the warm lines and the load line\'s field name no video, part, address or token', () async {
    final controller = await withPlaying();
    await controller.warm(next, cid: nextCid, detail: nextDetail());
    await controller.openVideo(next, cid: nextCid);
    await controller.warm(playing, cid: 137649199, detail: VideoDetail.fromJson({'bvid': playing}));
    final values = [
      for (final line in lines('story warm')) ...line.values,
      for (final line in lines('load')) line['warm'],
    ];
    expect(values, isNotEmpty);
    for (final value in values) {
      for (final secret in ['BV1', '$nextCid', '137649199', 'http', 'upos', 'tok', 'deadline']) {
        expect('$value', isNot(contains(secret)));
      }
    }
  });

  group('comfortable', () {
    test('once the playing load holds eight seconds ahead, or all of a short video, with one notification', () async {
      final controller = await withPlaying();
      var notified = 0;
      controller.addListener(() => notified++);
      time.advance(PlaybackClock.jumpSettleMs);
      player.emit(PositionChanged(seconds: 1, hostMs: time.clock.nowMs(), rate: 1));
      player.emit(const BufferedChanged([(start: 0, end: 6)]));
      expect(controller.comfortable, isFalse);
      player.emit(const BufferedChanged([(start: 0, end: 9.5)]));
      expect(controller.comfortable, isTrue);
      player.emit(const BufferedChanged([(start: 0, end: 20)]));
      expect(notified, 1);

      await controller.openVideo(next, cid: nextCid, detail: nextDetail());
      expect(controller.comfortable, isFalse, reason: 'every load starts without it');
      player.emit(const StatusChanged(PlayerStatus.playing));
      player.emit(const DurationChanged(4));
      player.emit(const BufferedChanged([(start: 0, end: 4)]));
      expect(controller.comfortable, isTrue, reason: 'all of it is in');
    });

    test('not before the load has played', () async {
      final controller = make();
      await controller.openVideo(playing, cid: 137649199);
      player.emit(const BufferedChanged([(start: 0, end: 30)]));
      expect(controller.comfortable, isFalse);
      player.emit(const StatusChanged(PlayerStatus.playing));
      player.emit(const BufferedChanged([(start: 0, end: 30)]));
      expect(controller.comfortable, isTrue);
    });
  });
}
