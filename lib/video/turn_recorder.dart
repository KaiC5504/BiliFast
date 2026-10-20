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

  /// `slow` counts frames whose whole span, vsync to raster end, is over this.
  static const _slowMs = 16.7;

  /// Per frame: µs since t0, angle (rad), grow, box left, top, width, height (NaN at rest), width, height.
  static const _stride = 9;

  final Logger _logger;
  final DateTime Function() _now;
  final Timer Function(Duration, void Function()) _startTimer;
  final SchedulerBinding? _scheduler;

  Float64List _samples = Float64List(_stride * 128);
  int _count = 0;
  int _t0Us = 0;
  int _lastFrameUs = 0;
  final _timings = <FrameTiming>[];
  SchedulerBinding? _listening;

  /// The settle check, at most one at a time; [_busy] when a frame or event came since it was started.
  Timer? _quiet;
  bool _busy = false;
  Timer? _waitingForTimings;
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
    if (_count == 0) {
      _t0Us = now;
      _listen();
    }
    _lastFrameUs = now;
    _waitingForTimings?.cancel();
    _waitingForTimings = null;
    _touch();
    if (_count == maxFrames) return;
    var at = _count * _stride;
    if (at + _stride > _samples.length) {
      _samples = Float64List(_samples.length * 2)..setAll(0, _samples);
    }
    _samples[at++] = (now - _t0Us).toDouble();
    _samples[at++] = angle;
    _samples[at++] = grow;
    _samples[at++] = box?.left ?? double.nan;
    _samples[at++] = box?.top ?? double.nan;
    _samples[at++] = box?.width ?? double.nan;
    _samples[at++] = box?.height ?? double.nan;
    _samples[at++] = size.width;
    _samples[at] = size.height;
    _count++;
  }

  /// Writes what is pending at once.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_count > 0) _write();
    _quiet?.cancel();
    _quiet = null;
  }

  void _event(String kind, Map<String, Object> fields) {
    _logger.info(LogCategory.ui, 'turn $kind', {'wUs': _now().microsecondsSinceEpoch, ...fields});
    if (_quiet != null) _busy = true;
  }

  /// One timer per [settle] rather than one per frame: when it fires after more activity, it starts over, so the line
  /// goes out between one and two [settle]s after the turn's last frame or event.
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
    if (_count == 0) return;
    if (_timingsCaughtUp) {
      _write();
    } else {
      _waitingForTimings = _startTimer(timingsWait, _write);
    }
  }

  void _listen() {
    if (_listening != null) return;
    final scheduler = _scheduler ?? SchedulerBinding.instance;
    scheduler.addTimingsCallback(_timingsReported);
    _listening = scheduler;
  }

  void _timingsReported(List<FrameTiming> timings) {
    if (_timings.length < 2 * maxFrames) _timings.addAll(timings);
    if (_waitingForTimings != null && _timingsCaughtUp) _write();
  }

  /// The engine's timestamps are on its own clock; the raster end is also stamped on the wall clock, which places
  /// the rest. Null when the engine gave no wall time.
  static int? _wallOffset(FrameTiming timing) {
    final wall = timing.timestampInMicroseconds(FramePhase.rasterFinishWallTime);
    return wall == 0 ? null : wall - timing.timestampInMicroseconds(FramePhase.rasterFinish);
  }

  /// The frame that built the last sample has been reported.
  bool get _timingsCaughtUp => _timings.any((timing) {
        final offset = _wallOffset(timing);
        return offset == null || timing.timestampInMicroseconds(FramePhase.buildFinish) + offset >= _lastFrameUs;
      });

  /// The frame was built while the samples were taken: its build overlaps the first to the last.
  bool _inWindow(FrameTiming timing) {
    final offset = _wallOffset(timing);
    if (offset == null) return true;
    return timing.timestampInMicroseconds(FramePhase.buildStart) + offset <= _lastFrameUs &&
        timing.timestampInMicroseconds(FramePhase.buildFinish) + offset >= _t0Us;
  }

  void _write() {
    _waitingForTimings?.cancel();
    _waitingForTimings = null;
    _listening?.removeTimingsCallback(_timingsReported);
    _listening = null;

    final samples = StringBuffer();
    for (var i = 0; i < _count; i++) {
      final at = i * _stride;
      if (i > 0) samples.write(';');
      samples
        ..write(_fixed(_samples[at] / 1000, 1))
        ..write(',')
        ..write(_fixed(_samples[at + 1] * 180 / pi, 1))
        ..write(',')
        ..write(_fixed(_samples[at + 2], 3));
      for (var field = 3; field < _stride; field++) {
        samples
          ..write(',')
          ..write(_fixed(_samples[at + field], 1));
      }
    }

    final timings = StringBuffer();
    var worstBuild = 0.0;
    var worstRaster = 0.0;
    var slow = 0;
    for (final timing in _timings) {
      if (!_inWindow(timing)) continue;
      final build = timing.buildDuration.inMicroseconds / 1000;
      final raster = timing.rasterDuration.inMicroseconds / 1000;
      final total = timing.totalSpan.inMicroseconds / 1000;
      if (timings.isNotEmpty) timings.write(';');
      timings.write('${_fixed(build, 1)},${_fixed(raster, 1)},${_fixed(total, 1)}');
      worstBuild = max(worstBuild, build);
      worstRaster = max(worstRaster, raster);
      if (total > _slowMs) slow++;
    }

    _logger.info(LogCategory.ui, 'turn frames', {
      'wUs': _now().microsecondsSinceEpoch,
      't0Us': _t0Us,
      'count': _count,
      'samples': samples.toString(),
      'timings': timings.toString(),
      'worstBuildMs': (worstBuild * 10).round() / 10,
      'worstRasterMs': (worstRaster * 10).round() / 10,
      'slow': slow,
    });
    _count = 0;
    _timings.clear();
  }

  /// Empty for NaN (no player box), and never `-0.0`.
  static String _fixed(double value, int digits) {
    if (value.isNaN) return '';
    final text = value.toStringAsFixed(digits);
    return text.startsWith('-') && double.parse(text) == 0 ? text.substring(1) : text;
  }
}
