import 'dart:convert';
import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/settings/font_store.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// The first bytes of a TrueType file, padded; the fake loader never parses it.
final trueType = Uint8List.fromList([0, 1, 0, 0, ...List.filled(60, 7)]);
final openType = Uint8List.fromList([...ascii.encode('OTTO'), ...List.filled(60, 3)]);

final class LoaderSpy {
  final loaded = <(String, int)>[];
  bool failing = false;

  Future<void> call(Uint8List bytes, String family) async {
    if (failing) throw StateError('engine refused');
    loaded.add((family, bytes.length));
  }
}

void main() {
  late Directory folder;
  late String path;
  late MemorySink logs;
  late Logger logger;
  late LoaderSpy loader;
  late List<FontStore> opened;

  String fonts(String file) => '${folder.path}${Platform.pathSeparator}fonts${Platform.pathSeparator}$file';

  setUp(() {
    folder = Directory.systemTemp.createTempSync('font_store_test');
    path = '${folder.path}${Platform.pathSeparator}font.json';
    logs = MemorySink();
    logger = Logger(session: 'test')..add(logs);
    loader = LoaderSpy();
    opened = [];
  });

  /// Loads the store as a launch does; tear-down waits for its writes, since Windows won't delete an open file.
  Future<FontStore> open([LoaderSpy? spy]) async {
    final store = await FontStore.load(path, loader: (spy ?? loader).call, logger: logger);
    opened.add(store);
    return store;
  }

  tearDown(() async {
    for (final store in opened) {
      await store.settle();
    }
    BiliFonts.family = BiliFonts.miSans;
    folder.deleteSync(recursive: true);
  });

  test('without a file: MiSans off the iPhone, nothing written', () async {
    final store = await open();
    expect(store.choice, FontChoice.miSans);
    expect(store.label, 'MiSans');
    expect(BiliFonts.family, BiliFonts.miSans);
    expect(BiliFonts.nudged, isTrue);
    expect(File(path).existsSync(), isFalse);
  });

  test('on the iPhone the default is the system font, as the official app', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final store = await open();
    expect(store.choice, FontChoice.system);
    expect(store.label, '系统字体');
    expect(BiliFonts.family, isNull);
    expect(BiliFonts.nudged, isFalse, reason: 'the MiSans nudges would push PingFang off the official layout');
  });

  test('a choice applies at once, tells listeners and comes back on the next launch', () async {
    final store = await open();
    var told = 0;
    store.addListener(() => told++);
    store.select(FontChoice.system);
    expect(BiliFonts.family, isNull);
    expect(told, 1);
    store.select(FontChoice.system);
    expect(told, 1, reason: 'the same choice again changes nothing');
    await store.settle();

    BiliFonts.family = BiliFonts.miSans;
    final again = await open();
    expect(again.choice, FontChoice.system);
    expect(BiliFonts.family, isNull);
  });

  test('imported is refused until a font has been imported', () async {
    final store = await open();
    store.select(FontChoice.imported);
    expect(store.choice, FontChoice.miSans);
  });

  test('an imported font is registered, copied, used, and loaded again on the next launch', () async {
    final store = await open();
    expect(await store.importFont('霞鹜文楷.TTF', trueType), ImportOutcome.imported);
    final imported = store.imported!;
    expect(imported.name, '霞鹜文楷');
    expect(imported.file, endsWith('.ttf'));
    expect(store.choice, FontChoice.imported);
    expect(store.label, '霞鹜文楷');
    expect(BiliFonts.family, imported.family);
    expect(BiliFonts.nudged, isFalse);
    expect(loader.loaded, [(imported.family, trueType.length)]);
    expect(File(fonts(imported.file)).readAsBytesSync(), trueType);
    await store.settle();

    BiliFonts.family = BiliFonts.miSans;
    final relaunch = LoaderSpy();
    final again = await open(relaunch);
    expect(again.choice, FontChoice.imported);
    expect(again.imported!.name, '霞鹜文楷');
    expect(relaunch.loaded, [(imported.family, trueType.length)]);
    expect(BiliFonts.family, imported.family);
  });

  test('a second import takes a new family and deletes the first copy', () async {
    final store = await open();
    await store.importFont('one.ttf', trueType);
    final first = store.imported!;
    await store.importFont('two.otf', openType);
    final second = store.imported!;
    expect(second.family, isNot(first.family), reason: 'the engine keeps a family once loaded');
    expect(second.name, 'two');
    expect(File(fonts(first.file)).existsSync(), isFalse);
    expect(File(fonts(second.file)).existsSync(), isTrue);
  });

  test('switching away keeps the imported font to switch back to', () async {
    final store = await open();
    await store.importFont('mine.ttf', trueType);
    store.select(FontChoice.miSans);
    expect(BiliFonts.family, BiliFonts.miSans);
    store.select(FontChoice.imported);
    expect(BiliFonts.family, store.imported!.family);
  });

  test('a file that is not a font is refused before the engine sees it', () async {
    final store = await open();
    final png = Uint8List.fromList([0x89, ...ascii.encode('PNG'), ...List.filled(40, 0)]);
    expect(await store.importFont('picture.ttf', png), ImportOutcome.notAFont);
    expect(await store.importFont('tiny.ttf', Uint8List.fromList([0, 1, 0, 0])), ImportOutcome.notAFont);
    expect(loader.loaded, isEmpty);
    expect(store.choice, FontChoice.miSans);
    expect(Directory('${folder.path}${Platform.pathSeparator}fonts').existsSync(), isFalse);
  });

  test('an import the engine refuses fails, logged, and leaves the font as it was', () async {
    final store = await open();
    loader.failing = true;
    expect(await store.importFont('broken.ttf', trueType), ImportOutcome.failed);
    expect(store.choice, FontChoice.miSans);
    expect(store.imported, isNull);
    expect(logs.events.map((event) => event.msg), contains('font not imported'));
  });

  test("an imported font whose copy is gone falls back to the default, logged", () async {
    final store = await open();
    await store.importFont('gone.ttf', trueType);
    await store.settle();
    File(fonts(store.imported!.file)).deleteSync();

    final again = await open();
    expect(again.choice, FontChoice.miSans);
    expect(again.imported, isNull);
    expect(BiliFonts.family, BiliFonts.miSans);
    expect(logs.events.map((event) => event.msg), contains('imported font not loaded'));
  });

  test('an unreadable file falls back to the default, logged without its text', () async {
    File(path).writeAsStringSync('{"font": secret');
    final store = await open();
    expect(store.choice, FontChoice.miSans);
    final warning = logs.events.singleWhere((event) => event.msg == 'font choice unreadable, using the default');
    expect('${warning.f}', isNot(contains('secret')));
  });

  test('the MiSans nudges apply only while MiSans is on', () {
    BiliFonts.family = BiliFonts.miSans;
    expect(BiliMetrics.hudLabelDrop, 4 / 3);
    expect(BiliMetrics.endCaptionDrop, 0.5);
    expect(BiliMetrics.endButtonTextDrop, 2);
    expect(BiliMetrics.sheetMetaSpacing, 0.6);
    expect(BiliMetrics.sheetCountTextDrop, 1);
    for (final other in [null, 'imported-1']) {
      BiliFonts.family = other;
      expect(
        [
          BiliMetrics.hudLabelDrop,
          BiliMetrics.endCaptionDrop,
          BiliMetrics.endButtonTextDrop,
          BiliMetrics.sheetMetaSpacing,
          BiliMetrics.sheetCountTextDrop,
        ],
        everyElement(0),
        reason: '$other',
      );
    }
  });
}
