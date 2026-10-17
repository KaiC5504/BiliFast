import 'package:bili_core/shared.dart';

import 'bili_player.dart';

/// The playhead between position events (about 10 Hz), extrapolated from the last reading and the rate,
/// so danmaku moves every frame at 120 Hz.
final class PlaybackClock {
  PlaybackClock({MonotonicClock? clock}) : _clock = clock ?? MonotonicClock.system;

  /// Without a fresh reading the clock stops this far past the last one, so a stall the player hasn't
  /// reported yet doesn't run danmaku ahead of the picture.
  static const maxExtrapolationMs = 1000.0;

  /// After a jump the player can still report positions from before its seek landed; readings this far from the
  /// target are dropped for [jumpSettleMs], so danmaku doesn't snap back and forth.
  static const staleAfterJumpSeconds = 1.5;
  static const jumpSettleMs = 3000.0;

  final MonotonicClock _clock;
  double? _jumpTarget;
  double _jumpAtMs = 0;
  double _seconds = 0;
  double _atMs = 0;
  double _rate = 1;
  bool _running = false;

  bool get running => _running;

  double get seconds {
    if (!_running) return _seconds;
    final elapsed = (_clock.nowMs() - _atMs).clamp(0.0, maxExtrapolationMs);
    return _seconds + elapsed / 1000 * _rate;
  }

  void handle(PlayerEvent event) {
    switch (event) {
      case PositionChanged(:final seconds, :final hostMs, :final rate):
        if (_jumpTarget case final target?) {
          final settling = _clock.nowMs() - _jumpAtMs < jumpSettleMs;
          if (settling && (seconds - target).abs() > staleAfterJumpSeconds) return;
          _jumpTarget = null;
        }
        _seconds = seconds;
        _atMs = hostMs;
        _rate = rate;
      case RateChanged(:final rate):
        _rebase();
        _rate = rate;
      case StatusChanged(:final status):
        final running = status == PlayerStatus.playing;
        if (running == _running) return;
        _rebase();
        _running = running;
      default:
        break;
    }
  }

  /// A seek moves the playhead before the player's next reading.
  void jump(double seconds) {
    _seconds = seconds;
    _atMs = _clock.nowMs();
    _jumpTarget = seconds;
    _jumpAtMs = _atMs;
  }

  void _rebase() {
    _seconds = seconds;
    _atMs = _clock.nowMs();
  }
}
