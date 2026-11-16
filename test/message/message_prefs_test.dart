import 'dart:convert';
import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/message/message_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory folder;
  late String path;
  late MemorySink sink;
  late Logger logger;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('message_prefs');
    path = '${folder.path}${Platform.pathSeparator}message_prefs.json';
    sink = MemorySink();
    logger = Logger(session: 'test')..add(sink);
  });

  tearDown(() => folder.deleteSync(recursive: true));

  String logged() => sink.events.map((event) => '${event.toJson()}').join();

  test('消息提醒 starts on, with no file and in memory', () async {
    expect(MessagePrefs.memory().badgeOn, isTrue);
    expect((await MessagePrefs.load(path, logger: logger)).badgeOn, isTrue);
    expect((await MessagePrefs.load(null, logger: logger)).badgeOn, isTrue);
    expect(File(path).existsSync(), isFalse, reason: 'nothing is written until it changes');
  });

  test('turned off, it is off on the next launch; on again, on', () async {
    final prefs = await MessagePrefs.load(path, logger: logger);
    prefs.badgeOn = false;
    await prefs.settle();
    expect(jsonDecode(File(path).readAsStringSync()), {'badgeOn': false});
    expect(File('$path.tmp').existsSync(), isFalse, reason: 'written beside it, then renamed over it');
    expect((await MessagePrefs.load(path, logger: logger)).badgeOn, isFalse);

    prefs.badgeOn = true;
    await prefs.settle();
    expect((await MessagePrefs.load(path, logger: logger)).badgeOn, isTrue);
  });

  test('the same value again writes nothing', () async {
    final prefs = await MessagePrefs.load(path, logger: logger);
    prefs.badgeOn = true;
    await prefs.settle();
    expect(File(path).existsSync(), isFalse);
  });

  test('an unreadable file is set aside as .bad and 消息提醒 is on, its text never logged', () async {
    File(path).writeAsStringSync('{"badgeOn": fals');
    final prefs = await MessagePrefs.load(path, logger: logger);
    expect(prefs.badgeOn, isTrue);
    expect(File('$path.bad').existsSync(), isTrue);
    expect(File(path).existsSync(), isFalse);
    expect(logged(), contains('message prefs unreadable'));
    expect(logged(), isNot(contains('fals')));
  });

  test('a value of the wrong type falls back to on, logged by its key', () async {
    File(path).writeAsStringSync('{"badgeOn": "off"}');
    final prefs = await MessagePrefs.load(path, logger: logger);
    expect(prefs.badgeOn, isTrue);
    expect(logged(), contains('message prefs value ignored'));
    expect(logged(), contains('badgeOn'));
    expect(logged(), isNot(contains('"off"')));
  });

  test('in memory it changes and writes nothing', () async {
    final prefs = MessagePrefs.memory(badgeOn: false);
    expect(prefs.badgeOn, isFalse);
    prefs.badgeOn = true;
    await prefs.settle();
    expect(prefs.badgeOn, isTrue);
    expect(folder.listSync(), isEmpty);
  });
}
