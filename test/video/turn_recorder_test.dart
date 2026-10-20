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

/// A frame as the engine reports it, its build starting at [buildStartUs] on the wall clock: its raster ends
/// [buildMs] + 0.5 + [rasterMs] ms later, its whole span is 1.5 ms longer. Without [wall] the engine gives no wall time.
FrameTiming _timing(int buildStartUs, {double buildMs = 4, double rasterMs = 6, bool wall = true}) {
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
    rasterFinishWallTime: wall ? rasterFinish + _engineEpoch : 0,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const t0 = 1760000000000000;
  late int nowUs;
  late double hz;
  late MemorySink logs;
  late FakeTimers timers;
  late _FakeScheduler scheduler;
  late TurnRecorder recorder;

  TurnRecorder makeRecorder({SchedulerBinding? binding, double Function()? refreshRate}) => TurnRecorder(
        logger: Logger(session: 'test')..add(logs),
        now: () => DateTime.fromMicrosecondsSinceEpoch(nowUs),
        startTimer: timers.start,
        scheduler: binding,
        refreshRate: refreshRate,
      );

  setUp(() {
    nowUs = t0;
    hz = 120;
    logs = MemorySink();
    timers = FakeTimers();
    scheduler = _FakeScheduler();
    recorder = makeRecorder(binding: scheduler, refreshRate: () => hz);
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

  /// Each `;`-separated entry of a line's field, split on `,`.
  List<List<String>> rows(Map<String, Object> line, String field) {
    final text = line[field]! as String;
    return text.isEmpty ? [] : [for (final row in text.split(';')) row.split(',')];
  }

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
        _timing(t0 + 7833, buildMs: 6, rasterMs: 7),
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
      // Each sample shows when its frame's raster finished; the frames built before or after the samples are left
      // out of the timings.
      expect(framesLine(), {
        'wUs': t0 + 900000,
        't0Us': t0,
        'count': 3,
        'samples': '0.0,-90.0,0.000,,,,,956.0,440.0,10.0;'
            '8.3,-70.7,0.250,10.0,-3.1,400.6,225.0,956.0,440.0,21.3;'
            '16.7,0.0,1.000,0.0,0.0,956.0,440.0,956.0,440.0,22.2',
        'timings': '4.0,6.0,11.5,10.0;6.0,7.0,14.5,21.3;2.5,3.0,7.0,22.2',
        'worstBuildMs': 6.0,
        'worstRasterMs': 7.0,
        'refreshHz': 120.0,
        'slow': 2,
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
      expect(framesLine()['timings'], '4.0,6.0,11.5,10.3;4.0,6.0,11.5,18.5');
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
        'samples': '0.0,0.0,1.000,,,,,956.0,440.0,',
        'timings': '',
        'worstBuildMs': 0.0,
        'worstRasterMs': 0.0,
        'refreshHz': 120.0,
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

    test('a frame while the line waits for timings starts a new window; the old one still waits for its own', () {
      frameAt(t0);
      fireSettle();
      final wait = timers.activeWith(TurnRecorder.timingsWait)!;
      frameAt(t0 + 700000, angle: pi / 4);
      expect(wait.isActive, isTrue);
      expect(scheduler.callbacks, hasLength(2));

      scheduler.report([_timing(t0 - 300), _timing(t0 + 699000)]);
      expect(framesLine(), {
        'wUs': t0 + 700000,
        't0Us': t0,
        'count': 1,
        'samples': '0.0,0.0,1.000,,,,,956.0,440.0,10.2',
        'timings': '4.0,6.0,11.5,10.2',
        'worstBuildMs': 4.0,
        'worstRasterMs': 6.0,
        'refreshHz': 120.0,
        'slow': 1,
      });
      expect(wait.isActive, isFalse);
      expect(scheduler.callbacks, hasLength(1));

      nowUs = t0 + 1000000;
      fireSettle();
      expect(frameLines(), hasLength(2));
      final second = fields(frameLines().last);
      expect(second['t0Us'], t0 + 700000);
      expect(second['count'], 1);
      expect(second['samples'], '0.0,45.0,1.000,,,,,956.0,440.0,9.5');
      expect(second['timings'], '4.0,6.0,11.5,9.5');
      expect(scheduler.callbacks, isEmpty);
      expect(timers.active, isEmpty);
    });

    test('an event while the line waits for timings starts no settle, and the next frame starts a new window', () {
      frameAt(t0);
      fireSettle();
      recorder.presentation(
        Presentation.landscape,
        Presentation.inline,
        wide: true,
        waiting: true,
        style: const TurnStyle(method: TurnMethod.counter, picture: TurnPicture.fade),
      );
      expect(timers.activeWith(TurnRecorder.settle), isNull);
      expect(timers.activeWith(TurnRecorder.timingsWait), isNotNull);
      frameAt(t0 + 500000);
      timers.activeWith(TurnRecorder.timingsWait)!.fire();
      expect(framesLine()['count'], 1);
      expect(framesLine()['t0Us'], t0);
    });

    group('two turns 1.5 s apart (轮换测试) give two lines, each with only its own frames and timings', () {
      const frames = 36;
      const step = 8333;
      const second = t0 + (frames - 1) * step + 1500000;

      void turn(int start) {
        for (var i = 0; i < frames; i++) {
          frameAt(start + i * step, angle: -pi / 2 * (1 - i / frames));
        }
      }

      List<FrameTiming> timingsFor(int start, int from, int to) =>
          [for (var i = from; i < to; i++) _timing(start + i * step - 200)];

      /// [line] is the turn from [start] alone, with the first [timings] of its frames' timings and no other.
      void expectOwn(Map<String, Object> line, int start, {required int timings}) {
        expect(line['t0Us'], start);
        expect(line['count'], frames);
        final samples = rows(line, 'samples');
        expect(samples.map((sample) => sample.first), [
          for (var i = 0; i < frames; i++) (i * step / 1000).toStringAsFixed(1),
        ]);
        // Each frame's raster ends 10.3 ms after its sample.
        final shown = [for (var i = 0; i < frames; i++) ((i * step + 10300) / 1000).toStringAsFixed(1)];
        expect(rows(line, 'timings').map((timing) => timing[3]), shown.take(timings));
        expect(samples.map((sample) => sample[9]), [for (var i = 0; i < frames; i++) i < timings ? shown[i] : '']);
      }

      test("when the first turn's timings come during the second", () {
        turn(t0);
        fireSettle();
        nowUs = t0 + 600000;
        fireSettle();
        expect(timers.activeWith(TurnRecorder.timingsWait), isNotNull);

        nowUs = second - 10000;
        recorder.presentation(
          Presentation.inline,
          Presentation.landscape,
          wide: false,
          waiting: true,
          style: const TurnStyle(method: TurnMethod.counter, picture: TurnPicture.fade),
        );
        turn(second);
        expect(frameLines(), isEmpty);

        // One late batch: all of the first turn and the start of the second.
        nowUs = second + 400000;
        scheduler.report([...timingsFor(t0, 0, frames), ...timingsFor(second, 0, 4)]);
        expect(frameLines(), hasLength(1));
        expectOwn(fields(frameLines().first), t0, timings: frames);

        fireSettle();
        nowUs = second + 900000;
        fireSettle();
        expect(frameLines(), hasLength(1));
        scheduler.report(timingsFor(second, 4, frames));
        expect(frameLines(), hasLength(2));
        expectOwn(fields(frameLines().last), second, timings: frames);
        expect(scheduler.callbacks, isEmpty);
        expect(timers.active, isEmpty);
      });

      test('when they come only after its wait ran out', () {
        turn(t0);
        fireSettle();
        fireSettle();
        turn(second);
        nowUs = second + 300000;
        timers.activeWith(TurnRecorder.timingsWait)!.fire();
        expect(frameLines(), hasLength(1));
        expectOwn(fields(frameLines().first), t0, timings: 0);

        scheduler.report([...timingsFor(t0, 0, frames), ...timingsFor(second, 0, frames)]);
        fireSettle();
        fireSettle();
        expect(frameLines(), hasLength(2));
        expectOwn(fields(frameLines().last), second, timings: frames);
      });
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
      expect(second['timings'], '3.0,6.0,10.5,9.2');
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
      recorder = makeRecorder(refreshRate: () => hz);
      frameAt(t0);
      final report = SchedulerBinding.instance.platformDispatcher.onReportTimings!;
      report([_timing(t0 - 400, buildMs: 5)]);
      fireSettle();
      expect(framesLine()['timings'], '5.0,6.0,12.5,11.1');
      // Removed again: a later report reaches no recorder and throws nothing.
      report([_timing(t0 + 900000)]);
      expect(frameLines(), hasLength(1));
    });
  });

  group('refreshHz and slow', () {
    final spans = [
      _timing(t0 - 200, buildMs: 2.5, rasterMs: 3),
      _timing(t0 + 8133, buildMs: 3.5, rasterMs: 4),
      _timing(t0 + 16467, buildMs: 7, rasterMs: 8),
      _timing(t0 + 24800, buildMs: 8, rasterMs: 8),
    ];

    Map<String, Object> lineAt(double Function() refreshRate) {
      recorder = makeRecorder(binding: scheduler, refreshRate: refreshRate);
      for (var i = 0; i < 4; i++) {
        frameAt(t0 + i * 8333);
      }
      scheduler.report(spans);
      fireSettle();
      fireSettle();
      return framesLine();
    }

    test('at 120 Hz, slow counts the frames whose whole span is over 8.3 ms', () {
      final line = lineAt(() => 120);
      expect(rows(line, 'timings').map((timing) => timing[2]), ['7.0', '9.0', '16.5', '17.5']);
      expect(line['refreshHz'], 120.0);
      expect(line['slow'], 3);
    });

    test('at 60 Hz, only those over 16.7 ms', () {
      final line = lineAt(() => 60);
      expect(line['refreshHz'], 60.0);
      expect(line['slow'], 1);
    });

    test('a display that reports no rate counts as 60 Hz', () {
      final line = lineAt(() => 0);
      expect(line['refreshHz'], 60.0);
      expect(line['slow'], 1);
    });

    test("without one given, the rate is the view's display's", () {
      final display = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first.display;
      display.refreshRate = 120;
      addTearDown(display.resetRefreshRate);
      recorder = makeRecorder();
      frameAt(t0);
      fireSettle();
      timers.activeWith(TurnRecorder.timingsWait)!.fire();
      expect(framesLine()['refreshHz'], 120.0);
    });
  });

  group('rasterEndMs and shownMs', () {
    test('are filled from the wall clock, and empty for a sample whose frame was never reported', () {
      frameAt(t0);
      frameAt(t0 + 8333);
      frameAt(t0 + 16667);
      scheduler.report([_timing(t0 - 1000, buildMs: 3), _timing(t0 + 7333, buildMs: 5, rasterMs: 2)]);
      fireSettle();
      fireSettle();
      timers.activeWith(TurnRecorder.timingsWait)!.fire();
      final line = framesLine();
      expect(rows(line, 'timings').map((timing) => timing[3]), ['8.5', '14.8']);
      expect(rows(line, 'samples').map((sample) => sample[9]), ['8.5', '14.8', '']);
    });

    test('are empty when the engine gives no wall time', () {
      frameAt(t0);
      frameAt(t0 + 8333);
      scheduler.report([_timing(t0 - 300, wall: false), _timing(t0 + 8033, buildMs: 5, wall: false)]);
      fireSettle();
      fireSettle();
      final line = framesLine();
      expect(line['timings'], '4.0,6.0,11.5,;5.0,6.0,12.5,');
      expect(line['samples'], '0.0,0.0,1.000,,,,,956.0,440.0,;8.3,0.0,1.000,,,,,956.0,440.0,');
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
        'samples': '0.0,-90.0,0.000,,,,,956.0,440.0,10.2',
        'timings': '4.0,6.0,11.5,10.2',
        'worstBuildMs': 4.0,
        'worstRasterMs': 6.0,
        'refreshHz': 120.0,
        'slow': 1,
      });
      expect(scheduler.callbacks, isEmpty);
      expect(timers.active, isEmpty);

      frameAt(t0 + 60000);
      recorder.dispose();
      expect(frameLines(), hasLength(1));
      expect(scheduler.callbacks, isEmpty);
      expect(timers.active, isEmpty);
    });

    test('writes a turn still waiting for its timings before the one running', () {
      frameAt(t0);
      fireSettle();
      frameAt(t0 + 700000);
      recorder.dispose();
      expect(frameLines().map((line) => fields(line)['t0Us']), [t0, t0 + 700000]);
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
