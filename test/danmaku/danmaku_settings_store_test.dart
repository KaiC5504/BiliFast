import 'dart:convert';
import 'dart:io';

import 'package:bili_core/danmaku.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/danmaku/danmaku_settings.dart';
import 'package:bilifast/danmaku/danmaku_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory folder;
  late String path;
  late MemorySink logs;
  late Logger logger;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('danmaku_settings_test');
    path = '${folder.path}${Platform.pathSeparator}danmaku_settings.json';
    logs = MemorySink();
    logger = Logger(session: 'test')..add(logs);
  });

  tearDown(() => folder.delete(recursive: true));

  Map<String, Object?> saved() => jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

  const changed = DanmakuSettings(
    area: 0.25,
    opacity: 0.7,
    scale: 1.5,
    speed: 4,
    filter: DanmakuFilterOptions(blockColored: true, dedupe: true),
  );

  test('no file yet: the defaults, nothing logged', () async {
    final store = await DanmakuSettingsStore.load(path, logger: logger);
    expect(store.value, const DanmakuSettings());
    expect(logs.events, isEmpty);
  });

  test('update shows at once, is saved and loads back', () async {
    final store = await DanmakuSettingsStore.load(path, logger: logger);
    var heard = 0;
    store.addListener(() => heard++);
    store.update(changed);
    expect(store.value, changed);
    expect(heard, 1);
    await store.settle();
    expect(saved(), changed.toJson());

    final again = await DanmakuSettingsStore.load(path, logger: logger);
    expect(again.value, changed);
  });

  test('a slider drag\'s updates are written together, the last one last', () async {
    final store = await DanmakuSettingsStore.load(path, logger: logger);
    for (var i = 1; i <= 20; i++) {
      store.update(store.value.copyWith(opacity: 0.2 + i * 0.04));
    }
    await store.settle();
    expect(saved()['opacity'], closeTo(1.0, 1e-9));
    expect(File('$path.tmp').existsSync(), isFalse);
  });

  test('a bad file gives the defaults, logged, and is set aside', () async {
    File(path).writeAsStringSync('{not json');
    final store = await DanmakuSettingsStore.load(path, logger: logger);
    expect(store.value, const DanmakuSettings());
    expect([for (final event in logs.events) event.msg], contains('danmaku settings unreadable, using defaults'));
    expect(File('$path.bad').existsSync(), isTrue);

    store.update(changed);
    await store.settle();
    expect(saved(), changed.toJson());
  });

  test('a file that isn\'t an object gives the defaults too', () async {
    File(path).writeAsStringSync('[1, 2]');
    final store = await DanmakuSettingsStore.load(path, logger: logger);
    expect(store.value, const DanmakuSettings());
    expect(logs.events, isNotEmpty);
  });

  test('reset goes back to the defaults and saves them', () async {
    final store = await DanmakuSettingsStore.load(path, logger: logger);
    store.update(changed);
    store.reset();
    expect(store.value, const DanmakuSettings());
    await store.settle();
    expect(saved(), const DanmakuSettings().toJson());
  });

  test('in memory: no file, values still change', () async {
    final store = DanmakuSettingsStore.memory();
    store.update(changed);
    expect(store.value, changed);
    await store.settle();
    final loaded = await DanmakuSettingsStore.load(null);
    expect(loaded.value, const DanmakuSettings());
    expect(File(path).existsSync(), isFalse);
  });
}
