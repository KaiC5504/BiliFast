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

/// A lock-screen or Control Center button (MPRemoteCommandCenter), or the headphones' and car's.
enum NativeRemoteCommand { play, pause, toggle, seek, next, previous }

/// What the lock screen and Control Center show for a player. Elapsed time, duration and rate come from the AVPlayer
/// itself (MPNowPlayingSession publishes them).
class NativeNowPlaying {
  NativeNowPlaying({
    required this.title,
    required this.artist,
    this.artworkPath,
    required this.hasPrevious,
    required this.hasNext,
  });

  String title;

  /// The uploader's name.
  String artist;

  /// A picture file on the phone (the cover from the picture cache, or a cached video's cover.jpg), drawn at its own
  /// aspect.
  String? artworkPath;

  /// Whether ⏮ and ⏭ are enabled.
  bool hasPrevious;
  bool hasNext;
}

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

  /// A page kept for the small window can come back for this player: the restore button then waits for its view to be
  /// back in a window (up to 3 s) rather than ending at once.
  void setRestorable(int playerId, bool restorable);

  /// 后台听视频: on, the player keeps playing with the app in the background or the screen locked
  /// (`audiovisualBackgroundPlaybackPolicy` .continuesIfPossible); off, iOS pauses it there (.pauses). Picture in
  /// picture plays either way.
  void setBackgroundPlayback(int playerId, bool enabled);

  /// Makes this player the one the lock screen and Control Center show, with [info]; null takes it off them and
  /// disables its remote commands.
  void setNowPlaying(int playerId, NativeNowPlaying? info);

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

  /// A remote command for the player now playing; [seconds] is the position asked for, with `seek` only.
  @asyncCallback
  void onRemoteCommand(int playerId, NativeRemoteCommand command, double? seconds);

  /// An audio interruption (a call, Siri, an alarm) began or ended for the player now playing. AVPlayer has already
  /// paused itself when one begins; [shouldResume] is iOS's hint when it ends.
  @asyncCallback
  void onInterruption(int playerId, bool began, bool shouldResume);

  /// Access-log and error-log entries and other player diagnostics for DevLog's `player` category.
  @asyncCallback
  void onLog(int playerId, String kind, Map<String, Object?> fields);
}
