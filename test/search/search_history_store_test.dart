import 'dart:convert';
import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/search/search_history_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every message and field value logged, as text.
List<String> logged(MemorySink logs) => [
  for (final event in logs.events) ...[event.msg, for (final value in event.f.values) '${value.toJson()}'],
];

void main() {
  late Directory folder;
  late String path;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('search_history');
    path = '${folder.path}${Platform.pathSeparator}search_history.json';
  });
  tearDown(() => folder.delete(recursive: true));

  Future<SearchHistoryStore> load([MemorySink? logs]) =>
      SearchHistoryStore.load(path, logger: Logger(session: 'test')..add(logs ?? MemorySink()));

  test('newest first, once each, trimmed, nothing for a blank word, and only the last 20', () async {
    final store = SearchHistoryStore.memory(logger: Logger(session: 'test'));
    var notified = 0;
    store.addListener(() => notified++);
    store
      ..add(' 猫 ')
      ..add('狗')
      ..add('猫')
      ..add('   ');
    expect(store.words, ['猫', '狗']);
    expect(notified, 3);
    store.add('猫');
    expect(notified, 3, reason: 'already first');
    for (var i = 0; i < 30; i++) {
      store.add('词$i');
    }
    expect(store.words, hasLength(SearchHistoryStore.limit));
    expect(store.words.first, '词29');
    expect(store.words.last, '词10');
  });

  test('one word removed, all cleared, and 搜索发现 hidden', () async {
    final store = SearchHistoryStore.memory(logger: Logger(session: 'test'))
      ..add('猫')
      ..add('狗')
      ..remove(' 猫');
    expect(store.words, ['狗']);
    store.clear();
    expect(store.words, isEmpty);
    expect(store.discoveryHidden, isFalse);
    store.setDiscoveryHidden(true);
    expect(store.discoveryHidden, isTrue);
  });

  test('kept across launches in its file, in the agreed shape', () async {
    final nested = '${folder.path}${Platform.pathSeparator}sub${Platform.pathSeparator}search_history.json';
    final store = await SearchHistoryStore.load(nested, logger: Logger(session: 'test'))
      ..add('猫')
      ..add('狗')
      ..setDiscoveryHidden(true);
    await store.settle();
    expect(jsonDecode(await File(nested).readAsString()), {
      'words': ['狗', '猫'],
      'discoveryHidden': true,
    });

    final again = await SearchHistoryStore.load(nested, logger: Logger(session: 'test'));
    expect(again.words, ['狗', '猫']);
    expect(again.discoveryHidden, isTrue);
    again
      ..remove('狗')
      ..setDiscoveryHidden(false);
    await again.settle();
    final third = await SearchHistoryStore.load(nested, logger: Logger(session: 'test'));
    expect(third.words, ['猫']);
    expect(third.discoveryHidden, isFalse);
    third.clear();
    await third.settle();
    expect((await SearchHistoryStore.load(nested, logger: Logger(session: 'test'))).words, isEmpty);
  });

  test('no file yet starts empty and writes nothing until something changes', () async {
    final store = await load();
    expect(store.words, isEmpty);
    expect(store.discoveryHidden, isFalse);
    await store.settle();
    expect(File(path).existsSync(), isFalse);
  });

  test('a file written by hand is tidied: words that are not text, blanks and repeats dropped, 20 kept', () async {
    await File(path).writeAsString(
      jsonEncode({
        'words': [' 猫 ', 3, null, '', '狗', '猫', for (var i = 0; i < 30; i++) '词$i'],
        'discoveryHidden': 'yes',
      }),
    );
    final store = await load();
    expect(store.words.take(3), ['猫', '狗', '词0']);
    expect(store.words, hasLength(SearchHistoryStore.limit));
    expect(store.discoveryHidden, isFalse);
    expect(File('$path.bad').existsSync(), isFalse);
  });

  group('an unreadable file is set aside as .bad and the history starts empty', () {
    for (final (what, text) in [
      ('not JSON', '{"words": ["秘密'),
      ('not an object', '["秘密"]'),
      ('words not a list', '{"words": "秘密"}'),
    ]) {
      test(what, () async {
        await File(path).writeAsString(text);
        final logs = MemorySink();
        final store = await load(logs);
        expect(store.words, isEmpty);
        expect(await File('$path.bad').readAsString(), text);
        expect(File(path).existsSync(), isFalse);
        expect(logs.events.single.msg, 'search history unreadable, starting empty');
        expect(logs.events.single.f['file']?.toJson(), 'search_history.json');
        expect(logged(logs).where((line) => line.contains('秘密')), isEmpty, reason: 'never what was searched');

        store.add('猫');
        await store.settle();
        expect(jsonDecode(await File(path).readAsString()), {
          'words': ['猫'],
          'discoveryHidden': false,
        });
      });
    }
  });

  test('a save that fails is logged and never reaches the caller', () async {
    final blocker = File('${folder.path}${Platform.pathSeparator}blocker');
    await blocker.writeAsString('');
    final logs = MemorySink();
    final store = await SearchHistoryStore.load(
      '${blocker.path}${Platform.pathSeparator}search_history.json',
      logger: Logger(session: 'test')..add(logs),
    );
    store.add('秘密');
    await store.settle();
    expect(store.words, ['秘密']);
    expect(logs.events.single.msg, 'search history not saved');
    expect(logged(logs).where((line) => line.contains('秘密')), isEmpty);
  });
}
