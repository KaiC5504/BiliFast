enum StepKind { first, tap, hint, back }

final class StepResult {
  const StepResult({required this.kind, required this.to, required this.ms, required this.timedOut});

  final StepKind kind;
  final double to;

  /// A step that timed out counts as the whole timeout, so a variant can't look faster by never resuming.
  final double ms;
  final bool timedOut;
}

/// One pass as it ran; filled in by the runner.
final class PassResult {
  PassResult({
    required this.pass,
    required this.variant,
    required this.askedQuality,
    required this.bvid,
    required this.seed,
    this.cold = false,
  }) : quality = askedQuality;

  final int pass;
  final String variant;
  final int askedQuality;
  String bvid;
  final int seed;

  /// The first pass on its video at its quality (`SpeedTestPass.cold`).
  final bool cold;

  /// What played; [askedQuality] until the stream is chosen.
  int quality;
  String codec = '';
  double? firstFrameMs;
  final List<StepResult> steps = [];
  int stalls = 0;
  int fastStalls = 0;
  int memoryWarnings = 0;
  int rssMaxBytes = 0;
  bool skipped = false;
  bool failed = false;

  /// Why it failed, for the page.
  String? failure;

  bool get counts => !skipped && !failed;

  List<double> msOf(StepKind kind) => [
        for (final step in steps)
          if (step.kind == kind) step.ms,
      ];

  int get timeouts => steps.where((step) => step.kind != StepKind.first && step.timedOut).length;

  void noteRss(int bytes) {
    if (bytes > rssMaxBytes) rssMaxBytes = bytes;
  }
}

/// Every counted pass of one variant at one played quality, cold or warm, pooled.
final class GroupSummary {
  GroupSummary({required this.variant, required this.quality, this.cold = false, required List<PassResult> passes})
      : passes = passes.length,
        firstFrameMs = median([for (final pass in passes) ?pass.firstFrameMs]),
        seekMedianMs = median(_pooled(passes, StepKind.tap)),
        seekP90Ms = p90(_pooled(passes, StepKind.tap)),
        seekMaxMs = _max(_pooled(passes, StepKind.tap)),
        hintMedianMs = median(_pooled(passes, StepKind.hint)),
        backMedianMs = median(_pooled(passes, StepKind.back)),
        timeouts = passes.fold(0, (sum, pass) => sum + pass.timeouts),
        stalls = passes.fold(0, (sum, pass) => sum + pass.stalls),
        fastStalls = passes.fold(0, (sum, pass) => sum + pass.fastStalls),
        memoryWarnings = passes.fold(0, (sum, pass) => sum + pass.memoryWarnings),
        rssMaxMB = passes.fold(0, (most, pass) => pass.rssMaxBytes > most ? pass.rssMaxBytes : most) ~/ (1024 * 1024);

  final String variant;
  final int quality;
  final bool cold;
  final int passes;
  final double? firstFrameMs;
  final double? seekMedianMs;
  final double? seekP90Ms;
  final double? seekMaxMs;
  final double? hintMedianMs;
  final double? backMedianMs;
  final int timeouts;
  final int stalls;
  final int fastStalls;
  final int memoryWarnings;
  final int rssMaxMB;

  /// In the order the variants first ran, then by quality, highest first, cold before warm.
  static List<GroupSummary> of(List<PassResult> results) {
    final variants = <String>[];
    final grouped = <(String, int, bool), List<PassResult>>{};
    for (final pass in results.where((pass) => pass.counts)) {
      if (!variants.contains(pass.variant)) variants.add(pass.variant);
      grouped.putIfAbsent((pass.variant, pass.quality, pass.cold), () => []).add(pass);
    }
    final keys = grouped.keys.toList()
      ..sort((a, b) {
        final byVariant = variants.indexOf(a.$1).compareTo(variants.indexOf(b.$1));
        if (byVariant != 0) return byVariant;
        final byQuality = b.$2.compareTo(a.$2);
        return byQuality != 0 ? byQuality : (a.$3 == b.$3 ? 0 : (a.$3 ? -1 : 1));
      });
    return [
      for (final key in keys) GroupSummary(variant: key.$1, quality: key.$2, cold: key.$3, passes: grouped[key]!),
    ];
  }

  static List<double> _pooled(List<PassResult> passes, StepKind kind) =>
      [for (final pass in passes) ...pass.msOf(kind)];
}

/// [other] minus [base] at the same quality, cold or warm alike, where both have a number.
final class GroupDelta {
  GroupDelta(this.base, this.other)
      : firstFrameMs = _minus(other.firstFrameMs, base.firstFrameMs),
        seekMedianMs = _minus(other.seekMedianMs, base.seekMedianMs),
        seekP90Ms = _minus(other.seekP90Ms, base.seekP90Ms),
        seekMaxMs = _minus(other.seekMaxMs, base.seekMaxMs),
        backMedianMs = _minus(other.backMedianMs, base.backMedianMs),
        stalls = other.stalls - base.stalls,
        rssMaxMB = other.rssMaxMB - base.rssMaxMB;

  final GroupSummary base;
  final GroupSummary other;
  final double? firstFrameMs;
  final double? seekMedianMs;
  final double? seekP90Ms;
  final double? seekMaxMs;
  final double? backMedianMs;
  final int stalls;
  final int rssMaxMB;

  /// Every later variant against the first one, per quality.
  static List<GroupDelta> of(List<GroupSummary> groups) {
    if (groups.isEmpty) return const [];
    final first = groups.first.variant;
    return [
      for (final group in groups)
        if (group.variant != first)
          for (final base in groups)
            if (base.variant == first && base.quality == group.quality && base.cold == group.cold)
              GroupDelta(base, group),
    ];
  }

  static double? _minus(double? a, double? b) => a == null || b == null ? null : a - b;
}

double? median(List<double> values) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

/// Nearest rank, so it is always a value that happened.
double? p90(List<double> values) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  return sorted[(sorted.length * 0.9).ceil() - 1];
}

double? _max(List<double> values) => values.isEmpty ? null : values.reduce((a, b) => a > b ? a : b);
