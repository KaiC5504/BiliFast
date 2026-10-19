import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/history/history_model.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'history_fakes.dart';

void main() {
  late FakePageApi api;
  late DateTime now;
  var loggedIn = true;

  setUp(() {
    api = FakePageApi();
    now = wallTime(19, 0, 5);
    loggedIn = true;
  });

  HistoryModel model() => HistoryModel(
    api: api,
    isLoggedIn: () => loggedIn,
    now: () => now,
    utcOffset: testOffset,
    logger: Logger(session: 'test'),
  );

  List<String> titles(HistoryModel model) => [
    for (final section in model.sections) '${section.title} ${section.items.map((item) => item.aid).join(',')}',
  ];

  group('grouping', () {
    test('今天, 昨天, then everything older under one 更早', () async {
      api.historyItems = [
        historyItem(1, viewAt: wall(19, 0, 1)),
        historyItem(2, viewAt: wall(18, 23, 59)),
        historyItem(3, viewAt: wall(18, 0, 0)),
        historyItem(4, viewAt: wall(17, 23, 59)),
        historyItem(5, viewAt: wall(12, 8, 0)),
        historyItem(6, viewAt: wall(3, 8, 0, month: 9)),
      ];
      final history = model();
      await history.start();
      expect(titles(history), ['今天 1', '昨天 2,3', '更早 4,5,6']);
    });

    test('the groups move on when the clock passes midnight', () async {
      now = wallTime(18, 23, 58);
      api.historyItems = [
        historyItem(1, viewAt: wall(18, 23, 50)),
        historyItem(2, viewAt: wall(17, 23, 59)),
        historyItem(3, viewAt: wall(16, 12, 0)),
      ];
      final history = model();
      await history.start();
      expect(titles(history), ['今天 1', '昨天 2', '更早 3']);

      now = wallTime(19, 0, 1);
      expect(titles(history), ['昨天 1', '更早 2,3']);
    });

    test('empty groups are left out', () async {
      api.historyItems = [historyItem(1, viewAt: wall(10, 8, 0))];
      final history = model();
      await history.start();
      expect(titles(history), ['更早 1']);
    });

    test('the time is the full date at the offset', () {
      final history = model();
      expect(history.timeLabel(historyItem(1, viewAt: wall(19, 3, 2))), '2026年10月19日 03:02');
    });
  });

  group('paging', () {
    test('pages through the cursor until an empty page', () async {
      api.historyItems = historyRows(45, from: wall(18, 22, 0));
      final history = model();
      await history.start();
      expect(history.items.length, 20);
      expect(history.isEnd, isFalse);
      expect(history.canLoadMore, isTrue);

      await history.loadMore();
      expect(history.items.length, 40);
      await history.loadMore();
      expect(history.items.length, 45);
      expect(history.isEnd, isFalse, reason: 'the last full cursor still asks once more');

      await history.loadMore();
      expect(history.items.length, 45);
      expect(history.isEnd, isTrue);
      expect(history.canLoadMore, isFalse);
      expect(api.calls, ['history after=0', 'history after=20', 'history after=40', 'history after=45']);

      await history.loadMore();
      expect(api.calls.length, 4, reason: 'nothing is asked once the end is reached');
      expect(history.items.map((item) => item.aid), [for (var i = 1; i <= 45; i++) i]);
    });

    test('a page of rows already listed asks on instead of stalling', () async {
      final rows = historyRows(3, from: wall(18, 22, 0));
      final pages = [
        HistoryPage(items: rows.sublist(0, 2), next: const HistoryCursor(max: 2, viewAt: 1)),
        HistoryPage(items: rows.sublist(0, 2), next: const HistoryCursor(max: 2, viewAt: 2)),
        HistoryPage(items: rows.sublist(2), next: const HistoryCursor(max: 3, viewAt: 3)),
      ];
      final history = HistoryModel(
        api: _PagedApi(pages),
        isLoggedIn: () => true,
        logger: Logger(session: 'test'),
      );
      await history.start();
      await history.loadMore();
      expect(history.items.map((item) => item.aid), [1, 2, 3]);
    });

    test('a failed page shows its error and asks again only on retry', () async {
      api.historyItems = historyRows(25, from: wall(18, 22, 0));
      final history = model();
      await history.start();
      api.failures['history'] = const BiliError.http(500);
      await history.loadMore();
      expect(history.error, isNotNull);
      expect(history.items.length, 20, reason: 'the rows shown stay');
      expect(history.canLoadMore, isFalse);

      api.failures.remove('history');
      await history.loadMore();
      expect(history.error, isNull);
      expect(history.items.length, 25);
    });

    test('a failed first page leaves an error with no rows', () async {
      api.failures['history'] = const BiliError.http(502);
      final history = model();
      await history.start();
      expect(history.items, isEmpty);
      expect(history.error, isNotNull);
    });

    test('an empty history ends at once', () async {
      final history = model();
      await history.start();
      expect(history.items, isEmpty);
      expect(history.isEnd, isTrue);
      expect(history.error, isNull);
    });
  });

  group('refresh', () {
    test('keeps the rows on screen until the first page answers', () async {
      api.historyItems = historyRows(30, from: wall(18, 22, 0));
      final history = model();
      await history.start();
      await history.loadMore();
      expect(history.items.length, 30);

      api.historyItems = [historyItem(99, viewAt: wall(19, 0, 4)), ...api.historyItems];
      final hold = Completer<void>();
      api.holds['history'] = hold;
      final reloading = history.reload();
      await Future<void>.delayed(Duration.zero);
      expect(history.refreshing, isTrue);
      expect(history.items.length, 30, reason: 'the list stays while it reloads');

      hold.complete();
      expect(await reloading, isNull);
      expect(history.refreshing, isFalse);
      expect(history.items.first.aid, 99);
      expect(history.items.length, 20, reason: 'starts over from the first page');
      expect(history.isEnd, isFalse);
    });

    test('a failed refresh keeps the rows and hands back words for a toast', () async {
      api.historyItems = historyRows(5, from: wall(18, 22, 0));
      final history = model();
      await history.start();
      api.failures['history'] = const BiliError.http(500);
      final message = await history.reload();
      expect(message, isNotNull);
      expect(history.items.length, 5);
      expect(history.error, isNull);
    });

    test('a load more still running cannot append to the reloaded list', () async {
      api.historyItems = historyRows(25, from: wall(18, 22, 0));
      final history = model();
      await history.start();
      final hold = Completer<void>();
      api.holds['history'] = hold;
      final more = history.loadMore();
      await Future<void>.delayed(Duration.zero);
      api.holds.remove('history');
      await history.reload();
      hold.complete();
      await more;
      expect(history.items.length, 20);
    });
  });

  group('login', () {
    test('logged out shows the login state without asking Bilibili', () async {
      loggedIn = false;
      final history = model();
      await history.start();
      expect(history.needsLogin, isTrue);
      expect(api.calls, isEmpty);
    });

    test('-101 turns into the login state, and a reload after logging in loads the list', () async {
      api.historyItems = historyRows(3, from: wall(18, 22, 0));
      api.failures['history'] = const BiliError.api(code: -101, message: '账号未登录');
      final history = model();
      await history.start();
      expect(history.needsLogin, isTrue);
      expect(history.error, isNull);
      expect(history.canLoadMore, isFalse);

      api.failures.remove('history');
      await history.reload();
      expect(history.needsLogin, isFalse);
      expect(history.items.length, 3);
    });
  });

  group('rows', () {
    test('a row resumes where it was left, a finished one from the start', () {
      final watching = HistoryModel.route(historyItem(1, viewAt: 0, progress: 158));
      expect(watching.bvid, 'BV1test1');
      expect(watching.cid, 1001);
      expect(watching.start, 158);
      expect(HistoryModel.route(historyItem(2, viewAt: 0, progress: -1)).start, 0);
    });

    test('the cover shows the time watched, hours as hh:mm:ss, or 已看完', () {
      expect(HistoryModel.progressLabel(historyItem(1, viewAt: 0, progress: 2, duration: 447)), '00:02/07:27');
      expect(HistoryModel.progressLabel(historyItem(1, viewAt: 0, progress: 6, duration: 13230)), '00:06/03:40:30');
      expect(HistoryModel.progressLabel(historyItem(1, viewAt: 0, progress: -1, duration: 600)), '已看完');
      expect(
        HistoryModel.progressFraction(historyItem(1, viewAt: 0, progress: 26, duration: 193)),
        closeTo(0.1347, 0.001),
      );
      expect(HistoryModel.progressFraction(historyItem(1, viewAt: 0, progress: -1)), 1);
      expect(HistoryModel.progressFraction(historyItem(1, viewAt: 0, progress: 5, duration: 0)), 0);
    });

    test('分享 hands out the video page on the web', () {
      expect(HistoryModel.shareLink(historyItem(7, viewAt: 0)).toString(), 'https://www.bilibili.com/video/BV1test7');
    });
  });

  group('delete', () {
    test('takes the row off at once and deletes it on the server', () async {
      api.historyItems = historyRows(3, from: wall(18, 22, 0));
      final history = model();
      await history.start();
      final hold = Completer<void>();
      api.holds['deleteHistory'] = hold;
      final deleting = history.delete(history.items[1]);
      expect(history.items.map((item) => item.aid), [1, 3]);
      hold.complete();
      expect(await deleting, isNull);
      expect(api.calls.last, 'deleteHistory aid=2');
      expect(history.items.map((item) => item.aid), [1, 3]);
    });

    test('a failed delete puts the row back where it was and says so', () async {
      api.historyItems = historyRows(3, from: wall(18, 22, 0));
      final history = model();
      await history.start();
      api.failures['deleteHistory'] = const BiliError.api(code: -111, message: 'csrf 校验失败');
      final hold = Completer<void>();
      api.holds['deleteHistory'] = hold;
      final deleting = history.delete(history.items[1]);
      expect(history.items.map((item) => item.aid), [1, 3]);
      hold.complete();
      expect(await deleting, HistoryModel.deleteFailed);
      expect(history.items.map((item) => item.aid), [1, 2, 3]);
    });

    test('a -101 answer turns the page to its login state without a toast', () async {
      api.historyItems = historyRows(3, from: wall(18, 22, 0));
      final history = model();
      await history.start();
      api.failures['deleteHistory'] = const BiliError.api(code: -101, message: '账号未登录');
      expect(await history.delete(history.items[1]), isNull);
      expect(history.needsLogin, isTrue);
      expect(history.items, isEmpty);
      expect(history.loading, isFalse);
    });

    test('a deleted row does not come back with a later page', () async {
      final rows = historyRows(2, from: wall(18, 22, 0));
      final pages = [
        HistoryPage(items: rows, next: const HistoryCursor(max: 2, viewAt: 1)),
        HistoryPage(
          items: [
            rows[1],
            historyItem(3, viewAt: wall(17, 8, 0)),
          ],
          next: null,
        ),
      ];
      final api = _PagedApi(pages);
      final history = HistoryModel(
        api: api,
        isLoggedIn: () => true,
        logger: Logger(session: 'test'),
      );
      await history.start();
      await history.delete(rows[1]);
      await history.loadMore();
      expect(history.items.map((item) => item.aid), [1, 3]);
    });
  });

  test('the --fake-account demo has two pages over 今天, 昨天 and 更早', () async {
    final demo = FakePageApi.demo(now: DateTime(2026, 10, 19, 9, 8))..delay = Duration.zero;
    final history = HistoryModel(
      api: demo,
      isLoggedIn: () => true,
      now: () => DateTime(2026, 10, 19, 9, 8),
      logger: Logger(session: 'test'),
    );
    await history.start();
    expect(history.items.length, 20);
    await history.loadMore();
    await history.loadMore();
    expect(history.isEnd, isTrue);
    expect(history.items.length, 30);
    expect([for (final section in history.sections) section.title], ['今天', '昨天', '更早']);
    expect(history.items.where((item) => item.progress < 0).length, 1);
    expect(history.items.map((item) => item.deviceKind).toSet(), {HistoryDeviceKind.phone, HistoryDeviceKind.pc});
    expect(history.items.every((item) => item.cover.isEmpty), isTrue, reason: 'no real covers are fetched');
  });
}

/// Answers [pages] in turn, whatever the cursor.
class _PagedApi extends FakePageApi {
  _PagedApi(this.pages);

  final List<HistoryPage> pages;
  var _next = 0;

  @override
  Future<HistoryPage> history({HistoryCursor? after}) async =>
      _next < pages.length ? pages[_next++] : const HistoryPage(items: [], next: null);

  @override
  Future<void> deleteHistory(HistoryItem item) async {}
}
