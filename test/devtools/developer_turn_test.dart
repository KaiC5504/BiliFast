import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/app/form_factor.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/device/orientation_host.dart';
import 'package:bilifast/device/player_device.dart';
import 'package:bilifast/devtools/developer_rows.dart';
import 'package:bilifast/main.dart' show applyTurnTakeover;
import 'package:bilifast/video/player_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';

import '../device/fake_orientation_host.dart' show FakeOrientationHost, settle;
import 'developer_world.dart';

/// 开发者's 旋转动画: turns drawn by Flutter (自绘) or by iOS (系统), kept in player_prefs.json and applied at launch.
void main() {
  late Logger logger;
  late FakeOrientationHost host;

  setUp(() {
    logger = Logger(session: 'test');
    host = FakeOrientationHost();
  });

  group('at launch', () {
    late Directory folder;
    late String path;

    setUp(() {
      folder = Directory.systemTemp.createTempSync('turn_takeover_test');
      path = '${folder.path}${Platform.pathSeparator}player_prefs.json';
    });

    tearDown(() => folder.deleteSync(recursive: true));

    test('a first launch takes turns over, from the first page that owns the orientation; the saved 系统 hands them '
        'back to iOS', () async {
      final orientation = OrientationController(host: host, logger: logger);
      addTearDown(orientation.dispose);
      applyTurnTakeover(orientation, await PlayerPrefs.load(path, logger: logger));
      await settle();
      expect(host.takeovers, isEmpty, reason: 'no page to draw a turn yet');
      expect(orientation.turnTakeover, isFalse);
      orientation.begin(Object(), videoIsVertical: false);
      await settle();
      expect(host.takeovers, [true]);
      expect(orientation.turnTakeover, isTrue);

      final saved = await PlayerPrefs.load(path, logger: logger)
        ..turnTakeover = false;
      await saved.settle();
      applyTurnTakeover(orientation, await PlayerPrefs.load(path, logger: logger));
      await settle();
      expect(host.takeovers, [true, false]);
      expect(orientation.turnTakeover, isFalse);
    });

    for (final (json, drawn) in [
      ('{"turnMethod":"system","turnPicture":"fade"}', false),
      ('{"turnMethod":"quietRequest","turnSpinStart":"afterPicture"}', true),
    ]) {
      test('a 1.0.0 (14) file $json ${drawn ? 'draws the turns' : 'leaves turns to iOS'} after the update', () async {
        File(path).writeAsStringSync(json);
        final orientation = OrientationController(host: host, logger: logger);
        addTearDown(orientation.dispose);
        applyTurnTakeover(orientation, await PlayerPrefs.load(path, logger: logger));
        orientation.begin(Object(), videoIsVertical: false);
        await settle();
        expect(host.takeovers, drawn ? [true] : isEmpty);
        expect(orientation.turnTakeoverChosen, drawn);
      });
    }

    test('without a host (Windows) it stays off', () async {
      final orientation = OrientationController(logger: logger);
      addTearDown(orientation.dispose);
      applyTurnTakeover(orientation, PlayerPrefs.memory(logger: logger));
      await settle();
      expect(orientation.turnTakeover, isFalse);
    });
  });

  group('the 开发者 row', () {
    late PlayerPrefs prefs;
    late OrientationController orientation;

    setUp(() => prefs = PlayerPrefs.memory(logger: logger));

    Future<void> show(WidgetTester tester, {OrientationHost? host}) async {
      orientation = OrientationController(host: host, logger: logger);
      addTearDown(orientation.dispose);
      await DeveloperWorld(
        device: PlayerDevice(orientation: orientation, controls: orientation.controls),
      ).show(tester, prefs: prefs);
    }

    final row = find.byKey(const ValueKey('dev-turn'));
    Finder value(String text) => find.descendant(of: row, matching: find.text(text));

    testWidgets('on the iPhone it opens a page of the two, whose 系统 and 自绘 save the choice and reach the host at once '
        'while a page owns the orientation', (tester) async {
      await show(tester, host: host);
      applyTurnTakeover(orientation, prefs);
      orientation.begin(Object(), videoIsVertical: false);
      await tester.pump();
      expect(host.takeovers, [true]);
      expect(value('自绘'), findsOneWidget);

      await press(tester, row);
      await tester.pumpAndSettle();
      expect(find.byType(DeveloperChoicePage<bool>), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const ValueKey('choice-自绘')), matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('choice-系统')));
      await tester.pump();
      expect(prefs.turnTakeover, isFalse);
      expect(host.takeovers, [true, false]);
      expect(orientation.turnTakeover, isFalse);
      expect(
        find.descendant(of: find.byKey(const ValueKey('choice-系统')), matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );

      // As ghosthand presses it on the PC.
      final semantics = tester.ensureSemantics();
      tester.semantics.tap(find.semantics.byLabel('自绘'));
      await tester.pump();
      expect(prefs.turnTakeover, isTrue);
      expect(host.takeovers, [true, false, true]);
      expect(orientation.turnTakeover, isTrue);

      tester.semantics.tap(find.semantics.byLabel('返回'));
      await tester.pumpAndSettle();
      expect(find.byType(DeveloperChoicePage<bool>), findsNothing);
      expect(value('自绘'), findsOneWidget);
      semantics.dispose();
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('shows the saved choice', (tester) async {
      prefs.turnTakeover = false;
      await show(tester, host: host);
      expect(value('系统'), findsOneWidget);
      expect(host.takeovers, isEmpty, reason: 'opening the page applies nothing; launch did');
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    for (final (where, platform, pad) in [
      ('on Windows', TargetPlatform.windows, false),
      ('on the iPad', TargetPlatform.iOS, true),
    ]) {
      for (final drawn in [true, false]) {
        final chosen = drawn ? '自绘' : '系统';
        testWidgets('$where, with no turns of its own to draw, it shows the stored $chosen with nothing to press', (
          tester,
        ) async {
          if (pad) {
            FormFactor.device = FormFactor.pad;
            addTearDown(() => FormFactor.device = FormFactor.phone);
          }
          prefs.turnTakeover = drawn;
          await show(tester);
          expect(value('$chosen（仅 iPhone）'), findsOneWidget);

          await tester.tap(row, warnIfMissed: false);
          await tester.pumpAndSettle();
          expect(find.byType(DeveloperChoicePage<bool>), findsNothing);
          expect(prefs.turnTakeover, drawn);
          expect(orientation.turnTakeover, isFalse);

          final semantics = tester.ensureSemantics();
          final node = tester.getSemantics(row);
          expect(node.label, contains('旋转动画'));
          expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
          semantics.dispose();
        }, variant: TargetPlatformVariant.only(platform));
      }
    }
  });
}
