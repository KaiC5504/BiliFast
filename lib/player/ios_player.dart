import 'package:flutter/widgets.dart';

import 'bili_player.dart';

/// AVPlayer in a native view (`bilifast/player`), driven over Pigeon.
final class IosPlayer implements BiliPlayer {
  static Future<IosPlayer> create() => throw UnimplementedError('iOS native agent');

  @override
  PlayerCapabilities get capabilities => throw UnimplementedError('iOS native agent');

  @override
  Stream<PlayerEvent> get events => throw UnimplementedError('iOS native agent');

  @override
  Widget buildView() => throw UnimplementedError('iOS native agent');

  @override
  Future<void> load(PlayerSource source) => throw UnimplementedError('iOS native agent');

  @override
  Future<void> play() => throw UnimplementedError('iOS native agent');

  @override
  Future<void> pause() => throw UnimplementedError('iOS native agent');

  @override
  Future<void> seek(double seconds, {bool precise = false}) => throw UnimplementedError('iOS native agent');

  @override
  Future<void> setRate(double rate) => throw UnimplementedError('iOS native agent');

  @override
  Future<void> setFit(FitMode fit) => throw UnimplementedError('iOS native agent');

  @override
  Future<void> setMirrored(bool mirrored) => throw UnimplementedError('iOS native agent');

  @override
  Future<void> startPictureInPicture() => throw UnimplementedError('iOS native agent');

  @override
  Future<void> stopPictureInPicture() => throw UnimplementedError('iOS native agent');

  @override
  Future<void> setAutoPictureInPicture(bool enabled) => throw UnimplementedError('iOS native agent');

  @override
  Future<bool> captureFrame() => throw UnimplementedError('iOS native agent');

  @override
  Future<void> dispose() => throw UnimplementedError('iOS native agent');
}
