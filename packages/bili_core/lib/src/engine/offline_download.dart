import 'dart:async';

import '../shared/byte_range.dart';
import 'auto_concurrency.dart';
import 'node_catalog.dart';
import 'node_memory.dart';
import 'offline_types.dart';
import 'playback_engine.dart';
import 'ripper_config.dart';
import 'transport.dart';

/// The engine isolate's offline downloads (离线缓存): whole DASH files over the engine's nodes, written to disk and
/// resumable from `.ranges`. Every event goes to [emit].
final class OfflineDownloads {
  OfflineDownloads({
    required this.transport,
    required this.auto,
    required this.mode,
    required this.config,
    required this.policy,
    required this.emit,
    this.memory,
  });

  final RangeTransport transport;
  final AutoConcurrency auto;

  /// The CDN 节点 as set now.
  final NodeMode Function() mode;
  final RipperConfig config;
  final MediaURLPolicy policy;
  final NodeMemory? memory;
  final void Function(DownloadEvent event) emit;

  /// Starts or resumes [request]; returns once it runs. A request already running is left as it is.
  Future<void> start(DownloadRequest request) => throw UnimplementedError('OfflineDownloads.start');

  /// Stops [id] at once, flushes what it wrote and reports what is missing. An unknown id reports the gaps on disk
  /// for nothing: both lists empty, totals 0.
  Future<DownloadGaps> stop(String id) => throw UnimplementedError('OfflineDownloads.stop');

  void replaceUrls(String id, TrackKind track, {required String primary, required List<String> backups}) {}

  void networkChanged({required bool interfaceChanged}) {}

  /// Running downloads, for the engine's own bookkeeping.
  Iterable<String> get running => const [];

  Future<void> dispose() async {}
}

/// The ranges of `[total]` bytes not in [done] (sorted, merged, inclusive).
List<ByteRange> missingRanges(List<ByteRange> done, int total) => throw UnimplementedError('missingRanges');
