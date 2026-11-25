import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/offline/fake_offline_library.dart';
import 'package:bilifast/offline/page/offline_playback.dart';
import 'package:bilifast/playback/codec_memory.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/playback/playback_setup.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player/playback_clock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player.dart';
import 'fakes.dart';

const bv = 'BV1GJ411x7h7';
const p1 = 137649199;
const p2 = 137649200;
const next = 'BV1Nx411c7mD';
const nextCid = 222;
const flacId = 30251;
const aacId = 30280;

/// Hi-Res 无损's FLAC track, beside the AAC list as the playurl answer has it.
String flacTrack({String tag = 'a'}) =>
    '{"id":$flacId,'
    '"baseUrl":"https://upos-sz-mirrorcos.bilivideo.com/a/$flacId.m4s?deadline=${Canned.deadline}&upsig=$tag",'
    '"backupUrl":["https://upos-sz-mirrorali.bilivideo.com/a/$flacId.m4s?deadline=${Canned.deadline}&upsig=$tag"],'
    '"bandwidth":1600000,"mimeType":"audio/mp4","codecs":"fLaC",'
    '"SegmentBase":{"Initialization":"0-1000","indexRange":"1001-1600"},"codecid":0}';

/// [Canned.playUrl] with a FLAC track, as 大会员 get it.
String playUrlWithFlac({String tag = 'a'}) =>
    Canned.playUrl(tag: tag)
        .replaceFirst('"audio":[', '"flac":{"display":true,"audio":${flacTrack(tag: tag)}},"audio":[');

VideoDetail nextDetail() => VideoDetail.fromJson({
  'bvid': next,
  'aid': 2,
  'title': '下一个',
  'owner': {'mid': 3, 'name': 'UP'},
  'pages': [
    {'cid': nextCid, 'page': 1, 'part': '', 'duration': 60},
  ],
});

const onePartView =
    '{"code":0,"data":{"bvid":"$bv","aid":1,"title":"单P","owner":{"mid":1,"name":"UP"},'
    '"pages":[{"cid":$p1,"page":1,"part":"","duration":712}]}}';

/// The controller's side of Hi-Res 无损 (274): the pick, the switch, the fallback to AAC, and the warms.
void main() {
  late CannedHttp http;
  late FakeEngine engine;
  late FakePlayer player;
  late FakeTimers timers;
  late ManualClock time;
  late CodecMemory memory;
  late MemorySink logs;
  late DateTime now;
  late List<PlaybackController> made;

  setUp(() {
    http = Canned.http()..routes[Canned.playUrlPath] = (200, playUrlWithFlac());
    engine = FakeEngine();
    player = FakePlayer();
    timers = FakeTimers();
    time = ManualClock(10000);
    memory = CodecMemory();
    logs = MemorySink();
    now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
    made = [];
  });

  tearDown(() {
    for (final controller in made) {
      controller.dispose();
    }
  });

  PlaybackController make({PlaybackMode mode = PlaybackMode.btr}) {
    final logger = Logger(session: 'test')..add(logs);
    final client = BiliClient(transport: http, cookies: CookieJar(Canned.cookies), now: () => now, logger: logger);
    final controller = PlaybackController(
      client: client,
      engine: engine,
      player: player,
      codecMemory: memory,
      mode: mode,
      clock: time.clock,
      now: () => now,
      startTimer: timers.start,
      logger: logger,
    );
    made.add(controller);
    return controller;
  }

  List<int> audios() => [for (final request in engine.prepared) request.choice.audio.id];
  int loads() => player.calls.where((call) => call.startsWith('load')).length;
  int playUrls() => http.to(Canned.playUrlPath).length;

  List<Map<String, Object?>> lines(String msg) => [
    for (final event in logs.events)
      if (event.msg == msg) {for (final MapEntry(:key, :value) in event.f.entries) key: value.toJson()},
  ];

  void at(double seconds) {
    time.advance(PlaybackClock.jumpSettleMs);
    player.emit(PositionChanged(seconds: seconds, hostMs: time.clock.nowMs(), rate: 1));
  }

  group('the offer', () {
    test('off by default: an answer with a FLAC track still plays AAC, and offers it', () async {
      final controller = make();
      await controller.openVideo(bv, cid: p1);
      expect(controller.hiRes, isFalse);
      expect(audios(), [aacId]);
      expect(controller.hiResOffered, isTrue);
      expect(controller.playingFlac, isFalse);
      expect(lines('choice').single['audioKind'], 'aac');
    });

    test(
      'an answer without a FLAC track offers nothing, and Hi-Res asked for plays AAC with nothing reopened',
      () async {
        http.routes[Canned.playUrlPath] = (200, Canned.playUrl());
        final controller = make();
        await controller.openVideo(bv, cid: p1);
        player.emit(const StatusChanged(PlayerStatus.playing));
        expect(controller.hiResOffered, isFalse);
        await controller.setHiRes(true);
        expect(controller.hiRes, isTrue);
        expect(engine.prepared, hasLength(1));
        expect(loads(), 1);
        await controller.openVideo(bv, cid: p2);
        expect(audios(), [aacId, aacId]);
      },
    );

    test('a cached part never offers it, and plays its own files with Hi-Res asked for', () async {
      final library = FakeOfflineLibrary.demo();
      final controller = make();
      await controller.setHiRes(true);
      await controller.openLocal(() async => localVideoOf((await library.playback(7003))!));
      await settle();
      expect(controller.isLocal, isTrue);
      expect(controller.hiResOffered, isFalse);
      expect(controller.playingFlac, isFalse);
      await controller.setHiRes(false);
      await controller.setHiRes(true);
      expect(loads(), 1, reason: 'a cached part has one audio track');
    });

    test('kept through a quality change of the same part, gone with another open until its answer lands', () async {
      final controller = make();
      await controller.openVideo(bv, cid: p1);
      final gate = http.gates[Canned.playUrlPath] = Completer<void>();
      final quality = controller.setQuality(80);
      await settle();
      expect(controller.hiResOffered, isTrue, reason: 'the button does not blink while the new answer is out');
      final opening = controller.openVideo(bv, cid: p2);
      expect(controller.hiResOffered, isFalse);
      gate.complete();
      await Future.wait([quality, opening]);
      expect(controller.hiResOffered, isTrue);
    });
  });

  group('the switch', () {
    test('on reopens at the same second, playing, on the FLAC track from the answer in hand; off goes back', () async {
      final controller = make();
      await controller.openVideo(bv, cid: p1);
      player.emit(const StatusChanged(PlayerStatus.playing));
      at(42);
      await controller.setHiRes(true);
      expect(audios(), [aacId, flacId]);
      expect(engine.prepared.last.startSeconds, closeTo(42, 1e-9));
      expect(engine.prepared.last.choice.video.codecid, VideoCodec.hevc.codecid, reason: 'the picture stays');
      expect(player.loaded!.startSeconds, closeTo(42, 1e-9));
      expect(player.loaded!.autoplay, isTrue);
      expect(engine.released, ['tok1']);
      expect(playUrls(), 1, reason: 'the answer in hand has both tracks');
      expect(controller.playingFlac, isTrue);
      expect(controller.hasPlayed, isFalse, reason: 'the reopened stream has its own first frame');
      expect(lines('hi-res').single, {'on': true});
      expect(lines('choice').last['audioKind'], 'flac');

      player.emit(const StatusChanged(PlayerStatus.playing));
      expect(controller.hasPlayed, isTrue);
      expect(lines('first frame').last['audioKind'], 'flac');
      at(50);
      await controller.setHiRes(false);
      expect(audios(), [aacId, flacId, aacId]);
      expect(player.loaded!.startSeconds, closeTo(50, 1e-9));
      expect(controller.playingFlac, isFalse);
      expect(playUrls(), 1);
    });

    test('a paused video stays paused through the switch', () async {
      final controller = make();
      await controller.openVideo(bv, cid: p1);
      player
        ..emit(const StatusChanged(PlayerStatus.playing))
        ..emit(const StatusChanged(PlayerStatus.paused));
      at(30);
      await controller.setHiRes(true);
      expect(audios().last, flacId);
      expect(player.loaded!.autoplay, isFalse);
      expect(player.loaded!.startSeconds, closeTo(30, 1e-9));
      expect(player.calls, isNot(contains('play')));
    });

    test('nothing reopens when the stream already has the audio asked for, or without reopen', () async {
      final controller = make();
      await controller.openVideo(bv, cid: p1);
      await controller.setHiRes(false);
      await controller.setHiRes(true, reopen: false);
      expect(engine.prepared, hasLength(1));
      expect(controller.hiRes, isTrue);
      expect(lines('hi-res'), [
        {'on': false},
      ], reason: 'only the user\'s switch is logged');
    });

    test('on while the answer is still out: the open picks FLAC', () async {
      final controller = make();
      final gate = http.gates[Canned.playUrlPath] = Completer<void>();
      final opening = controller.openVideo(bv, cid: p1);
      await settle();
      await controller.setHiRes(true);
      gate.complete();
      await opening;
      expect(audios(), [flacId]);
    });

    test('every open and part after it picks FLAC, and a quality change keeps it', () async {
      final controller = make();
      await controller.setHiRes(true, reopen: false);
      await controller.openVideo(bv, cid: p1);
      await controller.openVideo(bv, cid: p2);
      await controller.setQuality(80);
      expect(audios(), [flacId, flacId, flacId]);
      expect(engine.prepared.last.choice.video.id, 80);
    });

    test('the stream addresses of the FLAC track are renewed from the answer\'s FLAC track', () async {
      final controller = make();
      await controller.setHiRes(true, reopen: false);
      await controller.openVideo(bv, cid: p1);
      final refresh = timers.activeWith(const Duration(seconds: 700));
      http.routes[Canned.playUrlPath] = (200, playUrlWithFlac(tag: 'fresh'));
      refresh!.fire();
      await settle();
      final audio = engine.replaced.where((entry) => entry.track == TrackKind.audio).single;
      expect(audio.primary, allOf(contains('$flacId.m4s'), contains('upsig=fresh')));
      expect(audio.backups.single, contains('mirrorali'));
      expect(controller.playingFlac, isTrue);
      expect(lines('url refresh found no matching streams'), isEmpty);
    });

    for (final mode in [PlaybackMode.btr, PlaybackMode.direct]) {
      test('${mode.name}: a refresh whose answer has no FLAC track reopens on its AAC at the same second, with a renewed '
          'schedule; the FLAC item let go meanwhile blames no codec', () async {
        final controller = make(mode: mode);
        final refusals = <void>[];
        controller.hiResRefusals.listen(refusals.add);
        await controller.setHiRes(true, reopen: false);
        await controller.openVideo(bv, cid: p1);
        player.emit(const StatusChanged(PlayerStatus.playing));
        at(300);
        final refresh = timers.activeWith(const Duration(seconds: 700))!;
        http.routes[Canned.playUrlPath] = (200, Canned.playUrl(tag: 'fresh'));
        final gate = engine.prepareGate = Completer<void>();
        refresh.fire();
        await settle();
        expect(lines('flac gone on refresh').single, containsPair('at', 300));
        expect(controller.playingFlac, isFalse);
        expect(controller.hiResOffered, isFalse);
        player.emit(const PlayerFailed('cannot decode', formatRejected: true));
        await settle();
        engine.prepareGate = null;
        gate.complete();
        await settle();
        expect(audios(), [flacId, aacId]);
        expect(engine.prepared.last.startSeconds, closeTo(300, 1e-9));
        expect(engine.prepared.last.choice.audio.baseURL, contains('upsig=fresh'));
        expect(engine.prepared.last.choice.video.codecid, VideoCodec.hevc.codecid);
        expect(memory.failedKinds, isEmpty);
        expect(engine.replaced, isEmpty, reason: 'nothing renews the FLAC addresses');
        expect(engine.released, contains('tok1'));
        expect(player.loaded!.autoplay, isTrue);
        expect(playUrls(), 2);
        final renewed = timers.activeWith(const Duration(seconds: 700));
        expect(renewed, isNotNull);
        expect(renewed, isNot(same(refresh)));
        expect(refusals, isEmpty);
        expect(lines('url refresh found no matching streams'), isEmpty);
      });
    }

    test('matchHiRes reopens at the same second only when the audio differs, and keeps a refused track refused', () async {
      final controller = make();
      await controller.openVideo(bv, cid: p1);
      player.emit(const StatusChanged(PlayerStatus.playing));
      at(20);
      await controller.matchHiRes(false);
      expect(engine.prepared, hasLength(1));
      await controller.matchHiRes(true);
      expect(audios(), [aacId, flacId]);
      expect(player.loaded!.startSeconds, closeTo(20, 1e-9));
      expect(lines('hi-res matched').single, {'on': true});
      expect(lines('hi-res'), isEmpty, reason: 'not the user\'s switch');

      player.emit(const PlayerFailed('cannot decode', formatRejected: true));
      await settle();
      expect(audios().last, aacId);
      await controller.matchHiRes(true);
      expect(audios(), hasLength(3), reason: 'the refused track is not tried again');
    });
  });

  group('the playurl line', () {
    const unreadable = '"flac":{"display":true,"audio":{"id":$flacId,"codecs":"fLaC"}},';
    for (final (answer, flac) in [
      (playUrlWithFlac(), 'ok'),
      (Canned.playUrl(), 'none'),
      (Canned.playUrl().replaceFirst('"audio":[', '$unreadable"audio":['), 'malformed'),
    ]) {
      test('says flac $flac, with no address', () async {
        http.routes[Canned.playUrlPath] = (200, answer);
        final controller = make();
        await controller.openVideo(bv, cid: p1);
        expect(lines('playurl').single, containsPair('flac', flac));
        expect(controller.hiResOffered, flac == 'ok');
        final text = logs.events.map((event) => event.encode()).join('\n');
        expect(text, isNot(contains('upsig')));
        expect(text, isNot(contains('$flacId.m4s')));
      });
    }
  });

  group('a refused FLAC track', () {
    test(
      'the player\'s refusal goes on with AAC where it was, once, blaming no codec, and is told once AAC plays; the '
      'next part tries again',
      () async {
        final controller = make();
        final refusals = <void>[];
        controller.hiResRefusals.listen(refusals.add);
        await controller.setHiRes(true, reopen: false);
        await controller.openVideo(bv, cid: p1);
        at(12);
        player.emit(const PlayerFailed('cannot decode', formatRejected: true));
        await settle();
        expect(audios(), [flacId, aacId]);
        expect(engine.prepared.map((request) => request.choice.video.codecid), [12, 12]);
        expect(memory.failedKinds, isEmpty);
        expect(player.loaded!.startSeconds, closeTo(12, 1e-9));
        expect(refusals, isEmpty, reason: 'an AAC load failing the same way would make it no refusal');
        expect(controller.hiRes, isTrue, reason: 'the choice stays');
        expect(controller.playingFlac, isFalse);
        expect(lines('flac refused, playing aac').single, containsPair('by', 'player'));
        expect(lines('flac refused, playing aac').single, containsPair('how', 'format'));

        player.emit(const StatusChanged(PlayerStatus.playing));
        await settle();
        expect(refusals, hasLength(1));

        player.emit(const PlayerFailed('cannot decode', formatRejected: true));
        await settle();
        expect(
          engine.prepared.last.choice.video.codecid,
          VideoCodec.avc.codecid,
          reason: 'with AAC playing, a refusal is the codec\'s again',
        );
        expect(audios().last, aacId);
        expect(refusals, hasLength(1));

        await controller.openVideo(bv, cid: p2);
        expect(audios().last, flacId);
      },
    );

    test('an unexplained failure before it played is the FLAC track\'s; after, it takes the usual way', () async {
      final controller = make(mode: PlaybackMode.direct);
      await controller.setHiRes(true, reopen: false);
      await controller.openVideo(bv, cid: p1);
      player.emit(const PlayerFailed('unknown', domain: 'AVFoundationErrorDomain', code: -11800));
      await settle();
      expect(audios(), [flacId, aacId]);

      await controller.openVideo(bv, cid: p2);
      player.emit(const StatusChanged(PlayerStatus.playing));
      player.emit(const PlayerFailed('unknown', domain: 'AVFoundationErrorDomain', code: -11800));
      await settle();
      expect(audios().sublist(2), [flacId, flacId], reason: 'fresh addresses first, as for any stream');
    });

    test('a FLAC track the engine cannot index goes on with AAC in BTR before direct mode is tried', () async {
      engine.prepareErrors.add(const PlaybackError(PlaybackErrorKind.noSidx));
      final controller = make();
      final refusals = <void>[];
      controller.hiResRefusals.listen(refusals.add);
      await controller.setHiRes(true, reopen: false);
      // A link: no warm of its own beside the view to take the error first.
      await controller.open(bv);
      await settle();
      expect(audios(), [flacId, aacId]);
      expect(engine.prepared.map((request) => request.mode), [PlaybackMode.btr, PlaybackMode.btr]);
      expect(controller.fellBack, isFalse);
      expect(controller.phase, isNot(PlaybackPhase.failed));
      expect(lines('flac refused, playing aac').single, containsPair('by', 'engine'));
      player.emit(const StatusChanged(PlayerStatus.playing));
      await settle();
      expect(refusals, hasLength(1));
    });

    test('after a refusal, a quality or codec change and a replay keep AAC, and nothing is refused again', () async {
      final controller = make();
      final refusals = <void>[];
      controller.hiResRefusals.listen(refusals.add);
      await controller.setHiRes(true, reopen: false);
      await controller.openVideo(bv, cid: p1);
      player.emit(const PlayerFailed('cannot decode', formatRejected: true));
      await settle();
      player.emit(const StatusChanged(PlayerStatus.playing));
      await controller.setQuality(80);
      player.emit(const StatusChanged(PlayerStatus.playing));
      await controller.setCodec(VideoCodec.av1);
      player.emit(const StatusChanged(PlayerStatus.playing));
      await controller.replay();
      player.emit(const StatusChanged(PlayerStatus.playing));
      await settle();
      expect(audios(), [flacId, aacId, aacId, aacId, aacId]);
      expect(controller.playingFlac, isFalse);
      expect(controller.hiRes, isTrue);
      expect(refusals, hasLength(1));
      expect(lines('flac refused, playing aac'), hasLength(1));
    });

    group('an AAC load failing as the FLAC one did, before it plays, withdraws the refusal', () {
      late PlaybackController controller;
      late List<void> refusals;

      Future<void> open({PlaybackMode mode = PlaybackMode.btr, bool link = false}) async {
        controller = make(mode: mode);
        refusals = [];
        controller.hiResRefusals.listen(refusals.add);
        await controller.setHiRes(true, reopen: false);
        if (link) {
          await controller.open(bv);
        } else {
          await controller.openVideo(bv, cid: p1);
        }
        await settle();
      }

      test('a format failure: the video\'s codec takes the blame, FLAC is picked again, nothing is said', () async {
        await open();
        player.emit(const PlayerFailed('cannot decode', formatRejected: true));
        await settle();
        expect(audios(), [flacId, aacId]);
        player.emit(const PlayerFailed('cannot decode', formatRejected: true));
        await settle();
        expect(memory.failedKinds, {'hevc'}, reason: 'as it was before Hi-Res');
        expect(audios(), [flacId, aacId, flacId]);
        expect(engine.prepared.last.choice.video.codecid, VideoCodec.avc.codecid);
        expect(controller.playingFlac, isTrue);
        expect(lines('flac refusal withdrawn').single, containsPair('by', 'player'));
        player.emit(const StatusChanged(PlayerStatus.playing));
        await settle();
        expect(refusals, isEmpty);
      });

      test('an unexplained failure: BTR takes the blame, and direct mode plays FLAC', () async {
        await open();
        player.emit(const PlayerFailed('unknown', domain: 'AVFoundationErrorDomain', code: -11800));
        await settle();
        player.emit(const PlayerFailed('unknown', domain: 'AVFoundationErrorDomain', code: -11800));
        await settle();
        expect(audios(), [flacId, aacId, flacId]);
        expect(engine.prepared.map((request) => request.mode), [PlaybackMode.btr, PlaybackMode.btr, PlaybackMode.direct]);
        expect(controller.fellBack, isTrue);
        expect(memory.failedKinds, isEmpty);
        player.emit(const StatusChanged(PlayerStatus.playing));
        await settle();
        expect(refusals, isEmpty);
      });

      test('an engine that can\'t index the AAC load either: BTR takes the blame, and direct mode plays FLAC', () async {
        engine.prepareErrors.addAll(const [
          PlaybackError(PlaybackErrorKind.noSidx),
          PlaybackError(PlaybackErrorKind.noSidx),
        ]);
        await open(link: true);
        expect(audios(), [flacId, aacId, flacId]);
        expect(engine.prepared.map((request) => request.mode), [PlaybackMode.btr, PlaybackMode.btr, PlaybackMode.direct]);
        expect(controller.fellBack, isTrue);
        expect(controller.playingFlac, isTrue);
        expect(controller.phase, isNot(PlaybackPhase.failed));
        expect(lines('flac refusal withdrawn').single, containsPair('by', 'engine'));
        player.emit(const StatusChanged(PlayerStatus.playing));
        await settle();
        expect(refusals, isEmpty);
      });

      test('but a failure of another kind leaves it standing, and it is told once AAC plays', () async {
        await open();
        player.emit(const PlayerFailed('cannot decode', formatRejected: true));
        await settle();
        player.emit(const PlayerFailed('offline', domain: 'NSURLErrorDomain', code: -1009));
        await settle();
        expect(audios(), [flacId, aacId, aacId]);
        expect(controller.fellBack, isTrue);
        expect(lines('flac refusal withdrawn'), isEmpty);
        player.emit(const StatusChanged(PlayerStatus.playing));
        await settle();
        expect(refusals, hasLength(1));
      });
    });

    test('asked for again, FLAC is tried again', () async {
      final controller = make();
      await controller.setHiRes(true, reopen: false);
      await controller.openVideo(bv, cid: p1);
      player.emit(const PlayerFailed('cannot decode', formatRejected: true));
      await settle();
      await controller.setHiRes(false);
      expect(audios(), [flacId, aacId], reason: 'already AAC: nothing to reopen');
      await controller.setHiRes(true);
      expect(audios(), [flacId, aacId, flacId]);
    });

    test('logs carry no address', () async {
      final controller = make();
      await controller.setHiRes(true, reopen: false);
      await controller.openVideo(bv, cid: p1);
      player.emit(const PlayerFailed('cannot decode', formatRejected: true));
      await settle();
      await controller.setHiRes(false);
      await controller.setHiRes(true);
      final text = logs.events.map((event) => event.encode()).join('\n');
      expect(text, isNot(contains('upsig')));
      expect(text, isNot(contains('$flacId.m4s')));
    });
  });

  group('warms', () {
    Future<PlaybackController> withPlaying() async {
      now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 3 * 3600) * 1000);
      final controller = make();
      await controller.openVideo(bv, cid: p1);
      player.emit(const StatusChanged(PlayerStatus.playing));
      return controller;
    }

    test('an AAC warm is let go when Hi-Res is turned on, and its video opens on FLAC', () async {
      final controller = await withPlaying();
      await controller.warm(next, cid: nextCid, detail: nextDetail());
      expect(engine.warmed.single.choice.audio.id, aacId);
      await controller.setHiRes(true, reopen: false);
      expect(engine.released, contains('tok2'), reason: 'the warm source goes');
      await controller.openVideo(next, cid: nextCid, detail: nextDetail());
      expect(lines('load').last['warm'], 'miss hiRes');
      expect(engine.prepared.last.choice.audio.id, flacId);
      expect(engine.promoted, isEmpty);
    });

    test('a FLAC warm plays its FLAC open, and a warm asked again under the same choice is kept', () async {
      final controller = await withPlaying();
      await controller.setHiRes(true, reopen: false);
      await controller.warm(next, cid: nextCid, detail: nextDetail());
      await controller.warm(next, cid: nextCid, detail: nextDetail());
      expect(engine.warmed, hasLength(1));
      expect(engine.warmed.single.choice.audio.id, flacId);
      await controller.openVideo(next, cid: nextCid);
      expect(lines('load').last['warm'], 'hit');
      expect(controller.playingFlac, isTrue);
    });

    test('the open\'s own warm picks as the answer lands, so Hi-Res set just after the open starts is kept', () async {
      http.routes[Canned.signedViewPath] = (200, onePartView);
      final view = http.gates[Canned.signedViewPath] = Completer<void>();
      final controller = make();
      final opening = controller.openVideo(bv, cidHint: p1);
      unawaited(controller.setHiRes(true, reopen: false));
      await settle();
      view.complete();
      await opening;
      expect(audios(), [flacId]);
      expect(lines('load').last['parallel'], 'kept');
    });

    test('the open\'s own warm picked AAC before Hi-Res came: dropped, its answer still stands in', () async {
      http.routes[Canned.signedViewPath] = (200, onePartView);
      final view = http.gates[Canned.signedViewPath] = Completer<void>();
      final controller = make();
      final opening = controller.openVideo(bv, cidHint: p1);
      await settle();
      expect(audios(), [aacId], reason: 'the warm prepared beside the view');
      await controller.setHiRes(true, reopen: false);
      view.complete();
      await opening;
      expect(audios(), [aacId, flacId]);
      expect(lines('load').last['parallel'], 'dropped hiRes');
      expect(playUrls(), 1);
      expect(engine.released, ['tok1']);
    });
  });

  test('the engine prefetches as far ahead of FLAC as of the video, and AAC stays at its floor', () {
    const config = appRipperConfig;
    // 24-bit/96 kHz FLAC runs about 4 Mbps.
    const flacBytesPerSecond = 4e6 / 8;
    final reach = config.prefetchAheadSeconds * RipperConfig.maxPrefetchRate * 1.25;
    expect(config.prefetchAudioMaxBytes!, greaterThanOrEqualTo(reach * flacBytesPerSecond));
    const aacBytesPerSecond = 320000 / 8;
    expect(reach * aacBytesPerSecond, lessThan(config.prefetchAudioBytes));
  });
}
