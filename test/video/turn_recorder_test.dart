import 'dart:math';
import 'dart:ui';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/video/turn_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const t0 = 1760000000000000;
  late int nowUs;
  late MemorySink logs;
  late TurnRecorder recorder;

  setUp(() {
    nowUs = t0;
    logs = MemorySink();
    recorder = TurnRecorder(
      logger: Logger(session: 'test')..add(logs),
      now: () => DateTime.fromMicrosecondsSinceEpoch(nowUs),
    );
  });

  List<Map<String, Object>> lines() => [
        for (final event in logs.events)
          {'msg': event.msg, ...event.f.map((key, value) => MapEntry(key, value.toJson()))},
      ];

  test('each event is logged at once as turn <kind>, category ui, with the wall clock', () {
    recorder.presentation(Presentation.inline, Presentation.landscape, wide: false, waiting: true, drawn: true);
    nowUs = t0 + 1500;
    recorder.started((id: 3, angle: pi / 2, duration: const Duration(milliseconds: 300)), outcome: 'pending');
    recorder.sized(const Size(956, 440), layout: Presentation.landscape);
    recorder.began(3, spinFrom: -pi / 2, duration: const Duration(microseconds: 300500), grow: 0);
    recorder.drawnSent(3);
    recorder.late(missed: true);

    expect(logs.events.every((event) => event.cat == LogCategory.ui && event.level == LogLevel.info), isTrue);
    const w = t0 + 1500;
    expect(lines(), [
      {
        'msg': 'turn presentation',
        'wUs': t0,
        'from': 'inline',
        'to': 'landscape',
        'wide': false,
        'waiting': true,
        'style': '自绘',
      },
      {'msg': 'turn started', 'wUs': w, 'turn': 3, 'angle': pi / 2, 'ms': 300.0, 'outcome': 'pending'},
      {'msg': 'turn sized', 'wUs': w, 'w': 956.0, 'h': 440.0, 'layout': 'landscape'},
      {'msg': 'turn began', 'wUs': w, 'turn': 3, 'spinFrom': -pi / 2, 'ms': 300.5, 'grow': 0.0},
      {'msg': 'turn drawn sent', 'wUs': w, 'turn': 3},
      {'msg': 'turn late', 'wUs': w, 'missed': true},
    ]);
  });

  test('presentation names 系统 when the turns are left to iOS', () {
    recorder.presentation(Presentation.landscape, Presentation.inline, wide: true, waiting: false, drawn: false);
    expect(lines().single, containsPair('style', '系统'));
  });
}
