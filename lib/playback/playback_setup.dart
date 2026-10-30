import 'dart:io' show Directory, File, Platform;

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:path_provider/path_provider.dart';

import '../devtools/log_forwarder.dart';
import '../player/player_factory.dart';
import '../video/player_prefs.dart';
import 'codec_memory.dart';
import 'cupertino_transport.dart';
import 'playback_controller.dart';
import 'shared_engine.dart';

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

String? _iosSupportFolder;

/// The files the app keeps in its support folder, for the launch's check.
const _supportFiles = [
  'player_prefs.json',
  'recents.json',
  'font.json',
  'search_history.json',
  'danmaku_settings.json',
  'emotes_recent.json',
  'codec_memory.json',
  'node_memory.json',
  'log_server.json',
  'app_device.json',
  'me.json',
  'history_outbox.json',
];

/// Asks iOS where the app's Application Support folder is, once per launch, before any store loads. A TestFlight
/// update moves the app's container, so the folder is looked up each launch and never kept; logs whether it exists
/// and which of the app's files it holds (names only: the path carries the container's id). [isIOS], [lookup] and
/// [home] are for tests.
Future<void> resolveSupportFolder({
  Logger? logger,
  bool? isIOS,
  Future<Directory> Function() lookup = getApplicationSupportDirectory,
  String? home,
}) async {
  if (!(isIOS ?? Platform.isIOS)) return;
  final log = logger ?? Logger.shared;
  _iosSupportFolder = null;
  try {
    _iosSupportFolder = (await lookup()).path;
  } catch (error) {
    log.error(LogCategory.app, 'support folder lookup failed', {'error': '${error.runtimeType}'});
  }
  final folder = _iosSupportFolder;
  log.info(LogCategory.app, 'support folder', {
    'resolved': folder != null,
    'sameAsHome': folder != null && folder == _homeSupportFolder(home),
    'exists': folder != null && await Directory(folder).exists(),
    'files': [
      for (final name in _supportFiles)
        if (folder != null && await File('$folder/$name').exists()) name,
    ].join(','),
  });
}

String? _homeSupportFolder(String? home) {
  final folder = home ?? Platform.environment['HOME'];
  return folder == null ? null : '$folder/Library/Application Support';
}

/// [name] in the app's support folder, kept across launches; null on other platforms or without HOME/APPDATA.
/// [isIOS] and [home] are for tests.
String? supportFilePath(String name, {bool? isIOS, String? home}) {
  if (isIOS ?? Platform.isIOS) {
    final folder = _iosSupportFolder ?? _homeSupportFolder(home);
    return folder == null ? null : '$folder/$name';
  }
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
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

/// One page's controller: a player of its own on a lease of the app's [engine], which is also where it goes for a new
/// one once the engine isolate is gone.
Future<PlaybackController> startPlaybackController(
  BiliClient client, {
  required SharedEngine engine,
  required CodecMemory codecMemory,
}) async {
  final lease = await engine.lease();
  try {
    final player = await createPlayer();
    return PlaybackController(
      client: client,
      codecMemory: codecMemory,
      engine: lease,
      startEngine: engine.lease,
      player: player,
      transportName: platformTransportName,
    );
  } catch (_) {
    await lease.dispose();
    rethrow;
  }
}
