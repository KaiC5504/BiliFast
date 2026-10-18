import 'dart:io' show Platform;

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/devtools/log_forwarder.dart';
import 'package:bilifast/playback/codec_memory.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/playback/playback_setup.dart';
import 'package:bilifast/playback/seek_timer.dart';
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
  late ManualClock time;
  late MemorySink logs;
  final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);

  setUp(() {
    http = Canned.http();
    engine = FakeEngine();
    player = FakePlayer();
    time = ManualClock(10000);
    logs = MemorySink();
  });

  PlaybackController make({PlaybackMode mode = PlaybackMode.btr}) {
    final logger = Logger(session: 'test')..add(logs);
    final client = BiliClient(transport: http, cookies: CookieJar(Canned.cookies), now: () => now, logger: logger);
    return PlaybackController(
      client: client,
      engine: engine,
      player: player,
      codecMemory: CodecMemory(),
      mode: mode,
      transportName: 'dart:io',
      clock: time.clock,
      now: () => now,
      startTimer: FakeTimers().start,
      logger: logger,
    );
  }

  void emitPosition(double seconds) =>
      player.emit(PositionChanged(seconds: seconds, hostMs: time.clock.nowMs(), rate: 1));

  test('BTR opens connections to the chosen streams\' nodes before preparing', () async {
    final controller = make();
    await controller.open(bv);
    final choice = engine.prepared.single.choice;
    expect(engine.preconnects.single,
        [choice.video.baseURL, ...choice.video.backupURLs, choice.audio.baseURL, ...choice.audio.backupURLs]);
    controller.dispose();
  });

  test('direct mode has no engine connections to open', () async {
    final controller = make(mode: PlaybackMode.direct);
    await controller.open(bv);
    expect(engine.preconnects, isEmpty);
    controller.dispose();
  });

  test('the engine hears where playback will start, to load it before the player asks', () async {
    final controller = make();
    await controller.open(bv);
    expect(engine.prepared.single.startSeconds, 0);
    player.emit(const StatusChanged(PlayerStatus.playing));
    time.advance(PlaybackClock.jumpSettleMs);
    emitPosition(20);
    await controller.setMode(PlaybackMode.direct);
    await controller.setMode(PlaybackMode.btr);
    expect(engine.prepared.last.startSeconds, closeTo(20, 1e-9));
    controller.dispose();
  });

  test('a finger resting on the bar hints the engine, and a drag given up cancels the hint', () async {
    final controller = make();
    await controller.open(bv);
    controller.seekHint(42);
    controller.seekHint(null);
    expect(engine.hints, [(token: 'tok1', seconds: 42.0), (token: 'tok1', seconds: null)]);
    controller.dispose();
  });

  test('direct mode has no engine to hint', () async {
    final controller = make(mode: PlaybackMode.direct);
    await controller.open(bv);
    controller.seekHint(42);
    expect(engine.hints, isEmpty);
    controller.dispose();
  });

  test('a keyframe seek is timed from where the player landed', () async {
    final controller = make();
    await controller.open(bv);
    player.emit(const StatusChanged(PlayerStatus.playing));
    controller.userSeeked(100, precise: false);
    time.advance(300);
    // The keyframe before 100 s: far enough that a precise seek would take the reading for a stale one.
    emitPosition(96.5);
    expect(controller.clock.seconds, closeTo(96.5, 1e-9));
    expect(controller.stats.value.lastSeekMs, isNull, reason: 'landed, not yet moving');
    time.advance(250);
    emitPosition(96.75);
    expect(controller.stats.value.lastSeekMs, closeTo(300, 1e-9));
    final seek = logs.events.lastWhere((event) => event.msg == 'seek');
    expect(seek.f['precise'], const LogBool(false));
    final resumed = logs.events.lastWhere((event) => event.msg == 'seek resumed');
    expect(resumed.f['precise'], const LogBool(false));
    controller.dispose();
  });

  test('a seek timer for a keyframe seek takes the first reading as the landing', () {
    final timer = SeekTimer()..jumped(position: 100, atMs: 1000, rate: 1, exact: false);
    expect(timer.ticked(position: 97, rate: 1, playing: true, atMs: 1200), isNull);
    expect(timer.ticked(position: 97.1, rate: 1, playing: true, atMs: 1300), isNull, reason: 'under 0.2 s moved');
    expect(timer.ticked(position: 97.5, rate: 1, playing: true, atMs: 1700), 200);
  });

  test('after a keyframe seek the clock takes readings up to a segment away at once', () {
    for (final precise in [true, false]) {
      final clock = PlaybackClock(clock: time.clock)..jump(100, precise: precise);
      clock.handle(PositionChanged(seconds: 94, hostMs: time.clock.nowMs(), rate: 1));
      expect(clock.seconds, precise ? 100 : 94);
      clock.reset(10);
      clock.handle(PositionChanged(seconds: 4, hostMs: time.clock.nowMs(), rate: 1));
      expect(clock.seconds, 10, reason: 'a new item keeps the tight window');
    }
  });

  test('the app runs the engine with the startup and seek speed-ups on', () {
    const config = appRipperConfig;
    expect(config.primeStart && config.prefetchOnPrime && config.streamAdopted, isTrue);
    expect(config.seekBurst && config.audioFirst && config.prefetchFollowsRate, isTrue);
    expect(config.prefetchVideoMaxBytes, greaterThan(config.prefetchVideoBytes));
    expect(config.keepBehindSeconds, 30);
    expect(config.keepBehindBytes, greaterThan(0));
    expect(appEngineOptions.config, same(appRipperConfig));
    expect(appEngineOptions.forwardDebugLogs, devToolsEnabled);
    expect(appRipperConfig.exploreInHurry, isFalse);
    expect(appRipperConfig.tailBackups, isTrue);
    expect(appRipperConfig.banProbation, isTrue);
    expect(config.hurryKeepsOffSlow && config.medianEstimates && config.seekHurriesPrefetch, isTrue);
    expect(config.trimOnMemoryWarning && config.peakBandwidth, isTrue);
    expect(config.hurryPieceBytes, isNull, reason: 'mixed in the speed test: still on trial');
    if (Platform.isWindows) {
      expect(nodeMemoryPath(), endsWith(r'\bilifast\node_memory.json'));
    }
  });
}
