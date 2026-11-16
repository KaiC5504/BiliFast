import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/home/hot/hot_api.dart';
import 'package:bilifast/home/hot/hot_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'hot_support.dart';

void main() {
  late FakeHotApi api;
  late HotModel model;

  HotModel make(FakeHotApi fake) {
    api = fake;
    final made = HotModel(
      api: fake,
      logger: Logger(session: 'test'),
    );
    addTearDown(made.dispose);
    return made;
  }

  List<String> shown() => [for (final video in model.videos) video.card.bvid];

  setUp(() => model = make(FakeHotApi(videos: hotVideos(50))));

  test('starts once, with the first page', () async {
    expect(model.started, isFalse);
    model.start();
    model.start();
    expect(model.loadingFirst, isTrue);
    await pumpEventQueue();
    expect(api.calls, ['page=1']);
    expect(model.videos, hasLength(20));
    expect(model.loadingFirst, isFalse);
  });

  test('pages on to the end, and asks nothing past it', () async {
    model.start();
    await pumpEventQueue();
    await model.loadMore();
    await model.loadMore();
    expect(api.calls, ['page=1', 'page=2', 'page=3']);
    expect(model.videos, hasLength(50));
    expect(model.exhausted, isTrue);
    await model.loadMore();
    expect(api.calls, hasLength(3));
  });

  test('one call out at a time: a second ask while a page is out asks nothing', () async {
    model.start();
    await pumpEventQueue();
    final hold = api.holds['page=2'] = Completer<void>();
    final first = model.loadMore();
    final second = model.loadMore();
    expect(model.loadingMore, isTrue);
    hold.complete();
    await Future.wait([first, second]);
    expect(api.calls, ['page=1', 'page=2']);
  });

  test('a video a later page repeats shows once; a page that adds nothing ends the list', () async {
    model = make(FakeHotApi(videos: [...hotVideos(20), ...hotVideos(20)]));
    model.start();
    await pumpEventQueue();
    await model.loadMore();
    expect(model.videos, hasLength(20));
    expect(model.exhausted, isTrue);
    await model.loadMore();
    expect(api.calls, ['page=1', 'page=2']);
  });

  test('a failed first page says why and waits for 重试, which asks it again', () async {
    api.failures['page'] = const BiliError.api(code: -500, message: '服务器错误');
    model.start();
    await pumpEventQueue();
    expect(model.error, 'B 站返回错误 -500：服务器错误');
    expect(model.canLoadMore, isFalse);
    api.failures.clear();
    await model.retry();
    expect(api.calls, ['page=1', 'page=1']);
    expect(model.error, isNull);
    expect(model.videos, hasLength(20));
  });

  test('a failed next page keeps the rows, stops paging, and 重试 asks that page again', () async {
    model.start();
    await pumpEventQueue();
    api.failures['page=2'] = const BiliError.api(code: -412, message: '请求被拦截');
    await model.loadMore();
    expect(model.error, isNotNull);
    expect(model.videos, hasLength(20));
    await model.loadMore();
    expect(api.calls, ['page=1', 'page=2'], reason: 'no loop against the website');
    api.failures.clear();
    await model.retry();
    expect(api.calls, ['page=1', 'page=2', 'page=2']);
    expect(model.videos, hasLength(40));
  });

  test('a refresh puts page 1 in place of every page', () async {
    model.start();
    await pumpEventQueue();
    await model.loadMore();
    expect(model.videos, hasLength(40));
    expect(await model.refresh(), isNull);
    expect(api.calls, ['page=1', 'page=2', 'page=1']);
    expect(shown(), [for (var i = 0; i < 20; i++) 'BV1hot$i']);
    await model.loadMore();
    expect(api.calls.last, 'page=2', reason: 'paging starts again from the top');
  });

  test('a refresh with rows shown that fails keeps them and gives back why, for a toast', () async {
    model.start();
    await pumpEventQueue();
    api.failures['page'] = const BiliError.api(code: -500, message: '服务器错误');
    expect(await model.refresh(), 'B 站返回错误 -500：服务器错误');
    expect(model.videos, hasLength(20));
    expect(model.error, isNull);
  });

  test('a refresh while the next page is out waits for it and drops its answer, still one call at a time', () async {
    model.start();
    await pumpEventQueue();
    final hold = api.holds['page=2'] = Completer<void>();
    final more = model.loadMore();
    final refresh = model.refresh();
    await pumpEventQueue();
    expect(api.calls, ['page=1', 'page=2']);
    hold.complete();
    await more;
    await refresh;
    expect(api.calls, ['page=1', 'page=2', 'page=1']);
    expect(model.videos, hasLength(20), reason: "page 2's answer dropped");
  });

  test('a refresh while the first page is out joins it', () async {
    final hold = api.holds['page'] = Completer<void>();
    model.start();
    final refresh = model.refresh();
    hold.complete();
    await refresh;
    expect(api.calls, ['page=1']);
    expect(model.videos, hasLength(20));
  });

  test('a refresh asked twice is one call', () async {
    model.start();
    await pumpEventQueue();
    final hold = api.holds['page'] = Completer<void>();
    final first = model.refresh();
    expect(identical(model.refresh(), first), isTrue);
    expect(model.refreshing, isTrue);
    hold.complete();
    await first;
    expect(api.calls, ['page=1', 'page=1']);
    expect(model.refreshing, isFalse);
  });

  test('an empty first page ends the list at once', () async {
    model = make(FakeHotApi());
    model.start();
    await pumpEventQueue();
    expect(model.videos, isEmpty);
    expect(model.exhausted, isTrue);
  });
}
