import 'dart:math' as math;

/// The time danmaku is drawn at, following the playhead. A change of rate (the 2× hold and its release) eases the
/// danmaku's speed over [easeSeconds] instead of stepping it, as the official app does, and the playhead's jitter
/// only bends the speed: shown time never steps, it closes any gap at [catchUpPerSecond]. A seek, a pause or a gap
/// past [snapSeconds] is taken at once.
final class DanmakuPace {
  static const easeSeconds = 0.2;
  static const catchUpPerSecond = 1.5;
  static const snapSeconds = 0.5;

  /// A frame longer than this (a hitch, the app coming back) advances no further, so the gap is caught up instead.
  static const maxFrameSeconds = 0.1;

  double? _shown;
  double _rate = 1;
  double? _lastFrame;

  /// The time to draw at for a frame [frameSeconds] into the ticker's run, the playhead at [target] moving at [rate].
  double follow(
    double target, {
    required double rate,
    required bool running,
    required double frameSeconds,
  }) {
    final shown = _shown;
    final last = _lastFrame;
    _lastFrame = frameSeconds;
    if (shown == null ||
        last == null ||
        !running ||
        (target - shown).abs() > snapSeconds) {
      _rate = rate;
      return _shown = target;
    }
    final dt = (frameSeconds - last).clamp(0.0, maxFrameSeconds);
    _rate += (rate - _rate) * (1 - math.exp(-dt / easeSeconds));
    final eased = shown + _rate * dt;
    final next = eased + (target - eased) * (1 - math.exp(-dt * catchUpPerSecond));
    return _shown = math.max(shown, next);
  }

  /// The ticker starts again from zero: the next frame takes the playhead as it is.
  void restart() {
    _shown = null;
    _lastFrame = null;
  }
}
