import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bilifast/home/home_tab_bar.dart';
import 'package:bilifast/home/tab_bar_icons.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The icon drawn at 3× on white: its pixels, row by row as RGBA.
Future<(ByteData, int)> _render(WidgetTester tester, Widget icon) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Center(
      child: RepaintBoundary(
        key: key,
        child: ColoredBox(color: const Color(0xFFFFFFFF), child: icon),
      ),
    ),
  );
  expect(tester.takeException(), isNull);
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  late ByteData bytes;
  late int width;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    width = image.width;
    bytes = (await image.toByteData())!;
    image.dispose();
  });
  return (bytes, width);
}

/// How many pixels are inked, and the inked pixels' summed red, green and blue.
(int, int, int, int) _ink(ByteData bytes) {
  var count = 0, red = 0, green = 0, blue = 0;
  for (var i = 0; i < bytes.lengthInBytes; i += 4) {
    final r = bytes.getUint8(i), g = bytes.getUint8(i + 1), b = bytes.getUint8(i + 2);
    if (r + g + b < 3 * 200) {
      count++;
      red += r;
      green += g;
      blue += b;
    }
  }
  return (count, red, green, blue);
}

void main() {
  testWidgets('each line glyph paints in its slot, grey unselected and pink selected', (tester) async {
    for (final tab in HomeTab.values.where((tab) => tab != HomeTab.post)) {
      for (final selected in [false, true]) {
        await tester.pumpWidget(const SizedBox.shrink());
        final (bytes, width) = await _render(tester, HomeTabIcon(tab, selected: selected));
        expect(width, (TabIconTheme.size * 3).round(), reason: '$tab');
        final (count, red, green, _) = _ink(bytes);
        expect(count, greaterThan(150), reason: '$tab selected $selected draws');
        final reddish = red / count - green / count;
        if (selected) {
          expect(reddish, greaterThan(80), reason: '$tab selected is pink');
        } else {
          expect(reddish.abs(), lessThan(20), reason: '$tab unselected is grey');
        }
      }
    }
  });

  testWidgets('首页 and 我的 change their faces when selected', (tester) async {
    for (final tab in [HomeTab.home, HomeTab.mine]) {
      final (off, _) = await _render(tester, HomeTabIcon(tab));
      final (on, _) = await _render(tester, HomeTabIcon(tab, selected: true));
      final offCount = _ink(off).$1, onCount = _ink(on).$1;
      expect(offCount, isNot(onCount), reason: '$tab');
    }
  });

  testWidgets('发布 is the pink square with a white +, darker at the bottom', (tester) async {
    final (bytes, width) = await _render(tester, const HomeTabIcon(HomeTab.post));
    expect(width, (TabIconTheme.postSquare * 3).round());
    ui.Color at(int x, int y) {
      final i = (y * width + x) * 4;
      return ui.Color.fromARGB(255, bytes.getUint8(i), bytes.getUint8(i + 1), bytes.getUint8(i + 2));
    }

    final middle = width ~/ 2;
    expect(at(middle, middle), const Color(0xFFFFFFFF));
    final top = at(middle, 12), bottom = at(middle, width - 12);
    expect(top.g, greaterThan(bottom.g));
    expect(top.r, greaterThan(0.95));
    // The corner is cut round, so the very corner stays white.
    expect(at(1, 1), const Color(0xFFFFFFFF));
  });

  testWidgets('a glyph scales to the square it is given', (tester) async {
    await tester.pumpWidget(const Center(child: SizedBox.square(dimension: 44, child: HomeTabIcon(HomeTab.messages))));
    expect(tester.takeException(), isNull);
  });
}
