import 'dart:convert';
import 'dart:io';

import 'package:bili_core/api.dart' show VideoCodec;
import 'package:bili_core/devlog.dart';
import 'package:bilifast/device/turn_style.dart';
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

  test('without a file the defaults apply: 自动连播 on, 不循环, 适应, BTR on, stats off, danmaku on, 旋转动画 '
      '移除·直接切·立即', () async {
    final prefs = await PlayerPrefs.load(path, logger: logger);
    expect(prefs.autoplay, isTrue);
    expect(prefs.loop, LoopMode.off);
    expect(prefs.fit, FitMode.fit);
    expect(prefs.btr, isTrue);
    expect(prefs.showStats, isFalse);
    expect(prefs.danmakuOn, isTrue);
    expect(prefs.coinAlsoLike, isTrue);
    expect(prefs.turnStyle, const TurnStyle());
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
      ..coinAlsoLike = false
      ..turnStyle = const TurnStyle(
          method: TurnMethod.counter, picture: TurnPicture.fade, spinStart: TurnSpinStart.afterPicture)
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
    expect(again.coinAlsoLike, isFalse);
    expect(again.turnStyle,
        const TurnStyle(method: TurnMethod.counter, picture: TurnPicture.fade, spinStart: TurnSpinStart.afterPicture));
    expect(again.quality, 127);
    expect(again.codec, VideoCodec.av1);
  });

  test('旋转动画 put back on the default stays there, and only what differs from it is written', () async {
    final prefs = await PlayerPrefs.load(path, logger: logger)..turnStyle = TurnStyle.system;
    await prefs.settle();
    expect(jsonDecode(File(path).readAsStringSync()), containsPair('turnMethod', 'system'));
    prefs.turnStyle = const TurnStyle(picture: TurnPicture.none);
    await prefs.settle();
    final written = jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
    expect(written['turnPicture'], 'none');
    expect(written.keys, isNot(contains('turnMethod')));
    expect(written.keys, isNot(contains('turnSpinStart')));
    prefs.turnStyle = const TurnStyle();
    await prefs.settle();
    final cleared = jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
    expect(cleared.keys.where((key) => key.startsWith('turn')), isEmpty);
    expect((await PlayerPrefs.load(path, logger: logger)).turnStyle, const TurnStyle());
  });

  group('the 1.0.0 (12) 旋转动画 bool', () {
    for (final (json, style, name) in [
      ('{"turnTakeover":false}', TurnStyle.system, '系统'),
      ('{"turnTakeover":true}', const TurnStyle(), '自绘, the default'),
      ('{}', const TurnStyle(), 'absent, the default'),
    ]) {
      test('$json reads as $name', () async {
        File(path).writeAsStringSync(json);
        expect((await PlayerPrefs.load(path, logger: logger)).turnStyle, style);
      });
    }

    test('the new keys win over it, and the next write drops it', () async {
      File(path).writeAsStringSync('{"turnTakeover":false,"turnMethod":"counter"}');
      final prefs = await PlayerPrefs.load(path, logger: logger);
      expect(prefs.turnStyle, const TurnStyle(method: TurnMethod.counter));
      prefs.autoplay = false;
      await prefs.settle();
      final written = jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
      expect(written.keys, isNot(contains('turnTakeover')));
      expect(written['turnMethod'], 'counter');
    });

    test('系统 carries over to the next launch as the method', () async {
      File(path).writeAsStringSync('{"turnTakeover":false}');
      final prefs = await PlayerPrefs.load(path, logger: logger)..autoplay = false;
      await prefs.settle();
      expect(jsonDecode(File(path).readAsStringSync()), containsPair('turnMethod', 'system'));
      expect((await PlayerPrefs.load(path, logger: logger)).turnStyle, TurnStyle.system);
    });
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
    File(path).writeAsStringSync(
        '{"autoplay":"yes","loop":"forever","fit":"fill","quality":"high","codec":"hevc","turnTakeover":0,'
        '"turnMethod":"spin","turnPicture":3,"turnSpinStart":"afterPicture"}');
    final prefs = await PlayerPrefs.load(path, logger: logger);
    expect(prefs.autoplay, isTrue);
    expect(prefs.loop, LoopMode.off);
    expect(prefs.fit, FitMode.fill);
    expect(prefs.quality, isNull);
    expect(prefs.codec, VideoCodec.hevc);
    expect(prefs.turnStyle, const TurnStyle(spinStart: TurnSpinStart.afterPicture));
    final ignored = logs.events.where((event) => event.msg == 'player prefs value ignored').toList();
    expect(ignored.map((event) => event.f['key']), const [
      LogString('autoplay'),
      LogString('loop'),
      LogString('turnTakeover'),
      LogString('turnMethod'),
      LogString('turnPicture'),
      LogString('quality'),
    ]);
    expect(ignored.every((event) => event.level == LogLevel.warn), isTrue);
    expect(ignored.map((event) => event.f.keys.toList()), everyElement(['key']), reason: 'never the value');
  });

  test('in memory nothing touches the disk', () async {
    final prefs = PlayerPrefs.memory(logger: logger)..autoplay = false;
    await prefs.settle();
    expect(prefs.autoplay, isFalse);
    expect(folder.listSync(), isEmpty);
  });
}
