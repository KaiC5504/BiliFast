import 'package:flutter/widgets.dart';

import 'bili_player.dart';

/// media_kit (mpv) for development on Windows.
final class WindowsPlayer implements BiliPlayer {
  static Future<WindowsPlayer> create() => throw UnimplementedError('Windows player agent');

  @override
  PlayerCapabilities get capabilities => throw UnimplementedError('Windows player agent');

  @override
  Stream<PlayerEvent> get events => throw UnimplementedError('Windows player agent');

  @override
  Widget buildView() => throw UnimplementedError('Windows player agent');

  @override
  Future<void> load(PlayerSource source) => throw UnimplementedError('Windows player agent');

  @override
  Future<void> play() => throw UnimplementedError('Windows player agent');

  @override
  Future<void> pause() => throw UnimplementedError('Windows player agent');

  @override
  Future<void> seek(double seconds, {bool precise = false}) => throw UnimplementedError('Windows player agent');

  @override
  Future<void> setRate(double rate) => throw UnimplementedError('Windows player agent');

  @override
  Future<void> setFit(FitMode fit) => throw UnimplementedError('Windows player agent');

  @override
  Future<void> setMirrored(bool mirrored) => throw UnimplementedError('Windows player agent');

  @override
  Future<void> startPictureInPicture() => throw UnimplementedError('Windows player agent');

  @override
  Future<void> stopPictureInPicture() => throw UnimplementedError('Windows player agent');

  @override
  Future<void> setAutoPictureInPicture(bool enabled) => throw UnimplementedError('Windows player agent');

  @override
  Future<bool> captureFrame() => throw UnimplementedError('Windows player agent');

  @override
  Future<void> dispose() => throw UnimplementedError('Windows player agent');
}
