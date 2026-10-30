import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';

/// The official app's line icons in ⋮ (20, 21) and the light 选集 sheet (19), drawn from the screenshots at 3 px per
/// point; Material has nothing close enough.
class PanelGlyph extends StatelessWidget {
  const PanelGlyph(this.kind, {super.key, this.color = BiliColors.panelText});

  final PanelGlyphKind kind;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(size: kind.size, painter: _GlyphPainter(kind, color));
}

enum PanelGlyphKind {
  watchLater(Size.square(BiliMetrics.panelActionIcon)),
  pictureInPicture(Size.square(BiliMetrics.panelActionIcon)),
  autoplay(Size(BiliMetrics.panelAutoplayGlyphWidth, BiliMetrics.panelAutoplayGlyphHeight)),
  loop(Size(BiliMetrics.panelLoopGlyphWidth, BiliMetrics.panelLoopGlyphHeight)),
  mirror(Size(BiliMetrics.panelMirrorGlyphWidth, BiliMetrics.panelMirrorGlyphHeight)),
  fit(Size.square(BiliMetrics.panelFitGlyph)),
  chevron(Size(BiliMetrics.panelChevronWidth, BiliMetrics.panelChevronHeight)),
  views(Size(BiliMetrics.sheetCountGlyphWidth, BiliMetrics.sheetCountGlyphHeight)),
  danmaku(Size(BiliMetrics.sheetCountGlyphWidth, BiliMetrics.sheetCountGlyphHeight)),
  order(Size(BiliMetrics.sheetOrderGlyphWidth, BiliMetrics.sheetOrderGlyphHeight)),
  playing(Size(BiliMetrics.sheetPlayingGlyphWidth, BiliMetrics.sheetPlayingGlyphHeight)),

  /// The portrait ⋮ sheet's own rows (42, 43); the APK's icons for them aren't the iPhone's.
  speed(Size(DownloadSheetTheme.speedGlyphWidth, DownloadSheetTheme.speedGlyphHeight)),
  timer(Size(DownloadSheetTheme.timerGlyphWidth, DownloadSheetTheme.timerGlyphHeight)),
  listen(Size(DownloadSheetTheme.listenGlyphWidth, DownloadSheetTheme.listenGlyphHeight)),
  subtitle(Size(DownloadSheetTheme.subtitleGlyphWidth, DownloadSheetTheme.subtitleGlyphHeight)),
  quality(Size.square(DownloadSheetTheme.qualityGlyph)),
  gesture(Size.square(DownloadSheetTheme.gestureGlyph));

  const PanelGlyphKind(this.size);

  final Size size;
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.kind, this.color);

  final PanelGlyphKind kind;
  final Color color;

  Paint _line(double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    switch (kind) {
      case PanelGlyphKind.watchLater:
        _watchLater(canvas);
      case PanelGlyphKind.pictureInPicture:
        _pictureInPicture(canvas);
      case PanelGlyphKind.autoplay:
        _autoplay(canvas, size);
      case PanelGlyphKind.loop:
        _loop(canvas, size);
      case PanelGlyphKind.mirror:
        _mirror(canvas);
      case PanelGlyphKind.fit:
        _fit(canvas, size);
      case PanelGlyphKind.chevron:
        canvas.drawPath(
          Path()
            ..moveTo(0.5, 0.5)
            ..lineTo(size.width - 0.5, size.height / 2)
            ..lineTo(0.5, size.height - 0.5),
          _line(1),
        );
      case PanelGlyphKind.views:
        _countFrame(canvas, size);
        final mid = size.center(Offset.zero);
        final triangle = Path()
          ..moveTo(mid.dx - 1.3, mid.dy - 1.7)
          ..lineTo(mid.dx + 1.9, mid.dy)
          ..lineTo(mid.dx - 1.3, mid.dy + 1.7)
          ..close();
        canvas.drawPath(triangle, _line(0.9)..style = PaintingStyle.fill);
        canvas.drawPath(triangle, _line(0.9));
      case PanelGlyphKind.danmaku:
        _countFrame(canvas, size);
        final paint = _line(1);
        for (final (dot, from, to, y) in const [(3.1, 4.8, 9.2, 4.2), (4.1, 5.8, 10.2, 6.7)]) {
          canvas.drawLine(Offset(dot, y), Offset(dot, y), paint);
          canvas.drawLine(Offset(from, y), Offset(to, y), paint);
        }
      case PanelGlyphKind.order:
        final paint = _line(0.9);
        canvas.drawLine(const Offset(0.5, 1.6), const Offset(11.6, 1.6), paint);
        canvas.drawLine(const Offset(0.5, 5.6), const Offset(7.6, 5.6), paint);
        canvas.drawLine(const Offset(0.5, 9.6), const Offset(7.6, 9.6), paint);
        canvas.drawPath(
          Path()
            ..moveTo(9.7, 3.9)
            ..lineTo(9.7, 9.9)
            ..lineTo(12.1, 7.9),
          paint,
        );
      case PanelGlyphKind.playing:
        final paint = Paint()..color = color;
        const bar = BiliMetrics.sheetPlayingBar;
        for (final (x, height) in const [(0.0, 1.0), (4.8, 0.47), (9.6, 0.9)]) {
          final h = size.height * height;
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(x, (size.height - h) / 2, bar, h), const Radius.circular(bar / 2)),
            paint,
          );
        }
      case PanelGlyphKind.speed:
        _speed(canvas);
      case PanelGlyphKind.timer:
        _timer(canvas);
      case PanelGlyphKind.listen:
        _listen(canvas);
      case PanelGlyphKind.subtitle:
        _subtitle(canvas, size);
      case PanelGlyphKind.quality:
        _quality(canvas, size);
      case PanelGlyphKind.gesture:
        _gesture(canvas);
    }
  }

  /// Two outlined play triangles, the second's back at the first's tip.
  void _speed(Canvas canvas) {
    final paint = _line(DownloadSheetTheme.glyphStroke);
    for (final left in const [0.6, 8.3]) {
      canvas.drawPath(
        Path()
          ..moveTo(left, 0.7)
          ..lineTo(left + 7.4, 5.5)
          ..lineTo(left, 10.3)
          ..close(),
        paint,
      );
    }
  }

  /// A power sign whose ring gives way at the bottom right to a small clock.
  void _timer(Canvas canvas) {
    final paint = _line(DownloadSheetTheme.glyphStroke);
    double rad(double degrees) => degrees * math.pi / 180;
    final ring = Rect.fromCircle(center: const Offset(7.7, 9.0), radius: 6.9);
    canvas.drawArc(ring, rad(-68), rad(60), false, paint);
    canvas.drawArc(ring, rad(94), rad(153), false, paint);
    canvas.drawLine(const Offset(7.6, 0.75), const Offset(7.6, 7.4), paint);
    canvas.drawCircle(const Offset(12.7, 13.5), 3.55, paint);
    canvas.drawLine(const Offset(12.55, 11.9), const Offset(13.5, 14.0), paint);
  }

  /// Headphones over a pulse.
  void _listen(Canvas canvas) {
    final paint = _line(DownloadSheetTheme.glyphStroke);
    const left = 0.75, right = 15.25, centre = 8.0, cupTop = 8.2, bottom = 14.3, inner = 3.9, r = 1.6;
    canvas.drawPath(
      Path()
        ..moveTo(left, bottom - r)
        ..lineTo(left, centre)
        ..arcToPoint(const Offset(right, centre), radius: const Radius.circular((right - left) / 2))
        ..lineTo(right, bottom - r),
      paint,
    );
    for (final (outer, inside) in const [(left, inner), (right, right - (inner - left))]) {
      final sign = inside > outer ? 1.0 : -1.0;
      canvas.drawPath(
        Path()
          ..moveTo(outer, cupTop)
          ..lineTo(inside, cupTop)
          ..lineTo(inside, bottom - r)
          ..arcToPoint(Offset(inside - sign * r, bottom), radius: const Radius.circular(r), clockwise: sign > 0)
          ..lineTo(outer + sign * r, bottom)
          ..arcToPoint(Offset(outer, bottom - r), radius: const Radius.circular(r), clockwise: sign > 0),
        paint,
      );
    }
    canvas.drawPath(
      Path()
        ..moveTo(4.4, 8.0)
        ..lineTo(5.6, 8.0)
        ..lineTo(6.8, 5.7)
        ..lineTo(8.8, 10.0)
        ..lineTo(9.8, 8.0)
        ..lineTo(11.4, 8.0),
      paint,
    );
  }

  /// A rounded screen with a thick bar near its bottom.
  void _subtitle(Canvas canvas, Size size) {
    const half = DownloadSheetTheme.glyphStroke / 2;
    canvas.drawRRect(
      RRect.fromLTRBR(half, half, size.width - half, size.height - half, const Radius.circular(3)),
      _line(DownloadSheetTheme.glyphStroke),
    );
    canvas.drawLine(const Offset(3.6, 10), Offset(size.width - 3.6, 10), _line(1.9));
  }

  /// A circle split down the middle, its right half hatched.
  void _quality(Canvas canvas, Size size) {
    final paint = _line(DownloadSheetTheme.glyphStroke);
    final centre = size.center(Offset.zero);
    final r = size.width / 2 - DownloadSheetTheme.glyphStroke / 2;
    canvas.drawCircle(centre, r, paint);
    canvas.drawLine(Offset(centre.dx, centre.dy - r), Offset(centre.dx, centre.dy + r), paint);
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: centre, radius: r)));
    canvas.clipRect(Rect.fromLTRB(centre.dx, 0, size.width, size.height));
    final hatch = _line(1.0)..strokeCap = StrokeCap.butt;
    for (var at = -1.0; at < 5; at++) {
      final y = 3.4 * at + 2;
      canvas.drawLine(Offset(centre.dx, y + 8), Offset(size.width, y), hatch);
    }
    canvas.restore();
  }

  /// A hand tapping with its forefinger, a ring over the fingertip.
  void _gesture(Canvas canvas) {
    final paint = _line(DownloadSheetTheme.glyphStroke);
    double rad(double degrees) => degrees * math.pi / 180;
    canvas.drawArc(Rect.fromCircle(center: const Offset(4.4, 4.6), radius: 3.6), rad(155), rad(175), false, paint);
    canvas.drawPath(
      Path()
        ..moveTo(7.6, 13.0)
        ..lineTo(3.2, 5.6)
        ..arcToPoint(const Offset(5.6, 4.4), radius: const Radius.circular(1.4))
        ..lineTo(8.2, 8.7)
        ..lineTo(8.6, 6.5)
        ..lineTo(14.0, 6.2)
        ..quadraticBezierTo(16.0, 6.2, 16.8, 9.6)
        ..quadraticBezierTo(17.7, 13.4, 15.8, 15.6)
        ..quadraticBezierTo(14.4, 17.4, 11.0, 16.6)
        ..lineTo(4.0, 15.0)
        ..arcToPoint(const Offset(4.4, 12.9), radius: const Radius.circular(1.1))
        ..close(),
      paint,
    );
  }

  /// A circle open between three and half past four, its arrowhead at three pointing on round, around a play
  /// triangle.
  void _watchLater(Canvas canvas) {
    final paint = _line(1.6);
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(11.1, 12), radius: 9),
      math.pi / 4,
      math.pi * 7 / 4,
      false,
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(17.6, 10.9)
        ..lineTo(20.1, 13.5)
        ..lineTo(22.4, 10.9),
      paint,
    );
    final triangle = Path()
      ..moveTo(9.6, 9.6)
      ..lineTo(14.1, 12)
      ..lineTo(9.6, 14.4)
      ..close();
    canvas.drawPath(triangle, _line(1.4)..style = PaintingStyle.fill);
    canvas.drawPath(triangle, _line(1.4));
  }

  /// The screen, open where the small window sits over its corner, and an arrow into it.
  void _pictureInPicture(Canvas canvas) {
    final paint = _line(1.45);
    const r = 3.4;
    canvas.drawPath(
      Path()
        ..moveTo(20.8, 10.8)
        ..lineTo(20.8, 4.3 + r)
        ..arcToPoint(const Offset(20.8 - r, 4.3), radius: const Radius.circular(r), clockwise: false)
        ..lineTo(2.5 + r, 4.3)
        ..arcToPoint(const Offset(2.5, 4.3 + r), radius: const Radius.circular(r), clockwise: false)
        ..lineTo(2.5, 19.7 - r)
        ..arcToPoint(const Offset(2.5 + r, 19.7), radius: const Radius.circular(r), clockwise: false)
        ..lineTo(10.6, 19.7),
      paint,
    );
    canvas.drawRRect(RRect.fromLTRBR(12.9, 13.1, 21.5, 20.0, const Radius.circular(2.6)), paint);
    canvas.drawLine(const Offset(7, 8.7), const Offset(10.6, 12), paint);
    canvas.drawPath(
      Path()
        ..moveTo(7.5, 12)
        ..lineTo(10.6, 12)
        ..lineTo(10.6, 8.9),
      paint,
    );
  }

  /// ▷| in outline.
  void _autoplay(Canvas canvas, Size size) {
    const stroke = 1.3, half = stroke / 2;
    final paint = _line(stroke);
    final bar = size.width - half;
    canvas.drawPath(
      Path()
        ..moveTo(half, half + 0.4)
        ..lineTo(bar - 1, size.height / 2)
        ..lineTo(half, size.height - half - 0.4)
        ..close(),
      paint,
    );
    canvas.drawLine(Offset(bar, half), Offset(bar, size.height - half), paint);
  }

  /// Two arcs of a wide oval chasing each other, each ending in a single barb.
  void _loop(Canvas canvas, Size size) {
    final paint = _line(1.4);
    final centre = size.center(Offset.zero);
    const rx = 8.4, ry = 5.75;
    final oval = Rect.fromCenter(center: centre, width: rx * 2, height: ry * 2);
    double rad(double degrees) => degrees * math.pi / 180;
    canvas.drawArc(oval, rad(112), rad(160), false, paint);
    canvas.drawArc(oval, rad(292), rad(160), false, paint);
    final top = centre + Offset(rx * math.cos(rad(272)), ry * math.sin(rad(272)));
    final bottom = centre + Offset(rx * math.cos(rad(92)), ry * math.sin(rad(92)));
    canvas.drawLine(top, top + const Offset(-2, -2), paint);
    canvas.drawLine(bottom, bottom + const Offset(2, 2), paint);
  }

  /// The picture as a slanted outline, and its mirror image dashed.
  void _mirror(Canvas canvas) {
    final paint = _line(1.2);
    canvas.drawPath(
      Path()
        ..moveTo(0.6, 1.9)
        ..quadraticBezierTo(0.6, 0.6, 1.9, 0.8)
        ..lineTo(5.6, 1.6)
        ..quadraticBezierTo(6.7, 1.8, 6.7, 2.9)
        ..lineTo(6.7, 10.9)
        ..quadraticBezierTo(6.7, 12, 5.6, 12.2)
        ..lineTo(1.9, 13.1)
        ..quadraticBezierTo(0.6, 13.3, 0.6, 12)
        ..close(),
      paint,
    );
    final frame = Path()..addRRect(RRect.fromLTRBR(9.9, 0.9, 15.7, 13, const Radius.circular(2.5)));
    for (final metric in frame.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += 2.7) {
        canvas.drawPath(metric.extractPath(at, at + 1.2), paint);
      }
    }
  }

  /// Only the top-left and bottom-right corners of a frame.
  void _fit(Canvas canvas, Size size) {
    const stroke = 1.1, half = stroke / 2, arm = 6.3, r = 1.0;
    final paint = _line(stroke);
    final right = size.width - half, bottom = size.height - half;
    canvas.drawPath(
      Path()
        ..moveTo(half, half + arm)
        ..lineTo(half, half + r)
        ..arcToPoint(const Offset(half + r, half), radius: const Radius.circular(r))
        ..lineTo(half + arm, half),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(right, bottom - arm)
        ..lineTo(right, bottom - r)
        ..arcToPoint(Offset(right - r, bottom), radius: const Radius.circular(r))
        ..lineTo(right - arm, bottom),
      paint,
    );
  }

  void _countFrame(Canvas canvas, Size size) {
    canvas.drawRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(0.5), const Radius.circular(2.6)), _line(1));
  }

  @override
  bool shouldRepaint(_GlyphPainter oldDelegate) => oldDelegate.kind != kind || oldDelegate.color != color;
}
