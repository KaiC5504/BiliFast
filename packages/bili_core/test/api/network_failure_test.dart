import 'dart:async';
import 'dart:convert';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:test/test.dart';

import 'fake_http.dart';

final _token = AppToken(accessToken: 'SECRET', refreshToken: 'SECRET-REFRESH', mid: 7, expiresAt: DateTime.utc(2027));

/// Fails as cupertino_http does offline: the message ends with the request's URL, the official query's access_key
/// included.
final class _OfflineError implements Exception {
  _OfflineError(this.uri);

  final Uri uri;

  @override
  String toString() =>
      'NSErrorClientException: The Internet connection appears to be offline. '
      '[domain=NSURLErrorDomain, code=-1009], uri=$uri';
}

final class _Failing implements HTTPTransport {
  _Failing(this.error);

  final Object Function(Uri url) error;
  final List<HTTPRequest> requests = [];

  @override
  Future<HTTPResponse> send(HTTPRequest request) async {
    requests.add(request);
    throw error(request.url);
  }
}

/// Answers each request only when the test completes its gate.
final class _Gated implements HTTPTransport {
  final List<Completer<HTTPResponse>> pending = [];

  @override
  Future<HTTPResponse> send(HTTPRequest request) {
    final answer = Completer<HTTPResponse>();
    pending.add(answer);
    return answer.future;
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

  BiliClient client(HTTPTransport transport) =>
      BiliClient(transport: transport, cookies: CookieJar(), now: () => testNow, logger: logger)..appToken = _token;

  test("an official call that fails offline throws the network error, and the token is in no log or error", () async {
    final transport = _Failing(_OfflineError.new);
    final official = client(transport);
    final failures = <Object>[];
    for (final call in <Future<void> Function()>[
      () => official.officialFeed(index: 0),
      () => official.feedDislike(goto: 'av', id: 1, reasonId: 1),
      () => official.feedDislikeCancel(goto: 'av', id: 1, reasonId: 1),
    ]) {
      await call().then<void>((_) => fail('should have failed'), onError: failures.add);
    }
    expect(transport.requests, hasLength(3));
    expect('${transport.requests.first.url}', contains('access_key=SECRET'), reason: 'the leak the error carried');
    for (final error in failures) {
      expect(error, const BiliError.network('_OfflineError', domain: 'NSURLErrorDomain', code: -1009));
      expect('$error', isNot(contains('SECRET')));
      expect((error as BiliError).userMessage, '网络连接失败，请检查网络后重试');
    }
    final logged = log.events.where((event) => event.level == LogLevel.error).toList();
    expect(logged.map((event) => event.msg), ['/x/v2/feed/index', '/x/feed/dislike', '/x/feed/dislike/cancel']);
    expect(logged.first.f, {
      'error': const LogString('_OfflineError'),
      'domain': const LogString('NSURLErrorDomain'),
      'code': const LogInt(-1009),
    });
    for (final leak in ['SECRET', 'access_key', 'uri=', '?']) {
      expect(log.text, isNot(contains(leak)));
    }
  });

  test('a timeout is a network error named by its type', () async {
    final official = client(_Failing((url) => TimeoutException('no answer from $url')));
    await expectLater(official.officialFeed(index: 0), throwsA(const BiliError.network('TimeoutException')));
    expect(log.text, isNot(contains('SECRET')));
  });

  test("a short link that can't be reached throws the network error without the link", () async {
    final web = client(_Failing(_OfflineError.new));
    final link = LinkParser.parse('https://b23.tv/AbCdEf1')!;
    await expectLater(
      web.resolve(link),
      throwsA(isA<BiliNetworkError>().having((error) => '$error', 'text', isNot(contains('AbCdEf1')))),
    );
    expect(log.text, isNot(contains('AbCdEf1')));
  });

  test('a rejection names the token the call was signed with, even after the client took another', () async {
    final transport = _Gated();
    final official = client(transport);
    final rejected = <String>[];
    official.onAppTokenRejected = rejected.add;
    final call = official.officialFeed(index: 0);
    await Future<void>.delayed(Duration.zero);
    official.appToken = AppToken(accessToken: 'RENEWED', refreshToken: 'R2', mid: 7, expiresAt: DateTime.utc(2028));
    transport.pending.single.complete(
      HTTPResponse(
        status: 200,
        headers: {},
        body: utf8.encode('{"code":-101,"message":"账号未登录","ttl":1}'),
        finalURL: Uri.parse('https://app.bilibili.com/x/v2/feed/index'),
      ),
    );
    await expectLater(call, throwsA(isA<BiliAPIError>()));
    expect(rejected, ['SECRET']);
  });
}
