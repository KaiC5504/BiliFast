import 'package:bili_core/logic.dart';
import 'package:test/test.dart';

void main() {
  final began = DateTime.utc(2026, 11, 12, 8);
  late DateTime now;
  late WatchSession session;

  setUp(() {
    now = began;
    session = WatchSession(now: () => now);
  });

  void pass(double seconds) => now = now.add(Duration(microseconds: (seconds * 1e6).round()));

  /// Plays on from [from] for [seconds] of the clock, a position every quarter second; where it got to.
  double play(double from, double seconds, {double rate = 1}) {
    var position = from;
    for (var left = seconds; left > 1e-9; left -= 0.25) {
      final step = left < 0.25 ? left : 0.25;
      pass(step);
      position += step * rate;
      session.tick(position: position, playing: true);
    }
    return position;
  }

  List<int> numbers() {
    final totals = session.totals;
    return [
      totals.playedTime,
      totals.actualPlayedTime,
      totals.totalTime,
      totals.pausedTime,
      totals.lastProgress,
      totals.maxProgress,
    ];
  }

  test('the captured 8 s play of a 10 s video: times to the nearest second, places cut to the second', () {
    session.started(0);
    // The first frame lands a moment after the player says it plays.
    pass(0.08);
    session.tick(position: 0, playing: true);
    play(0, 7.96);
    expect(session.totals.startTs, began.millisecondsSinceEpoch ~/ 1000);
    expect(numbers(), [8, 8, 8, 0, 7, 7]);
  });

  test('nothing counts before the play starts', () {
    session
      ..tick(position: 40, playing: true)
      ..seeked(90)
      ..paused();
    pass(20);
    expect(session.totals.startTs, 0);
    expect(numbers(), [0, 0, 0, 0, 0, 0]);

    session.started(12);
    expect(session.totals.startTs, began.add(const Duration(seconds: 20)).millisecondsSinceEpoch ~/ 1000);
    expect(numbers(), [0, 0, 0, 0, 12, 12], reason: 'a play that resumes at 12 s starts there');
  });

  test('a pause is time paused, not time played', () {
    session.started(0);
    final at = play(0, 10);
    session.paused();
    pass(30);
    session.tick(position: at, playing: false);
    expect(numbers(), [10, 10, 40, 30, 10, 10]);
    session.resumed();
    play(at, 5);
    expect(numbers(), [15, 15, 45, 30, 15, 15]);
  });

  test('a seek moves the place and plays nothing', () {
    session.started(0);
    play(0, 10);
    session.seeked(300);
    expect(numbers(), [10, 10, 10, 0, 300, 300]);
    play(300, 5);
    expect(numbers(), [15, 15, 15, 0, 305, 305]);

    session.seeked(20);
    play(20, 10);
    expect(numbers(), [25, 25, 25, 0, 30, 305], reason: 'back at 30 s, having been as far as 305');
  });

  test('a jump no speed explains is not play: positions from before a seek landed, a seek nobody named', () {
    session.started(0);
    play(0, 10);
    session.seeked(300);
    pass(0.25);
    session.tick(position: 10.25, playing: true);
    pass(0.25);
    session.tick(position: 300.1, playing: true);
    expect(numbers(), [10, 11, 11, 0, 300, 300]);

    pass(0.25);
    session.tick(position: 400, playing: true);
    expect(session.totals.playedTime, 10);
    expect(session.totals.lastProgress, 400);
  });

  test('at 2× twice the video goes by in the same time', () {
    session.started(0);
    play(0, 10, rate: 2);
    expect(numbers(), [20, 10, 10, 0, 20, 20]);
  });

  test('a wait for the network is neither played nor paused', () {
    session.started(0);
    final at = play(0, 4);
    session.tick(position: at, playing: false);
    pass(6);
    session.tick(position: at, playing: false);
    expect(numbers(), [4, 4, 10, 0, 4, 4]);
    session.tick(position: at, playing: true);
    play(at, 2);
    expect(numbers(), [6, 6, 12, 0, 6, 6]);
  });

  test('a paused player stays paused whatever its positions say, until it is resumed', () {
    session.started(0);
    play(0, 2);
    session.paused();
    pass(3);
    session.tick(position: 2, playing: true);
    pass(3);
    expect(numbers(), [2, 2, 8, 6, 2, 2]);
    session.resumed();
    play(2, 1);
    expect(numbers(), [3, 3, 9, 6, 3, 3]);
  });

  test('played to its end, the clock goes on but nothing more is played', () {
    session.started(0);
    play(0, 10);
    session.ended();
    pass(3);
    expect(numbers(), [10, 10, 13, 0, 10, 10]);
  });

  test('positions that are no number, or below zero, are passed over', () {
    session.started(0);
    play(0, 2);
    pass(0.25);
    session
      ..tick(position: double.nan, playing: true)
      ..tick(position: double.infinity, playing: true)
      ..tick(position: -3, playing: true)
      ..seeked(double.nan);
    pass(0.25);
    session.tick(position: 2.5, playing: true);
    expect(numbers(), [3, 3, 3, 0, 2, 2]);
  });

  test('a clock set back mid-play takes nothing away', () {
    session.started(0);
    play(0, 5);
    now = now.subtract(const Duration(minutes: 1));
    session.tick(position: 5.25, playing: true);
    expect(session.totals.actualPlayedTime, 5);
    expect(session.totals.totalTime, 0);
  });
}
