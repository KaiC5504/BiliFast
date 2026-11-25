import 'package:bili_core/api.dart' show Chapter;

/// A drag passing a chapter's dot taps the hand once per dot crossed (KaiC, 2026-11-25).
abstract final class ChapterCrossing {
  /// Whether moving from [from] to [to] seconds passes the start of any chapter but the first.
  static bool crossed(List<Chapter> chapters, double from, double to) => false;
}
