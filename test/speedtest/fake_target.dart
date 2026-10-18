import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:bili_core/engine.dart';
import 'package:bilifast/devtools/log_server_discovery.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/speedtest/speed_test_plan.dart';
import 'package:bilifast/speedtest/speed_test_runner.dart';

import '../playback/fakes.dart';

/// Takes every config: the engine switches in the plans here are checked against bili_core in its own tests.
({RipperConfig config, List<String> rejected}) acceptAll(Map<String, Object?> overrides) =>
    (config: const RipperConfig(), rejected: const []);

const smallPlan = <String, Object?>{
  'id': 'test-1',
  'videos': <String>[],
  'qualities': [120],
  'variants': [
    {'name': 'A', 'config': <String, Object?>{}, 'connectionsPerHost': 8},
    {'name': 'B', 'config': {'peakBandwidth': true}, 'connectionsPerHost': 4},
  ],
  'order': 'ABBA',
  'seeks': 2,
  'hints': 1,
  'backJumps': 1,
  'dwellSeconds': 1,
  'fastSeconds': 2,
  'fastRate': 2,
};

SpeedTestPlan planWith([Map<String, Object?> changes = const {}]) =>
    SpeedTestPlan.parse(jsonEncode({...smallPlan, ...changes}), check: acceptAll);

/// Plays scripted marks on a fake clock: the first frame [firstFrameMs] after each open or replay, each seek
/// resumed after [seekMs] (null: never).
final class FakeTarget implements SpeedTestTarget {
  final _marks = StreamController<PlaybackMark>.broadcast();
  final calls = <String>[];

  /// (elapsed ms, call) for the calls whose timing matters.
  final timeline = <(int, String)>[];
  Duration Function() now = () => Duration.zero;

  double duration = 600;
  int maxQuality = 127;
  double position = 0;
  final failToOpen = <String>{};

  /// Links whose view works but whose playurl call fails.
  final failPlayurl = <String>{};

  /// Replays (counting from 1) that fail and lose the playurl answer, as the controller's `_fail` does.
  final failReplays = <int>{};

  /// Replays (counting from 1) that fall back to direct.
  final fallBackOnReplays = <int>{};
  int _replays = 0;
  bool _answer = false;

  /// The pending first frame; a replay or an engine swap drops it, as the controller ignores an old item's events.
  Timer? _firstFrame;

  /// One per open or replay, in order; once used up, [defaultFirstFrameMs]. Null: no first frame.
  final firstFrames = <int?>[];
  int defaultFirstFrameMs = 800;
  double? Function(double to) seekMs = (_) => 300;

  @override
  PlaybackPhase phase = PlaybackPhase.idle;
  @override
  String? bvid;
  @override
  int? playingQuality;
  @override
  int selectedQuality = 120;
  @override
  PlaybackMode mode = PlaybackMode.btr;
  @override
  bool fellBack = false;

  @override
  bool get canReplay => bvid != null && _answer;

  /// Playurl calls: each open, and each replay without the answer in hand.
  int playurlCalls = 0;

  void emit(PlaybackMark mark) => _marks.add(mark);

  void _note(String call) {
    calls.add(call);
    timeline.add((now().inMilliseconds, call));
  }

  @override
  Stream<PlaybackMark> get marks => _marks.stream;

  @override
  String? get currentLink => bvid;

  @override
  String get playingCodec => 'HEVC';

  @override
  double get durationSeconds => duration;

  @override
  double get positionSeconds => position;

  @override
  Future<void> useEngine(Future<PlaybackEngine> Function() start) async {
    _note('useEngine');
    _firstFrame?.cancel();
    await start();
    bvid = null;
    _answer = false;
    fellBack = false;
    playingQuality = null;
    phase = PlaybackPhase.idle;
  }

  @override
  Future<void> setQuality(int quality) async {
    _note('quality $quality');
    selectedQuality = quality;
  }

  @override
  Future<void> setMode(PlaybackMode mode) async {
    _note('mode ${mode.name}');
    this.mode = mode;
  }

  @override
  Future<void> open(String link) async {
    _note('open $link');
    if (failToOpen.contains(link)) {
      phase = PlaybackPhase.failed;
      return;
    }
    bvid = link;
    playurlCalls += 1;
    if (failPlayurl.contains(link)) {
      _answer = false;
      phase = PlaybackPhase.failed;
      return;
    }
    _answer = true;
    _play();
  }

  @override
  Future<void> replay({Future<PlaybackEngine> Function()? engine, int? quality}) async {
    _note('replay $quality');
    _firstFrame?.cancel();
    if (bvid == null) return;
    if (engine != null) await engine();
    if (quality != null) selectedQuality = quality;
    _replays += 1;
    fellBack = fallBackOnReplays.contains(_replays);
    if (!_answer) {
      playurlCalls += 1;
      _answer = !failPlayurl.contains(bvid);
    }
    if (failReplays.contains(_replays) || !_answer) {
      _answer = false;
      playingQuality = null;
      phase = PlaybackPhase.failed;
      return;
    }
    _play();
  }

  void _play() {
    position = 0;
    phase = PlaybackPhase.loading;
    playingQuality = min(selectedQuality, maxQuality);
    final ms = firstFrames.isEmpty ? defaultFirstFrameMs : firstFrames.removeAt(0);
    if (ms == null) return;
    _firstFrame = Timer(Duration(milliseconds: ms), () {
      phase = PlaybackPhase.playing;
      emit(FirstFrame(ms.toDouble(), timed: true));
    });
  }

  @override
  Future<void> seek(double seconds) async {
    _note('seek ${seconds.round()}');
    position = seconds;
    final ms = seekMs(seconds);
    if (ms != null) Timer(Duration(milliseconds: ms.round()), () => emit(SeekResumed(ms)));
  }

  @override
  void seekHint(double seconds) => _note('hint ${seconds.round()}');

  @override
  Future<void> setRate(double rate) async => _note('rate $rate');

  @override
  Future<void> setMuted(bool muted) async => _note('muted $muted');

  @override
  Future<void> setKeepAwake(bool on) async => _note('awake $on');
}

/// Hooks that hand out fake engines and record which variant each was for ('app' for the app's own).
final class FakeHooks {
  FakeHooks(this.plan, {this.source = PlanSource.builtin});

  SpeedTestPlan plan;
  final PlanSource source;
  Object? planError;
  final engines = <String>[];
  LogServerEndpoint? askedServer;

  SpeedTestHooks get hooks => SpeedTestHooks(
        choosePlan: (server) async {
          askedServer = server;
          final error = planError;
          if (error != null) throw error;
          return PlanChoice(plan: plan, source: source, note: '没有连接电脑');
        },
        startEngine: (variant) async {
          engines.add(variant.name);
          return FakeEngine();
        },
        appEngine: () async {
          engines.add('app');
          return FakeEngine();
        },
      );
}
