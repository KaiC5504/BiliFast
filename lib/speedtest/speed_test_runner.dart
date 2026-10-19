import 'dart:async';
import 'dart:convert';
import 'dart:io' show ProcessInfo;
import 'dart:math';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:flutter/foundation.dart';

import '../devtools/log_server_discovery.dart';
import '../playback/playback_controller.dart';
import 'speed_test_plan.dart';
import 'speed_test_results.dart';

/// What the speed test drives: the controller and its player, as the player UI does.
abstract interface class SpeedTestTarget {
  Stream<PlaybackMark> get marks;
  PlaybackPhase get phase;

  /// The open video's, or null.
  String? get bvid;

  /// A link to the open video, or null.
  String? get currentLink;
  int? get playingQuality;
  String get playingCodec;
  int get selectedQuality;

  /// A playurl answer is in hand: [replay] asks Bilibili nothing.
  bool get canReplay;
  PlaybackMode get mode;

  /// BTR failed during this playback and it went on direct.
  bool get fellBack;
  double get durationSeconds;
  double get positionSeconds;

  Future<void> useEngine(Future<PlaybackEngine> Function() start);
  Future<void> setQuality(int quality);
  Future<void> setMode(PlaybackMode mode);
  Future<void> open(String link);
  Future<void> replay({Future<PlaybackEngine> Function()? engine, int? quality});

  /// A tap on the seek bar: the player seeks to a keyframe and the controller times it.
  Future<void> seek(double seconds);
  void seekHint(double seconds);
  Future<void> setRate(double rate);
  Future<void> setMuted(bool muted);
  bool get muted;
  Future<void> setKeepAwake(bool on);
}

final class ControllerTarget implements SpeedTestTarget {
  ControllerTarget(this.controller);

  final PlaybackController controller;

  @override
  Stream<PlaybackMark> get marks => controller.marks;

  @override
  PlaybackPhase get phase => controller.phase;

  @override
  String? get bvid => controller.video?.bvid;

  @override
  String? get currentLink {
    final video = controller.video;
    if (video == null) return null;
    final page = controller.page?.page ?? 1;
    return page > 1 ? '${video.bvid}?p=$page' : video.bvid;
  }

  @override
  int? get playingQuality => controller.playing?.quality;

  @override
  String get playingCodec => controller.playing?.codec ?? '';

  @override
  int get selectedQuality => controller.selectedQuality;

  @override
  bool get canReplay => controller.canReplay;

  @override
  PlaybackMode get mode => controller.mode;

  @override
  bool get fellBack => controller.fellBack;

  @override
  Future<void> setMode(PlaybackMode mode) => controller.setMode(mode);

  @override
  double get durationSeconds {
    final reported = controller.duration.value;
    return reported > 0 ? reported : (controller.page?.duration ?? 0).toDouble();
  }

  @override
  double get positionSeconds => controller.currentSeconds;

  @override
  Future<void> useEngine(Future<PlaybackEngine> Function() start) => controller.useEngine(start);

  @override
  Future<void> setQuality(int quality) => controller.setQuality(quality);

  @override
  Future<void> open(String link) => controller.open(link);

  @override
  Future<void> replay({Future<PlaybackEngine> Function()? engine, int? quality}) =>
      controller.replay(engine: engine, quality: quality);

  /// In the order PlayerStage commits a seek.
  @override
  Future<void> seek(double seconds) async {
    final seeked = controller.player.seek(seconds, precise: false);
    controller.userSeeked(seconds, precise: false);
    await seeked;
  }

  @override
  void seekHint(double seconds) => controller.seekHint(seconds);

  @override
  Future<void> setRate(double rate) => controller.player.setRate(rate);

  @override
  Future<void> setMuted(bool muted) => controller.player.setMuted(muted);

  @override
  bool get muted => controller.player.muted;

  @override
  Future<void> setKeepAwake(bool on) => controller.player.setKeepAwake(on);
}

/// Where plans and engines come from; the page's default uses the real ones, tests pass fakes.
final class SpeedTestHooks {
  const SpeedTestHooks({required this.choosePlan, required this.startEngine, required this.appEngine});

  final Future<PlanChoice> Function(LogServerEndpoint? server) choosePlan;
  final Future<PlaybackEngine> Function(SpeedTestVariant variant) startEngine;

  /// Put back when the test ends.
  final Future<PlaybackEngine> Function() appEngine;
}

/// Runs a [SpeedTestPlan] on the phone by itself: the same steps every pass, every number to the log (category
/// `app`, messages starting `speedtest`), a summary for the page.
class SpeedTestRunner extends ChangeNotifier {
  SpeedTestRunner({
    required this.target,
    required this.hooks,
    Logger? logger,
    int Function()? newSeed,
    int Function()? rss,
  })  : _logger = logger ?? Logger.shared,
        _newSeed = newSeed ?? (() => Random().nextInt(1 << 31)),
        _rss = rss ?? (() => ProcessInfo.currentRss);

  static const firstFrameTimeout = Duration(seconds: 20);
  static const seekTimeout = Duration(seconds: 15);
  static const hintRest = Duration(milliseconds: 300);
  static const backJumpSeconds = 15.0;

  /// Tap seeks land at least this far from where this pass has been, so the engine's cache never answers one.
  static const freshGapSeconds = 30.0;
  static const seekStartSeconds = 10.0;
  static const seekEndMarginSeconds = 20.0;

  final SpeedTestTarget target;
  final SpeedTestHooks hooks;
  final Logger _logger;
  final int Function() _newSeed;
  final int Function() _rss;

  bool _running = false;
  bool _cancelled = false;
  bool _disposed = false;
  PlanChoice? _plan;
  String? _error;
  int _passCount = 0;
  SpeedTestPass? _pass;
  String _step = '';
  final List<PassResult> _results = [];
  final List<String> _notes = [];

  PassResult? _current;
  bool _fast = false;
  final Set<void Function()> _interrupts = {};
  bool _soundAndScreenRestored = true;

  /// As the run found them, to be put back.
  bool _wasMuted = false;
  int _originalQuality = 0;
  PlaybackMode _originalMode = PlaybackMode.btr;

  /// A variant engine has been asked for since the run began, so the app's must come back.
  bool _needsPutBack = false;

  bool get running => _running;
  bool get cancelled => _cancelled;
  PlanChoice? get plan => _plan;

  /// Why the test didn't start or stopped early.
  String? get error => _error;
  int get passCount => _passCount;
  SpeedTestPass? get pass => _pass;
  String get step => _step;
  List<PassResult> get results => List.unmodifiable(_results);
  List<String> get notes => List.unmodifiable(_notes);

  /// [links] one per line from the page; empty means the plan's videos, or the video that is open.
  Future<void> start({required List<String> links, LogServerEndpoint? server}) async {
    if (_running) return;
    _running = true;
    _cancelled = false;
    _error = null;
    _plan = null;
    _pass = null;
    _passCount = 0;
    _results.clear();
    _notes.clear();
    _step = '正在取计划…';
    _notify();
    final PlanChoice choice;
    try {
      choice = await hooks.choosePlan(server);
    } catch (error) {
      _logger.warn(LogCategory.app, 'speedtest plan refused', {'error': '$error'});
      _finishEarly('$error');
      return;
    }
    _plan = choice;
    final plan = choice.plan;
    final current = target.currentLink;
    final videos = links.isNotEmpty
        ? links
        : plan.videos.isNotEmpty
            ? plan.videos
            : [?current];
    if (videos.isEmpty) {
      _finishEarly('没有要测的视频：填链接，或先播放一个');
      return;
    }
    if (_cancelled) {
      _finishEarly(null);
      return;
    }
    final passes = plan.passes(videos);
    _passCount = passes.length;
    _logger.info(LogCategory.app, 'speedtest start', {
      'plan': plan.id,
      'source': choice.source.name,
      'planNote': choice.note,
      'passes': passes.length,
      'videos': videos.length,
    });
    await _run(plan, passes);
  }

  void stop() {
    if (!_running || _cancelled) return;
    _cancelled = true;
    _step = '正在停止…';
    _notify();
    for (final interrupt in _interrupts.toList()) {
      interrupt();
    }
  }

  void _finishEarly(String? error) {
    _error = error;
    _running = false;
    _step = '';
    _notify();
  }

  Future<void> _run(SpeedTestPlan plan, List<SpeedTestPass> passes) async {
    final marks = target.marks.listen(_onMark);
    final sampler = Timer.periodic(const Duration(seconds: 1), (_) => _current?.noteRss(_rss()));
    _originalQuality = target.selectedQuality;
    _originalMode = target.mode;
    _wasMuted = target.muted;
    var finished = 0;
    _soundAndScreenRestored = false;
    final done = <String>{};
    int? openVideo;
    int? brokenVideo;
    // A failed pass loses the playurl answer; the next may ask for it once, and the video is given up after that.
    var refetched = false;
    try {
      await _quietly(() => target.setMuted(true));
      // Stopped meanwhile, the screen would stay on: its restore has already been sent.
      _checkCancelled();
      await _quietly(() => target.setKeepAwake(true));
      for (final pass in passes) {
        _checkCancelled();
        _pass = pass;
        final result = PassResult(
          pass: pass.index,
          variant: pass.variant.name,
          askedQuality: pass.quality,
          bvid: pass.videoIndex == openVideo ? target.bvid ?? '' : _idOf(pass.video),
          seed: _newSeed(),
          cold: pass.cold,
        );
        _current = result;
        _results.add(result);
        _logger.info(LogCategory.app, 'speedtest pass', {
          'pass': pass.index,
          'variant': pass.variant.name,
          'quality': pass.quality,
          'bvid': result.bvid,
          'seed': result.seed,
          'cold': pass.cold,
          'connectionsPerHost': pass.variant.connectionsPerHost,
          'overrides': jsonEncode(pass.variant.overrides),
        });
        if (pass.videoIndex != openVideo && pass.videoIndex != brokenVideo) {
          _needsPutBack = true;
          switch (await _openVideo(pass)) {
            case _Opened.ok:
              openVideo = pass.videoIndex;
              refetched = false;
            case _Opened.broken:
              brokenVideo = pass.videoIndex;
            case _Opened.engineFailed:
              break;
          }
        }
        if (!target.canReplay && pass.videoIndex == openVideo) {
          if (refetched) {
            brokenVideo = pass.videoIndex;
            openVideo = null;
          } else {
            refetched = true;
          }
        }
        if (pass.videoIndex == brokenVideo) {
          result
            ..failed = true
            ..failure = '视频打不开';
        } else if (pass.videoIndex != openVideo) {
          result
            ..failed = true
            ..failure = '引擎启动失败';
        } else {
          await _runPass(plan, pass, result, done: done);
        }
        _logPassDone(result);
        finished++;
        _current = null;
        _notify();
      }
    } on _Cancelled {
      if (_current case final current?) _results.remove(current);
    } catch (error, stack) {
      _error = '$error';
      _logger.error(LogCategory.app, 'speedtest failed', {'error': '$error', 'stack': '$stack'});
      if (_current case final current?) _results.remove(current);
    } finally {
      _current = null;
      _fast = false;
      sampler.cancel();
      unawaited(marks.cancel());
      // Sound and screen first: restoring the engine can hang on a network that has gone.
      _restoreSoundAndScreen();
      await _quietly(() => target.setRate(1));
      // Once disposed, [dispose] has put them back, or the target went with the page.
      if (!_disposed) await _putBack();
      _logger.info(LogCategory.app, 'speedtest done', {'passes': finished, 'cancelled': _cancelled});
      _running = false;
      _pass = null;
      _step = _cancelled ? '已停止' : (_error != null ? '出错，已停止' : '完成');
      _notify();
    }
  }

  /// Opens the pass's video in BTR mode: the run's one call for its playurl. What plays is only a warm-up; every pass,
  /// the first too, replays from 0 on a fresh engine, so no pass's first frame carries the playurl round trip.
  Future<_Opened> _openVideo(SpeedTestPass pass) async {
    _setStep('正在打开视频');
    try {
      await target.useEngine(() => hooks.startEngine(pass.variant));
    } catch (error) {
      _logger.warn(LogCategory.app, 'speedtest engine failed', {'error': '$error'});
      return _Opened.engineFailed;
    }
    _checkCancelled();
    // With nothing loaded, neither reloads anything.
    if (target.mode != PlaybackMode.btr) await target.setMode(PlaybackMode.btr);
    _checkCancelled();
    await target.setQuality(pass.quality);
    _checkCancelled();
    await target.open(pass.video);
    _checkCancelled();
    return target.bvid != null && target.canReplay ? _Opened.ok : _Opened.broken;
  }

  Future<void> _runPass(SpeedTestPlan plan, SpeedTestPass pass, PassResult result,
      {required Set<String> done}) async {
    final random = Random(result.seed);
    final visited = <double>[0];
    _MarkWait<FirstFrame>? first;
    try {
      _setStep('从头播放');
      first = _MarkWait(this, firstFrameTimeout);
      await target.replay(engine: () => hooks.startEngine(pass.variant), quality: pass.quality);
      _checkCancelled();
      final played = target.playingQuality;
      result.bvid = target.bvid ?? result.bvid;
      if (played == null || target.phase == PlaybackPhase.failed) {
        throw const _PassFailed('播放失败');
      }
      if (target.fellBack) throw const _PassFailed('回退到直连');
      result
        ..quality = played
        ..codec = target.playingCodec;
      // ABBA's second A repeats the first by design; only a video without the asked quality plays one twice.
      if (!done.add('${pass.videoIndex}|${pass.variant.name}|${pass.repeat}|$played')) {
        result.skipped = true;
        return;
      }
      _setStep('等待首帧');
      final got = await first.result;
      first = null;
      _checkCancelled();
      switch (got) {
        case _Got(:final mark):
          result.firstFrameMs = mark.ms;
          _logStep(result, StepResult(kind: StepKind.first, to: 0, ms: mark.ms, timedOut: false));
        case _TimedOut():
          _logStep(result,
              StepResult(kind: StepKind.first, to: 0, ms: firstFrameTimeout.inMilliseconds.toDouble(), timedOut: true));
          throw const _PassFailed('首帧超时');
        case _Failed():
          throw const _PassFailed('播放失败');
      }
      await _sleep(_seconds(plan.dwellSeconds));

      for (var i = 0; i < plan.seeks; i++) {
        final to = _freshTarget(random, visited);
        if (to == null) {
          _short(pass, '跳转', plan.seeks, i);
          break;
        }
        _setStep('跳转 ${i + 1}/${plan.seeks}');
        await _seekStep(plan, result, StepKind.tap, to, visited);
      }
      for (var i = 0; i < plan.hints; i++) {
        final to = _freshTarget(random, visited);
        if (to == null) {
          _short(pass, '提示跳转', plan.hints, i);
          break;
        }
        _setStep('提示跳转 ${i + 1}/${plan.hints}');
        target.seekHint(to);
        await _sleep(hintRest);
        await _seekStep(plan, result, StepKind.hint, to, visited);
      }
      for (var i = 0; i < plan.backJumps; i++) {
        _setStep('回跳 ${i + 1}/${plan.backJumps}');
        final to = max(0.0, (target.positionSeconds - backJumpSeconds).floorToDouble());
        await _seekStep(plan, result, StepKind.back, to, visited);
      }
      if (plan.fastSeconds > 0) {
        _setStep('${_rate(plan.fastRate)} 倍速 ${_rate(plan.fastSeconds)} 秒');
        await target.setRate(plan.fastRate);
        _fast = true;
        try {
          await _sleep(_seconds(plan.fastSeconds));
        } finally {
          _fast = false;
          await _quietly(() => target.setRate(1));
        }
      }
      // Numbers from a pass that went on direct are not the variant's.
      if (target.fellBack) throw const _PassFailed('回退到直连');
    } on _PassFailed catch (failure) {
      result
        ..failed = true
        ..failure = failure.reason;
    } finally {
      first?.cancel();
    }
  }

  Future<void> _seekStep(SpeedTestPlan plan, PassResult result, StepKind kind, double to, List<double> visited) async {
    final wait = _MarkWait<SeekResumed>(this, seekTimeout);
    try {
      await target.seek(to);
    } catch (_) {
      wait.cancel();
      rethrow;
    }
    final got = await wait.result;
    _checkCancelled();
    visited.add(to);
    _logStep(
        result,
        switch (got) {
          _Got(:final mark) => StepResult(kind: kind, to: to, ms: mark.ms, timedOut: false),
          _TimedOut() => StepResult(kind: kind, to: to, ms: seekTimeout.inMilliseconds.toDouble(), timedOut: true),
          _Failed() => throw const _PassFailed('播放失败'),
        });
    await _sleep(_seconds(plan.dwellSeconds));
  }

  /// A whole second in [seekStartSeconds, duration - [seekEndMarginSeconds]], [freshGapSeconds] from the playhead
  /// and from every spot this pass played; null when the video has no such spot left.
  double? _freshTarget(Random random, List<double> visited) {
    const low = seekStartSeconds;
    final high = target.durationSeconds - seekEndMarginSeconds;
    if (high < low) return null;
    final avoid = [target.positionSeconds, ...visited];
    final span = (high - low).floor();
    for (var tries = 0; tries < 200; tries++) {
      final to = low + random.nextInt(span + 1);
      if (avoid.every((spot) => (spot - to).abs() >= freshGapSeconds)) return to;
    }
    return null;
  }

  void _short(SpeedTestPass pass, String what, int wanted, int made) {
    final note = '第 ${pass.index} 次：视频太短，$what只做了 $made/$wanted 次';
    if (!_notes.contains(note)) _notes.add(note);
    _logger.warn(LogCategory.app, 'speedtest short video',
        {'pass': pass.index, 'kind': what, 'wanted': wanted, 'made': made, 'duration': target.durationSeconds.round()});
  }

  void _onMark(PlaybackMark mark) {
    final current = _current;
    if (current == null) return;
    switch (mark) {
      case Stall():
        current.stalls++;
        if (_fast) current.fastStalls++;
      case MemoryWarning(:final rssBytes):
        current
          ..memoryWarnings += 1
          ..noteRss(rssBytes);
      case FirstFrame() || SeekResumed():
        break;
    }
  }

  void _logStep(PassResult result, StepResult step) {
    result.steps.add(step);
    _logger.info(LogCategory.app, 'speedtest step', {
      'pass': result.pass,
      'variant': result.variant,
      'kind': step.kind.name,
      'to': step.to.round(),
      'ms': step.ms.round(),
      'timedOut': step.timedOut,
    });
  }

  /// Numbers a pass doesn't have (no seeks made, a failed start) are left out rather than logged as zero.
  void _logPassDone(PassResult result) {
    final seeks = result.msOf(StepKind.tap);
    final fields = <String, Object>{
      'pass': result.pass,
      'variant': result.variant,
      'quality': result.quality,
      'askedQuality': result.askedQuality,
      'cold': result.cold,
      'codecs': result.codec,
      'firstFrameMs': ?result.firstFrameMs?.round(),
      'seekMedianMs': ?median(seeks)?.round(),
      'seekP90Ms': ?p90(seeks)?.round(),
      'seekMaxMs': ?(seeks.isEmpty ? null : seeks.reduce(max).round()),
      'hintMedianMs': ?median(result.msOf(StepKind.hint))?.round(),
      'backMedianMs': ?median(result.msOf(StepKind.back))?.round(),
      'timeouts': result.timeouts,
      'stalls': result.stalls,
      'fastStalls': result.fastStalls,
      'rssMaxMB': result.rssMaxBytes ~/ (1024 * 1024),
      'memoryWarnings': result.memoryWarnings,
      'skipped': result.skipped,
      'failed': result.failed,
      'failure': ?result.failure,
    };
    _logger.info(LogCategory.app, 'speedtest pass done', fields);
  }

  Future<void> _sleep(Duration duration) async {
    _checkCancelled();
    if (duration <= Duration.zero) return;
    final woke = Completer<void>();
    final timer = Timer(duration, () {
      if (!woke.isCompleted) woke.complete();
    });
    void interrupt() {
      timer.cancel();
      if (!woke.isCompleted) woke.complete();
    }

    _interrupts.add(interrupt);
    try {
      await woke.future;
    } finally {
      _interrupts.remove(interrupt);
    }
    _checkCancelled();
  }

  void _checkCancelled() {
    if (_cancelled) throw const _Cancelled();
  }

  void _setStep(String step) {
    _step = step;
    _notify();
  }

  void _restoreSoundAndScreen() {
    if (_soundAndScreenRestored) return;
    _soundAndScreenRestored = true;
    unawaited(_quietly(() => target.setMuted(_wasMuted)));
    unawaited(_quietly(() => target.setKeepAwake(false)));
  }

  /// The app's engine, then the quality and mode the run found. The engine swap stops what is loaded at once, so the
  /// other two only change settings; it queues behind a variant's swap still starting, so the app's is the one left.
  Future<void> _putBack() async {
    if (!_needsPutBack) return;
    _needsPutBack = false;
    _setStep('正在恢复…');
    final engine = _quietly(() => target.useEngine(hooks.appEngine));
    await _quietly(() => target.setQuality(_originalQuality));
    if (target.mode != _originalMode) await _quietly(() => target.setMode(_originalMode));
    await engine;
  }

  Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      _logger.warn(LogCategory.app, 'speedtest restore failed', {'error': '$error'});
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  static String _idOf(String link) => switch (LinkParser.parse(link)) {
        BvidLink(:final id) => id,
        AidLink(:final id) => 'av$id',
        _ => '',
      };

  static Duration _seconds(double seconds) => Duration(milliseconds: (seconds * 1000).round());

  static String _rate(double value) => value == value.roundToDouble() ? '${value.round()}' : '$value';

  /// The page is going away: sound and screen are put back now, while the player can still hear it. The target goes
  /// with the page, so its engine, quality and mode are left alone.
  @override
  void dispose() {
    _disposed = true;
    stop();
    _restoreSoundAndScreen();
    super.dispose();
  }
}

sealed class _WaitResult<T extends PlaybackMark> {
  const _WaitResult();
}

final class _Got<T extends PlaybackMark> extends _WaitResult<T> {
  const _Got(this.mark);

  final T mark;
}

final class _TimedOut<T extends PlaybackMark> extends _WaitResult<T> {
  const _TimedOut();
}

final class _Failed<T extends PlaybackMark> extends _WaitResult<T> {
  const _Failed();
}

/// Listens from before the action that should cause the mark, so a quick one isn't missed. Ends at the mark, at
/// [timeout], when the playback fails, or when the run is stopped (then [result] reports a timeout and the runner
/// notices it was stopped).
final class _MarkWait<T extends PlaybackMark> {
  _MarkWait(SpeedTestRunner runner, Duration timeout) : _runner = runner {
    _subscription = runner.target.marks.listen((mark) {
      if (mark is T) _finish(_Got(mark));
    });
    _timer = Timer(timeout, () => _finish(const _TimedOut()));
    _poll = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (runner.target.phase == PlaybackPhase.failed) _finish(const _Failed());
    });
    runner._interrupts.add(cancel);
  }

  final SpeedTestRunner _runner;
  late final StreamSubscription<PlaybackMark> _subscription;
  late final Timer _timer;
  late final Timer _poll;
  final _done = Completer<_WaitResult<T>>();

  Future<_WaitResult<T>> get result => _done.future;

  void cancel() => _finish(const _TimedOut());

  void _finish(_WaitResult<T> result) {
    if (_done.isCompleted) return;
    unawaited(_subscription.cancel());
    _timer.cancel();
    _poll.cancel();
    _runner._interrupts.remove(cancel);
    _done.complete(result);
  }
}

final class _Cancelled implements Exception {
  const _Cancelled();
}

final class _PassFailed implements Exception {
  const _PassFailed(this.reason);

  final String reason;
}

enum _Opened { ok, broken, engineFailed }
