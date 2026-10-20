import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilifast/app/phone_frame.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sizes the test's view as KaiC's iPhone (440×956 at 3×, or 956×440 turned) with its safe areas, for a look-alike
/// check against his screenshots.
void showAsPhone(WidgetTester tester, {bool landscape = false}) {
  final size = landscape ? PhoneFrame.landscape : PhoneFrame.portrait;
  final padding = landscape ? PhoneFrame.landscapePadding : PhoneFrame.portraitPadding;
  final fake = FakeViewPadding(
    left: padding.left * 3,
    top: padding.top * 3,
    right: padding.right * 3,
    bottom: padding.bottom * 3,
  );
  tester.view
    ..physicalSize = size * 3
    ..devicePixelRatio = 3
    ..padding = fake
    ..viewPadding = fake;
  addTearDown(tester.view.reset);
}

/// Writes what the RepaintBoundary [boundary] finds as a 3× PNG at [path], for tools/screen_diff.py. Shots go to the
/// scratchpad, never into the repo.
Future<void> saveShot(WidgetTester tester, Finder boundary, String path) async {
  final render = tester.renderObject<RenderRepaintBoundary>(boundary);
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
