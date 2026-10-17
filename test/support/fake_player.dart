import 'dart:async';

import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/widgets.dart';

/// Records commands and lets a test push events, for widget and controller tests on the PC.
final class FakePlayer implements BiliPlayer {
  FakePlayer({this.capabilities = const PlayerCapabilities(pictureInPicture: true, frameCapture: true)});

  @override
  final PlayerCapabilities capabilities;

  final calls = <String>[];
  PlayerSource? loaded;
  bool disposed = false;
  final _events = StreamController<PlayerEvent>.broadcast(sync: true);

  void emit(PlayerEvent event) => _events.add(event);

  @override
  Stream<PlayerEvent> get events => _events.stream;

  @override
  Widget buildView() => const ColoredBox(color: BiliColors.videoBackground, key: ValueKey('fake-video'));

  @override
  Future<void> load(PlayerSource source) async {
    _record('load ${source.master}');
    loaded = source;
    emit(const StatusChanged(PlayerStatus.loading));
  }

  @override
  Future<void> play() async => _record('play');

  @override
  Future<void> pause() async => _record('pause');

  @override
  Future<void> seek(double seconds, {bool precise = false}) async =>
      _record('seek $seconds${precise ? ' precise' : ''}');

  @override
  Future<void> setRate(double rate) async => _record('rate $rate');

  @override
  Future<void> setFit(FitMode fit) async => _record('fit ${fit.name}');

  @override
  Future<void> setMirrored(bool mirrored) async => _record('mirrored $mirrored');

  @override
  Future<void> startPictureInPicture() async => _record('pip start');

  @override
  Future<void> stopPictureInPicture() async => _record('pip stop');

  @override
  Future<void> setAutoPictureInPicture(bool enabled) async => _record('pip auto $enabled');

  @override
  Future<bool> captureFrame() async {
    _record('capture');
    return capabilities.frameCapture;
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    await _events.close();
  }

  void _record(String call) {
    if (disposed) throw StateError('player disposed');
    calls.add(call);
  }
}
