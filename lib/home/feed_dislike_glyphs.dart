import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/widgets.dart';

import '../shared/theme.dart';

/// The line drawings of 推荐's ⋮ sheet (90), the reasons sheet (92) and the card after 不感兴趣 (91), traced off the
/// official shots in pt about the middle of their ink.
enum FeedDislikeGlyph {
  /// 不感兴趣：当前视频: a player frame, open at its lower right, with ⊘.
  videoOff,

  /// 不感兴趣：UP: a head and shoulder with ⊘.
  uploaderOff,

  /// 该内容已推荐过: two stacked frames with ⊘.
  repeatedOff,

  /// 色情低俗: a checker in a frame.
  explicit,

  /// 引战对立: two speech bubbles, ! in the front one.
  conflict,

  /// 恐怖血腥: a startled ghost.
  horror,

  /// 恶心猎奇: a face hiding its eyes.
  gross,

  /// 广告营销: a loudhailer.
  advert,

  /// 负能量: a bowed head.
  negative,

  /// 搬运拼剪: a dashed frame with ▶ over another.
  reupload,

  /// 标题/封面党 and any reason without its own drawing: ! in a frame.
  clickbait,

  /// 撤销's ↶.
  undo,

  /// 选择不感兴趣原因's ›.
  chevron;

  /// A 反馈 reason's tile drawing, from its name.
  static FeedDislikeGlyph forReason(String name) {
    bool has(List<String> words) => words.any(name.contains);
    if (has(['色情', '低俗'])) return explicit;
    if (has(['引战', '对立'])) return conflict;
    if (has(['恐怖', '血腥'])) return horror;
    if (has(['恶心', '猎奇'])) return gross;
    if (has(['广告', '营销'])) return advert;
    if (has(['负能量'])) return negative;
    if (has(['搬运', '拼剪'])) return reupload;
    return clickbait;
  }
}

/// [glyph] drawn about the middle of a [size] square.
class FeedDislikeGlyphIcon extends StatelessWidget {
  const FeedDislikeGlyphIcon(this.glyph, {super.key, required this.size, required this.color, this.stroke});

  final FeedDislikeGlyph glyph;
  final double size;
  final Color color;

  /// The line width; the sheet's rows and the tiles differ.
  final double? stroke;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _GlyphPainter(glyph, color: color, stroke: stroke ?? FeedDislikeTheme.glyphStroke),
      ),
    ),
  );
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.glyph, {required this.color, required this.stroke});

  final FeedDislikeGlyph glyph;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..translate(size.width / 2 + _inkShift.dx, size.height / 2 + _inkShift.dy);
    switch (glyph) {
      case FeedDislikeGlyph.videoOff:
        _videoOff(canvas);
      case FeedDislikeGlyph.uploaderOff:
        _uploaderOff(canvas);
      case FeedDislikeGlyph.repeatedOff:
        _repeatedOff(canvas);
      case FeedDislikeGlyph.explicit:
        _explicit(canvas);
      case FeedDislikeGlyph.conflict:
        _conflict(canvas);
      case FeedDislikeGlyph.horror:
        _horror(canvas);
      case FeedDislikeGlyph.gross:
        _gross(canvas);
      case FeedDislikeGlyph.advert:
        _advert(canvas);
      case FeedDislikeGlyph.negative:
        _negative(canvas);
      case FeedDislikeGlyph.reupload:
        _reupload(canvas);
      case FeedDislikeGlyph.clickbait:
        _clickbait(canvas);
      case FeedDislikeGlyph.undo:
        _undo(canvas);
      case FeedDislikeGlyph.chevron:
        _chevron(canvas);
    }
    canvas.restore();
  }

  /// Where the icons' ink sits from their box's middle on 90 and 92 (the ⊘ hangs low and right).
  Offset get _inkShift => switch (glyph) {
    FeedDislikeGlyph.videoOff => const Offset(0, 1),
    FeedDislikeGlyph.uploaderOff => const Offset(2 / 3, 0.5),
    FeedDislikeGlyph.repeatedOff => const Offset(-1 / 3, 1 / 3),
    FeedDislikeGlyph.advert => const Offset(-0.5, -0.8),
    FeedDislikeGlyph.clickbait => const Offset(0, -0.4),
    FeedDislikeGlyph.undo => const Offset(0, -0.5),
    _ => Offset.zero,
  };

  Paint get _line => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  Paint get _fill => Paint()..color = color;

  /// A filled triangle whose corners the stroke rounds, as the official ▶s are.
  void _play(Canvas canvas, List<Offset> corners) {
    final path = Path()..addPolygon(corners, true);
    canvas
      ..drawPath(path, _fill)
      ..drawPath(path, _line..strokeWidth = stroke * 0.6);
  }

  void _forbidden(Canvas canvas, Offset centre) {
    const radius = 3.28;
    final reach = Offset(radius * math.cos(math.pi / 4), radius * math.sin(math.pi / 4));
    canvas
      ..drawCircle(centre, radius, _line)
      ..drawLine(centre - reach, centre + reach, _line);
  }

  /// A rounded frame's outline, from [start] on its bottom edge clockwise round to [end] on its right edge.
  Path _openFrame(Rect frame, double radius, {required double start, required double end}) {
    final r = Radius.circular(radius);
    return Path()
      ..moveTo(start, frame.bottom)
      ..lineTo(frame.left + radius, frame.bottom)
      ..arcToPoint(Offset(frame.left, frame.bottom - radius), radius: r)
      ..lineTo(frame.left, frame.top + radius)
      ..arcToPoint(Offset(frame.left + radius, frame.top), radius: r)
      ..lineTo(frame.right - radius, frame.top)
      ..arcToPoint(Offset(frame.right, frame.top + radius), radius: r)
      ..lineTo(frame.right, end);
  }

  void _videoOff(Canvas canvas) {
    canvas.drawPath(_openFrame(const Rect.fromLTRB(-8.3, -7.65, 6.5, 5.0), 2.6, start: -0.6, end: -1.0), _line);
    _play(canvas, const [Offset(-2.67, -3.46), Offset(1.5, -1.08), Offset(-2.67, 1.33)]);
    _forbidden(canvas, const Offset(4.9, 4.35));
  }

  void _uploaderOff(Canvas canvas) {
    const centre = Offset(-1.25, -2.9);
    const radius = 5.2;
    final head = Path()
      ..addArc(Rect.fromCircle(center: centre, radius: radius), 0.25, -4.17)
      ..lineTo(-4.17, 2.29)
      ..lineTo(-7.29, 6.04);
    canvas.drawPath(head, _line);
    _forbidden(canvas, const Offset(4.0, 4.85));
  }

  void _repeatedOff(Canvas canvas) {
    const r = Radius.circular(2.5);
    final back = Path()
      ..moveTo(-7.25, 2.92)
      ..lineTo(-7.25, -5.62)
      ..arcToPoint(const Offset(-4.75, -8.12), radius: r)
      ..lineTo(1.42, -8.12);
    canvas
      ..drawPath(back, _line)
      ..drawPath(_openFrame(const Rect.fromLTRB(-4.42, -5.42, 5.58, 5.63), 2.5, start: -1.92, end: -0.83), _line);
    _forbidden(canvas, const Offset(3.92, 4.58));
  }

  void _explicit(Canvas canvas) {
    canvas.drawRRect(RRect.fromLTRBR(-9.6, -7.9, 9.6, 7.9, const Radius.circular(4)), _line);
    const cell = 2.92;
    const left = -5.84;
    const top = -4.38;
    for (final (row, column) in const [(0, 0), (0, 2), (1, 1), (1, 3), (2, 0), (2, 2)]) {
      canvas.drawRect(Rect.fromLTWH(left + column * cell, top + row * cell, cell, cell), _fill);
    }
  }

  void _conflict(Canvas canvas) {
    const front = Rect.fromLTRB(-9.4, -8.1, 5.6, 5.2);
    Offset onFront(double angle) =>
        front.center + Offset(front.width / 2 * math.cos(angle), front.height / 2 * math.sin(angle));
    final bubble = Path()
      ..addArc(front, 2.25, 2 * math.pi - 0.5)
      ..lineTo(-6.4, 6.96)
      ..lineTo(onFront(2.25).dx, onFront(2.25).dy);
    const backCentre = Offset(4.6, 1.6);
    final back = Path()
      ..addArc(Rect.fromCircle(center: backCentre, radius: 5.8), -1.0, 2.0)
      ..lineTo(7.2, 9.4)
      ..lineTo(5.0, 7.6)
      ..lineTo(-0.3, 7.0);
    canvas
      ..drawPath(bubble, _line)
      ..drawPath(back, _line)
      ..drawLine(const Offset(-1.95, -4.1), const Offset(-1.95, -0.6), _line)
      ..drawCircle(const Offset(-1.95, 1.55), stroke * 0.6, _fill);
  }

  void _horror(Canvas canvas) {
    const radius = 8.2;
    final ghost = Path()
      ..moveTo(-radius, 6.4)
      ..lineTo(-radius, -0.75)
      ..arcTo(Rect.fromCircle(center: const Offset(0, -0.75), radius: radius), math.pi, math.pi, false)
      ..lineTo(radius, 6.4)
      ..quadraticBezierTo(radius, 9.0, 5.6, 8.7)
      ..quadraticBezierTo(4.2, 8.5, 2.6, 6.6)
      ..quadraticBezierTo(1.6, 8.9, 0, 8.9)
      ..quadraticBezierTo(-1.6, 8.9, -2.6, 6.6)
      ..quadraticBezierTo(-4.2, 8.5, -5.6, 8.7)
      ..quadraticBezierTo(-radius, 9.0, -radius, 6.4);
    canvas
      ..drawPath(ghost, _line)
      ..drawCircle(const Offset(-2.4, -2.5), 1.5, _fill)
      ..drawCircle(const Offset(2.4, -2.5), 1.5, _fill)
      ..drawOval(Rect.fromCenter(center: const Offset(0, 1.75), width: 2.9, height: 3.8), _line);
  }

  void _gross(Canvas canvas) {
    final head = Path()
      ..moveTo(-10.3, -1.0)
      ..cubicTo(-6.0, -11.8, 6.0, -11.8, 10.3, -0.6);
    Path hand(double side) => Path()
      ..moveTo(-10.3 * side, -1.0)
      ..lineTo(-7.2 * side, -4.0)
      ..cubicTo(-5.6 * side, -5.2, -2.2 * side, -5.0, -2.0 * side, -2.0)
      ..quadraticBezierTo(-1.9 * side, 0, -3.2 * side, 1.1)
      ..lineTo(-9.3 * side, 6.2);
    final chin = Path()
      ..moveTo(-7.2, 5.9)
      ..quadraticBezierTo(0, 12.2, 7.2, 5.9);
    final mouth = Path()
      ..moveTo(-2.2, 5.1)
      ..quadraticBezierTo(0, 2.1, 2.2, 5.1);
    for (final path in [head, hand(1), hand(-1), chin, mouth]) {
      canvas.drawPath(path, _line);
    }
  }

  void _advert(Canvas canvas) {
    final cone = Path()
      ..moveTo(-5.9, -3.9)
      ..lineTo(2.6, -7.2)
      ..quadraticBezierTo(4.0, -7.6, 4.0, -6.0)
      ..lineTo(4.0, 4.9)
      ..quadraticBezierTo(4.0, 6.4, 2.6, 5.9)
      ..lineTo(-5.9, 2.4);
    final handle = Path()
      ..moveTo(-8.6, 1.7)
      ..lineTo(-7.0, 7.7)
      ..quadraticBezierTo(-6.6, 8.6, -5.9, 8.3)
      ..quadraticBezierTo(-5.3, 8.0, -5.4, 7.4)
      ..lineTo(-5.7, 2.5);
    final bump = Path()..addArc(Rect.fromCircle(center: const Offset(4.0, -0.6), radius: 2.5), -math.pi / 2, math.pi);
    canvas
      ..drawRRect(RRect.fromLTRBR(-9.6, -3.95, -5.9, 1.65, const Radius.circular(1.2)), _line)
      ..drawPath(cone, _line)
      ..drawPath(handle, _line)
      ..drawPath(bump, _line)
      ..drawLine(const Offset(8.0, -4.7), const Offset(9.25, -5.75), _line)
      ..drawLine(const Offset(9.25, -0.75), const Offset(11.1, -0.75), _line)
      ..drawLine(const Offset(8.0, 3.4), const Offset(9.25, 4.45), _line);
  }

  void _negative(Canvas canvas) {
    final head = Path()
      ..moveTo(-3.5, -6.0)
      ..cubicTo(-1.5, -9.2, 5.5, -9.6, 8.1, -4.6)
      ..lineTo(6.2, -3.2)
      ..lineTo(7.9, -1.8)
      ..lineTo(6.9, 0.4)
      ..lineTo(4.4, 0.5)
      ..lineTo(4.6, 2.3)
      ..cubicTo(1.0, 3.8, -3.6, 1.6, -3.6, -2.2)
      ..quadraticBezierTo(-3.6, -4.8, -3.5, -6.0);
    final hair = Path()
      ..moveTo(-3.5, -6.0)
      ..quadraticBezierTo(-6.8, -5.6, -6.6, -1.0)
      ..quadraticBezierTo(-6.4, 3.0, -2.4, 8.2);
    final left = Path()
      ..moveTo(-10.1, 5.1)
      ..quadraticBezierTo(-5.6, 5.4, -3.1, 8.5);
    final right = Path()
      ..moveTo(0.5, 8.4)
      ..quadraticBezierTo(3.2, 5.4, 8.2, 5.1);
    for (final path in [head, hair, left, right]) {
      canvas.drawPath(path, _line);
    }
  }

  void _reupload(Canvas canvas) {
    const r = Radius.circular(2.4);
    final back = Path()
      ..moveTo(-8.0, 6.9)
      ..arcToPoint(const Offset(-9.5, 5.4), radius: const Radius.circular(1.5))
      ..lineTo(-9.5, -4.6)
      ..arcToPoint(const Offset(-7.1, -7.0), radius: r)
      ..lineTo(4.6, -7.0)
      ..arcToPoint(const Offset(7.0, -4.6), radius: r);
    canvas.drawPath(back, _line);
    final front = Path()..addRRect(RRect.fromLTRBR(-5.95, -2.6, 10.1, 9.45, const Radius.circular(2.5)));
    for (final metric in front.computeMetrics()) {
      _dash(canvas, metric, dash: 2.4, gap: 1.75);
    }
    _play(canvas, const [Offset(0.4, 1.2), Offset(5.3, 3.63), Offset(0.4, 6.05)]);
  }

  void _dash(Canvas canvas, PathMetric metric, {required double dash, required double gap}) {
    // Whole dashes round the outline, stretched a little to close the loop.
    final count = (metric.length / (dash + gap)).round();
    final step = metric.length / count;
    final drawn = step * dash / (dash + gap);
    final line = _line..strokeCap = StrokeCap.butt;
    for (var i = 0; i < count; i++) {
      canvas.drawPath(metric.extractPath(i * step, i * step + drawn), line);
    }
  }

  void _clickbait(Canvas canvas) {
    canvas
      ..drawRRect(RRect.fromLTRBR(-9.6, -7.4, 9.6, 8.4, const Radius.circular(4)), _line)
      ..drawLine(const Offset(0, -2.6), const Offset(0, 1.5), _line)
      ..drawCircle(const Offset(0, 4.2), stroke * 0.6, _fill);
  }

  void _undo(Canvas canvas) {
    final arrow = Path()
      ..moveTo(-1.7, -4.0)
      ..lineTo(-3.9, -2.0)
      ..lineTo(-1.7, 0)
      ..moveTo(-3.9, -2.0)
      ..lineTo(1.2, -2.0)
      ..arcToPoint(const Offset(1.2, 3.8), radius: const Radius.circular(2.9))
      ..lineTo(-2.2, 3.8);
    canvas.drawPath(arrow, _line);
  }

  void _chevron(Canvas canvas) {
    final path = Path()
      ..moveTo(-1.73, -4.07)
      ..lineTo(1.73, 0)
      ..lineTo(-1.73, 4.07);
    canvas.drawPath(path, _line);
  }

  @override
  bool shouldRepaint(_GlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color || oldDelegate.stroke != stroke;
}

/// 91's white disc with the ✓ cut out of it, so the blurred cover shows through the tick.
class FeedDislikeCheck extends StatelessWidget {
  const FeedDislikeCheck({super.key});

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: SizedBox.square(
      dimension: FeedDislikeTheme.checkDisc,
      child: CustomPaint(painter: _CheckPainter()),
    ),
  );
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    canvas
      ..saveLayer(Offset.zero & size, Paint())
      ..drawCircle(centre, size.shortestSide / 2, Paint()..color = FeedDislikeTheme.messageInk);
    final tick = Path()
      ..moveTo(centre.dx - 5.5, centre.dy + 0.7)
      ..lineTo(centre.dx - 2.1, centre.dy + 3.85)
      ..lineTo(centre.dx + 5.7, centre.dy - 3.65);
    canvas
      ..drawPath(
        tick,
        Paint()
          ..blendMode = BlendMode.clear
          ..style = PaintingStyle.stroke
          ..strokeWidth = FeedDislikeTheme.checkStroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) => false;
}
