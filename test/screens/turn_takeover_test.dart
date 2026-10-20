import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/device/orientation_host.dart';
import 'package:bilifast/device/player_device.dart';
import 'package:bilifast/device/turn_style.dart';
import 'package:bilifast/devtools/turn_cycle.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/main.dart' show applyTurnStyle;
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/screens/player_test_page.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../device/fake_orientation_host.dart' show FakeOrientationHost, settle;
import '../playback/fakes.dart' hide settle;
import '../support/fake_player.dart';

Widget stageStandIn(BuildContext context, PlaybackController controller,
        {required bool showStats, required bool danmakuEnabled}) =>
    const SizedBox(key: ValueKey('stage'));

/// 开发者's 旋转动画: how turns are drawn (方式, 截图, 起转), kept in player_prefs.json and applied at launch, and
/// 轮换测试 below it.
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

    test('a first launch draws turns as shipped (移除·直接切), from the first page that owns the orientation; the saved '
        '系统 hands them back to iOS', () async {
      final orientation = OrientationController(host: host, logger: logger);
      addTearDown(orientation.dispose);
      applyTurnStyle(orientation, await PlayerPrefs.load(path, logger: logger));
      await settle();
      expect(host.takeovers, isEmpty, reason: 'no page to draw a turn yet');
      expect(orientation.turnTakeover, isFalse);
      expect(orientation.turnStyle, const TurnStyle());
      orientation.begin(Object(), videoIsVertical: false);
      await settle();
      expect(host.takeovers, [true]);
      expect(host.styles, [(TurnMethod.remove, TurnPicture.cut)]);
      expect(orientation.turnTakeover, isTrue);

      final saved = await PlayerPrefs.load(path, logger: logger)
        ..turnStyle = TurnStyle.system;
      await saved.settle();
      applyTurnStyle(orientation, await PlayerPrefs.load(path, logger: logger));
      await settle();
      expect(host.takeovers, [true, false]);
      expect(orientation.turnTakeover, isFalse);
    });

    test('a saved style reaches the host as saved, its drawn start on the controller for the page', () async {
      final saved = await PlayerPrefs.load(path, logger: logger)
        ..turnStyle = const TurnStyle(
            method: TurnMethod.counter, picture: TurnPicture.fade, spinStart: TurnSpinStart.afterPicture);
      await saved.settle();
      final orientation = OrientationController(host: host, logger: logger);
      addTearDown(orientation.dispose);
      applyTurnStyle(orientation, await PlayerPrefs.load(path, logger: logger));
      orientation.begin(Object(), videoIsVertical: false);
      await settle();
      expect(host.styles, [(TurnMethod.counter, TurnPicture.fade)]);
      expect(orientation.turnStyle.spinStart, TurnSpinStart.afterPicture);
    });

    test('系统 saved by 1.0.0 (12) still leaves turns to iOS after the update', () async {
      File(path).writeAsStringSync('{"turnTakeover":false}');
      final orientation = OrientationController(host: host, logger: logger);
      addTearDown(orientation.dispose);
      applyTurnStyle(orientation, await PlayerPrefs.load(path, logger: logger));
      orientation.begin(Object(), videoIsVertical: false);
      await settle();
      expect(host.takeovers, isEmpty);
      expect(orientation.turnStyle, TurnStyle.system);
    });

    test('without a host (Windows) it stays off', () async {
      final orientation = OrientationController(logger: logger);
      addTearDown(orientation.dispose);
      applyTurnStyle(orientation, PlayerPrefs.memory(logger: logger));
      await settle();
      expect(orientation.turnTakeover, isFalse);
    });
  });

  group('the 开发者 rows', () {
    late PlayerPrefs prefs;
    late OrientationController orientation;
    late TurnCycle cycle;

    setUp(() => prefs = PlayerPrefs.memory(logger: logger));

    Future<void> show(WidgetTester tester, {OrientationHost? host}) async {
      tester.view.physicalSize = const Size(440, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final environment = await AppEnvironment.load(
          keychain: FakeKeychain(const StoredCookies(Canned.cookies)), http: Canned.http(), logger: logger);
      final playback = AppPlayback(() async => PlaybackController(
            client: environment.client,
            engine: FakeEngine(),
            player: FakePlayer(),
            clock: ManualClock().clock,
            startTimer: FakeTimers().start,
            logger: logger,
          ));
      addTearDown(playback.dispose);
      orientation = OrientationController(host: host, logger: logger);
      addTearDown(orientation.dispose);
      cycle = TurnCycle(orientation: orientation, prefs: prefs, logger: logger);
      addTearDown(cycle.dispose);
      final services = AppServices(
        environment: environment,
        playback: playback,
        recents: await RecentStore.load(null, logger: logger),
        device: PlayerDevice(orientation: orientation, controls: orientation.controls),
        turnCycle: cycle,
      );
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => AppScope(services: services, child: child!),
        home: PlayerTestPage(
          environment: environment,
          startPlayback: playback.create,
          releasePlayback: playback.release,
          stageBuilder: stageStandIn,
          prefs: prefs,
          turnCycle: cycle,
        ),
      ));
      await tester.pump();
    }

    final method = find.byKey(const ValueKey('turn-method'));
    final picture = find.byKey(const ValueKey('turn-picture'));
    final spinStart = find.byKey(const ValueKey('turn-spin-start'));
    Finder choice(Finder row, String label) => find.descendant(of: row, matching: find.text(label));

    /// The fill of a choice's pill.
    Color? fill(WidgetTester tester, Finder row, String label) => (tester
            .widget<Container>(find.ancestor(of: choice(row, label), matching: find.byType(Container)).first)
            .decoration! as BoxDecoration)
        .color;

    /// What accessibility reads for a greyed row, and that there is nothing to press.
    void readsAs(WidgetTester tester, Finder row, String chosen) {
      final node = tester.getSemantics(find.descendant(of: row, matching: find.byType(Wrap)));
      expect(node.label, chosen);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      expect(node.getSemanticsData().flagsCollection.isButton, isFalse);
    }

    final cycleText = find.byKey(const ValueKey('turn-cycle-position'));
    String positionText(WidgetTester tester) => tester.widget<Text>(cycleText).data!;

    testWidgets('on the phone, 方式, 截图 and 起转 save the choice and reach the host at once while a page owns the '
        'orientation', (tester) async {
      await show(tester, host: host);
      applyTurnStyle(orientation, prefs);
      orientation.begin(Object(), videoIsVertical: false);
      await tester.pump();
      expect(host.takeovers, [true]);
      expect(find.text('旋转动画'), findsOneWidget);
      expect(fill(tester, method, '移除'), BiliColors.pinkTint);
      expect(fill(tester, method, '系统'), BiliColors.pageGrey);

      await tester.tap(choice(method, '系统'));
      await tester.pump();
      expect(prefs.turnStyle, TurnStyle.system);
      expect(host.takeovers, [true, false]);
      expect(orientation.turnTakeover, isFalse);
      expect(fill(tester, method, '系统'), BiliColors.pinkTint);

      // As ghosthand presses them on the PC.
      final semantics = tester.ensureSemantics();
      tester.semantics.tap(find.semantics.byLabel('抵消'));
      await tester.pump();
      expect(prefs.turnStyle, const TurnStyle(method: TurnMethod.counter));
      expect(host.takeovers, [true, false, true]);
      expect(host.styles.last, (TurnMethod.counter, TurnPicture.cut));
      expect(orientation.turnTakeover, isTrue);

      tester.semantics.tap(find.semantics.byLabel('淡出'));
      await tester.pump();
      expect(prefs.turnStyle.picture, TurnPicture.fade);
      expect(host.styles.last, (TurnMethod.counter, TurnPicture.fade));
      expect(fill(tester, picture, '淡出'), BiliColors.pinkTint);

      tester.semantics.tap(find.semantics.byLabel('等截图'));
      await tester.pump();
      expect(prefs.turnStyle.method, TurnMethod.counter);
      expect(prefs.turnStyle.picture, TurnPicture.fade);
      expect(prefs.turnStyle.spinStart, TurnSpinStart.afterPicture);
      expect(orientation.turnStyle.spinStart, TurnSpinStart.afterPicture, reason: 'the page reads it from here');
      semantics.dispose();
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    for (final none in [TurnMethod.system, TurnMethod.noSpin]) {
      testWidgets('with ${none.label}, 截图 and 起转 are greyed but still show and read their choice', (tester) async {
        prefs.turnStyle = TurnStyle(method: none, picture: TurnPicture.fade, spinStart: TurnSpinStart.afterPicture);
        await show(tester, host: host);
        final semantics = tester.ensureSemantics();
        readsAs(tester, picture, '淡出');
        readsAs(tester, spinStart, '等截图');
        expect(fill(tester, picture, '淡出'), BiliColors.divider);
        expect(fill(tester, picture, '直接切'), BiliColors.card);
        expect(tester.widget<Text>(choice(picture, '直接切')).style?.color, BiliColors.secondaryText);
        expect(find.semantics.byLabel('直接切'), findsNothing);

        await tester.tap(choice(picture, '直接切'));
        await tester.tap(choice(spinStart, '立即'));
        await tester.pump();
        expect(prefs.turnStyle.picture, TurnPicture.fade);
        expect(prefs.turnStyle.spinStart, TurnSpinStart.afterPicture);

        tester.semantics.tap(find.semantics.byLabel('移除'));
        await tester.pump();
        expect(prefs.turnStyle, const TurnStyle(picture: TurnPicture.fade, spinStart: TurnSpinStart.afterPicture),
            reason: 'a drawn method takes up the picture and start kept');
        expect(find.semantics.byLabel('直接切'), findsOneWidget);
        semantics.dispose();
      }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
    }

    testWidgets('shows the saved choice', (tester) async {
      prefs.turnStyle = const TurnStyle(method: TurnMethod.counter, picture: TurnPicture.none);
      await show(tester, host: host);
      expect(fill(tester, method, '抵消'), BiliColors.pinkTint);
      expect(fill(tester, picture, '无截图'), BiliColors.pinkTint);
      expect(fill(tester, spinStart, '立即'), BiliColors.pinkTint);
      expect(host.takeovers, isEmpty, reason: 'opening the page applies nothing; launch did');
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('the choices fit 440 pt, 方式 on two rows', (tester) async {
      await show(tester, host: host);
      for (final row in [method, picture, spinStart]) {
        expect(tester.getBottomRight(row).dx, lessThanOrEqualTo(440 - 2 * BiliMetrics.gutter));
      }
      final rows = {for (final each in TurnMethod.values) tester.getTopLeft(choice(method, each.label)).dy};
      expect(rows, hasLength(2));
      for (final row in [picture, spinStart]) {
        expect(tester.getSize(row).height, BiliMetrics.pillHeight + BiliMetrics.rowGap, reason: 'one row');
      }
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    for (final stored in [const TurnStyle(), TurnStyle.system]) {
      final chosen = stored.method.label;
      testWidgets('on Windows, with no turns to take over, it is shown off-limits (仅 iPhone); the stored $chosen '
          'still shows chosen, and reads as it with nothing to press', (tester) async {
        prefs.turnStyle = stored;
        await show(tester);
        expect(find.text('旋转动画（仅 iPhone）'), findsOneWidget);
        expect(fill(tester, method, chosen), BiliColors.divider);
        expect(fill(tester, method, '抵消'), BiliColors.card);

        final semantics = tester.ensureSemantics();
        readsAs(tester, method, chosen);
        readsAs(tester, picture, '直接切');
        readsAs(tester, spinStart, '立即');
        expect(find.semantics.byLabel('抵消'), findsNothing);
        semantics.dispose();

        await tester.tap(choice(method, '抵消'), warnIfMissed: false);
        await tester.pump();
        expect(prefs.turnStyle, stored);
        expect(orientation.turnTakeover, isFalse);
      }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
    }

    testWidgets('轮换测试: on starts at 1/13 系统 and greys the choices, the count and style follow the turns, 重置 goes '
        'back to 1, off leaves the style and frees the choices', (tester) async {
      prefs.turnStyle = const TurnStyle(method: TurnMethod.counter);
      await show(tester, host: host);
      expect(find.text('轮换测试'), findsOneWidget);
      expect(cycle.on, isFalse);
      expect(positionText(tester), contains('每种往返 2 次后换下一种，共 13 种'));
      expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('turn-cycle-reset'))).onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('turn-cycle-switch')));
      await tester.pump();
      expect(cycle.on, isTrue);
      expect(positionText(tester), '1/13 系统 · 第 1/2 次往返');
      expect(prefs.turnStyle, TurnStyle.system);
      expect(orientation.turnStyle, TurnStyle.system);
      final semantics = tester.ensureSemantics();
      readsAs(tester, method, '系统');

      for (var trip = 0; trip < 3; trip++) {
        orientation.enterLandscape();
        await tester.pump(TurnCycle.settle);
        orientation.exitToInline();
        await tester.pump(TurnCycle.settle);
      }
      expect(positionText(tester), '2/13 原样·直接切·立即 · 第 2/2 次往返');
      readsAs(tester, method, '原样');
      expect(prefs.turnStyle, const TurnStyle(method: TurnMethod.legacy));

      tester.semantics.tap(find.semantics.byLabel('重置'));
      await tester.pump();
      expect(positionText(tester), '1/13 系统 · 第 1/2 次往返');
      expect(prefs.turnStyle, TurnStyle.system);

      await tester.tap(find.byKey(const ValueKey('turn-cycle-switch')));
      await tester.pump();
      expect(cycle.on, isFalse);
      expect(prefs.turnStyle, TurnStyle.system);
      expect(find.semantics.byLabel('抵消'), findsOneWidget, reason: 'the choices are back');
      semantics.dispose();
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('on Windows 轮换测试 still runs, so the PC can check it', (tester) async {
      await show(tester);
      final semantics = tester.ensureSemantics();
      await tester.tap(find.byKey(const ValueKey('turn-cycle-switch')));
      await tester.pump();
      expect(cycle.on, isTrue);
      expect(positionText(tester), '1/13 系统 · 第 1/2 次往返');
      orientation.enterLandscape();
      await tester.pump(TurnCycle.settle);
      orientation.exitToInline();
      await tester.pump(TurnCycle.settle);
      expect(positionText(tester), '1/13 系统 · 第 2/2 次往返');
      tester.semantics.tap(find.semantics.byLabel('重置'));
      await tester.pump();
      expect(positionText(tester), '1/13 系统 · 第 1/2 次往返');
      semantics.dispose();
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  });
}
