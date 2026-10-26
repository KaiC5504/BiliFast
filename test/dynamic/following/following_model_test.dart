import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/dynamic/fake_dynamic_api.dart';
import 'package:bilifast/dynamic/following/following_model.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

FollowingUser _user(int mid, String name) => FollowingUser(mid: mid, name: name, face: '');

/// Names to search among: 'a' finds three, 'ab' two, 'abc' one.
final _named = [
  _user(1, 'abc'),
  _user(2, 'ab'),
  _user(3, 'a'),
  _user(4, 'xyz'),
  for (var i = 5; i <= 45; i++) _user(i, '关注$i'),
];

void main() {
  late MemorySink logs;

  setUp(() => logs = MemorySink());

  FollowingListModel make(FakeDynamicApi api, {int? Function()? mid}) => FollowingListModel(
    api: api,
    mid: mid ?? () => 12345,
    searchPause: const Duration(milliseconds: 300),
    logger: Logger(session: 'test')..add(logs),
  );

  List<String> searches(FakeDynamicApi api) => [
    for (final call in api.calls)
      if (call.startsWith('searchFollowings')) call,
  ];

  test('the first page in 推荐排序 and the dots from one ups call', () async {
    final api = FakeDynamicApi(
      following: _named,
      upList: const [
        DynamicUp(mid: 1, name: '', face: '', hasUpdate: true),
        DynamicUp(mid: 2, name: '', face: ''),
      ],
    );
    final model = make(api)..start();
    expect(model.list.firstLoading, isTrue);
    await pumpEventQueue();

    expect(api.calls, ['followings recommended page=1', 'ups offset=']);
    expect(model.list.users.length, 20);
    expect(model.list.hasMore, isTrue);
    expect(model.hasUpdate(1), isTrue);
    expect(model.hasUpdate(2), isFalse);
    expect(model.hasUpdate(3), isFalse);
  });

  test('pages on to the end, one page at a time, then stops', () async {
    final api = FakeDynamicApi(following: _named);
    final model = make(api)..start();
    await pumpEventQueue();
    api.holds['followings'] = Completer<void>();
    model
      ..loadMore()
      ..loadMore();
    expect(model.list.loading, isTrue);
    api.holds.remove('followings')!.complete();
    await pumpEventQueue();
    model.loadMore();
    await pumpEventQueue();
    model.loadMore();
    await pumpEventQueue();

    expect(api.calls.where((call) => call.startsWith('followings')), [
      'followings recommended page=1',
      'followings recommended page=2',
      'followings recommended page=3',
    ]);
    expect(model.list.users.length, 45);
    expect(model.list.hasMore, isFalse);
  });

  test('a page that adds nobody ends the list', () async {
    final api = _RepeatingApi(following: _named);
    final model = make(api)..start();
    await pumpEventQueue();
    model.loadMore();
    await pumpEventQueue();
    expect(model.list.users.length, 20);
    expect(model.list.hasMore, isFalse);
    model.loadMore();
    await pumpEventQueue();
    expect(api.calls.where((call) => call.startsWith('followings')).length, 2);
  });

  test('a new order starts over from page 1 and drops the old order’s answer', () async {
    final api = FakeDynamicApi(following: _named);
    final model = make(api)..start();
    await pumpEventQueue();
    final hold = api.holds['followings'] = Completer<void>();
    model.loadMore();
    model.setOrder(FollowingOrder.recent);
    expect(model.order, FollowingOrder.recent);
    expect(model.list.firstLoading, isTrue);
    hold.complete();
    api.holds.remove('followings');
    await pumpEventQueue();

    expect(api.calls.where((call) => call.startsWith('followings')), [
      'followings recommended page=1',
      'followings recommended page=2',
      'followings recent page=1',
    ]);
    // 最近关注 answers newest first: the fake reverses the list.
    expect(model.list.users.first.mid, 45);
    expect(model.list.users.length, 20);
    model.setOrder(FollowingOrder.recent);
    await pumpEventQueue();
    expect(api.calls.where((call) => call.startsWith('followings')).length, 3);
  });

  test('a failed first page says why, and retry asks again', () async {
    final api = FakeDynamicApi(following: _named)
      ..failures['followings'] = const BiliError.api(code: -500, message: '服务器错误');
    final model = make(api)..start();
    await pumpEventQueue();
    expect(model.list.loaded, isFalse);
    expect(model.list.error, isNotNull);
    expect(logs.events.single.msg, 'following list failed');

    api.failures.remove('followings');
    model.retry();
    await pumpEventQueue();
    expect(model.list.users.length, 20);
    expect(model.list.error, isNull);
  });

  test('nothing is asked until the mid is known; then the list, the dots and the text typed meanwhile', () {
    fakeAsync((async) {
      int? account;
      final api = FakeDynamicApi(following: _named);
      final model = make(api, mid: () => account)..start();
      model
        ..loadMore()
        ..retry()
        ..setOrder(FollowingOrder.recent)
        ..textChanged('ab');
      async.elapse(const Duration(milliseconds: 300));
      expect(api.calls, isEmpty);
      expect(model.list.firstLoading, isTrue, reason: 'the TV, waiting for the account');
      expect(model.searching, isFalse);

      account = 12345;
      model.start();
      async.flushMicrotasks();
      expect(api.calls, ['followings recent page=1', 'ups offset=', 'searchFollowings page=1']);
      expect(model.list.users.length, 20);
      expect([for (final user in model.results.users) user.name], ['abc', 'ab']);

      model.start();
      async.flushMicrotasks();
      expect(api.calls, hasLength(3), reason: 'started once');
    });
  });

  test('signing out empties the lists and drops an answer on its way; the next start asks page 1 again', () async {
    int? account = 12345;
    final api = FakeDynamicApi(
      following: _named,
      upList: const [DynamicUp(mid: 1, name: '', face: '', hasUpdate: true)],
    );
    final model = make(api, mid: () => account)..start();
    await pumpEventQueue();
    expect(model.hasUpdate(1), isTrue);

    final hold = api.holds['followings'] = Completer<void>();
    model.loadMore();
    account = null;
    model.signOut();
    expect(model.list.firstLoading, isTrue);
    expect(model.list.users, isEmpty);
    expect(model.hasUpdate(1), isFalse);
    api.holds.remove('followings');
    hold.complete();
    await pumpEventQueue();
    expect(model.list.users, isEmpty, reason: 'page 2 answered for the account that left');

    account = 12345;
    model.start();
    await pumpEventQueue();
    expect(api.calls.where((call) => call.startsWith('followings')), [
      'followings recommended page=1',
      'followings recommended page=2',
      'followings recommended page=1',
    ]);
    expect(model.list.users.length, 20);
    expect(model.hasUpdate(1), isTrue);
  });

  test('typing searches once it pauses', () {
    fakeAsync((async) {
      final api = FakeDynamicApi(following: _named);
      final model = make(api)..start();
      async.flushMicrotasks();
      model.textChanged('a');
      async.elapse(const Duration(milliseconds: 200));
      model.textChanged('ab');
      async.elapse(const Duration(milliseconds: 299));
      expect(searches(api), isEmpty);
      expect(model.searching, isFalse);

      async.elapse(const Duration(milliseconds: 1));
      expect(model.searching, isTrue);
      async.flushMicrotasks();
      expect(searches(api), ['searchFollowings page=1']);
      expect([for (final user in model.results.users) user.name], ['abc', 'ab']);
    });
  });

  test('one search call at a time: text typed meanwhile waits, the stale answer is dropped, only the latest goes', () {
    fakeAsync((async) {
      final api = FakeDynamicApi(following: _named);
      final model = make(api)..start();
      async.flushMicrotasks();
      final hold = api.holds['searchFollowings'] = Completer<void>();
      model.textChanged('a');
      async.elapse(const Duration(milliseconds: 300));
      expect(searches(api).length, 1);

      model.textChanged('ab');
      async.elapse(const Duration(milliseconds: 300));
      model.textChanged('abc');
      async.elapse(const Duration(milliseconds: 300));
      expect(searches(api).length, 1);

      api.holds.remove('searchFollowings');
      hold.complete();
      async.flushMicrotasks();
      expect(searches(api).length, 2);
      expect([for (final user in model.results.users) user.name], ['abc']);
    });
  });

  test('clearing the field shows the list again at once, and drops a search out', () {
    fakeAsync((async) {
      final api = FakeDynamicApi(following: _named);
      final model = make(api)..start();
      async.flushMicrotasks();
      final hold = api.holds['searchFollowings'] = Completer<void>();
      model.textChanged('a');
      async.elapse(const Duration(milliseconds: 300));
      expect(model.searching, isTrue);

      model.textChanged('');
      expect(model.searching, isFalse);
      expect(model.shown.users.length, 20);
      api.holds.remove('searchFollowings');
      hold.complete();
      async.flushMicrotasks();
      expect(model.searching, isFalse);
      expect(model.results.users, isEmpty);
      expect(api.calls.where((call) => call.startsWith('followings')).length, 1);
    });
  });

  test('a failed search never logs the text', () {
    fakeAsync((async) {
      final api = FakeDynamicApi(following: _named)
        ..failures['searchFollowings'] = const BiliError.api(code: -400, message: '请求错误');
      final model = make(api)..start();
      async.flushMicrotasks();
      model.textChanged('秘密的名字');
      async.elapse(const Duration(milliseconds: 300));
      async.flushMicrotasks();

      expect(model.results.error, isNotNull);
      expect(logs.events.single.msg, 'following search failed');
      final logged = [
        for (final event in logs.events) ...[event.msg, for (final value in event.f.values) '${value.toJson()}'],
      ];
      expect(logged.any((text) => text.contains('秘密')), isFalse);
    });
  });

  test('search results page on, one call at a time', () {
    fakeAsync((async) {
      final api = FakeDynamicApi(following: [for (var i = 1; i <= 30; i++) _user(i, '同名$i')]);
      final model = make(api)..start();
      async.flushMicrotasks();
      model.textChanged('同名');
      async.elapse(const Duration(milliseconds: 300));
      async.flushMicrotasks();
      expect(model.results.users.length, 20);

      final hold = api.holds['searchFollowings'] = Completer<void>();
      model
        ..loadMore()
        ..loadMore();
      expect(searches(api).length, 2);
      api.holds.remove('searchFollowings');
      hold.complete();
      async.flushMicrotasks();
      expect(model.results.users.length, 30);
      expect(model.results.hasMore, isFalse);
    });
  });

  test('the keyboard’s 搜索 goes without the pause', () {
    fakeAsync((async) {
      final api = FakeDynamicApi(following: _named);
      final model = make(api)..start();
      async.flushMicrotasks();
      model
        ..textChanged('xyz')
        ..submit();
      async.flushMicrotasks();
      expect(searches(api).length, 1);
      expect([for (final user in model.results.users) user.mid], [4]);
      async.elapse(const Duration(milliseconds: 300));
      expect(searches(api).length, 1);
    });
  });
}

/// Answers every page with the first page's people, as a list that shifted under the user would.
final class _RepeatingApi extends FakeDynamicApi {
  _RepeatingApi({super.following});

  @override
  Future<FollowingPage> followings(int mid, {required FollowingOrder order, required int page}) async {
    calls.add('followings ${order.name} page=$page');
    return FollowingPage(users: following.take(20).toList(), total: following.length, hasMore: true);
  }
}
