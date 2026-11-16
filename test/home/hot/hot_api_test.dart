import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bilifast/home/hot/hot_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'hot_support.dart';

void main() {
  test('the demo: 40 made-up videos in two pages, no cover to fetch, dates from minutes to weeks back', () async {
    final now = DateTime(2026, 11, 16, 12);
    final api = FakeHotApi.demo(now: now);
    final first = await api.page(1);
    final second = await api.page(2);
    expect(api.calls, ['page=1', 'page=2']);
    expect((first.videos.length, first.hasMore), (20, true));
    expect((second.videos.length, second.hasMore), (20, false));
    final all = [...first.videos, ...second.videos];
    expect(all.map((video) => video.card.bvid).toSet(), hasLength(40));
    expect(all.every((video) => video.card.cover.isEmpty && video.card.title.startsWith('演示')), isTrue);
    expect(all.map((video) => video.card.views).toSet().length, greaterThan(5));
    final ages = [for (final video in all) now.difference(video.published!)];
    expect(ages.any((age) => age < const Duration(hours: 1)), isTrue);
    expect(ages.any((age) => age > const Duration(days: 7)), isTrue);
  });

  test('a page past the end is empty and ends the list', () async {
    final page = await FakeHotApi(videos: hotVideos(5)).page(2);
    expect(page.videos, isEmpty);
    expect(page.hasMore, isFalse);
  });

  test('failures and holds by the call or for every page', () async {
    final api = FakeHotApi(videos: hotVideos(30))..failures['page=2'] = const BiliError.api(code: -1, message: 'x');
    await api.page(1);
    await expectLater(api.page(2), throwsA(isA<BiliError>()));
    final hold = api.holds['page'] = Completer<void>();
    var answered = false;
    unawaited(api.page(1).then((_) => answered = true));
    await pumpEventQueue();
    expect(answered, isFalse);
    hold.complete();
    await pumpEventQueue();
    expect(answered, isTrue);
  });
}
