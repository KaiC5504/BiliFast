import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../shared/theme.dart';

/// 搜索's line glyphs, drawn to match 52-60.
enum SearchGlyph {
  /// The field's magnifier (52); also 首页's field (01).
  magnifier,

  /// The grey filled ⓧ that clears the field (55).
  clear,

  /// 搜索历史's 🗑 (52).
  trash,

  /// 搜索历史's ⌄, and ⌃ once expanded (52, 54).
  expand,
  collapse,

  /// 搜索发现's ↻ and 👁 (52); [eyeOff] once hidden.
  refresh,
  eye,
  eyeOff,

  /// The 反馈 pill's glyph (53).
  feedback,

  /// 完整榜单's › (52).
  chevron,

  /// 筛选's funnel (56).
  funnel,

  /// The play count's ▷ in its rounded box (56).
  play,

  /// + 关注's + (60).
  plus,

  /// 添加至稍后再看's arrowed circle with its ▶ (59).
  watchLater;

  /// The ink box's larger side on the official shots; [SearchGlyphIcon.size] scales the glyph from it.
  double get designSize => switch (this) {
    magnifier => SearchGlyphTheme.magnifierSize,
    clear => SearchGlyphTheme.clearSize,
    trash => SearchGlyphTheme.trashSize,
    expand || collapse => SearchGlyphTheme.expandSize,
    refresh => SearchGlyphTheme.refreshSize,
    eye || eyeOff => SearchGlyphTheme.eyeSize,
    feedback => SearchGlyphTheme.feedbackSize,
    chevron => SearchGlyphTheme.chevronSize,
    funnel => SearchGlyphTheme.funnelSize,
    play => SearchGlyphTheme.playSize,
    plus => SearchGlyphTheme.plusSize,
    watchLater => SearchGlyphTheme.watchLaterSize,
  };
}

/// [glyph] centred in a [size] square; its ink's larger side is [size]. [SearchGlyph.clear] fills its disc with
/// [color] and leaves the × see-through.
class SearchGlyphIcon extends StatelessWidget {
  const SearchGlyphIcon(this.glyph, {super.key, required this.size, required this.color});

  final SearchGlyph glyph;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: SearchGlyphPainter(glyph, color: color)),
    ),
  );
}

/// Draws in pt about the glyph's centre at its [SearchGlyph.designSize], scaled to the square it gets.
class SearchGlyphPainter extends CustomPainter {
  SearchGlyphPainter(this.glyph, {required this.color});

  final SearchGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    if (side <= 0) return;
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..scale(side / glyph.designSize);
    switch (glyph) {
      case SearchGlyph.magnifier:
        _magnifier(canvas);
      case SearchGlyph.clear:
        _clear(canvas);
      case SearchGlyph.trash:
        _trash(canvas);
      case SearchGlyph.expand:
        _chevronDown(canvas, flip: false);
      case SearchGlyph.collapse:
        _chevronDown(canvas, flip: true);
      case SearchGlyph.refresh:
        _refresh(canvas);
      case SearchGlyph.eye:
        _eye(canvas);
      case SearchGlyph.eyeOff:
        _eyeOff(canvas);
      case SearchGlyph.feedback:
        _feedback(canvas);
      case SearchGlyph.chevron:
        _chevron(canvas);
      case SearchGlyph.funnel:
        _funnel(canvas);
      case SearchGlyph.play:
        _play(canvas);
      case SearchGlyph.plus:
        _plus(canvas);
      case SearchGlyph.watchLater:
        _watchLater(canvas);
    }
    canvas.restore();
  }

  Paint _line([double width = SearchGlyphTheme.stroke]) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  Paint get _fill => Paint()..color = color;

  void _magnifier(Canvas canvas) {
    final line = _line(SearchGlyphTheme.magnifierStroke);
    canvas
      ..drawCircle(const Offset(-0.16, -0.17), 4.95, line)
      ..drawLine(const Offset(3.34, 3.33), const Offset(5.42, 5.42), line);
  }

  void _clear(Canvas canvas) {
    const reach = 2.1;
    canvas
      ..saveLayer(Rect.fromCircle(center: Offset.zero, radius: 7), Paint())
      ..drawCircle(Offset.zero, 6.5, _fill);
    final cut = _line(SearchGlyphTheme.clearStroke)
      ..strokeCap = StrokeCap.butt
      ..blendMode = BlendMode.clear;
    canvas
      ..drawLine(const Offset(-reach, -reach), const Offset(reach, reach), cut)
      ..drawLine(const Offset(reach, -reach), const Offset(-reach, reach), cut)
      ..restore();
  }

  void _trash(Canvas canvas) {
    final line = _line();
    const handleCorner = Radius.circular(1.2);
    const bodyCorner = Radius.circular(2.65);
    final handle = Path()
      ..moveTo(-2.17, -3.66)
      ..lineTo(-2.17, -5.75 + handleCorner.x)
      ..arcToPoint(Offset(-2.17 + handleCorner.x, -5.75), radius: handleCorner)
      ..lineTo(2.17 - handleCorner.x, -5.75)
      ..arcToPoint(Offset(2.17, -5.75 + handleCorner.x), radius: handleCorner)
      ..lineTo(2.17, -3.66);
    final body = Path()
      ..moveTo(-4.83, -1.66)
      ..lineTo(-4.83, 6 - bodyCorner.x)
      ..arcToPoint(Offset(-4.83 + bodyCorner.x, 6), radius: bodyCorner, clockwise: false)
      ..lineTo(4.83 - bodyCorner.x, 6)
      ..arcToPoint(Offset(4.83, 6 - bodyCorner.x), radius: bodyCorner, clockwise: false)
      ..lineTo(4.83, -1.66);
    canvas
      ..drawLine(const Offset(-6.17, -3.66), const Offset(6.17, -3.66), line)
      ..drawPath(handle, line)
      ..drawPath(body, line)
      ..drawLine(const Offset(-1.66, -0.33), const Offset(-1.66, 2), line)
      ..drawLine(const Offset(1.66, -0.33), const Offset(1.66, 2), line);
  }

  /// ⌄, or ⌃ when [flip]: two 45° strokes 11 pt across.
  void _chevronDown(Canvas canvas, {required bool flip}) {
    final sign = flip ? -1.0 : 1.0;
    canvas.drawPath(
      Path()
        ..moveTo(-5.5, -2.7 * sign)
        ..lineTo(0, 2.8 * sign)
        ..lineTo(5.5, -2.7 * sign),
      _line(),
    );
  }

  /// Two arcs of one circle, each ending in a right-angled arrowhead; the second is the first turned half a turn.
  void _refresh(Canvas canvas) {
    const radius = 5.65;
    const arrow = 2.8;
    final line = _line();
    for (final turn in const [0.0, math.pi]) {
      canvas
        ..save()
        ..rotate(turn);
      const start = math.pi / 2;
      const end = 234 * math.pi / 180;
      final tip = Offset(math.cos(end), math.sin(end)) * radius;
      canvas
        ..drawArc(Rect.fromCircle(center: Offset.zero, radius: radius), start, end - start, false, line)
        ..drawPath(
          Path()
            ..moveTo(tip.dx - arrow, tip.dy)
            ..lineTo(tip.dx, tip.dy)
            ..lineTo(tip.dx, tip.dy + arrow),
          line,
        )
        ..restore();
    }
  }

  void _eye(Canvas canvas) {
    const lid = Radius.circular(7.8);
    final line = _line();
    canvas
      ..drawPath(
        Path()
          ..moveTo(-7.17, 0)
          ..arcToPoint(const Offset(7.17, 0), radius: lid)
          ..arcToPoint(const Offset(-7.17, 0), radius: lid)
          ..close(),
        line,
      )
      ..drawCircle(Offset.zero, 2.39, line);
  }

  /// The eye struck through from top left to bottom right, with a gap either side of the stroke.
  void _eyeOff(Canvas canvas) {
    const from = Offset(-5.6, -5.6);
    const to = Offset(5.6, 5.6);
    canvas.saveLayer(const Rect.fromLTRB(-9, -9, 9, 9), Paint());
    _eye(canvas);
    canvas
      ..drawLine(from, to, _line(3 * SearchGlyphTheme.stroke)..blendMode = BlendMode.clear)
      ..drawLine(from, to, _line())
      ..restore();
  }

  /// A rounded square open at its lower right, a ? inside, and a pencil over the opening.
  void _feedback(Canvas canvas) {
    final line = _line();
    const corner = Radius.circular(1.7);
    const left = -6.48, top = -5.59, right = 5.55, bottom = 4.6;
    final frame = Path()
      ..moveTo(right, -1.85)
      ..lineTo(right, top + corner.x)
      ..arcToPoint(Offset(right - corner.x, top), radius: corner, clockwise: false)
      ..lineTo(left + corner.x, top)
      ..arcToPoint(Offset(left, top + corner.x), radius: corner, clockwise: false)
      ..lineTo(left, bottom - corner.x)
      ..arcToPoint(Offset(left + corner.x, bottom), radius: corner, clockwise: false)
      ..lineTo(-1.12, bottom);
    final question = Path()
      ..moveTo(-1.72, -1.55)
      ..cubicTo(-1.72, -2.75, -0.95, -3.45, -0.17, -3.45)
      ..cubicTo(0.45, -3.45, 0.88, -3, 0.88, -2.4)
      ..cubicTo(0.88, -1.75, 0.55, -1.4, 0.2, -1.1)
      ..cubicTo(-0.1, -0.85, -0.25, -0.6, -0.25, -0.2)
      ..lineTo(-0.25, 0.75);
    final pencil = Path()
      ..moveTo(1.63, 3.55)
      ..lineTo(1.63, 5.6)
      ..lineTo(3.68, 5.6)
      ..lineTo(6.08, 3.15)
      ..arcToPoint(const Offset(3.98, 1.15), radius: const Radius.circular(1.45), clockwise: false)
      ..close();
    canvas
      ..drawPath(frame, line)
      ..drawPath(question, line)
      ..drawCircle(const Offset(-0.25, 2.03), 0.65, _fill)
      ..drawPath(pencil, line);
  }

  void _chevron(Canvas canvas) => canvas.drawPath(
    Path()
      ..moveTo(-2, -4.17)
      ..lineTo(2.17, 0)
      ..lineTo(-2, 4.17),
    _line(),
  );

  void _funnel(Canvas canvas) => canvas.drawPath(
    _roundedPolygon(const [
      (Offset(-7.9, -6.55), 1.6),
      (Offset(7.9, -6.55), 1.6),
      (Offset(2.24, 1.6), 2.4),
      (Offset(2.24, 6.61), 1.2),
      (Offset(-2.24, 6.61), 1.2),
      (Offset(-2.24, 1.6), 2.4),
    ]),
    _line(SearchGlyphTheme.funnelStroke),
  );

  void _play(Canvas canvas) {
    canvas
      ..drawRRect(RRect.fromLTRBR(-6.17, -5.17, 6.17, 5.16, const Radius.circular(2.4)), _line())
      ..drawPath(
        _roundedPolygon(const [(Offset(-1.4, -1.95), 0.5), (Offset(2.5, 0), 0.5), (Offset(-1.4, 1.95), 0.5)]),
        _fill,
      );
  }

  void _plus(Canvas canvas) {
    const reach = 4.67;
    final line = _line(SearchGlyphTheme.plusStroke)..strokeCap = StrokeCap.butt;
    canvas
      ..drawLine(const Offset(-reach, 0), const Offset(reach, 0), line)
      ..drawLine(const Offset(0, -reach), const Offset(0, reach), line);
  }

  /// A circle left open at the lower right, its end arrowed downwards, with a solid ▶ inside.
  void _watchLater(Canvas canvas) {
    const centre = Offset(-0.95, 0);
    const radius = 7.41;
    const start = 42.5 * math.pi / 180;
    const sweep = 328.5 * math.pi / 180;
    final tip = centre + Offset(math.cos(start + sweep), math.sin(start + sweep)) * radius;
    final line = _line(SearchGlyphTheme.watchLaterStroke);
    canvas
      ..drawArc(Rect.fromCircle(center: centre, radius: radius), start, sweep, false, line)
      ..drawPath(
        Path()
          ..moveTo(tip.dx - 2.15, tip.dy - 1.9)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(tip.dx + 2.13, tip.dy - 2.15),
        line,
      )
      ..drawPath(
        _roundedPolygon(const [(Offset(-2.9, -2.5), 0.6), (Offset(2.2, -0.05), 0.6), (Offset(-2.9, 2.4), 0.6)]),
        _fill,
      );
  }

  /// A closed polygon whose corners are cut by quadratic curves [radius] long on each side.
  static Path _roundedPolygon(List<(Offset, double)> corners) {
    final path = Path();
    for (var i = 0; i < corners.length; i++) {
      final (point, radius) = corners[i];
      final previous = corners[(i - 1 + corners.length) % corners.length].$1;
      final next = corners[(i + 1) % corners.length].$1;
      final into = point + _toward(point, previous) * radius;
      final out = point + _toward(point, next) * radius;
      if (i == 0) {
        path.moveTo(into.dx, into.dy);
      } else {
        path.lineTo(into.dx, into.dy);
      }
      path.quadraticBezierTo(point.dx, point.dy, out.dx, out.dy);
    }
    return path..close();
  }

  static Offset _toward(Offset from, Offset to) {
    final delta = to - from;
    return delta / delta.distance;
  }

  @override
  bool shouldRepaint(SearchGlyphPainter old) => old.glyph != glyph || old.color != color;
}
