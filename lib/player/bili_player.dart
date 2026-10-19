import 'package:flutter/widgets.dart';

enum FitMode {
  fit('适应'),
  fill('填充'),
  stretch('拉伸'),
  ratio16x9('16:9'),
  ratio4x3('4:3');

  const FitMode(this.label);

  final String label;
}

enum PlayerStatus { idle, loading, buffering, playing, paused, ended }

final class PlayerCapabilities {
  const PlayerCapabilities({required this.pictureInPicture, required this.frameCapture});

  static const none = PlayerCapabilities(pictureInPicture: false, frameCapture: false);

  final bool pictureInPicture;
  final bool frameCapture;
}

final class PlayerSource {
  const PlayerSource({
    required this.master,
    this.video,
    this.audio,
    this.headers = const {},
    this.startSeconds = 0,
    this.autoplay = true,
  });

  /// The HLS master playlist on the local server.
  final Uri master;

  /// The media files behind the playlists, for a player that can't read the playlists (mpv's EDL fallback).
  final Uri? video;
  final Uri? audio;

  /// Sent with every request that leaves the phone (direct mode): User-Agent and Referer.
  final Map<String, String> headers;
  final double startSeconds;
  final bool autoplay;
}

sealed class PlayerEvent {
  const PlayerEvent();
}

final class PositionChanged extends PlayerEvent {
  const PositionChanged({required this.seconds, required this.hostMs, required this.rate});

  final double seconds;

  /// `MonotonicClock.system` when the reading reached Dart; danmaku extrapolates from it.
  final double hostMs;
  final double rate;
}

final class DurationChanged extends PlayerEvent {
  const DurationChanged(this.seconds);

  final double seconds;
}

final class BufferedChanged extends PlayerEvent {
  const BufferedChanged(this.ranges);

  final List<({double start, double end})> ranges;
}

/// Raw player state. The 0.75 s 卡顿 rule (`StallFilter`) is applied above the player, the same on every
/// platform.
final class StatusChanged extends PlayerEvent {
  const StatusChanged(this.status);

  final PlayerStatus status;
}

final class RateChanged extends PlayerEvent {
  const RateChanged(this.rate);

  final double rate;
}

final class SizeChanged extends PlayerEvent {
  const SizeChanged({required this.width, required this.height});

  final int width;
  final int height;
}

final class PlayerFailed extends PlayerEvent {
  const PlayerFailed(this.message, {this.domain, this.code, this.formatRejected = false});

  final String message;
  final String? domain;
  final int? code;

  /// The player refused the stream's format or codec, so another codec may play.
  final bool formatRejected;
}

final class PictureInPictureChanged extends PlayerEvent {
  const PictureInPictureChanged(this.active);

  final bool active;
}

/// The small window's restore button was tapped.
final class PictureInPictureRestore extends PlayerEvent {
  const PictureInPictureRestore();
}

/// AVPlayer access-log / error-log entries and the like, for DevLog's `player` category.
final class PlayerLog extends PlayerEvent {
  const PlayerLog(this.kind, this.fields);

  final String kind;
  final Map<String, Object?> fields;
}

/// One video player. Each platform has its own: AVPlayer in a native view on iOS, media_kit on Windows,
/// ExoPlayer on Android later. Everything above this interface is shared.
///
/// Rules every implementation keeps (test/support/player_contract.dart):
/// - [events] is a broadcast stream that closes on [dispose];
/// - [load] emits `StatusChanged(PlayerStatus.loading)` before it completes;
/// - picture in picture and [captureFrame] are harmless no-ops when [capabilities] says unsupported,
///   and [captureFrame] then returns false;
/// - every command after [dispose] throws [StateError].
abstract interface class BiliPlayer {
  PlayerCapabilities get capabilities;

  Stream<PlayerEvent> get events;

  /// The video surface. It takes no touches: Flutter's gestures sit above it.
  Widget buildView();

  Future<void> load(PlayerSource source);

  /// Drops the loaded item, so nothing more is buffered or decoded for it; the next [load] plays as usual.
  Future<void> unload();

  Future<void> play();

  Future<void> pause();

  Future<void> seek(double seconds, {bool precise = false});

  Future<void> setRate(double rate);

  /// Silences the sound without changing the volume it comes back at.
  Future<void> setMuted(bool muted);

  /// What the last [setMuted] asked for.
  bool get muted;

  /// Keeps the screen on while set, app-wide (the speed test runs with nobody touching the phone).
  Future<void> setKeepAwake(bool on);

  Future<void> setFit(FitMode fit);

  Future<void> setMirrored(bool mirrored);

  Future<void> startPictureInPicture();

  Future<void> stopPictureInPicture();

  /// Start picture in picture by itself when the app goes to the background while playing.
  Future<void> setAutoPictureInPicture(bool enabled);

  /// A page kept for the small window can come back for this player, so its restore button waits for the page.
  Future<void> setRestorable(bool restorable);

  /// Saves the current frame to the photo library.
  Future<bool> captureFrame();

  Future<void> dispose();
}
