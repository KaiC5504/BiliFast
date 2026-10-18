import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// The action icons: solid under the title (03) and down 竖屏's right side (09), outlined across landscape's top
/// (04) and its end screen (27).
enum ActionGlyph { like, dislike, coin, favourite, share, comment, charge }

/// One action icon at [size] pt square. Every glyph is drawn: the official shapes (the cuffed thumb, the coin's 币,
/// the soft star and arrow) match no icon font closely enough. The glyph's ink spans [inkShare] of [size], so the
/// coin, thumb, star, bubble and arrow are all as wide as `size * inkShare`.
class ActionIcon extends StatelessWidget {
  const ActionIcon(this.glyph, {super.key, required this.solid, required this.size, required this.color});

  /// Measured on 03, 04, 09 and 27: a 20 pt coin in a 24 pt icon.
  static const inkShare = 0.84;

  final ActionGlyph glyph;
  final bool solid;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: ActionGlyphPainter(glyph, solid: solid, color: color),
      ),
    ),
  );
}

/// Paints [glyph] into the centre [ActionIcon.inkShare] of the square it gets.
class ActionGlyphPainter extends CustomPainter {
  ActionGlyphPainter(this.glyph, {required this.solid, required this.color});

  final ActionGlyph glyph;
  final bool solid;
  final Color color;

  /// Outline strokes on 04 and 27 are 1.1 pt on a 20 pt glyph.
  static const _line = 0.055;

  /// The 币 strokes, solid and outlined alike.
  static const _markLine = 0.056;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    if (side <= 0) return;
    final ink = side * ActionIcon.inkShare;
    final box = Rect.fromCenter(center: size.center(Offset.zero), width: ink, height: ink);
    switch (glyph) {
      case ActionGlyph.like:
        _thumb(canvas, box, down: false);
      case ActionGlyph.dislike:
        // 03's thumbs-down sits 2 pt lower than the thumbs-up beside it.
        _thumb(canvas, box.shift(Offset(0, ink * 0.1)), down: true);
      case ActionGlyph.coin:
        _coin(canvas, box);
      case ActionGlyph.favourite:
        _shape(canvas, box, _star, extent: const Size(1, 0.98));
      case ActionGlyph.share:
        _shape(canvas, box, _share, extent: const Size(1, 0.833), soften: 0.07);
      case ActionGlyph.comment:
        _comment(canvas, box);
      case ActionGlyph.charge:
        _charge(canvas, box);
    }
  }

  Paint get _fill => Paint()
    ..color = color
    ..isAntiAlias = true;

  Paint _stroke(double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;

  /// Maps a path drawn in a unit square onto [box], centred, at [extent] of it. Outlines go inside by half a line so
  /// their ink keeps the solid glyph's size.
  Path _place(Path unit, Rect box, Size extent, {double inset = 0}) {
    final width = box.width * extent.width - inset;
    final height = box.height * extent.height - inset;
    final scale = math.min(width / extent.width, height / extent.height);
    final dx = box.center.dx - extent.width * scale / 2;
    final dy = box.center.dy - extent.height * scale / 2;
    final matrix = Float64List.fromList([scale, 0, 0, 0, 0, scale, 0, 0, 0, 0, 1, 0, dx, dy, 0, 1]);
    return unit.transform(matrix);
  }

  void _shape(Canvas canvas, Rect box, Path Function() unit, {required Size extent, double soften = 0}) {
    if (solid) {
      final inset = soften * box.width;
      final path = _place(unit(), box, extent, inset: inset);
      canvas.drawPath(path, _fill);
      if (inset > 0) canvas.drawPath(path, _stroke(inset));
    } else {
      final line = _line * box.width;
      canvas.drawPath(_place(unit(), box, extent, inset: line), _stroke(line));
    }
  }

  void _thumb(Canvas canvas, Rect box, {required bool down}) {
    final flip = down
        ? (Path path) => path.transform(Float64List.fromList([1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 0, 1, 0, 1]))
        : (Path path) => path;
    const extent = Size(1, 1);
    if (solid) {
      canvas
        ..drawPath(_place(flip(_hand()), box, extent), _fill)
        ..drawPath(_place(flip(_cuff()), box, extent), _fill);
    } else {
      final line = _line * box.width;
      canvas
        ..drawPath(_place(flip(_thumbOutline()), box, extent, inset: line), _stroke(line))
        ..drawPath(
          _place(
            flip(
              Path()
                ..moveTo(0.225, 0.36)
                ..lineTo(0.225, 1),
            ),
            box,
            extent,
            inset: line,
          ),
          _stroke(line),
        );
    }
  }

  void _coin(Canvas canvas, Rect box) {
    final mark = _stroke(_markLine * box.width);
    if (solid) {
      // The 币 is cut out of the disc, so whatever is behind shows through it.
      canvas
        ..saveLayer(box.inflate(1), Paint())
        ..drawOval(box, _fill)
        ..drawPath(_place(_bi(), box, const Size(1, 1)), mark..blendMode = BlendMode.clear)
        ..restore();
    } else {
      final line = _line * box.width;
      canvas
        ..drawOval(box.deflate(line / 2), _stroke(line))
        ..drawPath(_place(_bi(), box, const Size(1, 1)), mark);
    }
  }

  void _comment(Canvas canvas, Rect box) {
    const extent = Size(1, 0.985);
    if (solid) {
      final bubble = _place(_bubble(), box, extent);
      final dots = Path();
      for (final x in const [0.245, 0.495, 0.745]) {
        dots.addOval(Rect.fromCircle(center: Offset(x, 0.45), radius: 0.056));
      }
      canvas.drawPath(Path.combine(PathOperation.difference, bubble, _place(dots, box, extent)), _fill);
    } else {
      final line = _line * box.width;
      canvas.drawPath(_place(_bubble(), box, extent, inset: line), _stroke(line));
    }
  }

  void _charge(Canvas canvas, Rect box) {
    // 04's battery: 14.7 x 20.3 pt on a 20 pt glyph, its cap a short bar above a rounded body, a bolt inside.
    final width = box.width * 0.73;
    final battery = Rect.fromCenter(center: box.center, width: width, height: box.height);
    Offset at(double u, double v) => Offset(battery.left + u * width, battery.top + v * battery.height);
    final line = _line * box.width;
    final cap = RRect.fromRectAndRadius(Rect.fromPoints(at(0.3, 0), at(0.7, 0.06)), Radius.circular(box.width * 0.03));
    final body = Rect.fromPoints(at(0, 0.13), at(1, 1));
    final corner = Radius.circular(box.width * 0.1);
    final bolt = Path()
      ..moveTo(at(0.57, 0.34).dx, at(0.57, 0.34).dy)
      ..lineTo(at(0.27, 0.59).dx, at(0.27, 0.59).dy)
      ..lineTo(at(0.47, 0.59).dx, at(0.47, 0.59).dy)
      ..lineTo(at(0.43, 0.77).dx, at(0.43, 0.77).dy)
      ..lineTo(at(0.73, 0.5).dx, at(0.73, 0.5).dy)
      ..lineTo(at(0.53, 0.5).dx, at(0.53, 0.5).dy)
      ..close();
    final boltEdge = _stroke(box.width * 0.03);
    canvas.drawRRect(cap, _fill);
    if (solid) {
      canvas
        ..saveLayer(box.inflate(1), Paint())
        ..drawRRect(RRect.fromRectAndRadius(body, corner), _fill)
        ..drawPath(bolt, _fill..blendMode = BlendMode.clear)
        ..drawPath(bolt, boltEdge..blendMode = BlendMode.clear)
        ..restore();
    } else {
      canvas
        ..drawRRect(RRect.fromRectAndRadius(body.deflate(line / 2), corner), _stroke(line))
        ..drawPath(bolt, _fill)
        ..drawPath(bolt, boltEdge);
    }
  }

  /// The hand of the thumbs-up, without its cuff; the thumb rises a little right of centre.
  static Path _hand() => Path()
    ..moveTo(0.265, 1)
    ..lineTo(0.265, 0.345)
    ..cubicTo(0.36, 0.33, 0.41, 0.22, 0.44, 0.12)
    ..cubicTo(0.47, 0.03, 0.51, 0, 0.555, 0)
    ..cubicTo(0.62, 0, 0.655, 0.06, 0.648, 0.14)
    ..lineTo(0.64, 0.35)
    ..lineTo(0.915, 0.35)
    ..cubicTo(0.98, 0.35, 1.01, 0.4, 0.998, 0.465)
    ..lineTo(0.905, 0.87)
    ..cubicTo(0.888, 0.95, 0.84, 1, 0.77, 1)
    ..close();

  static Path _cuff() => Path()
    ..addRRect(
      RRect.fromLTRBAndCorners(
        0,
        0.35,
        0.19,
        1,
        topLeft: const Radius.circular(0.1),
        bottomLeft: const Radius.circular(0.1),
        topRight: const Radius.circular(0.015),
        bottomRight: const Radius.circular(0.015),
      ),
    );

  /// 04's thumbs-up: one contour round the hand and cuff, the cuff marked off by a line.
  static Path _thumbOutline() => Path()
    ..moveTo(0.265, 0.345)
    ..cubicTo(0.36, 0.33, 0.41, 0.22, 0.44, 0.12)
    ..cubicTo(0.47, 0.03, 0.51, 0, 0.555, 0)
    ..cubicTo(0.62, 0, 0.655, 0.06, 0.648, 0.14)
    ..lineTo(0.64, 0.35)
    ..lineTo(0.915, 0.35)
    ..cubicTo(0.98, 0.35, 1.01, 0.4, 0.998, 0.465)
    ..lineTo(0.905, 0.87)
    ..cubicTo(0.888, 0.95, 0.84, 1, 0.77, 1)
    ..lineTo(0.1, 1)
    ..quadraticBezierTo(0, 1, 0, 0.9)
    ..lineTo(0, 0.45)
    ..quadraticBezierTo(0, 0.35, 0.1, 0.35)
    ..close();

  /// The stylised 币 inside the coin: a bar, the stem through it, and an arch either side.
  static Path _bi() => Path()
    ..moveTo(0.3, 0.255)
    ..lineTo(0.69, 0.255)
    ..moveTo(0.494, 0.255)
    ..lineTo(0.494, 0.78)
    ..moveTo(0.29, 0.68)
    ..lineTo(0.29, 0.565)
    ..cubicTo(0.29, 0.47, 0.37, 0.42, 0.494, 0.42)
    ..cubicTo(0.62, 0.42, 0.705, 0.47, 0.705, 0.565)
    ..lineTo(0.705, 0.68);

  /// The official star is a little taller than a regular one, with short plump arms and soft tips.
  static Path _star() {
    const tips = 0.1, valleys = 0.05;
    const outer = 0.568, inner = 0.33, stretch = 1.04;
    const centre = Offset(0.5, 0.553);
    final points = <(Offset, double)>[];
    for (var i = 0; i < 10; i++) {
      final angle = -math.pi / 2 + i * math.pi / 5;
      final radius = i.isEven ? outer : inner;
      final point = centre + Offset(math.cos(angle) * radius, math.sin(angle) * radius * stretch);
      points.add((point, i.isEven ? tips : valleys));
    }
    return _rounded(points);
  }

  static Path _share() => Path()
    ..moveTo(0.54, 0)
    ..lineTo(1, 0.41)
    ..lineTo(0.54, 0.831)
    ..lineTo(0.515, 0.6)
    ..cubicTo(0.36, 0.589, 0.17, 0.636, 0, 0.831)
    ..cubicTo(0.04, 0.564, 0.21, 0.241, 0.515, 0.231)
    ..close();

  /// 09's bubble: a wide oval with its tail low on the left, pointing down.
  static Path _bubble() {
    const oval = Rect.fromLTRB(0, 0, 1, 0.88);
    const start = 96.9 * math.pi / 180, end = 125.5 * math.pi / 180;
    return Path()
      ..arcTo(oval, start, -(2 * math.pi - (end - start)), true)
      ..quadraticBezierTo(0.215, 0.92, 0.22, 0.975)
      ..quadraticBezierTo(0.225, 1.0, 0.26, 0.985)
      ..close();
  }

  /// A polygon whose corners are cut by quadratic curves [radius] long on each side.
  static Path _rounded(List<(Offset, double)> points) {
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final (point, radius) = points[i];
      final previous = points[(i - 1 + points.length) % points.length].$1;
      final next = points[(i + 1) % points.length].$1;
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
  bool shouldRepaint(ActionGlyphPainter old) => old.glyph != glyph || old.solid != solid || old.color != color;
}
