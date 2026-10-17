import 'dart:async';

import 'package:bili_core/api.dart' show BiliClient;
import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:cupertino_http/cupertino_http.dart';
// NSData's bytes are only reachable through objective_c's extension; it comes with cupertino_http.
// ignore: depend_on_referenced_packages
import 'package:objective_c/objective_c.dart' show NSDataExtensions;

/// The iOS transport: URLSession through cupertino_http (HTTP/2 to the mirrors, 8 per host for Akamai).
/// A top-level function, because it runs inside the engine isolate.
///
/// Whether cupertino_http works from a background isolate only shows on the phone (spec 4.3), so if
/// creating it, or its first requests, fail with anything but a network error, the engine carries on over
/// dart:io and the stats overlay says `dart:io (fallback)`.
RangeTransport createCupertinoTransport() {
  final headers = BiliClient.mediaHeaders;
  try {
    return _FallbackTransport(CupertinoRangeTransport(headers: headers), headers);
  } catch (error) {
    _logFallback(error);
    return _FallbackTransport(null, headers);
  }
}

void _logFallback(Object error) =>
    Logger.shared.warn(LogCategory.engine, 'URLSession unusable in the engine isolate, using dart:io', {'error': '$error'});

final class _FallbackTransport implements RangeTransport {
  _FallbackTransport(this._primary, this._headers);

  CupertinoRangeTransport? _primary;
  final Map<String, String> _headers;
  IoRangeTransport? _io;

  /// After one response URLSession is known to work here; later errors are the network's.
  bool _proven = false;

  IoRangeTransport get _fallback => _io ??= IoRangeTransport(headers: _headers);

  @override
  int? get connectionsPerHost => _primary?.connectionsPerHost ?? _fallback.connectionsPerHost;

  @override
  String get name => _primary == null ? 'dart:io (fallback)' : _primary!.name;

  @override
  Future<TransportResponse> fetch(Uri url, ByteRange range, {CancelToken? cancel}) async {
    final primary = _primary;
    if (primary != null) {
      try {
        final response = await primary.fetch(url, range, cancel: cancel);
        _proven = true;
        return response;
      } on CancelledException {
        rethrow;
      } on NSErrorClientException {
        rethrow;
      } catch (error) {
        if (_proven) rethrow;
        if (identical(_primary, primary)) {
          _primary = null;
          _logFallback(error);
          primary.close();
        }
      }
    }
    return _fallback.fetch(url, range, cancel: cancel);
  }

  @override
  void close() {
    _primary?.close();
    _io?.close();
  }
}

/// Port of URLSessionRangeTransport.swift: an ephemeral session, no cache, no cookies, the body streamed from
/// the task's delegate. Cancelling ends the call at once rather than when URLSession reports the cancellation,
/// so a cancelled hedge copy gives its connection permit back immediately.
final class CupertinoRangeTransport implements RangeTransport {
  CupertinoRangeTransport({this.headers = const {}, int maxConnectionsPerHost = 8})
      : connectionsPerHost = maxConnectionsPerHost {
    final configuration = URLSessionConfiguration.ephemeralSessionConfiguration()
      ..httpMaximumConnectionsPerHost = maxConnectionsPerHost
      ..requestCachePolicy = NSURLRequestCachePolicy.NSURLRequestReloadIgnoringLocalCacheData
      ..cache = null
      ..httpShouldSetCookies = false;
    _session = URLSession.sessionWithConfiguration(configuration);
  }

  final Map<String, String> headers;

  @override
  final int? connectionsPerHost;

  late final URLSession _session;
  final _running = <void Function()>{};

  @override
  String get name => 'URLSession';

  @override
  Future<TransportResponse> fetch(Uri url, ByteRange range, {CancelToken? cancel}) {
    if (cancel?.isCancelled ?? false) return Future.error(const CancelledException());
    final request = MutableURLRequest.fromUrl(url);
    // cupertino_http's parameter names are swapped: the header name goes first.
    headers.forEach(request.setValueForHttpHeaderField);
    request.setValueForHttpHeaderField('Range', range.headerValue);
    final task = _session.dataTaskWithRequest(request);
    final result = Completer<TransportResponse>();
    var abandoned = false;
    late final StreamController<List<int>> body;
    void Function()? unlink;

    void abandon() {
      if (abandoned) return;
      abandoned = true;
      _running.remove(abandon);
      unlink?.call();
      task.cancel();
    }

    body = StreamController<List<int>>(onCancel: abandon);
    _running.add(abandon);
    unlink = cancel?.onCancel(() {
      abandon();
      if (!result.isCompleted) {
        result.completeError(const CancelledException());
      } else if (!body.isClosed) {
        body
          ..addError(const CancelledException())
          ..close();
      }
    });

    task.taskDelegate = URLSessionTask.delegate(
      onResponse: (session, task, response) {
        if (abandoned || result.isCompleted) return NSURLSessionResponseDisposition.NSURLSessionResponseCancel;
        final http = response is HTTPURLResponse ? response : null;
        final lowercased = {
          for (final MapEntry(:key, :value) in (http?.allHeaderFields ?? const <String, String>{}).entries)
            key.toLowerCase(): value,
        };
        result.complete(TransportResponse(status: http?.statusCode ?? 0, headers: lowercased, body: body.stream));
        return NSURLSessionResponseDisposition.NSURLSessionResponseAllow;
      },
      onData: (session, task, data) {
        if (!abandoned && !body.isClosed) body.add(data.toList());
      },
      onComplete: (session, task, error) {
        _running.remove(abandon);
        unlink?.call();
        if (abandoned) {
          if (!body.isClosed) body.close();
          return;
        }
        if (error != null) {
          final failure = NSErrorClientException(error, url);
          if (!result.isCompleted) {
            result.completeError(failure);
          } else if (!body.isClosed) {
            body.addError(failure);
          }
        } else if (!result.isCompleted) {
          result.completeError(const RipperError.badResponse(0));
        }
        if (!body.isClosed) body.close();
      },
    );
    task.resume();
    return result.future;
  }

  @override
  void close() {
    for (final abandon in _running.toList()) {
      abandon();
    }
    _session.finishTasksAndInvalidate();
  }
}
