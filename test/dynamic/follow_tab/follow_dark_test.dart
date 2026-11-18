import 'dart:io';
import 'dart:ui' as ui;

import 'package:bilifast/dynamic/fake_dynamic_api.dart';
import 'package:bilifast/home/home_tab_bar.dart';
import 'package:bilifast/home/main_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/look_alike.dart';
import 'follow_fixtures.dart';

/// The pixel at [at] (in points) of what the shell paints.
Future<Color> pixelAt(WidgetTester tester, Offset at) async {
  final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(shellScreen));
  late Color color;
  await tester.runAsync(() async {
    final image = await render.toImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final i = (at.dy.floor() * image.width + at.dx.floor()) * 4;
    color = Color.fromARGB(bytes.getUint8(i + 3), bytes.getUint8(i), bytes.getUint8(i + 1), bytes.getUint8(i + 2));
    image.dispose();
  });
  return color;
}

/// 关注 in 深色模式 against 243 (the tab) and 246 (a card's ⋮ sheet), in px / 3. With BILIFAST_SHOTS naming a folder
/// outside the repo, the 3× shots are saved there for tools/screen_diff.py.
void main() {
  Future<void> openFollow(WidgetTester tester) async {
    await showShell(tester, api: FakeDynamicApi(posts: posts(4), upList: faces), phone: true, dark: true);
    await settle(tester, 20);
    final context = tester.element(find.byType(MainShell));
    await tester.runAsync(() async {
      for (final art in ['follow_write', 'follow_pointer']) {
        await precacheImage(AssetImage('assets/images/dynamic/$art.png'), context);
      }
    });
    await tester.tap(find.byKey(ValueKey('home-tab-${HomeTab.follow.name}')));
    await settle(tester, 20);
  }

  Future<void> save(WidgetTester tester, String name) async {
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(shellScreen), '$shots/$name-ours.png');
  }

  testWidgets('243: the dark header, the switch on #1E2022, the grey pen and light status bar icons', (tester) async {
    await openFollow(tester);
    expect(await pixelAt(tester, const Offset(20, 40)), const Color(0xFF17181A));
    expect(await pixelAt(tester, const Offset(16, 99)), const Color(0xFF1E2022));
    expect(await pixelAt(tester, const Offset(230, 99)), const Color(0xFF1E2022));
    final title = tester.widget<Text>(find.byKey(const ValueKey('follow-title')));
    expect(title.style!.color, const Color(0xFFE7E9EB));
    final pen = tester.widget<Image>(
      find.descendant(of: find.byKey(const ValueKey('follow-write')), matching: find.byType(Image)),
    );
    expect(pen.color, const Color(0xFFA2A7AE));
    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>).last,
    );
    expect(region.value, SystemUiOverlayStyle.light);
    await save(tester, '243-dark');
  });

  testWidgets('246: a card\'s ⋮ sheet on #1E2022, its 取消 under a #0A0B0C gap', (tester) async {
    await openFollow(tester);
    await tester.tap(find.byKey(const ValueKey('dynamic-more')).first);
    await settle(tester, 20);
    final sheet = tester.getRect(find.byKey(const ValueKey('dynamic-more-sheet')));
    expect(await pixelAt(tester, Offset(sheet.right - 4, sheet.top + 4)), const Color(0xFF1E2022));
    final cancel = tester.getRect(find.byKey(const ValueKey('dynamic-more-cancel')));
    expect(await pixelAt(tester, Offset(cancel.left + 4, cancel.top - 2)), const Color(0xFF0A0B0C));
    await save(tester, '246-dark');
  });
}
