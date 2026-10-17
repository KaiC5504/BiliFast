import 'package:bili_core/logic.dart';
import 'package:test/test.dart';

void main() {
  test('heartbeat every 15 seconds of playback and on marks', () {
    final s = HeartbeatSchedule();
    expect(s.tick(position: 14, playing: true), isNull);
    expect(s.tick(position: 15, playing: true), 15);
    expect(s.tick(position: 40, playing: false), isNull);
    expect(s.mark(position: 40), 40);
    expect(s.tick(position: 54, playing: true), isNull);
    expect(s.tick(position: 55, playing: true), 55);
  });

  test('paused player never beats', () {
    final s = HeartbeatSchedule();
    expect(s.tick(position: 100, playing: false), isNull);
    expect(s.tick(position: 100, playing: true), 100);
  });

  test('custom interval and fractional positions', () {
    final s = HeartbeatSchedule(interval: 5);
    expect(s.tick(position: 4.9, playing: true), isNull);
    expect(s.tick(position: 5.4, playing: true), 5);
    expect(s.tick(position: 10.3, playing: true), isNull);
    expect(s.tick(position: 10.4, playing: true), 10);
  });

  test('seeking back waits a full interval from the mark', () {
    final s = HeartbeatSchedule();
    expect(s.tick(position: 60, playing: true), 60);
    expect(s.mark(position: 10), 10);
    expect(s.tick(position: 24, playing: true), isNull);
    expect(s.tick(position: 25, playing: true), 25);
  });

  test('non-finite positions neither throw nor fire', () {
    final s = HeartbeatSchedule();
    expect(s.tick(position: double.infinity, playing: true), isNull);
    expect(s.tick(position: double.nan, playing: true), isNull);
    expect(s.tick(position: double.negativeInfinity, playing: true), isNull);
    expect(s.mark(position: double.nan), 0);
    expect(s.mark(position: double.infinity), 0);
    expect(s.tick(position: 14, playing: true), isNull);
    expect(s.tick(position: 15, playing: true), 15);
  });

  test('negative position is not the finished marker', () {
    final s = HeartbeatSchedule();
    expect(s.mark(position: -3), 0);
    expect(s.mark(position: -1), isNot(HeartbeatSchedule.finished));
  });

  test('finished is minus one', () {
    expect(HeartbeatSchedule.finished, -1);
  });
}
