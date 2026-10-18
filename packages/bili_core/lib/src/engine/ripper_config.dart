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
    this.hurryKeepsOffSlow = false,
    this.emptyLossCounts = false,
    this.seekHurriesPrefetch = false,
    this.trimOnMemoryWarning = false,
    this.peakBandwidth = false,
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

  /// In a hurry a node far slower than the best known one never takes a piece's first copy, even when the fast
  /// nodes are full or carry more than half: the piece waits for a fast node instead. On the phone (1.0.0 (1)) cosov
  /// and the HK nodes ran at 1-2 Mbps against Akamai's 130 and aliov's 23, yet took the first copy of 773 of 3,300
  /// pieces, and 528 of those sat 0.4-0.7 s without a byte before a backup went elsewhere.
  final bool hurryKeepsOffSlow;

  /// A copy outrun before its first byte counts for its node as a first byte at least that late. Without it a node
  /// that never answers in time is never measured as slow (cosov lost 333 races with nothing sent, 665 ms each).
  final bool emptyLossCounts;

  /// A seek onto a segment that prefetch is still fetching turns that fetch into a hurried one. A seek that took
  /// over a slow prefetch waited 4.6 s for a 3.9 MB segment on the phone.
  final bool seekHurriesPrefetch;

  /// A memory warning drops only what is far from the playhead: the segments around it stay. Dropping everything
  /// made the player's next reads download again what it had just played (six warnings in four minutes).
  final bool trimOnMemoryWarning;

  /// The master playlist's BANDWIDTH is the largest segment's bitrate rather than 1.5x the average; AVPlayer logged
  /// "Segment exceeds specified bandwidth for variant" for bigger segments.
  final bool peakBandwidth;

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
    bool? hurryKeepsOffSlow,
    bool? emptyLossCounts,
    bool? seekHurriesPrefetch,
    bool? trimOnMemoryWarning,
    bool? peakBandwidth,
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
    hurryKeepsOffSlow: hurryKeepsOffSlow ?? this.hurryKeepsOffSlow,
    emptyLossCounts: emptyLossCounts ?? this.emptyLossCounts,
    seekHurriesPrefetch: seekHurriesPrefetch ?? this.seekHurriesPrefetch,
    trimOnMemoryWarning: trimOnMemoryWarning ?? this.trimOnMemoryWarning,
    peakBandwidth: peakBandwidth ?? this.peakBandwidth,
  );

  /// Every field by name, for logs and speed test plans.
  Map<String, Object?> toJson() => {
    'firstByteTimeoutMs': firstByteTimeoutMs,
    'stallTimeoutMs': stallTimeoutMs,
    'attemptTimeoutMs': attemptTimeoutMs,
    'hedgeDelayMs': hedgeDelayMs,
    'minChunkBytes': minChunkBytes,
    'pieceRounds': pieceRounds,
    'retryWindowMs': retryWindowMs,
    'fixedConcurrency': fixedConcurrency,
    'prefetchVideoBytes': prefetchVideoBytes,
    'prefetchAudioBytes': prefetchAudioBytes,
    'prefetchAheadSeconds': prefetchAheadSeconds,
    'priority': priority,
    'hurry': hurry,
    'hurryAheadSeconds': hurryAheadSeconds,
    'primeStart': primeStart,
    'prefetchOnPrime': prefetchOnPrime,
    'streamAdopted': streamAdopted,
    'seekBurst': seekBurst,
    'seekBurstBytes': seekBurstBytes,
    'seekBurstCopies': seekBurstCopies,
    'audioFirst': audioFirst,
    'audioReserve': audioReserve,
    'audioWholeBytes': audioWholeBytes,
    'prefetchFollowsRate': prefetchFollowsRate,
    'prefetchVideoMaxBytes': prefetchVideoMaxBytes,
    'prefetchAudioMaxBytes': prefetchAudioMaxBytes,
    'keepBehindSeconds': keepBehindSeconds,
    'keepBehindBytes': keepBehindBytes,
    'exploreInHurry': exploreInHurry,
    'tailBackups': tailBackups,
    'banProbation': banProbation,
    'hurryKeepsOffSlow': hurryKeepsOffSlow,
    'emptyLossCounts': emptyLossCounts,
    'seekHurriesPrefetch': seekHurriesPrefetch,
    'trimOnMemoryWarning': trimOnMemoryWarning,
    'peakBandwidth': peakBandwidth,
  };

  /// This config with fields set by name, as a speed test plan from the PC gives them. A name that is not a field,
  /// or a value of the wrong type, changes nothing and comes back in `rejected`. Null clears a nullable field.
  ({RipperConfig config, List<String> rejected}) withOverrides(Map<String, Object?> overrides) {
    final fields = toJson();
    final rejected = <String>[];
    for (final MapEntry(:key, :value) in overrides.entries) {
      if (!fields.containsKey(key)) {
        rejected.add(key);
        continue;
      }
      final current = fields[key];
      final Object? accepted = switch (value) {
        null when _nullable.contains(key) => null,
        final bool flag when current is bool => flag,
        final num number when _doubles.contains(key) => number.toDouble(),
        final int count when current is int || _nullable.contains(key) => count,
        _ => _rejected,
      };
      if (identical(accepted, _rejected)) {
        rejected.add(key);
      } else {
        fields[key] = accepted;
      }
    }
    return (config: RipperConfig._fromJson(fields), rejected: rejected);
  }

  static const _rejected = Object();

  static const _nullable = {'fixedConcurrency', 'prefetchVideoMaxBytes', 'prefetchAudioMaxBytes'};

  static const _doubles = {
    'firstByteTimeoutMs',
    'stallTimeoutMs',
    'attemptTimeoutMs',
    'hedgeDelayMs',
    'retryWindowMs',
    'prefetchAheadSeconds',
    'priority',
    'hurryAheadSeconds',
    'keepBehindSeconds',
  };

  factory RipperConfig._fromJson(Map<String, Object?> json) => RipperConfig(
    firstByteTimeoutMs: json['firstByteTimeoutMs']! as double,
    stallTimeoutMs: json['stallTimeoutMs']! as double,
    attemptTimeoutMs: json['attemptTimeoutMs']! as double,
    hedgeDelayMs: json['hedgeDelayMs']! as double,
    minChunkBytes: json['minChunkBytes']! as int,
    pieceRounds: json['pieceRounds']! as int,
    retryWindowMs: json['retryWindowMs']! as double,
    fixedConcurrency: json['fixedConcurrency'] as int?,
    prefetchVideoBytes: json['prefetchVideoBytes']! as int,
    prefetchAudioBytes: json['prefetchAudioBytes']! as int,
    prefetchAheadSeconds: json['prefetchAheadSeconds']! as double,
    priority: json['priority']! as double,
    hurry: json['hurry']! as bool,
    hurryAheadSeconds: json['hurryAheadSeconds']! as double,
    primeStart: json['primeStart']! as bool,
    prefetchOnPrime: json['prefetchOnPrime']! as bool,
    streamAdopted: json['streamAdopted']! as bool,
    seekBurst: json['seekBurst']! as bool,
    seekBurstBytes: json['seekBurstBytes']! as int,
    seekBurstCopies: json['seekBurstCopies']! as int,
    audioFirst: json['audioFirst']! as bool,
    audioReserve: json['audioReserve']! as int,
    audioWholeBytes: json['audioWholeBytes']! as int,
    prefetchFollowsRate: json['prefetchFollowsRate']! as bool,
    prefetchVideoMaxBytes: json['prefetchVideoMaxBytes'] as int?,
    prefetchAudioMaxBytes: json['prefetchAudioMaxBytes'] as int?,
    keepBehindSeconds: json['keepBehindSeconds']! as double,
    keepBehindBytes: json['keepBehindBytes']! as int,
    exploreInHurry: json['exploreInHurry']! as bool,
    tailBackups: json['tailBackups']! as bool,
    banProbation: json['banProbation']! as bool,
    hurryKeepsOffSlow: json['hurryKeepsOffSlow']! as bool,
    emptyLossCounts: json['emptyLossCounts']! as bool,
    seekHurriesPrefetch: json['seekHurriesPrefetch']! as bool,
    trimOnMemoryWarning: json['trimOnMemoryWarning']! as bool,
    peakBandwidth: json['peakBandwidth']! as bool,
  );
}
