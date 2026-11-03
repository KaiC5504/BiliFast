import 'dart:convert';
import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/sideload/sideload_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory folder;
  late String path;
  late MemorySink logs;
  late Logger logger;
  late List<SideloadStore> opened;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('sideload_store_test');
    path = '${folder.path}${Platform.pathSeparator}sideload.json';
    logs = MemorySink();
    logger = Logger(session: 'test')..add(logs);
    opened = [];
  });

  /// Loads the store as a launch does; tear-down waits for its writes, since Windows won't delete an open file.
  Future<SideloadStore> open() async {
    final store = SideloadStore.file(path, logger: logger);
    opened.add(store);
    await store.load();
    return store;
  }

  tearDown(() async {
    for (final store in opened) {
      await store.settle();
    }
    folder.deleteSync(recursive: true);
  });

  test('without a file: unanswered, off, nothing announced or warned, nothing written', () async {
    final store = await open();
    expect(store.reminderAnswered, isFalse);
    expect(store.reminderOn, isFalse);
    expect(store.announced, isNull);
    expect(store.warnedOn, isNull);
    expect(File(path).existsSync(), isFalse);
  });

  test('every answer survives a relaunch', () async {
    final first = await open();
    first
      ..reminderAnswered = true
      ..reminderOn = true
      ..announced = '1.3.0-8'
      ..warnedOn = '2026-11-04';
    await first.settle();
    expect(jsonDecode(File(path).readAsStringSync()), {
      'reminderAnswered': true,
      'reminderOn': true,
      'announced': '1.3.0-8',
      'warnedOn': '2026-11-04',
    });

    final second = await open();
    expect(second.reminderAnswered, isTrue);
    expect(second.reminderOn, isTrue);
    expect(second.announced, '1.3.0-8');
    expect(second.warnedOn, '2026-11-04');

    second.reminderOn = false;
    await second.settle();
    expect((await open()).reminderOn, isFalse);
  });

  test('an unreadable file starts unanswered, logged without its text, and the next answer replaces it', () async {
    File(path).writeAsStringSync('{"reminderAnswered": tru');
    final store = await open();
    expect(store.reminderAnswered, isFalse);
    expect(logs.events.single.msg, 'sideload answers unreadable, starting unanswered');
    expect(logs.events.single.encode(), isNot(contains('tru')));

    store.reminderAnswered = true;
    await store.settle();
    expect((await open()).reminderAnswered, isTrue);
  });

  test('fields of the wrong type read as unanswered', () async {
    File(path).writeAsStringSync('{"reminderAnswered": "yes", "reminderOn": 1, "announced": 8, "warnedOn": false}');
    final store = await open();
    expect(store.reminderAnswered, isFalse);
    expect(store.reminderOn, isFalse);
    expect(store.announced, isNull);
    expect(store.warnedOn, isNull);
  });

  test('load reads the file once', () async {
    final store = await open();
    File(path).writeAsStringSync('{"reminderAnswered": true}');
    await store.load();
    expect(store.reminderAnswered, isFalse);
  });

  test('in memory nothing touches the disk', () async {
    final store = SideloadStore.memory(logger: logger);
    await store.load();
    store.reminderOn = true;
    await store.settle();
    expect(store.reminderOn, isTrue);
    expect(folder.listSync(), isEmpty);
  });
}
