import 'package:bilifast/danmaku/danmaku_pace.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs [pace] frame by frame at 120 Hz behind a playhead at [rate], returning each frame's (playhead, shown).
List<(double, double)> run(
  DanmakuPace pace, {
  required double from,
  required double frames,
  required double rate,
  double start = 0,
}) {
  const frame = 1 / 120;
  final out = <(double, double)>[];
  var playhead = from;
  for (var i = 0; i < frames; i++) {
    playhead += rate * frame;
    final at = start + (i + 1) * frame;
    out.add((
      playhead,
      pace.follow(playhead, rate: rate, running: true, frameSeconds: at),
    ));
  }
  return out;
}

void main() {
  test('at a steady rate the danmaku sits on the playhead', () {
    final pace = DanmakuPace();
    expect(pace.follow(10, rate: 1, running: true, frameSeconds: 0), 10);
    final frames = run(pace, from: 10, frames: 240, rate: 1);
    for (final (playhead, shown) in frames) {
      expect(shown, closeTo(playhead, 1e-9));
    }
  });

  test('the 2× hold eases the speed up instead of stepping it, and catches the playhead up', () {
    final pace = DanmakuPace();
    pace.follow(10, rate: 1, running: true, frameSeconds: 0);
    run(pace, from: 10, frames: 120, rate: 1);
    final frames = run(pace, from: 11, frames: 360, rate: 2, start: 1);
    final speeds = [
      for (var i = 1; i < frames.length; i++)
        (frames[i].$2 - frames[i - 1].$2) * 120,
    ];
    // First frame barely faster than 1×, never a jump to 2×; never backwards; overshoot small.
    expect(speeds.first, lessThan(1.2));
    expect(speeds.every((speed) => speed > 0), isTrue);
    expect(speeds.reduce((a, b) => a > b ? a : b), lessThan(2.15));
    // A tenth of a second in, it's on its way.
    expect(speeds[11], inInclusiveRange(1.3, 1.8));
    // Three seconds on, back on the playhead.
    final (playhead, shown) = frames.last;
    expect(shown, closeTo(playhead, 0.01));
  });

  test('the release eases back down', () {
    final pace = DanmakuPace();
    pace.follow(10, rate: 2, running: true, frameSeconds: 0);
    run(pace, from: 10, frames: 120, rate: 2);
    final frames = run(pace, from: 12, frames: 360, rate: 1, start: 1);
    final first = (frames[1].$2 - frames[0].$2) * 120;
    expect(first, greaterThan(1.7));
    expect(frames.last.$2, closeTo(frames.last.$1, 0.01));
  });

  test('a playhead stepping back by jitter never draws backwards', () {
    final pace = DanmakuPace();
    pace.follow(10, rate: 2, running: true, frameSeconds: 0);
    final first = pace.follow(
      10.0167,
      rate: 2,
      running: true,
      frameSeconds: 1 / 120,
    );
    final second = pace.follow(
      9.97,
      rate: 2,
      running: true,
      frameSeconds: 2 / 120,
    );
    expect(second, greaterThanOrEqualTo(first));
  });

  test('a seek, a pause and a restart are taken at once', () {
    final pace = DanmakuPace();
    pace.follow(10, rate: 1, running: true, frameSeconds: 0);
    expect(pace.follow(40, rate: 1, running: true, frameSeconds: 1 / 120), 40);
    expect(
      pace.follow(40.3, rate: 1, running: false, frameSeconds: 2 / 120),
      40.3,
    );
    pace.restart();
    expect(pace.follow(41, rate: 1, running: true, frameSeconds: 0), 41);
  });
}
