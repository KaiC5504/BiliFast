import 'dart:async';
import 'dart:io';

import '../shared/byte_range.dart';
import 'cancel.dart';
import 'transport.dart';

/// dart:io (HTTP/1.1): Windows, Android until cronet_http, and the tests.
final class IoRangeTransport implements RangeTransport {
  IoRangeTransport({this.headers = const {}, this.connectionsPerHost = 8})
      : _client = HttpClient()
          ..maxConnectionsPerHost = connectionsPerHost
          // Byte ranges must arrive as the bytes they name.
          ..autoUncompress = false;

  /// Sent with every request: the Safari User-Agent and Bilibili's Referer.
  final Map<String, String> headers;

  @override
  final int? connectionsPerHost;

  final HttpClient _client;

  /// Fresh connections tried after a lost one, before the error reaches the engine.
  static const lostConnectionRetries = 2;

  @override
  String get name => 'dart:io';

  /// Redirects are followed, with these headers and the Range kept, as URLSession does.
  @override
  Future<TransportResponse> fetch(Uri url, ByteRange range, {CancelToken? cancel}) async {
    for (var attempt = 0;; attempt++) {
      try {
        return await _fetchOnce(url, range, cancel);
      } on _ConnectFailed catch (failure) {
        // Refused, unreachable or not resolved: the node, not a lost connection. Windows takes about 2 s to report
        // each refused connect, so retrying those pushed the error past the engine's first-byte timeout.
        Error.throwWithStackTrace(failure.error, failure.stack);
      } on Object catch (error) {
        // Akamai closes idle keep-alive sockets, and dart:io reports a request sent on one as an HttpException
        // before any header: a lost connection, not a failing node (spec section 7). URLSession retries those
        // by itself.
        final lost = error is HttpException || error is SocketException;
        if (!lost || attempt >= lostConnectionRetries || (cancel?.isCancelled ?? false)) rethrow;
      }
    }
  }

  Future<TransportResponse> _fetchOnce(Uri url, ByteRange range, CancelToken? cancel) async {
    cancel?.throwIfCancelled();
    final result = Completer<TransportResponse>();
    HttpClientRequest? request;
    _Body? body;
    final unlink = cancel?.onCancel(() {
      request?.abort(const CancelledException());
      body?.cancelled();
      if (!result.isCompleted) result.completeError(const CancelledException());
    });

    Future<void> send() async {
      final HttpClientRequest opened;
      try {
        opened = await _client.getUrl(url);
      } on Object catch (error, stack) {
        throw _ConnectFailed(error, stack);
      }
      if (result.isCompleted) {
        opened.abort(const CancelledException());
        return;
      }
      request = opened;
      headers.forEach(opened.headers.set);
      opened.headers
        ..removeAll(HttpHeaders.acceptEncodingHeader)
        ..set(HttpHeaders.rangeHeader, range.headerValue);
      final response = await opened.close();
      if (result.isCompleted) {
        unawaited(response.listen(null).cancel());
        return;
      }
      final lowercased = <String, String>{};
      response.headers.forEach((name, values) => lowercased[name.toLowerCase()] = values.join(', '));
      final wrapped = body = _Body(response, onEnd: () => unlink?.call());
      result.complete(TransportResponse(status: response.statusCode, headers: lowercased, body: wrapped.stream));
    }

    send().catchError((Object error, StackTrace stack) {
      if (!result.isCompleted) result.completeError(error, stack);
      unlink?.call();
    });
    return result.future;
  }

  @override
  void close() => _client.close(force: true);
}

/// An error from opening the connection, before any request went out on it. A reused keep-alive socket opens at
/// once, so a stale one fails later, while the request waits for its headers.
final class _ConnectFailed {
  const _ConnectFailed(this.error, this.stack);

  final Object error;
  final StackTrace stack;
}

/// The response body. Cancelling it, or the request's CancelToken firing, cancels the response subscription,
/// which makes dart:io destroy the socket instead of draining it, so the connection is free at once.
final class _Body {
  _Body(this._response, {required this._onEnd}) {
    _controller = StreamController<List<int>>(
      onListen: _listen,
      onPause: () => _subscription?.pause(),
      onResume: () => _subscription?.resume(),
      onCancel: _drop,
    );
  }

  final HttpClientResponse _response;
  final void Function() _onEnd;
  late final StreamController<List<int>> _controller;
  StreamSubscription<List<int>>? _subscription;
  bool _ended = false;

  Stream<List<int>> get stream => _controller.stream;

  void _listen() {
    if (_ended) return;
    _subscription = _response.listen(
      _controller.add,
      onError: _controller.addError,
      onDone: () {
        _end();
        _controller.close();
      },
    );
  }

  Future<void> _drop() async {
    if (_ended) return;
    _end();
    final subscription = _subscription;
    if (subscription == null) {
      await _response.listen(null).cancel();
    } else {
      await subscription.cancel();
    }
  }

  void cancelled() {
    if (_ended) return;
    unawaited(_drop());
    _controller
      ..addError(const CancelledException())
      ..close();
  }

  void _end() {
    if (_ended) return;
    _ended = true;
    _onEnd();
  }
}
