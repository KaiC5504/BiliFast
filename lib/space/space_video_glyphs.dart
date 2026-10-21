import 'package:flutter/widgets.dart';

import '../shared/theme.dart';

/// 播放全部's pink ring with its solid ▶ (63, 69), drawn in a [SpaceVideosTheme.playAllRing] square.
class PlayAllGlyph extends StatelessWidget {
  const PlayAllGlyph({super.key});

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: SizedBox.square(
      dimension: SpaceVideosTheme.playAllRing,
      child: CustomPaint(painter: _PlayAllPainter()),
    ),
  );
}

class _PlayAllPainter extends CustomPainter {
  const _PlayAllPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    const stroke = SpaceVideosTheme.playAllStroke;
    canvas.drawCircle(
      centre,
      (size.shortestSide - stroke) / 2,
      Paint()
        ..color = SpaceVideosTheme.playAllGlyphInk
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    const left = SpaceVideosTheme.playAllTriangleLeft;
    const right = SpaceVideosTheme.playAllTriangleRight;
    const half = SpaceVideosTheme.playAllTriangleHalf;
    final triangle = Path()
      ..moveTo(centre.dx + left, centre.dy - half)
      ..lineTo(centre.dx + right, centre.dy)
      ..lineTo(centre.dx + left, centre.dy + half)
      ..close();
    canvas.drawPath(
      triangle,
      Paint()
        ..color = SpaceVideosTheme.playAllGlyphInk
        ..style = PaintingStyle.fill,
    );
    // A thin stroke of the same colour rounds the triangle's corners, as the official one's are.
    canvas.drawPath(
      triangle,
      Paint()
        ..color = SpaceVideosTheme.playAllGlyphInk
        ..style = PaintingStyle.stroke
        ..strokeWidth = SpaceVideosTheme.playAllTriangleRound
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_PlayAllPainter oldDelegate) => false;
}

/// The sort's ≡: three grey bars 4 apart (63, 69).
class SortGlyph extends StatelessWidget {
  const SortGlyph({super.key});

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: SizedBox(
      width: SpaceVideosTheme.sortGlyphWidth,
      height: SpaceVideosTheme.sortGlyphPitch * 2 + SpaceVideosTheme.sortGlyphBar,
      child: CustomPaint(painter: _SortPainter()),
    ),
  );
}

class _SortPainter extends CustomPainter {
  const _SortPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = SpaceVideosTheme.sortGlyphInk;
    for (var i = 0; i < 3; i++) {
      canvas.drawRect(
        Rect.fromLTWH(0, i * SpaceVideosTheme.sortGlyphPitch, size.width, SpaceVideosTheme.sortGlyphBar),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SortPainter oldDelegate) => false;
}

/// A row's ⋮: three grey dots centred in the box it gets.
class MoreDotsPainter extends CustomPainter {
  const MoreDotsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final paint = Paint()..color = SpaceVideosTheme.moreInk;
    for (final step in const [-1, 0, 1]) {
      canvas.drawCircle(centre.translate(0, step * SpaceVideosTheme.morePitch), SpaceVideosTheme.moreDot / 2, paint);
    }
  }

  @override
  bool shouldRepaint(MoreDotsPainter oldDelegate) => false;
}
