import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory folder;
  late Logger logger;
  late MemorySink sink;

  String path(String name) => '${folder.path}${Platform.pathSeparator}$name';

  setUp(() {
    folder = Directory.systemTemp.createTempSync('old_font_files_test');
    logger = Logger(session: 'test');
    sink = MemorySink();
    logger.add(sink);
  });

  tearDown(() => folder.deleteSync(recursive: true));

  test("the old 字体 choice and the imported font's folder go; the other stores stay", () async {
    File(path('font.json')).writeAsStringSync('{"font":"imported"}');
    File(path('font.json.tmp')).writeAsStringSync('{}');
    File(path('fonts${Platform.pathSeparator}imported-1.ttf'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([0, 1, 0, 0]);
    File(path('player_prefs.json')).writeAsStringSync('{}');

    await removeOldFontFiles(path, logger: logger);

    expect(File(path('font.json')).existsSync(), isFalse);
    expect(File(path('font.json.tmp')).existsSync(), isFalse);
    expect(Directory(path('fonts')).existsSync(), isFalse);
    expect(File(path('player_prefs.json')).existsSync(), isTrue);
    expect(sink.events.where((event) => event.msg == 'old font files not removed'), isEmpty);
  });

  test('nothing left over, or no support folder, is fine', () async {
    await removeOldFontFiles(path, logger: logger);
    await removeOldFontFiles((_) => null, logger: logger);

    expect(folder.listSync(), isEmpty);
    expect(sink.events.where((event) => event.msg == 'old font files not removed'), isEmpty);
  });
}
