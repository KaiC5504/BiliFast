// Port of Bilibili-thread-ripper (see LICENSE-BTR.txt), by way of BiliNative's RipperSession.swift.

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../devlog/log_event.dart';
import '../devlog/logger.dart';
import '../shared/byte_range.dart';
import '../shared/clock.dart';
import '../shared/media_segment.dart';
import 'attempt.dart';
import 'auto_concurrency.dart';
import 'ban_list.dart';
import 'cancel.dart';
import 'connection_pool.dart';
import 'node_catalog.dart';
import 'node_stats.dart';
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

typedef _Key = (TrackKind, ByteRange);

final class _CacheEntry {
  const _CacheEntry(this.bytes, this.endTime);

  final Uint8List bytes;
  final double endTime;
}

/// A segment downloading ahead of the player: Swift's prefetch Task, cancelled through its token.
final class _Prefetch {
  _Prefetch(this.token);

  final CancelToken token;
  late final Future<Uint8List> bytes;
}

final class _Request {
  _Request({this.memory, this.segment, this.number = 0, this.seek = false, this.firstOfTrack = false, this.total});

  /// Served from the headers or the cache.
  Uint8List? memory;

  /// A prefetch the request took over.
  _Prefetch? adopted;
  final MediaSegment? segment;
  final int number;
  final bool seek;
  final bool firstOfTrack;
  final int? total;
  int generation = 0;
}

/// One playback in BTR mode (port of RipperSession.swift): both tracks' resolvers, the shared connection pool, the
/// segment cache and prefetch. Each player request is one byte range, usually one whole SIDX segment, which [read]
/// splits into pieces fetched across the nodes and delivers in order; the segments after it are then prefetched.
/// Everything runs on the engine isolate, so Swift's locks have no counterpart here.
final class RipperSession {
  factory RipperSession({
    required Map<TrackKind, TrackSource> sources,
    required NodeMode mode,
    required RangeTransport transport,
    AutoConcurrency? auto,
    RipperConfig config = const RipperConfig(),
    MediaURLPolicy policy = MediaURLPolicy.bilibili,
    MonotonicClock? clock,
    Logger? logger,
  }) {
    final follower = config.fixedConcurrency == null ? auto : null;
    final monotonic = clock ?? MonotonicClock.system;
    final pool = ConnectionPool(config.fixedConcurrency ?? follower?.threads ?? RipperConfig.defaultConcurrency,
        clock: monotonic);
    final ctx = EngineContext(
        transport: transport, pool: pool, config: config, auto: follower, clock: monotonic, logger: logger);
    return RipperSession._(ctx, sources, mode, policy);
  }

  RipperSession._(this._ctx, Map<TrackKind, TrackSource> sources, NodeMode mode, MediaURLPolicy policy) {
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
    final follower = _ctx.auto;
    if (follower != null) {
      final pool = _ctx.pool;
      pool.onChange = (active, limit, queued) => follower.demand(active: active, limit: limit, queued: queued);
      // The connection count is app-wide with one handler slot: the newest session takes it. The limit is read
      // from `threads`, not taken from the arguments, as Swift does for deliveries that arrive out of order.
      _followerHandler = (threads, previous, reason) {
        if (_closed) return;
        pool.setLimit(follower.threads);
        _ctx.logger.info(LogCategory.engine, 'threads', {'threads': threads, 'previous': previous, 'reason': reason});
      };
      follower.onChange = _followerHandler;
      follower.newSession();
      pool.setLimit(follower.threads);
    }
  }

  final EngineContext _ctx;
  final _bans = BanList();
  late final Map<TrackKind, Resolver> _resolvers;
  late final RangeDownloader _downloader;
  ConcurrencyChange? _followerHandler;

  /// Parent of every read and prefetch, so [close] reaches them all.
  final _root = CancelToken();
  final _headers = <TrackKind, TrackHeaders>{};
  final _segments = <TrackKind, List<MediaSegment>>{};

  /// Position in [_segments] by range start.
  final _segmentAt = <TrackKind, Map<int, int>>{};
  final _cache = <_Key, _CacheEntry>{};
  final _inflight = <_Key, _Prefetch>{};

  /// Bumped by [_dropPrefetch]; a reader that adopted a prefetch before a seek must not hand it back after.
  final _seekGeneration = <TrackKind, int>{};

  /// Segments a player request is downloading or waiting on, with how many requests; prefetch leaves them alone.
  final _playerPending = <_Key, int>{};
  final _lastRequest = <TrackKind, ByteRange>{};
  double _playhead = 0;
  double _rate = 1;
  int _reads = 0;
  int _requests = 0;

  /// Requests numbered up to this were already covered by an [onFatal] call.
  int _fatalCovered = 0;
  int _seeks = 0;
  bool _closed = false;

  /// A player request failed after every retry: the app refreshes the URLs or falls back to direct mode.
  /// Requests that fail together are reported once; a request made after a report can report again.
  void Function(Object error)? onFatal;

  bool get isClosed => _closed;
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

  /// Single subscription. Cancelling the subscription cancels every piece of the read at once; a prefetch the read
  /// took over goes on downloading.
  Stream<List<int>> read(TrackKind track, ByteRange range) {
    if (_closed) return Stream.error(const RipperError(RipperErrorKind.closed));
    final token = CancelToken(_root);
    late final StreamController<List<int>> controller;
    controller = StreamController<List<int>>(
      onListen: () {
        _reads += 1;
        _serve(track, range, controller.add, token).then(
          (_) => controller.close(),
          onError: (Object error, StackTrace stack) {
            controller.addError(_closed ? const RipperError(RipperErrorKind.closed) : error, stack);
            controller.close();
          },
        ).whenComplete(() {
          _reads -= 1;
          token.dispose();
        });
      },
      onCancel: token.cancel,
    );
    return controller.stream;
  }

  void updatePlayhead({required double seconds, required double rate}) {
    _playhead = seconds;
    _rate = rate > 0 ? rate : 1;
    _cache.removeWhere((_, entry) => entry.endTime < seconds - 2);
  }

  void reportBuffer({required double aheadSeconds, required bool playing}) =>
      _ctx.auto?.buffer(ahead: aheadSeconds, playing: playing);

  void reportStall() => _ctx.auto?.stall();

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

  /// Memory warning: drops cached and still-downloading prefetched segments; playback goes on.
  void dropCache() {
    _cache.clear();
    final prefetches = _inflight.values.toList();
    _inflight.clear();
    for (final prefetch in prefetches) {
      prefetch.token.cancel();
    }
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
    _cache.clear();
    final prefetches = _inflight.values.toList();
    _inflight.clear();
    _ctx.pool.onChange = null;
    // Swift's handler holds the session weakly and does nothing once it is closed; dropping it does the same and
    // lets the session go.
    final follower = _ctx.auto;
    if (follower != null && identical(follower.onChange, _followerHandler)) follower.onChange = null;
    for (final prefetch in prefetches) {
      prefetch.token.cancel();
    }
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
    final key = (track, range);
    final request = _plan(track, range, key);
    final pending = request.memory == null;
    try {
      var served = false;
      var source = 'fetch';
      final adopted = request.adopted;
      if (request.memory case final bytes?) {
        _ctx.stats.cache(hit: true);
        emit(bytes);
        served = true;
        source = 'memory';
      } else if (adopted != null) {
        final bytes = await _waitForPrefetch(adopted, token);
        if (token.isCancelled) {
          _returnPrefetch(adopted, key, endTime: request.segment?.endTime ?? 0, generation: request.generation);
          throw const CancelledException();
        }
        if (bytes != null) {
          _ctx.stats.cache(hit: true);
          emit(bytes);
          served = true;
          source = 'prefetch';
        }
      }
      if (!served) {
        _ctx.stats.cache(hit: false);
        if (adopted == null && request.seek) {
          _dropPrefetch(track);
          if (!request.firstOfTrack) _ctx.auto?.newSession();
        }
        try {
          await _downloader.stream(
            range,
            resolver,
            startup: request.seek,
            priority: _ctx.config.priority,
            emit: emit,
            deadline: _deadline(request.segment),
            expectedTotal: request.total,
            hurry: _hurry(request.segment, startup: request.seek),
            cancel: token,
          );
          token.throwIfCancelled();
        } catch (error) {
          if (!token.isCancelled && error is! CancelledException) {
            _ctx.logger
                .error(LogCategory.engine, 'range failed', {'track': track.name, 'range': '$range', 'error': '$error'});
            if (_claimFatal(request.number)) onFatal?.call(error);
          }
          rethrow;
        }
      }
      _ctx.logger.debug(LogCategory.engine, 'read', {
        'track': track.name,
        'range': '$range',
        'source': source,
        'seek': request.seek,
        'ms': (_ctx.clock.nowMs() - began).roundToDouble(),
      });
      _schedulePrefetch(track, request.segment);
    } finally {
      if (pending) {
        final left = (_playerPending[key] ?? 1) - 1;
        if (left > 0) {
          _playerPending[key] = left;
        } else {
          _playerPending.remove(key);
        }
      }
    }
  }

  _Request _plan(TrackKind track, ByteRange range, _Key key) {
    if (_closed) throw const RipperError(RipperErrorKind.closed);
    final headers = _headers[track];
    if (headers != null && range.end < headers.bytes.length) {
      return _Request(memory: Uint8List.sublistView(headers.bytes, range.start, range.end + 1));
    }
    final positions = _segmentAt[track];
    final position = positions?[range.start];
    final previous = _lastRequest[track];
    _lastRequest[track] = range;
    _requests += 1;
    final request = _Request(
      segment: position == null ? null : _segments[track]?[position],
      number: _requests,
      seek: _isSeek(range, previous, positions),
      firstOfTrack: previous == null,
      total: headers?.totalSize,
    );
    final entry = _cache.remove(key);
    final prefetch = entry == null ? _inflight.remove(key) : null;
    if (entry != null) {
      request.memory = entry.bytes;
    } else if (prefetch != null) {
      // Taken out of `_inflight`, so a seek cannot cancel it and its bytes do not also land in the cache.
      request.adopted = prefetch;
      request.generation = _seekGeneration[track] ?? 0;
    } else if (request.seek) {
      _seeks += 1;
    }
    if (request.memory == null) _playerPending[key] = (_playerPending[key] ?? 0) + 1;
    return request;
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

  bool _claimFatal(int number) {
    if (_closed || number <= _fatalCovered) return false;
    _fatalCovered = _requests;
    return true;
  }

  /// When playback needs this segment, as a monotonic time in ms; re-read on every queue pass.
  double Function()? _deadline(MediaSegment? segment) {
    if (segment == null) return null;
    final clock = _ctx.clock;
    return () => clock.nowMs() + max(0.0, segment.startTime - _playhead) / _rate * 1000;
  }

  /// Whether playback is about to need the segment: startup and seek reads always are, others once the segment
  /// starts less than `hurryAheadSeconds` of playback ahead. Re-read on every call, so a prefetch the playhead
  /// approaches turns into a hurry.
  bool Function() _hurry(MediaSegment? segment, {required bool startup}) {
    final config = _ctx.config;
    return () {
      if (!config.hurry) return false;
      if (startup) return true;
      if (segment == null) return false;
      return segment.startTime - _playhead < config.hurryAheadSeconds * _rate;
    };
  }

  /// After a seek the track's prefetched segments belong to the old position; left in place they
  /// would hold the cap and keep the new position from being prefetched.
  void _dropPrefetch(TrackKind track) {
    _seekGeneration[track] = (_seekGeneration[track] ?? 0) + 1;
    _cache.removeWhere((key, _) => key.$1 == track);
    final keys = _inflight.keys.where((key) => key.$1 == track).toList();
    for (final key in keys) {
      _inflight.remove(key)?.token.cancel();
    }
  }

  int _prefetchedBytes(TrackKind track) {
    var bytes = 0;
    for (final MapEntry(:key, :value) in _cache.entries) {
      if (key.$1 == track) bytes += value.bytes.length;
    }
    for (final key in _inflight.keys) {
      if (key.$1 == track) bytes += key.$2.length;
    }
    return bytes;
  }

  void _schedulePrefetch(TrackKind track, MediaSegment? segment) {
    final resolver = _resolvers[track];
    if (segment == null || resolver == null || _closed) return;
    final segments = _segments[track];
    final position = _segmentAt[track]?[segment.range.start];
    if (segments == null || position == null) return;
    final config = _ctx.config;
    final cap = track == TrackKind.video ? config.prefetchVideoBytes : config.prefetchAudioBytes;
    final total = _headers[track]?.totalSize;
    var budget = cap - _prefetchedBytes(track);
    for (final next in segments.skip(position + 1)) {
      if (next.startTime - _playhead > config.prefetchAheadSeconds) break;
      final key = (track, next.range);
      if (_cache.containsKey(key) || _inflight.containsKey(key) || _playerPending.containsKey(key)) continue;
      if (next.range.length > budget) break;
      budget -= next.range.length;
      final prefetch = _Prefetch(CancelToken(_root));
      prefetch.bytes = _fetchSegment(next, resolver, total, prefetch.token);
      _inflight[key] = prefetch;
      _watch(key, prefetch, next.endTime);
    }
  }

  Future<Uint8List> _fetchSegment(MediaSegment segment, Resolver resolver, int? total, CancelToken cancel) async {
    final builder = BytesBuilder(copy: false);
    try {
      await _downloader.stream(
        segment.range,
        resolver,
        startup: false,
        priority: 10,
        emit: builder.add,
        deadline: _deadline(segment),
        expectedTotal: total,
        hurry: _hurry(segment, startup: false),
        cancel: cancel,
      );
      cancel.throwIfCancelled();
      return builder.takeBytes();
    } finally {
      cancel.dispose();
    }
  }

  void _watch(_Key key, _Prefetch prefetch, double endTime) {
    unawaited(prefetch.bytes.then(
      (bytes) => _prefetchFinished(key, prefetch, endTime, bytes: bytes),
      onError: (Object error) => _prefetchFinished(key, prefetch, endTime, error: error),
    ));
  }

  void _prefetchFinished(_Key key, _Prefetch prefetch, double endTime, {Uint8List? bytes, Object? error}) {
    if (identical(_inflight[key], prefetch)) {
      _inflight.remove(key);
      if (bytes != null && !_closed) _cache[key] = _CacheEntry(bytes, endTime);
    }
    if (error != null && error is! CancelledException) {
      _ctx.logger.warn(LogCategory.engine, 'prefetch failed',
          {'track': key.$1.name, 'range': '${key.$2}', 'error': '$error'});
    }
  }

  /// Null when the prefetch failed, and as soon as the reader is cancelled: waiting for the prefetch alone would
  /// keep the reader parked until it ends, and the prefetch is not the reader's to cancel.
  static Future<Uint8List?> _waitForPrefetch(_Prefetch prefetch, CancelToken token) async {
    try {
      return await token.guard(prefetch.bytes);
    } catch (_) {
      return null;
    }
  }

  /// A reader that gives up on an adopted prefetch hands it back to `_inflight`, so it still ends in the cache.
  /// With the session closed, a seek since the reader took it, or the segment scheduled again meanwhile,
  /// nobody wants it.
  void _returnPrefetch(_Prefetch prefetch, _Key key, {required double endTime, required int generation}) {
    if (_closed || (_seekGeneration[key.$1] ?? 0) != generation || _inflight.containsKey(key)) {
      prefetch.token.cancel();
      return;
    }
    _inflight[key] = prefetch;
    // The prefetch may have finished while it was out of `_inflight`, after the first watcher gave up on it.
    _watch(key, prefetch, endTime);
  }

  // For tests.
  bool isCached(TrackKind track, ByteRange range) => _cache.containsKey((track, range));
  NodeStats get nodeStats => _ctx.nodes;
  int get seekCount => _seeks;
  int get mediaRequestCount => _requests;
  int prefetchedBytes(TrackKind track) => _prefetchedBytes(track);
  int cachedBytes(TrackKind track) => _cache.entries
      .where((entry) => entry.key.$1 == track)
      .fold(0, (sum, entry) => sum + entry.value.bytes.length);
  bool hurries(TrackKind track, ByteRange range) {
    final position = _segmentAt[track]?[range.start];
    return _hurry(position == null ? null : _segments[track]?[position], startup: false)();
  }

  int seekGeneration(TrackKind track) => _seekGeneration[track] ?? 0;
  int prefetchesRunning(TrackKind track) => _inflight.keys.where((key) => key.$1 == track).length;
  int get readsRunning => _reads;
}
