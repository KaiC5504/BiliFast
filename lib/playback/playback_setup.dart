import 'dart:io' show Platform;

import 'package:bili_core/api.dart';
import 'package:bili_core/engine.dart';

import '../devtools/log_forwarder.dart';
import '../player/player_factory.dart';
import '../video/player_prefs.dart';
import 'codec_memory.dart';
import 'cupertino_transport.dart';
import 'playback_controller.dart';

/// dart:io with Bilibili's media headers, 8 connections per host by default. Top-level: it runs in the engine
/// isolate.
RangeTransport createIoTransport({int connectionsPerHost = 8}) =>
    IoRangeTransport(headers: BiliClient.mediaHeaders, connectionsPerHost: connectionsPerHost);

/// The engine as the app runs it: Swift's defaults plus BiliFast's own startup and seek speed-ups. 8K runs
/// 15-25 MB per 5 s segment, so prefetch may hold up to 256 MiB of video ahead and 96 MiB of it behind the playhead,
/// which a memory warning trims to what is near the playhead. The last five came from 1.0.0 (1)'s phone log and won
/// the speed tests on warm 8K seeks (variant B in 1.0.0 (2) and (3)).
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
  exploreInHurry: false,
  tailBackups: true,
  banProbation: true,
  hurryKeepsOffSlow: true,
  medianEstimates: true,
  seekHurriesPrefetch: true,
  trimOnMemoryWarning: true,
  peakBandwidth: true,
);

/// Dev builds also send the engine's per-piece debug events to the log, for timing it from the phone. Node speeds are
/// remembered between launches in the app's support folder. The engine starts on 设置's CDN 节点 as saved now.
EngineOptions appEngineOptions({RipperConfig config = appRipperConfig}) => EngineOptions(
  nodeMode: PlayerPrefs.shared.node.mode,
  config: config,
  forwardDebugLogs: devToolsEnabled,
  nodeMemoryPath: nodeMemoryPath(),
);

String? nodeMemoryPath() => supportFilePath('node_memory.json');

/// Where the codecs this phone's player refused are kept (Swift's `playback.failedCodecs`).
String? codecMemoryPath() => supportFilePath('codec_memory.json');

/// [name] in the app's support folder, kept across launches; null on other platforms or without HOME/APPDATA.
String? supportFilePath(String name) {
  final env = Platform.environment;
  if (Platform.isIOS) {
    final home = env['HOME'];
    return home == null ? null : '$home/Library/Application Support/$name';
  }
  if (Platform.isWindows) {
    final appData = env['APPDATA'];
    return appData == null ? null : '$appData\\bilifast\\$name';
  }
  return null;
}

/// URLSession on iOS (HTTP/2 to the mirrors), dart:io elsewhere. The speed test starts engines with other configs;
/// [connectionsPerHost] only limits HTTP/1.1 hosts (Akamai), since an HTTP/2 mirror takes everything on one
/// connection.
Future<PlaybackEngine> startPlatformEngine({RipperConfig config = appRipperConfig, int connectionsPerHost = 8}) =>
    PlaybackEngine.start(
      transportFactory: _transportFactory(connectionsPerHost),
      options: appEngineOptions(config: config),
    );

/// The factory is sent to the engine isolate, so it captures nothing but the count.
RangeTransport Function() _transportFactory(int connectionsPerHost) => Platform.isIOS
    ? () => createCupertinoTransport(connectionsPerHost: connectionsPerHost)
    : () => createIoTransport(connectionsPerHost: connectionsPerHost);

/// What the overlay shows until the engine's first stats arrive.
String get platformTransportName => Platform.isIOS ? 'URLSession' : 'dart:io';

/// The engine isolate, the platform's player and the controller that owns both, with the codec memory read again.
Future<PlaybackController> startPlaybackController(BiliClient client) async {
  final memory = CodecMemory.load(codecMemoryPath());
  final engine = await startPlatformEngine();
  try {
    final player = await createPlayer();
    return PlaybackController(
      client: client,
      codecMemory: await memory,
      engine: engine,
      startEngine: startPlatformEngine,
      player: player,
      transportName: platformTransportName,
    );
  } catch (_) {
    await engine.dispose();
    rethrow;
  }
}
