import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../shared/theme.dart';

Paint _stroke(Color color, double width) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

/// The pill's ≡ (163): three equal lines whose ink spans the box.
class PillMenuPainter extends CustomPainter {
  const PillMenuPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const half = FriendsTheme.pillGlyphStroke / 2;
    final paint = _stroke(color, FriendsTheme.pillGlyphStroke);
    final step = (size.height - FriendsTheme.pillGlyphStroke) / 2;
    for (var line = 0; line < 3; line++) {
      final y = half + step * line;
      canvas.drawLine(Offset(half, y), Offset(size.width - half, y), paint);
    }
  }

  @override
  bool shouldRepaint(PillMenuPainter oldDelegate) => oldDelegate.color != color;
}

/// 设置分组's glyph on 166, traced there in an 18 × 16.33 box: two rings and a ✓ down the left, each before a line.
class GroupActionPainter extends CustomPainter {
  const GroupActionPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = _stroke(FriendsTheme.actionGlyphInk, FriendsTheme.actionGlyphStroke);
    final x = size.width / FriendsTheme.groupGlyphWidth;
    final y = size.height / FriendsTheme.groupGlyphHeight;
    Offset at(double dx, double dy) => Offset(dx * x, dy * y);
    canvas
      ..drawCircle(at(2.17, 2.27), 1.75 * x, paint)
      ..drawCircle(at(2.17, 8.37), 1.75 * x, paint)
      ..drawPath(
        Path()
          ..moveTo(at(0.45, 13.6).dx, at(0.45, 13.6).dy)
          ..lineTo(at(2.2, 15.55).dx, at(2.2, 15.55).dy)
          ..lineTo(at(5.3, 12.5).dx, at(5.3, 12.5).dy),
        paint,
      );
    for (final line in const [2.27, 8.37, 14.3]) {
      canvas.drawLine(at(8.0, line), at(17.55, line), paint);
    }
  }

  @override
  bool shouldRepaint(GroupActionPainter oldDelegate) => false;
}

/// 取消关注's glyph on 166, traced there in a 20 × 19 box: a head open where a ring with − overlaps it at the lower
/// right, the shoulder falling away to the left.
class UnfollowActionPainter extends CustomPainter {
  const UnfollowActionPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = _stroke(FriendsTheme.actionGlyphInk, FriendsTheme.actionGlyphStroke);
    final x = size.width / FriendsTheme.unfollowGlyphWidth;
    final y = size.height / FriendsTheme.unfollowGlyphHeight;
    Offset at(double dx, double dy) => Offset(dx * x, dy * y);
    const toRadians = math.pi / 180;
    final head = Rect.fromCircle(center: at(7.2, 4.4), radius: 3.95 * x);
    canvas.drawArc(head, 100 * toRadians, 268 * toRadians, false, paint);
    final neck = at(6.45, 8.6);
    final shoulder = at(0.45, 15.6);
    canvas
      ..drawPath(
        Path()
          ..moveTo(neck.dx, neck.dy)
          ..lineTo(at(5.6, 9.25).dx, at(5.6, 9.25).dy)
          ..quadraticBezierTo(at(0.6, 10.6).dx, at(0.6, 10.6).dy, shoulder.dx, shoulder.dy),
        paint,
      )
      ..drawCircle(at(13.7, 12.6), 5.55 * x, paint)
      ..drawLine(at(11.4, 12.6), at(16.0, 12.6), paint);
  }

  @override
  bool shouldRepaint(UnfollowActionPainter oldDelegate) => false;
}

/// ＋新建分组's ＋, its arms spanning the box.
class PlusPainter extends CustomPainter {
  const PlusPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = _stroke(FriendsTheme.newGroupInk, FriendsTheme.plusStroke);
    const half = FriendsTheme.plusStroke / 2;
    canvas
      ..drawLine(Offset(size.width / 2, half), Offset(size.width / 2, size.height - half), paint)
      ..drawLine(Offset(half, size.height / 2), Offset(size.width - half, size.height / 2), paint);
  }

  @override
  bool shouldRepaint(PlusPainter oldDelegate) => false;
}

/// A 分组's circle (167): a grey ring, or filled pink with a white ✓ once ticked.
class TickPainter extends CustomPainter {
  const TickPainter({required this.ticked});

  final bool ticked;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    if (!ticked) {
      canvas.drawCircle(
        centre,
        radius - FriendsTheme.tickRingWidth / 2,
        _stroke(FriendsTheme.tickRing, FriendsTheme.tickRingWidth),
      );
      return;
    }
    canvas
      ..drawCircle(centre, radius, Paint()..color = FriendsTheme.tickFill)
      ..drawPath(
        Path()
          ..moveTo(centre.dx - radius * 0.42, centre.dy + radius * 0.02)
          ..lineTo(centre.dx - radius * 0.1, centre.dy + radius * 0.34)
          ..lineTo(centre.dx + radius * 0.44, centre.dy - radius * 0.28),
        _stroke(FriendsTheme.tickInk, FriendsTheme.tickStroke),
      );
  }

  @override
  bool shouldRepaint(TickPainter oldDelegate) => oldDelegate.ticked != ticked;
}
