import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart' show PlaybackMode;
import 'package:bili_core/shared.dart';
import 'package:bilifast/offline/fake_offline_library.dart';
import 'package:bilifast/offline/page/offline_playback.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player.dart';
import 'fakes.dart';

const bv = 'BV1GJ411x7h7';
const p1 = 137649199;

/// 详情页直接播放 off opens a video paused, and 应用外自动小窗播放 off keeps auto picture in picture off (172, 174).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CannedHttp http;
  late FakeEngine engine;
  late FakePlayer player;
  late MemorySink logs;
  late PlayerPrefs prefs;

  setUp(() {
    http = Canned.http();
    engine = FakeEngine();
    player = FakePlayer();
    logs = MemorySink();
    final saved = PlayerPrefs.shared;
    PlayerPrefs.shared = prefs = PlayerPrefs.memory();
    addTearDown(() => PlayerPrefs.shared = saved);
  });

  PlaybackController make({bool Function()? autoPipAllowed}) {
    final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
    final logger = Logger(session: 'test')..add(logs);
    final controller = PlaybackController(
      client: BiliClient(transport: http, cookies: CookieJar(Canned.cookies), now: () => now, logger: logger),
      engine: engine,
      player: player,
      clock: ManualClock(10000).clock,
      now: () => now,
      startTimer: FakeTimers().start,
      logger: logger,
      autoPipAllowed: autoPipAllowed,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  List<String> autoPip() => [
    for (final call in player.calls)
      if (call.startsWith('pip auto')) call,
  ];

  group('an open without autoplay', () {
    test('loads paused from its start, and is not about to play while it loads', () async {
      final controller = make();
      final opening = controller.openVideo(bv, cid: p1, start: 30, autoplay: false);
      expect(controller.loadWillPlay, isFalse, reason: 'a page covered now must not resume it when shown');
      await opening;
      expect(player.loaded?.autoplay, isFalse);
      expect(player.loaded?.startSeconds, 30);
      expect(controller.phase, PlaybackPhase.playing, reason: 'loaded, so its controls are the paused ones');
      expect(controller.hasPlayed, isFalse);
    });

    test('still resumes where Bilibili saw it last', () async {
      http.routes[Canned.playUrlPath] = (
        200,
        Canned.playUrl().replaceFirst('"quality":120,', '"quality":120,"last_play_time":45000,"last_play_cid":$p1,'),
      );
      final controller = make();
      await controller.openVideo(bv, cid: p1, autoplay: false);
      expect(player.loaded?.startSeconds, 45);
      expect(player.loaded?.autoplay, isFalse);
    });

    test('stays paused through a reload before its first play, and plays once played', () async {
      final controller = make();
      await controller.openVideo(bv, cid: p1, start: 0, autoplay: false);
      player.emit(const StatusChanged(PlayerStatus.paused));
      await controller.setQuality(80);
      await settle();
      expect(player.loaded?.autoplay, isFalse, reason: 'the reload keeps it paused');
      expect(player.calls, isNot(contains('play')));

      player.emit(const StatusChanged(PlayerStatus.playing));
      expect(controller.hasPlayed, isTrue);
      final first = logs.events.singleWhere((event) => event.msg == 'first frame');
      expect(first.f['timed'], const LogBool(false), reason: 'the wait for ▶ is not startup time');
    });

    for (final (name, change) in <(String, Future<void> Function(PlaybackController))>[
      ('a quality', (controller) => controller.setQuality(80)),
      ('a codec', (controller) => controller.setCodec(VideoCodec.av1)),
      ('BTR', (controller) => controller.setMode(PlaybackMode.direct)),
    ]) {
      test('$name change while its first load is still out keeps it paused', () async {
        final controller = make();
        http.gates[Canned.playUrlPath] = Completer<void>();
        final opening = controller.openVideo(bv, cid: p1, start: 0, autoplay: false);
        await pumpEventQueue();
        expect(controller.phase, PlaybackPhase.loading);
        final changing = change(controller);
        http.gates[Canned.playUrlPath]!.complete();
        await Future.wait([opening, changing]);
        await settle();
        expect(player.loaded?.autoplay, isFalse);
        expect(player.calls, isNot(contains('play')));
      });
    }

    test('a cached part loads paused too', () async {
      final library = FakeOfflineLibrary.demo();
      final controller = make();
      await controller.openLocal(() async => localVideoOf((await library.playback(7003))!), start: 23, autoplay: false);
      await settle();
      expect(player.loaded?.autoplay, isFalse);
      expect(player.loaded?.startSeconds, 23);
      expect(controller.hasPlayed, isFalse);
    });

    test('an open with autoplay, the default, plays', () async {
      final controller = make();
      await controller.openVideo(bv, cid: p1, start: 0);
      expect(player.loaded?.autoplay, isTrue);
    });
  });

  group('应用外自动小窗播放', () {
    test('off, the first play leaves auto picture in picture off, logged once', () async {
      final controller = make(autoPipAllowed: () => false);
      await controller.openVideo(bv, cid: p1, start: 0);
      player
        ..emit(const StatusChanged(PlayerStatus.playing))
        ..emit(const StatusChanged(PlayerStatus.paused))
        ..emit(const StatusChanged(PlayerStatus.playing));
      await settle();
      expect(autoPip(), isEmpty);
      expect(logs.events.where((event) => event.msg == 'auto pip off by setting'), hasLength(1));
    });

    test('off, turning it on (a page shown, a card taken over) turns it off instead', () async {
      final controller = make(autoPipAllowed: () => false);
      await controller.openVideo(bv, cid: p1, start: 0);
      player.emit(const StatusChanged(PlayerStatus.playing));
      controller.setAutoPictureInPicture(true);
      controller.setAutoPictureInPicture(true, now: true);
      await settle();
      expect(autoPip(), ['pip auto false', 'pip auto false']);
    });

    test('read at each change: turned off after it was on, then on again', () async {
      var allowed = true;
      final controller = make(autoPipAllowed: () => allowed);
      await controller.openVideo(bv, cid: p1, start: 0);
      player.emit(const StatusChanged(PlayerStatus.playing));
      controller.setAutoPictureInPicture(false);
      allowed = false;
      controller.setAutoPictureInPicture(true);
      allowed = true;
      controller.setAutoPictureInPicture(true);
      await settle();
      expect(autoPip(), ['pip auto true', 'pip auto false', 'pip auto false', 'pip auto true']);
    });

    test('turned on after a first play it refused, the next play turns it on', () async {
      var allowed = false;
      final controller = make(autoPipAllowed: () => allowed);
      await controller.openVideo(bv, cid: p1, start: 0);
      player
        ..emit(const StatusChanged(PlayerStatus.playing))
        ..emit(const StatusChanged(PlayerStatus.paused));
      allowed = true;
      player.emit(const StatusChanged(PlayerStatus.playing));
      await settle();
      expect(autoPip(), ['pip auto true']);
    });

    test('the app reads PlayerPrefs; the small window by hand still starts', () async {
      prefs.autoPip = false;
      final controller = make();
      await controller.openVideo(bv, cid: p1, start: 0);
      player.emit(const StatusChanged(PlayerStatus.playing));
      await controller.startPictureInPicture();
      await settle();
      expect(autoPip(), isEmpty);
      expect(player.calls, contains('pip start'));

      prefs.autoPip = true;
      controller.setAutoPictureInPicture(true, now: true);
      await settle();
      expect(autoPip(), ['pip auto true']);
    });
  });
}
