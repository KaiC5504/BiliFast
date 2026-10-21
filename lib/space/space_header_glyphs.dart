import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../comments/comment_badges.dart' show SegmentGlyph;
import '../shared/theme.dart';

/// UP主空间's line glyphs, traced on 63, 70, 72 and 73.
enum SpaceGlyph {
  /// 〈 on the banner and the bar.
  back,

  /// 私信's speech bubble with its two dots.
  chat,
  search,

  /// ⋮.
  more,

  /// + 关注's +.
  plus,

  /// 已关注's ≡.
  list,

  /// ▽'s chevron.
  chevronDown,

  /// 充电's bolt, filled.
  bolt,

  /// IP属地's boxed IP.
  ip,

  /// 小店's awning, filled.
  shop,

  /// The › after a link tag.
  chevron,
}

/// [glyph] drawn to fill a [width] × [height] ink box.
class SpaceGlyphIcon extends StatelessWidget {
  const SpaceGlyphIcon(this.glyph, {super.key, required this.width, required this.height, required this.color});

  final SpaceGlyph glyph;
  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: width,
      height: height,
      child: CustomPaint(painter: SpaceGlyphPainter(glyph, color: color)),
    ),
  );
}

class SpaceGlyphPainter extends CustomPainter {
  const SpaceGlyphPainter(this.glyph, {required this.color});

  final SpaceGlyph glyph;
  final Color color;

  Paint _line(double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  Paint get _fill => Paint()..color = color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    switch (glyph) {
      case SpaceGlyph.back:
        const s = SpaceTheme.glyphStroke / 2;
        canvas.drawPath(
          Path()
            ..moveTo(w - s, s)
            ..lineTo(s, h / 2)
            ..lineTo(w - s, h - s),
          _line(SpaceTheme.glyphStroke),
        );
      case SpaceGlyph.chat:
        _chat(canvas, w, h);
      case SpaceGlyph.search:
        const s = SpaceTheme.glyphStroke;
        // The ring takes 13.67 of the 15 pt box; the handle runs on to its corner.
        final ring = w * 0.911;
        final centre = Offset(ring / 2, ring / 2);
        canvas
          ..drawCircle(centre, (ring - s) / 2, _line(s))
          ..drawLine(centre + Offset(ring * 0.36, ring * 0.36), Offset(w - s / 2, h - s / 2), _line(s));
      case SpaceGlyph.more:
        final r = w / 2;
        for (final y in [r, h / 2, h - r]) {
          canvas.drawCircle(Offset(w / 2, y), r, _fill);
        }
      case SpaceGlyph.plus:
        final paint = _line(SpaceTheme.followPlusStroke)..strokeCap = StrokeCap.butt;
        canvas
          ..drawLine(Offset(0, h / 2), Offset(w, h / 2), paint)
          ..drawLine(Offset(w / 2, 0), Offset(w / 2, h), paint);
      case SpaceGlyph.list:
        const s = SpaceTheme.followedListStroke;
        final paint = _line(s);
        for (final y in [s / 2, h / 2, h - s / 2]) {
          canvas.drawLine(Offset(s / 2, y), Offset(w - s / 2, y), paint);
        }
      case SpaceGlyph.chevronDown:
        const s = SpaceTheme.moreChevronStroke / 2;
        canvas.drawPath(
          Path()
            ..moveTo(s, s)
            ..lineTo(w / 2, h - s)
            ..lineTo(w - s, s),
          _line(SpaceTheme.moreChevronStroke),
        );
      case SpaceGlyph.bolt:
        Offset p(double x, double y) => Offset(x * w, y * h);
        canvas.drawPath(
          Path()
            ..addPolygon([p(0.38, 0), p(1, 0), p(0.72, 0.42), p(1, 0.42), p(0.12, 1), p(0.35, 0.6), p(0, 0.6)], true),
          _fill,
        );
      case SpaceGlyph.ip:
        _ip(canvas, w, h);
      case SpaceGlyph.shop:
        _shop(canvas, w, h);
      case SpaceGlyph.chevron:
        const s = SpaceTheme.tagIconStroke / 2;
        canvas.drawPath(
          Path()
            ..moveTo(s, s)
            ..lineTo(w - s, h / 2)
            ..lineTo(s, h - s),
          _line(SpaceTheme.tagIconStroke),
        );
    }
  }

  /// A round bubble whose lower left runs out to a corner, as 72's 私信.
  void _chat(Canvas canvas, double w, double h) {
    const s = SpaceTheme.glyphStroke;
    final r = (h - s) / 2;
    final centre = Offset(w - s / 2 - r, s / 2 + r);
    // From the left side just under the middle, round over the top and the right to the bottom, then straight out
    // to the corner and back up.
    const start = math.pi - 0.2;
    final path = Path()
      ..addArc(Rect.fromCircle(center: centre, radius: r), start, math.pi * 2.5 - start)
      ..lineTo(s / 2, h - s / 2)
      ..close();
    canvas.drawPath(path, _line(s));
    final dot = Paint()..color = color;
    canvas
      ..drawCircle(centre + Offset(-r * 0.37, 0), s * 0.7, dot)
      ..drawCircle(centre + Offset(r * 0.37, 0), s * 0.7, dot);
  }

  void _ip(Canvas canvas, double w, double h) {
    const s = SpaceTheme.tagIconStroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(s / 2, s / 2, w - s, h - s), const Radius.circular(SpaceTheme.tagIconRadius)),
      _line(s),
    );
    final letter = _line(s * 1.15)..strokeCap = StrokeCap.butt;
    final top = h * 0.28, bottom = h * 0.72;
    canvas
      ..drawLine(Offset(w * 0.33, top), Offset(w * 0.33, bottom), letter)
      ..drawPath(
        Path()
          ..moveTo(w * 0.5, bottom)
          ..lineTo(w * 0.5, top)
          ..lineTo(w * 0.62, top)
          ..arcToPoint(Offset(w * 0.62, h * 0.54), radius: Radius.circular(h * 0.13))
          ..lineTo(w * 0.5, h * 0.54),
        letter,
      );
  }

  /// The awning over the counter, split by a wavy gap (63's 小店).
  void _shop(Canvas canvas, double w, double h) {
    final fill = _fill;
    final awning = Path()
      ..addRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(0, 0, w, h * 0.5),
          topLeft: Radius.circular(h * 0.22),
          topRight: Radius.circular(h * 0.22),
          bottomLeft: Radius.circular(h * 0.12),
          bottomRight: Radius.circular(h * 0.12),
        ),
      );
    final counter = Path()
      ..addRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(w * 0.07, h * 0.58, w * 0.86, h * 0.42),
          bottomLeft: Radius.circular(h * 0.16),
          bottomRight: Radius.circular(h * 0.16),
        ),
      );
    canvas
      ..drawPath(awning, fill)
      ..drawPath(counter, fill);
  }

  @override
  bool shouldRepaint(SpaceGlyphPainter oldDelegate) => oldDelegate.glyph != glyph || oldDelegate.color != color;
}

/// The space's LV badge: 评论's block shape and block letters in the space's colours, and for 硬核会员 a longer
/// block with a bolt after the digit (72).
class SpaceLevelBadge extends StatelessWidget {
  const SpaceLevelBadge({super.key, required this.level, this.senior = false});

  final int level;
  final bool senior;

  @override
  Widget build(BuildContext context) {
    final clamped = level.clamp(0, SpaceTheme.levels.length - 1);
    return Semantics(
      label: senior ? 'LV$clamped 硬核会员' : 'LV$clamped',
      child: CustomPaint(
        key: const ValueKey('space-level'),
        size: Size(
          SpaceTheme.levelWidth + (senior ? SpaceTheme.levelSeniorExtra : 0),
          SpaceTheme.levelHeight,
        ),
        painter: _LevelPainter(clamped, senior: senior),
      ),
    );
  }
}

class _LevelPainter extends CustomPainter {
  const _LevelPainter(this.level, {required this.senior});

  final int level;
  final bool senior;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.height / 9;
    final corner = Radius.circular(unit);
    final block = Paint()..color = SpaceTheme.levels[level];
    canvas
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, unit, 12 * unit, 8 * unit), corner), block)
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(11 * unit, 0, size.width - 11 * unit, 9 * unit), corner), block);
    final weight = 1.3 * unit;
    final ink = Paint()..color = SpaceTheme.levelInk;
    SegmentGlyph.draw(canvas, 'L', Rect.fromLTWH(1.3 * unit, 2.1 * unit, 3.5 * unit, 5.7 * unit), weight, ink);
    SegmentGlyph.draw(canvas, 'V', Rect.fromLTWH(5.9 * unit, 2.1 * unit, 4.4 * unit, 5.7 * unit), weight, ink);
    final digit = '$level';
    final width = SegmentGlyph.glyphWidth(digit, width: 4.5 * unit, weight: weight);
    // The digit sits a little right of its block's middle, as on 评论's badge.
    final centre = (11 * unit + SpaceTheme.levelWidth) / 2 + 0.15 * unit;
    SegmentGlyph.draw(canvas, digit, Rect.fromLTWH(centre - width / 2, 1.35 * unit, width, 6.5 * unit), weight, ink);
    if (senior) {
      final left = SpaceTheme.levelWidth - 0.6 * unit;
      Offset p(double x, double y) => Offset(left + x * 4.6 * unit, (1.4 + y * 6.2) * unit);
      canvas.drawPath(
        Path()..addPolygon([p(0.62, 0), p(0, 0.6), p(0.42, 0.6), p(0.3, 1), p(1, 0.38), p(0.58, 0.38)], true),
        ink,
      );
    }
  }

  @override
  bool shouldRepaint(_LevelPainter oldDelegate) => oldDelegate.level != level || oldDelegate.senior != senior;
}
