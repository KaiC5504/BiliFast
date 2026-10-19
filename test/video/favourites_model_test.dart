import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/video/actions/actions_model.dart';
import 'package:bilifast/video/actions/favourites_model.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_video_actions.dart';

const _aid = 900000001;

FavFolder _folder(int id, {bool contains = false, bool isDefault = false, String? title}) =>
    FavFolder(id: id, title: title ?? '收藏夹$id', count: 3, isPrivate: false, contains: contains, isDefault: isDefault);

/// The account's three folders, the video in the default one.
List<FavFolder> _three() => [
  _folder(3001, contains: true, isDefault: true, title: '默认收藏夹'),
  _folder(3002),
  _folder(3003),
];

/// [FakePageApi] whose folder lists answer when the test says, each call its own answer.
class _QueuedFolders extends FakePageApi {
  final answers = <Completer<List<FavFolder>>>[];

  @override
  Future<List<FavFolder>> favouriteFolders({required int mid, required int aid}) {
    calls.add('favouriteFolders');
    final answer = Completer<List<FavFolder>>();
    answers.add(answer);
    return answer.future;
  }
}

void main() {
  late FakePageApi api;
  late FakeVideoActions actions;
  late MemorySink logs;
  late int logins;
  final models = <FavouritesModel>[];

  setUp(() {
    api = FakePageApi(folders: _three());
    actions = FakeVideoActions();
    logs = MemorySink();
    logins = 0;
  });

  tearDown(() {
    for (final model in models) {
      model.dispose();
    }
    models.clear();
    actions.dispose();
  });

  FavouritesModel make({int? mid = 10001, FakePageApi? on}) {
    final model = FavouritesModel(
      api: on ?? api,
      aid: _aid,
      mid: () => mid,
      actions: actions,
      requestLogin: () => logins += 1,
      logger: Logger(session: 'test')..add(logs),
    );
    models.add(model);
    return model;
  }

  List<int> ids(FavouritesModel model) => [for (final folder in model.folders) folder.id];

  List<String> logged() => [for (final event in logs.events) event.msg];

  test('loads at once, ticking the folders that hold the video', () async {
    final model = make();
    expect(model.loading, isTrue);
    expect(api.calls, ['favouriteFolders']);
    var notified = 0;
    model.addListener(() => notified += 1);
    await pumpEventQueue();
    expect(model.loading, isFalse);
    expect(model.error, isNull);
    expect(ids(model), [3001, 3002, 3003]);
    expect(model.isTicked(3001), isTrue);
    expect(model.isTicked(3002), isFalse);
    expect(notified, 1);
  });

  test('logged out it asks Bilibili nothing and asks for the login once', () async {
    final model = make(mid: null);
    await pumpEventQueue();
    expect(model.loading, isFalse);
    expect(model.error, '请先登录');
    expect(api.calls, isEmpty);
    expect(logins, 1);
  });

  test('a list Bilibili refuses for want of a login asks for the login', () async {
    api.failures['favouriteFolders'] = const BiliError.api(code: -101, message: '账号未登录');
    final model = make();
    await pumpEventQueue();
    expect(model.error, isNotNull);
    expect(logins, 1);
  });

  test('新建收藏夹 refused for want of a login asks for the login rather than toasting', () async {
    final model = make();
    await pumpEventQueue();
    api.failures['createFolder'] = const BiliError.api(code: -101, message: '账号未登录');
    expect(await model.create('新的', isPrivate: false), '');
    expect(logins, 1);
    expect(ids(model), [3001, 3002, 3003]);
  });

  test('a list that fails says why, and 重试 loads it', () async {
    api.failures['favouriteFolders'] = const BiliError.http(500);
    final model = make();
    await pumpEventQueue();
    expect(model.loading, isFalse);
    expect(model.error, '网络请求失败（HTTP 500）');
    expect(model.folders, isEmpty);
    expect(logged(), contains('favourite folders failed'));

    api.failures.remove('favouriteFolders');
    final reloading = model.reload();
    expect(model.loading, isTrue);
    expect(model.error, isNull);
    await reloading;
    expect(model.error, isNull);
    expect(ids(model), [3001, 3002, 3003]);
  });

  test('toggle flips a tick and notifies', () async {
    final model = make();
    await pumpEventQueue();
    var notified = 0;
    model.addListener(() => notified += 1);
    model.toggle(3002);
    expect(model.isTicked(3002), isTrue);
    model.toggle(3001);
    expect(model.isTicked(3001), isFalse);
    expect(notified, 2);
  });

  group('完成', () {
    test('sends only the difference, in list order', () async {
      final model = make();
      await pumpEventQueue();
      model.toggle(3003);
      model.toggle(3002);
      model.toggle(3001);
      expect(model.change.add, [3002, 3003]);
      expect(model.change.remove, [3001]);
      await model.commit();
      expect(actions.calls, ['applyFavourites add=3002,3003 remove=3001 inAny=true']);
    });

    test('nothing changed sends nothing', () async {
      final model = make();
      await pumpEventQueue();
      model.toggle(3002);
      model.toggle(3002);
      await model.commit();
      expect(actions.calls, isEmpty);
    });

    test('taking it out of every folder says it is in none', () async {
      final model = make();
      await pumpEventQueue();
      model.toggle(3001);
      await model.commit();
      expect(actions.calls, ['applyFavourites add= remove=3001 inAny=false']);
    });

    test('goes through the real actions: favourited stays while it is still in a folder', () async {
      final real = ActionsModel(
        api: api,
        detail: _detail(),
        relation: const VideoRelation(like: false, dislike: false, favorite: true, attention: false, coins: 0),
        isLoggedIn: () => true,
        accountMid: () => 10001,
        requestLogin: () {},
        toast: (_) {},
        logger: Logger(session: 'test'),
      );
      addTearDown(real.dispose);
      final model = real.openFolders();
      addTearDown(model.dispose);
      await pumpEventQueue();
      model.toggle(3001);
      model.toggle(3002);
      await model.commit();
      expect(api.calls.last, 'updateFavourites add=3002 remove=3001');
      expect(real.favorited, isTrue);
      expect(real.favCount, 3907);
    });

    test('still goes out when the sheet closes right after', () async {
      final model = make();
      await pumpEventQueue();
      model.toggle(3002);
      final committing = model.commit();
      model.dispose();
      models.remove(model);
      await committing;
      expect(actions.calls, ['applyFavourites add=3002 remove= inAny=true']);
    });
  });

  group('新建收藏夹', () {
    test('lists the new folder after the default one, ticked', () async {
      final model = make();
      await pumpEventQueue();
      var notified = 0;
      model.addListener(() => notified += 1);
      expect(await model.create('  新的收藏夹 ', isPrivate: true), isNull);
      expect(api.calls.last, 'createFolder title=新的收藏夹 private=true');
      expect(ids(model), [3001, 100, 3002, 3003]);
      expect(model.folders[1].isPrivate, isTrue);
      expect(model.isTicked(100), isTrue);
      expect(model.change.add, [100]);
      expect(notified, 1);
    });

    test('a refusal answers with the server\'s words and changes nothing', () async {
      final model = make();
      await pumpEventQueue();
      api.failures['createFolder'] = const BiliError.api(code: 11010, message: '收藏夹名称重复');
      expect(await model.create('默认收藏夹', isPrivate: false), '收藏夹名称重复');
      expect(ids(model), [3001, 3002, 3003]);
      expect(logged(), contains('create folder failed'));
    });

    test('an empty name makes nothing', () async {
      final model = make();
      await pumpEventQueue();
      expect(await model.create('   ', isPrivate: false), '请输入收藏夹名称');
      expect(api.calls, ['favouriteFolders']);
    });

    test('a second tap while one is being made makes no second folder', () async {
      final model = make();
      await pumpEventQueue();
      final hold = api.holds['createFolder'] = Completer<void>();
      final first = model.create('新的收藏夹', isPrivate: false);
      final second = model.create('新的收藏夹', isPrivate: false);
      hold.complete();
      expect(await first, isNull);
      expect(await second, isNull);
      expect(api.calls.where((call) => call.startsWith('createFolder')), hasLength(1));
      expect(ids(model), [3001, 100, 3002, 3003]);
    });

    test('a folder made before the list loads keeps its tick once it does', () async {
      api.failures['favouriteFolders'] = const BiliError.http(500);
      api.listsNewFolders = false;
      final model = make();
      await pumpEventQueue();
      expect(model.error, isNotNull);
      expect(await model.create('新建的收藏夹', isPrivate: false), isNull);
      expect(model.isTicked(100), isTrue);

      api.failures.remove('favouriteFolders');
      await model.reload();
      expect(model.error, isNull);
      expect(ids(model), [3001, 100, 3002, 3003], reason: 'the list had not caught up, so it goes after the default');
      expect(model.isTicked(3001), isTrue);
      expect(model.isTicked(100), isTrue);
      expect(model.change.add, [100]);
      expect(model.change.remove, isEmpty);
    });

    test('a list that has caught up keeps its own order and the new folder\'s tick', () async {
      final hold = api.holds['favouriteFolders'] = Completer<void>();
      final model = make();
      expect(await model.create('新建的收藏夹', isPrivate: false), isNull);
      hold.complete();
      await pumpEventQueue();
      expect(ids(model), [3001, 3002, 3003, 100]);
      expect(model.isTicked(100), isTrue);
      expect(model.change.add, [100]);
    });
  });

  test('a reload replaces an older load\'s answer, whichever lands last', () async {
    final queued = _QueuedFolders();
    final model = make(on: queued);
    final reloading = model.reload();
    queued.answers[1].complete([_folder(3002, contains: true)]);
    await reloading;
    queued.answers[0].completeError(const BiliError.http(500));
    await pumpEventQueue();
    expect(model.error, isNull);
    expect(model.loading, isFalse);
    expect(ids(model), [3002]);
    expect(model.isTicked(3002), isTrue);
  });

  test('an answer after the sheet closed changes nothing', () async {
    final queued = _QueuedFolders();
    final model = make(on: queued);
    model.dispose();
    models.remove(model);
    queued.answers[0].complete(_three());
    await pumpEventQueue();
    expect(model.folders, isEmpty);
    model.dispose();
  });
}

VideoDetail _detail() => const VideoDetail(
  bvid: 'BV1Dm4y1A7aa',
  aid: _aid,
  title: '演示',
  cover: '',
  pubdate: 0,
  duration: 200,
  desc: '',
  descParts: [],
  copyright: 1,
  owner: VideoOwner(mid: 42, name: '演示UP主', face: ''),
  stat: VideoStat(view: 37000, danmaku: 337, reply: 213, favorite: 3907, coin: 1210, share: 148, like: 9131),
  pages: [],
  season: null,
  staff: [],
  width: 1920,
  height: 1080,
  honor: null,
  redirectURL: null,
);
