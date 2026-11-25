import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart' show PlaybackError, PlaybackErrorKind;
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

/// The app's account as the session hears of it: checked late, so 大会员 arrives after the open.
final class _Account extends ChangeNotifier {
  _Account(this._vip);

  bool _vip;
  bool get vip => _vip;
  set vip(bool value) {
    _vip = value;
    notifyListeners();
  }
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
  late FakeTimers sessionTimers;
  late MemorySink logs;
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
    sessionTimers = FakeTimers();
    logs = MemorySink();
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
    final logger = Logger(session: 'test')..add(logs);
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

  PagePlayerSession makeSession({bool vip = true, _Account? account, SessionPlaylist? playlist}) {
    final controller = makeController();
    final session = PagePlayerSession(
      controller: controller,
      client: BiliClient(transport: http, cookies: CookieJar(Canned.cookies)),
      open: (bvid, {cid, followed = false}) => unawaited(controller.openVideo(bvid, cid: cid)),
      isVip: () => account?.vip ?? vip,
      isLoggedIn: () => true,
      requestLogin: () {},
      accountChanges: account,
      prefs: prefs,
      playlist: playlist,
      startTimer: sessionTimers.start,
      logger: Logger(session: 'test'),
    );
    sessions.add(session);
    return session;
  }

  List<int> audios() => [for (final request in engine.prepared) request.choice.audio.id];
  List<String> notes(PlayerSession session) => [for (final note in session.notes.shown) note.text];

  void playing() => player.emit(const StatusChanged(PlayerStatus.playing));

  FakeTimer? settleTimer() => sessionTimers.activeWith(PagePlayerSession.hiResSettle);

  /// The page has slid in: what the session waited for runs.
  Future<void> slidIn() async {
    settleTimer()!.fire();
    await settle();
  }

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

    test('a refused FLAC track plays on with AAC and says 开启失败 once AAC plays; the pref stays', () async {
      final session = makeSession();
      await controller.openVideo(bv, cid: p1);
      playing();
      await session.setHiRes(true);
      player.emit(const PlayerFailed('cannot decode', formatRejected: true));
      await settle();
      expect(audios(), [aacId, flacId, aacId]);
      expect(notes(session), [opening]);
      playing();
      await settle();
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
      playing();
      await settle();
      expect(notes(session), [failed]);
      expect(audios(), [flacId, aacId]);
    });

    test('a refusal the AAC load disproves says nothing, and 已开启 comes with FLAC on the next codec', () async {
      final session = makeSession();
      await controller.openVideo(bv, cid: p1);
      playing();
      await session.setHiRes(true);
      player.emit(const PlayerFailed('cannot decode', formatRejected: true));
      await settle();
      player.emit(const PlayerFailed('cannot decode', formatRejected: true));
      await settle();
      expect(audios(), [aacId, flacId, aacId, flacId]);
      playing();
      await settle();
      expect(notes(session), [opening, on]);
    });

    test('on while FLAC already plays (turned off on the page above, tapped before this one slid back): 开启中 then '
        '已开启 at once, nothing reopened', () async {
      prefs.hiRes = true;
      final session = makeSession();
      await controller.openVideo(bv, cid: p1);
      playing();
      session.active = false;
      prefs.hiRes = false;
      session.active = true;
      expect(controller.playingFlac, isTrue);
      expect(session.hiResOn, isFalse);
      await session.setHiRes(true);
      expect(notes(session), [opening, on]);
      expect(engine.prepared, hasLength(1));
      await slidIn();
      expect(engine.prepared, hasLength(1));
    });

    test('a reopen that fails leaves no stray 已开启 once FLAC plays later', () async {
      final session = makeSession();
      await controller.openVideo(bv, cid: p1);
      playing();
      engine.prepareErrors.addAll(const [
        PlaybackError(PlaybackErrorKind.serverDown),
        PlaybackError(PlaybackErrorKind.serverDown),
      ]);
      expect(await session.setHiRes(true), isNull);
      expect(controller.phase, PlaybackPhase.failed);
      expect(await session.setQuality(80), isNull);
      expect(controller.playingFlac, isTrue);
      playing();
      await settle();
      expect(notes(session), [opening]);
    });
  });

  test('章节进度条 writes the pref and notifies', () {
    final session = makeSession();
    var heard = 0;
    session.addListener(() => heard += 1);
    expect(session.chapterBar, isTrue);
    session.setChapterBar(false);
    expect(prefs.chapterBar, isFalse);
    expect(session.chapterBar, isFalse);
    expect(heard, 1);
    session.setChapterBar(true);
    expect(prefs.chapterBar, isTrue);
    expect(heard, 2);
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

    test('a card\'s session, inactive as it is made, plays AAC; taken over, it goes on with AAC while the page slides '
        'in, then reopens on FLAC at the same second, quietly', () async {
      prefs.hiRes = true;
      final session = makeSession()..active = false;
      await controller.openVideo(bv, cid: p1);
      playing();
      expect(audios(), [aacId]);
      at(25);
      session.active = true;
      await settle();
      expect(audios(), [aacId], reason: 'no reload under the page sliding in');
      expect(session.hiResOn && session.hiResOffered, isTrue, reason: 'the button is pink over AAC until then');
      await slidIn();
      expect(audios(), [aacId, flacId]);
      expect(player.loaded!.startSeconds, closeTo(25, 1e-9));
      expect(player.loaded!.autoplay, isTrue);
      playing();
      await settle();
      expect(notes(session), isEmpty, reason: 'nobody asked');
      expect(logs.events.where((event) => event.msg == 'hi-res matched'), hasLength(1));
    });

    test('a card taken over while Hi-Res is off stays on AAC, and nothing reopens', () async {
      final session = makeSession()..active = false;
      await controller.openVideo(bv, cid: p1);
      playing();
      session.active = true;
      await slidIn();
      expect(audios(), [aacId]);
    });

    test('a page covered again while it slides in reopens nothing until it shows once more', () async {
      prefs.hiRes = true;
      final session = makeSession()..active = false;
      await controller.openVideo(bv, cid: p1);
      playing();
      session.active = true;
      final waiting = settleTimer()!;
      session.active = false;
      expect(waiting.isActive, isFalse);
      expect(settleTimer(), isNull);
      await settle();
      expect(audios(), [aacId]);
      session.active = true;
      await slidIn();
      expect(audios(), [aacId, flacId]);
    });

    test('a page shown again after the page above turned Hi-Res off goes back on AAC at the same second, once it '
        'has slid back', () async {
      prefs.hiRes = true;
      final session = makeSession();
      await controller.openVideo(bv, cid: p1);
      playing();
      at(40);
      session.active = false;
      prefs.hiRes = false;
      await settle();
      expect(audios(), [flacId], reason: 'nothing reopens while covered');
      session.active = true;
      await settle();
      expect(audios(), [flacId]);
      await slidIn();
      expect(audios(), [flacId, aacId]);
      expect(player.loaded!.startSeconds, closeTo(40, 1e-9));
      expect(controller.playingFlac, isFalse);
      expect(notes(session), isEmpty);
      expect(session.hiResOn, isFalse);
    });

    test('and back on FLAC when the page above turned it on', () async {
      final session = makeSession();
      await controller.openVideo(bv, cid: p1);
      playing();
      session.active = false;
      prefs.hiRes = true;
      session.active = true;
      await slidIn();
      expect(audios(), [aacId, flacId]);
      expect(notes(session), isEmpty);
    });

    test('大会员 known only after the open: the page reopens on FLAC at the same second as the account lands', () async {
      prefs.hiRes = true;
      final account = _Account(false);
      final session = makeSession(account: account);
      await controller.openVideo(bv, cid: p1);
      playing();
      at(18);
      expect(audios(), [aacId]);
      expect(session.hiResOffered, isFalse);
      var heard = 0;
      session.addListener(() => heard += 1);
      account.vip = true;
      await settle();
      expect(heard, greaterThan(0));
      expect(session.hiResOffered, isTrue);
      expect(audios(), [aacId, flacId]);
      expect(player.loaded!.startSeconds, closeTo(18, 1e-9));
      expect(notes(session), isEmpty);
    });

    test('the account landing on a covered page waits for it to show', () async {
      prefs.hiRes = true;
      final account = _Account(false);
      final session = makeSession(account: account);
      await controller.openVideo(bv, cid: p1);
      playing();
      session.active = false;
      account.vip = true;
      await settle();
      expect(audios(), [aacId]);
      session.active = true;
      await slidIn();
      expect(audios(), [aacId, flacId]);
    });

    test('the account turning out without 大会员 puts a FLAC stream back on AAC', () async {
      prefs.hiRes = true;
      final account = _Account(true);
      makeSession(account: account);
      await controller.openVideo(bv, cid: p1);
      playing();
      expect(audios(), [flacId]);
      account.vip = false;
      await settle();
      expect(audios(), [flacId, aacId]);
    });

    test('a refused FLAC track is not tried again by a show or an account change', () async {
      prefs.hiRes = true;
      final account = _Account(true);
      final session = makeSession(account: account);
      await controller.openVideo(bv, cid: p1);
      player.emit(const PlayerFailed('cannot decode', formatRejected: true));
      await settle();
      playing();
      await settle();
      expect(audios(), [flacId, aacId]);
      session.active = false;
      session.active = true;
      await slidIn();
      account.vip = true;
      await settle();
      expect(audios(), [flacId, aacId]);
      expect(notes(session), [failed]);
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
