import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/settings/app_icon.dart';
import 'package:bilifast/settings/app_icon_page.dart';
import 'package:bilifast/settings/settings_page.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'settings_fakes.dart';

class _Refused implements Exception {
  @override
  String toString() => 'refused: private detail';
}

void main() {
  void phone(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(440, 956) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<void> showPage(WidgetTester tester, FakeAppIconHost host, {bool settle = true}) async {
    phone(tester);
    await tester.pumpWidget(MaterialApp(home: AppIconPage(host: host)));
    if (settle) await tester.pumpAndSettle();
  }

  Finder row(AppIconChoice choice) => find.byKey(ValueKey('app-icon-${choice.name}'));
  Finder tick(AppIconChoice choice) =>
      find.descendant(of: row(choice), matching: find.byKey(const ValueKey('app-icon-check')));
  final anyTick = find.byKey(const ValueKey('app-icon-check'));

  Future<void> tapRow(WidgetTester tester, AppIconChoice choice) async {
    await tester.tap(row(choice));
    await tester.pumpAndSettle();
  }

  Future<void> outlastToast(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  }

  group('设置\'s row', () {
    late SettingsWorld world;

    Future<void> showSettings(WidgetTester tester, FakeAppIconHost host) async {
      phone(tester);
      world = await SettingsWorld.create(appIcons: host);
      addTearDown(world.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => AppScope(services: world.services, child: child!),
          home: SettingsPage(prefs: PlayerPrefs.memory(), version: '1.0.0 (10)'),
        ),
      );
      await tester.pumpAndSettle();
    }

    final settingsRow = find.byKey(const ValueKey('settings-app-icon'));

    testWidgets('shows the current icon\'s name and opens 应用图标; back, it shows the new one', (tester) async {
      final host = FakeAppIconHost(AppIconChoice.cat);
      await showSettings(tester, host);
      expect(find.descendant(of: settingsRow, matching: find.text('应用图标')), findsOneWidget);
      expect(find.descendant(of: settingsRow, matching: find.text('猫猫')), findsOneWidget);

      await tester.tap(settingsRow);
      await tester.pumpAndSettle();
      expect(find.byType(AppIconPage), findsOneWidget);
      expect(find.text('应用图标'), findsOneWidget);

      await tapRow(tester, AppIconChoice.standard);
      await tester.tap(find.byKey(const ValueKey('settings-back')));
      await tester.pumpAndSettle();
      expect(find.byType(AppIconPage), findsNothing);
      expect(find.descendant(of: settingsRow, matching: find.text('默认')), findsOneWidget);
    });

    testWidgets('sits in its own section right under BTR', (tester) async {
      await showSettings(tester, FakeAppIconHost());
      final btr = tester.getRect(find.byKey(const ValueKey('settings-btr')));
      final icon = tester.getRect(settingsRow);
      expect(icon.top, greaterThan(btr.bottom + 1));
      expect(tester.getRect(find.byKey(const ValueKey('settings-recents'))).top, greaterThan(icon.bottom + 1));
    });

    testWidgets('presses through accessibility, as do the page\'s rows', (tester) async {
      final semantics = tester.ensureSemantics();
      final host = FakeAppIconHost();
      await showSettings(tester, host);
      tester.semantics.tap(find.semantics.byLabel(RegExp(r'^应用图标\s+默认$')));
      await tester.pumpAndSettle();
      expect(find.byType(AppIconPage), findsOneWidget);

      tester.semantics.tap(find.semantics.byLabel('猫猫'));
      await tester.pumpAndSettle();
      expect(host.chosen, [AppIconChoice.cat]);
      expect(tick(AppIconChoice.cat), findsOneWidget);

      tester.semantics.tap(find.semantics.byLabel('返回'));
      await tester.pumpAndSettle();
      expect(find.semantics.byLabel(RegExp(r'^应用图标\s+猫猫$')), findsOne);
      semantics.dispose();
    });
  });

  testWidgets('a row per icon with its picture and name, the tick only once the current one is known', (tester) async {
    final host = FakeAppIconHost(AppIconChoice.cat)..currentGate = Completer<void>();
    await showPage(tester, host);
    for (final choice in AppIconChoice.values) {
      expect(find.descendant(of: row(choice), matching: find.text(choice.label)), findsOneWidget);
      final picture = tester.widget<Image>(find.descendant(of: row(choice), matching: find.byType(Image)));
      expect((picture.image as AssetImage).assetName, choice.preview);
      expect(tester.getSize(find.descendant(of: row(choice), matching: find.byType(Image))), const Size(60, 60));
    }
    expect(anyTick, findsNothing);

    host.currentGate!.complete();
    await tester.pumpAndSettle();
    expect(tick(AppIconChoice.cat), findsOneWidget);
    expect(anyTick, findsOneWidget);
  });

  testWidgets('a tap on another icon asks for it and moves the tick', (tester) async {
    final host = FakeAppIconHost();
    await showPage(tester, host);
    expect(tick(AppIconChoice.standard), findsOneWidget);

    await tapRow(tester, AppIconChoice.cat);
    expect(host.chosen, [AppIconChoice.cat]);
    expect(tick(AppIconChoice.cat), findsOneWidget);
    expect(tick(AppIconChoice.standard), findsNothing);
  });

  testWidgets('a refusal keeps the tick, says 更换失败 and logs only the choice and the error\'s type', (tester) async {
    final logs = MemorySink();
    Logger.shared.add(logs);
    addTearDown(() => Logger.shared.remove(logs));
    final host = FakeAppIconHost()..refusal = _Refused();
    await showPage(tester, host);

    await tapRow(tester, AppIconChoice.cat);
    expect(host.chosen, [AppIconChoice.cat]);
    expect(tick(AppIconChoice.standard), findsOneWidget);
    expect(tick(AppIconChoice.cat), findsNothing);
    expect(find.text('更换失败'), findsOneWidget);

    final warning = logs.events.where((event) => event.msg == 'app icon change failed').single;
    expect(warning.f['choice']?.toJson(), 'cat');
    expect(warning.f['error']?.toJson(), '_Refused');
    expect(warning.f.keys, unorderedEquals(['choice', 'error']));
    await outlastToast(tester);
  });

  testWidgets('while a change is pending, more taps do nothing', (tester) async {
    final host = FakeAppIconHost()..chooseGate = Completer<void>();
    await showPage(tester, host);

    await tapRow(tester, AppIconChoice.cat);
    await tapRow(tester, AppIconChoice.cat);
    await tapRow(tester, AppIconChoice.standard);
    expect(host.chosen, [AppIconChoice.cat]);
    expect(tick(AppIconChoice.standard), findsOneWidget);

    host.chooseGate!.complete();
    await tester.pumpAndSettle();
    expect(tick(AppIconChoice.cat), findsOneWidget);

    await tapRow(tester, AppIconChoice.standard);
    expect(host.chosen, [AppIconChoice.cat, AppIconChoice.standard]);
    expect(tick(AppIconChoice.standard), findsOneWidget);
  });

  testWidgets('a tap on the current icon does nothing', (tester) async {
    final host = FakeAppIconHost(AppIconChoice.cat);
    await showPage(tester, host);
    await tapRow(tester, AppIconChoice.cat);
    expect(host.chosen, isEmpty);
    expect(tick(AppIconChoice.cat), findsOneWidget);
    expect(find.text('更换失败'), findsNothing);
  });
}
