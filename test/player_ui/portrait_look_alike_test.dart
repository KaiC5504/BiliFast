import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bilifast/player/bili_player.dart' show PlayerStatus, StatusChanged;
import 'package:bilifast/player_ui/portrait_controls.dart';
import 'package:bilifast/player_ui/seek_bar.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/player_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import '../video/mixed_lines.dart' show appTheme;
import 'portrait_controls_test.dart' show Rig;

/// The small player's controls as KaiC's iPhone draws them, against 17 (a 3:4 video paused at 00:00/00:31), measured
/// in px at 3×. With BILIFAST_SHOTS naming a folder outside the repo, the shot is saved there for tools/screen_diff.py.
void main() {
  testWidgets('17: an upright video\'s row ends at 竖屏, its corners, pill, time and bar where 17 has them', (
    tester,
  ) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    await tester.runAsync(SeekBar.precache);
    showAsPhone(tester);
    BiliFonts.family = BiliFonts.system;

    final rig = Rig()
      ..session.isVertical = true
      ..session.videoShape = (width: 1080, height: 1440)
      ..session.duration.value = 31;
    addTearDown(() {
      rig.chrome.dispose();
      rig.panels.dispose();
      rig.orientation.dispose();
      rig.session.dispose();
    });
    rig.session.player.emit(const StatusChanged(PlayerStatus.paused));
    final height = inlinePlayerHeight(440, video: rig.session.videoShape);

    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => RepaintBoundary(key: const ValueKey('screen'), child: child!),
        home: Material(
          color: BiliColors.videoBackground,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 62,
                width: 440,
                height: height,
                // A flat stand-in for 17's picture under the controls' shade.
                child: ColoredBox(color: const Color(0xFF6B625B), child: PortraitControls(ui: rig.ui)),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('screen')));
    final shot = await tester.runAsync(() async {
      final image = await render.toImage(pixelRatio: 3);
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final shot = _Shot(rgba!, image.width);
      image.dispose();
      final shots = Platform.environment['BILIFAST_SHOTS'];
      if (shots != null) {
        File('$shots/small-player-17.png')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(png!.buffer.asUint8List());
      }
      return shot;
    });

    // 17: the corners' white in columns 1229-1272 and rows 1854-1905; no 全屏 corners past them.
    final corners = shot!.white(1852, 1915, 1190, 1320);
    expect(corners.left, closeTo(1229, 1));
    expect(corners.right, closeTo(1273, 1));
    expect(corners.top, closeTo(1854, 1.5));
    expect(corners.bottom, closeTo(1906, 1.5));
    // 17: the 竖屏 pill's text in columns 1247-1290 and rows 1821-1841.
    final pill = shot.white(1815, 1848, 1236, 1310);
    expect(pill.left, closeTo(1247, 2));
    expect(pill.right, closeTo(1291, 2));
    expect(pill.top, closeTo(1821, 1.5));
    expect(pill.bottom, closeTo(1842, 1.5));
    // 17: 00:00/00:31's digits end at 1152 px, in rows 1867-1898.
    final time = shot.white(1855, 1910, 900, 1190);
    expect(time.right, closeTo(1153, 3));
    expect(time.top, closeTo(1867, 1.5));
    expect(time.bottom, closeTo(1899, 1.5));
  });
}

/// A 3× shot's pixels.
final class _Shot {
  _Shot(this._rgba, this._width);

  final ByteData _rgba;
  final int _width;

  bool _white(int x, int y) {
    final i = (y * _width + x) * 4;
    return _rgba.getUint8(i) > 225 && _rgba.getUint8(i + 1) > 225 && _rgba.getUint8(i + 2) > 225;
  }

  /// The bounds (bottom and right exclusive) of the near-white pixels in the region.
  Rect white(int top, int bottom, int left, int right) {
    var minX = right, maxX = left, minY = bottom, maxY = top;
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        if (_white(x, y)) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    return Rect.fromLTRB(minX.toDouble(), minY.toDouble(), maxX + 1.0, maxY + 1.0);
  }
}
