import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/video/page_session.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:bilifast/video/player_session.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';
import '../support/fake_player.dart';

const bv = 'BV1GJ411x7h7';
const p1 = 137649199;
const p2 = 137649200;
const playerInfoPath = '/x/player/wbi/v2';
const relatedPath = '/x/web-interface/archive/related';
const watchLaterPath = '/x/v2/history/toview/add';

String playerInfo({int lastPlayCid = 0, String chapter = '开场'}) =>
    '{"code":0,"data":{"last_play_cid":$lastPlayCid,"view_points":['
    '{"type":2,"from":0,"to":60,"content":"$chapter"},{"type":2,"from":60,"to":120,"content":"正片"}]}}';

const related =
    '{"code":0,"data":[{"aid":9,"bvid":"BV1EF411e9oF","cid":5,"title":"相关视频","pic":"","duration":60,'
    '"owner":{"mid":7,"name":"UP"},"stat":{"view":1,"danmaku":0,"like":0}}]}';

String _episode(String bvid, int cid, String title) =>
    '{"aid":1,"cid":$cid,"title":"$title","bvid":"$bvid","arc":{"aid":1,"title":"$title","duration":100}}';

/// A one-part video [bvid] in a 合集 of two sections: 第一集 and 第二集, then 番外.
String seasonView(String bvid, int cid) =>
    '{"code":0,"data":{"bvid":"$bvid","aid":2,"title":"合集里的视频",'
    '"owner":{"mid":1,"name":"UP"},"pages":[{"cid":$cid,"page":1,"part":"","duration":100}],'
    '"ugc_season":{"id":1,"title":"合集","sections":['
    '{"id":1,"title":"正片","episodes":[${_episode('BV1AA411a1aa', 1001, '第一集')},${_episode('BV1BB411b1bb', 1002, '第二集')}]},'
    '{"id":2,"title":"特别篇","episodes":[${_episode('BV1CC411c1cc', 1003, '番外')}]}]}}}';

final class FakePeriodic {
  final ticks = <void Function()>[];
  final timers = <FakeTimer>[];

  Timer start(Duration period, void Function() tick) {
    final timer = FakeTimer(period, tick);
    ticks.add(tick);
    timers.add(timer);
    return timer;
  }

  void tick() {
    for (var i = 0; i < timers.length; i++) {
      if (timers[i].isActive) ticks[i]();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CannedHttp http;
  late FakeEngine engine;
  late FakePlayer player;
  late ManualClock time;
  late FakePeriodic periodic;
  late FakeTimers timers;
  late PlayerPrefs prefs;
  late List<String> opened;
  late PlaybackController controller;
  final sessions = <PagePlayerSession>[];
  final controllers = <PlaybackController>[];

  setUp(() {
    http = Canned.http()
      ..routes[relatedPath] = (200, related)
      ..routes[watchLaterPath] = (200, '{"code":0,"message":"0"}');
    engine = FakeEngine();
    player = FakePlayer();
    time = ManualClock(10000);
    periodic = FakePeriodic();
    timers = FakeTimers();
    prefs = PlayerPrefs.memory();
    opened = [];
  });

  tearDown(() {
    for (final session in sessions) {
      session.dispose();
    }
    sessions.clear();
    for (final controller in controllers) {
      controller.dispose();
    }
    controllers.clear();
  });

  PlaybackController makeController() {
    final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
    final logger = Logger(session: 'test');
    final client = BiliClient(transport: http, cookies: CookieJar(Canned.cookies), now: () => now, logger: logger);
    controller = PlaybackController(
      client: client,
      engine: engine,
      player: player,
      clock: time.clock,
      now: () => now,
      startTimer: FakeTimers().start,
      logger: logger,
    );
    controllers.add(controller);
    return controller;
  }

  /// A session as the video page makes it: `open` plays on the same controller.
  PagePlayerSession makeSession() {
    final controller = makeController();
    final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
    final session = PagePlayerSession(
      controller: controller,
      client: BiliClient(transport: http, cookies: CookieJar(Canned.cookies), now: () => now),
      open: (bvid, {cid}) {
        opened.add('$bvid ${cid ?? '-'}');
        unawaited(controller.openVideo(bvid, cid: cid));
      },
      isVip: () => false,
      prefs: prefs,
      clock: time.clock,
      periodic: periodic.start,
      startTimer: timers.start,
      logger: Logger(session: 'test'),
    );
    sessions.add(session);
    return session;
  }

  void playing() {
    player.emit(const StatusChanged(PlayerStatus.playing));
    player.emit(const DurationChanged(712));
  }

  Future<void> ended() async {
    player.emit(const StatusChanged(PlayerStatus.ended));
    await settle();
  }

  List<String> callsAfterLastLoad() => player.calls.sublist(player.calls.lastIndexWhere((c) => c.startsWith('load')));

  test('the chosen rate plays the next part too, and a new page starts at 1×', () async {
    final session = makeSession();
    await controller.openVideo(bv, cid: p1);
    await session.setRate(1.5);
    expect(player.calls.last, 'rate 1.5');
    session.playEpisode(session.episodes[1]);
    await settle();
    expect(controller.page?.cid, p2);
    expect(callsAfterLastLoad(), contains('rate 1.5'), reason: 'applied after the load');
    expect(session.rate, 1.5);

    session.dispose();
    sessions.remove(session);
    final next = PagePlayerSession(
      controller: controller,
      client: BiliClient(transport: http, cookies: CookieJar(Canned.cookies)),
      open: (_, {cid}) {},
      isVip: () => false,
      prefs: prefs,
    );
    sessions.add(next);
    expect(next.rate, 1);
  });

  test('hold to speed up plays at 2× without changing the rate, then goes back', () async {
    final session = makeSession();
    await controller.openVideo(bv, cid: p1);
    await session.setRate(1.25);
    var notified = 0;
    session.addListener(() => notified++);
    session.speedUp(true);
    expect(player.calls.last, 'rate 2.0');
    expect(session.speedingUp, isTrue);
    expect(session.rate, 1.25);
    session.speedUp(false);
    expect(player.calls.last, 'rate 1.25');
    expect(session.speedingUp, isFalse);
    expect(notified, 2);
  });

  test('fit and mirroring reach the player and stay for the next load; fit is saved', () async {
    final session = makeSession();
    await controller.openVideo(bv, cid: p1);
    await session.setFit(FitMode.fill);
    await session.setMirrored(true);
    expect(prefs.fit, FitMode.fill);
    await controller.openVideo(bv, cid: p2);
    await settle();
    expect(callsAfterLastLoad(), containsAll(['fit fill', 'mirrored true']));
  });

  group('at the end', () {
    test('单集循环 plays the same part again from 0', () async {
      final session = makeSession()..setLoop(LoopMode.single);
      await controller.openVideo(bv, cid: p1);
      playing();
      player.calls.clear();
      await ended();
      expect(player.calls, containsAllInOrder(['seek 0.0 precise', 'play']));
      expect(opened, isEmpty);
      expect(session.ended, isFalse);
    });

    test('自动连播 opens the next part through the page', () async {
      final session = makeSession();
      await controller.openVideo(bv, cid: p1);
      expect(session.next, const Episode(bvid: bv, cid: p2, title: 'P2 第二集', current: false));
      playing();
      await ended();
      expect(opened, ['$bv $p2']);
      expect(controller.page?.cid, p2);
    });

    test('without 自动连播 or a loop, the end screen shows', () async {
      final session = makeSession()..setAutoplayNext(false);
      await controller.openVideo(bv, cid: p1);
      playing();
      var notified = 0;
      session.addListener(() => notified++);
      await ended();
      expect(opened, isEmpty);
      expect(session.ended, isTrue);
      expect(notified, greaterThan(0));
    });

    test('the last part with nothing after it ends', () async {
      final session = makeSession();
      await controller.openVideo(bv, cid: p2);
      expect(session.next, isNull);
      playing();
      await ended();
      expect(opened, isEmpty);
      expect(session.ended, isTrue);
    });

    test('列表循环 wraps from the last part to the first', () async {
      final session = makeSession()..setLoop(LoopMode.list);
      await controller.openVideo(bv, cid: p2);
      expect(session.next?.cid, p1);
      playing();
      await ended();
      expect(opened, ['$bv $p1']);
    });

    test('列表循环 wraps a 合集 from its last episode to its first', () async {
      http.routes[Canned.signedViewPath] = (200, seasonView('BV1CC411c1cc', 1003));
      makeSession().setLoop(LoopMode.list);
      await controller.openVideo('BV1CC411c1cc');
      playing();
      await ended();
      expect(opened, ['BV1AA411a1aa 1001']);
    });

    test('replay after the end screen plays from 0, and togglePlay does the same', () async {
      final session = makeSession()..setAutoplayNext(false);
      await controller.openVideo(bv, cid: p2);
      playing();
      await ended();
      expect(session.ended, isTrue);
      player.calls.clear();
      session.togglePlay();
      await settle();
      expect(player.calls, containsAllInOrder(['seek 0.0 precise', 'play']));
      expect(session.ended, isFalse);
    });
  });

  test('a one-part video in a 合集: 选集 lists its section and 自动连播 plays the next episode', () async {
    http.routes[Canned.signedViewPath] = (200, seasonView('BV1AA411a1aa', 1001));
    final session = makeSession();
    await controller.openVideo('BV1AA411a1aa');
    expect(session.episodesAreParts, isFalse);
    expect(session.episodes, const [
      Episode(bvid: 'BV1AA411a1aa', cid: 1001, title: '第一集', current: true),
      Episode(bvid: 'BV1BB411b1bb', cid: 1002, title: '第二集', current: false),
    ]);
    expect(session.next, const Episode(bvid: 'BV1BB411b1bb', cid: 1002, title: '第二集', current: false));
    expect(session.title, '合集里的视频');
    playing();
    await ended();
    expect(opened, ['BV1BB411b1bb 1002']);
  });

  test('a video in parts lists its parts as P1 name, titles with the part and shares with ?p', () async {
    final session = makeSession();
    await controller.openVideo(bv, cid: p2);
    expect(session.episodesAreParts, isTrue);
    expect(session.episodes.map((e) => (e.title, e.current)), [('P1 第一集', false), ('P2 第二集', true)]);
    expect(session.title, '第二集');
    expect(session.shareLink.toString(), 'https://www.bilibili.com/video/$bv?p=2');
    await controller.openVideo(bv, cid: p1);
    expect(session.shareLink.toString(), 'https://www.bilibili.com/video/$bv');
  });

  group('in the background', () {
    test('without picture in picture the player pauses; with it, it plays on', () async {
      final session = makeSession();
      await controller.openVideo(bv, cid: p1);
      playing();
      player.calls.clear();
      session.didChangeAppLifecycleState(AppLifecycleState.paused);
      timers.activeWith(PagePlayerSession.backgroundGrace)!.fire();
      expect(player.calls, ['pause']);

      session.didChangeAppLifecycleState(AppLifecycleState.resumed);
      player.emit(const StatusChanged(PlayerStatus.playing));
      player.emit(const PictureInPictureChanged(true));
      player.calls.clear();
      session.didChangeAppLifecycleState(AppLifecycleState.paused);
      timers.activeWith(PagePlayerSession.backgroundGrace)!.fire();
      expect(player.calls, isEmpty);
    });

    test('autoplay is skipped without picture in picture', () async {
      final session = makeSession();
      await controller.openVideo(bv, cid: p1);
      playing();
      session.didChangeAppLifecycleState(AppLifecycleState.paused);
      await ended();
      expect(opened, isEmpty);
      expect(session.ended, isTrue);
    });

    test('with picture in picture autoplay goes on', () async {
      final session = makeSession();
      await controller.openVideo(bv, cid: p1);
      playing();
      player.emit(const PictureInPictureChanged(true));
      session.didChangeAppLifecycleState(AppLifecycleState.paused);
      await ended();
      expect(opened, ['$bv $p2']);
    });
  });

  test('定时关闭 counts down, pauses at zero and turns itself off', () async {
    final session = makeSession();
    await controller.openVideo(bv, cid: p1);
    playing();
    session.setSleepTimer(const Duration(minutes: 1));
    expect(session.sleepTimer, const Duration(minutes: 1));
    expect(session.sleepRemaining.value, const Duration(minutes: 1));
    time.advance(30000);
    periodic.tick();
    expect(session.sleepRemaining.value, const Duration(seconds: 30));
    player.calls.clear();
    time.advance(30000);
    periodic.tick();
    expect(player.calls, ['pause']);
    expect(session.sleepTimer, isNull);
    expect(session.sleepRemaining.value, isNull);
    expect(periodic.timers.every((timer) => !timer.isActive), isTrue);

    session.setSleepTimer(const Duration(minutes: 15));
    session.setSleepTimer(null);
    expect(session.sleepRemaining.value, isNull);
    expect(periodic.timers.every((timer) => !timer.isActive), isTrue);
  });

  group('看点', () {
    test('the player info that chose the part gives its chapters; another part asks once for its own', () async {
      http.routes[playerInfoPath] = (200, playerInfo(lastPlayCid: p1));
      final session = makeSession();
      await controller.openVideo(bv);
      await settle();
      expect(http.to(playerInfoPath), hasLength(1));
      expect(session.chapters.map((c) => c.title), ['开场', '正片']);

      http.routes[playerInfoPath] = (200, playerInfo(chapter: '第二P开场'));
      session.playEpisode(session.episodes[1]);
      await settle();
      expect(http.to(playerInfoPath), hasLength(2));
      expect(http.to(playerInfoPath).last.url.queryParameters['cid'], '$p2');
      expect(session.chapters.first.title, '第二P开场');
    });

    test('a part given asks once; a failure leaves none', () async {
      http.routes[playerInfoPath] = (500, '');
      final session = makeSession();
      await controller.openVideo(bv, cid: p2);
      await settle();
      expect(http.to(playerInfoPath), hasLength(1));
      expect(session.chapters, isEmpty);
    });
  });

  test('related videos are asked for once per video, not per part', () async {
    final session = makeSession();
    await controller.openVideo(bv, cid: p1);
    await settle();
    expect(session.related.single.bvid, 'BV1EF411e9oF');
    await controller.openVideo(bv, cid: p2);
    await settle();
    expect(http.to(relatedPath), hasLength(1));
    session.playRelated(session.related.single);
    expect(opened, ['BV1EF411e9oF -']);
  });

  test('once its page closed the player, the session ignores the next page\'s video', () async {
    final session = makeSession();
    await controller.openVideo(bv, cid: p1);
    await settle();
    controller.close();
    http.routes[Canned.signedViewPath] = (200, seasonView('BV1AA411a1aa', 1001));
    await controller.openVideo('BV1AA411a1aa');
    await settle();
    expect(http.to(relatedPath), hasLength(1));
    expect(session.related.single.bvid, 'BV1EF411e9oF');
    playing();
    await ended();
    expect(opened, isEmpty);
  });

  test('稍后再看 toasts what happened', () async {
    final session = makeSession();
    expect(await session.watchLater(), '视频还没有加载完');
    await controller.openVideo(bv, cid: p1);
    expect(await session.watchLater(), '已添加至稍后再看');
    expect(http.to(watchLaterPath), hasLength(1));
    http.routes[watchLaterPath] = (200, '{"code":-101,"message":"账号未登录"}');
    expect(await session.watchLater(), '需要登录');
  });

  test('the screenshot toasts 已保存到相册, or 保存失败 when the player cannot', () async {
    final session = makeSession();
    expect(session.canCaptureFrame, isTrue);
    expect(await session.captureFrame(), '已保存到相册');
    session.dispose();
    sessions.remove(session);

    player = FakePlayer(capabilities: PlayerCapabilities.none);
    final without = makeSession();
    expect(without.canCaptureFrame, isFalse);
    expect(without.pictureInPictureSupported, isFalse);
    expect(await without.captureFrame(), '保存失败');
  });

  group('seeks', () {
    test('a committed seek holds scrubbing at the target until it lands', () async {
      final session = makeSession();
      await controller.openVideo(bv, cid: p1);
      playing();
      session.scrub(90);
      expect(session.position, 90);
      session.hint(95);
      expect(engine.hints.last.seconds, 95);
      final commit = session.commitSeek(100);
      expect(session.scrubbing.value, 100, reason: 'held while the seek runs');
      expect(player.calls, contains('seek 100.0'));
      await commit;
      expect(session.scrubbing.value, isNull);
      expect(controller.clock.seconds, closeTo(100, 0.01));
    });

    test('a drag begun before the seek landed keeps its own target', () async {
      final session = makeSession();
      await controller.openVideo(bv, cid: p1);
      playing();
      final commit = session.commitSeek(100);
      session.scrub(200);
      await commit;
      expect(session.scrubbing.value, 200);
    });

    test('a drag that ends without a seek takes its hint back', () async {
      final session = makeSession();
      await controller.openVideo(bv, cid: p1);
      playing();
      session.scrub(50);
      session.hint(50);
      session.cancelScrub();
      expect(session.scrubbing.value, isNull);
      expect(engine.hints.last.seconds, isNull);
    });

    test('nothing seeks before the duration is known', () async {
      final session = makeSession();
      await controller.openVideo(bv, cid: p1);
      session.scrub(10);
      await session.commitSeek(10);
      expect(session.scrubbing.value, isNull);
      expect(player.calls.where((c) => c.startsWith('seek')), isEmpty);
    });
  });

  test('settings that Swift kept are saved and applied to the next page', () async {
    final session = makeSession();
    session
      ..setLoop(LoopMode.list)
      ..setAutoplayNext(false)
      ..setShowStats(true)
      ..setDanmakuOn(false);
    await session.setBtr(false);
    await session.setQuality(80);
    await session.setCodec(VideoCodec.avc);
    expect(prefs.toJson(), {
      'autoplay': false,
      'loop': 'list',
      'fit': 'fit',
      'btr': false,
      'showStats': true,
      'danmakuOn': false,
      'quality': 80,
      'codec': 'avc',
    });

    final fresh = PlaybackController(
      client: BiliClient(transport: http, cookies: CookieJar(Canned.cookies)),
      engine: FakeEngine(),
      player: FakePlayer(),
    );
    final next = PagePlayerSession(
      controller: fresh,
      client: BiliClient(transport: http, cookies: CookieJar(Canned.cookies)),
      open: (_, {cid}) {},
      isVip: () => true,
      prefs: prefs,
    );
    sessions.add(next);
    await settle();
    expect(fresh.mode, PlaybackMode.direct);
    expect(fresh.selectedQuality, 80);
    expect(fresh.codec, VideoCodec.avc);
    expect(next.btr, isFalse);
    expect(next.isVip, isTrue);
    expect(next.loop, LoopMode.list);
    controllers.add(fresh);
  });
}
