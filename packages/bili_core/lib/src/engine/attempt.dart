import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../devlog/log_event.dart';
import '../devlog/logger.dart';
import '../shared/byte_range.dart';
import '../shared/clock.dart';
import 'cancel.dart';
import 'connection_pool.dart';
import 'engine_stats.dart';
import 'meter.dart';
import 'node_catalog.dart';
import 'node_stats.dart';
import 'resolver.dart';
import 'ripper_config.dart';
import 'transport.dart';

final class EngineContext {
  EngineContext({
    required this.transport,
    required this.pool,
    required this.config,
    Meter? meter,
    EngineStats? stats,
    MonotonicClock? clock,
    Logger? logger,
  })  : meter = meter ?? Meter(),
        stats = stats ?? EngineStats(),
        clock = clock ?? MonotonicClock.system,
        logger = logger ?? Logger.shared,
        nodes = NodeStats(connectionsPerHost: transport.connectionsPerHost);

  final RangeTransport transport;
  final ConnectionPool pool;
  final RipperConfig config;
  final Meter meter;
  final EngineStats stats;
  final MonotonicClock clock;
  final Logger logger;
  final NodeStats nodes;

  /// BTR's pause before retry round [round] (1 or later): 0.5 s, 1 s, at most 2 s. False once
  /// the retry window that began at [startedAt] is spent.
  Future<bool> pauseBeforeRound(int round, {required double startedAt, CancelToken? cancel}) async {
    if (clock.nowMs() - startedAt > config.retryWindowMs) return false;
    await cancellableSleep(min(2000, 500 * pow(2, round - 1)).toDouble(), cancel);
    return true;
  }
}

/// Throws [CancelledException] as soon as [cancel] fires, and stops the timer with it.
Future<void> cancellableSleep(double ms, CancelToken? cancel) {
  if (cancel?.isCancelled ?? false) return Future.error(const CancelledException());
  if (ms <= 0) return Future.value();
  final completer = Completer<void>();
  void Function() remove = () {};
  final timer = Timer(Duration(microseconds: (ms * 1000).round()), () {
    remove();
    completer.complete();
  });
  remove = cancel?.onCancel(() {
        timer.cancel();
        if (!completer.isCompleted) completer.completeError(const CancelledException());
      }) ??
      remove;
  return completer.future;
}

final class AttemptOutput {
  const AttemptOutput({required this.bytes, required this.total, required this.url});

  final Uint8List bytes;
  final int? total;
  final String url;
}

/// Live state of one copy of a piece, read by the watchdog and by hedging decisions.
final class AttemptProgress {
  bool started = false;
  double startedAt = 0;
  bool gotHeaders = false;
  double headersAt = 0;
  double lastProgressAt = 0;
  int received = 0;
  final chunks = <List<int>>[];
  int length = 0;
  int seenBytes = 0;
  double seenAt = 0;
  bool failed = false;

  /// Set by the race that is about to cancel this copy because another copy won.
  bool outrun = false;

  void begin({required double at, required int length}) {
    started = true;
    startedAt = at;
    lastProgressAt = at;
    seenAt = at;
    this.length = length;
  }

  void headers({required double at}) {
    gotHeaders = true;
    headersAt = at;
    lastProgressAt = at;
  }

  void append(List<int> chunk, {required double at}) {
    received += chunk.length;
    chunks.add(chunk);
    lastProgressAt = at;
  }
}

/// Port of Attempt.swift's `AttemptRunner`, without resumed prefixes.
final class AttemptRunner {
  AttemptRunner(this.ctx);

  final EngineContext ctx;

  Future<AttemptOutput> runAt(
    String url, {
    required ByteRange piece,
    required AttemptProgress progress,
    required Resolver resolver,
    required double priority,
    required QueueClass queueClass,
    CancelToken? cancel,
  }) =>
      run(
        claim: () {
          ctx.nodes.begin(url);
          return url;
        },
        piece: piece,
        progress: progress,
        resolver: resolver,
        priority: priority,
        queueClass: queueClass,
        cancel: cancel,
      );

  /// One request for [piece]: waits for a connection, then [claim] picks the URL and counts the request on its
  /// node (so a request that waited for a permit goes where there is room by then). Enforces BTR's three
  /// timeouts, checks the 206 Content-Range and the length, and reports the outcome to the resolver, meter
  /// and stats.
  Future<AttemptOutput> run({
    required String Function() claim,
    required ByteRange piece,
    required AttemptProgress progress,
    required Resolver resolver,
    required double priority,
    required QueueClass queueClass,
    int copy = 1,
    CancelToken? cancel,
  }) async {
    final permit = await ctx.pool.acquire(priority: priority, queueClass: queueClass, cancel: cancel);
    try {
      cancel?.throwIfCancelled();
      final url = claim();
      try {
        return await _attempt(url, piece, progress, resolver, copy, cancel);
      } finally {
        ctx.nodes.end(url, receiving: progress.gotHeaders);
      }
    } finally {
      permit.release();
    }
  }

  Future<AttemptOutput> _attempt(
    String url,
    ByteRange part,
    AttemptProgress progress,
    Resolver resolver,
    int copy,
    CancelToken? cancel,
  ) async {
    final started = ctx.clock.nowMs();
    progress.begin(at: started, length: part.length);
    final node = NodeCatalog.nodeKey(url);
    ctx.stats.started(node);
    try {
      final output = await _transfer(url, part, progress, started, node, cancel);
      final now = ctx.clock.nowMs();
      final elapsed = max(1.0, now - started);
      ctx.meter.record(bytes: part.length, elapsedMs: elapsed);
      ctx.nodes.body(url, bytes: part.length, ms: now - progress.headersAt);
      resolver.success(url, bps: part.length >= Meter.sampleMinBytes ? part.length * 1000 / elapsed : 0);
      ctx.logger.debug(LogCategory.engine, 'piece', {
        'node': node,
        'range': '$part',
        'firstByteMs': (progress.headersAt - started).roundToDouble(),
        'bytes': part.length,
        'ms': elapsed.roundToDouble(),
        if (copy > 1) 'copy': copy,
      });
      return output;
    } catch (error) {
      final received = progress.received;
      final now = ctx.clock.nowMs();
      final elapsed = max(1.0, now - started);
      final cancelled = (cancel?.isCancelled ?? false) || error is CancelledException;
      if (cancelled) {
        // BTR PR 11: only a copy that lost a duplicate race says anything about its node. A seek or a
        // cancelled read would blend a queued request's whole wait into the estimate.
        if (progress.outrun) {
          if (progress.gotHeaders) {
            ctx.nodes.crawl(url, bytes: received, ms: now - progress.headersAt);
          } else {
            ctx.nodes.outrun(url, waitedMs: elapsed);
          }
        }
        // A copy that lost the race still measured its node; without this a slow node is never measured.
        if (received >= Meter.sampleMinBytes) resolver.sample(url, bps: received * 1000 / elapsed);
        if (received > 0) resolver.streamed(url);
        ctx.logger.debug(LogCategory.engine, 'attempt cancelled',
            {'node': node, 'range': '$part', 'bytes': received, 'ms': elapsed.roundToDouble()});
      } else {
        final ripperError = error is RipperError ? error : null;
        final firstByteTimeout = ripperError?.kind == RipperErrorKind.firstByteTimeout;
        // BTR PR 11: the request waited behind the node's own transfers (the transport's per-host limit on
        // HTTP/1.1 Akamai, or the node's queue), so it is not a strike.
        final busy = received == 0 && firstByteTimeout && ctx.nodes.isBusy(url);
        if (firstByteTimeout) ctx.nodes.silent(url, waitedMs: elapsed);
        if (!busy) {
          resolver.failure(url,
              status: ripperError?.status,
              receivedBytes: received,
              range: part,
              timedOut: ripperError?.isTimeout ?? false);
        }
        ctx.logger.debug(LogCategory.engine, 'attempt failed', {
          'node': node,
          'range': '$part',
          'error': '$error',
          'bytes': received,
          'ms': elapsed.roundToDouble(),
          if (busy) 'busy': true,
        });
      }
      ctx.stats.failed(node, wastedBytes: received, cancelled: cancelled);
      rethrow;
    }
  }

  Future<AttemptOutput> _transfer(
    String url,
    ByteRange part,
    AttemptProgress progress,
    double started,
    String node,
    CancelToken? cancel,
  ) {
    final done = Completer<AttemptOutput>();
    final request = CancelToken(cancel);
    StreamSubscription<List<int>>? body;
    Timer? watchdog;
    final config = ctx.config;

    void fail(Object error, [StackTrace? stack]) {
      if (done.isCompleted) return;
      done.completeError(error, stack);
      watchdog?.cancel();
      body?.cancel();
      request
        ..cancel()
        ..dispose();
    }

    void succeed(AttemptOutput output) {
      if (done.isCompleted) return;
      done.complete(output);
      watchdog?.cancel();
      request.dispose();
    }

    // One timer armed for the next deadline rather than Swift's 25 ms poll.
    void arm() {
      final now = ctx.clock.nowMs();
      if (!progress.gotHeaders && now - started > config.firstByteTimeoutMs) {
        fail(const RipperError(RipperErrorKind.firstByteTimeout));
      } else if (progress.gotHeaders && now - progress.lastProgressAt > config.stallTimeoutMs) {
        fail(const RipperError(RipperErrorKind.stalled));
      } else if (now - started > config.attemptTimeoutMs) {
        fail(const RipperError(RipperErrorKind.attemptTimeout));
      } else {
        final next = min(
          progress.gotHeaders ? progress.lastProgressAt + config.stallTimeoutMs : started + config.firstByteTimeoutMs,
          started + config.attemptTimeoutMs,
        );
        watchdog = Timer(Duration(microseconds: ((next - now + 1) * 1000).ceil()), arm);
      }
    }

    void onDone(ContentRange contentRange) {
      if (progress.received != part.length) {
        fail(RipperError.lengthMismatch(got: progress.received, expected: part.length));
        return;
      }
      final builder = BytesBuilder(copy: false);
      progress.chunks.forEach(builder.add);
      succeed(AttemptOutput(bytes: builder.takeBytes(), total: contentRange.total, url: url));
    }

    Future<void> start() async {
      final uri = Uri.tryParse(url);
      if (uri == null) throw const RipperError(RipperErrorKind.invalidURL);
      final response = await ctx.transport.fetch(uri, part, cancel: request);
      if (done.isCompleted) {
        // Lost to a timeout or a cancel while the headers were on their way: free the connection.
        unawaited(response.body.listen(null).cancel());
        return;
      }
      final now = ctx.clock.nowMs();
      progress.headers(at: now);
      ctx.stats.firstByte(node, ms: now - started);
      ctx.nodes.firstByte(url, ms: now - started);
      final contentRange = ContentRange.parse(response.headers['content-range']);
      if (response.status != 206 || contentRange == null || contentRange.range != part) {
        unawaited(response.body.listen(null).cancel());
        throw RipperError.badResponse(response.status);
      }
      body = response.body.listen(
        (chunk) => progress.append(chunk, at: ctx.clock.nowMs()),
        onError: fail,
        onDone: () => onDone(contentRange),
        cancelOnError: true,
      );
    }

    request.onCancel(() => fail(const CancelledException()));
    if (done.isCompleted) return done.future;
    arm();
    start().catchError(fail);
    return done.future;
  }
}
