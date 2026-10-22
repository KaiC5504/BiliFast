import 'dart:typed_data';

/// A decoded `.svga` file (github.com/svga/SVGA-Format), before its pictures are decoded.
final class SvgaMovie {
  const SvgaMovie({
    required this.version,
    required this.width,
    required this.height,
    required this.fps,
    required this.frames,
    required this.images,
    required this.sprites,
  });

  final String version;

  /// The view box everything is laid out in.
  final double width;
  final double height;
  final int fps;
  final int frames;

  /// Picture files by key; entries that aren't pictures (2.x keeps its audio here too) are left out.
  final Map<String, Uint8List> images;

  /// Bottom first.
  final List<SvgaSprite> sprites;
}

final class SvgaSprite {
  const SvgaSprite({required this.imageKey, this.matteKey, required this.frames});

  final String imageKey;

  /// The [imageKey] of the sprite whose alpha masks this one.
  final String? matteKey;

  /// One per movie frame, with the omitted parts already filled in (see `SvgaDecoder`).
  final List<SvgaFrame> frames;

  SvgaFrame frameAt(int index) => index >= 0 && index < frames.length ? frames[index] : SvgaFrame.hidden;
}

final class SvgaFrame {
  const SvgaFrame({this.alpha = 0, this.layout, this.transform, this.clipPath, this.shapes = const []});

  static const hidden = SvgaFrame();

  final double alpha;

  /// Where the sprite's picture is drawn, before [transform].
  final SvgaRect? layout;

  /// Null is the identity.
  final SvgaTransform? transform;

  /// SVG path data the sprite is clipped to, in its own coordinates.
  final String? clipPath;

  final List<SvgaShape> shapes;

  bool get visible => alpha > 0;
}

final class SvgaRect {
  const SvgaRect(this.x, this.y, this.width, this.height);

  final double x;
  final double y;
  final double width;
  final double height;
}

/// A 2D affine matrix as CSS writes it: x' = a·x + c·y + tx, y' = b·x + d·y + ty.
final class SvgaTransform {
  const SvgaTransform({this.a = 1, this.b = 0, this.c = 0, this.d = 1, this.tx = 0, this.ty = 0});

  final double a;
  final double b;
  final double c;
  final double d;
  final double tx;
  final double ty;

  /// Column-major, as `Canvas.transform` takes it.
  Float64List toMatrix4() => Float64List.fromList([a, b, 0, 0, c, d, 0, 0, 0, 0, 1, 0, tx, ty, 0, 1]);
}

enum SvgaShapeType { path, rect, ellipse, keep }

final class SvgaShape {
  const SvgaShape({
    required this.type,
    this.d,
    this.rect,
    this.cornerRadius = 0,
    this.ellipseCenterX = 0,
    this.ellipseCenterY = 0,
    this.radiusX = 0,
    this.radiusY = 0,
    this.style,
    this.transform,
  });

  final SvgaShapeType type;

  /// [SvgaShapeType.path]'s path data.
  final String? d;

  /// [SvgaShapeType.rect]'s box.
  final SvgaRect? rect;
  final double cornerRadius;

  final double ellipseCenterX;
  final double ellipseCenterY;
  final double radiusX;
  final double radiusY;

  final SvgaShapeStyle? style;
  final SvgaTransform? transform;
}

enum SvgaLineCap { butt, round, square }

enum SvgaLineJoin { miter, round, bevel }

final class SvgaShapeStyle {
  const SvgaShapeStyle({
    this.fill,
    this.stroke,
    this.strokeWidth = 0,
    this.lineCap = SvgaLineCap.butt,
    this.lineJoin = SvgaLineJoin.miter,
    this.miterLimit = 0,
    this.dash = 0,
    this.gap = 0,
    this.dashOffset = 0,
  });

  final SvgaColor? fill;
  final SvgaColor? stroke;
  final double strokeWidth;
  final SvgaLineCap lineCap;
  final SvgaLineJoin lineJoin;
  final double miterLimit;
  final double dash;
  final double gap;
  final double dashOffset;
}

/// Channels from 0 to 1.
final class SvgaColor {
  const SvgaColor(this.r, this.g, this.b, this.a);

  final double r;
  final double g;
  final double b;
  final double a;
}
