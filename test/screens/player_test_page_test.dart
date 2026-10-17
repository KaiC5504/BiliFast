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
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
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

  Future<void> show(WidgetTester tester, {LogForwarder? logs}) async {
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
}
