import 'dart:convert';
import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

RecentVideo video(String bvid, {int cid = 1, String title = '标题'}) =>
    RecentVideo(bvid: bvid, cid: cid, title: title, part: 'P', page: 1, pageCount: 1);

/// What JSONEncoder wrote for `[PlayerRoute]` in the Swift app: Int64 cids, escaped slashes, its own key order.
const swiftRecents =
    '[{"title":"【4K】城市夜景\\/延时","bvid":"BV1GJ411x7h7","pageCount":3,"part":"P2 夜","cid":137649199,"page":2},'
    '{"page":1,"cid":24601234567,"bvid":"BV1xx411c7mD","part":"","pageCount":1,"title":"单P"}]';

/// Every field value the logs carry, as text.
List<String> logged(MemorySink logs) => [
  for (final event in logs.events) ...[for (final value in event.f.values) '${value.toJson()}'],
];

void main() {
  late Directory folder;
  late String path;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('recents');
    path = '${folder.path}${Platform.pathSeparator}recents.json';
  });
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
    final nested = '${folder.path}${Platform.pathSeparator}sub${Platform.pathSeparator}recents.json';
    final store = await RecentStore.load(nested, logger: Logger(session: 'test'));
    store
      ..add(video('BV1'))
      ..add(video('BV2', cid: 9, title: '第二个'));
    await store.settle();
    final again = await RecentStore.load(nested, logger: Logger(session: 'test'));
    expect(again.items, store.items);
    expect(again.items.first.cid, 9);
    again.clear();
    await again.settle();
    expect((await RecentStore.load(nested, logger: Logger(session: 'test'))).items, isEmpty);
  });

  group('a damaged file', () {
    test('that is not JSON is set aside as .bad and the list starts empty, saved', () async {
      await File(path).writeAsString('{not json 秘密');
      final logs = MemorySink();
      final store = await RecentStore.load(path, logger: Logger(session: 'test')..add(logs));
      await store.settle();
      expect(store.items, isEmpty);
      expect(await File('$path.bad').readAsString(), '{not json 秘密');
      expect(await File(path).readAsString(), '[]', reason: 'so a later launch does not take the Swift list');
      final warning = logs.events.single;
      expect(warning.msg, 'recents unreadable, starting empty');
      expect(warning.f['file']?.toJson(), 'recents.json');
      expect(warning.f['bytes']?.toJson(), utf8.encode('{not json 秘密').length);
      expect(logged(logs).where((text) => text.contains('not json') || text.contains('秘密')), isEmpty,
          reason: 'never the content');
    });

    test('of the wrong shape: not a list is set aside; entries that are not videos are skipped', () async {
      for (final text in ['{"bvid":"BV1"}', '"BV1"', 'null']) {
        await File(path).writeAsString(text);
        final store = await RecentStore.load(path, logger: Logger(session: 'test'));
        await store.settle();
        expect(store.items, isEmpty, reason: text);
        expect(await File('$path.bad').readAsString(), text);
      }
      for (final text in ['[{"bvid":"BV1"}]', '[null]', '[{"bvid":"BV1","cid":"1","title":"t"}]', '[[]]']) {
        await File(path).writeAsString(text);
        final logs = MemorySink();
        final store = await RecentStore.load(path, logger: Logger(session: 'test')..add(logs));
        expect(store.items, isEmpty, reason: text);
        expect(logs.events.single.msg, 'recents entries skipped', reason: text);
        expect(logs.events.single.f['skipped']?.toJson(), 1, reason: text);
      }
    });

    test('keeps every entry that decodes, in order', () async {
      final good = [video('BV1', title: '第一'), video('BV2', cid: 2, title: '第二')];
      await File(path).writeAsString(jsonEncode([
        good[0].toJson(),
        {'bvid': 'BV3', 'title': '没有cid'},
        null,
        'BV4',
        good[1].toJson(),
      ]));
      final logs = MemorySink();
      final store = await RecentStore.load(path, logger: Logger(session: 'test')..add(logs));
      expect(store.items, good);
      final warning = logs.events.single;
      expect(warning.msg, 'recents entries skipped');
      expect({for (final MapEntry(:key, :value) in warning.f.entries) key: value.toJson()},
          {'file': 'recents.json', 'bytes': await File(path).length(), 'skipped': 3, 'kept': 2});
      expect(logged(logs).where((text) => text.contains('没有cid')), isEmpty);
    });
  });

  test('a write that fails is logged with the error, and the list stays in memory', () async {
    final sep = Platform.pathSeparator;
    await File('${folder.path}${sep}blocker').writeAsString('');
    final logs = MemorySink();
    final store = await RecentStore.load('${folder.path}${sep}blocker${sep}recents.json',
        logger: Logger(session: 'test')..add(logs));
    store
      ..add(video('BV1'))
      ..add(video('BV2', cid: 2));
    await store.settle();
    expect(store.items, hasLength(2));
    final failures = logs.events.where((event) => event.msg == 'recents not saved').toList();
    expect(failures, hasLength(2));
    for (final failure in failures) {
      expect(failure.f['file']?.toJson(), 'recents.json');
      expect('${failure.f['error']?.toJson()}', isNotEmpty);
    }
  });

  group('the Swift app\'s list', () {
    test('is carried over once when there is no file yet, and saved', () async {
      var reads = 0;
      Future<String?> reader() async {
        reads++;
        return swiftRecents;
      }

      final logs = MemorySink();
      final store = await RecentStore.load(path, logger: Logger(session: 'test')..add(logs), readSwift: reader);
      await store.settle();
      expect(reads, 1);
      expect([for (final item in store.items) item.toJson()], [
        {'bvid': 'BV1GJ411x7h7', 'cid': 137649199, 'title': '【4K】城市夜景/延时', 'part': 'P2 夜', 'page': 2, 'pageCount': 3},
        {'bvid': 'BV1xx411c7mD', 'cid': 24601234567, 'title': '单P', 'part': '', 'page': 1, 'pageCount': 1},
      ]);
      expect(logs.events.single.msg, 'recents carried over from the Swift app');
      expect(logged(logs).where((text) => text.contains('城市')), isEmpty);

      final again = await RecentStore.load(path, logger: Logger(session: 'test'), readSwift: reader);
      expect(reads, 1, reason: 'the saved file wins from then on');
      expect(again.items, store.items);
      expect(again.items.last.cid, 24601234567);
    });

    test('that is empty or missing leaves an empty file, so it is asked for only once', () async {
      for (final answer in [null, '[]']) {
        if (File(path).existsSync()) await File(path).delete();
        var reads = 0;
        Future<String?> reader() async {
          reads++;
          return answer;
        }

        final store = await RecentStore.load(path, logger: Logger(session: 'test'), readSwift: reader);
        await store.settle();
        expect(store.items, isEmpty);
        expect(await File(path).readAsString(), '[]');
        await RecentStore.load(path, logger: Logger(session: 'test'), readSwift: reader);
        expect(reads, 1, reason: '$answer');
      }
    });

    test('with bad entries keeps the rest; unreadable, it starts empty', () async {
      final mixed = '[${swiftRecents.substring(1, swiftRecents.length - 1)},{"bvid":"BV9"}]';
      final store = await RecentStore.load(path, logger: Logger(session: 'test'), readSwift: () async => mixed);
      expect(store.items.map((item) => item.bvid), ['BV1GJ411x7h7', 'BV1xx411c7mD']);
      await store.settle();
      await File(path).delete();

      final logs = MemorySink();
      final broken =
          await RecentStore.load(path, logger: Logger(session: 'test')..add(logs), readSwift: () async => '[{"秘密');
      await broken.settle();
      expect(broken.items, isEmpty);
      expect(logs.events.single.msg, 'Swift recents unreadable');
      expect(logged(logs).where((text) => text.contains('秘密')), isEmpty);
      expect(await File(path).readAsString(), '[]');
    });

    test('that could not be read is tried again on the next launch', () async {
      var reads = 0;
      Future<String?> failing() async {
        reads++;
        throw PlatformException(code: 'boom', message: 'details that stay out of the log');
      }

      final logs = MemorySink();
      final store = await RecentStore.load(path, logger: Logger(session: 'test')..add(logs), readSwift: failing);
      await store.settle();
      expect(store.items, isEmpty);
      expect(File(path).existsSync(), isFalse);
      expect(logs.events.single.msg, 'Swift recents not read');
      expect(logs.events.single.f['error']?.toJson(), 'PlatformException(boom)');
      final again = await RecentStore.load(path, logger: Logger(session: 'test'), readSwift: () async => swiftRecents);
      expect(reads, 1);
      expect(again.items, hasLength(2));
      // The import's save still runs, and Windows refuses to delete a folder with a file open in it.
      await again.settle();
    });

    test('is not asked for when the file exists or the list lives in memory only', () async {
      await File(path).writeAsString(jsonEncode([video('BV1').toJson()]));
      var reads = 0;
      Future<String?> reader() async {
        reads++;
        return swiftRecents;
      }

      expect((await RecentStore.load(path, logger: Logger(session: 'test'), readSwift: reader)).items, [video('BV1')]);
      expect((await RecentStore.load(null, logger: Logger(session: 'test'), readSwift: reader)).items, isEmpty);
      expect(reads, 0);
    });
  });

  test('an opened part is stamped with the time and keeps the progress it had', () async {
    var clock = DateTime.utc(2026, 10, 19, 10);
    final store = await RecentStore.load(null, logger: Logger(session: 'test'), now: () => clock);
    store.add(video('BV1'));
    expect(store.items.single.openedAt, clock.millisecondsSinceEpoch ~/ 1000);
    store.recordProgress(bvid: 'BV1', cid: 1, seconds: 42);
    store.recordProgress(bvid: 'BV9', cid: 1, seconds: 7);
    expect(store.items.single.progress, 42);
    clock = clock.add(const Duration(hours: 3));
    store.add(video('BV1'));
    expect(store.items.single.openedAt, clock.millisecondsSinceEpoch ~/ 1000);
    expect(store.items.single.progress, 42);
  });

  test('✕ removes just that part, and the file follows', () async {
    final store = await RecentStore.load(path, logger: Logger(session: 'test'));
    store
      ..add(video('BV1'))
      ..add(video('BV2'))
      ..add(video('BV1', cid: 2));
    var changes = 0;
    store.addListener(() => changes++);
    store.remove(video('BV1'));
    store.remove(video('BV3'));
    expect([for (final item in store.items) item.id], ['BV1#2', 'BV2#1']);
    expect(changes, 1, reason: 'removing what is not there changes nothing');
    await store.settle();
    final again = await RecentStore.load(path, logger: Logger(session: 'test'));
    expect([for (final item in again.items) item.id], ['BV1#2', 'BV2#1']);
  });

  test('cover, duration, time and progress survive a launch; older entries load without them', () async {
    final store = await RecentStore.load(path, logger: Logger(session: 'test'));
    store.add(
      const RecentVideo(
        bvid: 'BV1',
        cid: 1,
        title: '标题',
        part: '',
        page: 1,
        pageCount: 1,
        cover: 'https://i0.hdslb.com/bfs/archive/a.jpg',
        duration: 133,
      ),
    );
    store.recordProgress(bvid: 'BV1', cid: 1, seconds: 60);
    await store.settle();
    final item = (await RecentStore.load(path, logger: Logger(session: 'test'))).items.single;
    expect(item.cover, 'https://i0.hdslb.com/bfs/archive/a.jpg');
    expect(item.duration, 133);
    expect(item.openedAt, isNotNull);
    expect(item.progress, 60);

    final fresh = '${folder.path}${Platform.pathSeparator}fresh.json';
    final loaded = await RecentStore.load(fresh, logger: Logger(session: 'test'), readSwift: () async => swiftRecents);
    await loaded.settle();
    final old = loaded.items;
    expect(old.first.cover, isNull);
    expect(old.first.duration, 0);
    expect(old.first.openedAt, isNull);
  });
}
