import 'dart:io';

import 'package:bili_core/api.dart' show VideoCodec;
import 'package:bili_core/devlog.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:bilifast/video/player_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory folder;
  late String path;
  late MemorySink logs;
  late Logger logger;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('player_prefs_test');
    path = '${folder.path}${Platform.pathSeparator}player_prefs.json';
    logs = MemorySink();
    logger = Logger(session: 'test')..add(logs);
  });

  tearDown(() => folder.deleteSync(recursive: true));

  test('without a file the defaults apply: 自动连播 on, 不循环, 适应, BTR on, stats off, danmaku on', () async {
    final prefs = await PlayerPrefs.load(path, logger: logger);
    expect(prefs.autoplay, isTrue);
    expect(prefs.loop, LoopMode.off);
    expect(prefs.fit, FitMode.fit);
    expect(prefs.btr, isTrue);
    expect(prefs.showStats, isFalse);
    expect(prefs.danmakuOn, isTrue);
    expect(prefs.quality, isNull);
    expect(prefs.codec, isNull);
    expect(File(path).existsSync(), isFalse, reason: 'nothing is written until something changes');
  });

  test('what is set comes back on the next launch', () async {
    final prefs = await PlayerPrefs.load(path, logger: logger);
    prefs
      ..autoplay = false
      ..loop = LoopMode.single
      ..fit = FitMode.ratio4x3
      ..btr = false
      ..showStats = true
      ..danmakuOn = false
      ..quality = 127
      ..codec = VideoCodec.av1;
    await prefs.settle();

    final again = await PlayerPrefs.load(path, logger: logger);
    expect(again.autoplay, isFalse);
    expect(again.loop, LoopMode.single);
    expect(again.fit, FitMode.ratio4x3);
    expect(again.btr, isFalse);
    expect(again.showStats, isTrue);
    expect(again.danmakuOn, isFalse);
    expect(again.quality, 127);
    expect(again.codec, VideoCodec.av1);
  });

  test('a file that is not JSON is set aside and the defaults apply', () async {
    File(path).writeAsStringSync('{not json');
    final prefs = await PlayerPrefs.load(path, logger: logger);
    expect(prefs.loop, LoopMode.off);
    expect(File('$path.bad').existsSync(), isTrue);
    expect(logs.events.map((event) => event.msg), contains('player prefs unreadable, using defaults'));
    prefs.loop = LoopMode.list;
    await prefs.settle();
    expect((await PlayerPrefs.load(path, logger: logger)).loop, LoopMode.list);
  });

  test('a value of the wrong type or an unknown name falls back alone', () async {
    File(path).writeAsStringSync('{"autoplay":"yes","loop":"forever","fit":"fill","quality":"high","codec":"hevc"}');
    final prefs = await PlayerPrefs.load(path, logger: logger);
    expect(prefs.autoplay, isTrue);
    expect(prefs.loop, LoopMode.off);
    expect(prefs.fit, FitMode.fill);
    expect(prefs.quality, isNull);
    expect(prefs.codec, VideoCodec.hevc);
  });

  test('in memory nothing touches the disk', () async {
    final prefs = PlayerPrefs.memory(logger: logger)..autoplay = false;
    await prefs.settle();
    expect(prefs.autoplay, isFalse);
    expect(folder.listSync(), isEmpty);
  });
}
