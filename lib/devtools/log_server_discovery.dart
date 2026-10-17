import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

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
  static LogServerDiscovery platform() =>
      Platform.isIOS ? const BonjourLogServerDiscovery() : const NoLogServerDiscovery();

  /// Every server found so far, updated as they come and go. Cancel to stop browsing.
  Stream<List<LogServerEndpoint>> browse();
}

/// Windows and Android: type the address by hand (on Windows the server is usually `127.0.0.1`).
final class NoLogServerDiscovery implements LogServerDiscovery {
  const NoLogServerDiscovery();

  @override
  Stream<List<LogServerEndpoint>> browse() => const Stream.empty();
}

/// iPhone: an NWBrowser in ios/Runner/LogServerDiscovery.swift, which resolves each service to an IPv4 address
/// and port. It browses while the stream has a listener.
final class BonjourLogServerDiscovery implements LogServerDiscovery {
  const BonjourLogServerDiscovery({this.channel = const EventChannel('bilifast/log_servers')});

  final EventChannel channel;

  @override
  Stream<List<LogServerEndpoint>> browse() => channel.receiveBroadcastStream().map(parse);

  static List<LogServerEndpoint> parse(Object? event) => [
        if (event is List<Object?>)
          for (final entry in event)
            if (entry case {'name': final String name, 'host': final String host, 'port': final int port})
              LogServerEndpoint(name: name, host: host, port: port),
      ];
}
