import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilifast/app/form_factor.dart';
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

/// Sizes the test's view as KaiC's iPad Pro 11" (834×1194 at 2×, or 1194×834 sideways) with its safe areas, for a
/// look-alike check against `local/official-app-reference/ipad/`. Sets [FormFactor.device] to the iPad for the test.
void showAsPad(WidgetTester tester, {bool landscape = false}) {
  final size = landscape ? PhoneFrame.padLandscape : PhoneFrame.padPortrait;
  const padding = PhoneFrame.padPadding;
  final fake = FakeViewPadding(top: padding.top * 2, bottom: padding.bottom * 2);
  tester.view
    ..physicalSize = size * 2
    ..devicePixelRatio = 2
    ..padding = fake
    ..viewPadding = fake;
  FormFactor.device = FormFactor.pad;
  addTearDown(() {
    tester.view.reset();
    FormFactor.device = FormFactor.phone;
  });
}

/// Writes [boundary] as a PNG at [path] at [pixelRatio] (3 for the iPhone, 2 for the iPad) for tools/screen_diff.py.
/// Shots go to the scratchpad, never into the repo.
Future<void> saveShot(WidgetTester tester, Finder boundary, String path, {double pixelRatio = 3}) async {
  final render = tester.renderObject<RenderRepaintBoundary>(boundary);
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
