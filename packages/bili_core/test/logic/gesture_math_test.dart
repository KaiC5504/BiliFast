import 'package:bili_core/logic.dart';
import 'package:test/test.dart';

void main() {
  test('constants', () {
    expect(GestureMath.seekSecondsPerWidth, 90);
    expect(GestureMath.axisLockDistance, 10);
    expect(GestureMath.edgeInset, 25);
  });

  test('axis locks after ten points', () {
    expect(GestureMath.axis(dx: 6, dy: 6), isNull);
    expect(GestureMath.axis(dx: 0, dy: 9.99), isNull);
    expect(GestureMath.axis(dx: 8, dy: -9), GestureAxis.vertical);
    expect(GestureMath.axis(dx: -12, dy: 3), GestureAxis.horizontal);
    expect(GestureMath.axis(dx: 0, dy: 10), GestureAxis.vertical);
  });

  test('axis ties are horizontal', () {
    expect(GestureMath.axis(dx: 8, dy: 8), GestureAxis.horizontal);
    expect(GestureMath.axis(dx: -8, dy: 8), GestureAxis.horizontal);
  });

  test('seek is 90 seconds per width and clamped', () {
    expect(GestureMath.seekTarget(start: 100, dx: 200, width: 400, duration: 600), 145);
    expect(GestureMath.seekTarget(start: 10, dx: -400, width: 400, duration: 600), 0);
    expect(GestureMath.seekTarget(start: 590, dx: 400, width: 400, duration: 600), 600);
  });

  test('seek without a width or duration stays put', () {
    expect(GestureMath.seekTarget(start: 30, dx: 50, width: 0, duration: 600), 30);
    expect(GestureMath.seekTarget(start: 30, dx: 50, width: 400, duration: 0), 0);
  });

  test('level up raises and clamps', () {
    expect(GestureMath.level(start: 0.5, dy: -100, height: 400), 0.75);
    expect(GestureMath.level(start: 0.9, dy: -400, height: 400), 1);
    expect(GestureMath.level(start: 0.2, dy: 400, height: 400), 0);
    expect(GestureMath.level(start: 0.5, dy: 100, height: 400), 0.25);
  });

  test('level without a height keeps the start', () {
    expect(GestureMath.level(start: 0.4, dy: -50, height: 0), 0.4);
  });
}
