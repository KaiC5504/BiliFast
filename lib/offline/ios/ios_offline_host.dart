import 'package:flutter/services.dart';

import '../offline_host.dart';
import 'offline_api.g.dart';

/// The phone's [OfflineHost], over Pigeon's OfflineHostApi (OfflineHost.swift).
class IosOfflineHost implements OfflineHost {
  IosOfflineHost({BinaryMessenger? binaryMessenger}) : _api = OfflineHostApi(binaryMessenger: binaryMessenger) {
    OfflineEventApi.setUp(_events, binaryMessenger: binaryMessenger);
  }

  final OfflineHostApi _api;
  final _events = _Events();

  @override
  bool get backgroundTransfers => true;

  @override
  Future<int?> freeBytes() => _api.freeBytes();

  @override
  Future<bool> inBackground() => _api.inBackground();

  @override
  Future<void> excludeFromBackup(String path) => _api.excludeFromBackup(path);

  @override
  Future<void> beginGrace() => _api.beginGrace();

  @override
  Future<void> endGrace() => _api.endGrace();

  @override
  set onGraceEnding(VoidCallback? callback) => _events.graceEnding = callback;

  @override
  Future<void> handOff(List<BackgroundRange> ranges, {int connections = OfflineHost.defaultConnections}) =>
      _api.handOff([
    for (final range in ranges)
      NativeBackgroundRange(
        id: range.id,
        video: range.video,
        url: range.url,
        headers: range.headers,
        partPath: range.partPath,
        backgroundRangesPath: range.backgroundRangesPath,
        start: range.start,
        end: range.end,
        total: range.total,
      ),
  ], connections);

  @override
  Future<List<BackgroundRangeResult>> takeBack() async => [for (final result in await _api.takeBack()) _result(result)];

  @override
  set onRangeFinished(void Function(BackgroundRangeResult result)? callback) => _events.rangeFinished = callback;

  /// How OfflineHost.swift's refusals that hold for the rest of the run begin (`ContinuedDownloads.unavailable`): a
  /// re-signed install whose bundle id no longer heads the task's identifier, or iOS's not permitted.
  static const continuedUnavailable = 'unavailable';

  bool _continuedUnavailable = false;

  /// False after such a refusal, so the library asks no more and the hand-off carries the downloads away.
  @override
  bool get continuedProcessing => !_continuedUnavailable;

  @override
  Future<String?> beginContinued({required String title, required String subtitle}) async {
    final refusal = await _api.beginContinued(title, subtitle);
    if (refusal != null && refusal.startsWith(continuedUnavailable)) _continuedUnavailable = true;
    return refusal;
  }

  @override
  Future<void> updateContinued({required int done, required int total, required String subtitle}) =>
      _api.updateContinued(done, total, subtitle);

  @override
  Future<void> endContinued({required bool success}) => _api.endContinued(success);

  @override
  set onContinuedStarted(VoidCallback? callback) => _events.continuedStarted = callback;

  @override
  set onContinuedEnded(void Function(bool locked)? callback) => _events.continuedEnded = callback;
}

final class _Events implements OfflineEventApi {
  VoidCallback? graceEnding;
  void Function(BackgroundRangeResult result)? rangeFinished;
  VoidCallback? continuedStarted;
  void Function(bool locked)? continuedEnded;

  @override
  void onGraceEnding() => graceEnding?.call();

  @override
  void onRangeFinished(NativeBackgroundRangeResult result) => rangeFinished?.call(_result(result));

  @override
  void onContinuedStarted() => continuedStarted?.call();

  @override
  void onContinuedEnded(bool locked) => continuedEnded?.call(locked);
}

BackgroundRangeResult _result(NativeBackgroundRangeResult result) => BackgroundRangeResult(
  id: result.id,
  video: result.video,
  start: result.start,
  end: result.end,
  done: result.done,
  status: result.status,
  received: result.received,
);
