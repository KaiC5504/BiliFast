import 'dart:math';

/// Times a user's seek from the jump until playback moves again (port of SeekTimer.swift). Times are
/// milliseconds on a monotonic clock.
final class SeekTimer {
  ({double atMs, double position, bool exact})? _started;
  bool _reloading = false;

  bool get isRunning => _started != null;

  /// A reload starts where playback was; that is not the user's seek, up to the reload's first playing.
  void reloadBegan() {
    _reloading = true;
    _started = null;
  }

  /// A seek while paused is not timed: the wait would include however long the user stays paused.
  /// Returns true when timing started. A seek that is not [exact] lands on a keyframe near [position] instead.
  bool jumped({required double position, required double atMs, required double rate, bool exact = true}) {
    if (_reloading || rate <= 0) {
      _started = null;
      return false;
    }
    _started = (atMs: atMs, position: position, exact: exact);
    return true;
  }

  /// The player started playing; returns the seek's milliseconds if one was being timed.
  double? playing({required double atMs}) {
    _reloading = false;
    final started = _started;
    if (started == null) return null;
    _started = null;
    return max(0, atMs - started.atMs);
  }

  /// A seek inside the buffer may never leave playing. Once the playhead has moved on from the jump, playback
  /// resumed `advanced / rate` seconds ago; returns the seek's milliseconds then. After a seek to a keyframe the
  /// first reading says where it landed, and the playhead moves on from there.
  double? ticked({required double position, required double rate, required bool playing, required double atMs}) {
    final started = _started;
    if (started == null || !playing || rate <= 0) return null;
    if (!started.exact) {
      _started = (atMs: started.atMs, position: position, exact: true);
      return null;
    }
    final advanced = position - started.position;
    if (advanced < 0.2) return null;
    _started = null;
    return max(0, atMs - started.atMs - advanced / rate * 1000);
  }

  /// The user paused before playback resumed; the wait from here on is theirs, not the player's.
  void paused() => _started = null;

  void cancel() {
    _started = null;
    _reloading = false;
  }
}

/// AVPlayer reports a stall for the wait after a drag too, sometimes just before the jump itself is reported.
/// A stall counts only when no jump came within a second before it or 0.75 s after (port of StallFilter).
final class StallFilter {
  static const beforeMs = 1000.0;
  static const afterMs = 750.0;

  /// The wait after a jump is not a stall, but one this long is lag the viewer feels; direct mode waited 9-12 s.
  static const slowSeekMs = 1000.0;

  double? _lastJumpMs;

  static bool isLag(double seekMs) => seekMs > slowSeekMs;

  void jumped(double atMs) => _lastJumpMs = atMs;

  /// Ask [afterMs] past the stall, once a jump that belongs to it has had time to arrive.
  bool isSeekWait(double stalledAtMs) {
    final lastJump = _lastJumpMs;
    if (lastJump == null) return false;
    final gap = lastJump - stalledAtMs;
    return gap >= -beforeMs && gap <= afterMs;
  }
}
