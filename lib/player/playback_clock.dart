import 'dart:math' as math;

import 'package:bili_core/shared.dart';

import 'bili_player.dart';

/// The playhead between position events (about 10 Hz), extrapolated from the last reading and the rate,
/// so danmaku moves every frame at 120 Hz.
final class PlaybackClock {
  PlaybackClock({MonotonicClock? clock}) : _clock = clock ?? MonotonicClock.system;

  /// Without a fresh reading the clock stops this far past the last one, so a stall the player hasn't
  /// reported yet doesn't run danmaku ahead of the picture.
  static const maxExtrapolationMs = 1000.0;

  /// After a jump or a new item the player can still report positions from before its seek landed; readings
  /// this far from the target are dropped for [jumpSettleMs], so danmaku doesn't snap back and forth.
  static const staleAfterJumpSeconds = 1.5;
  static const jumpSettleMs = 3000.0;

  /// A seek that may land on a keyframe instead of the exact spot can land a whole segment away from it.
  static const keyframeJumpSeconds = 10.0;

  /// Readings arrive with tens of milliseconds of jitter (host time, so twice the media time at 2×); one this
  /// close to the prediction, per unit of rate, only nudges the clock, so danmaku glides instead of wobbling.
  static const smoothingWindowSeconds = 0.04;
  static const smoothing = 0.1;

  final MonotonicClock _clock;
  double? _jumpTarget;
  double _jumpTolerance = staleAfterJumpSeconds;
  double _jumpAtMs = 0;
  bool _fresh = true;
  double _seconds = 0;
  double _atMs = 0;
  double _rate = 1;
  bool _running = false;

  bool get running => _running;

  /// The rate the playhead moves at while [running].
  double get rate => _rate;

  double get seconds {
    if (!_running) return _seconds;
    final elapsed = (_clock.nowMs() - _atMs).clamp(0.0, maxExtrapolationMs);
    return _seconds + elapsed / 1000 * _rate;
  }

  /// False when a position reading was dropped as stale.
  bool handle(PlayerEvent event) {
    switch (event) {
      case PositionChanged(:final seconds, :final hostMs, :final rate):
        if (_jumpTarget case final target?) {
          final settling = _clock.nowMs() - _jumpAtMs < jumpSettleMs;
          if (settling && (seconds - target).abs() > _jumpTolerance) return false;
          _jumpTarget = null;
        }
        final predicted = _seconds + (hostMs - _atMs) / 1000 * _rate;
        if (!_fresh &&
            _running &&
            rate == _rate &&
            (seconds - predicted).abs() <= smoothingWindowSeconds * math.max(rate, 1)) {
          _seconds = predicted + (seconds - predicted) * smoothing;
        } else {
          _seconds = seconds;
        }
        _fresh = false;
        _atMs = hostMs;
        _rate = rate;
      case RateChanged(:final rate):
        _rebase();
        _rate = rate;
      case StatusChanged(:final status):
        final running = status == PlayerStatus.playing;
        if (running == _running) return true;
        _rebase();
        _running = running;
      default:
        break;
    }
    return true;
  }

  /// A seek moves the playhead before the player's next reading. A seek that is not [precise] lands on a keyframe
  /// up to [keyframeJumpSeconds] away, and readings from there are taken at once.
  void jump(double seconds, {bool precise = true}) {
    reset(seconds);
    if (!precise) _jumpTolerance = keyframeJumpSeconds;
  }

  /// A new item starts at [seconds]. It can report 0 before its start seek lands, so as after a jump, readings
  /// far from [seconds] wait until one lands near it or [jumpSettleMs] pass.
  void reset(double seconds) {
    _seconds = seconds;
    _atMs = _clock.nowMs();
    _jumpTarget = seconds;
    _jumpTolerance = staleAfterJumpSeconds;
    _jumpAtMs = _atMs;
    _fresh = true;
  }

  /// Nothing is loaded: the clock stands at 0 until the next item plays.
  void clear() {
    _running = false;
    reset(0);
  }

  void _rebase() {
    _seconds = seconds;
    _atMs = _clock.nowMs();
  }
}
