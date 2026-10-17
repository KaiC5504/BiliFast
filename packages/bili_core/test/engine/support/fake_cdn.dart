import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';

final class NodeBehavior {
  const NodeBehavior({
    this.firstByteMs = 2,
    this.bytesPerSecond = 200e6,
    this.status = 206,
    this.truncateAfter,
    this.stallAfter,
    this.connectionLost = false,
    this.refusedQueries = const [],
  });

  final double firstByteMs;
  final double bytesPerSecond;
  final int status;

  /// The body ends early, cleanly, after this many bytes.
  final int? truncateAfter;

  /// The body stops after this many bytes and never ends until cancelled.
  final int? stallAfter;

  /// The connection drops before any header: a 0-byte reply.
  final bool connectionLost;

  /// Answer 403 to addresses whose query contains one of these, as an edge refusing a signature does.
  final List<String> refusedQueries;
}

final class ConnectionLost implements Exception {
  const ConnectionLost();

  @override
  String toString() => 'ConnectionLost';
}

/// Port of the Swift tests' SimCDN, cut down to what slice 1 needs: serves one byte pattern on every node,
/// and each node (by host[:port]) can be slow, refusing, cut short, stalled or dropping its connections.
final class FakeCDN implements RangeTransport {
  FakeCDN({required int size, Map<String, NodeBehavior> behaviors = const {}, this.connectionsPerHost})
      : content = Uint8List.fromList([for (var index = 0; index < size; index++) (index * 31 + 7) & 0xff]),
        _behaviors = Map.of(behaviors);

  final Uint8List content;
  final Map<String, NodeBehavior> _behaviors;

  @override
  final int? connectionsPerHost;

  /// Every request's full URL, in order.
  final urls = <String>[];

  /// Requests (headers pending or body streaming) running now, and the most at once.
  int inflight = 0;
  int peakInflight = 0;

  /// Requests ended by the engine before their response or body ended.
  int cancelled = 0;

  @override
  String get name => 'fake';

  @override
  void close() {}

  void set(String node, NodeBehavior behavior) => _behaviors[node] = behavior;

  List<String> get nodes => [for (final url in urls) NodeCatalog.nodeKey(url)];

  int requestsTo(String node) => nodes.where((each) => each == node).length;

  @override
  Future<TransportResponse> fetch(Uri url, ByteRange range, {CancelToken? cancel}) async {
    final text = url.toString();
    urls.add(text);
    final behavior = _behaviors[NodeCatalog.nodeKey(text)] ?? const NodeBehavior();
    var live = true;
    void end({bool byEngine = false}) {
      if (!live) return;
      live = false;
      inflight -= 1;
      if (byEngine) cancelled += 1;
    }

    inflight += 1;
    peakInflight = max(peakInflight, inflight);
    try {
      await _sleep(behavior.firstByteMs, cancel);
    } on CancelledException {
      end(byEngine: true);
      rethrow;
    }
    if (behavior.connectionLost) {
      end();
      throw const ConnectionLost();
    }
    if (behavior.refusedQueries.any(url.query.contains)) {
      end();
      return TransportResponse(status: 403, headers: const {}, body: const Stream.empty());
    }
    if (behavior.status != 206) {
      end();
      return TransportResponse(status: behavior.status, headers: const {}, body: const Stream.empty());
    }
    if (range.end >= content.length) {
      end();
      return TransportResponse(
          status: 416, headers: {'content-range': 'bytes */${content.length}'}, body: const Stream.empty());
    }
    var stopped = false;
    late final StreamController<List<int>> body;
    Future<void> pump() async {
      var offset = range.start;
      while (offset <= range.end && !stopped) {
        final sent = offset - range.start;
        if (behavior.truncateAfter case final limit? when sent >= limit) break;
        if (behavior.stallAfter case final limit? when sent >= limit) return;
        var last = min(range.end, offset + 16 * 1024 - 1);
        if (behavior.truncateAfter case final limit?) last = min(last, range.start + limit - 1);
        if (behavior.stallAfter case final limit?) last = min(last, range.start + limit - 1);
        body.add(Uint8List.sublistView(content, offset, last + 1));
        final ms = (last - offset + 1) / behavior.bytesPerSecond * 1000;
        await Future<void>.delayed(ms >= 1 ? Duration(microseconds: (ms * 1000).round()) : Duration.zero);
        offset = last + 1;
      }
      if (stopped) return;
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
    return TransportResponse(
      status: 206,
      headers: {'content-range': 'bytes ${range.start}-${range.end}/${content.length}'},
      body: body.stream,
    );
  }

  static Future<void> _sleep(double ms, CancelToken? cancel) {
    cancel?.throwIfCancelled();
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
