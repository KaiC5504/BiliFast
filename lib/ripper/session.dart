// One playback in BTR mode: both tracks' resolvers, the shared connection pool, the segment cache and prefetch.
// Port of BiliNative's RipperSession.swift (see LICENSE-BTR.txt), reshaped for a player (mpv) that reads
// whole open-ended byte ranges instead of AVPlayer's one-segment requests.

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'byte_range.dart';
import 'cancel.dart';
import 'engine.dart';
import 'node_catalog.dart';
import 'resolver.dart';
import 'sidx.dart';

enum Track { video, audio }

class TrackSource {
  TrackSource(this.primary, this.backups, this.indexEnd);
  final String primary;
  final List<String> backups;

  /// Last byte of the SIDX: init segment plus index end here.
  final int indexEnd;
}

class SegmentJob {
  SegmentJob(this.segment, this.token, {required this.startup});
  final MediaSegment segment;
  final CancelToken token;
  final bool startup;
  final chunks = <Uint8List>[];
  int bytes = 0;
  bool done = false;
  Object? error;
  int readers = 0;
  double startedAt = nowMs();
  double? finishedAt;
  Completer<void> _signal = Completer<void>();

  Future<void> get changed => _signal.future;

  void _wake() {
    final s = _signal;
    _signal = Completer<void>();
    s.complete();
  }

  void add(Uint8List chunk) {
    chunks.add(chunk);
    bytes += chunk.length;
    _wake();
  }

  void finish([Object? failure]) {
    if (done) return;
    error = failure;
    done = true;
    finishedAt = nowMs();
    _wake();
  }
}

class _TrackState {
  _TrackState(this.source, this.resolver);
  final TrackSource source;
  final Resolver resolver;
  Future<void>? headerLoad;
  Uint8List? header;
  int? total;
  List<MediaSegment> segments = const [];
  final jobs = <int, SegmentJob>{};
  int current = 0;
  CancelToken? reader;
}

class RipperSession {
  RipperSession(Map<Track, TrackSource> sources, HttpClient http, {NodeMode mode = NodeMode.overseas, RipperConfig? config})
      : ctx = EngineContext(http, config ?? RipperConfig()) {
    downloader = RangeDownloader(ctx);
    for (final e in sources.entries) {
      _tracks[e.key] = _TrackState(e.value, Resolver(e.value.primary, e.value.backups, mode, bans));
    }
  }

  final EngineContext ctx;
  final bans = BanList();
  late final RangeDownloader downloader;
  final _tracks = <Track, _TrackState>{};
  final _root = CancelToken();
  double playhead = 0;

  /// Bytes of the cache kept per track; finished segments farthest from the read position go first.
  static const cacheBytes = 96 << 20;
  static const prefetchAheadSeconds = 45.0;

  EngineStats get stats => ctx.stats;
  Map<String, double> nodeSpeeds(Track t) => _tracks[t]!.resolver.nodeSpeeds();

  Future<void> ensureHeaders(Track t) {
    final s = _tracks[t]!;
    return s.headerLoad ??= () async {
      final out = await downloader.meta(ByteRange(0, s.source.indexEnd), s.resolver, _root);
      final total = out.total;
      final segments = parseSidx(out.bytes);
      if (total == null || segments == null) throw const RipperError(RipperErrorKind.badResponse, 206);
      s
        ..header = out.bytes
        ..total = total
        ..segments = segments;
    }()
        .catchError((Object e) {
      s.headerLoad = null;
      throw e;
    });
  }

  Uint8List header(Track t) => _tracks[t]!.header!;
  int total(Track t) => _tracks[t]!.total!;
  List<MediaSegment> segments(Track t) => _tracks[t]!.segments;

  int? segmentAt(Track t, int position) {
    final segs = _tracks[t]!.segments;
    var lo = 0, hi = segs.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final r = segs[mid].range;
      if (position < r.start) {
        hi = mid - 1;
      } else if (position > r.end) {
        lo = mid + 1;
      } else {
        return mid;
      }
    }
    return null;
  }

  /// A new player request on the track supersedes the previous one; mpv opens a new request for every seek.
  CancelToken beginRead(Track t) {
    final s = _tracks[t]!;
    s.reader?.cancel();
    final token = CancelToken(_root);
    s.reader = token;
    return token;
  }

  /// The job for segment `index`, started if needed, with prefetch scheduled behind it.
  SegmentJob segmentForPlayer(Track t, int index) {
    final s = _tracks[t]!;
    final seek = (index - s.current).abs() > 2 || !s.jobs.containsKey(index) && s.jobs.isNotEmpty && index != s.current + 1;
    s.current = index;
    if (seek) _dropOutside(s, index);
    final job = s.jobs[index] ?? _start(t, index, startup: seek || s.jobs.isEmpty);
    _prefetch(t, index);
    _evict(s);
    return job;
  }

  void _dropOutside(_TrackState s, int index) {
    for (final e in s.jobs.entries.toList()) {
      final j = e.value;
      if (!j.done && j.readers == 0 && (e.key < index || e.key > index + 8)) {
        j.token.cancel();
        s.jobs.remove(e.key);
      }
    }
  }

  void _evict(_TrackState s) {
    var held = s.jobs.values.fold<int>(0, (a, j) => a + j.bytes);
    if (held <= cacheBytes) return;
    final finished = s.jobs.entries.where((e) => e.value.done && e.value.readers == 0).toList()
      ..sort((a, b) => (b.key - s.current).abs().compareTo((a.key - s.current).abs()));
    for (final e in finished) {
      if (held <= cacheBytes) break;
      held -= e.value.bytes;
      s.jobs.remove(e.key);
    }
  }

  void _prefetch(Track t, int from) {
    final s = _tracks[t]!;
    final cap = t == Track.video ? ctx.config.prefetchVideoBytes : ctx.config.prefetchAudioBytes;
    var budget = cap;
    for (var i = from + 1; i < s.segments.length && i <= from + 12; i++) {
      if (s.segments[i].startTime - playhead > prefetchAheadSeconds) break;
      final len = s.segments[i].range.length;
      final existing = s.jobs[i];
      if (existing != null) {
        if (!existing.done) budget -= len;
        continue;
      }
      if (len > budget) break;
      budget -= len;
      _start(t, i, startup: false);
    }
  }

  SegmentJob _start(Track t, int index, {required bool startup}) {
    final s = _tracks[t]!;
    final seg = s.segments[index];
    final job = SegmentJob(seg, CancelToken(_root), startup: startup);
    s.jobs[index] = job;
    final segStart = seg.startTime;
    bool hurry() => job.startup || segStart - playhead < 10;
    double priority() => (job.readers > 0 ? 50.0 : 10.0) - max(0, index - s.current) * 0.5;
    downloader
        .run(seg.range, s.resolver,
            startup: startup, hurry: hurry, priority: priority, expectedTotal: s.total, emit: job.add, token: job.token)
        .then((_) => job.finish(), onError: (Object e) {
      job.finish(e);
      if (s.jobs[index] == job) s.jobs.remove(index);
    }).whenComplete(job.token.dispose);
    return job;
  }

  /// For bytes past the last segment (rare): fetched on demand, not cached.
  Future<Uint8List> fetchLoose(Track t, ByteRange range, CancelToken token) async {
    final s = _tracks[t]!;
    final builder = BytesBuilder(copy: false);
    await downloader.run(range, s.resolver,
        startup: true, hurry: () => true, priority: () => 50, expectedTotal: s.total, emit: builder.add, token: token);
    return builder.takeBytes();
  }

  void close() {
    _root.cancel();
    for (final s in _tracks.values) {
      s.jobs.clear();
    }
  }
}
