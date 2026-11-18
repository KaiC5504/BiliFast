import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The colours [boundary] paints at [points] (in pt), read off one picture of it at the phone's 3 px per pt, so a
/// 1/3 pt hairline fills a pixel row of its own.
Future<List<Color>> pixelsAt(WidgetTester tester, Finder boundary, List<Offset> points) async {
  final render = tester.renderObject<RenderRepaintBoundary>(boundary);
  final colours = <Color>[];
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 3);
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
    for (final point in points) {
      final at = ((point.dy * 3).floor() * image.width + (point.dx * 3).floor()) * 4;
      colours.add(
        Color.fromARGB(data.getUint8(at + 3), data.getUint8(at), data.getUint8(at + 1), data.getUint8(at + 2)),
      );
    }
    image.dispose();
  });
  return colours;
}
