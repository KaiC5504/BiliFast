import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';

/// Answers from fixed routes; nothing ever reaches the network.
final class FakeHTTP implements HTTPTransport {
  /// Keyed by path, or by "POST /path" to answer one method only (the method-specific key wins).
  Map<String, (int, String)> routes = {};

  /// Byte-exact bodies (protobuf, which is not valid UTF-8); checked before `routes`.
  Map<String, (int, Uint8List)> dataRoutes = {};

  /// Keyed by host + path: answers 200 with this final URL, as a followed redirect would.
  Map<String, Uri> redirects = {};

  /// Response headers for a route, keyed by path (lowercased names, as the transport gives them).
  Map<String, Map<String, String>> routeHeaders = {};

  /// Checked before everything else; null passes the request on to the routes.
  (int, String)? Function(HTTPRequest request)? answer;

  final List<HTTPRequest> requests = [];

  @override
  Future<HTTPResponse> send(HTTPRequest request) async {
    requests.add(request);
    if (answer?.call(request) case (final int status, final String body)) {
      return HTTPResponse(status: status, headers: {}, body: utf8.encode(body), finalURL: request.url);
    }
    final key = request.url.host + request.url.path;
    final redirected = redirects[key];
    if (redirected != null) {
      return HTTPResponse(status: 200, headers: {}, body: Uint8List(0), finalURL: redirected);
    }
    final path = request.url.path;
    final methodKey = '${request.method} $path';
    final data = dataRoutes[methodKey] ?? dataRoutes[path];
    if (data != null) {
      return HTTPResponse(status: data.$1, headers: {}, body: data.$2, finalURL: request.url);
    }
    final route = routes[methodKey] ?? routes[path];
    if (route == null) return HTTPResponse(status: 404, headers: {}, body: Uint8List(0), finalURL: request.url);
    return HTTPResponse(
      status: route.$1,
      headers: routeHeaders[path] ?? {},
      body: utf8.encode(route.$2),
      finalURL: request.url,
    );
  }

  List<HTTPRequest> requestsTo(String path) => requests.where((request) => request.url.path == path).toList();

  /// Like URLComponents.queryItems: percent-decoded, the first of a repeated name wins, `+` stays a plus.
  Map<String, String> query(HTTPRequest request) {
    final result = <String, String>{};
    final query = request.url.query;
    if (query.isEmpty) return result;
    for (final pair in query.split('&')) {
      final equals = pair.indexOf('=');
      final name = Uri.decodeComponent(equals < 0 ? pair : pair.substring(0, equals));
      final value = equals < 0 ? '' : Uri.decodeComponent(pair.substring(equals + 1));
      result.putIfAbsent(name, () => value);
    }
    return result;
  }

  /// The request body as text, for asserting on form posts.
  String bodyText(HTTPRequest request) => utf8.decode(request.body ?? Uint8List(0), allowMalformed: true);
}

final testNow = DateTime.fromMillisecondsSinceEpoch(1702204169 * 1000, isUtc: true);

BiliClient makeTestClient(FakeHTTP http, {Map<String, String> cookies = const {}}) =>
    BiliClient(transport: http, cookies: CookieJar(cookies), now: () => testNow, logger: Logger(session: 'test'));

/// Decodes an envelope the way the client does, for model tests.
BiliEnvelope<T> decodeEnvelope<T>(String json, T Function(Object? json) decode) => BiliEnvelope.parse(json, decode);

/// A form body back into fields, percent-decoded.
Map<String, String> formFields(String body) {
  final fields = <String, String>{};
  for (final pair in body.split('&')) {
    if (pair.isEmpty) continue;
    final equals = pair.indexOf('=');
    final name = equals < 0 ? pair : pair.substring(0, equals);
    fields[name] = equals < 0 ? '' : Uri.decodeComponent(pair.substring(equals + 1));
  }
  return fields;
}
