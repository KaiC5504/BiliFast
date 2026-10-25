import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bili_core/api.dart' show VideoShot;
import 'package:bilifast/player_ui/seek_bar.dart';
import 'package:bilifast/player_ui/seek_preview.dart';
import 'package:bilifast/player_ui/vertical_chrome.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import '../video/mixed_lines.dart' show appTheme;
import 'vertical_chrome_test.dart' show Rig;

/// 竖屏 with the bar held, as KaiC's iPhone draws it, against 19 (a 3:4 video at 00:06 / 00:31) and 20 (a 16:9 video),
/// measured in px at 3×. With BILIFAST_SHOTS naming a folder outside the repo, the shots are saved there.
void main() {
  Future<_Shot> hold(WidgetTester tester, {required bool upright, required double duration}) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    await tester.runAsync(SeekBar.precache);
    showAsPhone(tester);
    BiliFonts.family = BiliFonts.system;

    final rig = Rig();
    addTearDown(() {
      rig.chrome.dispose();
      rig.panels.dispose();
      rig.orientation.dispose();
      rig.session.dispose();
    });
    rig.session
      ..duration.value = duration
      ..isVertical = upright
      ..seekFrames.value = VideoShot(
        sheets: const ['https://i0.hdslb.com/bfs/videoshot/a.jpg'],
        columns: 10,
        rows: 10,
        times: [for (var i = 0; i <= 100; i++) i * 2],
        cellWidth: upright ? 120 : 160,
        cellHeight: upright ? 160 : 90,
      );
    rig.session.clock.jump(duration * 0.2);
    rig.session.readout.refresh();

    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => RepaintBoundary(key: const ValueKey('screen'), child: child!),
        home: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: BiliColors.videoBackground),
            VerticalChrome(ui: rig.ui),
            Positioned.fill(child: SeekPreview(session: rig.session, shown: true, upright: true)),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final bar = tester.getRect(find.byKey(const ValueKey('vertical-bar')));
    final finger = await tester.startGesture(bar.centerLeft + const Offset(100, 0));
    await finger.moveBy(const Offset(20, 0));
    await tester.pump();
    await finger.moveBy(const Offset(4, 0));
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
        File('$shots/vertical-seek-${upright ? 19 : 20}.png')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(png!.buffer.asUint8List());
      }
      return shot;
    });
    await finger.up();
    await tester.pumpAndSettle();
    return shot!;
  }

  testWidgets('19: the held bar 6 pt and pink under the TV, the 81 × 144 frame and the time where 19 has them', (
    tester,
  ) async {
    final shot = await hold(tester, upright: true, duration: 31);

    // 19: the track's rows 2598-2615 at 1000 px, #262626 over the black; the played part #FB7299 from 36 px.
    final track = shot.run(1000, 2560, 2660, (pixel) => pixel == const (38, 38, 38));
    expect(track.first, closeTo(2598, 0.5));
    expect(track.last, closeTo(2615, 0.5));
    expect(shot.pixel(60, 2606), (251, 114, 153));
    // 19: the TV's 15 pt screen, 45 px wide, in the story TV's #333 body.
    final thumb = shot.thumbScreen(2606);
    expect(thumb.width, closeTo(45, 1.5));
    expect(shot.pixel(thumb.left.round() - 3, thumb.top.round()), (51, 51, 51));

    // 19: the border's outer edges at 538, 780.67, 1932 and 2364 px.
    final frame = shot.whiteBox(const Offset(660, 2150));
    expect(frame.left, closeTo(538, 1.5));
    expect(frame.right, closeTo(781, 1.5));
    expect(frame.top, closeTo(1932, 1.5));
    expect(frame.bottom, closeTo(2364, 1.5));

    // 19: 00:06's ink in rows 2406-2441 (802-814 pt) and columns 503-634, the line's last digit ending at 811 px.
    final position = shot.ink(2380, 2470, 450, 640);
    expect(position.top, closeTo(2406, 2));
    expect(position.bottom, closeTo(2442, 2));
    expect(position.left, closeTo(503, 9));
    expect(position.right, closeTo(635, 9));
    final line = shot.ink(2380, 2470, 450, 870);
    expect(line.right, closeTo(812, 9));
  });

  testWidgets('20: a wide video\'s frame is 144 × 81, its bottom where 19\'s is', (tester) async {
    final shot = await hold(tester, upright: false, duration: 257);
    // 20: the border's outer edges at 444, 876, 2121 and 2364 px.
    final frame = shot.whiteBox(const Offset(660, 2250));
    expect(frame.left, closeTo(444, 1.5));
    expect(frame.right, closeTo(876, 1.5));
    expect(frame.top, closeTo(2121, 1.5));
    expect(frame.bottom, closeTo(2364, 1.5));
  });
}

/// A 3× shot's pixels.
final class _Shot {
  _Shot(this._rgba, this._width);

  final ByteData _rgba;
  final int _width;

  (int, int, int) pixel(int x, int y) {
    final i = (y * _width + x) * 4;
    return (_rgba.getUint8(i), _rgba.getUint8(i + 1), _rgba.getUint8(i + 2));
  }

  bool _white(int x, int y) {
    final (r, g, b) = pixel(x, y);
    return r > 200 && g > 200 && b > 200;
  }

  /// The rows from [from] to [to] at column [x] whose pixel passes [test].
  List<int> run(int x, int from, int to, bool Function((int, int, int)) test) => [
    for (var y = from; y < to; y++)
      if (test(pixel(x, y))) y,
  ];

  /// The white screen of the TV on the bar row [y]: its widest white run.
  Rect thumbScreen(int y) {
    var best = Rect.zero;
    for (var row = y - 15; row <= y + 15; row++) {
      int? start;
      for (var x = 0; x < _width; x++) {
        if (_white(x, row)) {
          start ??= x;
        } else if (start != null) {
          if (x - start > best.width) best = Rect.fromLTRB(start.toDouble(), row.toDouble(), x.toDouble(), row + 1.0);
          start = null;
        }
      }
    }
    return best;
  }

  /// The outer edges (exclusive) of the white border around [inside], read along its middle row and column.
  Rect whiteBox(Offset inside) {
    final x = inside.dx.round(), y = inside.dy.round();
    var left = x, right = x, top = y, bottom = y;
    while (!_white(left, y)) {
      left--;
    }
    while (_white(left - 1, y)) {
      left--;
    }
    while (!_white(right, y)) {
      right++;
    }
    while (_white(right, y)) {
      right++;
    }
    while (!_white(x, top)) {
      top--;
    }
    while (_white(x, top - 1)) {
      top--;
    }
    while (!_white(x, bottom)) {
      bottom++;
    }
    while (_white(x, bottom)) {
      bottom++;
    }
    return Rect.fromLTRB(left.toDouble(), top.toDouble(), right.toDouble(), bottom.toDouble());
  }

  /// The bounds (bottom and right exclusive) of every pixel brighter than 60 in the region.
  Rect ink(int top, int bottom, int left, int right) {
    var minX = right, maxX = left, minY = bottom, maxY = top;
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        final (r, g, b) = pixel(x, y);
        if (r > 60 || g > 60 || b > 60) {
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
