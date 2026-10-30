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
    required this.total,
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

  /// The track's size: an answer for another size (the part restarted meanwhile) is refused, never written.
  final int total;
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
    this.received = 0,
  });

  final String id;
  final bool video;
  final int start;
  final int end;

  /// Written to its part file and listed in its `.bg-ranges`.
  final bool done;

  /// Bytes iOS had fetched of a range it didn't finish: lost with it, except for status -4, where they are the ones
  /// written.
  final int received;

  /// The HTTP status; 0 for a range cancelled or still waiting, -1 for a transport error, -2 when its part file
  /// couldn't be written (or was gone), -3 when the answer wasn't the range asked for (its Content-Range or total), -4
  /// when it was shorter (what came, [received] bytes, is written and listed; the engine fetches the rest).
  final int status;
}

/// The phone's side of 离线缓存: free space, backups, the time iOS gives a backgrounded app, and background transfers.
/// Windows and tests have none of it ([NoOfflineHost]).
abstract class OfflineHost {
  /// Background transfers exist on this platform.
  bool get backgroundTransfers;

  /// Bytes free for important use; null when unknown.
  Future<int?> freeBytes();

  /// iOS runs the app in the background (launched for the background session); asked when Flutter has no lifecycle
  /// state yet.
  Future<bool> inBackground();

  /// Keeps [path] (a folder) out of iCloud and computer backups.
  Future<void> excludeFromBackup(String path);

  /// Asks iOS for time to finish after the app leaves the foreground; [onGraceEnding] runs shortly before it ends.
  Future<void> beginGrace();
  Future<void> endGrace();
  set onGraceEnding(VoidCallback? callback);

  /// Queues [ranges] on the background session that runs [connections] at a time per host (one of
  /// [handOffConnections]); they go on while the app is suspended or closed.
  Future<void> handOff(List<BackgroundRange> ranges, {int connections = defaultConnections});

  /// Cancels every range still queued and reports each one handed off since the last call.
  Future<List<BackgroundRangeResult>> takeBack();

  /// A range finished while the app was running.
  set onRangeFinished(void Function(BackgroundRangeResult result)? callback);

  /// iOS 26's continued processing (BGContinuedProcessingTask): asked for as the user starts downloads, it keeps the
  /// app running after it leaves, under a Live Activity showing the progress, until the work ends, iOS expires it or
  /// the user cancels it there. One at a time.
  bool get continuedProcessing;

  /// Submits the request; null when iOS took it ([onContinuedStarted] follows once it runs), else why not.
  Future<String?> beginContinued({required String title, required String subtitle});

  /// The Live Activity's progress, in bytes, and its subtitle.
  Future<void> updateContinued({required int done, required int total, required String subtitle});

  /// Ends the task, or withdraws a request not yet started; [success] false shows it as failed.
  Future<void> endContinued({required bool success});

  set onContinuedStarted(VoidCallback? callback);

  /// iOS expired the task: its time was up or the user cancelled it (iOS doesn't say which). [locked]: protected data
  /// was unavailable, so the device was locked.
  set onContinuedEnded(void Function(bool locked)? callback);

  /// The background sessions' connections per host, each its own session (`OfflineHost.swift`).
  static const handOffConnections = [2, 3, 6];
  static const defaultConnections = 3;
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
  Future<bool> inBackground() async => false;

  @override
  Future<void> excludeFromBackup(String path) async {}

  @override
  Future<void> beginGrace() async {}

  @override
  Future<void> endGrace() async {}

  @override
  set onGraceEnding(VoidCallback? callback) {}

  @override
  Future<void> handOff(List<BackgroundRange> ranges, {int connections = OfflineHost.defaultConnections}) async {}

  @override
  Future<List<BackgroundRangeResult>> takeBack() async => const [];

  @override
  set onRangeFinished(void Function(BackgroundRangeResult result)? callback) {}

  @override
  bool get continuedProcessing => false;

  @override
  Future<String?> beginContinued({required String title, required String subtitle}) async => 'unavailable';

  @override
  Future<void> updateContinued({required int done, required int total, required String subtitle}) async {}

  @override
  Future<void> endContinued({required bool success}) async {}

  @override
  set onContinuedStarted(VoidCallback? callback) {}

  @override
  set onContinuedEnded(void Function(bool locked)? callback) {}
}
