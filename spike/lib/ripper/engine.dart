// Port of BTR's range-core and idm-downloader (see LICENSE-BTR.txt), by way of BiliNative's
// Attempt.swift, PieceDownloader.swift, RangeDownloader.swift, PrimaryAssigner.swift and Meter.swift.
// Kept: probe race, weighted primaries, hedged copies (three in a hurry), retry rounds, timeouts, bans.
// Left out for the spike: resumed partial pieces, damaged spans, AutoConcurrency, NodeStats' full/busy rules.

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'byte_range.dart';
import 'cancel.dart';
import 'node_catalog.dart';
import 'resolver.dart';

class RipperConfig {
  double firstByteTimeoutMs = 5500;
  double stallTimeoutMs = 4000;
  double attemptTimeoutMs = 15000;
  double hedgeDelayMs = 900;
  int minChunkBytes = 64 * 1024;
  int pieceRounds = 3;
  double retryWindowMs = 25000;
  int concurrency = 16;
  int prefetchVideoBytes = 48 << 20;
  int prefetchAudioBytes = 8 << 20;
}

enum RipperErrorKind { firstByteTimeout, stalled, attemptTimeout, badResponse, lengthMismatch, totalMismatch, noNodes }

class RipperError implements Exception {
  const RipperError(this.kind, [this.status]);
  final RipperErrorKind kind;
  final int? status;
  bool get isTimeout =>
      kind == RipperErrorKind.firstByteTimeout || kind == RipperErrorKind.stalled || kind == RipperErrorKind.attemptTimeout;
  @override
  String toString() => status == null ? kind.name : '${kind.name}($status)';
}

class Permit {
  Permit._(this._pool);
  final ConnectionPool _pool;
  bool _released = false;
  void release() {
    if (_released) return;
    _released = true;
    _pool._release();
  }
}

class _Waiter {
  _Waiter(this.priority, this.seq);
  final double Function() priority;
  final int seq;
  final completer = Completer<void>();
}

/// A connection limit shared by every request of the playback; the waiter with the highest priority goes next.
class ConnectionPool {
  ConnectionPool(this.limit);
  int limit;
  int active = 0;
  int _seq = 0;
  final _waiters = <_Waiter>[];

  int get queued => _waiters.length;

  Future<Permit> acquire(double Function() priority, CancelToken token) async {
    token.throwIfCancelled();
    if (active < limit && _waiters.isEmpty) {
      active++;
      return Permit._(this);
    }
    final w = _Waiter(priority, _seq++);
    _waiters.add(w);
    final remove = token.onCancel(() {
      if (_waiters.remove(w)) w.completer.completeError(const CancelledException());
    });
    try {
      await w.completer.future;
    } finally {
      remove();
    }
    final permit = Permit._(this);
    if (token.isCancelled) {
      permit.release();
      throw const CancelledException();
    }
    return permit;
  }

  void _release() {
    active--;
    _pump();
  }

  void _pump() {
    while (active < limit && _waiters.isNotEmpty) {
      var best = _waiters.first;
      var bestPriority = best.priority();
      for (final w in _waiters.skip(1)) {
        final p = w.priority();
        if (p > bestPriority || (p == bestPriority && w.seq < best.seq)) {
          best = w;
          bestPriority = p;
        }
      }
      _waiters.remove(best);
      active++;
      best.completer.complete();
    }
  }
}

double _smoothed(double old, double sample) => old > 0 ? old * 0.7 + sample * 0.3 : sample;

/// What one connection typically delivers and how long a piece typically takes (BTR `meter`).
class Meter {
  static const sampleMinBytes = 48 * 1024;
  double connectionBps = 0;
  double pieceMs = 0;

  void record(int bytes, double elapsedMs) {
    if (bytes < sampleMinBytes || elapsedMs <= 0) return;
    connectionBps = _smoothed(connectionBps, bytes * 1000 / elapsedMs);
    pieceMs = _smoothed(pieceMs, elapsedMs);
  }

  /// A piece should keep its connection busy for a good part of a second; 64 KiB until the speed is known,
  /// never above 1 MiB, and small enough that a range still spreads over the nodes.
  int adaptiveMinChunk(int base, int rangeLength, int pieceLimit, int hostCount) {
    if (connectionBps <= 0) return base;
    final target = (connectionBps * 0.6 / 65536).floor() * 65536;
    final ways = max(1, min(max(4, hostCount), pieceLimit));
    final spread = (rangeLength + ways - 1) ~/ ways;
    return max(base, min(1 << 20, min(target, spread)));
  }

  double hedgeDelayMs(double configured) => pieceMs > 0 ? max(250, min(configured, (pieceMs * 1.5).roundToDouble())) : configured;
}

class NodeCounters {
  int bytes = 0;
  int pieces = 0;
  int failures = 0;
  int cancelled = 0;
  double ttfbMs = 0;
}

class EngineStats {
  int bytes = 0;
  int wastedBytes = 0;
  int pieces = 0;
  int hedges = 0;
  int failures = 0;
  final nodes = <String, NodeCounters>{};
  final errors = <String, int>{};
  final _window = <(double, int)>[];

  NodeCounters node(String key) => nodes.putIfAbsent(key, NodeCounters.new);

  void received(String node, int n) {
    bytes += n;
    this.node(node).bytes += n;
    _window.add((nowMs(), n));
  }

  /// Bytes per second over the last two seconds.
  double get recentBps {
    final cutoff = nowMs() - 2000;
    _window.removeWhere((e) => e.$1 < cutoff);
    final sum = _window.fold<int>(0, (a, e) => a + e.$2);
    return sum / 2;
  }
}

class AttemptProgress {
  bool started = false;
  double startedAt = 0;
  bool gotHeaders = false;
  double headersAt = 0;
  double lastProgressAt = 0;
  int received = 0;
  int length = 0;
  bool failed = false;
  bool outrun = false;
  String? url;
}

class AttemptOutput {
  AttemptOutput(this.bytes, this.total, this.url);
  final Uint8List bytes;
  final int? total;
  final String url;
}

enum PieceMode { normal, startup, probe }

class EngineContext {
  EngineContext(this.http, this.config) : pool = ConnectionPool(config.concurrency);
  final HttpClient http;
  final RipperConfig config;
  final ConnectionPool pool;
  final meter = Meter();
  final stats = EngineStats();

  /// dart:io speaks HTTP/1.1 only, so every request in flight holds its own connection; past
  /// `HttpClient.maxConnectionsPerHost` a request would wait inside the client with its first-byte clock running.
  static const connectionsPerNode = 8;
  final _inflight = <String, int>{};

  bool isFull(String url) => (_inflight[NodeCatalog.nodeKey(url)] ?? 0) >= connectionsPerNode;
  void begin(String url) => _inflight.update(NodeCatalog.nodeKey(url), (n) => n + 1, ifAbsent: () => 1);
  void end(String url) => _inflight.update(NodeCatalog.nodeKey(url), (n) => n - 1, ifAbsent: () => 0);
}

const _mediaHeaders = {
  'User-Agent':
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15',
  'Referer': 'https://www.bilibili.com/',
};

class AttemptRunner {
  AttemptRunner(this.ctx);
  final EngineContext ctx;

  /// One request for `piece` to the URL `claim` picks once a connection is held: BTR's three timeouts,
  /// the 206 Content-Range check, and the outcome reported to the resolver, meter and stats.
  Future<AttemptOutput> run({
    required String Function() claim,
    required ByteRange piece,
    required AttemptProgress progress,
    required Resolver resolver,
    required double Function() priority,
    required CancelToken token,
  }) async {
    final permit = await ctx.pool.acquire(priority, token);
    String? claimed;
    try {
      final url = claimed = claim();
      ctx.begin(url);
      progress.url = url;
      final node = NodeCatalog.nodeKey(url);
      final started = nowMs();
      progress
        ..started = true
        ..startedAt = started
        ..lastProgressAt = started
        ..length = piece.length;
      try {
        final out = await _transfer(url, piece, progress, token, node);
        final elapsed = max(1.0, nowMs() - started);
        ctx.meter.record(piece.length, elapsed);
        ctx.stats.pieces++;
        ctx.stats.node(node).pieces++;
        resolver.success(url, piece.length >= Meter.sampleMinBytes ? piece.length * 1000 / elapsed : 0);
        return out;
      } catch (e) {
        final elapsed = max(1.0, nowMs() - started);
        if (e is CancelledException) {
          ctx.stats.node(node).cancelled++;
          if (progress.received >= Meter.sampleMinBytes) resolver.sample(url, progress.received * 1000 / elapsed);
        } else {
          ctx.stats.failures++;
          ctx.stats.node(node).failures++;
          final key = '$node ${e is RipperError ? e : e.runtimeType} got ${progress.received > 0 ? '>0' : '0'}';
          ctx.stats.errors.update(key, (n) => n + 1, ifAbsent: () => 1);
          resolver.failure(url, status: e is RipperError ? e.status : null, receivedBytes: progress.received);
        }
        ctx.stats.wastedBytes += progress.received;
        rethrow;
      }
    } finally {
      if (claimed != null) ctx.end(claimed);
      permit.release();
    }
  }

  Future<AttemptOutput> _transfer(String url, ByteRange part, AttemptProgress p, CancelToken token, String node) {
    final done = Completer<AttemptOutput>();
    HttpClientRequest? request;
    StreamSubscription<List<int>>? sub;
    Timer? watchdog;
    void Function()? unlink;
    final cfg = ctx.config;
    final started = p.startedAt;

    void finish(Object? error, [AttemptOutput? out]) {
      if (done.isCompleted) return;
      watchdog?.cancel();
      unlink?.call();
      if (error != null) {
        sub?.cancel();
        request?.abort(error);
        done.completeError(error);
      } else {
        done.complete(out);
      }
    }

    unlink = token.onCancel(() => finish(const CancelledException()));
    if (done.isCompleted) return done.future;
    watchdog = Timer.periodic(const Duration(milliseconds: 25), (_) {
      final now = nowMs();
      if (!p.gotHeaders && now - started > cfg.firstByteTimeoutMs) {
        finish(const RipperError(RipperErrorKind.firstByteTimeout));
      } else if (p.gotHeaders && now - p.lastProgressAt > cfg.stallTimeoutMs) {
        finish(const RipperError(RipperErrorKind.stalled));
      } else if (now - started > cfg.attemptTimeoutMs) {
        finish(const RipperError(RipperErrorKind.attemptTimeout));
      }
    });

    () async {
      try {
        final req = await ctx.http.getUrl(Uri.parse(url));
        if (done.isCompleted) {
          req.abort();
          return;
        }
        request = req;
        _mediaHeaders.forEach(req.headers.set);
        req.headers.set('Range', part.header);
        final res = await req.close();
        if (done.isCompleted) {
          res.listen(null).cancel();
          return;
        }
        final now = nowMs();
        p
          ..gotHeaders = true
          ..headersAt = now
          ..lastProgressAt = now;
        final counters = ctx.stats.node(node);
        counters.ttfbMs = _smoothed(counters.ttfbMs, now - started);
        final cr = parseContentRange(res.headers.value('content-range'));
        if (res.statusCode != 206 || cr == null || cr.$1 != part) {
          res.listen(null).cancel();
          finish(RipperError(RipperErrorKind.badResponse, res.statusCode));
          return;
        }
        final builder = BytesBuilder(copy: false);
        sub = res.listen(
          (chunk) {
            builder.add(chunk);
            p
              ..received += chunk.length
              ..lastProgressAt = nowMs();
            ctx.stats.received(node, chunk.length);
          },
          onError: (Object e) => finish(e),
          onDone: () {
            if (p.received != part.length) {
              finish(const RipperError(RipperErrorKind.lengthMismatch));
            } else {
              finish(null, AttemptOutput(builder.takeBytes(), cr.$2, url));
            }
          },
          cancelOnError: true,
        );
      } catch (e) {
        finish(e);
      }
    }();
    return done.future;
  }
}

class PieceDownloader {
  PieceDownloader(this.ctx) : runner = AttemptRunner(ctx);
  final EngineContext ctx;
  final AttemptRunner runner;

  /// One piece, in up to `pieceRounds` rounds. Each round walks the candidates a few at a time: the first copy
  /// starts at once, the next once the one before is late; the first to finish wins and the others are cancelled.
  Future<AttemptOutput> download({
    required ByteRange piece,
    required int index,
    required Resolver resolver,
    required List<String> preferred,
    required PieceMode mode,
    required bool Function() hurry,
    required double Function() priority,
    required CancelToken token,
  }) async {
    final started = nowMs();
    Object lastError = const RipperError(RipperErrorKind.noNodes);
    for (var round = 0; round < ctx.config.pieceRounds; round++) {
      if (round > 0) {
        if (nowMs() - started > ctx.config.retryWindowMs) break;
        await sleepMs(min(2000, 500 * pow(2, round - 1)), token);
      }
      final candidates = _candidates(preferred, resolver, index, round);
      final limit = min(8, candidates.length);
      final tried = <String>{};
      while (tried.length < limit) {
        token.throwIfCancelled();
        final untried = candidates.where((u) => !tried.contains(u)).toList();
        final allowed = untried.where(resolver.allows).toList();
        final targets = allowed.isNotEmpty ? allowed : untried;
        if (targets.isEmpty) break;
        final width = min(targets.length, mode == PieceMode.probe ? limit : (hurry() ? 3 : 2));
        final progresses = [for (var i = 0; i < width; i++) AttemptProgress()];
        try {
          return await _race(targets, progresses, piece, resolver, mode, hurry, priority, token);
        } catch (e) {
          if (token.isCancelled) rethrow;
          lastError = e;
        }
        final used = [for (final p in progresses) ?p.url];
        tried.addAll(used.isEmpty ? [targets.first] : used);
      }
    }
    throw lastError;
  }

  /// Copy k waits on copy k - 1. A copy takes its node once it holds a connection permit: the first candidate no other
  /// copy took that has room, or the first one left when every node is full (BiliNative `CopyTargets`).
  Future<AttemptOutput> _race(List<String> targets, List<AttemptProgress> copies, ByteRange piece, Resolver resolver,
      PieceMode mode, bool Function() hurry, double Function() priority, CancelToken token) {
    final race = CancelToken(token);
    final result = Completer<AttemptOutput>();
    var pending = copies.length;
    final taken = <String>{};
    String claim() {
      final left = targets.where((u) => !taken.contains(u)).toList();
      final url = left.where((u) => !ctx.isFull(u)).firstOrNull ?? left.firstOrNull ?? targets.first;
      taken.add(url);
      return url;
    }

    String previousUrl(int i) => copies[i - 1].url ?? targets.first;
    Object lastError = const RipperError(RipperErrorKind.noNodes);

    void settle(Object? error) {
      if (error != null && error is! CancelledException) lastError = error;
      pending--;
      if (pending == 0 && !result.isCompleted) {
        result.completeError(token.isCancelled ? const CancelledException() : lastError);
      }
    }

    for (var i = 0; i < copies.length; i++) {
      () async {
        try {
          if (i > 0) {
            final go = await _waitForCopy(i, copies[i - 1], () => previousUrl(i), targets, piece.length, resolver, mode, hurry, race);
            if (!go) {
              settle(null);
              return;
            }
            ctx.stats.hedges++;
          }
          final out = await runner.run(
            claim: claim,
            piece: piece,
            progress: copies[i],
            resolver: resolver,
            priority: () => priority() + (i > 0 ? 20 : 0),
            token: race,
          );
          if (!result.isCompleted) {
            for (final c in copies) {
              c.outrun = true;
            }
            result.complete(out);
            race.cancel();
          }
          settle(null);
        } catch (e) {
          copies[i].failed = true;
          settle(e);
        }
      }();
    }
    return result.future.whenComplete(race.dispose);
  }

  Future<bool> _waitForCopy(int position, AttemptProgress previous, String Function() previousUrl, List<String> candidates, int pieceLength,
      Resolver resolver, PieceMode mode, bool Function() hurry, CancelToken race) async {
    if (mode == PieceMode.probe) return true;
    final measured = ctx.meter.hedgeDelayMs(ctx.config.hedgeDelayMs);
    final delay = mode == PieceMode.startup ? min(250.0, measured) : measured;
    while (true) {
      race.throwIfCancelled();
      final hurried = hurry();
      if (previous.failed) return hurried || position == 1;
      if (hurried) {
        if (previous.started && _hurryHedgeDue(previous, previousUrl(), pieceLength, candidates, resolver)) return true;
      } else if (position == 1 && previous.started && _hedgeDue(previous, delay)) {
        return true;
      }
      await sleepMs(50, race);
    }
  }

  bool _hedgeDue(AttemptProgress first, double delayMs) {
    final now = nowMs();
    final ran = now - first.startedAt;
    if (ran < delayMs) return false;
    if (first.received == 0 || now - first.lastProgressAt >= delayMs) return true;
    final rate = first.received * 1000 / ran;
    final usual = ctx.meter.connectionBps;
    return usual > 0 && rate < usual * 0.6;
  }

  double? _expectedMs(String url, int pieceBytes, Resolver resolver) {
    final bps = resolver.speed(url);
    if (bps <= 0) return null;
    return ctx.stats.node(NodeCatalog.nodeKey(url)).ttfbMs + pieceBytes * 1000 / bps;
  }

  /// BTR PR 11 `overdue`: late to its first byte (twice its node's usual, within 250-600 ms), stopped for 1 s,
  /// or past twice its expected time with under three quarters in.
  bool _hurryHedgeDue(AttemptProgress previous, String url, int pieceLength, List<String> candidates, Resolver resolver) {
    final now = nowMs();
    final ttfb = ctx.stats.node(NodeCatalog.nodeKey(url)).ttfbMs;
    final elapsed = now - previous.startedAt;
    if (!previous.gotHeaders) return elapsed >= (ttfb > 0 ? (ttfb * 2).clamp(250, 600) : 250);
    if (now - previous.lastProgressAt >= 1000) return true;
    final known = [for (final c in candidates) ?_expectedMs(c, pieceLength, resolver)];
    final expected = _expectedMs(url, pieceLength, resolver) ?? (known.isEmpty ? ctx.config.hedgeDelayMs : known.reduce(min));
    return elapsed >= max(400, expected * 2) && previous.received < pieceLength * 0.75;
  }

  /// BTR `pieceCandidates`: the assigned node first, then the fastest known nodes.
  static List<String> _candidates(List<String> preferred, Resolver resolver, int pieceIndex, int round) {
    final offset = preferred.isEmpty ? 0 : round % preferred.length;
    final rotated = [...preferred.sublist(offset), ...preferred.sublist(0, offset)];
    final rescue = resolver.rescueCandidates().where((u) => !rotated.contains(u));
    final rest = [...rotated.skip(1), ...rescue]..sort((a, b) => resolver.speed(b).compareTo(resolver.speed(a)));
    final list = rotated.isEmpty ? rest : [rotated.first, ...rest];
    for (final u in resolver.ordered(pieceIndex: pieceIndex)) {
      if (!list.contains(u)) list.add(u);
    }
    return list;
  }
}

class RangeDownloader {
  RangeDownloader(this.ctx) : pieces = PieceDownloader(ctx);
  final EngineContext ctx;
  final PieceDownloader pieces;
  int _turn = 0;

  /// BTR `downloadStartupRange`: init and index in one request, raced over up to three nodes started
  /// 0, 120 and 300 ms apart.
  Future<AttemptOutput> meta(ByteRange range, Resolver resolver, CancelToken token) async {
    Object lastError = const RipperError(RipperErrorKind.noNodes);
    for (var round = 0; round < ctx.config.pieceRounds; round++) {
      if (round > 0) await sleepMs(500 * round, token);
      var candidates = resolver.startupCandidates().take(3).toList();
      if (candidates.isEmpty) candidates = resolver.ordered(pieceIndex: round).take(3).toList();
      if (candidates.isEmpty) break;
      final race = CancelToken(token);
      final result = Completer<AttemptOutput>();
      var pending = candidates.length;
      const delays = [0, 120, 300];
      for (var i = 0; i < candidates.length; i++) {
        () async {
          try {
            await sleepMs(delays[i], race);
            final out = await pieces.runner.run(
                claim: () => candidates[i], piece: range, progress: AttemptProgress(), resolver: resolver, priority: () => 220, token: race);
            if (!result.isCompleted) result.complete(out);
            race.cancel();
          } catch (e) {
            if (e is! CancelledException) lastError = e;
          }
          if (--pending == 0 && !result.isCompleted) result.completeError(lastError);
        }();
      }
      try {
        return await result.future;
      } catch (e) {
        if (token.isCancelled) throw const CancelledException();
      } finally {
        race.dispose();
      }
    }
    throw lastError;
  }

  /// The bytes of `range` in file order, each piece handed to `emit` as soon as it and all before it are in.
  Future<void> run(
    ByteRange range,
    Resolver resolver, {
    required bool startup,
    required bool Function() hurry,
    required double Function() priority,
    required int? expectedTotal,
    required void Function(Uint8List) emit,
    required CancelToken token,
  }) async {
    var knownTotal = expectedTotal;
    void check(AttemptOutput out) {
      final t = out.total;
      if (t == null) return;
      if (knownTotal != null && knownTotal != t) throw const RipperError(RipperErrorKind.totalMismatch);
      knownTotal = t;
    }

    final hurried = hurry();
    var preferred = resolver.rangeCandidates();
    var assignable = preferred;
    var remaining = range;
    var indexOffset = 0;
    // In a hurry with nodes already measured, placement by speed takes the place of the race.
    if (startup && !(hurried && preferred.any((u) => resolver.speed(u) > 0))) {
      final headLength = min(range.length, max(64 * 1024, ctx.config.minChunkBytes));
      final head = ByteRange(range.start, range.start + headLength - 1);
      final out = await pieces.download(
          piece: head,
          index: 0,
          resolver: resolver,
          preferred: preferred,
          mode: PieceMode.probe,
          hurry: hurry,
          priority: () => 220,
          token: token);
      check(out);
      emit(out.bytes);
      if (head.end >= range.end) return;
      remaining = ByteRange(head.end + 1, range.end);
      preferred = [out.url, ...preferred.where((u) => u != out.url)];
      assignable = preferred.where((u) => u == out.url || resolver.speed(u) > 0).toList();
      indexOffset = 1;
    }
    final concurrency = ctx.pool.limit;
    final reserve = concurrency >= 8 ? min(8, max(1, (concurrency + 7) ~/ 8)) : 0;
    final pieceConcurrency = max(1, concurrency - reserve);
    final minChunk = hurried
        ? ctx.config.minChunkBytes
        : ctx.meter.adaptiveMinChunk(ctx.config.minChunkBytes, remaining.length, pieceConcurrency, preferred.length);
    final parts = remaining.split(pieceConcurrency, minChunk);
    final primaries = _assign(assignable, parts.length, resolver);
    final mode = startup ? PieceMode.startup : PieceMode.normal;

    final local = CancelToken(token);
    final ready = <int, AttemptOutput>{};
    var next = 0;
    final allDone = Completer<void>();
    var left = parts.length;
    for (var offset = 0; offset < parts.length; offset++) {
      final primary = offset < primaries.length ? primaries[offset] : preferred.first;
      final piecePreferred = [primary, ...preferred.where((u) => u != primary)];
      final pieceIndex = offset + indexOffset;
      () async {
        try {
          final out = await pieces.download(
            piece: parts[offset],
            index: pieceIndex,
            resolver: resolver,
            preferred: piecePreferred,
            mode: mode,
            hurry: hurry,
            priority: () => startup ? 120.0 - min(30, pieceIndex) : priority() - min(20, pieceIndex) * 0.1,
            token: local,
          );
          if (allDone.isCompleted) return;
          check(out);
          ready[offset] = out;
          while (ready.containsKey(next)) {
            emit(ready.remove(next)!.bytes);
            next++;
          }
          if (--left == 0) allDone.complete();
        } catch (e) {
          if (!allDone.isCompleted) {
            allDone.completeError(e);
            local.cancel();
          }
        }
      }();
    }
    try {
      await allDone.future;
    } finally {
      local.dispose();
    }
  }

  /// BTR `assignPrimaries`, simplified: faster nodes get more pieces in smooth weighted turns, a node under a
  /// twelfth of the fastest gets none, unmeasured nodes get a quarter of the pieces as trials.
  List<String> _assign(List<String> urls, int count, Resolver resolver) {
    if (urls.isEmpty || count <= 0) return const [];
    if (urls.length == 1) return List.filled(count, urls.first);
    final turn = _turn++;
    final speeds = urls.map(resolver.speed).toList();
    final top = speeds.reduce(max);
    if (top <= 0) return [for (var i = 0; i < count; i++) urls[(i + turn) % urls.length]];
    final known = [for (var i = 0; i < urls.length; i++) if (speeds[i] >= top / 12) urls[i]];
    final unknown = [for (var i = 0; i < urls.length; i++) if (speeds[i] == 0) urls[i]];
    final trials = min(unknown.length * 2, count ~/ 4);
    final weights = known.map((u) => max(resolver.speed(u), top * 0.05)).toList();
    final credit = List.filled(known.length, 0.0);
    final total = weights.fold<double>(0, (a, b) => a + b);
    final out = <String>[];
    for (var n = 0; n < count - trials; n++) {
      var best = 0;
      for (var i = 0; i < known.length; i++) {
        credit[i] += weights[i];
        if (credit[i] > credit[best]) best = i;
      }
      credit[best] -= total;
      out.add(known[best]);
    }
    for (var i = 0; i < trials; i++) {
      out.add(unknown[(i + turn) % unknown.length]);
    }
    return out;
  }
}
