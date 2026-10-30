import 'package:flutter/foundation.dart';

/// A byte range of one track handed to iOS's background transfers when the app leaves the foreground.
@immutable
final class BackgroundRange {
  const BackgroundRange({
    required this.id,
    required this.video,
    required this.url,
    required this.headers,
    required this.partPath,
    required this.backgroundRangesPath,
    required this.start,
    required this.end,
  });

  /// The part's id (its cid as text).
  final String id;

  /// The video track, else audio.
  final bool video;
  final String url;
  final Map<String, String> headers;

  /// The track's `.part` file, written in place at [start].
  final String partPath;

  /// The track's `.bg-ranges` file, where a finished range is listed (`DownloadRanges`).
  final String backgroundRangesPath;

  /// Inclusive.
  final int start;
  final int end;
}

/// What became of a range handed off.
@immutable
final class BackgroundRangeResult {
  const BackgroundRangeResult({
    required this.id,
    required this.video,
    required this.start,
    required this.end,
    required this.done,
    required this.status,
  });

  final String id;
  final bool video;
  final int start;
  final int end;

  /// Written to its part file and listed in its `.bg-ranges`.
  final bool done;

  /// The HTTP status; -1 for a transport error, 0 for a range cancelled or still waiting.
  final int status;
}

/// The phone's side of 离线缓存: free space, backups, the time iOS gives a backgrounded app, and background transfers.
/// Windows and tests have none of it ([NoOfflineHost]).
abstract class OfflineHost {
  /// Background transfers exist on this platform.
  bool get backgroundTransfers;

  /// Bytes free for important use; null when unknown.
  Future<int?> freeBytes();

  /// Keeps [path] (a folder) out of iCloud and computer backups.
  Future<void> excludeFromBackup(String path);

  /// Asks iOS for time to finish after the app leaves the foreground; [onGraceEnding] runs shortly before it ends.
  Future<void> beginGrace();
  Future<void> endGrace();
  set onGraceEnding(VoidCallback? callback);

  /// Queues [ranges] on the background session; they go on while the app is suspended or closed.
  Future<void> handOff(List<BackgroundRange> ranges);

  /// Cancels every range still queued and reports each one handed off since the last call.
  Future<List<BackgroundRangeResult>> takeBack();

  /// A range finished while the app was running.
  set onRangeFinished(void Function(BackgroundRangeResult result)? callback);
}

/// No background transfers and no grace: the engine downloads only while the app runs.
class NoOfflineHost implements OfflineHost {
  const NoOfflineHost({this.free});

  final int? free;

  @override
  bool get backgroundTransfers => false;

  @override
  Future<int?> freeBytes() async => free;

  @override
  Future<void> excludeFromBackup(String path) async {}

  @override
  Future<void> beginGrace() async {}

  @override
  Future<void> endGrace() async {}

  @override
  set onGraceEnding(VoidCallback? callback) {}

  @override
  Future<void> handOff(List<BackgroundRange> ranges) async {}

  @override
  Future<List<BackgroundRangeResult>> takeBack() async => const [];

  @override
  set onRangeFinished(void Function(BackgroundRangeResult result)? callback) {}
}
