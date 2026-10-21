import 'package:bilifast/search/search_glyphs.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _ink = Color(0xFF61666D);
const _margin = 3.0;

/// The glyph drawn at 3× on white with a [_margin] pt border round its square: how many pixels are inked, and the
/// inked box in pt relative to the square's centre.
Future<(int, Rect)> _render(WidgetTester tester, SearchGlyph glyph, double size) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Center(
      child: RepaintBoundary(
        key: key,
        child: ColoredBox(
          color: const Color(0xFFFFFFFF),
          child: Padding(
            padding: const EdgeInsets.all(_margin),
            child: SearchGlyphIcon(glyph, size: size, color: _ink),
          ),
        ),
      ),
    ),
  );
  expect(tester.takeException(), isNull);
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  var inked = 0;
  var left = 1 << 30, top = 1 << 30, right = -1, bottom = -1;
  late double half;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = (await image.toByteData())!;
    final width = image.width, height = image.height;
    half = width / 2;
    image.dispose();
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        // A size that isn't a whole number of pixels leaves a see-through last row and column; skip them.
        final i = (y * width + x) * 4;
        if (bytes.getUint8(i + 3) > 128 && bytes.getUint8(i + 1) < 230) {
          inked++;
          if (x < left) left = x;
          if (x > right) right = x;
          if (y < top) top = y;
          if (y > bottom) bottom = y;
        }
      }
    }
  });
  return (inked, Rect.fromLTRB((left - half) / 3, (top - half) / 3, (right + 1 - half) / 3, (bottom + 1 - half) / 3));
}

void main() {
  testWidgets('every glyph paints, its ink filling its measured size, centred', (tester) async {
    for (final glyph in SearchGlyph.values) {
      final (inked, box) = await _render(tester, glyph, glyph.designSize);
      expect(inked, greaterThan(40), reason: '$glyph draws');
      final side = box.width > box.height ? box.width : box.height;
      expect(side, closeTo(glyph.designSize, 0.7), reason: '$glyph ink $box');
      expect(box.center.dx, closeTo(0, 0.5), reason: '$glyph ink $box');
      expect(box.center.dy, closeTo(0, 0.5), reason: '$glyph ink $box');
    }
  });

  testWidgets('glyphs scale with the size they are given', (tester) async {
    for (final glyph in SearchGlyph.values) {
      final (small, _) = await _render(tester, glyph, glyph.designSize);
      final (large, _) = await _render(tester, glyph, glyph.designSize * 2);
      expect(large, greaterThan(small * 2.5), reason: '$glyph');
    }
  });

  testWidgets('the eye with its slash differs from the open eye', (tester) async {
    final (eye, _) = await _render(tester, SearchGlyph.eye, 30);
    final (eyeOff, _) = await _render(tester, SearchGlyph.eyeOff, 30);
    expect(eyeOff, isNot(eye));
  });

  testWidgets('a zero size paints nothing and throws nothing', (tester) async {
    await tester.pumpWidget(const Center(child: SearchGlyphIcon(SearchGlyph.funnel, size: 0, color: _ink)));
    expect(tester.takeException(), isNull);
  });
}
