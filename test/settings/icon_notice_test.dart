import 'dart:io';

import 'package:bilifast/settings/app_icon.dart';
import 'package:bilifast/settings/app_icon_page.dart';
import 'package:bilifast/settings/icon_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'settings_fakes.dart';

void main() {
  group('the store', () {
    late Directory folder;
    late String path;

    setUp(() {
      folder = Directory.systemTemp.createTempSync('icon_notice');
      path = '${folder.path}${Platform.pathSeparator}icon_notice.json';
    });
    tearDown(() => folder.deleteSync(recursive: true));

    test('an update is told once', () async {
      final notice = await IconNotice.load(path, earlierInstall: true);
      expect(notice.due, isTrue);
      expect(File(path).existsSync(), isFalse);

      await notice.done();
      expect(notice.due, isFalse);
      expect((await IconNotice.load(path, earlierInstall: true)).due, isFalse);
    });

    test('a fresh install is never told, even on later launches', () async {
      expect((await IconNotice.load(path, earlierInstall: false)).due, isFalse);
      expect(File(path).existsSync(), isTrue);
      expect((await IconNotice.load(path, earlierInstall: true)).due, isFalse);
    });

    test('without a support folder nothing is told', () async {
      expect((await IconNotice.load(null, earlierInstall: true)).due, isFalse);
    });
  });

  group('the alert', () {
    Future<void> show(WidgetTester tester, IconNotice notice, FakeAppIconHost host) async {
      tester.view
        ..physicalSize = const Size(440, 956) * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(children: [const Placeholder(), IconNoticePrompt(notice: notice, host: host)]),
        ),
      );
      await tester.pumpAndSettle();
    }

    final alert = find.byKey(const ValueKey('icon-notice'));

    testWidgets('says the icon changed; 知道了 closes it for good', (tester) async {
      final notice = IconNotice.memory(due: true);
      await show(tester, notice, FakeAppIconHost());
      expect(alert, findsOneWidget);
      expect(find.text('图标换新了'), findsOneWidget);

      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(alert, findsNothing);
      expect(find.byType(AppIconPage), findsNothing);
      expect(notice.due, isFalse);
    });

    testWidgets('换回小电视 opens 应用图标', (tester) async {
      final notice = IconNotice.memory(due: true);
      final host = FakeAppIconHost();
      await show(tester, notice, host);
      await tester.tap(find.text('换回小电视'));
      await tester.pumpAndSettle();
      expect(alert, findsNothing);
      expect(find.byType(AppIconPage), findsOneWidget);
      expect(notice.due, isFalse);

      await tester.tap(find.byKey(const ValueKey('app-icon-tv')));
      await tester.pumpAndSettle();
      expect(host.chosen, [AppIconChoice.tv]);
    });

    testWidgets('an install that had picked the cat sees nothing and is never asked again', (tester) async {
      final notice = IconNotice.memory(due: true);
      await show(tester, notice, FakeAppIconHost()..rawIconSet = 'AppIconCat');
      expect(alert, findsNothing);
      expect(notice.due, isFalse);
    });

    testWidgets('nothing when not due', (tester) async {
      await show(tester, IconNotice.memory(), FakeAppIconHost());
      expect(alert, findsNothing);
    });
  });
}
