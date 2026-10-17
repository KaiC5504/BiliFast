import 'package:bili_core/shared.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player/playback_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ManualClock time;
  late PlaybackClock clock;

  setUp(() {
    time = ManualClock(10000);
    clock = PlaybackClock(clock: time.clock);
  });

  test('extrapolates between readings while playing', () {
    clock.handle(const StatusChanged(PlayerStatus.playing));
    clock.handle(PositionChanged(seconds: 5, hostMs: time.clock.nowMs(), rate: 1));
    time.advance(50);
    expect(clock.seconds, closeTo(5.05, 1e-9));
  });

  test('follows the rate', () {
    clock.handle(const StatusChanged(PlayerStatus.playing));
    clock.handle(PositionChanged(seconds: 5, hostMs: time.clock.nowMs(), rate: 2));
    time.advance(100);
    expect(clock.seconds, closeTo(5.2, 1e-9));
  });

  test('holds still while paused', () {
    clock.handle(const StatusChanged(PlayerStatus.playing));
    clock.handle(PositionChanged(seconds: 5, hostMs: time.clock.nowMs(), rate: 1));
    time.advance(100);
    clock.handle(const StatusChanged(PlayerStatus.paused));
    time.advance(1000);
    expect(clock.seconds, closeTo(5.1, 1e-9));
  });

  test('resumes from where it paused, not from the old reading', () {
    clock.handle(const StatusChanged(PlayerStatus.playing));
    clock.handle(PositionChanged(seconds: 5, hostMs: time.clock.nowMs(), rate: 1));
    clock.handle(const StatusChanged(PlayerStatus.paused));
    time.advance(5000);
    clock.handle(const StatusChanged(PlayerStatus.playing));
    time.advance(100);
    expect(clock.seconds, closeTo(5.1, 1e-9));
  });

  test('stops a second past the last reading when readings stop', () {
    clock.handle(const StatusChanged(PlayerStatus.playing));
    clock.handle(PositionChanged(seconds: 5, hostMs: time.clock.nowMs(), rate: 1));
    time.advance(5000);
    expect(clock.seconds, closeTo(6, 1e-9));
  });

  test('a reading from before the seek landed is dropped', () {
    clock.handle(const StatusChanged(PlayerStatus.playing));
    clock.handle(PositionChanged(seconds: 5, hostMs: time.clock.nowMs(), rate: 1));
    clock.jump(60);
    clock.handle(PositionChanged(seconds: 5.1, hostMs: time.clock.nowMs(), rate: 1));
    expect(clock.seconds, closeTo(60, 1e-9));
    time.advance(200);
    clock.handle(PositionChanged(seconds: 60.1, hostMs: time.clock.nowMs(), rate: 1));
    expect(clock.seconds, closeTo(60.1, 1e-9));
  });

  test('after the settle time any reading counts again', () {
    clock.handle(const StatusChanged(PlayerStatus.playing));
    clock.jump(60);
    time.advance(PlaybackClock.jumpSettleMs);
    clock.handle(PositionChanged(seconds: 5, hostMs: time.clock.nowMs(), rate: 1));
    expect(clock.seconds, closeTo(5, 1e-9));
  });

  test('a jump moves the playhead at once', () {
    clock.handle(const StatusChanged(PlayerStatus.playing));
    clock.handle(PositionChanged(seconds: 5, hostMs: time.clock.nowMs(), rate: 1));
    clock.jump(60);
    time.advance(10);
    expect(clock.seconds, closeTo(60.01, 1e-9));
  });
}
