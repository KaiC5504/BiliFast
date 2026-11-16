import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';

Paint _stroke(Color color, double width) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

/// The header's ‹, its tip [LiveRoomTheme.backTipX] from the box's left, on the box's middle.
class RoomBackPainter extends CustomPainter {
  const RoomBackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const tip = LiveRoomTheme.backTipX;
    const end = tip + LiveRoomTheme.backWidth;
    final middle = size.height / 2;
    canvas.drawPath(
      Path()
        ..moveTo(end, middle - LiveRoomTheme.backHeight / 2)
        ..lineTo(tip, middle)
        ..lineTo(end, middle + LiveRoomTheme.backHeight / 2),
      _stroke(LiveRoomTheme.ink, LiveRoomTheme.backStroke),
    );
  }

  @override
  bool shouldRepaint(RoomBackPainter oldDelegate) => false;
}

/// 更多直播's ›, filling its box.
class RoomChevronPainter extends CustomPainter {
  const RoomChevronPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const inset = LiveRoomTheme.chipChevronStroke / 2;
    canvas.drawPath(
      Path()
        ..moveTo(inset, inset)
        ..lineTo(size.width - inset, size.height / 2)
        ..lineTo(inset, size.height - inset),
      _stroke(LiveRoomTheme.ink, LiveRoomTheme.chipChevronStroke),
    );
  }

  @override
  bool shouldRepaint(RoomChevronPainter oldDelegate) => false;
}

/// ⋯'s three dots, centred.
class RoomDotsPainter extends CustomPainter {
  const RoomDotsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final paint = Paint()..color = LiveRoomTheme.ink;
    for (var i = -1; i <= 1; i++) {
      canvas.drawCircle(centre.translate(i * LiveRoomTheme.barDotStep, 0), LiveRoomTheme.barDot / 2, paint);
    }
  }

  @override
  bool shouldRepaint(RoomDotsPainter oldDelegate) => false;
}

/// The input's emote button (207): a grey disc with a winking face. The APK carries no such picture.
class RoomWinkPainter extends CustomPainter {
  const RoomWinkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.drawCircle(size.center(Offset.zero), s / 2, Paint()..color = LiveRoomTheme.emoteFaceFill);
    final ink = Paint()..color = LiveRoomTheme.emoteFaceInk;
    Offset at(double x, double y) => Offset(x * s, y * s);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: at(0.3, 0.45), width: s * 0.1, height: s * 0.2),
        Radius.circular(s),
      ),
      ink,
    );
    canvas.drawPath(
      Path()
        ..moveTo(at(0.66, 0.36).dx, at(0.66, 0.36).dy)
        ..lineTo(at(0.76, 0.42).dx, at(0.76, 0.42).dy)
        ..lineTo(at(0.66, 0.48).dx, at(0.66, 0.48).dy),
      _stroke(LiveRoomTheme.emoteFaceInk, s * 0.08),
    );
    canvas.drawPath(
      Path()
        ..moveTo(at(0.4, 0.62).dx, at(0.4, 0.62).dy)
        ..lineTo(at(0.6, 0.62).dx, at(0.6, 0.62).dy)
        ..lineTo(at(0.5, 0.78).dx, at(0.5, 0.78).dy)
        ..close(),
      ink,
    );
  }

  @override
  bool shouldRepaint(RoomWinkPainter oldDelegate) => false;
}

/// The strip's battery: a yellow cell with its cap and a white bolt.
class RoomBatteryPainter extends CustomPainter {
  const RoomBatteryPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fill = Paint()..color = LiveRoomTheme.batteryInk;
    canvas
      ..drawRRect(RRect.fromLTRBR(w * 0.3, 0, w * 0.7, h * 0.14, Radius.circular(w * 0.08)), fill)
      ..drawRRect(RRect.fromLTRBR(0, h * 0.1, w, h, Radius.circular(w * 0.16)), fill);
    Offset at(double x, double y) => Offset(x * w, y * h);
    canvas.drawPath(
      Path()
        ..addPolygon([at(0.6, 0.26), at(0.24, 0.6), at(0.48, 0.6), at(0.4, 0.9), at(0.76, 0.52), at(0.52, 0.52)], true),
      Paint()..color = LiveRoomTheme.batteryBolt,
    );
  }

  @override
  bool shouldRepaint(RoomBatteryPainter oldDelegate) => false;
}

/// The bottom bar's +.
class RoomPlusPainter extends CustomPainter {
  const RoomPlusPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const arm = LiveRoomTheme.plusArm / 2;
    final paint = _stroke(LiveRoomTheme.ink, LiveRoomTheme.plusStroke);
    canvas
      ..drawLine(c.translate(-arm, 0), c.translate(arm, 0), paint)
      ..drawLine(c.translate(0, -arm), c.translate(0, arm), paint);
  }

  @override
  bool shouldRepaint(RoomPlusPainter oldDelegate) => false;
}

/// 消费管理's shield with ¥ and 色觉优化's eye, which the APK carries no picture of; drawn as 221's line icons, on a
/// 26 pt grid.
class RoomLineIconPainter extends CustomPainter {
  const RoomLineIconPainter.spending() : eye = false;
  const RoomLineIconPainter.colour() : eye = true;

  final bool eye;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide / 26;
    canvas
      ..save()
      ..translate((size.width - 26 * unit) / 2, (size.height - 26 * unit) / 2)
      ..scale(unit);
    final paint = _stroke(LiveRoomTheme.ink, LiveRoomTheme.glyphStroke * 1.2);
    if (eye) {
      canvas
        ..drawPath(
          Path()
            ..moveTo(2, 13)
            ..quadraticBezierTo(13, 1, 24, 13)
            ..quadraticBezierTo(13, 25, 2, 13),
          paint,
        )
        ..drawCircle(const Offset(13, 13), 4, paint);
    } else {
      canvas
        ..drawPath(
          Path()
            ..moveTo(13, 2)
            ..lineTo(22, 5.5)
            ..lineTo(22, 12)
            ..quadraticBezierTo(22, 20, 13, 24)
            ..quadraticBezierTo(4, 20, 4, 12)
            ..lineTo(4, 5.5)
            ..close(),
          paint,
        )
        ..drawPath(
          Path()
            ..moveTo(9.5, 8.5)
            ..lineTo(13, 12.5)
            ..lineTo(16.5, 8.5)
            ..moveTo(13, 12.5)
            ..lineTo(13, 18.5)
            ..moveTo(10, 13.5)
            ..lineTo(16, 13.5)
            ..moveTo(10, 16)
            ..lineTo(16, 16),
          paint,
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(RoomLineIconPainter oldDelegate) => oldDelegate.eye != eye;
}
