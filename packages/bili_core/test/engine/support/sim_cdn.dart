import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bili_core/src/engine/attempt.dart';
import 'package:bili_core/src/engine/ban_list.dart';
import 'package:bili_core/src/engine/connection_pool.dart';
import 'package:bili_core/src/engine/resolver.dart';

/// How one simulated node (by host[:port]) answers.
final class NodeBehavior {
  const NodeBehavior({
    this.firstByteMs = 2,
    this.bytesPerSecond = 200e6,
    this.status = 206,
    this.failForMs = 0,
    this.connectionLost = false,
    this.truncateAfter,
    this.stallAfter,
    this.wrongRange = false,
    this.omitContentRange = false,
    this.extraBytes = 0,
    this.totalSize,
    this.coldRequests = 0,
    this.coldFirstByteMs = 0,
    this.lateFirstByteFromRequest,
    this.refusedQueries = const [],
    this.missing,
    this.coldRange,
    this.coldRangeFirstByteMs = 0,
    this.coldRangeBytesPerSecond,
    this.missEvery,
    this.missFirstByteMs = 0,
  });

  final double firstByteMs;
  final double bytesPerSecond;
  final int status;

  /// Throw connection errors until this long after the SimCDN was created.
  final double failForMs;

  /// The connection drops before any header, every time: a 0-byte reply.
  final bool connectionLost;

  /// The body ends early, cleanly, after this many bytes.
  final int? truncateAfter;

  /// The body stops after this many bytes and never ends until cancelled.
  final int? stallAfter;

  /// The response starts one byte late while claiming the requested range.
  final bool wrongRange;

  /// A 206 without a Content-Range header.
  final bool omitContentRange;

  /// Send this many bytes past the requested end while still claiming the requested range.
  final int extraBytes;

  /// The total the Content-Range advertises, when it should differ from the content size.
  final int? totalSize;

  /// The first this many requests the node serves take [coldFirstByteMs] to the first byte, as on a CDN edge
  /// that does not have the file cached yet.
  final int coldRequests;
  final double coldFirstByteMs;

  /// From this request on (counting from 1, per node) the first byte takes [coldFirstByteMs], as when a node is
  /// busy sending other pieces and queues new requests behind them.
  final int? lateFirstByteFromRequest;

  /// Answer 403 at once, as an edge refusal does, to addresses whose query contains one of these.
  final List<String> refusedQueries;

  /// Bytes this node's copy lacks, as Akamai's copy of one file lacked 109972 through the end of its first MiB
  /// on 2026-10-16: a request starting inside gets no response, one running into it is cut off there.
  final ByteRange? missing;

  /// A request starting inside this span waits [coldRangeFirstByteMs] for its first byte and then runs at
  /// [coldRangeBytesPerSecond], as an edge does over a part of the file it has not served lately.
  final ByteRange? coldRange;
  final double coldRangeFirstByteMs;
  final double? coldRangeBytesPerSecond;

  /// Every this many requests (per node) misses the edge's cache and takes [missFirstByteMs] to its first byte, as a
  /// fifth of Akamai's did on the phone (1.0.0 (1)): 75% under 48 ms, the misses over 400 ms.
  final int? missEvery;
  final double missFirstByteMs;
}

final class ConnectionLost implements Exception {
  const ConnectionLost();

  @override
  String toString() => 'ConnectionLost';
}

/// Port of the Swift tests' SimCDN: serves one byte pattern on every node, and each node (by host[:port]) can be
/// made slow, broken or refusing. Akamai nodes share [connectionsPerHost] connections each, as URLSession's
/// `httpMaximumConnectionsPerHost` on HTTP/1.1.
final class SimCDN implements RangeTransport {
  SimCDN({required int size, Map<String, NodeBehavior> behaviors = const {}, this.connectionsPerHost})
    : content = Uint8List.fromList([for (var index = 0; index < size; index++) (index * 31 + 7) & 0xff]),
      _behaviors = Map.of(behaviors),
      _connections = connectionsPerHost == null ? null : HostConnections(connectionsPerHost);

  final Uint8List content;
  final Map<String, NodeBehavior> _behaviors;
  final HostConnections? _connections;
  final _born = Stopwatch()..start();
  final _served = <String, int>{};

  @override
  final int? connectionsPerHost;

  /// Every request's full URL, in order.
  final urls = <String>[];

  /// Bytes of responses sent to the end, per full URL; copies cancelled midway are not counted.
  final deliveredBytes = <String, int>{};

  /// Requests (headers pending or body streaming) running now, and the most at once.
  int inflight = 0;
  int peakInflight = 0;

  /// Requests ended by the engine before their response or body ended.
  int cancelled = 0;

  @override
  String get name => 'sim';

  @override
  void close() {}

  void set(String node, NodeBehavior behavior) => _behaviors[node] = behavior;

  /// Every request's node, in order.
  List<String> get requests => [for (final url in urls) NodeCatalog.nodeKey(url)];

  int get requestCount => urls.length;

  int requestsTo(String node) => requests.where((each) => each == node).length;

  /// The most requests that were waiting at once for one of the node's connections.
  int peakWaiting(String node) => _connections?.peakWaiting(node) ?? 0;

  @override
  Future<TransportResponse> fetch(Uri url, ByteRange range, {CancelToken? cancel}) async {
    final text = url.toString();
    final node = NodeCatalog.nodeKey(text);
    urls.add(text);
    final behavior = _behaviors[node] ?? const NodeBehavior();
    final hostConnections = NodeCatalog.isAkamai(text) ? _connections : null;
    var live = true;
    // Frees the connection before the engine can see the response end, as a finished response frees its own.
    void end({bool byEngine = false}) {
      if (!live) return;
      live = false;
      inflight -= 1;
      if (byEngine) cancelled += 1;
      hostConnections?.close(node);
    }

    inflight += 1;
    peakInflight = max(peakInflight, inflight);
    try {
      await hostConnections?.open(node, cancel);
    } on CancelledException {
      live = false;
      inflight -= 1;
      cancelled += 1;
      rethrow;
    }
    final TransportResponse? early;
    try {
      early = await _head(node, behavior, url, range, cancel);
    } on CancelledException {
      end(byEngine: true);
      rethrow;
    } catch (_) {
      end();
      rethrow;
    }
    if (early != null) {
      end();
      return early;
    }
    final served = behavior.wrongRange ? (ByteRange.of(range.start + 1, range.end) ?? range) : range;
    final bodyEnd = min(content.length - 1, served.end + behavior.extraBytes);
    final missingStart = behavior.missing?.start;
    final cutAt = missingStart != null && missingStart > served.start && missingStart <= bodyEnd ? missingStart : null;
    final coldSpan = _holds(behavior.coldRange, range.start);
    final bytesPerSecond = coldSpan
        ? behavior.coldRangeBytesPerSecond ?? behavior.bytesPerSecond
        : behavior.bytesPerSecond;
    var stopped = false;
    late final StreamController<List<int>> body;
    Future<void> pump() async {
      var offset = served.start;
      while (offset <= bodyEnd && !stopped) {
        final sent = offset - served.start;
        if (behavior.truncateAfter case final limit? when sent >= limit) break;
        if (behavior.stallAfter case final limit? when sent >= limit) return;
        var last = min(bodyEnd, offset + 16 * 1024 - 1);
        // Cut chunks exactly at the truncation and stall points.
        if (behavior.truncateAfter case final limit?) last = min(last, served.start + limit - 1);
        if (behavior.stallAfter case final limit?) last = min(last, served.start + limit - 1);
        if (cutAt != null) {
          if (offset >= cutAt) {
            end();
            body.addError(const ConnectionLost());
            await body.close();
            return;
          }
          last = min(last, cutAt - 1);
        }
        body.add(Uint8List.sublistView(content, offset, last + 1));
        final ms = (last - offset + 1) / bytesPerSecond * 1000;
        await Future<void>.delayed(ms >= 1 ? Duration(microseconds: (ms * 1000).round()) : Duration.zero);
        offset = last + 1;
      }
      if (stopped) return;
      if (offset > bodyEnd) deliveredBytes[text] = (deliveredBytes[text] ?? 0) + bodyEnd - served.start + 1;
      end();
      await body.close();
    }

    body = StreamController<List<int>>(
      onListen: () => unawaited(pump()),
      onCancel: () {
        stopped = true;
        end(byEngine: true);
      },
    );
    final total = behavior.totalSize ?? content.length;
    return TransportResponse(
      status: 206,
      headers: behavior.omitContentRange ? const {} : {'content-range': 'bytes ${served.start}-${served.end}/$total'},
      body: body.stream,
    );
  }

  /// Everything before the body: the refusal, the wait for the first byte, connection losses and error statuses.
  /// Null when a 206 body follows.
  Future<TransportResponse?> _head(
    String node,
    NodeBehavior behavior,
    Uri url,
    ByteRange range,
    CancelToken? cancel,
  ) async {
    if (behavior.refusedQueries.any(url.query.contains)) {
      await _sleep(2, cancel);
      return TransportResponse(status: 403, headers: const {}, body: const Stream.empty());
    }
    final number = (_served[node] ?? 0) + 1;
    _served[node] = number;
    final cold = number <= behavior.coldRequests || number >= (behavior.lateFirstByteFromRequest ?? 1 << 62);
    final coldSpan = _holds(behavior.coldRange, range.start);
    final every = behavior.missEvery;
    final miss = every != null && number % every == 0;
    await _sleep(
      coldSpan
          ? behavior.coldRangeFirstByteMs
          : cold
          ? behavior.coldFirstByteMs
          : miss
          ? behavior.missFirstByteMs
          : behavior.firstByteMs,
      cancel,
    );
    if (behavior.connectionLost || _born.elapsedMicroseconds / 1000 < behavior.failForMs) {
      throw const ConnectionLost();
    }
    if (behavior.status != 206) {
      return TransportResponse(status: behavior.status, headers: const {}, body: const Stream.empty());
    }
    if (range.end >= content.length) {
      return TransportResponse(
        status: 416,
        headers: {'content-range': 'bytes */${content.length}'},
        body: const Stream.empty(),
      );
    }
    if (_holds(behavior.missing, range.start)) throw const ConnectionLost();
    return null;
  }

  static bool _holds(ByteRange? span, int offset) => span != null && offset >= span.start && offset <= span.end;

  static Future<void> _sleep(double ms, CancelToken? cancel) {
    cancel?.throwIfCancelled();
    final completer = Completer<void>();
    void Function() remove = () {};
    final timer = Timer(Duration(microseconds: (ms * 1000).round()), () {
      remove();
      completer.complete();
    });
    remove =
        cancel?.onCancel(() {
          timer.cancel();
          if (!completer.isCompleted) completer.completeError(const CancelledException());
        }) ??
        remove;
    return completer.future;
  }
}

/// One HTTP/1.1 client's connections per host: a request beyond the limit waits, before anything is sent, until a
/// response ends and hands its connection over.
final class HostConnections {
  HostConnections(this.limit);

  final int limit;
  final _open = <String, int>{};
  final _waiting = <String, List<Completer<void>>>{};
  final _peakWaiting = <String, int>{};

  int peakWaiting(String node) => _peakWaiting[node] ?? 0;

  Future<void> open(String node, CancelToken? cancel) async {
    cancel?.throwIfCancelled();
    if ((_open[node] ?? 0) < limit) {
      _open[node] = (_open[node] ?? 0) + 1;
      return;
    }
    final waiter = Completer<void>();
    final queue = _waiting.putIfAbsent(node, () => []);
    queue.add(waiter);
    _peakWaiting[node] = max(peakWaiting(node), queue.length);
    final remove = cancel?.onCancel(() {
      if (queue.remove(waiter)) waiter.completeError(const CancelledException());
    });
    try {
      await waiter.future;
    } finally {
      remove?.call();
    }
  }

  void close(String node) {
    final queue = _waiting[node];
    if (queue != null && queue.isNotEmpty) {
      queue.removeAt(0).complete();
      return;
    }
    _open[node] = max(0, (_open[node] ?? 0) - 1);
  }
}

abstract final class TestEngine {
  static const primary = 'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/v.m4s?deadline=9&os=cosbv';
  static const cosov = 'upos-sz-mirrorcosov.bilivideo.com';
  static const aliov = 'upos-sz-mirroraliov.bilivideo.com';
  static const hk1 = 'cn-hk-eq-01-01.bilivideo.com';
  static const hk3 = 'cn-hk-eq-01-03.bilivideo.com';

  static const config = RipperConfig(
    firstByteTimeoutMs: 300,
    stallTimeoutMs: 300,
    attemptTimeoutMs: 3000,
    hedgeDelayMs: 100,
    retryWindowMs: 5000,
    fixedConcurrency: 8,
  );

  /// Slow simulated nodes pause between chunks; leave room for that on a loaded machine.
  static final slowConfig = config.copyWith(stallTimeoutMs: 2000);

  static EngineContext context(RangeTransport cdn, {RipperConfig config = config, AutoConcurrency? auto}) =>
      EngineContext(
        transport: cdn,
        pool: ConnectionPool(config.fixedConcurrency ?? auto?.threads ?? 8),
        config: config,
        auto: auto,
        logger: Logger(session: 'test'),
      );

  static Resolver resolver() => Resolver(primary: primary, backups: const [], mode: NodeMode.overseas, bans: BanList());

  static String on(String node, [String url = primary]) => NodeCatalog.swapHost(url, NodeAddress(node))!;
}

/// Polls [condition] every 10 ms for up to [seconds].
Future<bool> eventually(bool Function() condition, {double seconds = 2}) async {
  final deadline = DateTime.now().add(Duration(microseconds: (seconds * 1e6).round()));
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return condition();
}
