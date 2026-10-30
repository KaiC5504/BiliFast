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
  });

  String id;
  bool video;
  int start;
  int end;
  bool done;
  int status;
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

  void handOff(List<NativeBackgroundRange> ranges);

  @async
  List<NativeBackgroundRangeResult> takeBack();
}

@FlutterApi()
abstract class OfflineEventApi {
  void onGraceEnding();

  void onRangeFinished(NativeBackgroundRangeResult result);
}
