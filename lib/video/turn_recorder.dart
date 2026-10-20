import 'dart:async';
import 'dart:math' show max, pi;
import 'dart:typed_data';
import 'dart:ui' show FramePhase, FrameTiming, Rect, Size;

import 'package:bili_core/devlog.dart';
import 'package:flutter/scheduler.dart';

import '../device/orientation.dart';
import '../device/orientation_host.dart';
import '../device/turn_style.dart';

/// The video page's side of a drawn turn for the phone's log (docs/reference/turn-log.md): its events as they
/// happen, and every frame of the turn as one line once it has settled, to set against the native side's
/// `turn native …` lines. One per page.
class TurnRecorder {
  TurnRecorder({
    Logger? logger,
    DateTime Function()? now,
    Timer Function(Duration delay, void Function() callback)? startTimer,
    this._scheduler,
    this._refreshRate,
  })  : _logger = logger ?? Logger.shared,
        _now = now ?? DateTime.now,
        _startTimer = startTimer ?? Timer.new;

  /// How long a turn goes without a frame or an event before it counts as settled.
  static const settle = Duration(milliseconds: 300);

  /// Release builds hand over FrameTimings in batches up to a second apart, so a settled turn's line waits up to this
  /// long for the batch holding its last frame.
  static const timingsWait = Duration(milliseconds: 1200);

  /// A window keeps this many frames at most (5 s at 120 Hz), so a turn that never settles can't grow without bound.
  static const maxFrames = 600;

  /// Per frame: µs since t0, angle (rad), grow, the box's left, top, width and height (NaN at rest), then the size's
  /// width and height.
  static const _stride = 9;

  final Logger _logger;
  final DateTime Function() _now;
  final Timer Function(Duration, void Function()) _startTimer;
  final SchedulerBinding? _scheduler;

  /// The display's rate in Hz; the view's display when not given.
  final double Function()? _refreshRate;

  /// The turn being drawn now.
  late _Window _window = _Window(_heard);

  /// Settled turns still waiting for their timings, oldest first.
  final _pending = <_Window>[];

  /// The settle check, at most one at a time; [_busy] when a frame or event came since it was started.
  Timer? _quiet;
  bool _busy = false;
  bool _disposed = false;

  /// The presentation changed: a turn may follow.
  void presentation(
    Presentation from,
    Presentation to, {
    required bool wide,
    required bool waiting,
    required TurnStyle style,
  }) =>
      _event('presentation', {
        'from': from.name,
        'to': to.name,
        'wide': wide,
        'waiting': waiting,
        'style': style.label,
      });

  /// The host started [start]; [outcome] is `pending` (the turn the page waits for), `stale` (the other way, or
  /// overtaken) or `unasked` (none was waited for).
  void started(TurnStart start, {required String outcome}) => _event('started', {
        'turn': start.id,
        'angle': start.angle,
        'ms': start.duration.inMicroseconds / 1000,
        'outcome': outcome,
      });

  /// The first build at a new screen shape.
  void sized(Size size, {required Presentation layout}) =>
      _event('sized', {'w': size.width, 'h': size.height, 'layout': layout.name});

  /// The page started drawing [turn]: from [spinFrom] radians back to 0 over [duration], the player box from [grow];
  /// [held] while it waits for the still picture to go (等截图).
  void began(
    int turn, {
    required double spinFrom,
    required Duration duration,
    required double grow,
    required bool held,
  }) =>
      _event('began', {
        'turn': turn,
        'spinFrom': spinFrom,
        'ms': duration.inMicroseconds / 1000,
        'grow': grow,
        'held': held,
      });

  /// A held turn starts moving; [why] is `picture` or `timeout`.
  void released(int turn, {required String why}) => _event('released', {'turn': turn, 'why': why});

  void drawnSent(int turn) => _event('drawn sent', {'turn': turn});

  void pictureGone(int turn) => _event('picture gone', {'turn': turn});

  /// The wait for a turn ran out; [missed] when none came at all.
  void late({required bool missed}) => _event('late', {'missed': missed});

  /// One frame of a turn as drawn: the page's angle in radians, the grow, the player box (null at rest), the size laid
  /// out at.
  ///
  /// Called from the page's build on every tick of a turn, so it only stores numbers; the line is written once the
  /// turn has settled.
  void frame({required double angle, required double grow, required Rect? box, required Size size}) {
    if (_disposed) return;
    final now = _now().microsecondsSinceEpoch;
    final window = _window;
    if (window.count == 0) {
      window.t0Us = now;
      window.listen(_scheduler ?? SchedulerBinding.instance);
    }
    window.lastFrameUs = now;
    _touch();
    if (window.count == maxFrames) return;
    var at = window.count * _stride;
    var samples = window.samples;
    if (at + _stride > samples.length) {
      samples = window.samples = Float64List(samples.length * 2)..setAll(0, samples);
    }
    samples[at++] = (now - window.t0Us).toDouble();
    samples[at++] = angle;
    samples[at++] = grow;
    samples[at++] = box?.left ?? double.nan;
    samples[at++] = box?.top ?? double.nan;
    samples[at++] = box?.width ?? double.nan;
    samples[at++] = box?.height ?? double.nan;
    samples[at++] = size.width;
    samples[at] = size.height;
    window.count++;
  }

  /// Writes what is pending at once.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final window in List.of(_pending)) {
      _write(window);
    }
    if (_window.count > 0) _write(_window);
    _quiet?.cancel();
    _quiet = null;
  }

  void _event(String kind, Map<String, Object> fields) {
    _logger.info(LogCategory.ui, 'turn $kind', {'wUs': _now().microsecondsSinceEpoch, ...fields});
    if (_quiet != null) _busy = true;
  }

  /// One timer per [settle] rather than one per frame: when it fires after more activity, it starts over, so the
  /// settle check runs between one and two [settle]s after the turn's last frame or event.
  void _touch() {
    if (_quiet != null) {
      _busy = true;
      return;
    }
    _busy = false;
    _quiet = _startTimer(settle, _quietCheck);
  }

  void _quietCheck() {
    _quiet = null;
    if (_busy) {
      _touch();
      return;
    }
    final window = _window;
    if (window.count == 0) return;
    if (window.timingsCaughtUp) {
      _write(window);
      return;
    }
    // 轮换测试 turns again about 1.5 s later, inside the wait, so the next frame or event starts a window of its own.
    _pending.add(window);
    window.waiting = _startTimer(timingsWait, () => _write(window));
    _window = _Window(_heard);
  }

  void _heard(_Window window) {
    if (window.waiting != null && window.timingsCaughtUp) _write(window);
  }

  /// The engine's timestamps are on its own clock; the raster end is also stamped on the wall clock, which places
  /// the rest. Null when the engine gave no wall time.
  static int? _wallOffset(FrameTiming timing) {
    final wall = timing.timestampInMicroseconds(FramePhase.rasterFinishWallTime);
    return wall == 0 ? null : wall - timing.timestampInMicroseconds(FramePhase.rasterFinish);
  }

  /// NaN when the engine gave no wall time.
  static double _rasterEndMs(FrameTiming timing, int t0Us) {
    final wall = timing.timestampInMicroseconds(FramePhase.rasterFinishWallTime);
    return wall == 0 ? double.nan : (wall - t0Us) / 1000;
  }

  static int _buildStart(FrameTiming timing) => timing.timestampInMicroseconds(FramePhase.buildStart);

  double _hz() {
    final hz = _refreshRate?.call() ?? _displayHz(_scheduler ?? SchedulerBinding.instance);
    // Reported as 0 when the platform doesn't say.
    return hz.isFinite && hz > 0 ? hz : 60;
  }

  static double _displayHz(SchedulerBinding scheduler) {
    final views = scheduler.platformDispatcher.views;
    return views.isEmpty ? 0 : views.first.display.refreshRate;
  }

  void _write(_Window window) {
    window.waiting?.cancel();
    window.waiting = null;
    window.stopListening();
    _pending.remove(window);

    final t0Us = window.t0Us;
    final heard = window.timings.where(window.overlaps).toList()
      ..sort((a, b) => _buildStart(a).compareTo(_buildStart(b)));

    final samples = StringBuffer();
    var next = 0;
    for (var i = 0; i < window.count; i++) {
      final at = i * _stride;
      if (i > 0) samples.write(';');
      samples
        ..write(_fixed(window.samples[at] / 1000, 1))
        ..write(',')
        ..write(_fixed(window.samples[at + 1] * 180 / pi, 1))
        ..write(',')
        ..write(_fixed(window.samples[at + 2], 3));
      for (var field = 3; field < _stride; field++) {
        samples
          ..write(',')
          ..write(_fixed(window.samples[at + field], 1));
      }

      // A sample is taken while its frame builds, and both run in time order, so one pass pairs them.
      final us = t0Us + window.samples[at];
      var shownMs = double.nan;
      while (next < heard.length) {
        final timing = heard[next];
        final offset = _wallOffset(timing);
        if (offset != null && timing.timestampInMicroseconds(FramePhase.buildFinish) + offset >= us) {
          if (_buildStart(timing) + offset <= us) shownMs = _rasterEndMs(timing, t0Us);
          break;
        }
        next++;
      }
      samples
        ..write(',')
        ..write(_fixed(shownMs, 1));
    }

    final hz = _hz();
    final refreshMs = 1000 / hz;
    final timings = StringBuffer();
    var worstBuild = 0.0;
    var worstRaster = 0.0;
    var slow = 0;
    for (final timing in heard) {
      final build = timing.buildDuration.inMicroseconds / 1000;
      final raster = timing.rasterDuration.inMicroseconds / 1000;
      final total = timing.totalSpan.inMicroseconds / 1000;
      if (timings.isNotEmpty) timings.write(';');
      timings.write(
          '${_fixed(build, 1)},${_fixed(raster, 1)},${_fixed(total, 1)},${_fixed(_rasterEndMs(timing, t0Us), 1)}');
      worstBuild = max(worstBuild, build);
      worstRaster = max(worstRaster, raster);
      if (total > refreshMs) slow++;
    }

    _logger.info(LogCategory.ui, 'turn frames', {
      'wUs': _now().microsecondsSinceEpoch,
      't0Us': t0Us,
      'count': window.count,
      'samples': samples.toString(),
      'timings': timings.toString(),
      'worstBuildMs': (worstBuild * 10).round() / 10,
      'worstRasterMs': (worstRaster * 10).round() / 10,
      'refreshHz': (hz * 10).round() / 10,
      'slow': slow,
    });
    window.count = 0;
    window.timings.clear();
  }

  /// Empty for NaN (no player box), and never `-0.0`.
  static String _fixed(double value, int digits) {
    if (value.isNaN) return '';
    final text = value.toStringAsFixed(digits);
    return text.startsWith('-') && double.parse(text) == 0 ? text.substring(1) : text;
  }
}

/// One turn: its frames from the first until its line is written, and the engine's timings heard meanwhile.
final class _Window {
  _Window(this._heard);

  final void Function(_Window window) _heard;
  Float64List samples = Float64List(TurnRecorder._stride * 128);
  int count = 0;
  int t0Us = 0;
  int lastFrameUs = 0;
  final timings = <FrameTiming>[];
  SchedulerBinding? _listening;

  /// Settled, and waiting for the batch holding its last frame.
  Timer? waiting;

  void listen(SchedulerBinding scheduler) {
    if (_listening != null) return;
    scheduler.addTimingsCallback(_reported);
    _listening = scheduler;
  }

  void stopListening() {
    _listening?.removeTimingsCallback(_reported);
    _listening = null;
  }

  void _reported(List<FrameTiming> reported) {
    if (timings.length < 2 * TurnRecorder.maxFrames) timings.addAll(reported);
    _heard(this);
  }

  /// The frame that built the last sample has been reported.
  bool get timingsCaughtUp => timings.any((timing) {
        final offset = TurnRecorder._wallOffset(timing);
        return offset == null || timing.timestampInMicroseconds(FramePhase.buildFinish) + offset >= lastFrameUs;
      });

  /// The frame was built while the samples were taken: its build overlaps the first to the last.
  bool overlaps(FrameTiming timing) {
    final offset = TurnRecorder._wallOffset(timing);
    if (offset == null) return true;
    return timing.timestampInMicroseconds(FramePhase.buildStart) + offset <= lastFrameUs &&
        timing.timestampInMicroseconds(FramePhase.buildFinish) + offset >= t0Us;
  }
}
