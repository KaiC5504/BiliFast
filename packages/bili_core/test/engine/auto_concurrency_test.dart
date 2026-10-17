import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:test/test.dart';

void main() {
  late ManualClock manual;
  late AutoConcurrency auto;

  setUp(() {
    manual = ManualClock(100000);
    auto = AutoConcurrency(clock: manual.clock);
  });

  test('a new session starts at 16 and comes back when ahead', () {
    expect(auto.threads, 8);
    auto.newSession();
    expect(auto.threads, 16);
    expect(auto.status().inStartup, isTrue);
    manual.advance(3000);
    auto.buffer(ahead: 20, playing: true);
    expect(auto.threads, 12);
    manual.advance(3000);
    auto.buffer(ahead: 20, playing: true);
    expect(auto.threads, 8);
    expect(auto.status().inStartup, isFalse);
  });

  test('a stall climbs and respects the cooldown', () {
    auto.newSession();
    expect(auto.stall(), isFalse);
    manual.advance(3000);
    expect(auto.stall(), isTrue);
    expect(auto.threads, 24);
  });

  test('pushback steps down and blocks that level', () {
    auto.newSession();
    manual.advance(3000);
    auto.stall();
    expect(auto.threads, 24);
    expect(auto.pushback(status: 429), isTrue);
    expect(auto.threads, 16);
    manual.advance(3000);
    expect(auto.stall(), isFalse);
    expect(auto.threads, 16);
    manual.advance(180001);
    expect(auto.stall(), isTrue);
    expect(auto.threads, 24);
  });

  test('a fruitless trial is taken back', () {
    auto.demand(active: 8, limit: 8, queued: 4);
    for (var piece = 0; piece < 10; piece++) {
      auto.delivered(1000000);
      manual.advance(500);
    }
    expect(auto.stall(), isTrue);
    expect(auto.threads, 12);
    for (var piece = 0; piece < 21; piece++) {
      auto.delivered(200000);
      manual.advance(500);
    }
    expect(auto.threads, 8);
  });

  test('low-buffer pressure climbs', () {
    for (final step in <double>[0, 600, 600, 1100]) {
      manual.advance(step);
      auto
        ..activity()
        ..buffer(ahead: 3, playing: true);
    }
    expect(auto.threads, 12);
  });

  test('onChange reports steps', () {
    final seen = <int>[];
    auto.onChange = (threads, _, _) => seen.add(threads);
    auto.newSession();
    expect(seen, [16]);
  });

  test('onChange runs after the state changed', () {
    final seen = <int>[];
    auto.onChange = (threads, _, _) => seen.add(auto.threads * 100 + threads);
    auto.newSession();
    expect(seen, [1616]);
  });
}
