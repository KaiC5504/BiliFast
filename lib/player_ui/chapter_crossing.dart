import 'dart:math' as math;

import 'package:bili_core/api.dart' show Chapter;

/// A drag passing a chapter's dot taps the hand once per dot crossed (KaiC, 2026-11-25).
abstract final class ChapterCrossing {
  /// Whether moving from [from] to [to] seconds passes the start of any chapter but the first.
  ///
  /// A position at a start counts as past it, so a drag that stops on a dot and goes on taps once, and the way back
  /// taps once more as it leaves the dot.
  static bool crossed(List<Chapter> chapters, double from, double to) {
    if (from == to || !from.isFinite || !to.isFinite) return false;
    final low = math.min(from, to);
    final high = math.max(from, to);
    for (final chapter in chapters.skip(1)) {
      if (chapter.from > low && chapter.from <= high) return true;
    }
    return false;
  }
}
