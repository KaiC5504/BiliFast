import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/device/orientation_host.dart';
import 'package:bilifast/device/player_device.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/main.dart' show applyTurnTakeover;
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
      final services = AppServices(
        environment: environment,
        playback: playback,
        recents: await RecentStore.load(null, logger: logger),
        device: PlayerDevice(orientation: orientation, controls: orientation.controls),
      );
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => AppScope(services: services, child: child!),
        home: PlayerTestPage(
          environment: environment,
          startPlayback: playback.create,
          releasePlayback: playback.release,
          stageBuilder: stageStandIn,
          prefs: prefs,
        ),
      ));
      await tester.pump();
    }

    final row = find.byKey(const ValueKey('turn-takeover'));
    Finder segment(String label) => find.descendant(of: row, matching: find.text(label));
    Set<bool> selected(WidgetTester tester) => tester.widget<SegmentedButton<bool>>(row).selected;

    testWidgets('on the phone, 系统 and 自绘 save the choice and reach the host at once while a page owns the '
        'orientation', (tester) async {
      await show(tester, host: host);
      applyTurnTakeover(orientation, prefs);
      orientation.begin(Object(), videoIsVertical: false);
      await tester.pump();
      expect(host.takeovers, [true]);
      expect(find.text('旋转动画'), findsOneWidget);
      expect(selected(tester), {true});

      await tester.tap(segment('系统'));
      await tester.pump();
      expect(selected(tester), {false});
      expect(prefs.turnTakeover, isFalse);
      expect(host.takeovers, [true, false]);
      expect(orientation.turnTakeover, isFalse);

      // As ghosthand presses it on the PC.
      final semantics = tester.ensureSemantics();
      tester.semantics.tap(find.semantics.byLabel('自绘'));
      await tester.pump();
      expect(selected(tester), {true});
      expect(prefs.turnTakeover, isTrue);
      expect(host.takeovers, [true, false, true]);
      expect(orientation.turnTakeover, isTrue);
      semantics.dispose();
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('shows the saved choice', (tester) async {
      prefs.turnTakeover = false;
      await show(tester, host: host);
      expect(selected(tester), {false});
      expect(host.takeovers, isEmpty, reason: 'opening the page applies nothing; launch did');
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('on Windows, with no turns to take over, it is shown off-limits: 仅 iPhone', (tester) async {
      await show(tester);
      expect(find.text('旋转动画（仅 iPhone）'), findsOneWidget);
      expect(tester.widget<SegmentedButton<bool>>(row).onSelectionChanged, isNull);
      expect(selected(tester), {true});

      await tester.tap(segment('系统'), warnIfMissed: false);
      await tester.pump();
      expect(selected(tester), {true});
      expect(prefs.turnTakeover, isTrue);
      expect(orientation.turnTakeover, isFalse);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    /// The fill of a segment's button.
    Color? fill(WidgetTester tester, String label) =>
        tester.widget<Material>(find.ancestor(of: segment(label), matching: find.byType(Material)).first).color;

    for (final drawn in [true, false]) {
      final chosen = drawn ? '自绘' : '系统';
      final other = drawn ? '系统' : '自绘';
      testWidgets('on Windows the stored $chosen still shows chosen, and reads as it with nothing to press',
          (tester) async {
        prefs.turnTakeover = drawn;
        await show(tester);
        expect(fill(tester, chosen), BiliColors.divider);
        expect(fill(tester, other), isNot(BiliColors.divider));

        final semantics = tester.ensureSemantics();
        expect(find.semantics.byLabel(chosen), findsOneWidget);
        expect(find.semantics.byLabel(other), findsNothing);
        final node = tester.getSemantics(row);
        expect(node.label, chosen);
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
        expect(node.getSemanticsData().flagsCollection.isButton, isFalse);
        semantics.dispose();
      }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
    }
  });
}
