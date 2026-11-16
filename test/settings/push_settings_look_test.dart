import 'dart:io';

import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/notify/notify_host.dart';
import 'package:bilifast/settings/push_settings_page.dart';
import 'package:bilifast/settings/settings_page.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import '../video/mixed_lines.dart' show appTheme;
import 'settings_fakes.dart';

// Its own file: the stand-ins replace Roboto and the Cupertino families for every later test in the isolate.

/// 设置 with 推送设置 (50) and 推送设置 at its top and scrolled to its end (189, 190) as KaiC's iPhone draws them, under
/// the system font, notifications allowed and the five kept switches on as on his screenshots. With BILIFAST_SHOTS
/// naming a folder outside the repo, the 3× shots are saved there for tools/screen_diff.py (the official bar is 10 pt
/// taller: `--anchor 106:116`).
void main() {
  Future<void> shoot(WidgetTester tester, String name, Widget page, {bool end = false}) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    BiliFonts.family = BiliFonts.system;
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(key: const ValueKey('shot'), child: page),
      ),
    );
    await tester.pumpAndSettle();
    if (end) {
      final position = tester.state<ScrollableState>(find.byType(Scrollable)).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull, reason: 'nothing overflows');
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('shot')), '$shots/$name.png');
  }

  FakeNotifyHost allowedHost() => FakeNotifyHost(
    allowed: NotifyPermission.allowed,
    stored: const NotifyKinds(likes: true, replies: true, mentions: true, messages: true, uploads: true),
  );

  testWidgets('设置 with 推送设置 (50)', (tester) async {
    final world = await SettingsWorld.create(notify: allowedHost());
    addTearDown(world.dispose);
    await shoot(
      tester,
      '50-settings-push',
      AppScope(
        services: world.services,
        child: SettingsPage(prefs: PlayerPrefs.memory(), version: '1.4.0 (2)'),
      ),
    );
  });

  testWidgets('推送设置 at its top (189)', (tester) async {
    await shoot(tester, '189-push-top', PushSettingsPage(host: allowedHost()));
    final state = tester.getRect(find.text('[已开启]'));
    expect(state.right, lessThan(tester.getRect(find.text('请在您设备的“设置-通知”中，选择“BiliFast”进行修改')).right));
  });

  testWidgets('推送设置 scrolled to its end (190)', (tester) async {
    await shoot(tester, '190-push-bottom', PushSettingsPage(host: allowedHost()), end: true);
    final banner = tester.getRect(find.byKey(const ValueKey('push-banner')));
    expect(banner.bottom, closeTo(956 - 34 - 1 / 3, 0.01), reason: 'the last row ends over the home indicator');
  });
}
