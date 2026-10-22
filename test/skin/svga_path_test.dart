import 'dart:ui';

import 'package:bilifast/skin/svga/svg_path.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> parse(String data) => [for (final segment in SvgPath.parse(data)) '$segment'];

void main() {
  test('absolute moves, lines and a close', () {
    expect(parse('M10 20 L30 40 Z'), ['M 10 20', 'L 30 40', 'Z']);
  });

  test('relative commands start from the current point; pairs after a move are lines', () {
    expect(parse('m10 10 20 0 l0 10'), ['M 10 10', 'L 30 10', 'L 30 20']);
    expect(parse('M10 10 20 0'), ['M 10 10', 'L 20 0']);
  });

  test('H and V, absolute and relative, become lines', () {
    expect(parse('M1 2 H10 V20 h-5 v-10'), ['M 1 2', 'L 10 2', 'L 10 20', 'L 5 20', 'L 5 10']);
  });

  test('C and c; S reflects the last control point, or starts at the current point after anything else', () {
    expect(parse('M0 0 C1 2 3 4 5 6 S9 10 11 12'), ['M 0 0', 'C 1 2 3 4 5 6', 'C 7 8 9 10 11 12']);
    expect(parse('M10 10 c1 1 2 2 3 3 s1 1 2 2'), ['M 10 10', 'C 11 11 12 12 13 13', 'C 14 14 14 14 15 15']);
    expect(parse('M0 0 L5 5 S8 8 9 9'), ['M 0 0', 'L 5 5', 'C 5 5 8 8 9 9']);
  });

  test('Q and q; T reflects the last control point, and chains', () {
    expect(parse('M0 0 Q5 10 10 0 T20 0 T30 0'), ['M 0 0', 'Q 5 10 10 0', 'Q 15 -10 20 0', 'Q 25 10 30 0']);
    expect(parse('M0 0 q5 10 10 0 t10 0'), ['M 0 0', 'Q 5 10 10 0', 'Q 15 -10 20 0']);
    expect(parse('M0 0 T10 0'), ['M 0 0', 'Q 0 0 10 0']);
  });

  test('arcs: flags need no separators, negative radii are their size, relative ends', () {
    expect(parse('M0 0 A5 5 30 1 0 10 0'), ['M 0 0', 'A 5 5 30 1 0 10 0']);
    expect(parse('M0 0 a-5 5 0 0110 10'), ['M 0 0', 'A 5 5 0 0 1 10 10']);
  });

  test('Z returns to the subpath\'s start, so a relative move after it starts there', () {
    expect(parse('M10 10 L20 10 z m5 5 l1 0'), ['M 10 10', 'L 20 10', 'Z', 'M 15 15', 'L 16 15']);
    expect(parse('M10 10 L20 20 Z L0 0'), ['M 10 10', 'L 20 20', 'Z', 'L 0 0']);
  });

  test('numbers: commas, no spaces before signs, two dots, exponents', () {
    expect(parse('M1,2L-3-4'), ['M 1 2', 'L -3 -4']);
    expect(parse('M.5.5L1.5.25'), ['M 0.5 0.5', 'L 1.5 0.25']);
    expect(parse('M1e1 2E-1 L+3 4'), ['M 10 0.2', 'L 3 4']);
    expect(parse('  M 1 , 2\n\tL 3 4  '), ['M 1 2', 'L 3 4']);
  });

  test('an error ends the path where it is, as SVG asks', () {
    expect(parse('M0 0 L10 10 L20 X 30 30'), ['M 0 0', 'L 10 10']);
    expect(parse('M0 0 L10'), ['M 0 0']);
    expect(parse('M0 0 Z 5 5'), ['M 0 0', 'Z']);
    expect(parse('L10 10'), isEmpty, reason: 'path data must start with a move');
    expect(parse(''), isEmpty);
  });

  test('toPath draws what it parsed', () {
    final square = SvgPath.parsePath('M0 0 H10 V10 H0 Z');
    expect(square.getBounds(), const Rect.fromLTRB(0, 0, 10, 10));
    expect(square.contains(const Offset(5, 5)), isTrue);
    expect(square.contains(const Offset(15, 5)), isFalse);

    // The curve's lowest point is half way to its control point.
    final curve = SvgPath.parsePath('M0 0 Q10 20 20 0 Z');
    expect(curve.contains(const Offset(10, 9)), isTrue);
    expect(curve.contains(const Offset(10, 11)), isFalse);

    final halfCircle = SvgPath.parsePath('M0 0 A10 10 0 0 1 20 0 Z');
    expect(halfCircle.contains(const Offset(10, -9)), isTrue, reason: 'sweep 1 goes clockwise: over the top');
    expect(halfCircle.contains(const Offset(10, 5)), isFalse);
    expect(halfCircle.contains(const Offset(10, -11)), isFalse);
  });
}
