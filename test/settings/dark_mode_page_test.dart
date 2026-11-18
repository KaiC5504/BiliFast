import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/appearance.dart';
import 'package:bilifast/settings/dark_mode_page.dart';
import 'package:bilifast/settings/settings_page.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'settings_fakes.dart';

/// 设置 → 深色设置 (242, 249): the row, and 深色跟随系统 bound to [AppearanceModel.followSystem].
void main() {
  late AppearanceModel appearance;

  Future<void> show(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(440, 956) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    appearance = AppearanceModel.memory()..attach();
    addTearDown(appearance.dispose);
    final world = await SettingsWorld.create(appearance: appearance);
    addTearDown(world.dispose);
    await tester.pumpWidget(
      AppearanceRedraw(
        model: appearance,
        builder: (context) => MaterialApp(
          builder: (context, child) => AppScope(services: world.services, child: child!),
          home: SettingsPage(prefs: PlayerPrefs.memory(), version: '1.0.0 (10)'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final follow = find.byKey(const ValueKey('dark-follow-system'));

  bool switchOn(WidgetTester tester) => tester.widget<SettingsSwitchRow>(follow).value;

  Color pageColour(WidgetTester tester) =>
      tester.widget<Scaffold>(find.ancestor(of: follow, matching: find.byType(Scaffold))).backgroundColor!;

  Future<void> open(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const ValueKey('settings-dark-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-dark-mode')));
    await tester.pumpAndSettle();
  }

  testWidgets('深色设置 comes right after 推送设置 and opens its page, the switch off', (tester) async {
    await show(tester);
    final push = tester.getRect(find.byKey(const ValueKey('settings-push')));
    final dark = tester.getRect(find.byKey(const ValueKey('settings-dark-mode')));
    expect(dark.top, greaterThan(push.bottom));
    expect(dark.top - push.bottom, closeTo(BiliMetrics.settingsSectionGap + 2 * SettingsTheme.hairline, 0.01));
    await open(tester);
    expect(find.byType(DarkModePage), findsOneWidget);
    expect(find.text('深色跟随系统'), findsOneWidget);
    expect(find.text('开启后，将跟随系统打开或关闭深色模式'), findsOneWidget);
    expect(switchOn(tester), isFalse);
    expect(tester.getSize(follow).height, closeTo(DarkModeTheme.rowHeight, 0.01));
  });

  testWidgets('on, it follows iOS both ways and the page redraws; off, it keeps the mode it shows', (tester) async {
    await show(tester);
    await open(tester);

    await tester.tap(follow);
    await tester.pumpAndSettle();
    expect(switchOn(tester), isTrue);
    expect(appearance.followSystem, isTrue);
    expect(BiliTheme.dark, isFalse, reason: 'iOS is light');

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(BiliTheme.dark, isTrue);
    expect(pageColour(tester), const Color(0xFF0A0B0C));
    expect(switchOn(tester), isTrue);
    final styles = tester.widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
    );
    expect(styles.last.value, SystemUiOverlayStyle.light);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(BiliTheme.dark, isFalse);
    expect(pageColour(tester), const Color(0xFFF1F2F3));

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    await tester.tap(follow);
    await tester.pumpAndSettle();
    expect(switchOn(tester), isFalse);
    expect(appearance.followSystem, isFalse);
    expect(BiliTheme.dark, isTrue, reason: 'turned off, the mode shown stays');
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(BiliTheme.dark, isTrue, reason: 'no longer following');
  });

  testWidgets('the row and the switch answer accessibility presses', (tester) async {
    final handle = tester.ensureSemantics();
    await show(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('settings-dark-mode')));
    await tester.pumpAndSettle();
    tester.semantics.tap(find.semantics.byLabel('深色设置'));
    await tester.pumpAndSettle();
    expect(find.byType(DarkModePage), findsOneWidget);
    tester.semantics.tap(find.semantics.byLabel(RegExp('^深色跟随系统')));
    await tester.pumpAndSettle();
    expect(appearance.followSystem, isTrue);
    tester.semantics.tap(find.semantics.byLabel('返回'));
    await tester.pumpAndSettle();
    expect(find.byType(DarkModePage), findsNothing);
    handle.dispose();
  });
}
