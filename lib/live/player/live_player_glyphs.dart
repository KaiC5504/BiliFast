import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';

/// 222's icons the APK doesn't carry, traced off the screenshot on the disc's 42 pt grid.
enum LiveGlyph {
  /// 助TA必火: a flame with a bolt in it.
  flame,

  /// 消费管理: a shield with ¥ in it.
  shield,
}

class LiveDrawnGlyph extends StatelessWidget {
  const LiveDrawnGlyph(this.glyph, {super.key});

  final LiveGlyph glyph;

  @override
  Widget build(BuildContext context) => CustomPaint(
    key: ValueKey('live-glyph-${glyph.name}'),
    size: const Size.square(LivePlayerTheme.moreDisc),
    painter: _GlyphPainter(glyph),
  );
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.glyph);

  final LiveGlyph glyph;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / LivePlayerTheme.moreDisc;
    canvas.scale(scale);
    final line = Paint()
      ..color = BiliColors.panelText
      ..style = PaintingStyle.stroke
      ..strokeWidth = LivePlayerTheme.drawnStroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    switch (glyph) {
      case LiveGlyph.flame:
        _flame(canvas, line);
      case LiveGlyph.shield:
        _shield(canvas, line);
    }
  }

  static void _flame(Canvas canvas, Paint line) {
    // The outline: a round base, a tall tongue on the left, a short one on the right.
    final flame = Path()
      ..moveTo(21, 31.3)
      ..cubicTo(15.6, 31.3, 12, 27.6, 12, 23.2)
      ..cubicTo(12, 19.4, 14, 17.2, 15.6, 15.8)
      ..lineTo(16.8, 18.6)
      ..cubicTo(17.4, 14.6, 19.4, 11.4, 21.6, 9.2)
      ..cubicTo(22.4, 12.6, 24.2, 15.2, 26.2, 17.4)
      ..lineTo(27.2, 15.2)
      ..cubicTo(29, 17.2, 30, 19.8, 30, 23)
      ..cubicTo(30, 27.6, 26.4, 31.3, 21, 31.3)
      ..close();
    canvas.drawPath(flame, line);
    final bolt = Path()
      ..moveTo(21.6, 20)
      ..lineTo(18.8, 24.1)
      ..lineTo(21.2, 24.1)
      ..lineTo(20.4, 27.2)
      ..lineTo(23.2, 23.1)
      ..lineTo(20.8, 23.1)
      ..close();
    canvas.drawPath(bolt, Paint()..color = BiliColors.panelText);
  }

  static void _shield(Canvas canvas, Paint line) {
    final shield = Path()
      ..moveTo(21, 10)
      ..lineTo(29.8, 13.4)
      ..lineTo(29.8, 21.4)
      ..cubicTo(29.8, 26.4, 25.8, 30.2, 21, 32)
      ..cubicTo(16.2, 30.2, 12.2, 26.4, 12.2, 21.4)
      ..lineTo(12.2, 13.4)
      ..close();
    canvas.drawPath(shield, line);
    // ¥: the V, the stem and two bars.
    canvas
      ..drawPath(
        Path()
          ..moveTo(18.2, 16.6)
          ..lineTo(21, 20.4)
          ..lineTo(23.8, 16.6),
        line,
      )
      ..drawLine(const Offset(21, 20.4), const Offset(21, 26.2), line)
      ..drawLine(const Offset(18.6, 21.4), const Offset(23.4, 21.4), line)
      ..drawLine(const Offset(18.6, 23.8), const Offset(23.4, 23.8), line);
  }

  @override
  bool shouldRepaint(_GlyphPainter oldDelegate) => oldDelegate.glyph != glyph;
}
