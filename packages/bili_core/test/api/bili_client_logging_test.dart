import 'dart:convert';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:test/test.dart';

import 'fake_http.dart';
import 'fixtures.dart';

const _typed = "it's a secret";

/// Fails as cupertino_http does offline: the message ends with the request's URL, query and all.
final class _OfflineError implements Exception {
  _OfflineError(this.uri);

  final Uri uri;

  @override
  String toString() =>
      'NSErrorClientException: The Internet connection appears to be offline. '
      '[domain=NSURLErrorDomain, code=-1009], uri=$uri';
}

final class _Offline implements HTTPTransport {
  @override
  Future<HTTPResponse> send(HTTPRequest request) async {
    if (request.url.path == '/x/web-interface/nav') {
      return HTTPResponse(status: 200, headers: {}, body: utf8.encode(Fixtures.navLoggedOut), finalURL: request.url);
    }
    throw _OfflineError(request.url);
  }
}

final class _Events implements LogSink {
  final List<LogEvent> events = [];

  @override
  void receive(LogEvent event) => events.add(event);

  String get text => events.map((event) => event.encode()).join('\n');
}

void main() {
  late _Events log;
  late Logger logger;

  setUp(() {
    log = _Events();
    logger = Logger(session: 'test')..add(log);
  });

  test('a failed request logs the error type and the NSError code, never the URL or its query', () async {
    final client = BiliClient(
      transport: _Offline(),
      cookies: CookieJar({'buvid3': 'b3', 'buvid4': 'b4'}),
      now: () => testNow,
      logger: logger,
    );
    const offline = BiliError.network('_OfflineError', domain: 'NSURLErrorDomain', code: -1009);
    await expectLater(client.searchSuggestions(_typed), throwsA(offline));
    await expectLater(client.searchVideos(keyword: _typed), throwsA(offline));
    final failures = log.events.where((event) => event.level == LogLevel.error).toList();
    expect(failures, hasLength(2));
    expect(failures.first.msg, '/x/web-interface/suggest');
    expect(failures.first.f, {
      'error': const LogString('_OfflineError'),
      'domain': const LogString('NSURLErrorDomain'),
      'code': const LogInt(-1009),
    });
    for (final leak in ['secret', 'term', 'keyword', 'uri=', '?']) {
      expect(log.text, isNot(contains(leak)));
    }
  });

  test("an answer that isn't JSON logs the parser's complaint without quoting the answer", () async {
    final http = FakeHTTP()..routes = {'/x/web-interface/suggest': (200, '<html>$_typed</html>')};
    final client = BiliClient(
      transport: http,
      cookies: CookieJar({'buvid3': 'b3', 'buvid4': 'b4'}),
      now: () => testNow,
      logger: logger,
    );
    http.routes['/x/web-interface/nav'] = (200, Fixtures.navLoggedOut);
    http.routes['/x/web-interface/wbi/search/type'] = (200, '{"code":0,"data":{"result":"$_typed');
    await expectLater(client.searchSuggestions('typed'), throwsA(isA<BiliDecodingError>()));
    await expectLater(
      client.searchVideos(keyword: 'typed'),
      throwsA(isA<BiliDecodingError>().having((error) => '$error', 'message', isNot(contains('secret')))),
    );
    expect(log.events.where((event) => event.msg.endsWith('decode failed')), hasLength(2));
    expect(log.text, isNot(contains('secret')));
  });
}
