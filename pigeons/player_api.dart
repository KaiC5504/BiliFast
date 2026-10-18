// Regenerate after any change, from the repo root:
//   fvm dart run pigeon --input pigeons/player_api.dart
// and commit both outputs (lib/player/ios/player_api.g.dart, ios/Runner/PlayerApi.g.swift).
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/player/ios/player_api.g.dart',
    swiftOut: 'ios/Runner/PlayerApi.g.swift',
    // A second Pigeon file in ios/Runner would otherwise define PigeonError twice.
    swiftOptions: SwiftOptions(errorClassName: 'PlayerApiError'),
  ),
)
enum NativeFit { fit, fill, stretch, ratio16x9, ratio4x3 }

enum NativePlayerStatus { idle, loading, buffering, playing, paused, ended }

class NativeTimeRange {
  NativeTimeRange({required this.start, required this.end});

  double start;
  double end;
}

/// AVPlayer instances in the PlayerRegistry (ios/Runner/PlayerRegistry.swift), by id.
@HostApi()
abstract class PlayerHostApi {
  int create();

  bool pictureInPictureSupported();

  void load(int playerId, String url, Map<String, String> headers, double startSeconds, bool autoplay);

  /// Drops the item, so AVPlayer stops buffering it; the player and its view stay for the next load.
  void unload(int playerId);

  void play(int playerId);

  void pause(int playerId);

  void seek(int playerId, double seconds, bool precise);

  void setRate(int playerId, double rate);

  void setMuted(int playerId, bool muted);

  /// App-wide, not per player: the idle timer that dims and locks the screen.
  void setKeepAwake(bool enabled);

  void setFit(int playerId, NativeFit fit);

  void setMirrored(int playerId, bool mirrored);

  void startPiP(int playerId);

  void stopPiP(int playerId);

  void setAutoPiP(int playerId, bool enabled);

  /// Saves the current frame to the photo library; false without a frame or without access.
  @asyncCallback
  bool captureFrame(int playerId);

  void dispose(int playerId);
}

/// Everything a native player reports, each call tagged with its player id. The callback style keeps the
/// Swift side synchronous, so events leave in the order they happened.
@FlutterApi()
abstract class PlayerEventApi {
  @asyncCallback
  void onPosition(int playerId, double seconds, double rate);

  @asyncCallback
  void onDuration(int playerId, double seconds);

  @asyncCallback
  void onBuffered(int playerId, List<NativeTimeRange> ranges);

  @asyncCallback
  void onStatus(int playerId, NativePlayerStatus status);

  @asyncCallback
  void onRate(int playerId, double rate);

  @asyncCallback
  void onSize(int playerId, int width, int height);

  @asyncCallback
  void onFailure(int playerId, String message, String? domain, int? code, bool formatRejected);

  @asyncCallback
  void onPictureInPicture(int playerId, bool active);

  @asyncCallback
  void onPictureInPictureRestore(int playerId);

  /// Access-log and error-log entries and other player diagnostics for DevLog's `player` category.
  @asyncCallback
  void onLog(int playerId, String kind, Map<String, Object?> fields);
}
