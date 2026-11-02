import 'dart:ui' show PathMetric;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

import '../../comments/comment_badges.dart' show SegmentGlyph;
import '../../shared/theme.dart';

/// 👕 at the banner's foot (108), traced in a 52 × 46 grid of the 3× screenshot: collar, sleeves and body in one line.
class OwnSkinGlyph extends StatelessWidget {
  const OwnSkinGlyph({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: const Size(OwnSpaceTheme.skinWidth, OwnSpaceTheme.skinHeight),
      painter: _SkinPainter(color),
    ),
  );
}

class _SkinPainter extends CustomPainter {
  const _SkinPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 52, y = size.height / 46;
    final path = Path()..moveTo(11 * x, 20.5 * y);
    void line(double gx, double gy) => path.lineTo(gx * x, gy * y);
    void curve(double cx, double cy, double gx, double gy) => path.quadraticBezierTo(cx * x, cy * y, gx * x, gy * y);
    line(2.2, 17);
    line(11, 2.2);
    line(17, 2.2);
    curve(21, 11, 26, 11);
    curve(31, 11, 35, 2.2);
    line(41, 2.2);
    line(49.8, 17);
    line(41, 20.5);
    line(41, 40.5);
    curve(41, 43.8, 37.7, 43.8);
    line(14.3, 43.8);
    curve(11, 43.8, 11, 40.5);
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = OwnSpaceTheme.skinStroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SkinPainter oldDelegate) => oldDelegate.color != color;
}

/// The banner label's number ("NO.000067", 108; "CD.013149", 24) in the block letters of 评论's fan card, ending at
/// the box's right.
class OwnLabelNumber extends StatelessWidget {
  const OwnLabelNumber({super.key, required this.text, required this.color, this.shading = const []});

  final String text;
  final Color color;

  /// Two or more colours shade the letters left to right across the number's width, as 24's CD.013149 goes from
  /// #EBF3F7 to #CEE2EC; fewer leave it flat [color].
  final List<Color> shading;

  /// Whether every character of [text] has a block letter; anything else is set as type.
  static bool draws(String text) =>
      text.isNotEmpty && text.split('').every((character) => _segments.contains(character) || _Capitals.has(character));

  /// What [SegmentGlyph] spells; [_Capitals] has the other capitals.
  static const _segments = {'0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'N', 'O', 'C', 'L', 'V', '.'};

  static double _glyphWidth(String character) => _Capitals.has(character)
      ? _Capitals.width(character)
      : SegmentGlyph.glyphWidth(
          character,
          width: OwnSpaceTheme.labelNumberWidth,
          weight: OwnSpaceTheme.labelNumberWeight,
        );

  static double widthOf(String text) {
    var width = 0.0;
    for (final character in text.split('')) {
      width += _glyphWidth(character) + OwnSpaceTheme.labelNumberGap;
    }
    return text.isEmpty ? 0 : width - OwnSpaceTheme.labelNumberGap;
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: text,
    child: CustomPaint(
      size: Size(widthOf(text), OwnSpaceTheme.labelNumberHeight),
      painter: _NumberPainter(text, color, shading),
    ),
  );
}

class _NumberPainter extends CustomPainter {
  const _NumberPainter(this.text, this.color, this.shading);

  final String text;
  final Color color;
  final List<Color> shading;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()..color = color;
    if (shading.length >= 2) ink.shader = LinearGradient(colors: shading).createShader(Offset.zero & size);
    var left = 0.0;
    for (final character in text.split('')) {
      final width = OwnLabelNumber._glyphWidth(character);
      final box = Rect.fromLTWH(left, 0, width, size.height);
      if (_Capitals.has(character)) {
        _Capitals.draw(canvas, character, box, ink);
      } else {
        SegmentGlyph.draw(canvas, character, box, OwnSpaceTheme.labelNumberWeight, ink);
      }
      left += width + OwnSpaceTheme.labelNumberGap;
    }
  }

  @override
  bool shouldRepaint(_NumberPainter oldDelegate) =>
      oldDelegate.text != text || oldDelegate.color != color || !listEquals(oldDelegate.shading, shading);
}

/// The capitals [SegmentGlyph] lacks, in its style: bars on the seven-segment grid, slanted strokes as wide across as
/// its N's, and D (and B) with their right corners cut as 24's CD.013149 draws them. A collection's number is a
/// prefix of capitals, a dot and digits.
abstract final class _Capitals {
  static const _letters = 'ABDEFGHIJKMPQRSTUWXYZ';

  /// A slanted stroke's breadth across, against a straight one's, as SegmentGlyph's.
  static const _slant = 1.4;

  static bool has(String character) => character.length == 1 && _letters.contains(character);

  static double width(String character) =>
      character == 'I' ? OwnSpaceTheme.labelNumberWeight : OwnSpaceTheme.labelNumberWidth;

  static void draw(Canvas canvas, String character, Rect box, Paint ink) {
    const w = OwnSpaceTheme.labelNumberWeight;
    final half = box.height / 2;
    final mid = box.top + half;
    final across = w * _slant;
    final stem = box.center.dx - w / 2;
    void bar(Rect rect) => canvas.drawRect(rect, ink);
    void band(Offset from, Offset to) =>
        canvas.drawPath(Path()..addPolygon([from, from.translate(across, 0), to.translate(across, 0), to], true), ink);
    final a = Rect.fromLTWH(box.left, box.top, box.width, w);
    final d = Rect.fromLTWH(box.left, box.bottom - w, box.width, w);
    final g = Rect.fromLTWH(box.left, mid - w / 2, box.width, w);
    final f = Rect.fromLTWH(box.left, box.top, w, half + w / 2);
    final e = Rect.fromLTWH(box.left, mid - w / 2, w, half + w / 2);
    final b = Rect.fromLTWH(box.right - w, box.top, w, half + w / 2);
    final c = Rect.fromLTWH(box.right - w, mid - w / 2, w, half + w / 2);
    final stemDown = Rect.fromLTRB(stem, mid - w / 2, stem + w, box.bottom);
    switch (character) {
      case 'A':
        [a, b, c, e, f, g].forEach(bar);
      case 'B':
        _cut(canvas, box, ink, holes: 2);
      case 'D':
        _cut(canvas, box, ink, holes: 1);
      case 'E':
        [a, d, e, f, g].forEach(bar);
      case 'F':
        [a, e, f, g].forEach(bar);
      case 'G':
        [a, c, d, e, f, Rect.fromLTRB(box.center.dx, mid - w / 2, box.right, mid + w / 2)].forEach(bar);
      case 'H':
        [b, c, e, f, g].forEach(bar);
      case 'I':
        bar(box);
      case 'J':
        [b, c, d, Rect.fromLTRB(box.left, box.bottom - box.height * 0.35, box.left + w, box.bottom)].forEach(bar);
      case 'K':
        [e, f].forEach(bar);
        band(Offset(box.left + w * 0.6, mid - w / 2), Offset(box.right - across, box.top));
        band(Offset(box.left + w * 0.6, mid - w / 2), Offset(box.right - across, box.bottom));
      case 'M':
        [b, c, e, f].forEach(bar);
        band(box.topLeft, Offset(box.center.dx - across / 2, mid));
        band(Offset(box.right - across, box.top), Offset(box.center.dx - across / 2, mid));
      case 'P':
        [a, b, e, f, g].forEach(bar);
      case 'Q':
        [a, b, c, d, e, f].forEach(bar);
        band(Offset(box.center.dx - across / 2, mid), Offset(box.right - across, box.bottom));
      case 'R':
        [a, b, e, f, g].forEach(bar);
        band(Offset(box.center.dx - across / 2, mid), Offset(box.right - across, box.bottom));
      case 'S':
        [a, c, d, f, g].forEach(bar);
      case 'T':
        [a, Rect.fromLTRB(stem, box.top, stem + w, box.bottom)].forEach(bar);
      case 'U':
        [b, c, d, e, f].forEach(bar);
      case 'W':
        [b, c, d, e, f, stemDown].forEach(bar);
      case 'X':
        band(box.topLeft, Offset(box.right - across, box.bottom));
        band(Offset(box.right - across, box.top), box.bottomLeft);
      case 'Y':
        [b, f, g, stemDown].forEach(bar);
      case 'Z':
        [a, d].forEach(bar);
        band(Offset(box.right - across, box.top + w), Offset(box.left, box.bottom - w));
    }
  }

  /// D's and B's outline: a block with its right corners cut, less one hollow (D) or two over a middle bar (B).
  static void _cut(Canvas canvas, Rect box, Paint ink, {required int holes}) {
    const w = OwnSpaceTheme.labelNumberWeight;
    const cut = OwnSpaceTheme.labelNumberChamfer;
    final shape = Path()
      ..fillType = PathFillType.evenOdd
      ..addPolygon([
        box.topLeft,
        Offset(box.right - cut, box.top),
        Offset(box.right, box.top + cut),
        Offset(box.right, box.bottom - cut),
        Offset(box.right - cut, box.bottom),
        box.bottomLeft,
      ], true);
    final inside = box.deflate(w);
    if (holes == 1) {
      shape.addRect(inside);
    } else {
      final middle = box.center.dy;
      shape
        ..addRect(Rect.fromLTRB(inside.left, inside.top, inside.right, middle - w / 2))
        ..addRect(Rect.fromLTRB(inside.left, middle + w / 2, inside.right, inside.bottom));
    }
    canvas.drawPath(shape, ink);
  }
}

/// The 勋章 pills' rim: a stadium of dashes drawn inside its box.
class OwnDashedPillPainter extends CustomPainter {
  const OwnDashedPillPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const inset = OwnSpaceTheme.pillBorder / 2;
    final box = Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2);
    final outline = Path()..addRRect(RRect.fromRectAndRadius(box, Radius.circular(box.height / 2)));
    final paint = Paint()
      ..color = OwnSpaceTheme.pillRim
      ..style = PaintingStyle.stroke
      ..strokeWidth = OwnSpaceTheme.pillBorder;
    for (final PathMetric metric in outline.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += OwnSpaceTheme.pillDash + OwnSpaceTheme.pillDashGap) {
        canvas.drawPath(metric.extractPath(at, at + OwnSpaceTheme.pillDash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(OwnDashedPillPainter oldDelegate) => false;
}
