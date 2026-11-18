import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';

/// The send bar's face (226, 227): a ring, two dot eyes and a ω mouth. The APK's emoji glyphs have other eyes.
class LiveFaceGlyph extends StatelessWidget {
  const LiveFaceGlyph({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size.square(LiveSendTheme.faceSize), painter: _FacePainter(color));
}

class _FacePainter extends CustomPainter {
  const _FacePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = LiveSendTheme.faceStroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawCircle(centre, (size.shortestSide - LiveSendTheme.faceStroke) / 2, line);
    final eye = Paint()..color = color;
    for (final side in const [-1.0, 1.0]) {
      canvas.drawCircle(
        centre + Offset(side * LiveSendTheme.faceEyeX, -LiveSendTheme.faceEyeY),
        LiveSendTheme.faceEyeRadius,
        eye,
      );
    }
    const r = LiveSendTheme.faceMouthRadius;
    final top = centre.dy + LiveSendTheme.faceMouthTop;
    final mouth = Path()
      ..addArc(Rect.fromCircle(center: Offset(centre.dx - r, top), radius: r), 0, math.pi)
      ..addArc(Rect.fromCircle(center: Offset(centre.dx + r, top), radius: r), 0, math.pi);
    canvas.drawPath(mouth, line);
  }

  @override
  bool shouldRepaint(_FacePainter oldDelegate) => oldDelegate.color != color;
}

/// 227's ⌫: a tag pointing left with a × in it.
class LiveDeleteGlyph extends StatelessWidget {
  const LiveDeleteGlyph({super.key});

  @override
  Widget build(BuildContext context) => const CustomPaint(
    size: Size(LiveSendTheme.deleteGlyphWidth, LiveSendTheme.deleteGlyphHeight),
    painter: _DeletePainter(),
  );
}

class _DeletePainter extends CustomPainter {
  const _DeletePainter();

  @override
  void paint(Canvas canvas, Size size) {
    const inset = LiveSendTheme.deleteGlyphStroke / 2;
    final rect = (Offset.zero & size).deflate(inset);
    final nose = rect.height * 0.42;
    const corner = 1.0;
    final outline = Path()
      ..moveTo(rect.left, rect.center.dy)
      ..lineTo(rect.left + nose, rect.top)
      ..lineTo(rect.right - corner, rect.top)
      ..quadraticBezierTo(rect.right, rect.top, rect.right, rect.top + corner)
      ..lineTo(rect.right, rect.bottom - corner)
      ..quadraticBezierTo(rect.right, rect.bottom, rect.right - corner, rect.bottom)
      ..lineTo(rect.left + nose, rect.bottom)
      ..close();
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = LiveSendTheme.deleteGlyphStroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = LiveSendTheme.deleteInk;
    canvas.drawPath(outline, line);
    final cross = Offset(rect.left + nose + (rect.right - rect.left - nose) * 0.42, rect.center.dy);
    final arm = rect.height * 0.2;
    canvas
      ..drawLine(cross - Offset(arm, arm), cross + Offset(arm, arm), line)
      ..drawLine(cross + Offset(-arm, arm), cross + Offset(arm, -arm), line);
  }

  @override
  bool shouldRepaint(_DeletePainter oldDelegate) => false;
}

/// 醒目留言's SC mark: a purple speech bubble with its tail at the bottom left. Not among the APK's art.
class LiveScMark extends StatelessWidget {
  const LiveScMark({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: LiveSendTheme.pillMarkWidth,
    height: LiveSendTheme.pillMarkHeight,
    child: CustomPaint(
      painter: const _BubblePainter(),
      child: SizedBox(
        height: LiveSendTheme.pillMarkBody,
        child: Center(
          child: Text(
            'SC',
            style: TextStyle(
              fontFamily: BiliFonts.family,
              fontFamilyFallback: BiliFonts.fallback,
              fontSize: LiveSendTheme.pillMarkText,
              fontWeight: FontWeight.w800,
              height: 1,
              color: LiveSendTheme.pillMarkInk,
              letterSpacing: 0,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    ),
  );
}

class _BubblePainter extends CustomPainter {
  const _BubblePainter();

  @override
  void paint(Canvas canvas, Size size) {
    const body = LiveSendTheme.pillMarkBody;
    final bubble = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, body),
          const Radius.circular(LiveSendTheme.pillMarkRadius),
        ),
      )
      ..addPolygon([
        Offset(size.width * 0.2, body - 1),
        Offset(size.width * 0.42, body - 1),
        Offset(size.width * 0.22, size.height),
      ], true);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [LiveSendTheme.pillMarkTop, LiveSendTheme.pillMarkBottom],
      ).createShader(Offset.zero & size);
    canvas.drawPath(bubble, paint);
  }

  @override
  bool shouldRepaint(_BubblePainter oldDelegate) => false;
}
