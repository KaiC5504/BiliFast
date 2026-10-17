import 'package:bili_core/shared.dart';
import 'package:test/test.dart';

// Swift's LockedTests.testConcurrentIncrements has no counterpart: isolates share no memory, so there is no lock.
void main() {
  test('manual clock', () {
    final manual = ManualClock(100);
    expect(manual.clock.nowMs(), 100);
    manual.advance(50);
    expect(manual.clock.nowMs(), 150);
    manual.set(10);
    expect(manual.clock.nowMs(), 10);
  });
}
