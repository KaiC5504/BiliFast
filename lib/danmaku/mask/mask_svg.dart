import 'dart:typed_data';
import 'dart:ui';

import '../../skin/svga/svg_path.dart';

/// One mask frame's SVG, reduced to what clipping needs: the viewBox's size, the transform into it (the `<g>`'s, then
/// the viewBox's origin moved to 0, 0) and every path's data, joined. Plain data, so it is read off the UI isolate and
/// sent back.
final class MaskShape {
  const MaskShape({required this.box, required this.transform, required this.segments});

  final Size box;

  /// A 2D affine as SVG's `matrix(a b c d e f)` writes it.
  final Float64List transform;

  final List<PathSegment> segments;

  static final _svgTag = RegExp(r'<svg\b[^>]*>');
  static final _gTag = RegExp(r'<g\b[^>]*>');
  static final _pathTag = RegExp(r'<path\b[^>]*>');
  static final _viewBox = _attribute('viewBox');
  static final _width = _attribute('width');
  static final _height = _attribute('height');
  static final _transformAttribute = _attribute('transform');
  static final _d = _attribute('d');
  static final _number = RegExp(r'[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?');
  static final _transformItem = RegExp(r'(\w+)\s*\(([^)]*)\)');

  static RegExp _attribute(String name) => RegExp('\\s$name\\s*=\\s*(["\'])(.*?)\\1', dotAll: true);

  /// Reads potrace's SVG. Throws [FormatException] when it has no size or no path, or a transform other than matrix,
  /// translate and scale.
  static MaskShape parse(String text) {
    final svgTag = _svgTag.firstMatch(text)?[0];
    if (svgTag == null) throw const FormatException('no <svg>');
    final (box, origin) = _box(svgTag);
    var transform = _translate(-origin.dx, -origin.dy);
    final g = _gTag.firstMatch(text)?[0];
    final gTransform = g == null ? null : _transformAttribute.firstMatch(g)?[2];
    if (gTransform != null) transform = _multiply(transform, _parseTransform(gTransform));
    final segments = <PathSegment>[];
    for (final tag in _pathTag.allMatches(text)) {
      final data = _d.firstMatch(tag[0]!)?[2];
      if (data != null) segments.addAll(SvgPath.parse(data));
    }
    if (segments.isEmpty) throw const FormatException('no path');
    return MaskShape(box: box, transform: transform, segments: segments);
  }

  /// The path in the box's units, y down; filled even-odd, so a hole stays a hole whichever way potrace turned it, and
  /// an island inside one fills again.
  Path toPath() {
    final raw = SvgPath.toPath(segments);
    final t = transform;
    final path = _isIdentity(t)
        ? raw
        : raw.transform(Float64List.fromList([t[0], t[1], 0, 0, t[2], t[3], 0, 0, 0, 0, 1, 0, t[4], t[5], 0, 1]));
    return path..fillType = PathFillType.evenOdd;
  }

  static (Size, Offset) _box(String svgTag) {
    final viewBox = _viewBox.firstMatch(svgTag)?[2];
    if (viewBox != null) {
      final values = [for (final match in _number.allMatches(viewBox)) double.parse(match[0]!)];
      if (values.length == 4 && values[2] > 0 && values[3] > 0) {
        return (Size(values[2], values[3]), Offset(values[0], values[1]));
      }
    }
    // Without a viewBox the user space is the width and height ("180.000000pt").
    double? length(RegExp attribute) {
      final value = attribute.firstMatch(svgTag)?[2];
      final match = value == null ? null : _number.matchAsPrefix(value.trim());
      return match == null ? null : double.parse(match[0]!);
    }

    final width = length(_width);
    final height = length(_height);
    if (width == null || height == null || width <= 0 || height <= 0) throw const FormatException('no size');
    return (Size(width, height), Offset.zero);
  }

  /// SVG applies a list's items right to left to a point, so they multiply left to right.
  static Float64List _parseTransform(String list) {
    var result = _translate(0, 0);
    for (final item in _transformItem.allMatches(list)) {
      final v = [for (final match in _number.allMatches(item[2]!)) double.parse(match[0]!)];
      final Float64List next;
      switch ((item[1], v.length)) {
        case ('matrix', 6):
          next = Float64List.fromList(v);
        case ('translate', 1):
          next = _translate(v[0], 0);
        case ('translate', 2):
          next = _translate(v[0], v[1]);
        case ('scale', 1):
          next = Float64List.fromList([v[0], 0, 0, v[0], 0, 0]);
        case ('scale', 2):
          next = Float64List.fromList([v[0], 0, 0, v[1], 0, 0]);
        default:
          throw const FormatException('unsupported transform');
      }
      result = _multiply(result, next);
    }
    return result;
  }

  static Float64List _translate(double x, double y) => Float64List.fromList([1, 0, 0, 1, x, y]);

  static Float64List _multiply(Float64List m, Float64List n) => Float64List.fromList([
    m[0] * n[0] + m[2] * n[1],
    m[1] * n[0] + m[3] * n[1],
    m[0] * n[2] + m[2] * n[3],
    m[1] * n[2] + m[3] * n[3],
    m[0] * n[4] + m[2] * n[5] + m[4],
    m[1] * n[4] + m[3] * n[5] + m[5],
  ]);

  static bool _isIdentity(Float64List t) => t[0] == 1 && t[1] == 0 && t[2] == 0 && t[3] == 1 && t[4] == 0 && t[5] == 0;
}
