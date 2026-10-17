import 'playback_router.dart';

/// The loopback HTTP server the player reads from (port of the app's LocalServer.swift).
final class LocalServer {
  static Future<LocalServer> start(PlaybackRouter router) => throw UnimplementedError('port of LocalServer.swift');

  int get port => throw UnimplementedError('port of LocalServer.swift');

  /// `http://127.0.0.1:<port>/<token>/<name>`.
  Uri url(String token, String name) => throw UnimplementedError('port of LocalServer.swift');

  /// Probes the server over loopback: iOS can silently take a suspended app's listening socket.
  Future<bool> answers() => throw UnimplementedError('port of LocalServer.swift');

  /// Binds again on a new port with the same router. URLs handed out earlier stop working.
  Future<void> restart() => throw UnimplementedError('port of LocalServer.swift');

  Future<void> close() => throw UnimplementedError('port of LocalServer.swift');
}
