import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/landscape_chrome.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/player_ui/seek_bar.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player_session.dart';
import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import '../video/mixed_lines.dart' show appTheme;

/// Landscape's TV as KaiC's iPhone draws it, against 04 (at rest, 00:07/13:14) and the recording 102 (held and
/// released), measured in px at 3×. With BILIFAST_SHOTS naming a folder outside the repo, the shots are saved there.
void main() {
  late FakePlayerSession session;
  late PlayerUi playerUi;

  setUp(() {
    session = FakePlayerSession()..duration.value = 794;
    final chrome = ChromeState();
    final panels = PanelController();
    final orientation = OrientationController()..enterLandscape();
    addTearDown(() {
      session.dispose();
      chrome.dispose();
      panels.dispose();
      orientation.dispose();
    });
    playerUi = PlayerUi(
      session: session,
      chrome: chrome,
      panels: panels,
      orientation: orientation,
      device: orientation.controls,
      onBack: () {},
    );
  });

  Future<void> render(WidgetTester tester) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    await tester.runAsync(SeekBar.precache);
    showAsPhone(tester, landscape: true);
    BiliFonts.family = BiliFonts.system;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => RepaintBoundary(key: const ValueKey('screen'), child: child!),
        home: ColoredBox(color: BiliColors.videoBackground, child: LandscapeChrome(ui: playerUi)),
      ),
    );
    await tester.pumpAndSettle();
    session.readout.seconds.value = 7;
    await tester.pumpAndSettle();
  }

  Future<_Shot> shoot(WidgetTester tester, String name) async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('screen')));
    final shot = await tester.runAsync(() async {
      final image = await render.toImage(pixelRatio: 3);
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final shot = _Shot(rgba!, image.width);
      image.dispose();
      final shots = Platform.environment['BILIFAST_SHOTS'];
      if (shots != null) {
        File('$shots/seek-bar-$name.png')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(png!.buffer.asUint8List());
      }
      return shot;
    });
    return shot!;
  }

  // 04's bar starts at 62 pt and its TV's box is centred on 359 pt, the bar's centre.
  Offset thumb(double seconds) => Offset(62 + 9 + (832 - 18) * seconds / 794, 359);

  testWidgets('04: at rest, the TV\'s 12.5 × 9.5 pt screen where 04 has it, the eyes centred', (tester) async {
    await render(tester);
    final shot = await shoot(tester, 'rest');
    final screen = shot.screen(thumb(7) * 3);
    // 04: the screen's white is columns 215-251 and rows 1065-1091.
    expect(screen.left, closeTo(215, 1.5));
    expect(screen.right, closeTo(251, 1.5));
    expect(screen.top, closeTo(1065, 1.5));
    expect(screen.bottom, closeTo(1091, 1.5));
    expect(shot.eyesOffset(screen), closeTo(0, 1));
    expect(shot.eyeHeight(screen), closeTo(12, 1.5));
  });

  testWidgets('102: held and dragged later, the TV keeps its size and looks right; released, it blinks and rests', (
    tester,
  ) async {
    await render(tester);
    final rest = (await shoot(tester, 'rest')).screen(thumb(7) * 3);

    final finger = await tester.startGesture(thumb(7));
    await finger.moveBy(const Offset(20, 0));
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await finger.moveBy(const Offset(6, 0));
    }
    await tester.pumpAndSettle();
    final seekBar = tester.state<SeekBarState>(find.byType(SeekBar));
    final held = await shoot(tester, 'drag');
    final dragged = held.screen(thumb(session.position) * 3);
    expect(dragged.width, rest.width, reason: 'the TV doesn\'t grow under the finger');
    expect(dragged.height, rest.height);
    // 102, dragged later: the eyes 3.4 px right of the screen's centre.
    expect(held.eyesOffset(dragged), greaterThan(2.5));
    expect(seekBar.eyes, greaterThan(0.8));

    final released = session.position;
    await finger.up();
    // As the player would after the seek.
    session.readout.seconds.value = released;
    for (var i = 0; i < 40 && (seekBar.blink ?? 0) < 0.55; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final blink = await shoot(tester, 'blink');
    // 102: closed, the eyes are 4.5 px tall lines.
    expect(blink.eyeHeight(blink.screen(thumb(released) * 3)), lessThanOrEqualTo(6));

    await tester.pumpAndSettle();
    final after = await shoot(tester, 'released');
    final screen = after.screen(thumb(released) * 3);
    expect(after.eyesOffset(screen), closeTo(0, 1));
    expect(after.eyeHeight(screen), closeTo(12, 1.5));
  });
}

/// A 3× shot's pixels, read for the TV around a spot.
final class _Shot {
  _Shot(this._rgba, this._width);

  final ByteData _rgba;
  final int _width;

  int _luma(int x, int y) {
    final i = (y * _width + x) * 4;
    return (_rgba.getUint8(i) * 299 + _rgba.getUint8(i + 1) * 587 + _rgba.getUint8(i + 2) * 114) ~/ 1000;
  }

  bool _white(int x, int y) {
    final i = (y * _width + x) * 4;
    return _rgba.getUint8(i) > 225 && _rgba.getUint8(i + 1) > 225 && _rgba.getUint8(i + 2) > 225;
  }

  /// The white screen's pixel bounds around [centre], edges inclusive.
  Rect screen(Offset centre) {
    final cx = centre.dx.round(), cy = centre.dy.round();
    final xs = [for (var x = cx - 30; x <= cx + 30; x++) if (_white(x, cy + 10)) x];
    final ys = [for (var y = cy - 30; y <= cy + 30; y++) if (_white(xs.first + 3, y)) y];
    return Rect.fromLTRB(xs.first.toDouble(), ys.first.toDouble(), xs.last.toDouble(), ys.last.toDouble());
  }

  /// How far right of the screen's centre the eyes' mean sits, in px, read along the screen's middle row.
  double eyesOffset(Rect screen) {
    final y = screen.center.dy.round();
    var sum = 0.0, weight = 0.0;
    for (var x = screen.left.round() + 2; x <= screen.right.round() - 2; x++) {
      final dark = (200 - _luma(x, y)).clamp(0, 200).toDouble();
      sum += x * dark;
      weight += dark;
    }
    return sum / weight - screen.center.dx;
  }

  /// The darkest column's dark run through the screen's middle row, in px.
  int eyeHeight(Rect screen) {
    final y = screen.center.dy.round();
    var darkest = screen.left.round() + 2;
    for (var x = darkest; x <= screen.right.round() - 2; x++) {
      if (_luma(x, y) < _luma(darkest, y)) darkest = x;
    }
    var height = 0;
    for (var dy = -12; dy <= 12; dy++) {
      if (_luma(darkest, y + dy) < 110) height++;
    }
    return height;
  }
}
