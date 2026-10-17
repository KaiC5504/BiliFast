/// Port of RipperConfig.swift. The fields after [hurryAheadSeconds] are BiliFast's own; each default keeps Swift's
/// behaviour, and the app turns them on (`playback_setup.dart`).
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
    this.primeStart = false,
    this.prefetchOnPrime = false,
    this.streamAdopted = false,
    this.seekBurst = false,
    this.seekBurstBytes = 512 * 1024,
    this.seekBurstCopies = 3,
    this.audioFirst = false,
    this.audioReserve = 2,
    this.audioWholeBytes = 256 * 1024,
    this.prefetchFollowsRate = false,
    this.prefetchVideoMaxBytes,
    this.prefetchAudioMaxBytes,
    this.keepBehindSeconds = 2,
    this.keepBehindBytes = 0,
    this.exploreInHurry = true,
    this.tailBackups = false,
    this.banProbation = false,
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

  /// The engine starts both tracks' segment at the start position once their segments are known, instead of
  /// waiting for the player's first request (`RipperSession.prime`). Swift waited; the phone's first open lost
  /// 0.5 s between the headers and AVPlayer's first segment request (build 100).
  final bool primeStart;

  /// A prime also prefetches the segments after it at once, where Swift waited for the first player read to end.
  final bool prefetchOnPrime;

  /// A read that takes over a running prefetch gets its bytes as they arrive; Swift handed them over once the
  /// whole segment was in.
  final bool streamAdopted;

  /// Seek, prime and hint reads race the first [seekBurstBytes] of the range in 64 KiB pieces, each on up to
  /// [seekBurstCopies] nodes at once, and other prefetch waits until that head is in. Swift sent a second copy of
  /// the first piece only after 250-600 ms without a byte.
  final bool seekBurst;
  final int seekBurstBytes;
  final int seekBurstCopies;

  /// Audio goes before video: higher pool priority, [audioReserve] connections video may not take while an audio
  /// read waits, and an audio read under [audioWholeBytes] is one piece raced over the best two nodes. On the phone
  /// an audio segment waited 2.59 s for its first byte behind a video segment (build 100).
  final bool audioFirst;
  final int audioReserve;
  final int audioWholeBytes;

  /// Prefetch looks [prefetchAheadSeconds] of wall time ahead: at 2x that is twice as much of the video, up to
  /// [maxPrefetchRate].
  final bool prefetchFollowsRate;

  /// When set, a track's prefetch cap covers its look-ahead at the stream's own bitrate, between the fixed cap and
  /// this. 8K runs 15-25 MB per 5 s segment, so a fixed 64 MiB covers only about 7 s of wall time at 2x.
  final int? prefetchVideoMaxBytes;
  final int? prefetchAudioMaxBytes;

  /// Cached segments that ended further than this behind the playhead are dropped.
  final double keepBehindSeconds;

  /// Above 0, segments the player has read stay cached, up to this many bytes per track, so a jump back comes
  /// from memory. Swift dropped a segment from the cache once the player read it.
  final int keepBehindBytes;

  /// Off keeps hurried ranges on measured or remembered nodes: unknown and very slow nodes only get backup copies.
  /// Swift let a hurried range try every node.
  final bool exploreInHurry;

  /// The last unfinished piece of a hurried range gets a backup once its copy needs 3x as long as a fresh one would
  /// elsewhere ([HurryPlacement.tailBackupDue]). Swift judged a slow copy only against its own node's usual time.
  final bool tailBackups;

  /// A node banned for silent failures gets a copy now and then, so it can come back ([BanProbation]). Swift kept it
  /// out until the network changed.
  final bool banProbation;

  /// The connection count without AutoConcurrency (Swift's fallback when neither is given).
  static const defaultConcurrency = 16;

  /// [prefetchFollowsRate] scales the look-ahead up to this rate.
  static const maxPrefetchRate = 3.0;

  int get concurrency => fixedConcurrency ?? defaultConcurrency;

  /// [fixedConcurrency] and the max prefetch caps can't be cleared here; build a new config for that.
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
    bool? primeStart,
    bool? prefetchOnPrime,
    bool? streamAdopted,
    bool? seekBurst,
    int? seekBurstBytes,
    int? seekBurstCopies,
    bool? audioFirst,
    int? audioReserve,
    int? audioWholeBytes,
    bool? prefetchFollowsRate,
    int? prefetchVideoMaxBytes,
    int? prefetchAudioMaxBytes,
    double? keepBehindSeconds,
    int? keepBehindBytes,
    bool? exploreInHurry,
    bool? tailBackups,
    bool? banProbation,
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
    primeStart: primeStart ?? this.primeStart,
    prefetchOnPrime: prefetchOnPrime ?? this.prefetchOnPrime,
    streamAdopted: streamAdopted ?? this.streamAdopted,
    seekBurst: seekBurst ?? this.seekBurst,
    seekBurstBytes: seekBurstBytes ?? this.seekBurstBytes,
    seekBurstCopies: seekBurstCopies ?? this.seekBurstCopies,
    audioFirst: audioFirst ?? this.audioFirst,
    audioReserve: audioReserve ?? this.audioReserve,
    audioWholeBytes: audioWholeBytes ?? this.audioWholeBytes,
    prefetchFollowsRate: prefetchFollowsRate ?? this.prefetchFollowsRate,
    prefetchVideoMaxBytes: prefetchVideoMaxBytes ?? this.prefetchVideoMaxBytes,
    prefetchAudioMaxBytes: prefetchAudioMaxBytes ?? this.prefetchAudioMaxBytes,
    keepBehindSeconds: keepBehindSeconds ?? this.keepBehindSeconds,
    keepBehindBytes: keepBehindBytes ?? this.keepBehindBytes,
    exploreInHurry: exploreInHurry ?? this.exploreInHurry,
    tailBackups: tailBackups ?? this.tailBackups,
    banProbation: banProbation ?? this.banProbation,
  );
}
