import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// One bar of a playing mark as drawn, in pt from the picture's top left: its width across its middle, its height,
/// its centre, and the colour at that centre.
typedef Bar = ({double width, double height, double x, double y, Color ink});

/// The bars [boundary] draws inside [area] (pt, the boundary's own; all of it when null), read from a 3× picture of
/// it, left to right. Coverage is the alpha on a clear background, or the distance from [over] (an opaque one) as a
/// share of the area's furthest pixel.
Future<List<Bar>> barsIn(WidgetTester tester, Finder boundary, {Rect? area, Color? over}) async {
  const scale = 3.0;
  final render = tester.renderObject<RenderRepaintBoundary>(boundary);
  final (width, height, rgba) = (await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: scale);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
    final size = (image.width, image.height);
    image.dispose();
    return (size.$1, size.$2, bytes);
  }))!;
  final left = area == null ? 0 : (area.left * scale).floor();
  final right = area == null ? width : math.min(width, (area.right * scale).ceil());
  final top = area == null ? 0 : (area.top * scale).floor();
  final bottom = area == null ? height : math.min(height, (area.bottom * scale).ceil());

  double distance(int x, int y) {
    final at = (y * width + x) * 4;
    return math.sqrt(
      math.pow(rgba.getUint8(at) - (over!.r * 255), 2) +
          math.pow(rgba.getUint8(at + 1) - (over.g * 255), 2) +
          math.pow(rgba.getUint8(at + 2) - (over.b * 255), 2),
    );
  }

  var furthest = 1.0;
  if (over != null) {
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        furthest = math.max(furthest, distance(x, y));
      }
    }
  }

  double alpha(int x, int y) => over == null ? rgba.getUint8((y * width + x) * 4 + 3) / 255 : distance(x, y) / furthest;

  /// The covered length of a run of pixels and its middle, in pt from the run's start.
  (double, double) span(List<double> coverage) {
    var total = 0.0, moment = 0.0;
    for (final (i, value) in coverage.indexed) {
      total += value;
      moment += (i + 0.5) * value;
    }
    return (total / scale, moment / total / scale);
  }

  final columns = <List<int>>[];
  for (var x = left; x < right; x++) {
    var most = 0.0;
    for (var y = top; y < bottom; y++) {
      most = math.max(most, alpha(x, y));
    }
    if (most <= 0.05) continue;
    if (columns.isNotEmpty && columns.last.last == x - 1) {
      columns.last.add(x);
    } else {
      columns.add([x]);
    }
  }
  return [
    for (final bar in columns)
      () {
        final (tall, middle) = span([for (var y = top; y < bottom; y++) bar.map((x) => alpha(x, y)).reduce(math.max)]);
        final row = top + (middle * scale).floor();
        final (wide, centre) = span([for (final x in bar) alpha(x, row)]);
        final x = bar.first + (centre * scale).floor();
        final at = (row * width + x) * 4;
        return (
          width: wide,
          height: tall,
          x: bar.first / scale + centre,
          y: top / scale + middle,
          ink: Color.fromARGB(rgba.getUint8(at + 3), rgba.getUint8(at), rgba.getUint8(at + 1), rgba.getUint8(at + 2)),
        );
      }(),
  ];
}
