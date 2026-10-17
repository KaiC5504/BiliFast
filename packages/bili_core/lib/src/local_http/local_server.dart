import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../devlog/log_event.dart';
import '../devlog/logger.dart';
import 'http_request_parser.dart';
import 'http_response_writer.dart';
import 'playback_router.dart';

/// The loopback HTTP server the player reads from (port of the app's LocalServer.swift).
///
/// HTTP/1.1 on 127.0.0.1, one request per connection. The player fetches HLS playlists and media ranges from
/// here; media bodies stream from the engine as they arrive. Written on a raw [ServerSocket] rather than
/// `HttpServer` because AVPlayer is picky: `Connection: close`, an exact Content-Length and never chunked
/// encoding is the response shape it accepted on the phone.
final class LocalServer {
  LocalServer._(this.router);

  static Future<LocalServer> start(PlaybackRouter router) async {
    final server = LocalServer._(router);
    await server.restart();
    return server;
  }

  final PlaybackRouter router;

  /// Called when a running listener stops, whether the system ended it or [close] did, so playback can fall
  /// back. A listener that [restart] replaces stops quietly: nothing can be using it.
  void Function()? onStop;

  ServerSocket? _listener;
  StreamSubscription<Socket>? _accepting;
  int _port = 0;
  int _generation = 0;
  Future<void>? _binding;
  final _connections = <_Connection>{};

  bool get isRunning => _listener != null;

  /// The port last bound. It keeps its value after [close], when nothing answers on it any more.
  int get port => _port;

  /// `http://127.0.0.1:<port>/<token>/<name>`.
  Uri url(String token, String name) => Uri.parse('http://127.0.0.1:$_port/$token/$name');

  /// Probes the server over loopback: iOS can silently take a suspended app's listening socket, so a server
  /// that says it is running is asked whether it still answers a request.
  Future<bool> answers({Duration timeout = const Duration(milliseconds: 500)}) async {
    if (!isRunning) return false;
    final clock = Stopwatch()..start();
    final Socket socket;
    try {
      socket = await Socket.connect(InternetAddress.loopbackIPv4, _port, timeout: timeout);
    } catch (_) {
      return false;
    }
    socket.done.ignore();
    try {
      socket.add(_probe);
      final left = timeout - clock.elapsed;
      return await _readsStatusLine(socket).timeout(left.isNegative ? Duration.zero : left);
    } catch (_) {
      return false;
    } finally {
      socket.destroy();
    }
  }

  static final _probe = latin1.encode('HEAD / HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n');

  static Future<bool> _readsStatusLine(Socket socket) async {
    const statusPrefix = 'HTTP/1.1 ';
    final bytes = <int>[];
    await for (final chunk in socket) {
      bytes.addAll(chunk);
      if (bytes.length >= statusPrefix.length) break;
    }
    return bytes.length >= statusPrefix.length && latin1.decode(bytes.sublist(0, statusPrefix.length)) == statusPrefix;
  }

  /// Binds again on a new port with the same router. URLs handed out earlier stop working.
  ///
  /// Concurrent callers share one bind. Throws [StateError] if [close] runs before the bind completes.
  Future<void> restart() {
    final pending = _binding;
    if (pending != null) return pending;
    late final Future<void> binding;
    binding = _bind().whenComplete(() {
      if (identical(_binding, binding)) _binding = null;
    });
    return _binding = binding;
  }

  Future<void> _bind() async {
    final generation = ++_generation;
    final ServerSocket listener;
    try {
      listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    } catch (error) {
      if (generation == _generation) {
        Logger.shared.error(LogCategory.server, 'listener failed', {'error': '$error'});
        _dropListener();
      }
      rethrow;
    }
    // A close() during the bind: a later restart() must begin a new listener, not inherit this one.
    if (generation != _generation) {
      await listener.close();
      throw StateError('LocalServer closed while binding');
    }
    // Dropped only now, so the new port can't be the old one.
    _dropListener();
    _listener = listener;
    _port = listener.port;
    _accepting = listener.listen(
      _accept,
      onError: (Object error) => _lost(listener, error),
      onDone: () => _lost(listener, null),
      cancelOnError: true,
    );
    Logger.shared.info(LogCategory.server, 'listening', {'port': _port});
  }

  /// Stops listening without reporting a stop; connections already open carry on.
  void _dropListener() {
    final listener = _listener;
    if (listener == null) return;
    _listener = null;
    _accepting?.cancel().ignore();
    _accepting = null;
    listener.close().ignore();
  }

  void _lost(ServerSocket listener, Object? error) {
    if (!identical(_listener, listener)) return;
    _listener = null;
    _accepting = null;
    listener.close().ignore();
    if (error == null) {
      Logger.shared.warn(LogCategory.server, 'listener stopped');
    } else {
      Logger.shared.error(LogCategory.server, 'listener failed', {'error': '$error'});
    }
    onStop?.call();
  }

  /// Stops listening and ends every open connection, which cancels the media reads behind them.
  Future<void> close() async {
    _generation++;
    _binding = null;
    final listener = _listener;
    _listener = null;
    final accepting = _accepting;
    _accepting = null;
    for (final connection in List.of(_connections)) {
      connection.end();
    }
    if (listener == null) return;
    await accepting?.cancel();
    await listener.close();
    Logger.shared.warn(LogCategory.server, 'listener stopped');
    onStop?.call();
  }

  void _accept(Socket socket) {
    final connection = _Connection(socket, _connections.remove);
    _connections.add(connection);
    final buffer = <int>[];
    var answered = false;
    connection.input = socket.listen(
      (data) {
        // One request per connection: anything after the head is noise.
        if (answered) return;
        buffer.addAll(data);
        switch (HTTPRequestParser.parse(buffer)) {
          case HTTPParseIncomplete():
            break;
          case HTTPParseInvalid():
            answered = true;
            _reject(connection);
          case HTTPParseComplete(:final head):
            answered = true;
            _respond(connection, head);
        }
      },
      // A close means the player gave up on the request; its engine read should stop now rather than at the
      // next failed send.
      onDone: connection.end,
      onError: (Object _) => connection.end(),
      cancelOnError: true,
    );
  }

  Future<void> _reject(_Connection connection) async {
    await connection.send(
      HTTPResponseWriter.head(status: 400, headers: [('Content-Length', '0'), ('Connection', 'close')]),
    );
    await connection.finish();
  }

  Future<void> _respond(_Connection connection, HTTPRequestHead head) async {
    final started = Stopwatch()..start();
    final isHead = head.method == 'HEAD';
    try {
      switch (router.route(head)) {
        case RouteText(:final status, :final contentType, :final body):
          final bytes = BytesBuilder(copy: false)
            ..add(
              HTTPResponseWriter.head(
                status: status,
                headers: [('Content-Type', contentType), ('Content-Length', '${body.length}'), ('Connection', 'close')],
              ),
            );
          if (!isHead) bytes.add(body);
          await connection.send(bytes.takeBytes());
          _log(head, status: status, bytes: isHead ? 0 : body.length, started: started);
        case RouteFailure(:final status, :final headers):
          await connection.send(
            HTTPResponseWriter.head(
              status: status,
              headers: [...headers, ('Content-Length', '0'), ('Connection', 'close')],
            ),
          );
          _log(head, status: status, bytes: 0, started: started);
        case RouteMedia(:final status, :final headers, :final body):
          final headBytes = HTTPResponseWriter.head(status: status, headers: [...headers, ('Connection', 'close')]);
          if (!await connection.send(headBytes)) {
            _log(head, status: status, bytes: 0, started: started);
            return;
          }
          final (sent, firstByteMs) = isHead ? (0, null) : await _stream(connection, head, body, started);
          _log(head, status: status, bytes: sent, firstByteMs: firstByteMs, started: started);
      }
    } finally {
      await connection.finish();
    }
  }

  /// Sends the body a chunk at a time, reading the next chunk only once the socket has taken the last one, so a
  /// fast engine never piles a file up in memory. Leaving early cancels the subscription, which cancels the
  /// engine's download.
  Future<(int, double?)> _stream(
    _Connection connection,
    HTTPRequestHead head,
    Stream<List<int>> body,
    Stopwatch started,
  ) {
    final done = Completer<(int, double?)>();
    var sent = 0;
    double? firstByteMs;
    void finish() {
      if (!done.isCompleted) done.complete((sent, firstByteMs));
    }

    late final StreamSubscription<List<int>> subscription;
    subscription = body.listen(
      (chunk) {
        firstByteMs ??= started.elapsedMicroseconds / 1000;
        subscription.pause();
        connection.send(chunk).then((delivered) {
          if (delivered) {
            sent += chunk.length;
            subscription.resume();
          } else {
            subscription.cancel().ignore();
            finish();
          }
        });
      },
      onError: (Object error) {
        Logger.shared.warn(LogCategory.server, 'body failed', {
          'file': _fileName(head),
          'error': '$error',
          'sent': sent,
        });
        finish();
      },
      onDone: finish,
      cancelOnError: true,
    );
    connection.body = subscription;
    connection.ended.then((_) => finish());
    return done.future;
  }

  void _log(
    HTTPRequestHead head, {
    required int status,
    required int bytes,
    double? firstByteMs,
    required Stopwatch started,
  }) {
    Logger.shared.info(LogCategory.server, head.method, {
      'file': _fileName(head),
      'range': head.headers['range'] ?? '',
      'status': status,
      'bytes': bytes,
      'ms': (started.elapsedMicroseconds / 1000).roundToDouble(),
      if (firstByteMs != null) 'firstByteMs': firstByteMs.roundToDouble(),
    });
  }

  /// The last path component only: the token stays out of the log.
  static String _fileName(HTTPRequestHead head) =>
      head.path.split('/').where((part) => part.isNotEmpty).lastOrNull ?? '';
}

final class _Connection {
  _Connection(this.socket, this._onEnd) {
    // Write errors after the client has gone also land here; unhandled, they would surface as uncaught errors.
    socket.done.ignore();
  }

  final Socket socket;
  final void Function(_Connection) _onEnd;
  StreamSubscription<Uint8List>? input;
  StreamSubscription<List<int>>? body;
  final _ended = Completer<void>();
  Completer<bool>? _waiting;

  Future<void> get ended => _ended.future;

  /// True once the socket has taken [bytes]; false, without waiting, once the connection has ended.
  Future<bool> send(List<int> bytes) => _guard(() {
    socket.add(bytes);
    return socket.flush();
  });

  /// Closes the write side once everything is sent, then the socket.
  Future<void> finish() async {
    await _guard(socket.close);
    end();
  }

  /// A socket that was destroyed under a pending flush may never complete it, so [end] settles the wait.
  Future<bool> _guard(Future<Object?> Function() action) {
    if (_ended.isCompleted) return Future.value(false);
    final waiting = _waiting = Completer<bool>();
    Future<Object?>.sync(action).then(
      (_) {
        if (!waiting.isCompleted) waiting.complete(true);
      },
      onError: (Object _) {
        if (!waiting.isCompleted) waiting.complete(false);
      },
    );
    return waiting.future;
  }

  void end() {
    if (_ended.isCompleted) return;
    _ended.complete();
    final waiting = _waiting;
    if (waiting != null && !waiting.isCompleted) waiting.complete(false);
    body?.cancel().ignore();
    input?.cancel().ignore();
    socket.destroy();
    _onEnd(this);
  }
}
