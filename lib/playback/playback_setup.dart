import 'dart:io' show Platform;

import 'package:bili_core/api.dart';
import 'package:bili_core/engine.dart';

import '../devtools/log_forwarder.dart';
import '../player/player_factory.dart';
import 'cupertino_transport.dart';
import 'playback_controller.dart';

/// dart:io with Bilibili's media headers, 8 connections per host. Top-level: it runs in the engine isolate.
RangeTransport createIoTransport() => IoRangeTransport(headers: BiliClient.mediaHeaders, connectionsPerHost: 8);

/// The engine as the app runs it: Swift's defaults plus BiliFast's own startup and seek speed-ups. 8K runs
/// 15-25 MB per 5 s segment, so prefetch may hold up to 256 MiB of video ahead and 96 MiB of it behind the playhead,
/// which a memory warning drops.
const appRipperConfig = RipperConfig(
  primeStart: true,
  prefetchOnPrime: true,
  streamAdopted: true,
  seekBurst: true,
  audioFirst: true,
  prefetchFollowsRate: true,
  prefetchVideoMaxBytes: 256 * 1024 * 1024,
  prefetchAudioMaxBytes: 16 * 1024 * 1024,
  keepBehindSeconds: 30,
  keepBehindBytes: 96 * 1024 * 1024,
);

/// Dev builds also send the engine's per-piece debug events to the log, for timing it from the phone.
const appEngineOptions = EngineOptions(config: appRipperConfig, forwardDebugLogs: devToolsEnabled);

/// URLSession on iOS (HTTP/2 to the mirrors), dart:io elsewhere.
Future<PlaybackEngine> startPlatformEngine() => PlaybackEngine.start(
    transportFactory: Platform.isIOS ? createCupertinoTransport : createIoTransport, options: appEngineOptions);

/// What the overlay shows until the engine's first stats arrive.
String get platformTransportName => Platform.isIOS ? 'URLSession' : 'dart:io';

/// The engine isolate, the platform's player and the controller that owns both.
Future<PlaybackController> startPlaybackController(BiliClient client) async {
  final engine = await startPlatformEngine();
  try {
    final player = await createPlayer();
    return PlaybackController(
        client: client,
        engine: engine,
        startEngine: startPlatformEngine,
        player: player,
        transportName: platformTransportName);
  } catch (_) {
    await engine.dispose();
    rethrow;
  }
}
