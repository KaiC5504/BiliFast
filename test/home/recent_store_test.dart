import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:flutter_test/flutter_test.dart';

RecentVideo video(String bvid, {int cid = 1, String title = '标题'}) =>
    RecentVideo(bvid: bvid, cid: cid, title: title, part: 'P', page: 1, pageCount: 1);

void main() {
  late Directory folder;

  setUp(() async => folder = await Directory.systemTemp.createTemp('recents'));
  tearDown(() => folder.delete(recursive: true));

  test('newest first, an opened part moves to the top, and only the last 30 stay', () async {
    final store = await RecentStore.load(null, logger: Logger(session: 'test'));
    store
      ..add(video('BV1'))
      ..add(video('BV2'))
      ..add(video('BV1', title: '新标题'));
    expect([for (final item in store.items) item.bvid], ['BV1', 'BV2']);
    expect(store.items.first.title, '新标题');
    store.add(video('BV1', cid: 2));
    expect(store.items, hasLength(3), reason: 'another part of the same video is its own entry');
    for (var index = 0; index < 40; index++) {
      store.add(video('BVx$index'));
    }
    expect(store.items, hasLength(RecentStore.limit));
    expect(store.items.first.bvid, 'BVx39');
  });

  test('kept across launches in the support file, and cleared from it', () async {
    final path = '${folder.path}${Platform.pathSeparator}sub${Platform.pathSeparator}recents.json';
    final store = await RecentStore.load(path, logger: Logger(session: 'test'));
    store
      ..add(video('BV1'))
      ..add(video('BV2', cid: 9, title: '第二个'));
    await store.settle();
    final again = await RecentStore.load(path, logger: Logger(session: 'test'));
    expect(again.items, store.items);
    expect(again.items.first.cid, 9);
    again.clear();
    await again.settle();
    expect((await RecentStore.load(path, logger: Logger(session: 'test'))).items, isEmpty);
  });

  test('an unreadable file starts empty rather than failing the launch', () async {
    final path = '${folder.path}${Platform.pathSeparator}recents.json';
    await File(path).writeAsString('{not json');
    final logs = MemorySink();
    final store = await RecentStore.load(path, logger: Logger(session: 'test')..add(logs));
    expect(store.items, isEmpty);
    expect(logs.events.single.msg, 'recents unreadable, starting empty');
  });
}
