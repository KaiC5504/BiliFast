import 'dart:io' show Platform;

import 'package:bili_core/api.dart';
import 'package:bili_core/engine.dart';

import '../player/player_factory.dart';
import 'cupertino_transport.dart';
import 'playback_controller.dart';

/// dart:io with Bilibili's media headers, 8 connections per host. Top-level: it runs in the engine isolate.
RangeTransport createIoTransport() => IoRangeTransport(headers: BiliClient.mediaHeaders, connectionsPerHost: 8);

/// URLSession on iOS (HTTP/2 to the mirrors), dart:io elsewhere.
Future<PlaybackEngine> startPlatformEngine() =>
    PlaybackEngine.start(transportFactory: Platform.isIOS ? createCupertinoTransport : createIoTransport);

/// What the overlay shows until the engine's first stats arrive.
String get platformTransportName => Platform.isIOS ? 'URLSession' : 'dart:io';

/// The engine isolate, the platform's player and the controller that owns both.
Future<PlaybackController> startPlaybackController(BiliClient client) async {
  final engine = await startPlatformEngine();
  try {
    final player = await createPlayer();
    return PlaybackController(client: client, engine: engine, player: player, transportName: platformTransportName);
  } catch (_) {
    await engine.dispose();
    rethrow;
  }
}
