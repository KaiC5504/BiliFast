import 'dart:ui' as ui;

import 'package:bilifast/shared/action_glyphs.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _white = Color(0xFFFFFFFF);
const _scale = 3.0;

/// The painted pixels of one icon, in points.
final class Ink {
  Ink(this.bounds, this.count, this._alpha, this._width);

  final Rect bounds;
  final int count;
  final List<int> _alpha;
  final int _width;

  bool paintedAt(Offset point) => _alpha[(point.dy * _scale).floor() * _width + (point.dx * _scale).floor()] > 128;
}

Future<Ink> render(WidgetTester tester, ActionGlyph glyph, {required bool solid, required double size}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: key,
          child: ActionIcon(glyph, solid: solid, size: size, color: _white),
        ),
      ),
    ),
  );
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _scale);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final width = image.width, height = image.height;
    final alpha = List<int>.generate(width * height, (i) => bytes.getUint8(i * 4 + 3));
    var left = width, top = height, right = -1, bottom = -1, count = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (alpha[y * width + x] <= 128) continue;
        count++;
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
    image.dispose();
    final bounds = right < 0
        ? Rect.zero
        : Rect.fromLTRB(left / _scale, top / _scale, (right + 1) / _scale, (bottom + 1) / _scale);
    return Ink(bounds, count, alpha, width);
  }))!;
}

void main() {
  for (final size in const [24.0, 36.0]) {
    for (final solid in const [true, false]) {
      testWidgets('every glyph is centred in its ${size}pt square, ${solid ? 'solid' : 'outlined'}', (tester) async {
        final ink = size * ActionIcon.inkShare;
        for (final glyph in ActionGlyph.values) {
          final painted = await render(tester, glyph, solid: solid, size: size);
          expect(painted.count, greaterThan(0), reason: '$glyph paints');
          final centre = painted.bounds.center;
          // 03 draws the thumbs-down a tenth of the glyph lower than the thumbs-up.
          final expectedY = size / 2 + (glyph == ActionGlyph.dislike ? ink * 0.1 : 0);
          expect(centre.dx, closeTo(size / 2, size * 0.04), reason: '$glyph x');
          expect(centre.dy, closeTo(expectedY, size * 0.05), reason: '$glyph y');
          expect(painted.bounds.width, lessThanOrEqualTo(ink + 1), reason: '$glyph width');
          expect(painted.bounds.height, lessThanOrEqualTo(ink + 1), reason: '$glyph height');
          if (glyph != ActionGlyph.charge) {
            expect(painted.bounds.width, greaterThan(ink * 0.92), reason: '$glyph fills the ink width');
          }
        }
      });
    }
  }

  testWidgets('the coin is a 0.84 x size disc with the 币 cut out when solid, drawn as lines when outlined', (
    tester,
  ) async {
    const size = 30.0;
    final solid = await render(tester, ActionGlyph.coin, solid: true, size: size);
    expect(solid.bounds.width, closeTo(size * ActionIcon.inkShare, 0.7));
    expect(solid.bounds.height, closeTo(size * ActionIcon.inkShare, 0.7));
    final box = Rect.fromCenter(
      center: const Offset(size / 2, size / 2),
      width: size * ActionIcon.inkShare,
      height: size * ActionIcon.inkShare,
    );
    Offset at(double u, double v) => Offset(box.left + u * box.width, box.top + v * box.height);
    expect(solid.paintedAt(at(0.494, 0.6)), isFalse, reason: 'the stem is cut out');
    expect(solid.paintedAt(at(0.15, 0.5)), isTrue, reason: 'the disc is filled');

    final outline = await render(tester, ActionGlyph.coin, solid: false, size: size);
    expect(outline.paintedAt(at(0.494, 0.6)), isTrue, reason: 'the stem is drawn');
    expect(outline.paintedAt(at(0.15, 0.5)), isFalse, reason: 'the ring is hollow');
  });

  testWidgets('outlined glyphs, the share arrow among them, are hollow versions of the solid ones', (tester) async {
    for (final glyph in ActionGlyph.values) {
      final solid = await render(tester, glyph, solid: true, size: 36);
      final outline = await render(tester, glyph, solid: false, size: 36);
      expect(outline.count, lessThan(solid.count * 0.7), reason: '$glyph');
      expect(outline.bounds.width, closeTo(solid.bounds.width, 1.5), reason: '$glyph keeps its width');
    }
  });

  testWidgets('the icon is decoration only for accessibility', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Semantics(
          label: '点赞',
          child: const ActionIcon(ActionGlyph.like, solid: true, size: 24, color: _white),
        ),
      ),
    );
    expect(find.bySemanticsLabel('点赞'), findsOneWidget);
    expect(tester.getSemantics(find.byType(ActionIcon)).label, '点赞');
    semantics.dispose();
  });

  test('the painter repaints only when what it draws changes', () {
    final painter = ActionGlyphPainter(ActionGlyph.like, solid: true, color: _white);
    expect(painter.shouldRepaint(ActionGlyphPainter(ActionGlyph.like, solid: true, color: _white)), isFalse);
    expect(painter.shouldRepaint(ActionGlyphPainter(ActionGlyph.like, solid: false, color: _white)), isTrue);
    expect(painter.shouldRepaint(ActionGlyphPainter(ActionGlyph.coin, solid: true, color: _white)), isTrue);
    expect(
      painter.shouldRepaint(ActionGlyphPainter(ActionGlyph.like, solid: true, color: const Color(0xFFFF6699))),
      isTrue,
    );
  });
}
