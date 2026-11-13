import 'dart:io';

import 'package:bili_core/engine.dart';
import 'package:bilifast/devtools/log_server_discovery.dart';
import 'package:bilifast/offline/disk/background_trials.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/speedtest/speed_test_plan.dart';
import 'package:bilifast/speedtest/speed_test_runner.dart';
import 'package:bilifast/video/history_outbox.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';
import '../speedtest/fake_target.dart';
import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import '../video/mixed_lines.dart' show appTheme;
import 'developer_world.dart';

// Its own file: the stand-ins replace Roboto and the Cupertino families for every later test in the isolate.

/// 开发者 as KaiC's iPhone draws it, under the system font: nothing official to measure against, so these only check
/// that every row fits at 440 pt. With BILIFAST_SHOTS naming a folder outside the repo, the 3× shots are saved there.
void main() {
  const nodes = [
    ('upos-sz-mirrorali.bilivideo.com', 'healthy', 11.8, 62.0),
    ('upos-sz-mirrorcos.bilivideo.com', 'healthy', 9.4, 78.0),
    ('upos-hz-mirrorakam.akamaized.net', 'healthy', 14.2, 41.0),
    ('upos-sz-mirrorhw.bilivideo.com', 'banned', 0.6, 310.0),
    ('cn-hk-eq-01-13.bilivideo.com', 'blocked', 0.2, 650.0),
  ];

  Future<DeveloperWorld> show(WidgetTester tester, {SpeedTestHooks? hooks}) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    BiliFonts.family = BiliFonts.system;
    await tester.runAsync(loadSystemFontStandIns);
    await tester.runAsync(loadIconFonts);
    final trials = BackgroundTrials()
      ..record(trip(BackgroundArm.continuedArm, seconds: 60, megabytes: 300))
      ..record(trip(BackgroundArm.continuedArm, seconds: 90, megabytes: 420))
      ..record(trip(BackgroundArm.handOffArms.first, seconds: 120, megabytes: 240));
    final world = DeveloperWorld(
      offline: TrialLibrary(trials),
      historyOutbox: HeldOutbox([PendingReport(bvid: bv, cid: 1, played: 30, at: DateTime(2026, 11, 2, 9))]),
    );
    final discovery = FakeDiscovery();
    final logs = quietLogs(discovery: discovery);
    await world.show(
      tester,
      phone: true,
      theme: appTheme(),
      logs: logs,
      hooks: hooks,
      appAuth: StubAppAuth(expiresAt: DateTime.now().add(const Duration(days: 42, hours: 12))),
      before: () async {
        BiliFonts.family = BiliFonts.system;
        final engine = await world.shared.current() as FakeEngine;
        engine.statsController.add(
          EngineSnapshot(
            nodes: [for (final (node, _, _, firstByte) in nodes) NodeTiming(node: node, firstByteMs: firstByte)],
            nodeStates: [
              for (final (node, state, mbps, _) in nodes) NodeStatus(node: node, state: state, bps: mbps * 1048576),
            ],
          ),
        );
      },
    );
    logs.setEnabled(true);
    discovery.controller.add(const [LogServerEndpoint(name: 'KaiC-PC', host: '192.168.1.5', port: 47321)]);
    await frames(tester);
    return world;
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('shot')), '$shots/$name.png');
  }

  Future<void> scrollTo(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await frames(tester);
  }

  testWidgets('the page as opened, top to bottom', (tester) async {
    await show(tester);
    await shoot(tester, 'developer-1-top');
    await scrollTo(tester, 'status-outbox');
    await shoot(tester, 'developer-2-status');
    await scrollTo(tester, 'test-crash');
    await shoot(tester, 'developer-3-bottom');
    expect(tester.takeException(), isNull, reason: 'nothing overflows');
  });

  testWidgets('a speed test running, then its results', (tester) async {
    final hooks = SpeedTestHooks(
      choosePlan: (server) async => PlanChoice(
        plan: planWith({'order': 'ABA', 'seeks': 0, 'hints': 0, 'backJumps': 0, 'dwellSeconds': 0, 'fastSeconds': 0}),
        source: PlanSource.builtin,
        note: '没有连接电脑',
      ),
      startEngine: (variant) async => FakeEngine(),
      appEngine: () async => FakeEngine(),
    );
    final world = await show(tester, hooks: hooks);
    await tester.enterText(find.byKey(const ValueKey('speedtest-links')), bv);
    FocusManager.instance.primaryFocus?.unfocus();
    // The field's scroll to its caret ignores taps until it ends.
    await frames(tester);
    await press(tester, find.byKey(const ValueKey('speedtest-start')));
    await frames(tester, 20);
    await shoot(tester, 'developer-4-running');
    for (var pass = 0; pass < 3; pass++) {
      world.players.single.emit(const StatusChanged(PlayerStatus.playing));
      await frames(tester, 20);
    }
    expect(find.byKey(const ValueKey('speedtest-results')), findsOneWidget);
    await scrollTo(tester, 'speedtest-start');
    await shoot(tester, 'developer-5-results');
    expect(tester.takeException(), isNull, reason: 'nothing overflows');
  });
}
