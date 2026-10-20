import 'dart:math';
import 'dart:ui';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/device/turn_style.dart';
import 'package:bilifast/video/turn_recorder.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart' show FakeTimers;

/// The engine's FrameTiming reports, sent by hand.
final class _FakeScheduler implements SchedulerBinding {
  final callbacks = <TimingsCallback>[];

  @override
  void addTimingsCallback(TimingsCallback callback) => callbacks.add(callback);

  @override
  void removeTimingsCallback(TimingsCallback callback) => callbacks.remove(callback);

  void report(List<FrameTiming> timings) {
    for (final callback in List.of(callbacks)) {
      callback(timings);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The engine's own clock runs this far behind the wall clock.
const _engineEpoch = 1700000000000000;

/// A frame as the engine reports it, its build starting at [buildStartUs] on the wall clock.
FrameTiming _timing(int buildStartUs, {double buildMs = 4, double rasterMs = 6}) {
  final buildStart = buildStartUs - _engineEpoch;
  final buildFinish = buildStart + (buildMs * 1000).round();
  final rasterStart = buildFinish + 500;
  final rasterFinish = rasterStart + (rasterMs * 1000).round();
  return FrameTiming(
    vsyncStart: buildStart - 1000,
    buildStart: buildStart,
    buildFinish: buildFinish,
    rasterStart: rasterStart,
    rasterFinish: rasterFinish,
    rasterFinishWallTime: rasterFinish + _engineEpoch,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const t0 = 1760000000000000;
  late int nowUs;
  late MemorySink logs;
  late FakeTimers timers;
  late _FakeScheduler scheduler;
  late TurnRecorder recorder;

  TurnRecorder makeRecorder({SchedulerBinding? binding}) => TurnRecorder(
        logger: Logger(session: 'test')..add(logs),
        now: () => DateTime.fromMicrosecondsSinceEpoch(nowUs),
        startTimer: timers.start,
        scheduler: binding,
      );

  setUp(() {
    nowUs = t0;
    logs = MemorySink();
    timers = FakeTimers();
    scheduler = _FakeScheduler();
    recorder = makeRecorder(binding: scheduler);
  });

  Map<String, Object> fields(LogEvent event) => event.f.map((key, value) => MapEntry(key, value.toJson()));

  List<Map<String, Object>> lines() => [
        for (final event in logs.events) {'msg': event.msg, ...fields(event)},
      ];

  Iterable<LogEvent> frameLines() => logs.events.where((event) => event.msg == 'turn frames');

  Map<String, Object> framesLine() => fields(frameLines().single);

  void frameAt(int us, {double angle = 0, double grow = 1, Rect? box, Size size = const Size(956, 440)}) {
    nowUs = us;
    recorder.frame(angle: angle, grow: grow, box: box, size: size);
  }

  void fireSettle() => timers.activeWith(TurnRecorder.settle)!.fire();

  group('events', () {
    test('each is logged at once as turn <kind>, category ui, with the wall clock', () {
      const style = TurnStyle(method: TurnMethod.counter, picture: TurnPicture.fade);
      recorder.presentation(Presentation.inline, Presentation.landscape, wide: false, waiting: true, style: style);
      nowUs = t0 + 1500;
      recorder.started((id: 3, angle: pi / 2, duration: const Duration(milliseconds: 300)), outcome: 'pending');
      recorder.sized(const Size(956, 440), layout: Presentation.landscape);
      recorder.began(3, spinFrom: -pi / 2, duration: const Duration(microseconds: 300500), grow: 0, held: true);
      recorder.released(3, why: 'picture');
      recorder.drawnSent(3);
      recorder.pictureGone(3);
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
          'style': '抵消·淡出·立即',
        },
        {'msg': 'turn started', 'wUs': w, 'turn': 3, 'angle': pi / 2, 'ms': 300.0, 'outcome': 'pending'},
        {'msg': 'turn sized', 'wUs': w, 'w': 956.0, 'h': 440.0, 'layout': 'landscape'},
        {'msg': 'turn began', 'wUs': w, 'turn': 3, 'spinFrom': -pi / 2, 'ms': 300.5, 'grow': 0.0, 'held': true},
        {'msg': 'turn released', 'wUs': w, 'turn': 3, 'why': 'picture'},
        {'msg': 'turn drawn sent', 'wUs': w, 'turn': 3},
        {'msg': 'turn picture gone', 'wUs': w, 'turn': 3},
        {'msg': 'turn late', 'wUs': w, 'missed': true},
      ]);
      expect(timers.all, isEmpty);
      expect(scheduler.callbacks, isEmpty);
    });
  });

  group('frames', () {
    test('are only buffered while the turn runs, with one settle timer for the lot and no log line', () {
      for (var i = 0; i < 40; i++) {
        frameAt(t0 + i * 8333, angle: -pi / 2 * (1 - i / 40));
      }
      expect(logs.events, isEmpty);
      expect(timers.all, hasLength(1));
      expect(timers.all.single.delay, TurnRecorder.settle);
      expect(scheduler.callbacks, hasLength(1));
    });

    test('settled, they go out as one line in the format of docs/reference/turn-log.md', () {
      frameAt(t0, angle: -pi / 2, grow: 0);
      frameAt(t0 + 8333, angle: -1.2345, grow: 0.25, box: const Rect.fromLTWH(10.04, -3.06, 400.56, 225));
      frameAt(t0 + 16667, angle: -0.0001, box: const Rect.fromLTWH(0, 0, 956, 440));
      scheduler.report([
        _timing(t0 - 20000),
        _timing(t0 - 500),
        _timing(t0 + 7833, buildMs: 6, rasterMs: 18),
      ]);
      expect(logs.events, isEmpty);

      // Frames came after the settle timer started, so it starts over.
      fireSettle();
      expect(logs.events, isEmpty);
      nowUs = t0 + 600000;
      fireSettle();
      // The batch with the last frame hasn't come: release builds report up to a second late.
      expect(logs.events, isEmpty);
      expect(timers.activeWith(TurnRecorder.timingsWait), isNotNull);

      nowUs = t0 + 900000;
      scheduler.report([_timing(t0 + 16167, buildMs: 2.5, rasterMs: 3), _timing(t0 + 25000)]);
      expect(logs.events.map((event) => event.msg), ['turn frames']);
      expect(framesLine(), {
        'wUs': t0 + 900000,
        't0Us': t0,
        'count': 3,
        'samples': '0.0,-90.0,0.000,,,,,956.0,440.0;'
            '8.3,-70.7,0.250,10.0,-3.1,400.6,225.0,956.0,440.0;'
            '16.7,0.0,1.000,0.0,0.0,956.0,440.0,956.0,440.0',
        'timings': '4.0,6.0,11.5;6.0,18.0,25.5;2.5,3.0,7.0',
        'worstBuildMs': 6.0,
        'worstRasterMs': 18.0,
        'slow': 1,
      });
      expect(scheduler.callbacks, isEmpty);
      expect(timers.active, isEmpty);
    });

    test('timings already in at the settle go out with it, without waiting', () {
      frameAt(t0);
      frameAt(t0 + 8333);
      scheduler.report([_timing(t0 - 200), _timing(t0 + 8000)]);
      fireSettle();
      fireSettle();
      expect(framesLine()['timings'], '4.0,6.0,11.5;4.0,6.0,11.5');
      expect(timers.activeWith(TurnRecorder.timingsWait), isNull);
    });

    test('with no timings at all, the line goes out once the wait runs out', () {
      frameAt(t0);
      fireSettle();
      nowUs = t0 + 1500000;
      timers.activeWith(TurnRecorder.timingsWait)!.fire();
      expect(framesLine(), {
        'wUs': t0 + 1500000,
        't0Us': t0,
        'count': 1,
        'samples': '0.0,0.0,1.000,,,,,956.0,440.0',
        'timings': '',
        'worstBuildMs': 0.0,
        'worstRasterMs': 0.0,
        'slow': 0,
      });
      expect(scheduler.callbacks, isEmpty);
    });

    test("a turn's events while it runs hold the line back too", () {
      frameAt(t0);
      recorder.drawnSent(1);
      fireSettle();
      expect(timers.activeWith(TurnRecorder.timingsWait), isNull);
      fireSettle();
      expect(timers.activeWith(TurnRecorder.timingsWait), isNotNull);
      expect(frameLines(), isEmpty);
    });

    test('a frame while the line waits for timings carries on the same window', () {
      frameAt(t0);
      fireSettle();
      frameAt(t0 + 700000, angle: pi / 4);
      expect(timers.activeWith(TurnRecorder.timingsWait), isNull);
      fireSettle();
      scheduler.report([_timing(t0 + 699000)]);
      final line = framesLine();
      expect(line['t0Us'], t0);
      expect(line['count'], 2);
      expect(line['samples'], '0.0,0.0,1.000,,,,,956.0,440.0;700.0,45.0,1.000,,,,,956.0,440.0');
      expect(line['timings'], '4.0,6.0,11.5');
    });

    test('each window listens for timings from its first frame until its line is written', () {
      frameAt(t0);
      frameAt(t0 + 8333);
      expect(scheduler.callbacks, hasLength(1));
      scheduler.report([_timing(t0 + 8000)]);
      fireSettle();
      fireSettle();
      expect(scheduler.callbacks, isEmpty);
      // Reported between turns, so nobody hears it.
      scheduler.report([_timing(t0 + 2000000)]);

      frameAt(t0 + 2000000);
      expect(scheduler.callbacks, hasLength(1));
      scheduler.report([_timing(t0 + 2000000 - 300, buildMs: 3)]);
      fireSettle();
      expect(frameLines(), hasLength(2));
      final second = fields(frameLines().last);
      expect(second['t0Us'], t0 + 2000000);
      expect(second['timings'], '3.0,6.0,10.5');
      expect(scheduler.callbacks, isEmpty);
    });

    test('a window keeps at most maxFrames frames', () {
      for (var i = 0; i <= TurnRecorder.maxFrames; i++) {
        frameAt(t0 + i * 8333);
      }
      fireSettle();
      fireSettle();
      timers.activeWith(TurnRecorder.timingsWait)!.fire();
      expect(framesLine()['count'], TurnRecorder.maxFrames);
      expect((framesLine()['samples']! as String).split(';'), hasLength(TurnRecorder.maxFrames));
    });

    test('the engine reports through SchedulerBinding when no scheduler is given', () {
      recorder = makeRecorder();
      frameAt(t0);
      final report = SchedulerBinding.instance.platformDispatcher.onReportTimings!;
      report([_timing(t0 - 400, buildMs: 5)]);
      fireSettle();
      expect(framesLine()['timings'], '5.0,6.0,12.5');
      // Removed again: a later report reaches no recorder and throws nothing.
      report([_timing(t0 + 900000)]);
      expect(frameLines(), hasLength(1));
    });
  });

  group('dispose', () {
    test('writes what is pending at once, stops listening and cancels its timers', () {
      frameAt(t0, angle: -pi / 2, grow: 0);
      scheduler.report([_timing(t0 - 300)]);
      nowUs = t0 + 50000;
      recorder.dispose();
      expect(framesLine(), {
        'wUs': t0 + 50000,
        't0Us': t0,
        'count': 1,
        'samples': '0.0,-90.0,0.000,,,,,956.0,440.0',
        'timings': '4.0,6.0,11.5',
        'worstBuildMs': 4.0,
        'worstRasterMs': 6.0,
        'slow': 0,
      });
      expect(scheduler.callbacks, isEmpty);
      expect(timers.active, isEmpty);

      frameAt(t0 + 60000);
      recorder.dispose();
      expect(frameLines(), hasLength(1));
      expect(scheduler.callbacks, isEmpty);
      expect(timers.active, isEmpty);
    });

    test('with nothing pending, writes nothing', () {
      recorder.dispose();
      expect(logs.events, isEmpty);
      expect(timers.all, isEmpty);
    });
  });
}
