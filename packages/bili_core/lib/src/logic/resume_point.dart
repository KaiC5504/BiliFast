abstract final class ResumePoint {
  /// Where to start from the server's saved progress. The history cursor is per video, so it only counts for the part it was saved on.
  static double start({
    required int lastPlayTimeMs,
    required int lastPlayCid,
    required int cid,
    required double duration,
  }) {
    if (lastPlayCid != cid || lastPlayTimeMs <= 0) return 0;
    final seconds = lastPlayTimeMs / 1000;
    return duration - seconds > 5 ? seconds : 0;
  }
}
