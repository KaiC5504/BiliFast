import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

sealed class LoopbackRoute {
  const LoopbackRoute();
}

/// A 206 for the requested range of a [size]-byte file, sent at once. With [keepAlive] the connection stays open
/// for the next request, as a CDN's does.
final class Complete extends LoopbackRoute {
  const Complete(this.size, {this.keepAlive = false});

  final int size;
  final bool keepAlive;
}

/// Like [Complete], over these bytes instead of the pattern: fake media whose headers a session can parse.
final class Media extends LoopbackRoute {
  const Media(this.content, {this.keepAlive = true});

  final Uint8List content;
  final bool keepAlive;
}

/// The headers, then 1 KiB every 20 ms.
final class Trickle extends LoopbackRoute {
  const Trickle(this.size);

  final int size;
}

/// Reads the request and never answers.
final class Hang extends LoopbackRoute {
  const Hang();
}

/// The first request's connection is closed without an answer, as a stale keep-alive socket fails; later
/// requests get [Complete].
final class DropFirst extends LoopbackRoute {
  const DropFirst(this.size);

  final int size;
}

/// Keep-alive. The first request on a connection is answered; a later one on the same connection finds it closed
/// without an answer, as when Akamai closes an idle keep-alive socket just as the client sends on it.
final class StaleReuse extends LoopbackRoute {
  const StaleReuse(this.size);

  final int size;
}

/// Port of the Swift tests' LoopbackServer on a raw socket, so a test sees exactly when the client closes.
/// Answers with `Connection: close` unless the route keeps connections alive.
final class LoopbackServer {
  LoopbackServer._(this._socket, this._routes);

  static Future<LoopbackServer> start(Map<String, LoopbackRoute> routes) async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final server = LoopbackServer._(socket, routes);
    socket.listen(server._accept);
    return server;
  }

  final ServerSocket _socket;
  final Map<String, LoopbackRoute> _routes;
  final _requests = <String, List<Map<String, String>>>{};
  final _closes = <String, int>{};
  final _open = <Socket>{};
  int _connections = 0;

  int get port => _socket.port;

  Uri url(String path) => Uri.parse('http://127.0.0.1:${_socket.port}$path');

  int requests(String path) => _requests[path]?.length ?? 0;

  /// Lowercased request headers, per request.
  List<Map<String, String>> headers(String path) => _requests[path] ?? const [];

  /// Connections of [path] the client closed before the server was done with them.
  int closes(String path) => _closes[path] ?? 0;

  /// Connections accepted so far, on every path.
  int get connections => _connections;

  static Uint8List pattern(int start, int end) =>
      Uint8List.fromList([for (var index = start; index <= end; index++) (index * 31 + 7) & 0xff]);

  Future<void> stop() async {
    for (final socket in _open.toList()) {
      socket.destroy();
    }
    await _socket.close();
  }

  void _accept(Socket socket) {
    _connections += 1;
    _open.add(socket);
    final buffer = BytesBuilder();
    String? path;
    var answering = false;
    var finished = true;
    var gone = false;
    var served = 0;
    void closed() {
      if (gone) return;
      gone = true;
      _open.remove(socket);
      final requested = path;
      if (requested != null && !finished) _closes[requested] = (_closes[requested] ?? 0) + 1;
    }

    // A GET has no body, so whatever follows a request's blank line is the next request on a kept connection.
    void next() {
      if (answering || gone) return;
      final bytes = buffer.toBytes();
      final text = latin1.decode(bytes);
      final end = text.indexOf('\r\n\r\n');
      if (end < 0) return;
      buffer
        ..clear()
        ..add(bytes.sublist(end + 4));
      final lines = text.substring(0, end).split('\r\n');
      // Routes are paths: signed media URLs carry a query.
      final requested = path = lines.first.split(' ')[1].split('?').first;
      final headers = {
        for (final line in lines.skip(1))
          if (line.contains(':'))
            line.substring(0, line.indexOf(':')).trim().toLowerCase(): line.substring(line.indexOf(':') + 1).trim(),
      };
      final seen = _requests.putIfAbsent(requested, () => []);
      seen.add(headers);
      served += 1;
      answering = true;
      finished = false;
      final route = _routes[requested];
      unawaited(_answer(socket, route, headers, first: seen.length == 1, reused: served > 1).then((done) {
        finished = done;
        answering = false;
        if (done && _keepsAlive(route)) next();
      }));
    }

    socket.listen(
      (data) {
        buffer.add(data);
        next();
      },
      onDone: closed,
      onError: (Object _) => closed(),
      cancelOnError: true,
    );
  }

  static bool _keepsAlive(LoopbackRoute? route) => switch (route) {
        Complete(:final keepAlive) || Media(:final keepAlive) => keepAlive,
        StaleReuse() => true,
        _ => false,
      };

  /// True when the server is done with the request: answered it whole or ended the connection itself.
  Future<bool> _answer(
    Socket socket,
    LoopbackRoute? route,
    Map<String, String> headers, {
    required bool first,
    required bool reused,
  }) async {
    switch (route) {
      case null:
        return _send(socket, 'HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n', null);
      case Hang():
        return false;
      case DropFirst() when first:
      case StaleReuse() when reused:
        socket.destroy();
        return true;
      case Complete(:final size, :final keepAlive):
        final (start, end) = _range(headers['range'], size);
        return _send(socket, _head(start, end, size, keepAlive: keepAlive), pattern(start, end), keepAlive: keepAlive);
      case DropFirst(:final size):
        final (start, end) = _range(headers['range'], size);
        return _send(socket, _head(start, end, size), pattern(start, end));
      case StaleReuse(:final size):
        final (start, end) = _range(headers['range'], size);
        return _send(socket, _head(start, end, size, keepAlive: true), pattern(start, end), keepAlive: true);
      case Media(:final content, :final keepAlive):
        final (start, end) = _range(headers['range'], content.length);
        return _send(socket, _head(start, end, content.length, keepAlive: keepAlive),
            Uint8List.sublistView(content, start, end + 1),
            keepAlive: keepAlive);
      case Trickle(:final size):
        final (start, end) = _range(headers['range'], size);
        try {
          socket.write(_head(start, end, size));
          for (var offset = start; offset <= end; offset += 1024) {
            final last = offset + 1023 < end ? offset + 1023 : end;
            socket.add(pattern(offset, last));
            await socket.flush();
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          await socket.close();
          return true;
        } catch (_) {
          return false;
        }
    }
  }

  static String _head(int start, int end, int size, {bool keepAlive = false}) => 'HTTP/1.1 206 Partial Content\r\n'
      'Content-Range: bytes $start-$end/$size\r\n'
      'Content-Length: ${end - start + 1}\r\n'
      '${keepAlive ? '' : 'Connection: close\r\n'}\r\n';

  static (int, int) _range(String? header, int size) {
    final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(header ?? '');
    if (match == null) return (0, size - 1);
    return (int.parse(match[1]!), int.parse(match[2]!));
  }

  static Future<bool> _send(Socket socket, String head, List<int>? body, {bool keepAlive = false}) async {
    try {
      socket.write(head);
      if (body != null) socket.add(body);
      await socket.flush();
      if (!keepAlive) await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }
}
