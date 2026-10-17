/// Port of RipperConfig.swift, without the prefetch fields (slice 1 has no prefetch).
final class RipperConfig {
  const RipperConfig({
    this.firstByteTimeoutMs = 5500,
    this.stallTimeoutMs = 4000,
    this.attemptTimeoutMs = 15000,
    this.hedgeDelayMs = 900,
    this.minChunkBytes = 64 * 1024,
    this.pieceRounds = 3,
    this.retryWindowMs = 25000,
    this.fixedConcurrency,
    this.priority = 50,
    this.hurry = true,
    this.hurryAheadSeconds = 10,
  });

  final double firstByteTimeoutMs;
  final double stallTimeoutMs;
  final double attemptTimeoutMs;
  final double hedgeDelayMs;
  final int minChunkBytes;
  final int pieceRounds;
  final double retryWindowMs;

  /// Null takes [defaultConcurrency]: there is no AutoConcurrency yet.
  final int? fixedConcurrency;

  /// Base priority of player requests.
  final double priority;

  /// Off restores the engine without hurry mode: a kill switch.
  final bool hurry;

  /// A segment starting less than this much playback after the last seek is fetched in a hurry.
  final double hurryAheadSeconds;

  /// AutoConcurrency's starting rung in Swift.
  static const defaultConcurrency = 16;

  int get concurrency => fixedConcurrency ?? defaultConcurrency;
}
