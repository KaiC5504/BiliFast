import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/playback/codec_memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory folder;
  late String path;
  late Logger logger;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('codec_memory');
    path = '${folder.path}${Platform.pathSeparator}codec_memory.json';
    logger = Logger(session: 'test');
  });

  tearDown(() => folder.delete(recursive: true));

  test('no file remembers nothing', () async {
    final memory = await CodecMemory.load(path, logger: logger);
    expect(memory.failedKinds, isEmpty);
    expect(memory.hev1LabelsHoldHEV1, isFalse);
    expect(File(path).existsSync(), isFalse);
  });

  test('a refused codec and the hev1 note are saved and read back by the next start', () async {
    final memory = await CodecMemory.load(path, logger: logger);
    memory
      ..markFailed('av1')
      ..markFailed('hevc')
      ..noteHEV1Entry();
    await memory.settle();
    final read = await CodecMemory.load(path, logger: logger);
    expect(read.failedKinds, {'av1', 'hevc'});
    expect(read.hev1LabelsHoldHEV1, isTrue);
    expect(read.order(preferred: VideoCodec.hevc), [VideoCodec.avc]);
  });

  test('a reset is saved too', () async {
    final memory = await CodecMemory.load(path, logger: logger);
    memory
      ..markFailed('av1')
      ..noteHEV1Entry()
      ..reset();
    await memory.settle();
    final read = await CodecMemory.load(path, logger: logger);
    expect(read.failedKinds, isEmpty);
    expect(read.hev1LabelsHoldHEV1, isFalse);
  });

  test('an unreadable file is set aside as .bad and nothing is remembered', () async {
    await File(path).writeAsString('{not json');
    final memory = await CodecMemory.load(path, logger: logger);
    expect(memory.failedKinds, isEmpty);
    expect(File(path).existsSync(), isFalse);
    expect(File('$path.bad').readAsStringSync(), '{not json');
    memory.markFailed('av1');
    await memory.settle();
    expect((await CodecMemory.load(path, logger: logger)).failedKinds, {'av1'});
  });

  test('entries of the wrong type are dropped', () async {
    await File(path).writeAsString('{"failedCodecs":["av1",3,null],"hev1LabelsHoldHEV1":"yes"}');
    final memory = await CodecMemory.load(path, logger: logger);
    expect(memory.failedKinds, {'av1'});
    expect(memory.hev1LabelsHoldHEV1, isFalse);
  });

  test('without a path it stays in memory', () async {
    final memory = await CodecMemory.load(null, logger: logger)
      ..markFailed('av1');
    await memory.settle();
    expect(memory.failedKinds, {'av1'});
    expect(folder.listSync(), isEmpty);
  });
}
