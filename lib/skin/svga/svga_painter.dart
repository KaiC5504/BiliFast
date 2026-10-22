import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'svg_path.dart';
import 'svga_movie.dart';

/// A movie with its pictures decoded, ready to draw.
final class SvgaComposition {
  SvgaComposition(this.movie, this.images) : _matteKeys = {for (final sprite in movie.sprites) ?sprite.matteKey};

  final SvgaMovie movie;
  final Map<String, ui.Image> images;
  final Set<String> _matteKeys;
  late final Map<String, SvgaSprite> _mattes = {
    for (final sprite in movie.sprites)
      if (_matteKeys.contains(sprite.imageKey)) sprite.imageKey: sprite,
  };
  final Map<String, Path> _paths = {};

  Size get size => Size(movie.width, movie.height);

  /// Draws frame [index] in the view box's coordinates, bottom sprite first.
  void paintFrame(Canvas canvas, int index) {
    for (final sprite in movie.sprites) {
      // A matte layer only masks the sprites that name it.
      if (_mattes.containsKey(sprite.imageKey) || sprite.imageKey.endsWith('.matte')) continue;
      final frame = sprite.frameAt(index);
      if (!frame.visible) continue;
      final matte = _mattes[sprite.matteKey];
      if (matte == null) {
        _paintSprite(canvas, sprite, frame);
        continue;
      }
      final bounds = Offset.zero & size;
      canvas.saveLayer(bounds, Paint());
      _paintSprite(canvas, sprite, frame);
      canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.dstIn);
      final matteFrame = matte.frameAt(index);
      if (matteFrame.visible) _paintSprite(canvas, matte, matteFrame);
      canvas.restore();
      canvas.restore();
    }
  }

  void _paintSprite(Canvas canvas, SvgaSprite sprite, SvgaFrame frame) {
    final alpha = frame.alpha.clamp(0, 1).toDouble();
    canvas.save();
    if (frame.transform case final transform?) canvas.transform(transform.toMatrix4());
    if (frame.clipPath case final clip?) canvas.clipPath(_path(clip));
    final image = _image(sprite.imageKey);
    final layout = frame.layout;
    if (image != null && layout != null && layout.width > 0 && layout.height > 0) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(layout.x, layout.y, layout.width, layout.height),
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, alpha)
          ..filterQuality = FilterQuality.medium,
      );
    }
    for (final shape in frame.shapes) {
      _paintShape(canvas, shape, alpha);
    }
    canvas.restore();
  }

  void _paintShape(Canvas canvas, SvgaShape shape, double alpha) {
    final style = shape.style;
    if (style == null) return;
    final path = switch (shape.type) {
      SvgaShapeType.path => shape.d == null ? null : _path(shape.d!),
      SvgaShapeType.rect => switch (shape.rect) {
        final rect? =>
          Path()..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(rect.x, rect.y, rect.width, rect.height),
              Radius.circular(math.max(0, shape.cornerRadius)),
            ),
          ),
        null => null,
      },
      SvgaShapeType.ellipse =>
        Path()..addOval(
          Rect.fromCenter(
            center: Offset(shape.ellipseCenterX, shape.ellipseCenterY),
            width: shape.radiusX * 2,
            height: shape.radiusY * 2,
          ),
        ),
      SvgaShapeType.keep => null,
    };
    if (path == null) return;
    canvas.save();
    if (shape.transform case final transform?) canvas.transform(transform.toMatrix4());
    if (style.fill case final fill? when fill.a > 0) {
      canvas.drawPath(path, Paint()..color = _color(fill, alpha));
    }
    if (style.stroke case final stroke? when stroke.a > 0 && style.strokeWidth > 0) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..color = _color(stroke, alpha)
        ..strokeWidth = style.strokeWidth
        ..strokeCap = switch (style.lineCap) {
          SvgaLineCap.butt => StrokeCap.butt,
          SvgaLineCap.round => StrokeCap.round,
          SvgaLineCap.square => StrokeCap.square,
        }
        ..strokeJoin = switch (style.lineJoin) {
          SvgaLineJoin.miter => StrokeJoin.miter,
          SvgaLineJoin.round => StrokeJoin.round,
          SvgaLineJoin.bevel => StrokeJoin.bevel,
        }
        ..strokeMiterLimit = style.miterLimit > 0 ? style.miterLimit : 4;
      canvas.drawPath(style.dash > 0 && style.gap > 0 ? _dashed(path, style) : path, paint);
    }
    canvas.restore();
  }

  Path _path(String data) => _paths[data] ??= SvgPath.parsePath(data);

  /// A matte layer's picture may be keyed without its `.matte`.
  ui.Image? _image(String key) {
    final image = images[key];
    if (image != null || !key.endsWith('.matte')) return image;
    return images[key.substring(0, key.length - '.matte'.length)];
  }

  static Color _color(SvgaColor color, double alpha) =>
      Color.from(alpha: color.a * alpha, red: color.r, green: color.g, blue: color.b);

  static Path _dashed(Path path, SvgaShapeStyle style) {
    final period = style.dash + style.gap;
    final dashed = Path();
    for (final metric in path.computeMetrics()) {
      var start = -(style.dashOffset % period);
      while (start < metric.length) {
        final from = math.max(start, 0.0);
        final to = math.min(start + style.dash, metric.length);
        if (to > from) dashed.addPath(metric.extractPath(from, to), Offset.zero);
        start += period;
      }
    }
    return dashed;
  }
}

/// Draws [composition]'s frame [frame] fitted into the paint's size by [fit], centred and clipped to the view box.
class SvgaPainter extends CustomPainter {
  SvgaPainter({required this.composition, required this.frame, required this.fit}) : super(repaint: frame);

  final SvgaComposition composition;
  final ValueListenable<int> frame;
  final BoxFit fit;

  @override
  void paint(Canvas canvas, Size size) {
    final box = composition.size;
    if (size.isEmpty || box.isEmpty) return;
    final fitted = applyBoxFit(fit, box, size);
    final source = Alignment.center.inscribe(fitted.source, Offset.zero & box);
    final destination = Alignment.center.inscribe(fitted.destination, Offset.zero & size);
    if (source.isEmpty || destination.isEmpty) return;
    canvas.save();
    canvas.clipRect(destination);
    canvas.translate(destination.left, destination.top);
    canvas.scale(destination.width / source.width, destination.height / source.height);
    canvas.translate(-source.left, -source.top);
    composition.paintFrame(canvas, frame.value);
    canvas.restore();
  }

  @override
  bool shouldRepaint(SvgaPainter oldDelegate) =>
      !identical(oldDelegate.composition, composition) || oldDelegate.fit != fit || oldDelegate.frame != frame;
}
