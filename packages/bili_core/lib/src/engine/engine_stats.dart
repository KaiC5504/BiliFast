import 'meter.dart';
import 'playback_engine.dart';

final class _Timing {
  int requests = 0;
  int failures = 0;
  double firstByteMs = 0;
}

/// Port of EngineStats.swift; [snapshot] gives the overlay's [EngineSnapshot].
final class EngineStats {
  int deliveredBytes = 0;
  int duplicateBytes = 0;
  int requests = 0;
  int failures = 0;
  int cacheHits = 0;
  int cacheMisses = 0;
  final _timings = <String, _Timing>{};

  void started(String node) {
    requests += 1;
    _timings.putIfAbsent(node, _Timing.new).requests += 1;
  }

  void firstByte(String node, {required double ms}) {
    final timing = _timings.putIfAbsent(node, _Timing.new);
    timing.firstByteMs = smoothed(timing.firstByteMs, ms);
  }

  void failed(String node, {required int wastedBytes, required bool cancelled}) {
    duplicateBytes += wastedBytes;
    if (cancelled) return;
    failures += 1;
    _timings.putIfAbsent(node, _Timing.new).failures += 1;
  }

  void delivered(int bytes) => deliveredBytes += bytes;

  void cache({required bool hit}) {
    if (hit) {
      cacheHits += 1;
    } else {
      cacheMisses += 1;
    }
  }

  EngineSnapshot snapshot({
    required int concurrency,
    required List<NodeStatus> nodeStates,
    double downloadBps = 0,
    String transport = '',
  }) {
    final nodes = _timings.keys.toList()..sort();
    return EngineSnapshot(
      deliveredBytes: deliveredBytes,
      duplicateBytes: duplicateBytes,
      requests: requests,
      failures: failures,
      cacheHits: cacheHits,
      cacheMisses: cacheMisses,
      concurrency: concurrency,
      nodes: [
        for (final node in nodes)
          NodeTiming(
            node: node,
            requests: _timings[node]!.requests,
            failures: _timings[node]!.failures,
            firstByteMs: _timings[node]!.firstByteMs,
          ),
      ],
      nodeStates: nodeStates,
      downloadBps: downloadBps,
      transport: transport,
    );
  }
}
