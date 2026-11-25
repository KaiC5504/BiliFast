import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/api.dart' show Chapter;
import 'package:flutter/services.dart';

/// A drag passing a chapter's dot taps the hand (KaiC, 2026-11-25).
abstract final class ChapterCrossing {
  /// How far, in points along the drag, the position must go from the dot it last ticked before that dot ticks again.
  static const slackPoints = 1.0;

  /// Whether moving from [from] to [to] seconds passes the start of any chapter but the first.
  ///
  /// A position at a start counts as past it, so a drag that stops on a dot and goes on taps once, and the way back
  /// taps once more as it leaves the dot.
  static bool crossed(List<Chapter> chapters, double from, double to) => _crossedStart(chapters, from, to) != null;

  /// The start crossed nearest [to], or null.
  static double? _crossedStart(List<Chapter> chapters, double from, double to, {double? except}) {
    if (from == to || !from.isFinite || !to.isFinite) return null;
    final low = math.min(from, to);
    final high = math.max(from, to);
    double? nearest;
    for (final chapter in chapters.skip(1)) {
      final start = chapter.from;
      if (start == except || start <= low || start > high) continue;
      if (nearest == null || (start - to).abs() < (nearest - to).abs()) nearest = start;
    }
    return nearest;
  }

  /// The hand's tick. Windows has no haptics: its MissingPluginException would reach the crash log once per dot.
  static void tick() {
    unawaited(
      HapticFeedback.selectionClick().catchError((Object _) {}, test: (error) => error is MissingPluginException),
    );
  }
}

/// One drag's ticks: [ChapterCrossing.crossed], with the dot last ticked held until the position has gone
/// [ChapterCrossing.slackPoints] from it, so a finger resting on a dot doesn't tick it on every jitter. Leaving it
/// back the way it came ticks once, as the band is left.
final class ChapterTicker {
  double? _held;

  /// The side of [_held] the tick left the position on: positive past it, negative before it.
  double _side = 0;

  /// Forgets the held dot, for a new drag.
  void reset() => _held = null;

  /// Whether the move from [from] to [to] seconds should tick, given [secondsPerPoint] along the drag.
  bool moved(List<Chapter> chapters, double from, double to, {required double secondsPerPoint}) {
    if (!from.isFinite || !to.isFinite) return false;
    final held = _held;
    final crossed = ChapterCrossing._crossedStart(chapters, from, to, except: held);
    var tick = crossed != null;
    if (held != null && (to - held).abs() >= ChapterCrossing.slackPoints * secondsPerPoint) {
      _held = null;
      if (_sideOf(held, to) != _side) tick = true;
    }
    if (crossed != null) {
      _held = crossed;
      _side = _sideOf(crossed, to);
    }
    return tick;
  }

  static double _sideOf(double start, double position) => position >= start ? 1 : -1;
}
