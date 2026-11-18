import 'dart:io';

import 'package:bilifast/dynamic/fake_dynamic_api.dart';
import 'package:bilifast/home/home_tab_bar.dart';
import 'package:bilifast/message/fake_message_api.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../dynamic/follow_tab/follow_dark_test.dart' show pixelAt;
import '../dynamic/follow_tab/follow_fixtures.dart';
import '../support/look_alike.dart';

Finder _key(String key) => find.byKey(ValueKey(key));

/// 消息 in 深色模式 against 244 (the tab) and 245 (⋮'s sheet), in px / 3. With BILIFAST_SHOTS naming a folder outside
/// the repo, the 3× shots are saved there for tools/screen_diff.py.
void main() {
  Future<void> openMessages(WidgetTester tester) async {
    await showShell(
      tester,
      api: FakeDynamicApi(posts: posts(4), upList: faces),
      phone: true,
      dark: true,
      messageApi: FakeMessageApi.demo(now: DateTime(2026, 11, 17, 16, 8)),
    );
    await settle(tester, 20);
    await tester.runAsync(loadIconFonts);
    await tester.tap(_key('home-tab-${HomeTab.messages.name}'));
    await settle(tester, 30);
    // The asset glyphs decode off the test's clock.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await settle(tester);
  }

  Future<void> save(WidgetTester tester, String name) async {
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(shellScreen), '$shots/$name-ours.png');
  }

  testWidgets('244: the dark header with grey broom and ⋮, the entries on #1C1F20, light status bar icons', (
    tester,
  ) async {
    await openMessages(tester);
    expect(await pixelAt(tester, const Offset(20, 40)), const Color(0xFF17181A));
    final entry = tester.getRect(_key('message-entry-replies'));
    final squareTop = entry.top + MessageTabTheme.entryTop;
    expect(await pixelAt(tester, Offset(entry.center.dx - 18, squareTop + 3)), const Color(0xFF1C1F20));
    final title = tester.widget<Text>(_key('message-title'));
    expect(title.style!.color, const Color(0xFFE7E9EB));
    for (final button in ['message-read-all-button', 'message-more-button']) {
      final glyph = tester.widget<Image>(find.descendant(of: _key(button), matching: find.byType(Image)));
      expect(glyph.color, const Color(0xFFA2A7AE), reason: button);
    }
    final regions = tester.widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
    );
    expect(regions.last.value, SystemUiOverlayStyle.light);
    await save(tester, '244-dark');
  });

  testWidgets('245: ⋮\'s sheet on #202123, its card #242628 with #2F3134 rules and a #4D4D4F grabber', (tester) async {
    await openMessages(tester);
    await tester.tap(_key('message-more-button'));
    await settle(tester, 20);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await settle(tester);
    final sheet = tester.getRect(_key('message-sheet'));
    expect(await pixelAt(tester, Offset(sheet.left + 6, sheet.top + 40)), const Color(0xFF202123));
    final row = tester.getRect(_key('message-sheet-settings'));
    expect(await pixelAt(tester, Offset(row.right - 6, row.center.dy)), const Color(0xFF242628));
    expect(await pixelAt(tester, Offset(sheet.center.dx, sheet.top + 9.5)), const Color(0xFF4D4D4F));
    await save(tester, '245-dark');
  });
}
