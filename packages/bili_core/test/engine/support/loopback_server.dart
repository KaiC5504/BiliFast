import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

sealed class LoopbackRoute {
  const LoopbackRoute();
}

/// A 206 for the requested range of a [size]-byte file, sent at once.
final class Complete extends LoopbackRoute {
  const Complete(this.size);

  final int size;
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

/// Port of the Swift tests' LoopbackServer on a raw socket, so a test sees exactly when the client closes.
/// One request per connection, answered with `Connection: close`.
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

  Uri url(String path) => Uri.parse('http://127.0.0.1:${_socket.port}$path');

  int requests(String path) => _requests[path]?.length ?? 0;

  /// Lowercased request headers, per request.
  List<Map<String, String>> headers(String path) => _requests[path] ?? const [];

  /// Connections of [path] the client closed before the server was done with them.
  int closes(String path) => _closes[path] ?? 0;

  static Uint8List pattern(int start, int end) =>
      Uint8List.fromList([for (var index = start; index <= end; index++) (index * 31 + 7) & 0xff]);

  Future<void> stop() async {
    for (final socket in _open.toList()) {
      socket.destroy();
    }
    await _socket.close();
  }

  void _accept(Socket socket) {
    _open.add(socket);
    final buffer = BytesBuilder();
    String? path;
    var finished = false;
    void closed() {
      _open.remove(socket);
      final requested = path;
      if (requested != null && !finished) _closes[requested] = (_closes[requested] ?? 0) + 1;
    }

    socket.listen(
      (data) {
        if (path != null) return;
        buffer.add(data);
        final text = latin1.decode(buffer.toBytes());
        final end = text.indexOf('\r\n\r\n');
        if (end < 0) return;
        final lines = text.substring(0, end).split('\r\n');
        final requested = path = lines.first.split(' ')[1];
        final headers = {
          for (final line in lines.skip(1))
            if (line.contains(':'))
              line.substring(0, line.indexOf(':')).trim().toLowerCase(): line.substring(line.indexOf(':') + 1).trim(),
        };
        final seen = _requests.putIfAbsent(requested, () => []);
        seen.add(headers);
        unawaited(_answer(socket, _routes[requested], headers, first: seen.length == 1).then((done) {
          finished = done;
        }));
      },
      onDone: closed,
      onError: (Object _) => closed(),
      cancelOnError: true,
    );
  }

  /// True when the server ended the connection itself.
  Future<bool> _answer(Socket socket, LoopbackRoute? route, Map<String, String> headers, {required bool first}) async {
    switch (route) {
      case null:
        return _send(socket, 'HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n', null);
      case Hang():
        return false;
      case DropFirst() when first:
        socket.destroy();
        return true;
      case Complete(:final size) || DropFirst(:final size):
        final (start, end) = _range(headers['range'], size);
        return _send(socket, _head(start, end, size), pattern(start, end));
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

  static String _head(int start, int end, int size) => 'HTTP/1.1 206 Partial Content\r\n'
      'Content-Range: bytes $start-$end/$size\r\n'
      'Content-Length: ${end - start + 1}\r\n'
      'Connection: close\r\n\r\n';

  static (int, int) _range(String? header, int size) {
    final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(header ?? '');
    if (match == null) return (0, size - 1);
    return (int.parse(match[1]!), int.parse(match[2]!));
  }

  static Future<bool> _send(Socket socket, String head, List<int>? body) async {
    try {
      socket.write(head);
      if (body != null) socket.add(body);
      await socket.flush();
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }
}
