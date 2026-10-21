import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/home/feed_model.dart' show requestFailureMessage;
import 'package:bilifast/watch_later/fake_watch_later_api.dart';
import 'package:bilifast/watch_later/watch_later_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'watch_later_fakes.dart';

void main() {
  late FakeWatchLaterApi api;
  late WatchLaterModel model;
  var loggedIn = true;

  setUp(() {
    loggedIn = true;
    api = FakeWatchLaterApi(items: laterItems(23), folderList: testFolders);
    model = WatchLaterModel(
      api: api,
      isLoggedIn: () => loggedIn,
      accountMid: () => 77,
      logger: Logger(session: 'test'),
    );
    addTearDown(model.dispose);
  });

  Future<void> idle() => pumpEventQueue();

  List<int> numbers() => [for (final item in model.items) item.aid - 83000000];

  test('the first page is 全部, newest first, and the next page follows on asking', () async {
    await model.start();
    await idle();
    expect(api.calls, ['list all newest page=1']);
    expect(numbers(), [for (var i = 1; i <= 20; i++) i]);
    expect(model.hasMore, isTrue);
    model.loadMore();
    await idle();
    expect(api.calls.last, 'list all newest page=2');
    expect(model.items.length, 23);
    expect(model.hasMore, isFalse);
    model.loadMore();
    await idle();
    expect(api.calls.length, 2, reason: 'the end asks nothing more');
  });

  test('未看完 lists with its filter and leaves out the finished', () async {
    api.items[1] = laterItem(2, progress: -1);
    await model.start();
    await idle();
    model.selectFilter(WatchLaterFilter.unfinished);
    expect(model.items, isEmpty, reason: 'the old chip’s rows go at once');
    await idle();
    expect(api.calls.last, 'list unfinished newest page=1');
    expect(numbers(), isNot(contains(2)));
    model.selectFilter(WatchLaterFilter.unfinished);
    await idle();
    expect(api.calls.length, 2, reason: 'the chosen chip again asks nothing');
  });

  test('the sort turns the list to oldest first, and back', () async {
    await model.start();
    await idle();
    model.toggleOrder();
    await idle();
    expect(model.oldestFirst, isTrue);
    expect(api.calls.last, 'list all oldest page=1');
    expect(numbers().first, 23);
    model.toggleOrder();
    await idle();
    expect(api.calls.last, 'list all newest page=1');
    expect(numbers().first, 1);
  });

  test('changing the chip while a page is out asks once for the latest choice when it answers', () async {
    final hold = api.holds['list'] = Completer<void>();
    unawaited(model.start());
    await idle();
    model.selectFilter(WatchLaterFilter.unfinished);
    model.selectFilter(WatchLaterFilter.all);
    model.selectFilter(WatchLaterFilter.unfinished);
    expect(api.calls, ['list all newest page=1'], reason: 'one call out at a time');
    api.holds.remove('list');
    hold.complete();
    await idle();
    expect(api.calls, ['list all newest page=1', 'list unfinished newest page=1']);
    expect(model.filter, WatchLaterFilter.unfinished);
    expect(model.items, isNotEmpty);
  });

  test('a failed first page waits for 重试', () async {
    api.failures['list'] = const BiliError.http(500);
    await model.start();
    await idle();
    expect(model.error, isNotNull);
    expect(model.canLoadMore, isFalse);
    api.failures.clear();
    model.retry();
    await idle();
    expect(model.error, isNull);
    expect(model.items.length, 20);
  });

  test('logged out asks nothing; a -101 turns the list to its login state', () async {
    loggedIn = false;
    await model.start();
    expect(model.needsLogin, isTrue);
    expect(api.calls, isEmpty);

    loggedIn = true;
    api.failures['list'] = const BiliError.api(code: -101, message: '账号未登录');
    await model.reload();
    expect(model.needsLogin, isTrue);
    api.failures.clear();
    await model.reload();
    expect(model.needsLogin, isFalse);
    expect(model.items.length, 20);
  });

  test('a failed pull keeps the rows, says why, and paging goes on from where they end', () async {
    await model.start();
    await idle();
    api.failures['list'] = const BiliError.http(500);
    expect(await model.reload(), requestFailureMessage(const BiliError.http(500)));
    expect(model.items.length, 20);
    expect(model.error, isNull);
    api.failures.clear();
    model.loadMore();
    await idle();
    expect(api.calls.last, 'list all newest page=2');
    expect(model.items.length, 23);
  });

  test('removing a row takes it off at once and posts its aid', () async {
    await model.start();
    await idle();
    final row = model.items[2];
    final done = model.remove(row);
    expect(numbers().take(3), [1, 2, 4]);
    expect(await done, isNull);
    expect(api.calls.last, 'remove ${row.aid}');
  });

  test('a removal that fails puts the row back where it was and says why', () async {
    await model.start();
    await idle();
    final row = model.items[2];
    api.failures['remove'] = const BiliError.api(code: -400, message: '请求错误');
    expect(await model.remove(row), requestFailureMessage(api.failures['remove']!));
    expect(numbers().take(4), [1, 2, 3, 4]);
  });

  test('a page answering after a removal doesn’t bring the row back', () async {
    await model.start();
    await idle();
    final row = model.items.first;
    await model.remove(row);
    // The server here still lists it, as one answering before its delete lands would.
    api.items.insert(0, row);
    await model.reload();
    expect(numbers(), isNot(contains(1)));
  });

  test('删除 refused with -101 turns the list to its login state', () async {
    await model.start();
    await idle();
    api.failures['remove'] = const BiliError.api(code: -101, message: '账号未登录');
    expect(await model.remove(model.items[2]), isNull, reason: 'no toast');
    expect(model.needsLogin, isTrue);
    expect(model.items, isEmpty);
  });

  test(
    'removals among the first page leave no row behind: the next ask is the page holding the first unseen row',
    () async {
      api = FakeWatchLaterApi(items: laterItems(25));
      model = WatchLaterModel(
        api: api,
        isLoggedIn: () => true,
        accountMid: () => 77,
        logger: Logger(session: 'test'),
      );
      addTearDown(model.dispose);
      await model.start();
      await idle();
      model.setEditing(true);
      model.toggleChosen(model.items[2]);
      model.toggleChosen(model.items[6]);
      expect(await model.removeChosen(), isNull);
      expect(await model.remove(model.items[12]), isNull);
      expect(numbers(), isNot(contains(15)));
      final remaining = [
        for (var i = 1; i <= 25; i++)
          if (i != 3 && i != 7 && i != 15) i,
      ];
      for (var asks = 0; model.canLoadMore && asks < 5; asks++) {
        model.loadMore();
        await idle();
      }
      expect(numbers(), remaining);
      expect(model.hasMore, isFalse);
      expect(api.calls.where((call) => call.startsWith('list')), [
        'list all newest page=1',
        'list all newest page=1',
        'list all newest page=2',
      ]);
    },
  );

  test('a removal while the next page is out leaves no row behind, and rows keep the server’s order', () async {
    api = FakeWatchLaterApi(items: laterItems(25));
    model = WatchLaterModel(
      api: api,
      isLoggedIn: () => true,
      accountMid: () => 77,
      logger: Logger(session: 'test'),
    );
    addTearDown(model.dispose);
    await model.start();
    await idle();
    final hold = api.holds['list'] = Completer<void>();
    model.loadMore();
    await idle();
    expect(await model.remove(model.items[2]), isNull);
    api.holds.remove('list');
    hold.complete();
    await idle();
    for (var asks = 0; model.canLoadMore && asks < 5; asks++) {
      model.loadMore();
      await idle();
    }
    expect(numbers(), [
      for (var i = 1; i <= 25; i++)
        if (i != 3) i,
    ]);
    expect(model.hasMore, isFalse);
  });

  test('the edit mode chooses rows, 全选 and 取消选择, and 删除 sends them in one call', () async {
    await model.start();
    await idle();
    model.setEditing(true);
    model.toggleChosen(model.items[0]);
    model.toggleChosen(model.items[3]);
    expect(model.chosen.length, 2);
    model.toggleChosen(model.items[3]);
    expect(model.chosen, {model.items[0].aid});
    model.toggleAll();
    expect(model.allChosen, isTrue);
    model.toggleAll();
    expect(model.chosen, isEmpty);
    model.toggleChosen(model.items[0]);
    model.toggleChosen(model.items[1]);
    model.clearChoice();
    expect(model.chosen, isEmpty);
    model.toggleChosen(model.items[0]);
    model.toggleChosen(model.items[1]);
    expect(await model.removeChosen(), isNull);
    expect(api.calls.last, 'remove 83000001,83000002');
    expect(model.editing, isFalse);
    expect(numbers().first, 3);
  });

  test('a failed 批量 删除 puts every row back in order and leaves the edit mode', () async {
    await model.start();
    await idle();
    model.setEditing(true);
    for (final index in [0, 1, 4]) {
      model.toggleChosen(model.items[index]);
    }
    api.failures['remove'] = const BiliError.http(502);
    final done = model.removeChosen();
    expect(numbers().take(3), [3, 4, 6]);
    expect(await done, requestFailureMessage(const BiliError.http(502)));
    expect(api.calls.last, 'remove 83000001,83000002,83000005');
    expect(numbers(), [for (var i = 1; i <= 20; i++) i]);
    expect(model.editing, isFalse);
    expect(model.chosen, isEmpty);
  });

  test('the chips and the sort don’t change in edit mode', () async {
    await model.start();
    await idle();
    model.setEditing(true);
    model.selectFilter(WatchLaterFilter.unfinished);
    model.toggleOrder();
    await idle();
    expect(api.calls.length, 1);
  });

  test('一键清除 sends its kind, then lists again; a failure says why and keeps the list', () async {
    api.items[0] = laterItem(1, progress: -1);
    await model.start();
    await idle();
    expect(await model.clear(WatchLaterClean.watched), isNull);
    await idle();
    expect(api.calls.sublist(1), ['clear watched', 'list all newest page=1']);
    expect(numbers().first, 2);

    api.failures['clear'] = const BiliError.http(502);
    expect(await model.clear(WatchLaterClean.invalid), isNotNull);
    await idle();
    expect(api.calls.last, 'clear invalid');
  });

  test('一键清除 refused with -101 turns the list to its login state', () async {
    await model.start();
    await idle();
    api.failures['clear'] = const BiliError.api(code: -101, message: '账号未登录');
    expect(await model.clear(WatchLaterClean.watched), isNull, reason: 'no toast');
    expect(model.needsLogin, isTrue);
    expect(model.items, isEmpty);
  });

  test('复制到 names the folder and the account, ends the edit mode and lists again', () async {
    await model.start();
    await idle();
    model.setEditing(true);
    model.toggleChosen(model.items[0]);
    model.toggleChosen(model.items[1]);
    expect(await model.sendChosen(testFolders.last, move: false), WatchLaterModel.copied);
    await idle();
    expect(api.calls.sublist(1), ['copy 83000001,83000002 to=9102 mid=77', 'list all newest page=1']);
    expect(model.editing, isFalse);
    expect(model.items.length, 20, reason: 'copying keeps them in 稍后再看');
  });

  test('移动到 takes them out of 稍后再看; a failure keeps the edit mode and the choice', () async {
    await model.start();
    await idle();
    model.setEditing(true);
    model.toggleChosen(model.items[0]);
    api.failures['moveToFolder'] = const BiliError.api(code: 11010, message: '收藏夹已满');
    expect(await model.sendChosen(testFolders.first, move: true), requestFailureMessage(api.failures['moveToFolder']!));
    expect(model.editing, isTrue);
    expect(model.chosen.length, 1);
    api.failures.clear();
    expect(await model.sendChosen(testFolders.first, move: true), WatchLaterModel.moved);
    await idle();
    expect(api.calls.where((call) => call.startsWith('move')).last, 'move 83000001 to=9101');
    expect(numbers().first, 2);
  });

  for (final move in [false, true]) {
    test('${move ? '移动到' : '复制到'} refused with -101 turns the list to its login state, with no toast', () async {
      await model.start();
      await idle();
      model.setEditing(true);
      model.toggleChosen(model.items[0]);
      api.failures[move ? 'moveToFolder' : 'copyToFolder'] = const BiliError.api(code: -101, message: '账号未登录');
      expect(await model.sendChosen(testFolders.last, move: move), isNull);
      expect(model.needsLogin, isTrue);
      expect(model.editing, isFalse);
      expect(model.items, isEmpty);
    });
  }

  test('移动到 counts as a removal: paging after it leaves no row behind', () async {
    api = FakeWatchLaterApi(items: laterItems(25), folderList: testFolders);
    model = WatchLaterModel(
      api: api,
      isLoggedIn: () => true,
      accountMid: () => 77,
      logger: Logger(session: 'test'),
    );
    addTearDown(model.dispose);
    await model.start();
    await idle();
    model.setEditing(true);
    model.toggleChosen(model.items[1]);
    model.toggleChosen(model.items[3]);
    api.failures['list'] = const BiliError.http(500);
    expect(await model.sendChosen(testFolders.first, move: true), WatchLaterModel.moved);
    expect(numbers(), isNot(contains(2)), reason: 'moved rows leave at once');
    await idle();
    api.failures.clear();
    for (var asks = 0; model.canLoadMore && asks < 5; asks++) {
      model.loadMore();
      await idle();
    }
    expect(numbers(), [
      for (var i = 1; i <= 25; i++)
        if (i != 2 && i != 4) i,
    ]);
  });

  test('a row opens at its progress; a finished one from the start', () {
    final route = WatchLaterModel.route(laterItem(1, progress: 95));
    expect(route.bvid, 'BV1test1');
    expect(route.cid, 142000001);
    expect(route.start, 95);
    expect(WatchLaterModel.route(laterItem(2, progress: -1)).start, 0);
  });

  test('the cover says watched / total, 已看完, or the length', () {
    expect(WatchLaterModel.progressLabel(laterItem(1, progress: 1, duration: 412)), '00:01 / 06:52');
    expect(WatchLaterModel.progressLabel(laterItem(1, progress: 3700, duration: 7322)), '01:01:40 / 02:02:02');
    expect(WatchLaterModel.progressLabel(laterItem(1, progress: -1)), '已看完');
    expect(WatchLaterModel.progressLabel(laterItem(1, progress: 0, duration: 90)), '01:30');
  });
}
