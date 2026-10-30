// Regenerate after any change, from the repo root:
//   fvm dart run pigeon --input pigeons/offline_api.dart
// and commit both outputs (lib/offline/ios/offline_api.g.dart, ios/Runner/OfflineApi.g.swift).
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/offline/ios/offline_api.g.dart',
    swiftOut: 'ios/Runner/OfflineApi.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'OfflineApiError'),
  ),
)
/// A byte range of one track for the background session (lib/offline/offline_host.dart's BackgroundRange).
class NativeBackgroundRange {
  NativeBackgroundRange({
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

  String id;
  bool video;
  String url;
  Map<String, String> headers;
  String partPath;
  String backgroundRangesPath;
  int start;
  int end;

  /// The track's size; an answer whose Content-Range names another is refused.
  int total;
}

class NativeBackgroundRangeResult {
  NativeBackgroundRangeResult({
    required this.id,
    required this.video,
    required this.start,
    required this.end,
    required this.done,
    required this.status,
    required this.received,
  });

  String id;
  bool video;
  int start;
  int end;
  bool done;
  int status;

  /// Bytes fetched of a range not finished.
  int received;
}

/// 离线缓存's host (OfflineHost.swift): free space, backups, background time and the background URLSession
/// (`com.kaichuan.bilifast.offline`), which writes each finished range into its part file itself.
@HostApi()
abstract class OfflineHostApi {
  /// volumeAvailableCapacityForImportantUsage of the app's container; null when iOS doesn't say.
  int? freeBytes();

  /// UIApplication's applicationState is background: iOS launched the app for the background session.
  bool inBackground();

  void excludeFromBackup(String path);

  /// beginBackgroundTask; [OfflineEventApi.onGraceEnding] comes from its expiration handler.
  void beginGrace();

  void endGrace();

  /// On the background session that runs [connections] at a time per host (2, 3 or 6; each its own identifier).
  void handOff(List<NativeBackgroundRange> ranges, int connections);

  @async
  List<NativeBackgroundRangeResult> takeBack();

  /// Submits a BGContinuedProcessingTaskRequest (`com.kaichuan.bilifast.offline.continued`, strategy fail): null when
  /// iOS took it ([OfflineEventApi.onContinuedStarted] follows once it runs), else why not.
  String? beginContinued(String title, String subtitle);

  /// The task's progress in bytes, and its Live Activity's subtitle.
  void updateContinued(int done, int total, String subtitle);

  /// setTaskCompleted, or the request withdrawn when it hasn't started.
  void endContinued(bool success);
}

@FlutterApi()
abstract class OfflineEventApi {
  void onGraceEnding();

  void onRangeFinished(NativeBackgroundRangeResult result);

  void onContinuedStarted();

  /// The task's expiration handler ran: its time was up or the user cancelled it (iOS doesn't say which). [locked]:
  /// protected data was unavailable.
  void onContinuedEnded(bool locked);
}
