import '../api/live_models.dart';
import '../devlog/logger.dart';
import 'live_events.dart';

/// A room's danmaku feed as the room model sees it; [LiveSocket] on the network, a fake in tests and `--fake-account`.
abstract interface class LiveChannel {
  Stream<LiveEvent> get events;
  Stream<LiveSocketState> get states;

  /// Connects (again, after [close]); the hosts are tried in turn and a dropped connection comes back with a backoff.
  Future<void> start();
  Future<void> close();
}

/// The website's danmaku websocket (`wss://host:port/sub`), authenticated with [info]'s token as [uid] (0 logged out).
/// [headers] go with the upgrade (User-Agent, Origin, the `buvid3` cookie).
final class LiveSocket implements LiveChannel {
  LiveSocket({
    required this.roomId,
    required this.uid,
    required this.info,
    this.headers = const {},
    Logger? logger,
  }) : _logger = logger ?? Logger.shared;

  final int roomId;
  final int uid;
  final LiveDanmuInfo info;
  final Map<String, String> headers;
  // ignore: unused_field
  final Logger _logger;

  @override
  Stream<LiveEvent> get events => const Stream.empty();

  @override
  Stream<LiveSocketState> get states => const Stream.empty();

  @override
  Future<void> start() => throw UnimplementedError('LiveSocket.start');

  @override
  Future<void> close() async {}
}
