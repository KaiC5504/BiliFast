import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// The action icons: solid under the title (03) and down 竖屏's right side (09), outlined across landscape's top
/// (04) and its end screen (27).
enum ActionGlyph { like, dislike, coin, favourite, share, comment, charge }

/// One action icon at [size] pt square. Font Awesome (as PiliPlus uses) where it matches the official shapes; the
/// coin and 充电, which it lacks, are drawn.
class ActionIcon extends StatelessWidget {
  const ActionIcon(this.glyph, {super.key, required this.solid, required this.size, required this.color});

  final ActionGlyph glyph;
  final bool solid;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final data = switch (glyph) {
      ActionGlyph.like => solid ? FontAwesomeIcons.solidThumbsUp : FontAwesomeIcons.thumbsUp,
      ActionGlyph.dislike => solid ? FontAwesomeIcons.solidThumbsDown : FontAwesomeIcons.thumbsDown,
      ActionGlyph.favourite => solid ? FontAwesomeIcons.solidStar : FontAwesomeIcons.star,
      ActionGlyph.share => FontAwesomeIcons.share,
      ActionGlyph.comment => solid ? FontAwesomeIcons.solidCommentDots : FontAwesomeIcons.comment,
      ActionGlyph.coin || ActionGlyph.charge => null,
    };
    final child = data == null
        ? CustomPaint(painter: _DrawnGlyphPainter(glyph, solid: solid, color: color))
        : FaIcon(data, size: size * 0.86, color: color);
    return ExcludeSemantics(child: SizedBox.square(dimension: size, child: Center(child: child)));
  }
}

class _DrawnGlyphPainter extends CustomPainter {
  _DrawnGlyphPainter(this.glyph, {required this.solid, required this.color});

  final ActionGlyph glyph;
  final bool solid;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide == 0 ? 24.0 : size.shortestSide;
    final rect = Offset.zero & Size.square(side);
    if (glyph == ActionGlyph.coin) {
      _coin(canvas, rect);
    } else {
      _charge(canvas, rect);
    }
  }

  void _coin(Canvas canvas, Rect rect) {
    final centre = rect.center;
    final radius = rect.width * 0.42;
    final stroke = rect.width * 0.08;
    final ring = Paint()
      ..color = color
      ..style = solid ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = stroke;
    // Solid, the 币 mark is cut out of the disc, so whatever is behind shows through it.
    canvas
      ..saveLayer(rect, Paint())
      ..drawCircle(centre, solid ? radius : radius - stroke / 2, ring);
    final mark = Paint()
      ..color = color
      ..blendMode = solid ? BlendMode.clear : BlendMode.srcOver
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final w = radius;
    final top = centre.dy - w * 0.45;
    canvas
      ..drawLine(Offset(centre.dx - w * 0.5, top), Offset(centre.dx + w * 0.5, top), mark)
      ..drawLine(Offset(centre.dx, top), Offset(centre.dx, centre.dy + w * 0.55), mark);
    final legs = Path()
      ..moveTo(centre.dx - w * 0.45, centre.dy + w * 0.35)
      ..lineTo(centre.dx - w * 0.45, centre.dy - w * 0.05)
      ..lineTo(centre.dx + w * 0.45, centre.dy - w * 0.05)
      ..lineTo(centre.dx + w * 0.45, centre.dy + w * 0.35);
    canvas
      ..drawPath(legs, mark)
      ..restore();
  }

  void _charge(Canvas canvas, Rect rect) {
    final stroke = rect.width * 0.08;
    final body = Rect.fromLTWH(rect.width * 0.27, rect.height * 0.16, rect.width * 0.46, rect.height * 0.74);
    final outline = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas
      ..drawRRect(RRect.fromRectAndRadius(body, Radius.circular(rect.width * 0.08)), outline)
      ..drawLine(Offset(rect.width * 0.42, rect.height * 0.08), Offset(rect.width * 0.58, rect.height * 0.08), outline);
    final bolt = Path()
      ..moveTo(rect.width * 0.55, rect.height * 0.3)
      ..lineTo(rect.width * 0.4, rect.height * 0.56)
      ..lineTo(rect.width * 0.52, rect.height * 0.56)
      ..lineTo(rect.width * 0.45, rect.height * 0.78)
      ..lineTo(rect.width * 0.62, rect.height * 0.48)
      ..lineTo(rect.width * 0.5, rect.height * 0.48)
      ..close();
    canvas.drawPath(bolt, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_DrawnGlyphPainter old) => old.glyph != glyph || old.solid != solid || old.color != color;
}
