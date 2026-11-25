import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bili_core/api.dart' show QualityOption;
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
import 'landscape_chapter_line_test.dart' show chapters;
import 'landscape_chrome_test.dart' show twoParts;

/// 274 (01:48/04:01 in 2.3, Hi-Res on, its two notes) and 273 (章节's strip) as KaiC's iPhone draws them, measured in
/// px at 3× on black (the notes on grey, to find their boxes). With BILIFAST_SHOTS naming a folder outside the repo,
/// the shots are saved there.
void main() {
  late FakePlayerSession session;
  late PanelController panels;

  Future<_Shot> render(WidgetTester tester, String name, {Color ground = const Color(0xFF000000)}) async {
    session = FakePlayerSession()
      ..duration.value = 241
      ..chapters = chapters
      ..hiResOffered = true
      ..hiResOn = true
      ..episodes = twoParts
      ..qualities = const [QualityOption(id: 120, name: '4K 超清')]
      ..quality = 120;
    final chrome = ChromeState();
    panels = PanelController();
    final orientation = OrientationController()..enterLandscape();
    addTearDown(() {
      session.dispose();
      chrome.dispose();
      panels.dispose();
      orientation.dispose();
    });
    final playerUi = PlayerUi(
      session: session,
      chrome: chrome,
      panels: panels,
      orientation: orientation,
      device: orientation.controls,
      onBack: () {},
    );
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
        home: ColoredBox(color: ground, child: LandscapeChrome(ui: playerUi)),
      ),
    );
    await tester.pumpAndSettle();
    session.readout.seconds.value = 108;
    session.notes
      ..add('Hi-Res无损音质开启中，请稍候')
      ..add('Hi-Res无损音质已开启');
    if (name == 'strip') panels.open(PlayerPanel.chapters);
    await tester.pumpAndSettle();
    final shot = await _Shot.take(tester, name);
    await tester.pump(const Duration(seconds: 3));
    return shot;
  }

  bool white(Color c) => c.r > 0.67 && c.g > 0.67 && c.b > 0.67;

  testWidgets('274: 章节 and its title after the time, each dot on the digits, › after the title', (tester) async {
    final shot = await render(tester, 'line');
    final runs = shot.runs(170, 680, 940, 1000, white);
    // The time's eleven glyphs, then ·, 章, 节, ·, 2, ., 3 and ›.
    expect(runs, hasLength(19));
    final [dot1, zhang, jie, dot2, two, _, three, chevron] = runs.sublist(11);
    final digits = runs[0];
    int clear(_Run a, _Run b) => b.left - a.right - 1;
    // 274: 21 clear after the first dot, 19 either side of the second, 20 before ›.
    expect(clear(dot1, zhang), closeTo(21, 2));
    expect(clear(jie, dot2), closeTo(19, 2));
    expect(clear(dot2, two), closeTo(19, 2));
    expect(clear(three, chevron), closeTo(20, 2));
    expect(dot1.width, closeTo(5, 1));
    // 274: the dots' middle half a px above the digits', ›'s 2 px above, › 19 × 33 px.
    expect(dot1.middle - digits.middle, closeTo(-0.5, 1.5));
    expect(chevron.middle - digits.middle, closeTo(-2, 1.5));
    expect(chevron.width, closeTo(19, 1));
    expect(chevron.height, closeTo(33, 1.5));
    expect(zhang.width, closeTo(31, 2));
    expect(two.left - jie.right, closeTo(550 - 506, 3));
  });

  testWidgets("274: Hi-Res无损 in pink between 倍速 and 4K, its 大会员 tag as 274's", (tester) async {
    final shot = await render(tester, 'row');
    bool lit(Color c) => c.r > 0.67 && (c.r - c.b > 0.08 || c.b > 0.67);
    final row = shot.runs(1700, 2760, 1166, 1215, lit, merge: 8);
    final [_, speed, hiRes, wu, fourK] = row;
    // 274: 倍速 ends 104 px clear of Hi-Res; Hi-Res's s 10 px clear of 无; 无损 ends 118 clear of 4K.
    expect(hiRes.left - speed.right - 1, closeTo(104, 2));
    expect(wu.left - hiRes.right - 1, closeTo(10, 1.5));
    expect(wu.right - hiRes.left + 1, closeTo(216, 3));
    expect(fourK.left - wu.right - 1, closeTo(118, 3));
    // 274's centres from 4K's, within half a pt: 倍速 504.5 px before it, Hi-Res 297, 无损 184.
    double centre(_Run run) => (run.left + run.right) / 2;
    expect(centre(fourK) - centre(speed), closeTo(504.5, 1.5));
    expect(centre(fourK) - centre(hiRes), closeTo(297, 1.5));
    expect(centre(fourK) - centre(wu), closeTo(184, 1.5));
    final pink = shot.pixel(hiRes.left + 2, (hiRes.top + hiRes.bottom) ~/ 2 + 6);
    expect(pink, HiResButtonTheme.on);

    bool pinkInk(Color c) => c.r - c.b > 0.15;
    final tag = shot.runs(2300, 2520, 1115, 1162, pinkInk, merge: 20).single;
    // 274: the outline 90 px wide and 35 px tall, its right 29 px past 无损's ink.
    expect(tag.width, closeTo(90, 2));
    expect(tag.height, closeTo(35, 2));
    expect(tag.right - wu.right, closeTo(29, 2));
  });

  testWidgets("274: the two notes at the safe area's left, 103 px tall, 24 apart, their words where 274's sit", (
    tester,
  ) async {
    final shot = await render(tester, 'notes', ground: const Color(0xFF808080));
    bool dark(Color c) => c.r < 0.25;
    // Down the column 200 px in, left of the words: the boxes' rows.
    final rows = shot.column(200, 650, 960, dark);
    expect(rows, hasLength(2));
    expect(rows[0].$1, closeTo(697, 1.5));
    expect(rows[0].$2, closeTo(799, 1.5));
    expect(rows[1].$1, closeTo(824, 1.5));
    expect(rows[1].$2, closeTo(926, 1.5));
    expect(shot.row(870, 150, 300, dark).first.$1, closeTo(186, 1));
    final words = shot.runs(190, 640, 826, 925, white);
    // 274: H's ink from 225, 863-887; 无 from 343.
    expect(words.first.left, closeTo(225, 2));
    expect(words.first.top, closeTo(863, 2));
    expect(words.first.bottom, closeTo(887, 2));
    expect(words[6].left, closeTo(343, 3));
  });

  testWidgets("273: the strip's band, its rule at 01:48 and the titles centred on their stretches", (tester) async {
    final shot = await render(tester, 'strip');
    // 273 over black, 100 px in: clear above 1254, 21 at 1258, 76 at 1270, 150 at 1286, #AEB1B5 from 1292.
    double grey(int y) => shot.pixel(100, y).r * 255;
    expect(grey(1250), 0);
    expect(grey(1258), closeTo(21, 8));
    expect(grey(1270), closeTo(76, 8));
    expect(grey(1286), closeTo(150, 8));
    expect(shot.pixel(100, 1300), ChapterStripTheme.fill);
    bool lighter(Color c) => c.r * 255 > 180;
    final rule = shot.row(1300, 1270, 1300, lighter);
    expect(rule.single.$1, closeTo(1285, 2));
    expect(rule.single.$2 - rule.single.$1, lessThanOrEqualTo(3));
    // White over the band's light grey.
    final titles = shot.runs(600, 2160, 1268, 1305, (c) => c.r > 0.85, merge: 6);
    final [one, twoThree] = titles;
    // 273: 1's ink 636-644 and 1276-1296; 2.3's 2057-2095.
    expect((one.left + one.right) / 2, closeTo(640, 2));
    expect(one.top, closeTo(1276, 2));
    expect(one.bottom, closeTo(1296, 2));
    expect((twoThree.left + twoThree.right) / 2, closeTo(2076, 2));
  });
}

final class _Run {
  const _Run(this.left, this.right, this.top, this.bottom);

  final int left;
  final int right;
  final int top;
  final int bottom;

  int get width => right - left + 1;
  int get height => bottom - top + 1;
  double get middle => (top + bottom) / 2;

  @override
  String toString() => '[$left-$right, $top-$bottom]';
}

/// A 3× shot's pixels.
final class _Shot {
  _Shot(this._rgba, this._width);

  final ByteData _rgba;
  final int _width;

  static Future<_Shot> take(WidgetTester tester, String name) async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('screen')));
    final shot = await tester.runAsync(() async {
      final image = await render.toImage(pixelRatio: 3);
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final shot = _Shot(rgba!, image.width);
      image.dispose();
      final shots = Platform.environment['BILIFAST_SHOTS'];
      if (shots != null) {
        File('$shots/chapter-hi-res-$name.png')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(png!.buffer.asUint8List());
      }
      return shot;
    });
    return shot!;
  }

  Color pixel(int x, int y) {
    final i = (y * _width + x) * 4;
    return Color.fromARGB(255, _rgba.getUint8(i), _rgba.getUint8(i + 1), _rgba.getUint8(i + 2));
  }

  /// The columns in [x0, x1) where any pixel in rows [y0, y1) passes [lit], joined across gaps of up to [merge].
  List<_Run> runs(int x0, int x1, int y0, int y1, bool Function(Color) lit, {int merge = 0}) {
    final out = <_Run>[];
    int? left, right, top, bottom;
    for (var x = x0; x < x1; x++) {
      final ys = [for (var y = y0; y < y1; y++) if (lit(pixel(x, y))) y];
      if (ys.isNotEmpty) {
        if (left != null && x - right! <= merge + 1) {
          right = x;
          top = ys.first < top! ? ys.first : top;
          bottom = ys.last > bottom! ? ys.last : bottom;
        } else {
          if (left != null) out.add(_Run(left, right!, top!, bottom!));
          (left, right, top, bottom) = (x, x, ys.first, ys.last);
        }
      }
    }
    if (left != null) out.add(_Run(left, right!, top!, bottom!));
    return out;
  }

  /// The stretches of rows [y0, y1) in column [x] that pass [lit], ends inclusive.
  List<(int, int)> column(int x, int y0, int y1, bool Function(Color) lit) =>
      _stretches(y0, y1, (y) => lit(pixel(x, y)));

  /// The stretches of columns [x0, x1) in row [y] that pass [lit], ends inclusive.
  List<(int, int)> row(int y, int x0, int x1, bool Function(Color) lit) => _stretches(x0, x1, (x) => lit(pixel(x, y)));

  static List<(int, int)> _stretches(int from, int to, bool Function(int) lit) {
    final out = <(int, int)>[];
    int? start;
    for (var i = from; i < to; i++) {
      if (lit(i)) {
        start ??= i;
      } else if (start != null) {
        out.add((start, i - 1));
        start = null;
      }
    }
    if (start != null) out.add((start, to - 1));
    return out;
  }
}
