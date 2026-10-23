import 'dart:async';
import 'dart:typed_data';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/home/feed_model.dart';
import 'package:bilifast/shared/image_disk_cache.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';
import 'feed_fakes.dart';

/// Stands in for the iPhone's picture connection: records each request and answers it at once, or once [hold] does;
/// [error] is thrown in place of an answer.
final class _PictureHttp implements HTTPTransport {
  final sent = <HTTPRequest>[];
  Future<void>? hold;
  Object? error;

  @override
  Future<HTTPResponse> send(HTTPRequest request) async {
    sent.add(request);
    await hold;
    final failure = error;
    if (failure != null) throw failure;
    return HTTPResponse(status: 200, headers: const {}, body: Uint8List(0), finalURL: request.url);
  }
}

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

    test("its cards show the moment the answer is in, beforeShow called just before with the old ones still there; "
        "the log counts the covers ready by then, the failed apart", () async {
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
        return CoverPrefetch([cover.future, Future.value(false), Future.error(StateError('decode'))]);
      };
      await feed.refresh();
      expect(asked, ['BV2', 'BV3', 'BV4']);
      expect(shownThen, ['BV1'], reason: 'called before the cards are replaced');
      expect(bvids(feed), ['BV2', 'BV3', 'BV4'], reason: 'no cover is waited on');
      expect(feed.loading, isFalse);
      expect(cover.isCompleted, isFalse);
      final line = coverLines().last;
      expect(line.f['ready']?.toJson(), 0);
      expect(line.f['failed']?.toJson(), 0, reason: 'none had finished as the cards showed');
      expect(line.f['of']?.toJson(), 3);
      expect(line.f['early']?.toJson(), false);
      expect(line.f.keys, unorderedEquals(['ready', 'failed', 'of', 'early']), reason: 'no address');
    });

    test('a refresh restarted while the first is out drops the first answer', () async {
      http.pages[1] = [feedItem('BV1')];
      final feed = make();
      http.gates[1] = Completer<void>();
      final stale = feed.refresh();
      await pumpEventQueue();
      http.pages[1] = [feedItem('BV2')];
      final gate = http.gates.remove(1)!;
      await feed.refresh();
      expect(bvids(feed), ['BV2']);
      http.pages[1] = [feedItem('BV1')];
      gate.complete();
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
      feed.beforeShow = (_) => const CoverPrefetch.skipped(CoverSkip.noLayout);
      http.pages[1] = [feedItem('BV2')];
      await feed.refresh();
      expect(bvids(feed), ['BV2']);
      expect([for (final line in coverLines()) line.f.map((key, value) => MapEntry(key, value.toJson()))], [
        {'ready': 0, 'failed': 0, 'of': 0, 'why': 'noGrid', 'early': false},
        {'ready': 0, 'failed': 0, 'of': 0, 'why': 'noLayout', 'early': false},
      ]);
    });

    test('an empty answer asks for no covers', () async {
      var asked = false;
      final feed = make()
        ..beforeShow = (_) {
          asked = true;
          return const CoverPrefetch([]);
        };
      await feed.refresh();
      expect(feed.error, FeedModel.emptyMessage);
      expect(asked, isFalse);
      expect(coverLines(), isEmpty);
    });
  });

  group("a held pull's early page", () {
    late DateTime now;
    late List<String> asked;
    late BiliClient client;

    FeedModel held() {
      now = DateTime(2026, 10, 23, 12);
      asked = [];
      client = BiliClient(transport: http, cookies: CookieJar(Canned.cookies), logger: Logger(session: 'test'));
      return FeedModel(
        client: client,
        officialWanted: () => true,
        logger: Logger(session: 'test')..add(logs),
        now: () => now,
      )..beforeShow = (fresh) {
        asked.addAll([for (final card in fresh) card.bvid]);
        return CoverPrefetch([for (final _ in fresh) Future.value(true)]);
      };
    }

    List<LogEvent> lines(String msg) => [for (final event in logs.events) if (event.msg == msg) event];

    test('armed, page 1 is asked for at once and its covers once it is in, but nothing shows until the release',
        () async {
      http.pages[1] = [feedItem('BV1')];
      final feed = held();
      await feed.refresh();
      asked.clear();
      http.pages[1] = [feedItem('BV2'), feedItem('BV3')];
      var notified = 0;
      feed.addListener(() => notified++);
      feed.pullArmed();
      await pumpEventQueue();
      expect(http.asked, [1, 1]);
      expect(asked, ['BV2', 'BV3'], reason: 'covers on their way');
      expect(bvids(feed), ['BV1']);
      expect(feed.loading, isFalse);
      expect(notified, 0, reason: 'nothing on screen changed');
      expect(lines('feed page'), hasLength(1), reason: 'the first load only');

      now = now.add(const Duration(milliseconds: 1500));
      await feed.refresh(pulled: true);
      expect(http.asked, [1, 1], reason: 'the release joined the early page');
      expect(bvids(feed), ['BV2', 'BV3']);
      final line = lines('feed covers').last;
      expect(line.f['early']?.toJson(), true);
      expect(line.f['heldMs']?.toJson(), 1500);
      expect(line.f['ready']?.toJson(), 2, reason: 'asked for while held, ready by the release');
      expect(line.f['of']?.toJson(), 2);
    });

    test('released before the answer, it shows when the answer comes', () async {
      http.pages[1] = [feedItem('BV1')];
      final feed = held();
      await feed.refresh();
      http.pages[1] = [feedItem('BV2')];
      http.gates[1] = Completer<void>();
      feed.pullArmed();
      await pumpEventQueue();
      final refresh = feed.refresh(pulled: true);
      await pumpEventQueue();
      expect(bvids(feed), ['BV1']);
      http.gates[1]!.complete();
      await refresh;
      expect(http.asked, [1, 1]);
      expect(bvids(feed), ['BV2']);
      expect(lines('feed covers').last.f['early']?.toJson(), true);
    });

    test('pulled back under and let go: nothing shows, the answer is kept unseen, and a pull armed again within '
        '10 s takes it without asking', () async {
      http.pages[1] = [feedItem('BV1')];
      final feed = held();
      await feed.refresh();
      http.pages[1] = [feedItem('BV2')];
      var notified = 0;
      feed.addListener(() => notified++);
      feed.pullArmed();
      await pumpEventQueue();
      feed.pullDisarmed();
      await pumpEventQueue();
      expect(notified, 0);
      expect(bvids(feed), ['BV1']);
      expect(lines('feed covers'), hasLength(1), reason: 'the first load only');
      final cancelled = lines('feed pull cancelled').single;
      expect(cancelled.f['answered']?.toJson(), true);

      now = now.add(const Duration(seconds: 9));
      feed.pullArmed();
      await pumpEventQueue();
      expect(http.asked, [1, 1], reason: 'within the window: no new call');
      await feed.refresh(pulled: true);
      expect(http.asked, [1, 1]);
      expect(bvids(feed), ['BV2']);
    });

    test('armed again after the window, it asks once more', () async {
      http.pages[1] = [feedItem('BV1')];
      final feed = held();
      feed.pullArmed();
      await pumpEventQueue();
      feed.pullDisarmed();
      now = now.add(FeedModel.earlyReuse + const Duration(seconds: 1));
      feed.pullArmed();
      await pumpEventQueue();
      expect(http.asked, [1, 1]);
    });

    test('wiggling across the trigger many times makes one request', () async {
      http.pages[1] = [feedItem('BV1')];
      final feed = held();
      http.gates[1] = Completer<void>();
      for (var i = 0; i < 20; i++) {
        feed.pullArmed();
        await pumpEventQueue();
        feed.pullDisarmed();
        now = now.add(const Duration(milliseconds: 100));
      }
      http.gates[1]!.complete();
      await pumpEventQueue();
      for (var i = 0; i < 20; i++) {
        feed.pullArmed();
        feed.pullDisarmed();
      }
      feed.pullArmed();
      await feed.refresh(pulled: true);
      expect(http.asked, [1]);
      expect(bvids(feed), ['BV1']);
    });

    test('any other refresh drops it: the next pull asks again', () async {
      http.pages[1] = [feedItem('BV1')];
      final feed = held();
      await feed.refresh();
      http.pages[1] = [feedItem('BV2')];
      feed.pullArmed();
      await pumpEventQueue();
      http.pages[1] = [feedItem('BV3')];
      await feed.refresh();
      expect(bvids(feed), ['BV3']);
      expect(http.asked, [1, 1, 1]);
      await feed.refresh(pulled: true);
      expect(http.asked, [1, 1, 1, 1], reason: 'nothing held to take');
    });

    test('dropped by a refresh while still out, its late answer never shows', () async {
      http.pages[1] = [feedItem('BV1')];
      final feed = held();
      await feed.refresh();
      http.pages[1] = [feedItem('BV2')];
      final gate = http.gates[1] = Completer<void>();
      feed.pullArmed();
      await pumpEventQueue();
      http.gates.remove(1);
      http.pages[1] = [feedItem('BV3')];
      await feed.refresh();
      asked.clear();
      gate.complete();
      await pumpEventQueue();
      expect(bvids(feed), ['BV3']);
      expect(asked, isEmpty, reason: 'no covers for a stale page');
    });

    test('a new app token makes it stale: the release asks the official feed instead', () async {
      http.pages[1] = [feedItem('BV1')];
      http.officialPages[0] = [officialItem('BV9')];
      final feed = held();
      feed.pullArmed();
      await pumpEventQueue();
      expect(http.asked, [1]);
      client.appToken = fakeAppToken;
      await feed.refresh(pulled: true);
      expect(http.officialAsked, [0]);
      expect(bvids(feed), ['BV9']);
      expect(feed.source, FeedSource.official);
    });

    test('a failed early page is not shown as the release\'s answer: the release asks again', () async {
      http.pages[1] = [feedItem('BV1')];
      final feed = held();
      await feed.refresh();
      http.failing.add(1);
      feed.pullArmed();
      await pumpEventQueue();
      feed.pullDisarmed();
      feed.pullArmed();
      await pumpEventQueue();
      expect(http.asked, [1, 1], reason: 'a failure within the window is not asked again by an arming');
      http.failing.clear();
      http.pages[1] = [feedItem('BV2')];
      await feed.refresh(pulled: true);
      expect(http.asked, [1, 1, 1]);
      expect(bvids(feed), ['BV2']);
      expect(lines('feed early page failed').single.f.keys, unorderedEquals(['error', 'status']));
    });
  });

  group('the picture connection', () {
    late DateTime now;
    late _PictureHttp pictureHttp;
    late PictureSession pictures;

    setUp(() {
      now = DateTime(2026, 10, 23, 12);
      pictureHttp = _PictureHttp();
      pictures = PictureSession(pictureHttp, now: () => now);
    });

    FeedModel connected({PictureSession? Function()? session, DateTime Function()? clock}) => FeedModel(
      client: BiliClient(transport: http, cookies: CookieJar(Canned.cookies), logger: Logger(session: 'test')),
      logger: Logger(session: 'test')..add(logs),
      officialWanted: () => false,
      now: clock ?? () => now,
      pictures: session ?? () => pictures,
    )..beforeShow = (fresh) => CoverPrefetch([for (final _ in fresh) Future.value(true)]);

    List<LogEvent> lines(String msg) => [for (final event in logs.events) if (event.msg == msg) event];

    List<Map<String, Object?>> done() => [
      for (final line in lines('feed covers done')) line.f.map((key, value) => MapEntry(key, value.toJson())),
    ];

    test("a refresh opens it while page 1 is out, asking i0 for the top card's cover; the first load has none",
        () async {
      http.pages[1] = [
        {...feedItem('BV1'), 'pic': 'http://i1.hdslb.com/bfs/archive/BV1.jpg'},
      ];
      final feed = connected();
      await feed.refresh();
      expect(pictureHttp.sent, isEmpty, reason: 'no picture shown yet to ask for');

      now = now.add(const Duration(minutes: 1));
      http.pages[1] = [feedItem('BV2')];
      final gate = http.gates[1] = Completer<void>();
      final refresh = feed.refresh();
      await pumpEventQueue();
      expect(http.asked, [1, 1]);
      expect(gate.isCompleted, isFalse, reason: 'page 1 still out');
      final head = pictureHttp.sent.single;
      expect(head.method, 'HEAD');
      expect('${head.url}', 'https://i0.hdslb.com/bfs/archive/BV1.jpg');
      gate.complete();
      await refresh;

      await feed.refresh();
      expect(pictureHttp.sent, hasLength(1), reason: 'answered moments ago: the connection is still open');
    });

    test('a pull armed opens it once; the release that takes its page asks nothing more', () async {
      http.pages[1] = [feedItem('BV1')];
      final feed = connected();
      await feed.refresh();
      now = now.add(const Duration(minutes: 1));
      http.pages[1] = [feedItem('BV2')];
      final hold = Completer<void>();
      pictureHttp.hold = hold.future;
      feed.pullArmed();
      await pumpEventQueue();
      expect(pictureHttp.sent.single.method, 'HEAD');
      feed.pullDisarmed();
      feed.pullArmed();
      await feed.refresh(pulled: true);
      hold.complete();
      await pumpEventQueue();
      expect(pictureHttp.sent, hasLength(1));
      expect(http.asked, [1, 1]);
    });

    test("once the shown covers are all in or failed, one line says when the 3rd and the last came and whether the "
        'connection was open as they were asked for', () async {
      http.pages[1] = [feedItem('BV1')];
      final feed = connected();
      await feed.refresh();
      now = now.add(const Duration(minutes: 1));
      http.pages[1] = [for (var i = 2; i < 7; i++) feedItem('BV$i')];
      final covers = [for (var i = 0; i < 5; i++) Completer<bool>()];
      feed.beforeShow = (_) => CoverPrefetch([for (final cover in covers) cover.future]);
      await feed.refresh();
      final asked = now;
      expect(done(), hasLength(1), reason: 'the first load only');

      for (final (ms, index, ok) in [(120, 0, true), (180, 3, false), (260, 1, true), (310, 4, true), (700, 2, true)]) {
        now = asked.add(Duration(milliseconds: ms));
        covers[index].complete(ok);
        await pumpEventQueue();
      }
      expect(done(), hasLength(2));
      expect(done().last, {
        'of': 5,
        'ready': 4,
        'failed': 1,
        'thirdMs': 310,
        'lastMs': 700,
        'warm': true,
        'warmed': 'ok',
        'early': false,
      });
      expect(lines('feed covers').last.f.keys, unorderedEquals(['ready', 'failed', 'of', 'early']));
    });

    test('a warm still out as the covers are asked for is noted; on the PC there is no connection to warm', () async {
      http.pages[1] = [feedItem('BV1')];
      final feed = connected();
      await feed.refresh();
      now = now.add(const Duration(minutes: 1));
      pictureHttp.hold = Completer<void>().future;
      http.pages[1] = [feedItem('BV2')];
      await feed.refresh();
      await pumpEventQueue();
      expect(done().last, {
        'of': 1,
        'ready': 1,
        'failed': 0,
        'lastMs': 0,
        'warm': false,
        'warming': true,
        'warmed': 'pending',
        'early': false,
      });

      final pc = connected(session: () => null);
      http.pages[1] = [feedItem('BV3')];
      await pc.refresh();
      await pumpEventQueue();
      expect(done(), hasLength(3));
      expect(done().last['warm'], false);
      expect(done().last['warmed'], 'none');
      expect(done().last.containsKey('warming'), isFalse);
    });

    test("the line says what the refresh's warm came to: none when it sent none, failed apart from ok", () async {
      http.pages[1] = [feedItem('BV1')];
      final feed = connected();
      await feed.refresh();
      await pumpEventQueue();
      expect(done().last['warmed'], 'none', reason: 'no picture shown yet to ask for');

      now = now.add(const Duration(minutes: 1));
      pictureHttp.error = TimeoutException('head');
      http.pages[1] = [feedItem('BV2')];
      await feed.refresh();
      await pumpEventQueue();
      expect(pictureHttp.sent, hasLength(1));
      expect(done().last['warm'], false);
      expect(done().last['warmed'], 'failed');

      pictureHttp.error = null;
      http.pages[1] = [feedItem('BV3')];
      await feed.refresh();
      await pumpEventQueue();
      expect(done().last['warmed'], 'ok');

      http.pages[1] = [feedItem('BV4')];
      await feed.refresh();
      await pumpEventQueue();
      expect(pictureHttp.sent, hasLength(2), reason: 'answered moments ago: no warm sent');
      expect(done().last['warm'], true);
      expect(done().last['warmed'], 'none');
    });

    test("a held pull's covers count from when its page came in, and the line says early", () async {
      http.pages[1] = [feedItem('BV1')];
      final feed = connected();
      await feed.refresh();
      now = now.add(const Duration(minutes: 1));
      http.pages[1] = [feedItem('BV2'), feedItem('BV3'), feedItem('BV4')];
      final covers = [for (var i = 0; i < 3; i++) Completer<bool>()];
      feed.beforeShow = (_) => CoverPrefetch([for (final cover in covers) cover.future]);
      feed.pullArmed();
      await pumpEventQueue();
      final landed = now;
      now = landed.add(const Duration(milliseconds: 200));
      covers[0].complete(true);
      covers[1].complete(true);
      await pumpEventQueue();
      now = landed.add(const Duration(milliseconds: 900));
      await feed.refresh(pulled: true);
      expect(done(), hasLength(1), reason: 'one still out');
      now = landed.add(const Duration(milliseconds: 1000));
      covers[2].complete(true);
      await pumpEventQueue();
      expect(done(), hasLength(2));
      expect(done().last, {
        'of': 3,
        'ready': 3,
        'failed': 0,
        'thirdMs': 1000,
        'lastMs': 1000,
        'warm': true,
        'warmed': 'ok',
        'early': true,
      });
    });

    test('with covers still out 10 s after they were asked for, it logs what came, timed out; a model disposed first '
        'logs nothing and leaves no timer', () {
      fakeAsync((async) {
        final start = DateTime(2026, 10, 23, 12);
        final feed = connected(session: () => null, clock: () => start.add(async.elapsed));
        http.pages[1] = [feedItem('BV1'), feedItem('BV2')];
        final first = Completer<bool>();
        feed.beforeShow = (_) => CoverPrefetch([first.future, Completer<bool>().future]);
        unawaited(feed.refresh());
        async.flushMicrotasks();
        expect(feed.cards, hasLength(2));
        async.elapse(const Duration(milliseconds: 400));
        first.complete(true);
        async.elapse(const Duration(seconds: 9));
        expect(done(), isEmpty);
        async.elapse(const Duration(seconds: 1));
        expect(done(), [
          {
            'of': 2,
            'ready': 1,
            'failed': 0,
            'lastMs': 400,
            'warm': false,
            'warmed': 'none',
            'early': false,
            'timedOut': true,
          },
        ]);

        http.pages[1] = [feedItem('BV3')];
        feed.beforeShow = (_) => CoverPrefetch([Completer<bool>().future]);
        unawaited(feed.refresh());
        async.flushMicrotasks();
        expect(feed.cards.single.bvid, 'BV3');
        feed.dispose();
        expect(async.pendingTimers, isEmpty);
        async.elapse(const Duration(seconds: 11));
        expect(done(), hasLength(1));
      });
    });

    test('a model disposed while page 1 is out asks for no covers when the page lands, logs nothing and leaves no '
        'timer', () {
      fakeAsync((async) {
        final start = DateTime(2026, 10, 23, 12);
        final feed = connected(clock: () => start.add(async.elapsed));
        var asked = false;
        feed.beforeShow = (_) {
          asked = true;
          return CoverPrefetch([Completer<bool>().future]);
        };
        http.pages[1] = [feedItem('BV1')];
        final gate = http.gates[1] = Completer<void>();
        String? result = 'unfinished';
        unawaited(feed.refresh().then((value) => result = value));
        async.flushMicrotasks();
        feed.dispose();
        gate.complete();
        async.flushMicrotasks();
        expect(result, isNull);
        expect(asked, isFalse);
        expect(feed.cards, isEmpty);
        expect(async.pendingTimers, isEmpty);
        async.elapse(const Duration(seconds: 11));
        expect(logs.events, isEmpty);
      });
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
