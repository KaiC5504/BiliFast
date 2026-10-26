import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/dynamic/fake_dynamic_api.dart';
import 'package:bilifast/dynamic/follow_tab/follow_feed_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'follow_fixtures.dart';

void main() {
  late Logger logger;
  late MemorySink sink;

  setUp(() {
    logger = Logger(session: 'test');
    sink = MemorySink();
    logger.add(sink);
  });

  List<LogEvent> logged(String message) => [
    for (final event in sink.events)
      if (event.msg == message) event,
  ];

  group('FollowFeed', () {
    test('pages by offset, drops repeats, and stops at has_more false', () async {
      final asked = <String?>[];
      final pages = {
        null: DynamicPage(items: posts(3), offset: 'a', hasMore: true),
        'a': DynamicPage(items: [post(2), ...posts(2, from: 3)], offset: 'b', hasMore: false),
      };
      final feed = FollowFeed(
        name: 'all',
        load: (offset) async {
          asked.add(offset);
          return pages[offset]!;
        },
        logger: logger,
      );
      await feed.start();
      await feed.start();
      expect(asked, [null], reason: 'started once');
      expect(feed.canLoadMore, isTrue);
      await feed.loadMore();
      expect(asked, [null, 'a']);
      expect([for (final item in feed.items) item.id], ['p0', 'p1', 'p2', 'p3', 'p4']);
      expect(feed.isEnd, isTrue);
      await feed.loadMore();
      expect(asked, [null, 'a'], reason: 'nothing after the end');
    });

    test('a page that adds nothing new stops the paging, whatever has_more says', () async {
      var calls = 0;
      final feed = FollowFeed(
        name: 'all',
        load: (offset) async {
          calls++;
          return DynamicPage(items: posts(2), offset: 'again', hasMore: true);
        },
        logger: logger,
      );
      await feed.start();
      expect(feed.isEnd, isFalse);
      await feed.loadMore();
      expect(feed.isEnd, isTrue);
      expect(feed.canLoadMore, isFalse);
      await feed.loadMore();
      expect(calls, 2);
    });

    test('one call at a time', () async {
      final gate = Completer<void>();
      var calls = 0;
      final feed = FollowFeed(
        name: 'video',
        load: (offset) async {
          calls++;
          if (offset != null) await gate.future;
          return DynamicPage(
            items: posts(2, from: calls * 10),
            offset: 'o$calls',
            hasMore: true,
          );
        },
        logger: logger,
      );
      await feed.start();
      final first = feed.loadMore();
      expect(feed.loading, isTrue);
      expect(feed.canLoadMore, isFalse);
      await feed.loadMore();
      expect(calls, 2);
      gate.complete();
      await first;
      expect(feed.items, hasLength(4));
    });

    test('logs each page by kind and count, never a name or a word', () async {
      final feed = FollowFeed(
        name: 'all',
        load: (offset) async => DynamicPage(
          items: posts(4),
          offset: 'x',
          hasMore: true,
          skipped: const {'DYNAMIC_TYPE_LIVE': 2, 'DYNAMIC_TYPE_NONE': 1},
        ),
        logger: logger,
      );
      await feed.start();
      final events = logged('dynamic feed');
      expect(events, hasLength(1));
      final fields = events.single.f;
      expect(fields.keys.toSet(), {'type', 'count', 'added', 'more', 'skipped', 'ms'});
      expect(fields['type'], const LogString('all'));
      expect(fields['count'], const LogInt(4));
      expect(fields['skipped'], const LogString('DYNAMIC_TYPE_LIVE:2,DYNAMIC_TYPE_NONE:1'));
      expect(fields['more'], const LogBool(true));
    });

    test('a refresh that fails keeps the posts and hands back its words; with none, the list says it', () async {
      var fail = false;
      final feed = FollowFeed(
        name: 'all',
        load: (offset) async {
          if (fail) throw const BiliError.api(code: -500, message: '服务器错误');
          return DynamicPage(items: posts(2));
        },
        logger: logger,
      );
      await feed.start();
      fail = true;
      final words = await feed.reload();
      expect(words, isNotNull);
      expect(feed.items, hasLength(2));
      expect(feed.error, isNull);
      feed.clear();
      await feed.start();
      expect(feed.items, isEmpty);
      expect(feed.error, isNotNull);
      expect(logged('dynamic feed failed'), hasLength(2));
    });

    test(
      "after an empty list and a failed refresh, 重试 asks the first page again (loadMore takes it as the end)",
      () async {
        final asked = <String?>[];
        var answer = <DynamicItem>[];
        Object? failure;
        final feed = FollowFeed(
          name: 'all',
          load: (offset) async {
            asked.add(offset);
            if (failure case final error?) throw error;
            return DynamicPage(items: answer);
          },
          logger: logger,
        );
        await feed.start();
        expect(feed.isEnd, isTrue);
        failure = const BiliError.api(code: -500, message: '服务器错误');
        expect(await feed.reload(), isNull, reason: 'no posts to keep: the list says it');
        expect(feed.error, 'B 站返回错误 -500：服务器错误');

        failure = null;
        answer = posts(2);
        await feed.retry();
        expect(asked, [null, null, null]);
        expect(feed.items, hasLength(2));
        expect(feed.error, isNull);
      },
    );

    test('a refresh while the first page is out, or another refresh, asks nothing more', () async {
      final gate = Completer<void>();
      var calls = 0;
      final feed = FollowFeed(
        name: 'all',
        load: (offset) async {
          calls++;
          await gate.future;
          return DynamicPage(items: posts(2));
        },
        logger: logger,
      );
      final start = feed.start();
      final refreshed = feed.reload();
      final again = feed.reload();
      expect(calls, 1);
      gate.complete();
      await Future.wait([start, refreshed, again]);
      expect(calls, 1);
      await feed.reload();
      expect(calls, 2, reason: 'once answered, a refresh asks again');
    });

    test('a refresh while a next page is out keeps only the refreshed posts, and pages on from them', () async {
      final asked = <String?>[];
      final late = Completer<void>();
      final feed = FollowFeed(
        name: 'all',
        load: (offset) async {
          asked.add(offset);
          if (asked.length == 2) await late.future;
          return offset == null
              ? DynamicPage(items: posts(3), offset: 'a', hasMore: true)
              : DynamicPage(items: posts(3, from: 3), offset: 'b', hasMore: true);
        },
        logger: logger,
      );
      await feed.start();
      final paging = feed.loadMore();
      await feed.reload();
      late.complete();
      await paging;
      expect([for (final item in feed.items) item.id], ['p0', 'p1', 'p2'], reason: "the old next page dropped");
      expect(feed.loading, isFalse);
      expect(feed.canLoadMore, isTrue);

      await feed.loadMore();
      expect(asked, [null, 'a', null, 'a']);
      expect([for (final item in feed.items) item.id], ['p0', 'p1', 'p2', 'p3', 'p4', 'p5']);
    });
  });

  group('FollowTabModel', () {
    test('the first show asks the faces and 全部; 视频 asks its list and the posters once', () async {
      final api = FakeDynamicApi(posts: posts(3), upList: faces);
      final model = FollowTabModel(api: api, mid: () => 12345, logger: logger);
      addTearDown(model.dispose);
      await model.start();
      expect(api.calls, ['ups offset=', 'feed all offset=']);
      model.select(DynamicFeedType.video);
      await pumpEventQueue();
      model
        ..select(DynamicFeedType.all)
        ..select(DynamicFeedType.video);
      await pumpEventQueue();
      expect(api.calls, ['ups offset=', 'feed all offset=', 'feed video offset=', 'bangumi page=1']);
    });

    test('a face opened loses its dot for the run; signing out forgets everything', () async {
      final api = FakeDynamicApi(posts: posts(3), upList: faces);
      final model = FollowTabModel(api: api, mid: () => 12345, logger: logger);
      addTearDown(model.dispose);
      await model.start();
      expect(model.hasUpdate(faces[0]), isTrue);
      model.markSeen(faces[0].mid);
      expect(model.hasUpdate(faces[0]), isFalse);
      await model.refresh();
      expect(model.hasUpdate(faces[0]), isFalse, reason: 'kept across refreshes');
      model.signOut();
      expect(model.ups, isEmpty);
      expect(model.current.items, isEmpty);
      expect(model.hasUpdate(faces[0]), isTrue);
    });

    test('one refresh at a time: one asked while the first show or a refresh is out asks nothing more', () async {
      final api = FakeDynamicApi(posts: posts(3), upList: faces)
        ..holds['ups'] = Completer<void>()
        ..holds['feed'] = Completer<void>();
      final model = FollowTabModel(api: api, mid: () => 12345, logger: logger);
      addTearDown(model.dispose);
      final start = model.start();
      final refreshed = model.refresh();
      final again = model.refresh();
      expect(api.calls, ['ups offset=', 'feed all offset=']);
      api.holds.remove('ups')!.complete();
      api.holds.remove('feed')!.complete();
      await Future.wait([start, refreshed, again]);
      expect(api.calls, hasLength(2));

      api.holds['bangumi'] = Completer<void>();
      model.select(DynamicFeedType.video);
      await pumpEventQueue();
      final onVideo = model.refresh();
      await pumpEventQueue();
      api.holds.remove('bangumi')!.complete();
      await onVideo;
      expect(api.calls.sublist(2), [
        'feed video offset=',
        'bangumi page=1',
        'ups offset=',
        'feed video offset=',
      ], reason: "视频's posters still out answer for the refresh's");
    });

    test('a later page of faces that fails asks no more until a refresh answers', () async {
      final api = PagedUpsApi(posts: posts(3), first: faces.sublist(0, 2), rest: faces.sublist(2))
        ..failMore = const BiliError.api(code: -352, message: '风控');
      final model = FollowTabModel(api: api, mid: () => 12345, logger: logger);
      addTearDown(model.dispose);
      await model.start();
      for (var i = 0; i < 5; i++) {
        await model.loadMoreUps();
      }
      expect(api.calls.where((call) => call == 'ups offset=u1'), hasLength(1));
      expect(model.ups, hasLength(2));
      expect(logged('dynamic ups failed').single.f['more'], const LogBool(true));

      api.failMore = null;
      await model.refresh();
      await model.loadMoreUps();
      expect(api.calls.where((call) => call == 'ups offset=u1'), hasLength(2));
      expect(model.ups, hasLength(4));
      await model.loadMoreUps();
      expect(api.calls.where((call) => call == 'ups offset=u1'), hasLength(2), reason: 'the last page');
    });

    test('logged out, 我的追番 · 追剧 is never asked', () async {
      final api = FakeDynamicApi(posts: posts(3), upList: faces);
      final model = FollowTabModel(api: api, mid: () => null, logger: logger);
      addTearDown(model.dispose);
      model.select(DynamicFeedType.video);
      await model.start();
      expect(api.calls, ['ups offset=', 'feed video offset=']);
      expect(model.bangumi, isEmpty);
    });
  });
}
