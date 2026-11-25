import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player/playback_clock.dart';
import 'package:bilifast/video/page_session.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:bilifast/video/player_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';
import '../playback/hi_res_test.dart' show playUrlWithFlac;
import '../support/fake_player.dart';

const bv = 'BV1GJ411x7h7';
const p1 = 137649199;
const p2 = 137649200;
const flacId = 30251;
const aacId = 30280;
const relatedPath = '/x/web-interface/archive/related';

const opening = 'Hi-Res无损音质开启中，请稍候';
const on = 'Hi-Res无损音质已开启';
const off = 'Hi-Res无损音质已关闭';
const failed = 'Hi-Res无损音质开启失败';

final class _Playlist extends ChangeNotifier implements SessionPlaylist {
  @override
  List<Episode> get episodes => const [];

  @override
  String? coverFileOf(int cid) => null;
}

/// The page session's Hi-Res 无损 (274): who is offered it, the switch and its notes, and every open following the
/// pref.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CannedHttp http;
  late FakeEngine engine;
  late FakePlayer player;
  late ManualClock time;
  late PlayerPrefs prefs;
  late PlaybackController controller;
  final sessions = <PagePlayerSession>[];
  final controllers = <PlaybackController>[];

  setUp(() {
    http = Canned.http()
      ..routes[Canned.playUrlPath] = (200, playUrlWithFlac())
      ..routes[relatedPath] = (200, '{"code":0,"data":[]}');
    engine = FakeEngine();
    player = FakePlayer();
    time = ManualClock(10000);
    prefs = PlayerPrefs.memory();
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

  PagePlayerSession makeSession({bool vip = true, SessionPlaylist? playlist}) {
    final controller = makeController();
    final session = PagePlayerSession(
      controller: controller,
      client: BiliClient(transport: http, cookies: CookieJar(Canned.cookies)),
      open: (bvid, {cid, followed = false}) => unawaited(controller.openVideo(bvid, cid: cid)),
      isVip: () => vip,
      isLoggedIn: () => true,
      requestLogin: () {},
      prefs: prefs,
      playlist: playlist,
      startTimer: FakeTimers().start,
      logger: Logger(session: 'test'),
    );
    sessions.add(session);
    return session;
  }

  List<int> audios() => [for (final request in engine.prepared) request.choice.audio.id];
  List<String> notes(PlayerSession session) => [for (final note in session.notes.shown) note.text];

  void playing() => player.emit(const StatusChanged(PlayerStatus.playing));

  void at(double seconds) {
    time.advance(PlaybackClock.jumpSettleMs);
    player.emit(PositionChanged(seconds: seconds, hostMs: time.clock.nowMs(), rate: 1));
  }

  group('offered', () {
    test('to 大会员 when the answer carries a FLAC track', () async {
      final session = makeSession();
      expect(session.hiResOffered, isFalse, reason: 'no answer yet');
      await controller.openVideo(bv, cid: p1);
      expect(session.hiResOffered, isTrue);
      expect(session.hiResOn, isFalse);
    });

    test('never without 大会员, even when an answer carried a track, and the pref then plays AAC', () async {
      prefs.hiRes = true;
      final session = makeSession(vip: false);
      await controller.openVideo(bv, cid: p1);
      expect(controller.hiResOffered, isTrue);
      expect(session.hiResOffered, isFalse);
      expect(session.hiResOn, isTrue, reason: 'the pref, kept for an account that has it');
      expect(audios(), [aacId]);
    });

    test('never on an offline page, which plays AAC whatever the pref', () async {
      prefs.hiRes = true;
      final session = makeSession(playlist: _Playlist());
      await controller.openVideo(bv, cid: p1);
      expect(session.offline, isTrue);
      expect(session.hiResOffered, isFalse);
      expect(audios(), [aacId]);
    });

    test('not for an answer without a FLAC track: turning it on only saves', () async {
      http.routes[Canned.playUrlPath] = (200, Canned.playUrl());
      final session = makeSession();
      await controller.openVideo(bv, cid: p1);
      playing();
      expect(session.hiResOffered, isFalse);
      expect(await session.setHiRes(true), isNull);
      expect(prefs.hiRes, isTrue);
      expect(session.hiResOn, isTrue);
      expect(notes(session), isEmpty);
      expect(engine.prepared, hasLength(1));
    });

    test('the offer arriving notifies, a covered page\'s too', () async {
      final session = makeSession();
      await settle();
      session.active = false;
      final heard = <bool>[];
      session.addListener(() => heard.add(session.hiResOffered));
      await controller.openVideo(bv, cid: p1);
      expect(heard, contains(true));
    });
  });

  group('the switch', () {
    test('on: 开启中 at once, 已开启 at the reopened stream\'s first frame, at the same second, playing', () async {
      final session = makeSession();
      await controller.openVideo(bv, cid: p1);
      playing();
      at(42);
      final switching = session.setHiRes(true);
      expect(notes(session), [opening]);
      expect(prefs.hiRes, isTrue);
      expect(await switching, isNull);
      expect(audios(), [aacId, flacId]);
      expect(player.loaded!.startSeconds, closeTo(42, 1e-9));
      expect(player.loaded!.autoplay, isTrue);
      expect(notes(session), [opening], reason: 'not yet played');
      playing();
      expect(notes(session), [opening, on]);
      expect(session.hiResOn, isTrue);
    });

    test('off: one 已关闭 note, back on AAC at the same second', () async {
      prefs.hiRes = true;
      final session = makeSession();
      await controller.openVideo(bv, cid: p1);
      playing();
      at(30);
      await session.setHiRes(false);
      expect(notes(session), [off]);
      expect(audios(), [flacId, aacId]);
      expect(player.loaded!.startSeconds, closeTo(30, 1e-9));
      playing();
      expect(notes(session), [off]);
      expect(prefs.hiRes, isFalse);
    });

    test('paused, it stays paused, and 已开启 waits until it plays', () async {
      final session = makeSession();
      await controller.openVideo(bv, cid: p1);
      playing();
      player.emit(const StatusChanged(PlayerStatus.paused));
      await session.setHiRes(true);
      expect(player.loaded!.autoplay, isFalse);
      expect(notes(session), [opening]);
      session.togglePlay();
      expect(player.calls.last, 'play');
      playing();
      expect(notes(session), [opening, on]);
    });

    test('a refused FLAC track says 开启失败 and plays on with AAC; the pref stays', () async {
      final session = makeSession();
      await controller.openVideo(bv, cid: p1);
      playing();
      await session.setHiRes(true);
      player.emit(const PlayerFailed('cannot decode', formatRejected: true));
      await settle();
      expect(audios(), [aacId, flacId, aacId]);
      expect(notes(session), [opening, failed]);
      playing();
      expect(notes(session), [opening, failed], reason: 'the AAC stream is no 已开启');
      expect(prefs.hiRes, isTrue);
      expect(session.hiResOn, isTrue);
    });

    test('a refusal on an open says so too', () async {
      prefs.hiRes = true;
      final session = makeSession();
      await controller.openVideo(bv, cid: p1);
      player.emit(const PlayerFailed('cannot decode', formatRejected: true));
      await settle();
      expect(notes(session), [failed]);
      expect(audios(), [flacId, aacId]);
    });
  });

  group('every open follows the pref', () {
    test('the first, the next part from 选集, and a part after another page turned it off', () async {
      prefs.hiRes = true;
      final session = makeSession();
      await controller.openVideo(bv, cid: p1);
      expect(audios(), [flacId]);
      session.playEpisode(session.episodes[1]);
      await settle();
      expect(controller.page?.cid, p2);
      expect(audios(), [flacId, flacId]);
      prefs.hiRes = false;
      session.playEpisode(session.episodes[0]);
      await settle();
      expect(audios(), [flacId, flacId, aacId]);
      expect(notes(session), isEmpty, reason: 'notes are for the switch');
    });

    test('自动连播\'s next part too', () async {
      prefs.hiRes = true;
      makeSession();
      await controller.openVideo(bv, cid: p1);
      playing();
      player.emit(const StatusChanged(PlayerStatus.ended));
      await settle();
      expect(controller.page?.cid, p2);
      expect(audios(), [flacId, flacId]);
    });

    test('a card\'s session, inactive as it is made, plays AAC; taken over, its stream plays on and the next part '
        'takes FLAC', () async {
      prefs.hiRes = true;
      final session = makeSession()..active = false;
      await controller.openVideo(bv, cid: p1);
      expect(audios(), [aacId]);
      session.active = true;
      await settle();
      expect(audios(), [aacId], reason: 'no reload under the page taking it over');
      session.playEpisode(session.episodes[1]);
      await settle();
      expect(audios(), [aacId, flacId]);
    });

    test('a page covered after it was made keeps Hi-Res for what it picks', () async {
      prefs.hiRes = true;
      final session = makeSession();
      await settle();
      session.active = false;
      await controller.openVideo(bv, cid: p1);
      expect(audios(), [flacId]);
      expect(controller.hiRes, isTrue);
    });
  });
}
