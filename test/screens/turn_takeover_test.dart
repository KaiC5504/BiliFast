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
import 'package:bilifast/video/player_prefs.dart';
import 'package:flutter/material.dart';
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

    test('a first launch takes turns over; the saved 系统 hands them back to iOS', () async {
      final orientation = OrientationController(host: host, logger: logger);
      addTearDown(orientation.dispose);
      applyTurnTakeover(orientation, await PlayerPrefs.load(path, logger: logger));
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
          startPlayback: playback.obtain,
          stageBuilder: stageStandIn,
          ownsController: false,
          prefs: prefs,
        ),
      ));
      await tester.pump();
    }

    final row = find.byKey(const ValueKey('turn-takeover'));
    Finder segment(String label) => find.descendant(of: row, matching: find.text(label));
    Set<bool> selected(WidgetTester tester) => tester.widget<SegmentedButton<bool>>(row).selected;

    testWidgets('on the phone, 系统 and 自绘 save the choice and reach the host at once', (tester) async {
      await show(tester, host: host);
      expect(find.text('旋转动画'), findsOneWidget);
      expect(selected(tester), {true});

      await tester.tap(segment('系统'));
      await tester.pump();
      expect(selected(tester), {false});
      expect(prefs.turnTakeover, isFalse);
      expect(host.takeovers, [false]);
      expect(orientation.turnTakeover, isFalse);

      // As ghosthand presses it on the PC.
      final semantics = tester.ensureSemantics();
      tester.semantics.tap(find.semantics.byLabel('自绘'));
      await tester.pump();
      expect(selected(tester), {true});
      expect(prefs.turnTakeover, isTrue);
      expect(host.takeovers, [false, true]);
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
  });
}
