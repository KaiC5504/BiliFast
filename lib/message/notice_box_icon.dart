import 'package:bili_core/api.dart';
import 'package:flutter/widgets.dart';

import '../shared/theme.dart';

/// A notice box's round face, [size] across: 196's pink 服务通知 and 社区中心 (200's bubbles), and the APK's own blue
/// 系统通知 and 创作助手, which no screenshot shows.
class NoticeBoxIcon extends StatelessWidget {
  const NoticeBoxIcon(this.box, {super.key, required this.size});

  final NoticeBox box;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: switch (box) {
      NoticeBox.service || NoticeBox.community => DecoratedBox(
        decoration: const BoxDecoration(color: MessageTabTheme.boxFill, shape: BoxShape.circle),
        child: CustomPaint(painter: _BoxGlyphPainter(box)),
      ),
      NoticeBox.system => _apkFace('assets/images/message/tab_box_system.png'),
      NoticeBox.creator => _apkFace('assets/images/message/tab_box_creator.png'),
    },
  );

  /// The APK's face as it is, its disc filling the picture.
  static Widget _apkFace(String asset) => Image.asset(asset, fit: BoxFit.fill, excludeFromSemantics: true);
}

/// 196's white glyphs, traced in fortieths of the disc.
class _BoxGlyphPainter extends CustomPainter {
  const _BoxGlyphPainter(this.box);

  final NoticeBox box;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / 40);
    final glyph = Paint()..color = MessageTabTheme.boxGlyph;
    if (box == NoticeBox.service) {
      _service(canvas, glyph);
    } else {
      _community(canvas, glyph);
    }
    canvas.restore();
  }

  /// Three rounded squares and a diamond where the fourth would be.
  static void _service(Canvas canvas, Paint glyph) {
    const side = 25 / 3;
    const corner = Radius.circular(2.5);
    for (final (left, top) in [(11.0, 11.0), (11.0, 62 / 3), (62 / 3, 62 / 3)]) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(left, top, side, side), corner), glyph);
    }
    canvas
      ..save()
      ..translate(25.1, 14.85)
      ..rotate(0.7853981633974483)
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 7, height: 7), corner), glyph)
      ..restore();
  }

  /// A bubble with two pink lines and its tail, over a second one up and to the right, a pink gap between them.
  static void _community(Canvas canvas, Paint glyph) {
    const corner = Radius.circular(3.5);
    final front = RRect.fromLTRBR(9, 43 / 3, 80 / 3, 83 / 3, corner);
    final gap = Paint()..color = MessageTabTheme.boxFill;
    canvas
      ..drawRRect(RRect.fromLTRBR(46 / 3, 31 / 3, 31, 67 / 3, corner), glyph)
      ..drawRRect(front.inflate(5 / 3), gap)
      ..drawRRect(front, glyph)
      ..drawPath(
        Path()
          ..moveTo(13.4, 27)
          ..lineTo(18.6, 27)
          ..lineTo(14.6, 30.4)
          ..quadraticBezierTo(13.7, 31.1, 13.6, 29.9)
          ..close(),
        glyph,
      );
    final line = Paint()
      ..color = MessageTabTheme.boxFill
      ..strokeWidth = 4 / 3
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(const Offset(13, 59 / 3), const Offset(68 / 3, 59 / 3), line)
      ..drawLine(const Offset(13, 70 / 3), const Offset(56 / 3, 70 / 3), line);
  }

  @override
  bool shouldRepaint(_BoxGlyphPainter oldDelegate) => oldDelegate.box != box;
}
