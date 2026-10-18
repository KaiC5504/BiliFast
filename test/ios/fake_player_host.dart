import 'dart:async';

import 'package:bilifast/player/ios/player_api.g.dart';

/// The native PlayerRegistry stand-in: records every call instead of sending it over the channel.
final class FakePlayerHost extends PlayerHostApi {
  FakePlayerHost({this.id = 7, this.pictureInPicture = true, this.captureResult = true});

  final int id;
  final bool pictureInPicture;
  final bool captureResult;
  final calls = <String>[];
  Map<String, String>? headers;

  /// While set, load replies only once it completes, as the native side does after replacing the item.
  Completer<void>? holdLoad;

  @override
  Future<int> create() async {
    calls.add('create');
    return id;
  }

  @override
  Future<bool> pictureInPictureSupported() async => pictureInPicture;

  @override
  Future<void> load(int playerId, String url, Map<String, String> headers, double startSeconds, bool autoplay) async {
    this.headers = headers;
    calls.add('load $playerId $url $startSeconds $autoplay');
    await holdLoad?.future;
  }

  @override
  Future<void> unload(int playerId) async => calls.add('unload $playerId');

  @override
  Future<void> play(int playerId) async => calls.add('play $playerId');

  @override
  Future<void> pause(int playerId) async => calls.add('pause $playerId');

  @override
  Future<void> seek(int playerId, double seconds, bool precise) async => calls.add('seek $playerId $seconds $precise');

  @override
  Future<void> setRate(int playerId, double rate) async => calls.add('rate $playerId $rate');

  @override
  Future<void> setMuted(int playerId, bool muted) async => calls.add('muted $playerId $muted');

  @override
  Future<void> setKeepAwake(bool enabled) async => calls.add('keep awake $enabled');

  @override
  Future<void> setFit(int playerId, NativeFit fit) async => calls.add('fit $playerId ${fit.name}');

  @override
  Future<void> setMirrored(int playerId, bool mirrored) async => calls.add('mirrored $playerId $mirrored');

  @override
  Future<void> startPiP(int playerId) async => calls.add('pip start $playerId');

  @override
  Future<void> stopPiP(int playerId) async => calls.add('pip stop $playerId');

  @override
  Future<void> setAutoPiP(int playerId, bool enabled) async => calls.add('pip auto $playerId $enabled');

  @override
  Future<bool> captureFrame(int playerId) async {
    calls.add('capture $playerId');
    return captureResult;
  }

  @override
  Future<void> dispose(int playerId) async => calls.add('dispose $playerId');
}
