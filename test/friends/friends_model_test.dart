import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/friends/fake_friends_api.dart';
import 'package:bilifast/friends/friends_model.dart';
import 'package:bilifast/friends/friends_route.dart';
import 'package:bilifast/friends/group_sheet_model.dart';
import 'package:bilifast/space/follow_book.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'friends_support.dart' show friend, friends;

const _pause = Duration(milliseconds: 300);

final class _Harness {
  _Harness(this.api, {this.mid = 12345}) {
    model = FriendsModel(
      api: api,
      mid: () => mid,
      book: book,
      toast: toasts.add,
      requestLogin: () => logins++,
      searchPause: _pause,
      logger: Logger(session: 'test')..add(sink),
    );
  }

  final FakeFriendsApi api;
  int? mid;
  final book = FollowBook();
  final toasts = <String>[];
  final sink = MemorySink();
  int logins = 0;
  late final FriendsModel model;

}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('nothing is asked until the account is known; start then loads 关注, and 粉丝 only once shown', () async {
    final harness = _Harness(FakeFriendsApi(following: friends(3), fanList: [friend(9)]), mid: null);
    final model = harness.model..start();
    model.showFans();
    expect(harness.api.calls, isEmpty);

    harness.mid = 12345;
    model.start();
    await _settle();
    expect(harness.api.calls, ['followings recent page=1', 'fans page=1']);
    expect(model.following.total, 3);
    model.showFans();
    await _settle();
    expect(harness.api.calls, hasLength(2));
  });

  test('the order swaps and reloads; an answer for the old order is dropped', () async {
    final api = FakeFriendsApi(following: friends(3));
    final model = _Harness(api).model;
    final hold = api.holds['followings'] = Completer<void>();
    model.start();
    await _settle();
    expect(model.order, FollowingOrder.recent);

    api.holds.remove('followings');
    model.toggleOrder();
    expect(model.order, FollowingOrder.mostVisited);
    await _settle();
    hold.complete();
    await _settle();
    expect(api.calls, ['followings recent page=1', 'followings mostVisited page=1']);
    expect(model.following.users.map((user) => user.mid), [3, 2, 1]);
    expect(model.following.page, 1);

    model.toggleOrder();
    expect(model.order, FollowingOrder.recent);
  });

  test('the search waits for a pause, goes one at a time, and only the latest text goes next', () {
    fakeAsync((async) {
      final api = FakeFriendsApi(following: [friend(1, name: '甲一'), friend(2, name: '甲二'), friend(3, name: '乙')]);
      final harness = _Harness(api);
      final model = harness.model..start();
      async.flushMicrotasks();

      model.textChanged('甲');
      async.elapse(_pause ~/ 2);
      expect(model.searching, isFalse);
      async.elapse(_pause);
      expect(model.searching, isTrue);
      expect(model.lane(FriendsTab.following).users.map((user) => user.mid), [1, 2]);

      final hold = api.holds['searchFollowings'] = Completer<void>();
      model.textChanged('甲一');
      async.elapse(_pause);
      model.textChanged('乙');
      async.elapse(_pause);
      model.textChanged('甲二');
      async.elapse(_pause);
      expect(api.calls.where((call) => call.startsWith('search')), hasLength(2), reason: 'one out at a time');
      api.holds.remove('searchFollowings');
      hold.complete();
      async.flushMicrotasks();
      expect(api.calls.where((call) => call.startsWith('search')), hasLength(3));
      expect(model.lane(FriendsTab.following).users.map((user) => user.mid), [2]);

      model.textChanged('  ');
      expect(model.searching, isFalse);
      expect(model.lane(FriendsTab.following).users, hasLength(3));
      final words = [...api.calls, ...harness.sink.events.map((event) => event.encode())].join();
      expect(words, isNot(contains('甲')));
      expect(words, isNot(contains('乙')));
    });
  });

  test('关注 changes show at once, go to FollowBook when taken, and are taken back when refused', () async {
    final api = FakeFriendsApi(following: friends(2));
    final harness = _Harness(api);
    final model = harness.model..start();
    await _settle();
    final user = model.following.users.first;

    final hold = api.holds['follow'] = Completer<void>();
    unawaited(model.setFollowing(user, on: false));
    expect(model.isFollowing(user), isFalse);
    expect(model.isBusy(user), isTrue);
    unawaited(model.setFollowing(user, on: true));
    await _settle();
    expect(api.calls.where((call) => call.startsWith('follow ')), hasLength(1), reason: 'one call per person');
    api.holds.remove('follow');
    hold.complete();
    await _settle();
    expect(harness.book.following(user.mid), isFalse);
    expect(model.isFollowing(user), isFalse);
    expect(model.isBusy(user), isFalse);
    expect(harness.toasts, ['取消关注成功']);

    api.failures['follow'] = const BiliError.api(code: -500, message: '服务器开小差了');
    await model.setFollowing(user, on: true);
    expect(model.isFollowing(user), isFalse);
    expect(harness.toasts.last, '服务器开小差了');

    api.failures['follow'] = const BiliError.api(code: -101, message: '账号未登录');
    await model.setFollowing(user, on: true);
    expect(harness.logins, 1);
    expect(harness.toasts, hasLength(2));
  });

  test('the 分组 are asked once a page; a failure is asked again', () async {
    final api = FakeFriendsApi()..failures['tags'] = const BiliError.api(code: -500, message: '服务器开小差了');
    final model = _Harness(api).model;
    await expectLater(model.groups(), throwsA(isA<BiliError>()));
    api.failures.remove('tags');
    await model.groups();
    await model.groups();
    expect(api.calls, ['tags', 'tags']);
  });

  test('signing out empties every list and the next start begins again', () async {
    final api = FakeFriendsApi(following: friends(2), fanList: [friend(5)]);
    final model = _Harness(api).model
      ..start()
      ..showFans();
    await _settle();
    model.signOut();
    expect(model.following.loaded, isFalse);
    expect(model.fans.loaded, isFalse);
    model.start();
    await _settle();
    expect(api.calls.where((call) => call == 'fans page=1'), hasLength(2));
  });

  group('设置分组', () {
    GroupSheetModel sheet(FakeFriendsApi api) =>
        GroupSheetModel(api: api, mid: 7, groups: api.tags, logger: Logger(session: 'test'));

    test('lists the 分组 but 默认分组, ticked as Bilibili has them', () async {
      final api = FakeFriendsApi(
        groups: const [
          RelationTag(id: RelationTag.special, name: '特别关注'),
          RelationTag(id: RelationTag.defaultGroup, name: '默认分组'),
          RelationTag(id: 31, name: '测试分组'),
        ],
        memberships: {
          7: {31},
        },
      );
      final model = sheet(api);
      expect(model.groups, isNull);
      await model.load();
      expect(model.groups!.map((group) => group.id), [RelationTag.special, 31]);
      expect(model.chosen, {31});
      expect(model.toDefault, isFalse);
      expect(model.changed, isFalse);

      model.toggle(31);
      expect(model.toDefault, isTrue);
      expect(model.changed, isTrue);
      expect(await model.save(), isNull);
      expect(api.calls.last, 'setTags 7 ');
      expect(model.changed, isFalse);
    });

    test('saving unchanged sends nothing; a refused save says why and keeps the ticks', () async {
      final api = FakeFriendsApi();
      final model = sheet(api);
      await model.load();
      expect(await model.save(), isNull);
      expect(api.calls, ['tags', 'tagsOf 7']);

      model.toggle(RelationTag.special);
      api.failures['setTags'] = const BiliError.api(code: 22104, message: '分组已满');
      expect(await model.save(), '分组已满');
      expect(model.chosen, {RelationTag.special});
      expect(model.changed, isTrue);
      expect(model.saving, isFalse);
    });

    test('a failed load says why, and loads again', () async {
      final api = FakeFriendsApi()..failures['tagsOf'] = const BiliError.api(code: -500, message: '服务器开小差了');
      final model = sheet(api);
      await model.load();
      expect(model.groups, isNull);
      expect(model.error, isNotNull);
      api.failures.remove('tagsOf');
      await model.load();
      expect(model.error, isNull);
      expect(model.groups, isNotEmpty);
    });
  });
}
