import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/devtools/log_forwarder.dart';
import 'package:bilifast/devtools/log_server_discovery.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/screens/player_test_page.dart';
import 'package:bilifast/speedtest/speed_test_plan.dart';
import 'package:bilifast/speedtest/speed_test_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../speedtest/fake_target.dart';
import '../support/fake_player.dart';

/// Stands in for PlayerStage, so the screen is checked without the player UI.
Widget stageStandIn(BuildContext context, PlaybackController controller,
        {required bool showStats, required bool danmakuEnabled}) =>
    Text('stage stats:$showStats danmaku:$danmakuEnabled', key: const ValueKey('stage'));

void main() {
  late CannedHttp http;
  late FakeEngine engine;
  late FakePlayer player;
  late Logger logger;

  setUp(() {
    http = Canned.http();
    engine = FakeEngine();
    player = FakePlayer();
    logger = Logger(session: 'test');
  });

  Future<void> show(WidgetTester tester, {LogForwarder? logs, SpeedTestHooks hooks = appSpeedTestHooks}) async {
    tester.view.physicalSize = const Size(440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final environment = await AppEnvironment.load(
        keychain: FakeKeychain(const StoredCookies(Canned.cookies)), http: http, logger: logger);
    await environment.refreshAccount();
    final timers = FakeTimers();
    await tester.pumpWidget(MaterialApp(
      home: PlayerTestPage(
        environment: environment,
        logs: logs,
        stageBuilder: stageStandIn,
        speedTestHooks: hooks,
        startPlayback: () async => PlaybackController(
          client: environment.client,
          engine: engine,
          player: player,
          clock: ManualClock().clock,
          startTimer: timers.start,
          logger: logger,
        ),
      ),
    ));
    await tester.pump();
  }

  Future<void> play(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const ValueKey('link-field')), text);
    await tester.tap(find.byKey(const ValueKey('play-button')));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
  }

  testWidgets('shows the keychain account and plays a pasted BV in the stage', (tester) async {
    await show(tester);
    expect(find.text('测试用户'), findsOneWidget);
    expect(find.text('大会员'), findsOneWidget);
    expect(find.text('粘贴链接或 BV 号，点播放'), findsOneWidget);

    await play(tester, 'BV1GJ411x7h7');
    expect(find.text('stage stats:true danmaku:true'), findsOneWidget);
    expect(find.text('测试视频 · P1 第一集'), findsOneWidget);
    expect(find.textContaining('BTR · 4K 超高清 · HEVC'), findsOneWidget);
    expect(find.byKey(const ValueKey('quality-125')), findsOneWidget);
    expect(player.loaded?.master, FakeEngine.masterOf('tok1'));
  });

  testWidgets('the 显示统计 and 弹幕 switches reach the stage', (tester) async {
    await show(tester);
    await play(tester, 'BV1GJ411x7h7');
    await tester.tap(find.byKey(const ValueKey('stats-switch')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('danmaku-switch')));
    await tester.pump();
    expect(find.text('stage stats:false danmaku:false'), findsOneWidget);
  });

  testWidgets('直连 prepares the video again in direct mode', (tester) async {
    await show(tester);
    await play(tester, 'BV1GJ411x7h7');
    await tester.tap(find.text('直连'));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(engine.prepared.last.mode, PlaybackMode.direct);
    expect(player.loaded?.headers, BiliClient.mediaHeaders);
  });

  testWidgets('picking HDR asks for it', (tester) async {
    await show(tester);
    await play(tester, 'BV1GJ411x7h7');
    await tester.tap(find.byKey(const ValueKey('quality-125')));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(http.to(Canned.playUrlPath).last.url.queryParameters['qn'], '125');
  });

  testWidgets('小窗 is offered only when the player can, and starts it', (tester) async {
    await show(tester);
    await play(tester, 'BV1GJ411x7h7');
    await tester.tap(find.byKey(const ValueKey('pip-button')));
    await tester.pump();
    expect(player.calls, contains('pip start'));
  });

  testWidgets('no 小窗 on a player without picture in picture', (tester) async {
    player = FakePlayer(capabilities: PlayerCapabilities.none);
    await show(tester);
    await play(tester, 'BV1GJ411x7h7');
    expect(find.byKey(const ValueKey('pip-button')), findsNothing);
  });

  testWidgets('a failed playback says why', (tester) async {
    engine.prepareErrors.addAll(const [
      PlaybackError(PlaybackErrorKind.noTrack),
      PlaybackError(PlaybackErrorKind.noTrack),
    ]);
    await show(tester);
    await play(tester, 'BV1GJ411x7h7');
    expect(find.text(PlaybackErrorKind.noTrack.userMessage), findsOneWidget);
  });

  testWidgets('text without a video says so in the player box', (tester) async {
    await show(tester);
    await play(tester, 'hello');
    expect(find.text(BiliError.invalidLink.userMessage), findsOneWidget);
    expect(http.to(Canned.viewPath), isEmpty);
  });

  testWidgets('发送日志到电脑: switched on, then pointed at a typed address', (tester) async {
    final logs = LogForwarder(
      logger: logger,
      discovery: const NoLogServerDiscovery(),
      poster: (endpoint) => (body) async {},
      initialTarget: '',
    );
    await show(tester, logs: logs);
    expect(find.text('未开启'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('log-switch')));
    await tester.pump();
    expect(find.text('请选择电脑，或输入 IP:端口'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('log-address')), '10.0.0.2:47321');
    await tester.tap(find.byKey(const ValueKey('log-connect')));
    await tester.pump();
    expect(logs.target?.host, '10.0.0.2');
    expect(find.byKey(const ValueKey('log-status')), findsOneWidget);
    logs.dispose();
  });

  group('速度测试', () {
    late LogForwarder logs;
    late List<String> engines;

    setUp(() {
      logs = LogForwarder(
        logger: logger,
        discovery: const NoLogServerDiscovery(),
        poster: (endpoint) => (body) async {},
        initialTarget: '',
      );
      engines = [];
    });

    tearDown(() => logs.dispose());

    SpeedTestHooks hooksFor(Map<String, Object?> plan, {Object? planError}) => SpeedTestHooks(
          choosePlan: (server) async {
            if (planError != null) throw planError;
            return PlanChoice(plan: planWith(plan), source: PlanSource.builtin, note: '没有连接电脑');
          },
          startEngine: (variant) async {
            engines.add(variant.name);
            return FakeEngine();
          },
          appEngine: () async {
            engines.add('app');
            return FakeEngine();
          },
        );

    const quick = <String, Object?>{
      'order': 'AB',
      'seeks': 0,
      'hints': 0,
      'backJumps': 0,
      'dwellSeconds': 0,
      'fastSeconds': 0,
    };

    Future<void> settleRun(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> startTest(WidgetTester tester, String links) async {
      await tester.enterText(find.byKey(const ValueKey('speedtest-links')), links);
      await tester.tap(find.byKey(const ValueKey('speedtest-start')));
      await settleRun(tester);
    }

    testWidgets('only dev builds get the card, under the log section', (tester) async {
      await show(tester);
      expect(find.text('速度测试'), findsNothing);
    });

    testWidgets('runs the plan on the given link and shows each variant and the difference', (tester) async {
      await show(tester, logs: logs, hooks: hooksFor(quick));
      expect(find.text('速度测试'), findsOneWidget);
      await startTest(tester, 'BV1GJ411x7h7');
      expect(find.byKey(const ValueKey('speedtest-stop')), findsOneWidget);
      expect(find.textContaining('计划 test-1（内置，没有连接电脑） · 第 1/2 次 · A · 4K · 等待首帧'), findsOneWidget);

      player.emit(const StatusChanged(PlayerStatus.playing));
      await settleRun(tester);
      expect(find.textContaining('第 2/2 次 · B'), findsOneWidget);
      player.emit(const StatusChanged(PlayerStatus.playing));
      await settleRun(tester);

      expect(find.byKey(const ValueKey('speedtest-start')), findsOneWidget);
      expect(find.byKey(const ValueKey('speedtest-results')), findsOneWidget);
      expect(find.text('A 4K ×1'), findsOneWidget);
      expect(find.text('B 4K ×1'), findsOneWidget);
      expect(find.text('B−A 4K'), findsOneWidget);
      expect(find.textContaining('完成'), findsOneWidget);
      expect(engines, ['A', 'A', 'B', 'app']);
      expect(player.calls, containsAllInOrder(['muted true', 'keep awake true', 'muted false', 'keep awake false']));
      expect(http.to(Canned.viewPath).length + http.to(Canned.signedViewPath).length, 1, reason: 'one open per video');
    });

    testWidgets('停止 stops the run and gives the sound and the screen back', (tester) async {
      await show(tester, logs: logs, hooks: hooksFor(quick));
      await startTest(tester, 'BV1GJ411x7h7');
      await tester.tap(find.byKey(const ValueKey('speedtest-stop')));
      await settleRun(tester);
      expect(find.textContaining('已停止'), findsOneWidget);
      expect(find.byKey(const ValueKey('speedtest-start')), findsOneWidget);
      expect(player.calls, containsAllInOrder(['muted true', 'muted false', 'keep awake false']));
      expect(find.byKey(const ValueKey('speedtest-results')), findsNothing);
    });

    testWidgets('the plan is asked of the PC the logs go to, only while they are switched on', (tester) async {
      final asked = <String?>[];
      await show(tester,
          logs: logs,
          hooks: SpeedTestHooks(
            choosePlan: (server) async {
              asked.add(server?.host);
              throw const SpeedTestPlanError('stop here');
            },
            startEngine: (variant) async => FakeEngine(),
            appEngine: () async => FakeEngine(),
          ));
      logs.setManual('10.0.0.2:47321');
      await startTest(tester, 'BV1GJ411x7h7');
      logs.setEnabled(true);
      await tester.pump();
      await startTest(tester, 'BV1GJ411x7h7');
      logs.setEnabled(false);
      await tester.pump();
      expect(asked, [null, '10.0.0.2']);
    });

    testWidgets('a plan the PC got wrong is shown and nothing plays', (tester) async {
      await show(tester,
          logs: logs, hooks: hooksFor(quick, planError: const SpeedTestPlanError('方案 B 的 config 有引擎不认识或类型不对的项：typo')));
      await startTest(tester, 'BV1GJ411x7h7');
      expect(find.byKey(const ValueKey('speedtest-error')), findsOneWidget);
      expect(find.textContaining('typo'), findsOneWidget);
      expect(engines, isEmpty);
      expect(player.calls, isNot(contains('muted true')));
    });
  });
}
