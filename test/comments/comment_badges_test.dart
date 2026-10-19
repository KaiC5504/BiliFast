import 'dart:ui' as ui;

import 'package:bili_core/api.dart' show CommentMember;
import 'package:bilifast/comments/comment_badges.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// [child] drawn at 3× on transparency; answers the colour at a point in its own coordinates.
Future<Color Function(Offset)> _draw(WidgetTester tester, Widget child) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(key: key, child: child),
      ),
    ),
  );
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: 3)))!;
  final bytes = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
  final width = image.width;
  return (Offset point) {
    final i = ((point.dy * 3).floor() * width + (point.dx * 3).floor()) * 4;
    return Color.fromARGB(bytes.getUint8(i + 3), bytes.getUint8(i), bytes.getUint8(i + 1), bytes.getUint8(i + 2));
  };
}

void main() {
  test('1 is narrow and a full stop narrower; the rest share one width', () {
    double advance(String character) => SegmentGlyph.advance(character, width: 4, weight: 1, gap: 1);
    expect(advance('0'), 5);
    expect(advance('7'), 5);
    expect(advance('N'), 5);
    expect(advance('1'), lessThan(advance('0')));
    expect(advance('.'), 2);
  });

  test('a fan card colour is read only as #rrggbb', () {
    expect(FanCard.cssColour('#f35543'), const Color(0xFFF35543));
    expect(FanCard.cssColour('#ABB4BD'), const Color(0xFFABB4BD));
    for (final css in [null, '', 'f35543', '#f355', '#f35543ff', '#zzzzzz']) {
      expect(FanCard.cssColour(css), isNull, reason: '$css');
    }
  });

  testWidgets('the fan number is two lines, as wide as its longer one', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: FanNumber(number: '017949', color: CommentRowTheme.fanNumber),
        ),
      ),
    );
    final size = tester.getSize(find.byType(FanNumber));
    const w = CommentRowTheme.fanGlyphWidth, gap = CommentRowTheme.fanGlyphGap;
    final narrow = SegmentGlyph.glyphWidth('1', width: w, weight: CommentRowTheme.fanGlyphWeight);
    expect(size.width, closeTo(5 * w + narrow + 5 * gap, 0.01));
    expect(size.height, closeTo(CommentRowTheme.fanGlyphHeight * 2 + CommentRowTheme.fanLineGap, 0.01));
  });

  testWidgets('each level has its colour, with white letters', (tester) async {
    for (final level in [0, 3, 5, 6]) {
      final at = await _draw(tester, LevelBadge(level: level));
      expect(at(const Offset(0.6, 8.5)), CommentRowTheme.levels[level], reason: 'LV$level fill');
      expect(at(const Offset(1.3 * 28 / 27 + 0.5, 5)), CommentRowTheme.levelInk, reason: 'LV$level L');
    }
  });

  test('LV5 and LV6 take the fills sampled on 10 and 13', () {
    expect(CommentRowTheme.levels[5], const Color(0xFFDF6729));
    expect(CommentRowTheme.levels[6], const Color(0xFFE3524E));
  });

  testWidgets('an avatar without a face, or one still loading, is Bilibili\'s default', (tester) async {
    for (final face in ['', 'https://i0.hdslb.com/bfs/face/a.jpg']) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: CommentAvatar(member: CommentMember(mid: 1, name: 'a', face: face)),
          ),
        ),
      );
      expect(find.byType(DefaultAvatar), findsOneWidget, reason: face);
    }
  });

  testWidgets('a pressed thumb is solid, an unpressed one outlined', (tester) async {
    const ink = Color(0xFF61666D);
    final outline = await _draw(tester, const CommentThumb(color: ink));
    final solid = await _draw(tester, const CommentThumb(color: ink, solid: true));
    const palm = Offset(9, 9);
    expect(outline(palm).a, 0);
    expect(solid(palm), ink);
    expect(tester.getSize(find.byType(CommentThumb)).width, CommentRowTheme.thumbInk);
  });

  testWidgets('👎 is 👍 upside down', (tester) async {
    const ink = Color(0xFF61666D);
    final up = await _draw(tester, const CommentThumb(color: ink, solid: true));
    final down = await _draw(tester, const CommentThumb(color: ink, solid: true, down: true));
    final height = tester.getSize(find.byType(CommentThumb)).height;
    // The fingertip is top middle on 👍 and bottom middle on 👎; the cuff starts lower on 👍 and at the top on 👎.
    expect(up(const Offset(8, 1)), ink);
    expect(down(Offset(8, height - 1)), ink);
    expect(up(const Offset(2, 1)).a, 0);
    expect(down(const Offset(2, 1)), ink);
  });
}
