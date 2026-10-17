// Port of Bilibili-thread-ripper (see LICENSE-BTR.txt), by way of BiliNative's RipperSession.swift.

import 'dart:async';
import 'dart:typed_data';

import '../devlog/log_event.dart';
import '../devlog/logger.dart';
import '../shared/byte_range.dart';
import '../shared/clock.dart';
import '../shared/media_segment.dart';
import 'attempt.dart';
import 'ban_list.dart';
import 'cancel.dart';
import 'connection_pool.dart';
import 'node_catalog.dart';
import 'playback_engine.dart';
import 'range_downloader.dart';
import 'resolver.dart';
import 'ripper_config.dart';
import 'transport.dart';

final class TrackHeaders {
  const TrackHeaders({required this.bytes, required this.totalSize});

  /// Bytes 0 through the end of the SIDX: init segment plus index.
  final Uint8List bytes;
  final int totalSize;
}

typedef TrackSource = ({String primary, List<String> backups});

/// One playback in BTR mode: both tracks' resolvers and the shared connection pool (first version of
/// RipperSession.swift). Each player request is one byte range, usually one whole SIDX segment, which [read]
/// splits into pieces fetched across the nodes and delivers in order. Left for slice 2: prefetch and the
/// segment cache, AutoConcurrency, playhead tracking, fatal reporting.
final class RipperSession {
  RipperSession({
    required Map<TrackKind, TrackSource> sources,
    required NodeMode mode,
    required RangeTransport transport,
    RipperConfig config = const RipperConfig(),
    MediaURLPolicy policy = MediaURLPolicy.bilibili,
    MonotonicClock? clock,
    Logger? logger,
  }) : _ctx = EngineContext(
          transport: transport,
          pool: ConnectionPool(config.concurrency),
          config: config,
          clock: clock,
          logger: logger,
        ) {
    _resolvers = {
      for (final MapEntry(key: kind, value: source) in sources.entries)
        kind: Resolver(
          primary: source.primary,
          backups: source.backups,
          mode: mode,
          policy: policy,
          bans: _bans,
          clock: _ctx.clock,
        ),
    };
    _downloader = RangeDownloader(_ctx);
    _bans.onBan = (node, strikes, kind) =>
        _ctx.logger.warn(LogCategory.engine, 'ban', {'node': node, 'strikes': strikes, 'kind': kind.name});
  }

  final EngineContext _ctx;
  final _bans = BanList();
  late final Map<TrackKind, Resolver> _resolvers;
  late final RangeDownloader _downloader;
  final _root = CancelToken();
  final _headers = <TrackKind, TrackHeaders>{};
  final _segments = <TrackKind, List<MediaSegment>>{};

  /// Position in [_segments] by range start.
  final _segmentAt = <TrackKind, Map<int, int>>{};
  final _lastRequest = <TrackKind, ByteRange>{};

  /// Where the track's last startup or seek read began, in seconds: the engine has no playhead yet, so a
  /// segment counts as about to play when it starts within `hurryAheadSeconds` of that point.
  final _hurryFrom = <TrackKind, double>{};
  int _requests = 0;
  int _seeks = 0;
  bool _closed = false;

  bool get isClosed => _closed;
  int get seekCount => _seeks;
  int get mediaRequestCount => _requests;
  int get deliveredBytes => _ctx.stats.deliveredBytes;

  Future<TrackHeaders> loadHeaders(TrackKind track, {required int through}) async {
    if (_closed) throw const RipperError(RipperErrorKind.closed);
    final resolver = _resolvers[track];
    final range = ByteRange.of(0, through);
    if (resolver == null || range == null) throw const RipperError(RipperErrorKind.noNodes);
    final AttemptOutput output;
    try {
      output = await _downloader.meta(range, resolver, cancel: _root);
    } on CancelledException {
      if (_closed) throw const RipperError(RipperErrorKind.closed);
      rethrow;
    }
    final total = output.total;
    if (total == null) throw const RipperError.badResponse(206);
    final headers = TrackHeaders(bytes: output.bytes, totalSize: total);
    _headers[track] = headers;
    _ctx.logger.info(LogCategory.engine, 'headers',
        {'track': track.name, 'bytes': output.bytes.length, 'node': NodeCatalog.nodeKey(output.url)});
    return headers;
  }

  void setSegments(TrackKind track, List<MediaSegment> segments) {
    _segments[track] = segments;
    _segmentAt[track] = {
      for (var position = 0; position < segments.length; position++) segments[position].range.start: position,
    };
  }

  /// Single subscription. Cancelling the subscription cancels every piece of the read at once.
  Stream<List<int>> read(TrackKind track, ByteRange range) {
    if (_closed) return Stream.error(const RipperError(RipperErrorKind.closed));
    final token = CancelToken(_root);
    late final StreamController<List<int>> controller;
    controller = StreamController<List<int>>(
      onListen: () {
        _serve(track, range, controller.add, token).then(
          (_) => controller.close(),
          onError: (Object error, StackTrace stack) {
            controller.addError(_closed ? const RipperError(RipperErrorKind.closed) : error, stack);
            controller.close();
          },
        ).whenComplete(token.dispose);
      },
      onCancel: token.cancel,
    );
    return controller.stream;
  }

  void replaceUrls(TrackKind track, {required String primary, required List<String> backups}) {
    _resolvers[track]?.replaceURLs(primary: primary, backups: backups);
    _ctx.logger.info(LogCategory.engine, 'urls replaced', {'track': track.name, 'url': primary});
  }

  /// The phone's network path changed: bans and backoffs from the old path are dropped, and with
  /// a different interface the speed measurements too.
  void networkChanged({required bool interfaceChanged}) {
    _bans.reset();
    for (final resolver in _resolvers.values) {
      resolver.resetHealth(clearMeasurements: interfaceChanged);
    }
    _ctx.nodes.reset();
    _ctx.logger.info(LogCategory.engine, 'network changed, node health reset', {'interfaceChanged': interfaceChanged});
  }

  EngineSnapshot stats({double downloadBps = 0, String transport = ''}) => _ctx.stats.snapshot(
        concurrency: _ctx.pool.limit,
        nodeStates: _resolvers[TrackKind.video]?.status() ?? const [],
        downloadBps: downloadBps,
        transport: transport,
      );

  void close() {
    if (_closed) return;
    _closed = true;
    _root.cancel();
  }

  Future<void> _serve(
    TrackKind track,
    ByteRange range,
    void Function(Uint8List bytes) emit,
    CancelToken token,
  ) async {
    final resolver = _resolvers[track];
    if (resolver == null) throw const RipperError(RipperErrorKind.noNodes);
    final began = _ctx.clock.nowMs();
    final headers = _headers[track];
    if (headers != null && range.end < headers.bytes.length) {
      _ctx.stats.cache(hit: true);
      emit(Uint8List.sublistView(headers.bytes, range.start, range.end + 1));
      return;
    }
    final positions = _segmentAt[track];
    final position = positions?[range.start];
    final segment = position == null ? null : _segments[track]?[position];
    final previous = _lastRequest[track];
    _lastRequest[track] = range;
    _requests += 1;
    final seek = _isSeek(range, previous, positions);
    if (seek) {
      _seeks += 1;
      if (segment != null) {
        _hurryFrom[track] = segment.startTime;
      } else {
        _hurryFrom.remove(track);
      }
    }
    _ctx.stats.cache(hit: false);
    try {
      await _downloader.stream(
        range,
        resolver,
        startup: seek,
        priority: _ctx.config.priority,
        emit: emit,
        expectedTotal: headers?.totalSize,
        hurry: _hurry(track, segment, startup: seek),
        cancel: token,
      );
    } catch (error) {
      if (!token.isCancelled && error is! CancelledException) {
        _ctx.logger
            .error(LogCategory.engine, 'range failed', {'track': track.name, 'range': '$range', 'error': '$error'});
      }
      rethrow;
    }
    _ctx.logger.debug(LogCategory.engine, 'read', {
      'track': track.name,
      'range': '$range',
      'source': 'fetch',
      'seek': seek,
      'ms': (_ctx.clock.nowMs() - began).roundToDouble(),
    });
  }

  /// AVPlayer may ask for a track's next segment before the current one is in, and two such requests
  /// can arrive out of order, so a request within a segment (or, unaligned, its own length) of the
  /// previous one is not a seek.
  static bool _isSeek(ByteRange range, ByteRange? previous, Map<int, int>? positions) {
    if (previous == null) return true;
    final position = positions?[range.start];
    final last = positions?[previous.start];
    if (position != null && last != null) return position < last - 1 || position > last + 2;
    return range.start < previous.start - range.length || range.start > previous.end + 1 + range.length;
  }

  /// Startup and seek reads are always in a hurry; other reads while their segment starts within
  /// `hurryAheadSeconds` of where the track last started or seeked. Re-read on every call.
  bool Function() _hurry(TrackKind track, MediaSegment? segment, {required bool startup}) {
    final config = _ctx.config;
    return () {
      if (!config.hurry) return false;
      if (startup) return true;
      final from = _hurryFrom[track];
      if (segment == null || from == null) return false;
      return segment.startTime - from < config.hurryAheadSeconds;
    };
  }
}
