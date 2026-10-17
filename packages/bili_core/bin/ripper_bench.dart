// The Dart counterpart of BiliNative's ripper-bench (Sources/ripper-bench/Bench.swift): the same flags and output
// lines, so a run here compares line for line with a Swift one. Only the saved-playurl mode: it never calls
// Bilibili's API.
//
//   cd packages/bili_core
//   fvm dart run bili_core:ripper_bench --playurl saved-playurl.json [--mb 16] [--mode overseas|mainland]
//       [--quality 80] [--codec hevc|av1|avc] [--seeks N] [--no-hurry] [--repeat N]
//
// Without --seeks it downloads the start of the video twice, over one connection and through Ripper. --seeks N times
// N cold 4 MiB reads at seeded random offsets instead; --no-hurry turns hurry mode off for that run (and for the
// Ripper half of the comparison). --repeat N runs the measurement N times and adds the median: seek runs continue the
// seeded sequence, so the first run reads Swift's offsets and later runs fresh, still cold ones, while comparison runs
// read the same bytes and so meet a warm CDN after the first.

import 'dart:io';
import 'dart:math';

import 'package:bili_core/api.dart';
import 'package:bili_core/dash_hls.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';

Future<void> main(List<String> arguments) async {
  var code = 0;
  try {
    await Bench(BenchOptions.parse(arguments), say: stdout.writeln).run();
  } catch (error) {
    stderr.writeln(errorLine(error));
    code = 1;
  }
  await Future.wait([stdout.flush(), stderr.flush()]);
  // A cancelled piece can leave a timer or socket behind for a while; the bench is done either way.
  exit(code);
}

/// Transport errors can carry the failing signed URL.
String errorLine(Object error) => 'error: ${Redactor.text('$error')}';

final class UsageError implements Exception {
  const UsageError([this.reason]);

  final String? reason;

  @override
  String toString() => reason == null ? BenchOptions.usage : '$reason\n${BenchOptions.usage}';
}

final class BenchOptions {
  const BenchOptions({
    required this.playurl,
    this.megabytes = 16,
    this.mode = NodeMode.overseas,
    this.quality = 80,
    this.codec = VideoCodec.hevc,
    this.seeks = 0,
    this.hurry = true,
    this.repeat = 1,
  });

  static const usage =
      'usage: ripper_bench --playurl file.json [--mb 16] [--mode overseas|mainland] [--quality 80] '
      '[--codec hevc|av1|avc] [--seeks N] [--no-hurry] [--repeat N]';

  final String playurl;
  final int megabytes;
  final NodeMode mode;
  final int quality;
  final VideoCodec codec;
  final int seeks;
  final bool hurry;
  final int repeat;

  /// As lenient as Swift's: an unreadable --mb or --quality keeps its default, an unknown codec is HEVC and any mode
  /// but mainland is overseas. A count that is not positive is a usage error.
  static BenchOptions parse(List<String> arguments) {
    String? playurl;
    var megabytes = 16;
    NodeMode mode = NodeMode.overseas;
    var quality = 80;
    var codec = VideoCodec.hevc;
    var seeks = 0;
    var hurry = true;
    var repeat = 1;
    int count(String value) {
      final parsed = int.tryParse(value);
      if (parsed == null || parsed < 1) throw const UsageError();
      return parsed;
    }

    final iterator = arguments.iterator;
    while (iterator.moveNext()) {
      final flag = iterator.current;
      if (flag == '--no-hurry') {
        hurry = false;
        continue;
      }
      if (flag == '--bv' || flag == '--cookies') {
        throw const UsageError('the Dart bench only reads a saved playurl: it never calls Bilibili\'s API');
      }
      if (!iterator.moveNext()) throw const UsageError();
      final value = iterator.current;
      switch (flag) {
        case '--playurl':
          playurl = value;
        case '--mb':
          megabytes = int.tryParse(value) ?? 16;
          if (megabytes < 1) throw const UsageError();
        case '--mode':
          mode = value == 'mainland' ? NodeMode.mainland : NodeMode.overseas;
        case '--quality':
          quality = int.tryParse(value) ?? 80;
        case '--codec':
          codec = VideoCodec.values.asNameMap()[value] ?? VideoCodec.hevc;
        case '--seeks':
          seeks = count(value);
        case '--repeat':
          repeat = count(value);
        default:
          throw const UsageError();
      }
    }
    if (playurl == null) throw const UsageError();
    return BenchOptions(
      playurl: playurl,
      megabytes: megabytes,
      mode: mode,
      quality: quality,
      codec: codec,
      seeks: seeks,
      hurry: hurry,
      repeat: repeat,
    );
  }
}

/// Bench.swift's `SeededGenerator` (SplitMix64), on Dart's wrapping 64-bit ints.
final class SeededGenerator {
  SeededGenerator(this._state);

  int _state;

  static final _mask64 = (BigInt.one << 64) - BigInt.one;

  int next() {
    _state += 0x9E3779B97F4A7C15;
    var z = _state;
    z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9;
    z = (z ^ (z >>> 27)) * 0x94D049BB133111EB;
    return z ^ (z >>> 31);
  }

  /// Swift's `Int64.random(in: low...high, using:)`, which draws with Lemire's nearly divisionless method, so a seed
  /// picks the same offsets in both benches.
  int nextInRange(int low, int high) {
    final delta = BigInt.from(high - low).toUnsigned(64);
    if (delta == _mask64) return next();
    final bound = delta + BigInt.one;
    BigInt draw() => BigInt.from(next()).toUnsigned(64) * bound;
    var product = draw();
    if ((product & _mask64) < bound) {
      final threshold = (_mask64 + BigInt.one - bound) % bound;
      while ((product & _mask64) < threshold) {
        product = draw();
      }
    }
    return low + (product >> 64).toSigned(64).toInt();
  }
}

typedef ColdSeek = ({int offset, MediaSegment segment, ByteRange range});

const seekBytes = 4 << 20;

/// Where cold seeks may land: from 5% into the file to 2 MiB before its end.
(int, int) coldSeekSpan(int total) {
  final low = total ~/ 20;
  final high = total - (2 << 20);
  if (high <= low) throw const BiliError.decoding('video too small for cold seeks');
  return (low, high);
}

/// The next [count] cold seeks. Each offset snaps back to its segment's start, because the player asks for segments.
List<ColdSeek> coldSeekPlan(
  List<MediaSegment> segments, {
  required int total,
  required int count,
  required SeededGenerator generator,
}) {
  final (low, high) = coldSeekSpan(total);
  return [for (var number = 0; number < count; number++) _seekAt(segments, generator.nextInRange(low, high), total)];
}

ColdSeek _seekAt(List<MediaSegment> segments, int offset, int total) {
  final segment = segments.lastWhere((segment) => segment.range.start <= offset, orElse: () => segments.first);
  final start = segment.range.start;
  return (offset: offset, segment: segment, range: ByteRange(start, min(start + seekBytes, total) - 1));
}

double? median(List<double> values) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

String mib(int bytes) => (bytes / 1048576).toStringAsFixed(1);

String _f2(double value) => value.toStringAsFixed(2);

double _megabytesPerSecond(int bytes, double seconds) => bytes / 1048576 / max(seconds, 0.001);

String _rate(int bytes, double seconds) => '${_f2(_megabytesPerSecond(bytes, seconds))} MB/s';

double _seconds(Stopwatch clock) => clock.elapsedMicroseconds / 1e6;

final class _Session {
  _Session(this.session, this.transport);

  final RipperSession session;
  final RangeTransport transport;

  void close() {
    session.close();
    transport.close();
  }
}

final class Bench {
  Bench(this.options, {required this.say, this.policy = MediaURLPolicy.bilibili});

  static const seed = 17;

  /// URLSession's default request timeout, which the Swift bench runs under: a silent node ends the run instead of
  /// hanging it.
  static const _requestTimeout = Duration(seconds: 60);

  final BenchOptions options;
  final void Function(String line) say;

  /// Bilibili's media hosts only; a loopback run allows any address.
  final MediaURLPolicy policy;

  static Future<PlayURLInfo> loadPlayURL(String path) async {
    final envelope = BiliEnvelope.parse(await File(path).readAsString(), PlayURLInfo.fromJson);
    final info = envelope.data;
    if (info == null) throw BiliError.api(code: envelope.code, message: envelope.message ?? '');
    return info;
  }

  static DashStream chooseVideo(PlayURLInfo info, {required int quality, required VideoCodec codec}) {
    final dash = info.dash;
    final codecOrder = [codec, VideoCodec.hevc, VideoCodec.avc, VideoCodec.av1];
    final choice = dash == null ? null : TrackSelector.choose(dash, quality: quality, codecOrder: codecOrder);
    if (choice == null) throw BiliError.notDash;
    return choice.video;
  }

  static String describe(DashStream video) =>
      'video ${video.id} ${video.codecs} ${video.width}x${video.height} '
      '${video.bandwidth ~/ 1000} kbps on ${NodeCatalog.nodeKey(video.baseURL)}';

  Future<void> run() async {
    final info = await loadPlayURL(options.playurl);
    final video = chooseVideo(info, quality: options.quality, codec: options.codec);
    say(describe(video));
    final runs = options.repeat;
    if (options.seeks > 0) {
      final generator = SeededGenerator(seed);
      final firsts = <double>[];
      final wholes = <double>[];
      for (var run = 1; run <= runs; run++) {
        if (runs > 1) say('run $run of $runs');
        final medians = await coldSeeks(video, generator);
        if (medians == null) continue;
        firsts.add(medians.firstMiB);
        wholes.add(medians.whole);
      }
      if (runs == 1) return;
      final first = median(firsts);
      final whole = median(wholes);
      if (first == null || whole == null) {
        say('no run finished a seek');
        return;
      }
      say('median first MiB over ${firsts.length} of $runs runs: ${_f2(first)} s (median of the runs\' medians)');
      say('median ${mib(seekBytes)} MiB over ${wholes.length} of $runs runs: ${_f2(whole)} s');
      return;
    }
    final singles = <double>[];
    final rippers = <double>[];
    for (var run = 1; run <= runs; run++) {
      if (runs > 1) say('run $run of $runs');
      final rates = await compare(video);
      if (rates.single case final single?) singles.add(single);
      rippers.add(rates.ripper);
    }
    if (runs == 1) return;
    final single = median(singles);
    say(
      'median one connection over ${singles.length} of $runs runs: '
      '${single == null ? '-' : '${_f2(single)} MB/s'} (truncated or refused runs left out)',
    );
    say('median ripper over $runs runs: ${_f2(median(rippers)!)} MB/s');
  }

  _Session _open(DashStream video) {
    final transport = IoRangeTransport(headers: BiliClient.mediaHeaders, connectionsPerHost: 8);
    final session = RipperSession(
      sources: {TrackKind.video: (primary: video.baseURL, backups: video.backupURLs)},
      mode: options.mode,
      transport: transport,
      auto: AutoConcurrency(),
      config: RipperConfig(hurry: options.hurry),
      policy: policy,
    );
    return _Session(session, transport);
  }

  /// The first of the primary and backup URLs that answers a small probe with 206; some accounts get 403 from the
  /// primary node while a backup works. Probed on a throwaway client so the timed run starts cold.
  Future<({String url, String label})?> baselineURL(DashStream video) async {
    final probe = IoRangeTransport(headers: BiliClient.mediaHeaders);
    try {
      for (final (index, candidate) in [video.baseURL, ...video.backupURLs].indexed) {
        final label = index == 0 ? 'primary' : 'backup $index';
        final node = NodeCatalog.nodeKey(candidate);
        final url = Uri.tryParse(candidate);
        if (url == null) continue;
        try {
          final answer = await probe.fetch(url, ByteRange(0, 1023)).timeout(_requestTimeout);
          if (answer.status == 206) {
            await answer.body.timeout(_requestTimeout).drain<void>();
            return (url: candidate, label: label);
          }
          await answer.body.listen(null).cancel();
          say('baseline probe: $label on $node answered HTTP ${answer.status}');
        } catch (error) {
          say('baseline probe: $label on $node failed: ${Redactor.text('$error')}');
        }
      }
      return null;
    } finally {
      probe.close();
    }
  }

  /// One plain connection, then Ripper, over the first `--mb` MiB after the index. The rates come back in MB/s; the
  /// single one is null when it is not comparable (no URL answered, or the node cut the response).
  Future<({double? single, double ripper})> compare(DashStream video) async {
    final target = options.megabytes << 20;
    final singleRange = ByteRange(video.indexRange.end + 1, video.indexRange.end + target);
    var singleBytes = 0;
    var singleStatus = 0;
    var singleSeconds = 0.0;
    var singleSource = 'no URL answered 206';
    String? singleCut;
    final chosen = await baselineURL(video);
    if (chosen != null) {
      singleSource = '${chosen.label} on ${NodeCatalog.nodeKey(chosen.url)}';
      // Each run gets its own client so neither starts with the other's warm connections.
      final transport = IoRangeTransport(headers: BiliClient.mediaHeaders);
      try {
        final clock = Stopwatch()..start();
        final response = await transport.fetch(Uri.parse(chosen.url), singleRange).timeout(_requestTimeout);
        singleStatus = response.status;
        if (response.status == 206) {
          // Some nodes close a long single response early; report that and still run Ripper.
          try {
            await for (final chunk in response.body.timeout(_requestTimeout)) {
              singleBytes += chunk.length;
            }
          } catch (error) {
            singleCut = Redactor.text('$error');
          }
        } else {
          await response.body.listen(null).cancel();
        }
        singleSeconds = _seconds(clock);
      } finally {
        transport.close();
      }
    }

    final ripper = _open(video);
    final int rippedBytes;
    final double rippedSeconds;
    final EngineSnapshot stats;
    try {
      final clock = Stopwatch()..start();
      final headers = await ripper.session.loadHeaders(TrackKind.video, through: video.indexRange.end);
      final segments = SidxParser.parse(headers.bytes, absoluteStart: 0);
      if (segments == null) throw const BiliError.decoding('no sidx');
      ripper.session.setSegments(TrackKind.video, segments);
      var bytes = 0;
      for (final segment in segments) {
        if (bytes >= target) break;
        await for (final chunk in ripper.session.read(TrackKind.video, segment.range)) {
          bytes += chunk.length;
        }
        ripper.session.updatePlayhead(seconds: segment.startTime, rate: 1);
      }
      rippedSeconds = _seconds(clock);
      rippedBytes = bytes;
      stats = ripper.session.stats();
    } finally {
      ripper.close();
    }

    final cut = singleCut == null
        ? ''
        : ' (truncated after $singleBytes bytes: ${singleCut.substring(0, min(160, singleCut.length))}; '
              'rate is up to the cut, not comparable)';
    say(
      'one connection: $singleBytes bytes in ${_f2(singleSeconds)} s = ${_rate(singleBytes, singleSeconds)} '
      '(HTTP $singleStatus, $singleSource)$cut',
    );
    say('ripper:         $rippedBytes bytes in ${_f2(rippedSeconds)} s = ${_rate(rippedBytes, rippedSeconds)}');
    say(
      'connections ${stats.concurrency}, requests ${stats.requests}, failures ${stats.failures}, '
      'duplicate ${(stats.duplicateShare * 100).toStringAsFixed(1)}%',
    );
    for (final node in stats.nodes) {
      // One entry per address on the node (e.g. a refused os=cosovbv next to a serving os=akam): show the best.
      final states = stats.nodeStates.where((state) => state.node == node.node).toList();
      final best = NodeStatus.best(node.node, states);
      final all = states.length > 1 ? ' (addresses: ${states.map((state) => state.state).join(', ')})' : '';
      say(
        '  ${node.node}: ${node.requests} req, ${node.failures} failed, first byte ${node.firstByteMs.toInt()} ms, '
        '${best == null ? '-' : _rate(best.bps.toInt(), 1)} per connection, ${best?.state ?? '-'}$all',
      );
    }
    final comparable = chosen != null && singleStatus == 206 && singleCut == null;
    return (
      single: comparable ? _megabytesPerSecond(singleBytes, singleSeconds) : null,
      ripper: _megabytesPerSecond(rippedBytes, rippedSeconds),
    );
  }

  /// Reads 4 MiB at the next seeded offsets, each through a new session so every read starts cold, the way a seek
  /// into unloaded video does. The playhead is put at the segment too, so the read is due immediately. Returns the
  /// medians, or null when no seek finished.
  Future<({double firstMiB, double whole})?> coldSeeks(DashStream video, SeededGenerator generator) async {
    final probe = _open(video);
    final TrackHeaders headers;
    try {
      headers = await probe.session.loadHeaders(TrackKind.video, through: video.indexRange.end);
    } finally {
      probe.close();
    }
    final segments = SidxParser.parse(headers.bytes, absoluteStart: 0);
    if (segments == null || segments.isEmpty) throw const BiliError.decoding('no sidx');
    final total = headers.totalSize;
    final (low, high) = coldSeekSpan(total);
    say(
      'cold seeks: ${options.seeks} x ${mib(seekBytes)} MiB, seed $seed, hurry ${options.hurry ? 'on' : 'off'}, '
      'offsets ${mib(low)}-${mib(high)} MiB of ${mib(total)}',
    );

    final plan = coldSeekPlan(segments, total: total, count: options.seeks, generator: generator);
    final firstMiB = <double>[];
    final whole = <double>[];
    for (final (index, seek) in plan.indexed) {
      final label = 'seek ${index + 1}/${options.seeks} at ${mib(seek.range.start)} MiB';
      final cold = _open(video);
      try {
        await cold.session.loadHeaders(TrackKind.video, through: video.indexRange.end);
        cold.session
          ..setSegments(TrackKind.video, segments)
          ..updatePlayhead(seconds: seek.segment.startTime, rate: 1);
        final clock = Stopwatch()..start();
        var bytes = 0;
        double? toFirstMiB;
        await for (final chunk in cold.session.read(TrackKind.video, seek.range)) {
          bytes += chunk.length;
          if (toFirstMiB == null && bytes >= 1 << 20) toFirstMiB = _seconds(clock);
        }
        final elapsed = _seconds(clock);
        final stats = cold.session.stats();
        if (bytes != seek.range.length || toFirstMiB == null) {
          say('$label: short read, $bytes of ${seek.range.length} bytes after ${_f2(elapsed)} s');
          continue;
        }
        firstMiB.add(toFirstMiB);
        whole.add(elapsed);
        say(
          '$label: first MiB ${_f2(toFirstMiB)} s, ${mib(bytes)} MiB ${_f2(elapsed)} s '
          '(connections ${stats.concurrency}, requests ${stats.requests}, failures ${stats.failures}, '
          'duplicate ${(stats.duplicateShare * 100).toStringAsFixed(1)}%)',
        );
      } catch (error) {
        say('$label: failed: ${Redactor.text('$error')}');
      } finally {
        cold.close();
      }
    }
    final firstMedian = median(firstMiB);
    final wholeMedian = median(whole);
    if (firstMedian == null || wholeMedian == null) {
      say('no seek finished');
      return null;
    }
    say('median first MiB: ${_f2(firstMedian)} s over ${firstMiB.length} of ${options.seeks} seeks');
    say('median ${mib(seekBytes)} MiB: ${_f2(wholeMedian)} s over ${whole.length} of ${options.seeks} seeks');
    return (firstMiB: firstMedian, whole: wholeMedian);
  }
}
