import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/home/feed_model.dart';
import 'package:flutter_test/flutter_test.dart';

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

final class _Offline implements HTTPTransport {
  final urls = <Uri>[];

  @override
  Future<HTTPResponse> send(HTTPRequest request) async {
    urls.add(request.url);
    throw _OfflineError(request.url);
  }
}

class _Events implements LogSink {
  final lines = <String>[];

  @override
  void receive(LogEvent event) => lines.add(event.encode());
}

void main() {
  test("推荐's official feed lost offline says so, and the token reaches no log line", () async {
    final events = _Events();
    final logger = Logger(session: 'test')..add(events);
    final transport = _Offline();
    final token = AppToken(accessToken: 'SECRET', refreshToken: 'SECRET-REFRESH', mid: 7, expiresAt: DateTime.utc(2099));
    final client = BiliClient(transport: transport, cookies: CookieJar(), logger: logger)..appToken = token;
    final feed = FeedModel(client: client, logger: logger, officialWanted: () => true);
    addTearDown(feed.dispose);

    expect(await feed.refresh(), isNull);
    expect('${transport.urls.first}', contains('access_key=SECRET'));
    expect(feed.error, '网络连接失败，请检查网络后重试');
    expect(events.lines.where((line) => line.contains('feed refresh failed')), hasLength(1));
    for (final line in events.lines) {
      expect(line, isNot(contains('SECRET')));
      expect(line, isNot(contains('access_key')));
    }
  });

  test('a network error reads as the network wording wherever a failure is worded', () {
    for (final error in const [
      BiliError.network('TimeoutException'),
      BiliError.network('NSErrorClientException', domain: 'NSURLErrorDomain', code: -1009),
    ]) {
      expect(requestFailureMessage(error), '网络连接失败，请检查网络后重试');
      expect(requestFailureMessage(error, fallback: '操作失败'), '网络连接失败，请检查网络后重试');
    }
    expect(requestFailureMessage(TimeoutException('slow')), '网络连接失败，请检查网络后重试');
  });
}
