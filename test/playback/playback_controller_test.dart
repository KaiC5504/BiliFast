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

const bv = 'BV1GJ411x7h7';

void main() {
  late CannedHttp http;
  late FakeEngine engine;
  late FakePlayer player;
  late FakeTimers timers;
  late ManualClock time;
  late CodecMemory memory;
  late MemorySink logs;
  late DateTime now;

  setUp(() {
    http = Canned.http();
    engine = FakeEngine();
    player = FakePlayer();
    timers = FakeTimers();
    time = ManualClock(10000);
    memory = CodecMemory();
    logs = MemorySink();
    now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
  });

  PlaybackController make({PlaybackMode mode = PlaybackMode.btr}) {
    final logger = Logger(session: 'test')..add(logs);
    final client = BiliClient(transport: http, cookies: CookieJar(Canned.cookies), now: () => now, logger: logger);
    return PlaybackController(
      client: client,
      engine: engine,
      player: player,
      codecMemory: memory,
      mode: mode,
      transportName: 'dart:io',
      clock: time.clock,
      now: () => now,
      startTimer: timers.start,
      logger: logger,
    );
  }

  int loads() => player.calls.where((call) => call.startsWith('load')).length;

  void emitPosition(double seconds) =>
      player.emit(PositionChanged(seconds: seconds, hostMs: time.clock.nowMs(), rate: 1));

  /// A reading far from where the load started counts only once the clock's settle time has passed.
  void emitAfterSettle(double seconds) {
    time.advance(PlaybackClock.jumpSettleMs);
    emitPosition(seconds);
  }

  test('a BV link plays: view, playurl, prepare, then load with the master URL', () async {
    final controller = make();
    await controller.open('看看 https://www.bilibili.com/video/$bv');

    expect(http.paths.where((path) => path != Canned.navPath), [Canned.signedViewPath, Canned.playUrlPath]);
    final query = http.to(Canned.playUrlPath).single.url.queryParameters;
    expect(query['bvid'], bv);
    expect(query['cid'], '137649199');
    expect(query['qn'], '120');

    final request = engine.prepared.single;
    expect(request.mode, PlaybackMode.btr);
    expect(request.choice.video.id, 120);
    expect(request.choice.video.codecid, VideoCodec.hevc.codecid);
    expect(request.choice.audio.id, 30280);
    expect(request.mediaHeaders, BiliClient.mediaHeaders);

    expect(engine.ensureCalls, 1, reason: 'the local server is probed before every load');
    expect(player.loaded!.master, FakeEngine.masterOf('tok1'));
    expect(player.loaded!.headers, isEmpty);
    expect(player.loaded!.autoplay, isTrue);
    expect(player.loaded!.startSeconds, 0);
    expect(controller.video?.title, '测试视频');
    expect(controller.qualities.map((option) => option.id), [126, 125, 120, 80]);
    expect(controller.stats.value.stream, '4K 超高清 · HEVC · 12.0 Mbps');
    expect(controller.stats.value.mode, PlaybackMode.btr);
    expect(controller.stats.value.transport, 'dart:io');
    controller.dispose();
  });

  test('direct mode hands the player the media headers', () async {
    final controller = make(mode: PlaybackMode.direct);
    await controller.open(bv);
    expect(engine.prepared.single.mode, PlaybackMode.direct);
    expect(player.loaded!.headers, BiliClient.mediaHeaders);
    expect(controller.stats.value.mode, PlaybackMode.direct);
    controller.dispose();
  });

  test('a link without a video fails before any request', () async {
    final controller = make();
    await controller.open('hello');
    expect(controller.phase, PlaybackPhase.failed);
    expect(controller.error, BiliError.invalidLink.userMessage);
    expect(http.requests, isEmpty);
    controller.dispose();
  });

  test('an unplayable codec moves on to the next codec once, without remembering it', () async {
    engine.prepareErrors.add(const PlaybackError(PlaybackErrorKind.codecUnplayable, 'hev1 without VPS'));
    final controller = make();
    await controller.open(bv);

    expect(engine.prepared.map((request) => request.choice.video.codecid), [12, 7]);
    expect(loads(), 1);
    expect(player.loaded!.master, FakeEngine.masterOf('tok1'));
    expect(memory.failedKinds, isEmpty);
    expect(http.to(Canned.playUrlPath), hasLength(1), reason: 'the next codec comes from the answer in hand');
    expect(controller.phase, PlaybackPhase.loading);
    expect(controller.error, isNull);
    controller.dispose();
  });

  test('a format refusal in BTR mode remembers the codec and tries the next one where it was', () async {
    final controller = make();
    await controller.open(bv);
    emitAfterSettle(42);
    player.emit(const PlayerFailed('cannot decode', formatRejected: true));
    await settle();

    expect(memory.failedKinds, {'hevc'});
    expect(engine.prepared.map((request) => request.choice.video.codecid), [12, 7]);
    expect(engine.released, contains('tok1'));
    expect(loads(), 2);
    expect(player.loaded!.master, FakeEngine.masterOf('tok2'));
    expect(player.loaded!.startSeconds, closeTo(42, 1e-9));
    expect(http.to(Canned.playUrlPath), hasLength(1));
    controller.dispose();
  });

  test('direct mode refuses a hev1 label that holds hev1 and chooses again without it', () async {
    engine.sourceEntry = 'hev1';
    final controller = make(mode: PlaybackMode.direct);
    await controller.open(bv);
    expect(engine.prepared.map((request) => request.choice.video.codecid), [12, 7]);
    expect(engine.released, ['tok1']);
    expect(memory.hev1LabelsHoldHEV1, isTrue);
    expect(loads(), 1);
    expect(player.loaded!.master, FakeEngine.masterOf('tok2'));
    expect(http.to(Canned.playUrlPath), hasLength(1));
    final label = logs.events.firstWhere((event) => event.msg == 'hev1 label');
    expect(label.f['entry'], const LogString('hev1'));
    controller.dispose();
  });

  test('a hev1 label holding hvc1 plays in direct mode', () async {
    engine.sourceEntry = 'hvc1';
    final controller = make(mode: PlaybackMode.direct);
    await controller.open(bv);
    expect(engine.prepared.single.choice.video.codecid, 12);
    expect(memory.hev1LabelsHoldHEV1, isFalse);
    expect(logs.events.firstWhere((event) => event.msg == 'hev1 label').f['entry'], const LogString('hvc1'));
    controller.dispose();
  });

  test('once hev1 labels proved to hold hev1, direct mode skips them before fetching anything', () async {
    memory.noteHEV1Entry();
    final controller = make(mode: PlaybackMode.direct);
    await controller.open(bv);
    expect(engine.prepared.single.choice.video.codecid, 7);
    controller.dispose();
  });

  test('BTR plays a renamed hev1 entry, and a switch to direct then picks another codec', () async {
    engine
      ..sourceEntry = 'hev1'
      ..rewroteHEV1 = true;
    final controller = make();
    await controller.open(bv);
    expect(engine.prepared.single.choice.video.codecid, 12);
    expect(memory.hev1LabelsHoldHEV1, isTrue);

    await controller.setMode(PlaybackMode.direct);
    expect(engine.prepared.map((request) => (request.mode, request.choice.video.codecid)),
        [(PlaybackMode.btr, 12), (PlaybackMode.direct, 7)]);
    expect(http.to(Canned.playUrlPath), hasLength(1));
    controller.dispose();
  });

  test('a format refusal after the load played only skips the codec for this playback', () async {
    final controller = make();
    await controller.open(bv);
    player.emit(const StatusChanged(PlayerStatus.playing));
    player.emit(const PlayerFailed('decode failed after background', formatRejected: true));
    await settle();
    expect(memory.failedKinds, isEmpty);
    expect(engine.prepared.last.choice.video.codecid, 7);
    controller.dispose();
  });

  test('BTR that cannot start goes on in direct mode', () async {
    engine.prepareErrors.add(const PlaybackError(PlaybackErrorKind.noSource));
    final controller = make();
    await controller.open(bv);
    expect(engine.prepared.map((request) => request.mode), [PlaybackMode.btr, PlaybackMode.direct]);
    expect(controller.fellBack, isTrue);
    expect(controller.modeLabel, '直连（回退）');
    expect(player.loaded!.headers, BiliClient.mediaHeaders);
    controller.dispose();
  });

  test('switching modes prepares the same streams again at the current position', () async {
    final controller = make();
    await controller.open(bv);
    player.emit(const StatusChanged(PlayerStatus.playing));
    emitAfterSettle(20);
    await controller.setMode(PlaybackMode.direct);

    expect(engine.prepared.map((request) => request.mode), [PlaybackMode.btr, PlaybackMode.direct]);
    expect(engine.prepared.last.choice, engine.prepared.first.choice);
    expect(http.to(Canned.playUrlPath), hasLength(1), reason: 'no new playurl for a mode switch');
    expect(engine.released, ['tok1']);
    expect(player.loaded!.startSeconds, closeTo(20, 1e-9));
    expect(player.loaded!.headers, BiliClient.mediaHeaders);
    expect(player.loaded!.autoplay, isTrue);
    controller.dispose();
  });

  test('a user pause survives a mode switch', () async {
    final controller = make();
    await controller.open(bv);
    player.emit(const StatusChanged(PlayerStatus.playing));
    player.emit(const StatusChanged(PlayerStatus.paused));
    await controller.setMode(PlaybackMode.direct);
    expect(player.loaded!.autoplay, isFalse);
    controller.dispose();
  });

  test('the URL refresh is scheduled 300 s before the deadline and swaps the engine URLs in BTR', () async {
    final controller = make();
    await controller.open(bv);
    final refresh = timers.activeWith(const Duration(seconds: 700));
    expect(refresh, isNotNull, reason: 'deadline 1000 s away, refreshed 300 s before it');

    http.routes[Canned.playUrlPath] = (200, Canned.playUrl(tag: 'fresh'));
    refresh!.fire();
    await settle();

    expect(http.to(Canned.playUrlPath), hasLength(2));
    expect(engine.replaced.map((entry) => (entry.token, entry.track)),
        [('tok1', TrackKind.video), ('tok1', TrackKind.audio)]);
    expect(engine.replaced.first.primary, contains('upsig=fresh'));
    expect(engine.replaced.first.backups.single, contains('mirrorali'));
    expect(loads(), 1, reason: 'BTR keeps playing on new URLs');
    expect(timers.activeWith(const Duration(seconds: 700)), isNotNull, reason: 'the next refresh is scheduled');
    controller.dispose();
  });

  test('direct mode reloads at the current position when its URLs are refreshed', () async {
    final controller = make(mode: PlaybackMode.direct);
    await controller.open(bv);
    player.emit(const StatusChanged(PlayerStatus.playing));
    emitAfterSettle(75);
    http.routes[Canned.playUrlPath] = (200, Canned.playUrl(tag: 'fresh'));
    timers.activeWith(const Duration(seconds: 700))!.fire();
    await settle();

    expect(engine.replaced, isEmpty);
    expect(engine.prepared, hasLength(2));
    expect(engine.prepared.last.choice.video.baseURL, contains('upsig=fresh'));
    expect(player.loaded!.startSeconds, closeTo(75, 1e-9));
    expect(engine.released, ['tok1']);
    controller.dispose();
  });

  test('a refresh that fails is tried again in 30 s', () async {
    final controller = make();
    await controller.open(bv);
    http.routes[Canned.playUrlPath] = (500, '');
    timers.activeWith(const Duration(seconds: 700))!.fire();
    await settle();
    expect(timers.activeWith(const Duration(seconds: 30)), isNotNull);
    controller.dispose();
  });

  test('back in the foreground, a restarted local server means preparing again where it was', () async {
    final controller = make();
    await controller.open(bv);
    player.emit(const StatusChanged(PlayerStatus.playing));
    emitAfterSettle(30);

    await controller.appResumed();
    expect(engine.prepared, hasLength(1), reason: 'the server still answered');

    engine.restartOnEnsure = true;
    await controller.appResumed();
    expect(engine.prepared, hasLength(2));
    expect(player.loaded!.master, FakeEngine.masterOf('tok2'));
    expect(player.loaded!.startSeconds, closeTo(30, 1e-9));
    expect(http.to(Canned.playUrlPath), hasLength(1));
    controller.dispose();
  });

  test('a wait after the first frame counts as a stall 0.75 s later, unless a seek explains it', () async {
    final controller = make();
    await controller.open(bv);
    player.emit(const StatusChanged(PlayerStatus.buffering));
    expect(timers.active.where((timer) => timer.delay == const Duration(milliseconds: 750)), isEmpty,
        reason: 'waiting before the first frame is startup');

    player.emit(const StatusChanged(PlayerStatus.playing));
    player.emit(const StatusChanged(PlayerStatus.buffering));
    time.advance(750);
    timers.activeWith(const Duration(milliseconds: 750))!.fire();
    expect(controller.stats.value.stalls, 1);

    player.emit(const StatusChanged(PlayerStatus.playing));
    player.emit(const StatusChanged(PlayerStatus.buffering));
    time.advance(300);
    controller.userSeeked(100);
    timers.activeWith(const Duration(milliseconds: 750))!.fire();
    expect(controller.stats.value.stalls, 1, reason: 'the jump came 0.3 s after the wait');
    controller.dispose();
  });

  test('first frame and seek recovery times reach the overlay', () async {
    final controller = make();
    await controller.open(bv);
    time.advance(1234);
    player.emit(const StatusChanged(PlayerStatus.playing));
    expect(controller.stats.value.firstFrameMs, 1234);

    controller.userSeeked(60);
    player.emit(const StatusChanged(PlayerStatus.buffering));
    expect(timers.active.where((timer) => timer.delay == const Duration(milliseconds: 750)), isEmpty,
        reason: 'the wait of a timed seek is not a stall');
    time.advance(400);
    player.emit(const StatusChanged(PlayerStatus.playing));
    expect(controller.stats.value.lastSeekMs, 400);
    expect(controller.stats.value.worstSeekMs, 400);
    expect(controller.stats.value.stalls, 0);

    controller.userSeeked(300);
    time.advance(1500);
    player.emit(const StatusChanged(PlayerStatus.playing));
    expect(controller.stats.value.lastSeekMs, 1500);
    expect(controller.stats.value.worstSeekMs, 1500);
    expect(controller.stats.value.stalls, 1, reason: 'a seek slower than a second is lag');
    controller.dispose();
  });

  test('a seek inside the buffer is timed from the playhead', () async {
    final controller = make();
    await controller.open(bv);
    player.emit(const StatusChanged(PlayerStatus.playing));
    controller.userSeeked(100);
    time.advance(500);
    emitPosition(100.25);
    expect(controller.stats.value.lastSeekMs, closeTo(250, 1e-9));
    controller.dispose();
  });

  test('a seek while paused is not timed', () async {
    final controller = make();
    await controller.open(bv);
    player.emit(const StatusChanged(PlayerStatus.playing));
    player.emit(const StatusChanged(PlayerStatus.paused));
    controller.userSeeked(100);
    time.advance(5000);
    player.emit(const StatusChanged(PlayerStatus.playing));
    expect(controller.stats.value.lastSeekMs, isNull);
    controller.dispose();
  });

  test('engine stats reach the overlay in BTR mode', () async {
    final controller = make();
    await controller.open(bv);
    engine.statsController.add(const EngineSnapshot(concurrency: 8, downloadBps: 5e6, transport: 'URLSession'));
    expect(controller.stats.value.engine?.concurrency, 8);
    expect(controller.stats.value.downloadBps, 5e6);
    expect(controller.stats.value.transport, 'URLSession');

    await controller.setMode(PlaybackMode.direct);
    expect(controller.stats.value.engine, isNull);
    expect(controller.stats.value.downloadBps, 0);
    controller.dispose();
  });

  test('picture in picture starts by itself once playing, set once', () async {
    final controller = make();
    await controller.open(bv);
    player.emit(const StatusChanged(PlayerStatus.playing));
    player.emit(const StatusChanged(PlayerStatus.paused));
    player.emit(const StatusChanged(PlayerStatus.playing));
    await settle();
    expect(player.calls.where((call) => call == 'pip auto true'), hasLength(1));
    controller.dispose();
  });

  test('the playhead fetches the danmaku segment of the playing part', () async {
    final controller = make();
    await controller.open(bv);
    player.emit(const StatusChanged(PlayerStatus.playing));
    emitPosition(1);
    await controller.danmaku.settle();
    final request = http.to(Canned.segmentPath).single;
    expect(request.url.queryParameters['oid'], '137649199');
    expect(request.url.queryParameters['segment_index'], '1');
    expect(controller.danmaku.timeline, isNotNull);
    controller.dispose();
  });

  test('closing releases the playback and disposes the player and the engine', () async {
    final controller = make();
    await controller.open(bv);
    controller.dispose();
    await settle();
    expect(engine.released, ['tok1']);
    expect(player.disposed, isTrue);
    expect(engine.disposed, isTrue);
  });

  test('opening another video releases the first', () async {
    final controller = make();
    await controller.open(bv);
    await controller.open('BV1AB411c7mD');
    expect(engine.released, ['tok1']);
    expect(player.loaded!.master, FakeEngine.masterOf('tok2'));
    controller.dispose();
  });

  test('logs never carry a signed URL', () async {
    final controller = make();
    await controller.open(bv);
    player.emit(const PlayerFailed('cannot decode', formatRejected: true));
    await settle();
    controller.dispose();
    final text = logs.events.map((event) => event.encode()).join('\n');
    expect(text, isNot(contains('upsig')));
    expect(text, contains('playurl'));
  });

  test('a failure from the released item does not take over the next load', () async {
    final controller = make();
    await controller.open(bv);
    player.emit(const StatusChanged(PlayerStatus.playing));
    final gate = Completer<void>();
    engine.prepareGate = gate;
    final switching = controller.setQuality(80);
    await settle();
    expect(engine.released, ['tok1']);
    expect(engine.prepared, hasLength(2), reason: 'the new prepare is waiting');

    player.emit(const PlayerFailed('connection lost', domain: 'NSURLErrorDomain', code: -1005));
    gate.complete();
    await switching;
    await settle();
    expect(engine.prepared.map((request) => request.mode), [PlaybackMode.btr, PlaybackMode.btr]);
    expect(controller.fellBack, isFalse);
    expect(player.loaded!.master, FakeEngine.masterOf('tok2'));

    player.emit(const PlayerFailed('connection lost', domain: 'NSURLErrorDomain', code: -1005));
    await settle();
    expect(controller.fellBack, isTrue, reason: 'once the new item loaded its failures count again');
    controller.dispose();
  });

  test('buffering that ends within 0.75 s is not a stall; one that lasts is counted once', () async {
    final controller = make();
    await controller.open(bv);
    player.emit(const StatusChanged(PlayerStatus.playing));

    player.emit(const StatusChanged(PlayerStatus.buffering));
    time.advance(300);
    player.emit(const StatusChanged(PlayerStatus.playing));
    timers.activeWith(const Duration(milliseconds: 750))!.fire();
    expect(controller.stats.value.stalls, 0);

    player.emit(const StatusChanged(PlayerStatus.buffering));
    time.advance(800);
    timers.activeWith(const Duration(milliseconds: 750))!.fire();
    player.emit(const StatusChanged(PlayerStatus.playing));
    expect(controller.stats.value.stalls, 1);
    controller.dispose();
  });

  test('refreshed URLs replace the streams and qualities that another codec is chosen from', () async {
    final controller = make();
    await controller.open(bv);
    http.routes[Canned.playUrlPath] = (
      200,
      Canned.playUrl(tag: 'fresh').replaceFirst(
          '"accept_quality":[126,125,120,80],"accept_description":["杜比视界","真彩 HDR","超清 4K","高清 1080P"]',
          '"accept_quality":[120,80],"accept_description":["超清 4K","高清 1080P"]'),
    );
    timers.activeWith(const Duration(seconds: 700))!.fire();
    await settle();
    expect(controller.qualities.map((option) => option.id), [120, 80]);

    player.emit(const PlayerFailed('cannot decode', formatRejected: true));
    await settle();
    expect(engine.prepared.last.choice.video.codecid, 7);
    expect(engine.prepared.last.choice.video.baseURL, contains('upsig=fresh'));
    expect(http.to(Canned.playUrlPath), hasLength(2));
    controller.dispose();
  });

  test('a local server that cannot be bound again fails the playback, and a retry plays', () async {
    engine.ensureError = const PlaybackError(PlaybackErrorKind.serverDown);
    final controller = make();
    await controller.open(bv);
    expect(controller.phase, PlaybackPhase.failed);
    expect(controller.error, '本地加速服务不可用');
    expect(engine.prepared, isEmpty);

    engine.ensureError = null;
    await controller.open(bv);
    expect(controller.error, isNull);
    expect(player.loaded!.master, FakeEngine.masterOf('tok1'));
    controller.dispose();
  });

  test('back in the foreground, a local server that is down fails the playback', () async {
    final controller = make();
    await controller.open(bv);
    player.emit(const StatusChanged(PlayerStatus.playing));
    engine.ensureError = const PlaybackError(PlaybackErrorKind.serverDown);
    await controller.appResumed();
    expect(controller.phase, PlaybackPhase.failed);
    expect(controller.error, PlaybackErrorKind.serverDown.userMessage);
    controller.dispose();
  });

  test('an engine whose isolate exited is replaced on the next open', () async {
    final replacement = FakeEngine();
    var started = 0;
    final logger = Logger(session: 'test')..add(logs);
    final controller = PlaybackController(
      client: BiliClient(transport: http, cookies: CookieJar(Canned.cookies), now: () => now, logger: logger),
      engine: engine,
      startEngine: () async {
        started += 1;
        return replacement;
      },
      player: player,
      clock: time.clock,
      now: () => now,
      startTimer: timers.start,
      logger: logger,
    );
    await controller.open(bv);
    engine.closed = true;
    await controller.open(bv);
    expect(controller.phase, PlaybackPhase.failed);
    expect(controller.error, PlaybackErrorKind.serverDown.userMessage);
    expect(started, 0);

    await controller.open(bv);
    expect(started, 1);
    expect(controller.engine, same(replacement));
    expect(engine.disposed, isTrue);
    expect(replacement.prepared, hasLength(1));
    expect(player.loaded!.master, FakeEngine.masterOf('tok1'));
    expect(controller.phase, isNot(PlaybackPhase.failed));

    replacement.statsController.add(const EngineSnapshot(concurrency: 4));
    expect(controller.stats.value.engine?.concurrency, 4, reason: 'stats come from the new engine');
    controller.dispose();
  });

  test('a BV link asks the WBI-signed view first, and the unsigned one only when that fails', () async {
    final controller = make();
    await controller.open(bv);
    expect(http.to(Canned.signedViewPath), hasLength(1));
    expect(http.to(Canned.viewPath), isEmpty);

    http.routes[Canned.signedViewPath] = (500, '');
    await controller.open(bv);
    expect(http.to(Canned.viewPath), hasLength(1));
    expect(controller.video?.title, '测试视频');
    controller.dispose();
  });

  test('a BV link the signed view calls gone fails without asking the unsigned view', () async {
    http.routes[Canned.signedViewPath] = (200, '{"code":-404,"message":"啥都木有","ttl":1}');
    final controller = make();
    await controller.open(bv);
    expect(controller.phase, PlaybackPhase.failed);
    expect(http.to(Canned.viewPath), isEmpty);
    controller.dispose();
  });

  test('an av link uses the unsigned view, and the signed one when that answers 412', () async {
    final controller = make();
    await controller.open('av80433022');
    expect(http.to(Canned.viewPath).single.url.queryParameters['aid'], '80433022');
    expect(http.to(Canned.signedViewPath), isEmpty);

    http.routes[Canned.viewPath] = (412, '');
    http.routes['/x/frontend/finger/spi'] = (200, '{"code":0,"message":"ok","data":{"b_3":"B3","b_4":"B4"}}');
    await controller.open('av80433022');
    expect(http.to(Canned.signedViewPath).single.url.queryParameters['aid'], '80433022');
    expect(controller.video?.title, '测试视频');
    controller.dispose();
  });

  group('track choice', () {
    late Dash dash;

    setUp(() async {
      final info = PlayURLInfo.fromJson((BiliEnvelope.parse(Canned.playUrl(), (json) => json).data));
      dash = info.dash!;
    });

    test('takes the preferred codec at the highest quality not above the ceiling', () {
      final choice = PlaybackController.choose(dash,
          quality: 120, codecOrder: CodecMemory.fallbackOrder, excluded: const {})!;
      expect((choice.video.id, choice.video.codecid), (120, 12));
    });

    test('leaves out excluded codec kinds and then unknown ones', () {
      final choice = PlaybackController.choose(dash,
          quality: 120, codecOrder: CodecMemory.fallbackOrder, excluded: const {'hevc'})!;
      expect((choice.video.id, choice.video.codecid), (120, 7));
    });

    test('skips hev1 labels when direct mode cannot rename them', () {
      final choice = PlaybackController.choose(dash,
          quality: 120, codecOrder: CodecMemory.fallbackOrder, excluded: const {}, skipHEV1: true)!;
      expect(choice.video.codecid, 7);
    });

    test('direct mode plays a hev1 label only when the bytes hold hvc1', () {
      final hev1 = dash.video.first;
      final avc = dash.video[1];
      expect(PlaybackController.directCanPlay(hev1, sourceEntry: 'hev1'), isFalse);
      expect(PlaybackController.directCanPlay(hev1, sourceEntry: null), isFalse);
      expect(PlaybackController.directCanPlay(hev1, sourceEntry: 'hvc1'), isTrue);
      expect(PlaybackController.directCanPlay(avc, sourceEntry: null), isTrue);
    });

    test('reads the deadline of the signed URL', () {
      expect(PlaybackController.urlDeadline(dash.video.first), Canned.deadline);
    });
  });

  test('the reaction to a failed load follows the Swift table', () {
    ItemFailureReaction react(ItemFailure failure, {bool btr = false, bool unpatched = false, bool played = false}) =>
        PlaybackController.reaction(failure, btr: btr, servedUnpatchedHEV1: unpatched, played: played);
    expect(react(ItemFailure.format, btr: true, played: true), ItemFailureReaction.nextCodec);
    expect(react(ItemFailure.format, btr: true), ItemFailureReaction.nextCodecRemembered);
    expect(react(ItemFailure.network, btr: true), ItemFailureReaction.fallBackToDirect);
    expect(react(ItemFailure.unknown, btr: true), ItemFailureReaction.fallBackToDirect);
    expect(react(ItemFailure.network), ItemFailureReaction.restart);
    expect(react(ItemFailure.unknown), ItemFailureReaction.restartOnceThenNextCodec);
    expect(react(ItemFailure.format), ItemFailureReaction.nextCodecRemembered);
    expect(react(ItemFailure.format, unpatched: true), ItemFailureReaction.nextCodec);
  });
}
