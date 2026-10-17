/// Port of RipperConfig.swift.
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
    this.prefetchVideoBytes = 64 * 1024 * 1024,
    this.prefetchAudioBytes = 8 * 1024 * 1024,
    this.prefetchAheadSeconds = 45,
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

  /// Null lets AutoConcurrency decide.
  final int? fixedConcurrency;

  /// Each track's cap on prefetched bytes, cached and still downloading.
  final int prefetchVideoBytes;
  final int prefetchAudioBytes;

  /// Prefetch stops at segments starting further than this ahead of the playhead.
  final double prefetchAheadSeconds;

  /// Base priority of player requests; prefetch uses 10.
  final double priority;

  /// Off restores the engine without hurry mode: a kill switch.
  final bool hurry;

  /// A segment starting less than this much playback ahead of the playhead is fetched in a hurry.
  final double hurryAheadSeconds;

  /// The connection count without AutoConcurrency (Swift's fallback when neither is given).
  static const defaultConcurrency = 16;

  int get concurrency => fixedConcurrency ?? defaultConcurrency;

  /// [fixedConcurrency] can't be cleared here; build a new config for that.
  RipperConfig copyWith({
    double? firstByteTimeoutMs,
    double? stallTimeoutMs,
    double? attemptTimeoutMs,
    double? hedgeDelayMs,
    int? minChunkBytes,
    int? pieceRounds,
    double? retryWindowMs,
    int? fixedConcurrency,
    int? prefetchVideoBytes,
    int? prefetchAudioBytes,
    double? prefetchAheadSeconds,
    double? priority,
    bool? hurry,
    double? hurryAheadSeconds,
  }) => RipperConfig(
    firstByteTimeoutMs: firstByteTimeoutMs ?? this.firstByteTimeoutMs,
    stallTimeoutMs: stallTimeoutMs ?? this.stallTimeoutMs,
    attemptTimeoutMs: attemptTimeoutMs ?? this.attemptTimeoutMs,
    hedgeDelayMs: hedgeDelayMs ?? this.hedgeDelayMs,
    minChunkBytes: minChunkBytes ?? this.minChunkBytes,
    pieceRounds: pieceRounds ?? this.pieceRounds,
    retryWindowMs: retryWindowMs ?? this.retryWindowMs,
    fixedConcurrency: fixedConcurrency ?? this.fixedConcurrency,
    prefetchVideoBytes: prefetchVideoBytes ?? this.prefetchVideoBytes,
    prefetchAudioBytes: prefetchAudioBytes ?? this.prefetchAudioBytes,
    prefetchAheadSeconds: prefetchAheadSeconds ?? this.prefetchAheadSeconds,
    priority: priority ?? this.priority,
    hurry: hurry ?? this.hurry,
    hurryAheadSeconds: hurryAheadSeconds ?? this.hurryAheadSeconds,
  );
}
