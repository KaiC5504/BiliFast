import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/look_alike.dart';
import 'sheet_rig.dart';

/// The shot's pixels at 3×, read by point.
final class Pixels {
  Pixels(this.width, this.bytes);

  final int width;
  final ByteData bytes;

  Color at(double x, double y) {
    final offset = ((y * 3).round() * width + (x * 3).round()) * 4;
    return Color.fromARGB(
      bytes.getUint8(offset + 3),
      bytes.getUint8(offset),
      bytes.getUint8(offset + 1),
      bytes.getUint8(offset + 2),
    );
  }
}

Future<Pixels> capture(WidgetTester tester) async {
  final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(SheetRig.shot));
  late Pixels pixels;
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    pixels = Pixels(image.width, bytes!);
    image.dispose();
  });
  return pixels;
}

Color inkOf(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text).first).text.style!.color!;

/// The small player's light sheets in 深色模式, as 258: the sheet Ga12, its squares and cards Ga11, text Ga10's night.
/// With BILIFAST_SHOTS naming a folder outside the repo, the 3× shots are saved there for tools/screen_diff.py.
void main() {
  final shots = Platform.environment['BILIFAST_SHOTS'];

  testWidgets("258: ⋮'s sheet, squares and card at night", (tester) async {
    await tester.runAsync(loadIconFonts);
    final rig = await pumpSheetRig(tester, look: true, dark: true, session: singleVideo());
    await openSheet(tester, rig, PlayerPanel.more);
    expect(tester.takeException(), isNull);
    if (shots != null) await saveShot(tester, find.byKey(SheetRig.shot), '$shots/258-ours.png');
    final pixels = await capture(tester);
    const top = SheetRig.playerBottom;
    expect(pixels.at(4, top + 14), const Color(0xFF202123));
    expect(
      pixels.at(DownloadSheetTheme.tileLead + 3, top + 38),
      const Color(0xFF242628),
    );
    expect(pixels.at(DownloadSheetTheme.cardInset + 3, tester.getCenter(find.text('倍速')).dy), const Color(0xFF242628));
    expect(inkOf(tester, '倍速'), const Color(0xFFE7E9EB));
    expect(inkOf(tester, '不感兴趣'), const Color(0xFFA2A7AE));
  });

  testWidgets("弹幕设置's portrait sheet takes ⋮'s night colours", (tester) async {
    final rig = await pumpSheetRig(tester, look: true, dark: true, session: singleVideo());
    await openSheet(tester, rig, PlayerPanel.danmakuSettings);
    expect(tester.takeException(), isNull);
    if (shots != null) await saveShot(tester, find.byKey(SheetRig.shot), '$shots/40-dark-ours.png');
    final pixels = await capture(tester);
    expect(pixels.at(4, SheetRig.playerBottom + 14), const Color(0xFF202123));
    final card = tester.getTopLeft(find.text('不透明度').first);
    expect(pixels.at(DanmakuPanelTheme.inset + 2, card.dy), const Color(0xFF242628));
    expect(inkOf(tester, '不透明度'), const Color(0xFFE7E9EB));
  });

  testWidgets('the light sheets are as they were by day', (tester) async {
    final rig = await pumpSheetRig(tester, look: true, session: singleVideo());
    await openSheet(tester, rig, PlayerPanel.more);
    final pixels = await capture(tester);
    expect(pixels.at(4, SheetRig.playerBottom + 14), const Color(0xFFF6F7F8));
    expect(pixels.at(DownloadSheetTheme.cardInset + 3, tester.getCenter(find.text('倍速')).dy), const Color(0xFFFFFFFF));
    expect(inkOf(tester, '倍速'), const Color(0xFF18191C));
  });
}
