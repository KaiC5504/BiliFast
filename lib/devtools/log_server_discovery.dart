import 'dart:async';

final class LogServerEndpoint {
  const LogServerEndpoint({required this.name, required this.host, required this.port});

  /// `tools/logserver.py`'s default port in BiliNative.
  static const defaultPort = 47321;

  final String name;
  final String host;
  final int port;

  Uri get logsUrl => Uri(scheme: 'http', host: host, port: port, path: '/logs');
}

/// Finds the PC's log server (Bonjour `_bilinative-log._tcp`, port of LogServerDiscovery.swift).
abstract interface class LogServerDiscovery {
  static LogServerDiscovery platform() => const NoLogServerDiscovery();

  /// Every server found so far, updated as they come and go. Cancel to stop browsing.
  Stream<List<LogServerEndpoint>> browse();
}

/// Windows and Android: type the address by hand (on Windows the server is usually `127.0.0.1`).
final class NoLogServerDiscovery implements LogServerDiscovery {
  const NoLogServerDiscovery();

  @override
  Stream<List<LogServerEndpoint>> browse() => const Stream.empty();
}
