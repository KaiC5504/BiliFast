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

  test('a reading within 40 ms of the prediction moves the clock a tenth of the way to it', () {
    clock.handle(const StatusChanged(PlayerStatus.playing));
    clock.handle(PositionChanged(seconds: 5, hostMs: time.clock.nowMs(), rate: 1));
    time.advance(100);
    expect(clock.handle(PositionChanged(seconds: 5.13, hostMs: time.clock.nowMs(), rate: 1)), isTrue);
    expect(clock.seconds, closeTo(5.103, 1e-9));
    time.advance(100);
    clock.handle(PositionChanged(seconds: 5.173, hostMs: time.clock.nowMs(), rate: 1));
    expect(clock.seconds, closeTo(5.2, 1e-9));
  });

  test('a reading further off, or at a new rate, is taken as it is', () {
    clock.handle(const StatusChanged(PlayerStatus.playing));
    clock.handle(PositionChanged(seconds: 5, hostMs: time.clock.nowMs(), rate: 1));
    time.advance(100);
    clock.handle(PositionChanged(seconds: 5.2, hostMs: time.clock.nowMs(), rate: 1));
    expect(clock.seconds, closeTo(5.2, 1e-9));
    time.advance(100);
    clock.handle(PositionChanged(seconds: 5.31, hostMs: time.clock.nowMs(), rate: 2));
    expect(clock.seconds, closeTo(5.31, 1e-9));
  });

  test('while paused a reading is taken as it is', () {
    clock.handle(PositionChanged(seconds: 5, hostMs: time.clock.nowMs(), rate: 1));
    clock.handle(PositionChanged(seconds: 5.02, hostMs: time.clock.nowMs(), rate: 1));
    expect(clock.seconds, closeTo(5.02, 1e-9));
  });

  test('a new item drops readings far from its start until one lands near it', () {
    clock.handle(const StatusChanged(PlayerStatus.playing));
    clock.reset(300);
    expect(clock.handle(PositionChanged(seconds: 0, hostMs: time.clock.nowMs(), rate: 1)), isFalse);
    expect(clock.seconds, closeTo(300, 1e-9));
    time.advance(100);
    expect(clock.handle(PositionChanged(seconds: 300.05, hostMs: time.clock.nowMs(), rate: 1)), isTrue);
    expect(clock.seconds, closeTo(300.05, 1e-9));
    time.advance(100);
    expect(clock.handle(PositionChanged(seconds: 0, hostMs: time.clock.nowMs(), rate: 1)), isTrue,
        reason: 'once a reading landed, the filter is off');
  });

  test('a new item takes any reading after the settle time', () {
    clock.reset(300);
    time.advance(PlaybackClock.jumpSettleMs);
    expect(clock.handle(PositionChanged(seconds: 0, hostMs: time.clock.nowMs(), rate: 1)), isTrue);
    expect(clock.seconds, closeTo(0, 1e-9));
  });

  test('a jump moves the playhead at once', () {
    clock.handle(const StatusChanged(PlayerStatus.playing));
    clock.handle(PositionChanged(seconds: 5, hostMs: time.clock.nowMs(), rate: 1));
    clock.jump(60);
    time.advance(10);
    expect(clock.seconds, closeTo(60.01, 1e-9));
  });

  test('cleared, it stands at 0 and drops what the old item still reports', () {
    clock.handle(const StatusChanged(PlayerStatus.playing));
    clock.handle(PositionChanged(seconds: 45, hostMs: time.clock.nowMs(), rate: 1));
    clock.clear();
    time.advance(500);
    expect(clock.running, isFalse);
    expect(clock.seconds, 0);
    expect(clock.handle(PositionChanged(seconds: 45.5, hostMs: time.clock.nowMs(), rate: 1)), isFalse);
    expect(clock.seconds, 0);
  });
}
