import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/home/feed_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';
import 'feed_fakes.dart';

void main() {
  late FeedHttp http;

  setUp(() => http = FeedHttp());

  FeedModel make() => FeedModel(
    client: BiliClient(
      transport: http,
      cookies: CookieJar(Canned.cookies),
      logger: Logger(session: 'test'),
    ),
    logger: Logger(session: 'test'),
  );

  List<String> bvids(FeedModel feed) => [for (final card in feed.cards) card.bvid];

  test('refresh asks for page 1, load more for the next, and a repeated video shows once', () async {
    http.pages[1] = [feedItem('BV1'), feedItem('BV2')];
    http.pages[2] = [
      feedItem('BV2'),
      feedItem('BV3'),
      {'goto': 'ad'},
    ];
    final feed = make();
    await feed.refresh();
    expect(bvids(feed), ['BV1', 'BV2']);
    await feed.loadMore();
    expect(bvids(feed), ['BV1', 'BV2', 'BV3']);
    expect(http.asked, [1, 2]);
  });

  test('a page that adds nothing is followed by up to two more', () async {
    http.pages[1] = [feedItem('BV1')];
    http.pages[2] = [feedItem('BV1')];
    http.pages[3] = [];
    http.pages[4] = [feedItem('BV4')];
    final feed = make();
    await feed.refresh();
    await feed.loadMore();
    expect(bvids(feed), ['BV1', 'BV4']);
    expect(http.asked, [1, 2, 3, 4]);

    http.asked.clear();
    await feed.loadMore();
    expect(http.asked, [5, 6, 7], reason: 'three empty pages, then it stops asking');
  });

  test('a failure says why and the next refresh starts over at page 1', () async {
    http.failing.add(1);
    final feed = make();
    await feed.refresh();
    expect(feed.error, '网络请求失败（HTTP 500）');
    expect(feed.cards, isEmpty);
    http.failing.clear();
    http.pages[1] = [feedItem('BV1')];
    await feed.refresh();
    expect(feed.error, isNull);
    expect(bvids(feed), ['BV1']);
  });

  test('a load more still running when a refresh lands does not add to the new list', () async {
    http.pages[1] = [feedItem('BV1')];
    final feed = make();
    await feed.refresh();
    http.pages[2] = [feedItem('BV2')];
    http.gates[2] = Completer<void>();
    final more = feed.loadMore();
    await pumpEventQueue();
    http.pages[1] = [feedItem('BV9')];
    await feed.refresh();
    http.gates[2]!.complete();
    await more;
    expect(bvids(feed), ['BV9']);
    expect(feed.loading, isFalse);
  });

  test('load more with nothing shown refreshes, and does not run twice at once', () async {
    http.pages[1] = [feedItem('BV1')];
    final feed = make();
    await feed.loadMore();
    expect(http.asked, [1]);
    http.gates[2] = Completer<void>();
    final first = feed.loadMore();
    final second = feed.loadMore();
    http.gates[2]!.complete();
    await Future.wait([first, second]);
    expect(http.asked.where((index) => index == 2), hasLength(1));
  });
}
