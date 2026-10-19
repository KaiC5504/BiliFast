import 'dart:async';

import 'package:flutter/widgets.dart';

import '../shared/theme.dart';
import 'bili_player.dart';

/// Platforms without a player yet (Android until its ExoPlayer slice): the app still builds and opens.
final class UnsupportedPlayer implements BiliPlayer {
  final _events = StreamController<PlayerEvent>.broadcast();
  bool _disposed = false;
  bool _muted = false;

  @override
  PlayerCapabilities get capabilities => PlayerCapabilities.none;

  @override
  Stream<PlayerEvent> get events => _events.stream;

  @override
  Widget buildView() => const ColoredBox(
        color: BiliColors.videoBackground,
        child: Center(
          child: Text('这个平台还不能播放', style: TextStyle(color: BiliColors.onVideo, fontSize: 14)),
        ),
      );

  @override
  Future<void> load(PlayerSource source) async {
    _check();
    _events.add(const StatusChanged(PlayerStatus.loading));
    _events.add(const PlayerFailed('这个平台还不能播放'));
  }

  @override
  Future<void> unload() async => _check();

  @override
  Future<void> play() async => _check();

  @override
  Future<void> pause() async => _check();

  @override
  Future<void> seek(double seconds, {bool precise = false}) async => _check();

  @override
  Future<void> setRate(double rate) async => _check();

  @override
  Future<void> setMuted(bool muted) async {
    _check();
    _muted = muted;
  }

  @override
  bool get muted => _muted;

  @override
  Future<void> setKeepAwake(bool on) async => _check();

  @override
  Future<void> setFit(FitMode fit) async => _check();

  @override
  Future<void> setMirrored(bool mirrored) async => _check();

  @override
  Future<void> startPictureInPicture() async => _check();

  @override
  Future<void> stopPictureInPicture() async => _check();

  @override
  Future<void> setAutoPictureInPicture(bool enabled) async => _check();

  @override
  Future<void> setRestorable(bool restorable) async => _check();

  @override
  Future<bool> captureFrame() async {
    _check();
    return false;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _events.close();
  }

  void _check() {
    if (_disposed) throw StateError('player disposed');
  }
}
