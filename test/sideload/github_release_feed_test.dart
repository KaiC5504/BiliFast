import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/sideload/github_release_feed.dart';
import 'package:bilifast/sideload/sideload_links.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String answer({
  Object? tag = 'v1.3.0-8',
  Object? page = 'https://github.com/KaiC5504/BiliFast/releases/tag/v1.3.0-8',
}) => jsonEncode({'tag_name': tag, 'html_url': page, 'name': 'BiliFast 1.3.0 (8)', 'draft': false});

void main() {
  late MemorySink logs;
  late Logger logger;
  late List<http.Request> sent;

  setUp(() {
    logs = MemorySink();
    logger = Logger(session: 'test')..add(logs);
    sent = [];
  });

  GitHubReleaseFeed feed(Future<http.Response> Function(http.Request request) handler, {Duration? timeout}) =>
      GitHubReleaseFeed(
        MockClient((request) {
          sent.add(request);
          return handler(request);
        }),
        logger: logger,
        timeout: timeout ?? const Duration(seconds: 10),
      );

  List<String> reasons() => [for (final event in logs.events) '${event.f['reason']?.toJson()}'];

  test('one GET of the latest release, as GitHub asks for it, read into version, build and page', () async {
    final release = await feed((_) async => http.Response(answer(), 200)).latest();
    expect(release?.version, '1.3.0');
    expect(release?.build, 8);
    expect(release?.page, Uri.parse('https://github.com/KaiC5504/BiliFast/releases/tag/v1.3.0-8'));
    final request = sent.single;
    expect(request.method, 'GET');
    expect(request.url, Uri.parse(latestReleaseApi));
    expect(request.headers['Accept'], 'application/vnd.github+json');
    expect(request.headers['User-Agent'], 'BiliFast');
    expect(logs.events, isEmpty);
  });

  test('a status other than 200 is nothing, logged by its code', () async {
    expect(await feed((_) async => http.Response('{"message": "API rate limit exceeded"}', 403)).latest(), isNull);
    expect(reasons(), ['status 403']);
  });

  test('an answer that is not JSON, or not shaped as a release of ours, is nothing', () async {
    expect(await feed((_) async => http.Response('<html>', 200)).latest(), isNull);
    expect(await feed((_) async => http.Response('[]', 200)).latest(), isNull);
    expect(await feed((_) async => http.Response(answer(tag: 'nightly'), 200)).latest(), isNull);
    expect(await feed((_) async => http.Response(answer(tag: 'v1.3.0'), 200)).latest(), isNull);
    expect(await feed((_) async => http.Response(answer(tag: 8), 200)).latest(), isNull);
    expect(await feed((_) async => http.Response(answer(page: null), 200)).latest(), isNull);
    expect(await feed((_) async => http.Response(answer(page: 'https://example.com/v1.3.0-8'), 200)).latest(), isNull);
    expect(await feed((_) async => http.Response(answer(page: 'http://github.com/x'), 200)).latest(), isNull);
    expect(reasons(), ['not json', for (var i = 0; i < 7; i++) 'unexpected shape']);
  });

  test('no answer in time is nothing', () async {
    final never = Completer<http.Response>();
    final release = await feed((_) => never.future, timeout: const Duration(milliseconds: 10)).latest();
    expect(release, isNull);
    expect(reasons(), ['timeout']);
  });

  test("a failed connection is nothing, logged by its type and never its text, which carries the address", () async {
    final release = await feed((request) => throw SocketException('failed', osError: const OSError('refused')))
        .latest();
    expect(release, isNull);
    expect(reasons(), ['SocketException']);
    expect(logs.events.single.encode(), isNot(contains('refused')));
  });

  test('parseRelease takes a longer version and keeps it as written', () {
    final release = GitHubReleaseFeed.parseRelease({
      'tag_name': 'v1.10.0.2-12',
      'html_url': 'https://github.com/KaiC5504/BiliFast/releases/tag/v1.10.0.2-12',
    });
    expect((release?.version, release?.build), ('1.10.0.2', 12));
  });
}
