import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';

/// 弹幕设置's glyphs (07, 08, 29, 41), drawn from the screenshots at 3 px per point: the five 按弹幕类型屏蔽 types,
/// the ⊘ on a blocked one, ↻ and the chevrons. Neither the borrowed font nor Material has them.
class DanmakuPanelGlyph extends StatelessWidget {
  const DanmakuPanelGlyph(this.kind, {super.key, required this.color, this.blocked = false});

  final DanmakuGlyphKind kind;
  final Color color;

  /// A type glyph with the ⊘, its outline cut away round it.
  final bool blocked;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: kind.size,
    painter: _DanmakuGlyphPainter(kind, color, blocked: blocked),
  );
}

const _typeSize = Size(DanmakuPanelTheme.glyphWidth, DanmakuPanelTheme.glyphHeight);

enum DanmakuGlyphKind {
  fixed(_typeSize),
  scroll(_typeSize),
  colored(_typeSize),
  advanced(_typeSize),
  count(_typeSize),
  reset(Size(DanmakuPanelTheme.resetGlyphWidth, DanmakuPanelTheme.resetGlyphHeight)),
  chevronDown(Size(DanmakuPanelTheme.chevronDownWidth, DanmakuPanelTheme.chevronDownHeight)),
  buttonChevron(Size(DanmakuPanelTheme.buttonChevronWidth, DanmakuPanelTheme.buttonChevronHeight)),
  listChevron(Size(DanmakuPanelTheme.listChevronWidth, DanmakuPanelTheme.listChevronHeight));

  const DanmakuGlyphKind(this.size);

  final Size size;
}

class _DanmakuGlyphPainter extends CustomPainter {
  _DanmakuGlyphPainter(this.kind, this.color, {required this.blocked});

  final DanmakuGlyphKind kind;
  final Color color;
  final bool blocked;

  Paint _line(double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  Paint get _fill => Paint()..color = color;

  @override
  void paint(Canvas canvas, Size size) {
    switch (kind) {
      case DanmakuGlyphKind.fixed ||
          DanmakuGlyphKind.scroll ||
          DanmakuGlyphKind.colored ||
          DanmakuGlyphKind.advanced ||
          DanmakuGlyphKind.count:
        _type(canvas, size);
      case DanmakuGlyphKind.reset:
        _reset(canvas);
      case DanmakuGlyphKind.chevronDown:
        final inset = DanmakuPanelTheme.chevronStroke / 2;
        canvas.drawPath(
          Path()
            ..moveTo(inset, inset)
            ..lineTo(size.width / 2, size.height - inset)
            ..lineTo(size.width - inset, inset),
          _line(DanmakuPanelTheme.chevronStroke),
        );
      case DanmakuGlyphKind.buttonChevron || DanmakuGlyphKind.listChevron:
        final inset = DanmakuPanelTheme.chevronStroke / 2;
        canvas.drawPath(
          Path()
            ..moveTo(inset, inset)
            ..lineTo(size.width - inset, size.height / 2)
            ..lineTo(inset, size.height - inset),
          _line(DanmakuPanelTheme.chevronStroke),
        );
    }
  }

  void _type(Canvas canvas, Size size) {
    // The ⊘ cuts the screen's outline away round itself, so the outline goes on a layer the cut can clear.
    canvas.saveLayer((Offset.zero & size).inflate(DanmakuPanelTheme.badgeClear), Paint());
    _screen(canvas, size);
    switch (kind) {
      case DanmakuGlyphKind.fixed:
        _rows(canvas, const [(4.2, 7.3, 16.7, 6.5)]);
      case DanmakuGlyphKind.scroll:
        _rows(canvas, const [(6.2, 9.3, 19.0, 6.4), (8.5, 11.7, 21.3, 11.0)]);
      case DanmakuGlyphKind.colored:
        _palette(canvas);
      case DanmakuGlyphKind.advanced:
        _advanced(canvas);
      case DanmakuGlyphKind.count:
        _count(canvas);
      default:
        break;
    }
    if (blocked) {
      canvas.drawCircle(
        DanmakuPanelTheme.badgeCentre,
        DanmakuPanelTheme.badgeClear,
        Paint()..blendMode = BlendMode.clear,
      );
    }
    canvas.restore();
    if (blocked) _badge(canvas);
  }

  /// The rounded screen every type glyph is drawn in.
  void _screen(Canvas canvas, Size size) {
    const half = DanmakuPanelTheme.glyphStroke / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(half, half, size.width - half, size.height - half),
        const Radius.circular(4.25),
      ),
      _line(DanmakuPanelTheme.glyphStroke),
    );
  }

  /// A dot then a bar per row: (dot x, bar start, bar end, y).
  void _rows(Canvas canvas, List<(double, double, double, double)> rows) {
    final paint = _line(DanmakuPanelTheme.markStroke);
    for (final (dot, from, to, y) in rows) {
      canvas.drawLine(Offset(dot - 0.4, y), Offset(dot + 0.4, y), paint);
      canvas.drawLine(Offset(from, y), Offset(to, y), paint);
    }
  }

  /// 彩色: a palette with its thumb hole at the lower left and three dots of paint.
  void _palette(Canvas canvas) {
    const centre = Offset(12.5, 11.18);
    const radius = 6.8;
    const start = 165 * math.pi / 180;
    const end = 99 * math.pi / 180;
    final from = centre + Offset(math.cos(start), math.sin(start)) * radius;
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..arcTo(Rect.fromCircle(center: centre, radius: radius), start, 2 * math.pi - (start - end), false)
      ..quadraticBezierTo(10.4, 16.6, 10.5, 15.2)
      ..cubicTo(10.5, 13.9, 7.6, 13.1, from.dx, from.dy)
      ..close();
    canvas.drawPath(path, _line(DanmakuPanelTheme.glyphStroke));
    for (final dot in const [Offset(12.0, 8.6), Offset(16.0, 9.2), Offset(15.7, 12.8)]) {
      canvas.drawOval(Rect.fromCenter(center: dot, width: 2.6, height: 2.9), _fill);
    }
  }

  /// 高级: two rows, each a star then a bar.
  void _advanced(Canvas canvas) {
    final paint = _line(DanmakuPanelTheme.markStroke);
    for (final (star, from, to, y) in const [(6.83, 10.9, 18.1, 7.33), (8.5, 12.9, 20.1, 13.33)]) {
      _star(canvas, Offset(star, y + 0.2));
      canvas.drawLine(Offset(from, y), Offset(to, y), paint);
    }
  }

  void _star(Canvas canvas, Offset centre) {
    final path = Path();
    for (var point = 0; point < 10; point++) {
      final radius = point.isEven ? 2.2 : 0.95;
      final angle = point * math.pi / 5 - math.pi / 2;
      final spot = centre + Offset(math.cos(angle), math.sin(angle)) * radius;
      if (point == 0) {
        path.moveTo(spot.dx, spot.dy);
      } else {
        path.lineTo(spot.dx, spot.dy);
      }
    }
    path.close();
    canvas.drawPath(path, _fill);
    canvas.drawPath(path, _line(0.4));
  }

  /// 计数: ×99, the 99 heavy and slanted. Drawn rather than set in a font, since MiSans has no heavy italic.
  void _count(Canvas canvas) {
    final cross = _line(1.3);
    canvas.drawLine(const Offset(4.5, 11.15), const Offset(7.5, 13.85), cross);
    canvas.drawLine(const Offset(7.5, 11.15), const Offset(4.5, 13.85), cross);
    final stroke = _line(2.0);
    for (final left in const [10.85, 16.2]) {
      // Each nine upright from (left, 6.83), then slanted 0.15 of its height.
      final slant = Matrix4.identity()
        ..translateByDouble(left, 6.83, 0, 1)
        ..multiply(Matrix4.skewX(-0.15))
        ..translateByDouble(1.25, 0, 0, 1);
      canvas.save();
      canvas.transform(slant.storage);
      canvas.drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addOval(Rect.fromCenter(center: const Offset(2.35, 2.75), width: 4.9, height: 5.5))
          ..addOval(Rect.fromCenter(center: const Offset(2.45, 2.65), width: 0.9, height: 2.6)),
        _fill,
      );
      canvas.drawPath(
        Path()
          ..moveTo(3.75, 2.7)
          ..lineTo(3.75, 5.7)
          ..quadraticBezierTo(3.75, 7.4, 2.0, 7.4)
          ..quadraticBezierTo(1.0, 7.4, 0.95, 6.6),
        stroke,
      );
      canvas.restore();
    }
  }

  void _badge(Canvas canvas) {
    const centre = DanmakuPanelTheme.badgeCentre;
    const radius = DanmakuPanelTheme.badgeRadius;
    final paint = _line(DanmakuPanelTheme.glyphStroke);
    canvas.drawCircle(centre, radius, paint);
    final reach = radius * math.sqrt1_2;
    canvas.drawLine(centre - Offset(reach, reach), centre + Offset(reach, reach), paint..strokeCap = StrokeCap.butt);
  }

  /// ↻: two arcs round the middle, each ending in a corner.
  void _reset(Canvas canvas) {
    const centre = Offset(6.0, 6.16);
    const radius = 5.3;
    final paint = _line(DanmakuPanelTheme.resetStroke);
    const degree = math.pi / 180;
    final circle = Rect.fromCircle(center: centre, radius: radius);
    canvas.drawArc(circle, -113 * degree, -175 * degree, false, paint);
    canvas.drawArc(circle, -84 * degree, 132 * degree, false, paint);
    canvas.drawPath(
      Path()
        ..moveTo(0.9, 1.5)
        ..lineTo(4.0, 1.5)
        ..lineTo(4.0, 4.6),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(10.0, 7.7)
        ..lineTo(10.0, 10.8)
        ..lineTo(13.1, 10.8),
      paint,
    );
  }

  @override
  bool shouldRepaint(_DanmakuGlyphPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color || oldDelegate.blocked != blocked;
}
