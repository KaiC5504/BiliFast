import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'bili_hosts.dart';

final class HTTPRequest {
  HTTPRequest({
    required this.url,
    Map<String, String>? headers,
    this.method = 'GET',
    this.body,
    this.timeout,
    this.abort,
  }) : headers = headers ?? {};

  final Uri url;
  final Map<String, String> headers;
  final String method;
  final Uint8List? body;

  /// Overrides the transport's timeout for this request only.
  final Duration? timeout;

  /// Completing it cancels the request at whatever hop it is on. The timeout bounds each wait, not the whole, so a
  /// caller with a deadline for the whole request cancels it with this.
  final Future<void>? abort;
}

final class HTTPResponse {
  HTTPResponse({required this.status, required this.headers, required this.body, required this.finalURL});

  final int status;

  /// Lowercased header names.
  final Map<String, String> headers;
  final Uint8List body;

  /// After redirects, which is how b23.tv short links are resolved.
  final Uri finalURL;
}

abstract interface class HTTPTransport {
  Future<HTTPResponse> send(HTTPRequest request);
}

/// The real transport over any `package:http` client, so `cupertino_http` or `cronet_http` can be plugged in.
/// No cookie store: cookies are managed by CookieJar. Redirects are followed here, not by the client, so the
/// Cookie header and the body never follow a redirect off Bilibili's hosts.
final class ClientHTTPTransport implements HTTPTransport {
  ClientHTTPTransport({http.Client? client, this.timeout = const Duration(seconds: 15), this.maxRedirects = 10})
    : _client = client ?? http.Client();

  final http.Client _client;

  /// Like URLSession's request timeout: the longest wait for the headers or between body chunks.
  final Duration timeout;
  final int maxRedirects;

  void close() => _client.close();

  /// The Cookie header is set by hand, so a redirect would otherwise carry it to whatever host it points at.
  /// A 307/308 also keeps the method and body, which can be a form carrying the csrf token.
  static HTTPRequest redirectedRequest(HTTPRequest request) {
    if (BiliHosts.isBilibili(request.url.host)) return request;
    final headers = Map.of(request.headers)..removeWhere((name, _) => name.toLowerCase() == 'cookie');
    return HTTPRequest(
      url: request.url,
      headers: headers,
      method: request.method,
      timeout: request.timeout,
      abort: request.abort,
    );
  }

  @override
  Future<HTTPResponse> send(HTTPRequest request) async {
    var current = request;
    for (var hop = 0; ; hop++) {
      // A timed-out request is aborted, not left running behind the TimeoutException.
      final abort = Completer<void>();
      final cancelled = current.abort;
      final trigger = cancelled == null ? abort.future : Future.any([abort.future, cancelled]);
      final outgoing = http.AbortableRequest(current.method, current.url, abortTrigger: trigger)
        ..followRedirects = false
        ..headers.addAll(current.headers);
      final body = current.body;
      if (body != null) outgoing.bodyBytes = body;
      final wait = current.timeout ?? timeout;
      final http.StreamedResponse streamed;
      final Uint8List bytes;
      try {
        streamed = await _client.send(outgoing).timeout(wait);
        bytes = await http.ByteStream(streamed.stream.timeout(wait)).toBytes();
      } on TimeoutException {
        if (!abort.isCompleted) abort.complete();
        rethrow;
      }
      final location = streamed.headers['location'];
      if (_isRedirect(streamed.statusCode) && location != null && hop < maxRedirects) {
        current = redirectedRequest(_follow(current, streamed.statusCode, current.url.resolve(location)));
        continue;
      }
      return HTTPResponse(
        status: streamed.statusCode,
        headers: {for (final entry in streamed.headers.entries) entry.key.toLowerCase(): entry.value},
        body: bytes,
        finalURL: current.url,
      );
    }
  }

  static bool _isRedirect(int status) => const {301, 302, 303, 307, 308}.contains(status);

  /// As browsers and URLSession do: 303, and 301/302 after a POST, continue as a bodiless GET.
  static HTTPRequest _follow(HTTPRequest request, int status, Uri next) {
    final keepsMethod = status == 307 || status == 308 || (request.method == 'GET' || request.method == 'HEAD');
    if (keepsMethod && status != 303) {
      return HTTPRequest(
        url: next,
        headers: request.headers,
        method: request.method,
        body: request.body,
        timeout: request.timeout,
        abort: request.abort,
      );
    }
    final headers = Map.of(request.headers)..removeWhere((name, _) => name.toLowerCase() == 'content-type');
    return HTTPRequest(url: next, headers: headers, timeout: request.timeout, abort: request.abort);
  }
}
