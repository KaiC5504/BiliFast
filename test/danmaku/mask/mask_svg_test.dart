import 'dart:ui';

import 'package:bilifast/danmaku/mask/mask_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'web_mask_file.dart';

void expectRect(Rect actual, Rect expected) {
  expect(actual.left, closeTo(expected.left, 0.01));
  expect(actual.top, closeTo(expected.top, 0.01));
  expect(actual.right, closeTo(expected.right, 0.01));
  expect(actual.bottom, closeTo(expected.bottom, 0.01));
}

void main() {
  test('a square in potrace\'s flipped 0.1 units lands in the viewBox\'s, y down', () {
    final shape = MaskShape.parse(potraceSvg(['M100 100 l200 0 0 200 -200 0z']));

    expect(shape.box, const Size(180, 320));
    final path = shape.toPath();
    expectRect(path.getBounds(), const Rect.fromLTRB(10, 290, 30, 310));
    expect(path.contains(const Offset(20, 300)), isTrue);
    expect(path.contains(const Offset(20, 20)), isFalse);
  });

  test('a hole stays a hole and an island inside it draws, whichever way the hole turns', () {
    const outer = 'M0 1605 l0 -1595 900 0 900 0 0 1595 0 1595 -900 0 -900 0 0 -1595z';
    const island = 'M800 800 l200 0 0 200 -200 0 0 -200z';
    for (final hole in ['m500 -1105 l800 0 0 800 -800 0 0 -800z', 'm500 -1105 l0 800 800 0 0 -800 -800 0z']) {
      final path = MaskShape.parse(potraceSvg(['$outer $hole', island])).toPath();

      expect(path.contains(const Offset(5, 5)), isTrue, reason: 'outside the hole');
      expect(path.contains(const Offset(175, 315)), isTrue, reason: 'outside the hole');
      expect(path.contains(const Offset(60, 200)), isFalse, reason: 'in the hole');
      expect(path.contains(const Offset(120, 260)), isFalse, reason: 'in the hole');
      expect(path.contains(const Offset(90, 230)), isTrue, reason: 'on the island');
    }
  });

  test('potrace\'s curves: a round hole in the drawable frame', () {
    final path = MaskShape.parse(
      potraceSvg([
        'M0 1605 l0 -1595 900 0 900 0 0 1595 0 1595 -900 0 -900 0 0 -1595z m800 395 c-50 0 -100 -50 -100 -100 '
            '0 -50 50 -100 100 -100 50 0 100 50 100 100 0 50 -50 100 -100 100z',
      ]),
    ).toPath();

    expect(path.contains(const Offset(80, 130)), isFalse);
    expect(path.contains(const Offset(80, 145)), isTrue);
    expect(path.contains(const Offset(5, 300)), isTrue);
  });

  test('a viewBox away from the origin is moved to it; without a <g> the paths are as written', () {
    final shape = MaskShape.parse('<svg viewBox="10 20 100 50"><path d="M10 20 h10 v10 h-10 z"/></svg>');

    expect(shape.box, const Size(100, 50));
    expectRect(shape.toPath().getBounds(), const Rect.fromLTRB(0, 0, 10, 10));
  });

  test('without a viewBox the width and height size the box', () {
    final shape = MaskShape.parse('<svg width="180pt" height="320pt"><path d="M0 0 h10 v10 h-10 z"/></svg>');

    expect(shape.box, const Size(180, 320));
  });

  test('a matrix() transform and a single-value scale', () {
    final matrix = MaskShape.parse(
      '<svg viewBox="0 0 100 100"><g transform="matrix(2 0 0 2 5 5)"><path d="M0 0 h10 v10 h-10 z"/></g></svg>',
    );
    expectRect(matrix.toPath().getBounds(), const Rect.fromLTRB(5, 5, 25, 25));

    final scale = MaskShape.parse(
      '<svg viewBox="0 0 100 100"><g transform="scale(3)"><path d="M1 1 h10 v10 h-10 z"/></g></svg>',
    );
    expectRect(scale.toPath().getBounds(), const Rect.fromLTRB(3, 3, 33, 33));
  });

  test('no size, no path or a transform it doesn\'t know is a FormatException', () {
    expect(() => MaskShape.parse('<svg><path d="M0 0 h1 v1z"/></svg>'), throwsFormatException);
    expect(() => MaskShape.parse('<svg viewBox="0 0 180 320"><g></g></svg>'), throwsFormatException);
    expect(() => MaskShape.parse('<svg viewBox="0 0 180 320"><path id="x"/></svg>'), throwsFormatException);
    expect(
      () => MaskShape.parse('<svg viewBox="0 0 180 320"><g transform="rotate(90)"><path d="M0 0 h1 v1z"/></g></svg>'),
      throwsFormatException,
    );
    expect(() => MaskShape.parse('not svg'), throwsFormatException);
  });
}
