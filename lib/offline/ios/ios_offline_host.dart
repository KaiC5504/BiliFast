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
  Future<void> handOff(List<BackgroundRange> ranges) => _api.handOff([
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
  ]);

  @override
  Future<List<BackgroundRangeResult>> takeBack() async => [for (final result in await _api.takeBack()) _result(result)];

  @override
  set onRangeFinished(void Function(BackgroundRangeResult result)? callback) => _events.rangeFinished = callback;
}

final class _Events implements OfflineEventApi {
  VoidCallback? graceEnding;
  void Function(BackgroundRangeResult result)? rangeFinished;

  @override
  void onGraceEnding() => graceEnding?.call();

  @override
  void onRangeFinished(NativeBackgroundRangeResult result) => rangeFinished?.call(_result(result));
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
