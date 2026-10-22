import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/home/feed_model.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';
import 'feed_fakes.dart';

void main() {
  late FeedHttp http;
  late MemorySink logs;

  setUp(() {
    http = FeedHttp();
    logs = MemorySink();
  });

  FeedModel make() => FeedModel(
    client: BiliClient(
      transport: http,
      cookies: CookieJar(Canned.cookies),
      logger: Logger(session: 'test'),
    ),
    logger: Logger(session: 'test')..add(logs),
  );

  List<String> bvids(FeedModel feed) => [for (final card in feed.cards) card.bvid];

  Matcher failedWith(String message) => isA<DislikeError>().having((error) => error.message, 'message', message);

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

  test('three pages that add nothing end the feed until 重试, which asks again', () async {
    http.pages[1] = [feedItem('BV1')];
    final feed = make();
    await feed.refresh();
    expect(feed.canLoadMore, isTrue);
    await feed.loadMore();
    expect(http.asked, [1, 2, 3, 4]);
    expect(feed.exhausted, isTrue);
    expect(feed.error, isNull);
    expect(feed.canLoadMore, isFalse, reason: 'endless scroll stops asking');

    http.pages[5] = [feedItem('BV5')];
    await feed.retry();
    expect(http.asked, [1, 2, 3, 4, 5]);
    expect(feed.exhausted, isFalse);
    expect(bvids(feed), ['BV1', 'BV5']);
    expect(feed.canLoadMore, isTrue);
  });

  test('a first page with no cards says so instead of loading forever', () async {
    final feed = make();
    expect(await feed.refresh(), isNull);
    expect(feed.loading, isFalse);
    expect(feed.cards, isEmpty);
    expect(feed.error, FeedModel.emptyMessage);
    expect(feed.canLoadMore, isFalse);

    http.pages[1] = [feedItem('BV1')];
    await feed.retry();
    expect(bvids(feed), ['BV1']);
    expect(feed.error, isNull);
    expect(http.asked, [1, 1], reason: 'with nothing shown, 重试 is page 1 again');
  });

  test('a refresh that fails with cards on screen keeps them and hands back why', () async {
    http.pages[1] = [feedItem('BV1')];
    final feed = make();
    await feed.refresh();
    http.failing.add(1);
    expect(await feed.refresh(), '网络请求失败（HTTP 500）');
    expect(bvids(feed), ['BV1']);
    expect(feed.error, isNull, reason: 'the footer has nothing to retry');
    expect(feed.canLoadMore, isTrue);

    http.failing.clear();
    http.pages[1] = [];
    expect(await feed.refresh(), FeedModel.emptyMessage);
    expect(bvids(feed), ['BV1']);
  });

  test('重试 after a failed load more asks for the same page again, not page 1', () async {
    http.pages[1] = [feedItem('BV1')];
    http.failing.add(2);
    final feed = make();
    await feed.refresh();
    await feed.loadMore();
    expect(feed.error, '网络请求失败（HTTP 500）');
    expect(feed.canLoadMore, isFalse);
    http.failing.clear();
    http.pages[2] = [feedItem('BV2')];
    await feed.retry();
    expect(http.asked, [1, 2, 2]);
    expect(bvids(feed), ['BV1', 'BV2']);
    expect(feed.error, isNull);
  });

  test('every page is logged with its index, how many came and how many were new', () async {
    http.pages[1] = [feedItem('BV1'), feedItem('BV2')];
    http.pages[2] = [
      feedItem('BV2'),
      feedItem('BV3'),
      {'goto': 'ad'},
    ];
    final feed = make();
    await feed.refresh();
    await feed.loadMore();
    final pages = [
      for (final event in logs.events.where((event) => event.msg == 'feed page'))
        (event.f['index'], event.f['got'], event.f['new']),
    ];
    expect(pages, [
      (const LogInt(1), const LogInt(2), const LogInt(2)),
      (const LogInt(2), const LogInt(2), const LogInt(1)),
    ]);
  });

  test('a timeout reads as a network failure', () {
    expect(requestFailureMessage(TimeoutException('slow')), '网络连接失败，请检查网络后重试');
    expect(requestFailureMessage(StateError('?')), '加载失败，请稍后重试');
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

  group("a refresh's covers", () {
    List<LogEvent> coverLines() => [for (final event in logs.events) if (event.msg == 'feed covers') event];

    test('its cards show only once beforeShow\'s covers have finished, the old ones still there meanwhile; the log '
        'counts the failed apart from the ready', () async {
      http.pages[1] = [feedItem('BV1')];
      final feed = make();
      await feed.refresh();
      http.pages[1] = [feedItem('BV2'), feedItem('BV3'), feedItem('BV4')];
      final cover = Completer<bool>();
      List<String>? asked;
      List<String>? shownThen;
      feed.beforeShow = (fresh) {
        asked = [for (final card in fresh) card.bvid];
        shownThen = bvids(feed);
        return CoverWait([cover.future, Future.value(false), Future.error(StateError('decode'))]);
      };
      var done = false;
      final refresh = feed.refresh().then((_) => done = true);
      await pumpEventQueue();
      expect(asked, ['BV2', 'BV3', 'BV4']);
      expect(shownThen, ['BV1'], reason: 'called before the cards are replaced');
      expect(bvids(feed), ['BV1']);
      expect(feed.loading, isTrue);
      expect(done, isFalse, reason: 'the refresh, and with it the loading TV, waits');

      cover.complete(true);
      await refresh;
      expect(bvids(feed), ['BV2', 'BV3', 'BV4']);
      expect(feed.loading, isFalse);
      final line = coverLines().last;
      expect(line.f['ready']?.toJson(), 1);
      expect(line.f['failed']?.toJson(), 2);
      expect(line.f['of']?.toJson(), 3);
      expect(line.f['timedOut']?.toJson(), false);
      expect(line.f.keys, unorderedEquals(['ready', 'failed', 'of', 'waitedMs', 'timedOut']), reason: 'no address');
    });

    test('they are waited on for at most 300 ms after the answer; the slow ones are neither ready nor failed', () {
      expect(FeedModel.coverWait, const Duration(milliseconds: 300));
      fakeAsync((async) {
        http.pages[1] = [feedItem('BV1')];
        final feed = make()
          ..beforeShow = (_) => CoverWait([Completer<bool>().future, Future.value(true), Future.value(false)]);
        var done = false;
        unawaited(feed.refresh().then((_) => done = true));
        async.elapse(FeedModel.coverWait - const Duration(milliseconds: 1));
        expect(done, isFalse);
        expect(feed.cards, isEmpty);
        async.elapse(const Duration(milliseconds: 2));
        expect(done, isTrue);
        expect(bvids(feed), ['BV1']);
        final line = coverLines().single;
        expect(line.f['ready']?.toJson(), 1);
        expect(line.f['failed']?.toJson(), 1);
        expect(line.f['of']?.toJson(), 3);
        expect(line.f['timedOut']?.toJson(), true);
      });
    });

    test('a refresh restarted while they load drops the first answer', () async {
      http.pages[1] = [feedItem('BV1')];
      final feed = make();
      final first = Completer<bool>();
      var calls = 0;
      feed.beforeShow = (_) => CoverWait([if (calls++ == 0) first.future else Future.value(true)]);
      final stale = feed.refresh();
      await pumpEventQueue();
      expect(calls, 1);
      http.pages[1] = [feedItem('BV2')];
      await feed.refresh();
      expect(bvids(feed), ['BV2']);
      first.complete(true);
      expect(await stale, isNull);
      expect(bvids(feed), ['BV2']);
      expect(feed.loading, isFalse);
    });

    test('a hook that throws holds nothing up and goes to the crash log', () async {
      http.pages[1] = [feedItem('BV1')];
      final feed = make()..beforeShow = (_) => throw StateError('no layout');
      await feed.refresh();
      expect(bvids(feed), ['BV1']);
      final crash = logs.events.singleWhere((event) => event.msg == 'crash');
      expect(crash.cat, LogCategory.app);
      expect(crash.f['source']?.toJson(), 'feed covers');
      expect(crash.f['error']?.toJson(), contains('no layout'));
      expect(coverLines(), isEmpty);
    });

    test('with none asked for, the log still says so, and why', () async {
      http.pages[1] = [feedItem('BV1')];
      final feed = make();
      await feed.refresh();
      feed.beforeShow = (_) => const CoverWait.skipped(CoverSkip.noLayout);
      http.pages[1] = [feedItem('BV2')];
      await feed.refresh();
      expect(bvids(feed), ['BV2']);
      expect([for (final line in coverLines()) line.f.map((key, value) => MapEntry(key, value.toJson()))], [
        {'of': 0, 'why': 'noGrid'},
        {'of': 0, 'why': 'noLayout'},
      ]);
    });

    test('an empty answer asks for no covers', () async {
      var asked = false;
      final feed = make()
        ..beforeShow = (_) {
          asked = true;
          return const CoverWait([]);
        };
      await feed.refresh();
      expect(feed.error, FeedModel.emptyMessage);
      expect(asked, isFalse);
      expect(coverLines(), isEmpty);
    });
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

  group('the official feed', () {
    late BiliClient client;
    var wanted = true;

    FeedModel official() {
      wanted = true;
      client = BiliClient(transport: http, cookies: CookieJar(Canned.cookies), logger: Logger(session: 'test'))
        ..appToken = fakeAppToken;
      return FeedModel(client: client, logger: Logger(session: 'test')..add(logs), officialWanted: () => wanted);
    }

    test('without the app token it is never asked, whatever 开发者 says', () async {
      http.officialPages[0] = [officialItem('BV1')];
      http.pages[1] = [feedItem('BVweb')];
      http.pages[2] = [feedItem('BVweb2')];
      final feed = official();
      client.appToken = null;
      await feed.refresh();
      await feed.loadMore();
      expect(http.officialAsked, isEmpty);
      expect(http.asked, [1, 2]);
      expect(feed.source, FeedSource.web);
      expect(bvids(feed), ['BVweb', 'BVweb2']);
    });

    test('with the token it pages from 0, and 开发者 → 网页 goes back to the website', () async {
      http.officialPages[0] = [officialItem('BV1'), officialItem('BV2')];
      http.officialPages[1] = [officialItem('BV3')];
      final feed = official();
      await feed.refresh();
      expect(feed.source, FeedSource.official);
      expect(bvids(feed), ['BV1', 'BV2']);
      expect(feed.cards.first.viewsText, '10.4万');
      await feed.loadMore();
      expect(http.officialAsked, [0, 1]);
      expect(bvids(feed), ['BV1', 'BV2', 'BV3']);
      expect(http.asked, isEmpty, reason: 'the website is not asked as well');

      wanted = false;
      http.pages[1] = [feedItem('BVweb')];
      await feed.refresh();
      expect(feed.source, FeedSource.web);
      expect(http.asked, [1]);
      expect(http.officialAsked, [0, 1]);
    });

    test('only video cards are kept: ads and live rooms are dropped', () async {
      http.officialPages[0] = [
        officialItem('BV1'),
        officialItem('BVad', goto: 'ad_av'),
        officialItem('BVlive', goto: 'live'),
        {...officialItem('BVadinfo'), 'ad_info': <String, Object?>{}},
        officialItem('BV2'),
      ];
      final feed = official();
      await feed.refresh();
      expect(bvids(feed), ['BV1', 'BV2']);
    });

    test('a refused token brings the same load from the website, so 推荐 never goes blank', () async {
      http.officialCode = -101;
      http.pages[1] = [feedItem('BVweb1')];
      http.pages[2] = [feedItem('BVweb2')];
      final feed = official();
      expect(await feed.refresh(), isNull);
      expect(http.officialAsked, [0]);
      expect(http.asked, [1]);
      expect(feed.source, FeedSource.web);
      expect(bvids(feed), ['BVweb1']);
      await feed.loadMore();
      expect(http.officialAsked, [0], reason: 'the rest of the scroll stays on the website');
      expect(http.asked, [1, 2]);
    });

    test('a token refused mid-scroll (-2) loads that page from the website', () async {
      http.officialPages[0] = [officialItem('BV1')];
      final feed = official();
      await feed.refresh();
      http.officialCode = -2;
      http.pages[2] = [feedItem('BVweb2')];
      await feed.loadMore();
      expect(http.officialAsked, [0, 1]);
      expect(http.asked, [2], reason: "the website's own count, as if it had been read all along");
      expect(bvids(feed), ['BV1', 'BVweb2']);
      expect(feed.error, isNull);
    });

    test('any other official failure is a failure, not a switch', () async {
      http.officialCode = -352;
      final feed = official();
      await feed.refresh();
      expect(http.asked, isEmpty);
      expect(feed.error, '请求过于频繁，请稍后再试');
    });

    test("failures log the error's type and Bilibili's code or the HTTP status, never its words", () async {
      http.officialCode = -352;
      final feed = official();
      await feed.refresh();
      wanted = false;
      http.failing.add(1);
      await feed.refresh();
      http.failing.clear();
      http.pages[1] = [feedItem('BV1')];
      await feed.refresh();
      http.dislikeCode = -400;
      http.officialCode = 0;
      http.officialPages[0] = [officialItem('BV2')];
      wanted = true;
      await feed.refresh();
      await feed.dislike(feed.cards.first, feed.cards.first.dislike!.video!);
      Iterable<Map<String, LogValue>> fields(String message) =>
          logs.events.where((event) => event.msg == message).map((event) => event.f);
      expect(fields('feed refresh failed'), [
        {'error': const LogString('BiliAPIError'), 'code': const LogInt(-352)},
        {'error': const LogString('BiliHTTPError'), 'status': const LogInt(500)},
      ]);
      expect(fields('feed dislike failed'), [
        {'error': const LogString('BiliAPIError'), 'code': const LogInt(-400)},
      ]);
    });

    group('不感兴趣', () {
      Future<(FeedModel, FeedCard)> shown() async {
        http.officialPages[0] = [officialItem('BV1'), officialItem('BV2')];
        final feed = official();
        await feed.refresh();
        return (feed, feed.cards.first);
      }

      test('turns the card over at once and sends its reason; 撤销 takes it back', () async {
        final (feed, card) = await shown();
        final gate = http.dislikeGate = Completer<void>();
        final sent = feed.dislike(card, card.dislike!.video!);
        expect(feed.dislikeOf(card)?.reason.id, 1, reason: 'optimistic');
        expect(await feed.dislike(card, card.dislike!.uploader!), isNull, reason: 'a second tap is dropped');
        gate.complete();
        http.dislikeGate = null;
        expect(await sent, isNull);
        expect(http.dislikes, hasLength(1));
        expect(http.dislikes.single['reason_id'], '1');
        expect(http.dislikes.single['goto'], 'av');
        expect(http.dislikes.single['id'], '${'BV1'.hashCode.abs()}');
        expect(feed.dislikeOf(feed.cards[1]), isNull);

        expect(await feed.undo(card), isNull);
        expect(feed.dislikeOf(card), isNull);
        expect(http.cancels.single['reason_id'], '1');
      });

      test("the uploader's reason, then a 反馈 picked from the sheet with its feedback id", () async {
        final (feed, card) = await shown();
        await feed.dislike(card, card.dislike!.uploader!);
        expect(http.dislikes.single['reason_id'], '4');
        final repeated = card.dislike!.repeated!;
        expect(await feed.sendReason(card, repeated), isNull);
        expect(http.dislikes.last['feedback_id'], '19');
        expect(http.dislikes.last.containsKey('reason_id'), isFalse);
        expect(feed.dislikeOf(card)?.feedback, repeated);
        expect(feed.dislikeOf(card)?.reason.id, 4, reason: 'the card stays turned over');
      });

      test('a failure turns the card back and hands back why', () async {
        final (feed, card) = await shown();
        http.dislikeCode = -400;
        expect(await feed.dislike(card, card.dislike!.video!), failedWith('B 站返回错误 -400：请求错误'));
        expect(feed.dislikeOf(card), isNull);

        http.dislikeCode = 0;
        await feed.dislike(card, card.dislike!.video!);
        http.dislikeCode = -400;
        expect(await feed.undo(card), isA<DislikeError>());
        expect(feed.dislikeOf(card)?.reason.id, 1, reason: 'still turned over: the server kept it');
        expect(await feed.sendReason(card, card.dislike!.tiles.first), isA<DislikeError>());
        expect(feed.dislikeOf(card)?.feedback, isNull);
      });

      for (final code in [-101, -2]) {
        test('a token turned down ($code) is no 需要登录: each call rolls back and says the token was refused', () async {
          final (feed, card) = await shown();
          http.dislikeCode = code;
          expect(await feed.dislike(card, card.dislike!.video!), isA<DislikeTokenRefused>());
          expect(feed.dislikeOf(card), isNull);

          http.dislikeCode = 0;
          await feed.dislike(card, card.dislike!.video!);
          http.dislikeCode = code;
          expect(await feed.undo(card), isA<DislikeTokenRefused>());
          expect(feed.dislikeOf(card)?.reason.id, 1);
          expect(await feed.sendReason(card, card.dislike!.tiles.first), isA<DislikeTokenRefused>());
          expect(feed.dislikeOf(card)?.feedback, isNull);
        });
      }

      test('with no token held the call is refused for the token, and nothing is sent', () async {
        final (feed, card) = await shown();
        client.appToken = null;
        expect(await feed.dislike(card, card.dislike!.video!), isA<DislikeTokenRefused>());
        expect(feed.dislikeOf(card), isNull);
        expect(http.dislikes, isEmpty);
      });

      test('a web card has nothing to send', () async {
        http.pages[1] = [feedItem('BVweb')];
        final feed = make();
        await feed.refresh();
        final card = feed.cards.single;
        expect(card.dislike, isNull);
        expect(await feed.dislike(card, const FeedReason(id: 1, name: '不感兴趣', kind: FeedReasonKind.dislike)), isNull);
        expect(feed.dislikeOf(card), isNull);
        expect(http.dislikes, isEmpty);
      });

      test('a refresh forgets the cards it replaced', () async {
        final (feed, card) = await shown();
        await feed.dislike(card, card.dislike!.video!);
        await feed.refresh();
        expect(feed.dislikeOf(feed.cards.first), isNull);
      });
    });
  });
}
