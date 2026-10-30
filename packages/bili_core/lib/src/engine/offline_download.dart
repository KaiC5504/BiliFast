import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';

import '../devlog/log_event.dart';
import '../devlog/logger.dart';
import '../shared/byte_range.dart';
import '../shared/clock.dart';
import 'attempt.dart';
import 'auto_concurrency.dart';
import 'ban_list.dart';
import 'cancel.dart';
import 'connection_pool.dart';
import 'node_catalog.dart';
import 'node_memory.dart';
import 'offline_ranges.dart';
import 'offline_types.dart';
import 'piece_downloader.dart';
import 'playback_engine.dart';
import 'range_downloader.dart';
import 'resolver.dart';
import 'ripper_config.dart';
import 'transport.dart';

/// The engine isolate's offline downloads (离线缓存): whole DASH files over the engine's nodes, written to disk and
/// resumable from `.ranges`. Every event goes to [emit].
///
/// Each part's two tracks are cut into pieces of [pieceBytes] on a fixed grid, fetched across the nodes as prefetch
/// pieces are (placement, hedged copies, bans, retry rounds) and written at their offsets into `.part`. Downloads
/// keep out of a playing video's way by a smaller connection share: they have one pool of [connections] among them
/// all, apart from the 16 or more each playback starts with, and on an HTTP/1.1 node (Akamai) they take at most half
/// of the transport's connections.
final class OfflineDownloads {
  OfflineDownloads({
    required this.transport,
    required this.auto,
    required this.mode,
    required this.config,
    required this.policy,
    required this.emit,
    this.memory,
    this.connections = defaultConnections,
    this.pieceBytes = defaultPieceBytes,
    this.progressInterval = const Duration(seconds: 1),
    this.flushInterval = const Duration(seconds: 2),
    this.networkTimeout = const Duration(seconds: 20),
    MonotonicClock? clock,
    Logger? logger,
  }) : _clock = clock ?? MonotonicClock.system,
       _logger = logger ?? Logger.shared;

  static const defaultConnections = 6;
  static const defaultPieceBytes = 2 << 20;

  final RangeTransport transport;

  /// Hears the CDN's 412 and 429: they are aimed at the whole app. Downloads don't otherwise drive it.
  final AutoConcurrency auto;

  /// The CDN 节点 as set now.
  final NodeMode Function() mode;
  final RipperConfig config;
  final MediaURLPolicy policy;
  final NodeMemory? memory;
  final void Function(DownloadEvent event) emit;
  final int connections;
  final int pieceBytes;
  final Duration progressInterval;

  /// How often a running download writes its `.ranges`, besides when it stops.
  final Duration flushInterval;

  /// A download whose every request fails for this long fails with [DownloadFailure.network].
  final Duration networkTimeout;
  final MonotonicClock _clock;
  final Logger _logger;

  /// Pieces of one download started and not yet ended: twice the pool, so one download alone keeps every
  /// connection busy while the others queue.
  int get _window => connections * 2;

  /// Pieces are placed a few at a time, as a range's are, so a node not measured yet gets its trial piece.
  static const _batch = 4;

  /// A piece's backup copy goes out once the first is late to its first byte, stalls, or would take longer than this
  /// to finish (`PieceDownloader.hedgeDue`). Without a deadline every piece still running after the hedge delay would
  /// be fetched twice.
  static const _horizonMs = 6000.0;
  static const _priority = 10.0;
  static const _rateWindowMs = 3000.0;
  static const _retryPauseMs = 1000.0;

  final _downloads = <String, _Download>{};

  /// Fresh addresses for a download that isn't running, used by its next start.
  final _replaced = <String, Map<TrackKind, ({String primary, List<String> backups})>>{};
  Timer? _ticker;
  bool _disposed = false;

  late final EngineContext _ctx = () {
    final ctx = EngineContext(
      transport: _Share(transport, auto),
      pool: ConnectionPool(connections, clock: _clock),
      config: config,
      clock: _clock,
      logger: _logger,
    );
    ctx.nodes
      ..priors = memory?.priors ?? NodePriors.empty
      ..onMeasured = memory?.record
      ..exploreInHurry = config.exploreInHurry
      ..tailBackups = config.tailBackups
      ..keepsOffSlow = config.hurryKeepsOffSlow
      ..median = config.medianEstimates;
    return ctx;
  }();
  late final _downloader = RangeDownloader(_ctx);

  /// Starts or resumes [request]; returns once it runs. A request already running is left as it is.
  Future<void> start(DownloadRequest request) async {
    final id = request.id;
    final current = _downloads[id];
    if (current != null) {
      // One stopping or failing is about to let go of its files; the new start waits for that.
      if (!current.ending) return;
      await current.ended.future;
      if (_downloads.containsKey(id)) return;
    }
    if (_disposed) return;
    final download = _create(request);
    _downloads[id] = download;
    var folded = 0;
    try {
      for (final track in download.tracks.values) {
        folded += await _prepare(track);
      }
    } catch (error) {
      _fail(download, DownloadFailure.disk, detail: _describe(error));
      await _end(download);
      return;
    }
    if (download.ending) {
      await _end(download);
      return;
    }
    final now = _clock.nowMs();
    download
      ..running = true
      ..flushedAt = now
      ..samples.add((at: now, bytes: 0));
    _logger.info(LogCategory.engine, 'download started', {
      'id': id,
      'videoTotal': download.video.total,
      'audioTotal': download.audio.total,
      'have': download.have,
      'folded': folded,
    });
    _emitProgress(download, now);
    _ticker ??= Timer.periodic(progressInterval, (_) => _tick());
    unawaited(_run(download));
  }

  /// Stops [id] at once, flushes what it wrote and reports what is missing. An unknown id reports the gaps on disk
  /// for nothing: both lists empty, totals 0.
  ///
  /// A track whose total isn't known yet reports no gaps and a total of 0, as does one whose total changed.
  Future<DownloadGaps> stop(String id) async {
    final download = _downloads[id];
    if (download == null) return DownloadGaps(id: id, video: const [], audio: const [], videoTotal: 0, audioTotal: 0);
    download.stopping = true;
    download.cancel.cancel();
    await download.ended.future;
    return DownloadGaps(
      id: id,
      video: _gaps(download.video),
      audio: _gaps(download.audio),
      videoTotal: download.video.total,
      audioTotal: download.audio.total,
    );
  }

  void replaceUrls(String id, TrackKind track, {required String primary, required List<String> backups}) {
    final download = _downloads[id];
    final live = download != null && !download.ending;
    if (live) {
      download.tracks[track]!.resolver.replaceURLs(primary: primary, backups: backups);
    } else {
      (_replaced[id] ??= {})[track] = (primary: primary, backups: backups);
    }
    _logger.info(LogCategory.engine, 'download urls replaced', {'id': id, 'track': track.name, 'running': live});
  }

  /// As a playback's: bans, backoffs and damage from the old path are dropped, with a different interface the
  /// speeds too, and the network clock starts again.
  void networkChanged({required bool interfaceChanged}) {
    if (_downloads.isEmpty) return;
    final now = _clock.nowMs();
    for (final download in _downloads.values) {
      download.bans.reset();
      for (final track in download.tracks.values) {
        track.resolver.resetHealth(clearMeasurements: interfaceChanged);
      }
      download.lastSuccessAt = now;
    }
    _ctx.nodes.reset();
  }

  /// Running downloads, for the engine's own bookkeeping.
  Iterable<String> get running => [
    for (final download in _downloads.values)
      if (!download.ending) download.id,
  ];

  Future<void> dispose() async {
    _disposed = true;
    final downloads = _downloads.values.toList();
    for (final download in downloads) {
      download.stopping = true;
      download.cancel.cancel();
    }
    await Future.wait([for (final download in downloads) download.ended.future]);
    _ticker?.cancel();
    _ticker = null;
    _replaced.clear();
  }

  _Download _create(DownloadRequest request) {
    final urls = _replaced.remove(request.id) ?? const {};
    final nodeMode = mode();
    final bans = BanList();
    if (config.banProbation) bans.probation = BanProbation(clock: _clock);
    bans.onBan = (node, strikes, kind) => _logger.warn(LogCategory.engine, 'download ban', {
      'id': request.id,
      'node': node,
      'strikes': strikes,
      'kind': kind.name,
    });
    final priors = memory?.priors ?? NodePriors.empty;
    _Track track(TrackKind kind) {
      final spec = request.track(kind);
      final fresh = urls[kind];
      return _Track(
        kind,
        spec,
        Resolver(
          primary: fresh?.primary ?? spec.primary,
          backups: fresh?.backups ?? spec.backups,
          mode: nodeMode,
          policy: policy,
          bans: bans,
          clock: _clock,
          priors: priors,
          exploreInHurry: config.exploreInHurry,
        ),
      );
    }

    return _Download(
      request.id,
      {for (final kind in TrackKind.values) kind: track(kind)},
      bans,
      startedAt: _clock.nowMs(),
    );
  }

  /// Reads what the track has on disk and opens its part. Returns the bytes folded in from `.bg-ranges`.
  Future<int> _prepare(_Track track) async {
    final requested = track.spec.totalSize;
    final complete = File(track.spec.path);
    final part = File(track.part);
    if (!await part.exists() && await complete.exists()) {
      final length = await complete.length();
      if (length > 0 && (requested <= 0 || length == requested)) {
        track
          ..total = length
          ..done = [ByteRange(0, length - 1)]
          ..have = length
          ..finished = true;
        await _delete([track.ranges, track.background]);
        return 0;
      }
      _logger.warn(LogCategory.engine, 'download file dropped', {'track': track.kind.name, 'bytes': length});
      await complete.delete();
    }
    var total = requested;
    var done = <ByteRange>[];
    var rewrite = false;
    final record = await RangesRecord.read(track.ranges);
    if (record != null) {
      if (total > 0 && record.total > 0 && record.total != total) {
        _logger.warn(LogCategory.engine, 'download ranges dropped', {'track': track.kind.name, 'total': record.total});
        rewrite = true;
      } else {
        if (total <= 0) total = record.total;
        done = record.done;
      }
    }
    var folded = 0;
    final hadBackground = await File(track.background).exists();
    final background = hadBackground ? await RangesRecord.read(track.background) : null;
    if (hadBackground) rewrite = true;
    if (background != null) {
      if (total > 0 && background.total > 0 && background.total != total) {
        _logger.warn(LogCategory.engine, 'download background ranges dropped', {
          'track': track.kind.name,
          'total': background.total,
        });
      } else {
        if (total <= 0) total = background.total;
        final before = coveredBytes(done);
        done = mergeRanges([...done, ...background.done]);
        folded = coveredBytes(done) - before;
      }
    }
    if (total > 0) done = clipRanges(done, total);
    track
      ..total = total
      ..done = done
      ..have = coveredBytes(done);
    if (rewrite) {
      // The merged record goes down before the background file goes, so a crash between them only folds it twice.
      if (total > 0 || done.isNotEmpty) {
        await RangesRecord(total, done).write(track.ranges);
      } else {
        await _delete([track.ranges]);
      }
      await _delete([track.background]);
    }
    await part.parent.create(recursive: true);
    // Append mode never truncates: what the ranges vouch for stays, and any other byte is written over.
    track.file = await part.open(mode: FileMode.append);
    return folded;
  }

  Future<void> _run(_Download download) async {
    try {
      await Future.wait([
        for (final track in download.tracks.values)
          if (!track.finished && track.total <= 0) _learnTotal(download, track),
      ]);
      for (final track in download.tracks.values) {
        if (download.ending) break;
        if (track.finished) continue;
        if (track.have >= track.total) {
          await _finishTrack(download, track);
        } else {
          _plan(track);
        }
      }
      if (!download.ending) await _fetch(download);
    } catch (error) {
      _logger.error(LogCategory.engine, 'download error', {'id': download.id, 'error': _describe(error)});
      _fail(download, DownloadFailure.network, detail: _describe(error));
    }
    await _end(download);
  }

  /// Byte 0 alone, the one range every file has: its Content-Range gives the total.
  Future<void> _learnTotal(_Download download, _Track track) async {
    while (!download.ending) {
      try {
        final output = await _downloader.meta(ByteRange(0, 0), track.resolver, cancel: download.cancel);
        final total = output.total;
        if (total == null) throw const RipperError.badResponse(206);
        await track.io(() async {
          final file = track.file;
          if (file == null) return;
          track
            ..total = total
            ..done = clipRanges(track.done, total);
          await file.setPosition(0);
          await file.writeFrom(output.bytes);
          track.record(ByteRange(0, 0));
        });
        download
          ..lastSuccessAt = _clock.nowMs()
          ..fetched += output.bytes.length;
        return;
      } catch (error) {
        if (download.ending || error is CancelledException) return;
        if (!_retries(download, track, error)) return;
      }
      try {
        await cancellableSleep(_retryPauseMs, download.cancel);
      } on CancelledException {
        return;
      }
    }
  }

  /// The track's missing bytes as pieces on a grid of [pieceBytes], so a resumed download cuts the same pieces.
  void _plan(_Track track) {
    track.queue.clear();
    for (final gap in missingRanges(track.done, track.total)) {
      var start = gap.start;
      while (start <= gap.end) {
        final end = min(gap.end, (start ~/ pieceBytes + 1) * pieceBytes - 1);
        track.queue.add(ByteRange(start, end));
        start = end + 1;
      }
    }
  }

  /// Keeps up to [_window] pieces going, audio first; completes once none is left running and none is left to start
  /// (or the download is ending).
  Future<void> _fetch(_Download download) {
    final idle = Completer<void>();
    void pump() {
      if (!download.ending) {
        for (final track in [download.audio, download.video]) {
          while (track.queue.isNotEmpty) {
            final room = _window - download.outstanding;
            if (room <= 0 || (room < _batch && track.queue.length > room)) break;
            final batch = [
              for (var count = 0; count < room && track.queue.isNotEmpty; count++) track.queue.removeFirst(),
            ];
            final candidates = track.resolver.rangeCandidates();
            final primaries = _downloader.assigner.assign(
              urls: candidates,
              count: batch.length,
              speed: track.resolver.speed,
              trialKey: track.resolver,
              isFull: (url, placed) => _ctx.nodes.isFull(url, extraInflight: placed),
            );
            for (var index = 0; index < batch.length; index++) {
              final primary = index < primaries.length ? primaries[index] : candidates.firstOrNull;
              final preferred = primary == null ? candidates : [primary, ...candidates.where((url) => url != primary)];
              download.outstanding += 1;
              unawaited(
                _piece(download, track, batch[index], preferred).whenComplete(() {
                  download.outstanding -= 1;
                  pump();
                }),
              );
            }
          }
        }
      }
      final drained = download.ending || download.tracks.values.every((track) => track.queue.isEmpty);
      if (download.outstanding == 0 && drained && !idle.isCompleted) idle.complete();
    }

    pump();
    return idle.future;
  }

  Future<void> _piece(_Download download, _Track track, ByteRange piece, List<String> preferred) async {
    final AttemptOutput output;
    try {
      output = await _downloader.pieces.download(
        piece: piece,
        index: download.pieceIndex++,
        resolver: track.resolver,
        preferred: preferred,
        mode: PieceMode.normal,
        priority: _priority,
        deadline: _horizon,
        cancel: download.cancel,
        probation: true,
      );
    } catch (error) {
      if (download.ending || error is CancelledException) return;
      if (_retries(download, track, error)) track.queue.addFirst(piece);
      return;
    }
    final total = output.total;
    if (total != null && total != track.total) {
      track.discard = true;
      _fail(download, DownloadFailure.sizeChanged, track: track.kind, detail: 'total $total, was ${track.total}');
      return;
    }
    try {
      await track.io(() async {
        final file = track.file;
        if (file == null || track.discard) return;
        await file.setPosition(piece.start);
        await file.writeFrom(output.bytes);
        track.record(piece);
      });
    } catch (error) {
      _fail(download, DownloadFailure.disk, track: track.kind, detail: _describe(error));
      return;
    }
    download
      ..lastSuccessAt = _clock.nowMs()
      ..fetched += piece.length;
    if (track.have >= track.total) await _finishTrack(download, track);
  }

  /// Whether the failed request is worth asking again; when not, the download fails with the reason.
  bool _retries(_Download download, _Track track, Object error) {
    final failure = switch (error) {
      FileSystemException() => DownloadFailure.disk,
      RipperError(kind: RipperErrorKind.badResponse, status: 403 || 404) => DownloadFailure.expired,
      // Not one address the policy takes: fresh ones from Bilibili may be.
      RipperError(kind: RipperErrorKind.noNodes || RipperErrorKind.invalidURL) => DownloadFailure.expired,
      RipperError(kind: RipperErrorKind.badResponse, status: 416) ||
      RipperError(kind: RipperErrorKind.totalMismatch) => DownloadFailure.sizeChanged,
      _ when _clock.nowMs() - download.lastSuccessAt >= networkTimeout.inMicroseconds / 1000 => DownloadFailure.network,
      _ => null,
    };
    if (failure == null) return true;
    if (failure == DownloadFailure.sizeChanged) track.discard = true;
    _fail(download, failure, track: track.kind, detail: _describe(error));
    return false;
  }

  /// The first failure is the one reported; one met while stopping is the stop's doing.
  void _fail(_Download download, DownloadFailure failure, {TrackKind? track, String detail = ''}) {
    if (download.failure == null && !download.stopping) {
      download.failure = (failure: failure, track: track, detail: detail);
    }
    download.cancel.cancel();
  }

  Future<void> _finishTrack(_Download download, _Track track) async {
    if (track.finished) return;
    track.finished = true;
    try {
      await track.io(() async {
        final file = track.file;
        track.file = null;
        if (file != null) {
          final length = await file.length();
          if (length > track.total) await file.truncate(track.total);
          await file.flush();
          await file.close();
          if (length < track.total) throw const _ShortPart();
        }
        await File(track.part).rename(track.spec.path);
        await _delete([track.ranges, '${track.ranges}.tmp', track.background]);
        track.dirty = false;
      });
    } on _ShortPart {
      track
        ..finished = false
        ..discard = true;
      _fail(download, DownloadFailure.disk, track: track.kind, detail: 'part shorter than its ranges');
    } catch (error) {
      track.finished = false;
      _fail(download, DownloadFailure.disk, track: track.kind, detail: _describe(error));
    }
  }

  Future<void> _end(_Download download) async {
    download.cancel.cancel();
    for (final track in download.tracks.values) {
      if (track.discard) {
        await track.io(() => _close(track));
        await _delete([track.part, track.ranges, '${track.ranges}.tmp', track.background]);
        track
          ..total = 0
          ..done = const []
          ..have = 0;
        continue;
      }
      if (track.finished) continue;
      try {
        await _flush(track);
      } catch (error) {
        _logger.error(LogCategory.engine, 'download flush failed', {
          'id': download.id,
          'track': track.kind.name,
          'error': _describe(error),
        });
        _fail(download, DownloadFailure.disk, track: track.kind, detail: _describe(error));
      }
      await track.io(() => _close(track));
    }
    if (identical(_downloads[download.id], download)) _downloads.remove(download.id);
    if (_downloads.isEmpty) {
      _ticker?.cancel();
      _ticker = null;
    }
    // Every start ends in an event unless it was stopped, so the app never waits on a download that went quiet.
    if (download.failure == null && !download.finished && !download.stopping) {
      download.failure = (failure: DownloadFailure.network, track: null, detail: 'ended early');
    }
    final seconds = (_clock.nowMs() - download.startedAt) / 1000;
    final failure = download.failure;
    if (failure != null) {
      _logger.warn(LogCategory.engine, 'download failed', {
        'id': download.id,
        'failure': failure.failure.name,
        'track': failure.track?.name ?? '',
        'detail': failure.detail,
        'have': download.have,
        'seconds': seconds,
      });
      emit(DownloadFailed(download.id, failure: failure.failure, track: failure.track, detail: failure.detail));
    } else if (download.finished) {
      _logger.info(LogCategory.engine, 'download finished', {
        'id': download.id,
        'bytes': download.fetched,
        'total': download.have,
        'seconds': seconds,
        'bps': seconds > 0 ? (download.fetched / seconds).roundToDouble() : 0.0,
      });
      emit(DownloadFinished(download.id, videoTotal: download.video.total, audioTotal: download.audio.total));
    } else if (download.stopping) {
      _logger.info(LogCategory.engine, 'download stopped', {
        'id': download.id,
        'bytes': download.fetched,
        'have': download.have,
        'seconds': seconds,
      });
    }
    download.ended.complete();
  }

  /// The part's bytes reach the disk before the record that vouches for them.
  Future<void> _flush(_Track track) => track.io(() async {
    if (!track.dirty || track.discard || track.finished) return;
    await track.file?.flush();
    await RangesRecord(track.total, track.done).write(track.ranges);
    track.dirty = false;
  });

  Future<void> _close(_Track track) async {
    final file = track.file;
    track.file = null;
    try {
      await file?.close();
    } on FileSystemException {
      // Closing a file whose writes failed: the failure is already reported.
    }
  }

  void _tick() {
    final now = _clock.nowMs();
    for (final download in _downloads.values.toList()) {
      if (!download.running || download.ending) continue;
      _emitProgress(download, now);
      if (now - download.flushedAt >= flushInterval.inMicroseconds / 1000) {
        download.flushedAt = now;
        unawaited(_flushAll(download));
      }
    }
  }

  Future<void> _flushAll(_Download download) async {
    for (final track in download.tracks.values) {
      try {
        await _flush(track);
      } catch (error) {
        _fail(download, DownloadFailure.disk, track: track.kind, detail: _describe(error));
        return;
      }
    }
  }

  void _emitProgress(_Download download, double now) => emit(
    DownloadProgress(
      download.id,
      videoBytes: download.video.have,
      audioBytes: download.audio.have,
      videoTotal: download.video.total,
      audioTotal: download.audio.total,
      bps: _rate(download, now),
    ),
  );

  /// Bytes fetched over the last few seconds: pieces land a few MiB at a time, so one second alone jumps about.
  double _rate(_Download download, double now) {
    final samples = download.samples..add((at: now, bytes: download.fetched));
    while (samples.length > 2 && now - samples.elementAt(1).at >= _rateWindowMs) {
      samples.removeFirst();
    }
    final first = samples.first;
    final seconds = (now - first.at) / 1000;
    return seconds > 0 ? (download.fetched - first.bytes) / seconds : 0;
  }

  double _horizon() => _clock.nowMs() + _horizonMs;

  static List<ByteRange> _gaps(_Track track) =>
      track.finished || track.total <= 0 ? const [] : missingRanges(track.done, track.total);

  static Future<void> _delete(List<String> paths) async {
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  /// Never a URL: a transport's own errors may carry one.
  static String _describe(Object error) => switch (error) {
    RipperError() => '$error',
    FileSystemException(:final message, :final osError?) => '$message: ${osError.message} (${osError.errorCode})',
    FileSystemException(:final message) => message,
    _ => '${error.runtimeType}',
  };
}

/// The ranges of `[total]` bytes not in [done] (sorted, merged, inclusive).
List<ByteRange> missingRanges(List<ByteRange> done, int total) {
  final missing = <ByteRange>[];
  if (total <= 0) return missing;
  var next = 0;
  for (final range in mergeRanges(done)) {
    if (range.start >= total) break;
    if (range.start > next) missing.add(ByteRange(next, range.start - 1));
    if (range.end + 1 > next) next = range.end + 1;
  }
  if (next < total) missing.add(ByteRange(next, total - 1));
  return missing;
}

final class _Track {
  _Track(this.kind, this.spec, this.resolver);

  final TrackKind kind;
  final DownloadTrack spec;
  final Resolver resolver;
  int total = 0;
  List<ByteRange> done = const [];
  int have = 0;
  RandomAccessFile? file;

  /// [done] has more than `.ranges` says.
  bool dirty = false;
  bool finished = false;

  /// Its files are deleted when the download ends: the CDN's total changed, or the part was short.
  bool discard = false;
  final queue = Queue<ByteRange>();
  Future<void> _io = Future.value();

  String get part => DownloadRanges.partPath(spec.path);
  String get ranges => DownloadRanges.rangesPath(spec.path);
  String get background => DownloadRanges.backgroundRangesPath(spec.path);

  /// File work, one task at a time: a RandomAccessFile takes one operation at once, and a flush queued after a
  /// write sees it recorded.
  Future<T> io<T>(Future<T> Function() task) {
    final result = _io.then((_) => task());
    _io = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  void record(ByteRange range) {
    done = mergeRanges([...done, range]);
    have = coveredBytes(done);
    dirty = true;
  }
}

final class _Download {
  _Download(this.id, this.tracks, this.bans, {required this.startedAt}) : lastSuccessAt = startedAt;

  final String id;
  final Map<TrackKind, _Track> tracks;

  /// Shared by the two tracks, as a playback's are.
  final BanList bans;
  final double startedAt;
  final cancel = CancelToken();

  /// Its pieces have settled, its files are flushed and closed, and its last event is sent.
  final ended = Completer<void>();
  final samples = Queue<({double at, int bytes})>();
  double lastSuccessAt;
  double flushedAt = 0;

  /// Bytes fetched by this start, for the speed.
  int fetched = 0;
  int outstanding = 0;
  int pieceIndex = 0;
  bool running = false;
  bool stopping = false;
  ({DownloadFailure failure, TrackKind? track, String detail})? failure;

  bool get ending => cancel.isCancelled;
  _Track get video => tracks[TrackKind.video]!;
  _Track get audio => tracks[TrackKind.audio]!;
  bool get finished => tracks.values.every((track) => track.finished);
  int get have => video.have + audio.have;
}

final class _ShortPart implements Exception {
  const _ShortPart();
}

/// The engine's transport as downloads see it. An HTTP/1.1 node (Akamai) counts as full at half the transport's
/// connections to it, so a playing video finds the rest free; a 412 or 429 reaches the app-wide connection count,
/// as a playback's does.
final class _Share implements RangeTransport {
  _Share(this._inner, this._auto);

  final RangeTransport _inner;
  final AutoConcurrency _auto;

  @override
  int? get connectionsPerHost => switch (_inner.connectionsPerHost) {
    final limit? => max(1, limit ~/ 2),
    null => null,
  };

  @override
  String get name => _inner.name;

  /// The engine closes the transport it shares.
  @override
  void close() {}

  @override
  Future<TransportResponse> fetch(Uri url, ByteRange range, {CancelToken? cancel}) async {
    final response = await _inner.fetch(url, range, cancel: cancel);
    if (response.status == 412 || response.status == 429) _auto.pushback(status: response.status);
    return response;
  }
}
