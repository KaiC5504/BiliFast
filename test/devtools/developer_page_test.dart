import 'package:bili_core/api.dart' show OfficialIdentity;
import 'package:bili_core/engine.dart';
import 'package:bilifast/devtools/developer_page.dart';
import 'package:bilifast/devtools/node_probe_section.dart';
import 'package:bilifast/offline/disk/background_trials.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/history_outbox.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';
import 'developer_world.dart';

/// 开发者's page: its groups in order in 设置's look, slice 1's player and switches gone, 状态 read from the app's
/// services, and 官方接口.
void main() {
  Finder row(String key) => find.byKey(ValueKey(key));
  Finder inRow(String key, String text) => find.descendant(of: row(key), matching: find.text(text));

  testWidgets('网络, 状态, 调试 and 日志 in that order, each with its rows, 节点测速 first', (tester) async {
    final world = DeveloperWorld();
    await world.show(tester, logs: quietLogs(), appAuth: StubAppAuth());
    expect(find.text('开发者'), findsOneWidget);
    double top(Finder finder) => tester.getTopLeft(finder).dy;
    final order = [
      find.text('网络'),
      find.byType(NodeProbeSection),
      row('speedtest-start'),
      find.text('状态'),
      row('status-version'),
      row('status-nodes'),
      row('status-background'),
      row('status-outbox'),
      row('status-font'),
      find.text('调试'),
      row('dev-turn'),
      row('app-auth-state'),
      find.text('日志'),
      row('log-switch'),
      row('log-export'),
      row('test-crash'),
    ];
    for (final finder in order) {
      expect(finder, findsOneWidget);
    }
    for (var i = 1; i < order.length; i++) {
      expect(top(order[i]), greaterThanOrEqualTo(top(order[i - 1])), reason: '${order[i]} after ${order[i - 1]}');
    }
    final semantics = tester.ensureSemantics();
    for (final header in ['网络', '状态', '调试', '日志']) {
      expect(tester.getSemantics(find.text(header)).flagsCollection.isHeader, isTrue);
    }
    semantics.dispose();
  });

  testWidgets('the account, the BV box, the always-on player and its switches, and 推荐\'s choice are gone', (
    tester,
  ) async {
    final world = DeveloperWorld();
    await world.show(tester, logs: quietLogs(), appAuth: StubAppAuth());
    for (final text in ['测试用户', '大会员', '播放', '加速', '显示统计', '弹幕', '小窗播放', '清晰度', '推荐', '官方', '网页']) {
      expect(find.text(text), findsNothing, reason: text);
    }
    expect(row('link-field'), findsNothing);
    expect(row('speedtest-stage'), findsNothing);
    expect(find.byType(SegmentedButton<bool>), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(world.players, isEmpty, reason: 'no player until a speed test asks for one');
    expect(world.playback.live, 0);
  });

  group('状态', () {
    testWidgets('reads 版本, the nodes the shared engine reported, the trials, the waiting reports and the font', (
      tester,
    ) async {
      const ali = 'upos-sz-mirrorali.bilivideo.com';
      const cos = 'upos-sz-mirrorcos.bilivideo.com';
      final trials = BackgroundTrials()
        ..record(trip(BackgroundArm.continuedArm, seconds: 60, megabytes: 300))
        ..record(trip(BackgroundArm.handOffArms.first, seconds: 120, megabytes: 240));
      final at = DateTime(2026, 11, 2, 9);
      final world = DeveloperWorld(
        offline: TrialLibrary(trials),
        historyOutbox: HeldOutbox([
          PendingReport(bvid: bv, cid: 1, played: 30, at: at),
          PendingReport(bvid: 'BV1xx411c7mD', cid: 2, played: -1, at: at),
        ]),
      );
      await world.show(
        tester,
        before: () async {
          final engine = await world.shared.current() as FakeEngine;
          engine.statsController.add(
            const EngineSnapshot(
              nodes: [
                NodeTiming(node: ali, firstByteMs: 85.4),
                NodeTiming(node: cos, firstByteMs: 140),
              ],
              nodeStates: [
                NodeStatus(node: ali, state: 'healthy', bps: 12.3 * 1048576),
                NodeStatus(node: cos, state: 'banned', bps: 2 * 1048576),
              ],
            ),
          );
        },
      );
      expect(inRow('status-version', '1.3.0 (7)'), findsOneWidget);
      expect(inRow('status-nodes', '2 个 · 封禁 1'), findsOneWidget);
      final aliLine = row('status-node-$ali');
      expect(find.descendant(of: aliLine, matching: find.text('mirrorali')), findsOneWidget);
      expect(find.descendant(of: aliLine, matching: find.text('12.3 MB/s · 85 ms')), findsOneWidget);
      expect(find.descendant(of: row('status-node-$cos'), matching: find.text('封禁')), findsOneWidget);
      expect(
        tester.getTopLeft(aliLine).dy,
        lessThan(tester.getTopLeft(row('status-node-$cos')).dy),
        reason: 'fastest first',
      );

      expect(inRow('status-background', '持续处理 · 共 2 次'), findsOneWidget);
      expect(find.descendant(of: row('status-arm-continued'), matching: find.text('1 次 · 5.0 MB/s')), findsOneWidget);
      expect(
        find.descendant(of: row('status-arm-handoff-3x128'), matching: find.text('1 次 · 2.0 MB/s')),
        findsOneWidget,
      );
      expect(find.descendant(of: row('status-arm-handoff-2x64'), matching: find.text('暂无结果')), findsOneWidget);
      expect(inRow('status-outbox', '2 条'), findsOneWidget);
      expect(inRow('status-font', '仅 iOS'), findsOneWidget);
    });

    testWidgets('with nothing played, no trials and nothing waiting, each says so', (tester) async {
      final world = DeveloperWorld();
      await world.show(tester);
      expect(inRow('status-nodes', '暂无'), findsOneWidget);
      expect(find.byKey(const ValueKey('status-node-upos-sz-mirrorali.bilivideo.com')), findsNothing);
      expect(inRow('status-background', '无'), findsOneWidget);
      expect(inRow('status-outbox', '无'), findsOneWidget);
    });

    testWidgets('on iOS 系统字体 names what launch settled after the system font, SF by its own name', (tester) async {
      final saved = BiliFonts.systemFallback;
      addTearDown(() => BiliFonts.systemFallback = saved);
      BiliFonts.systemFallback = const [BiliFonts.appleSystem, 'PingFang SC'];
      final world = DeveloperWorld();
      await world.show(tester);
      expect(inRow('status-font', 'SF + PingFang SC'), findsOneWidget);

      BiliFonts.systemFallback = null;
      world.pop();
      await frames(tester, 20);
      await world.push(tester);
      expect(inRow('status-font', '未指定'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });

  group('官方接口', () {
    testWidgets('without the token it reads 未授权, and 授权 asks for it', (tester) async {
      final auth = StubAppAuth();
      await DeveloperWorld().show(tester, appAuth: auth);
      expect(inRow('app-auth-state', '未授权'), findsOneWidget);
      expect(inRow('app-auth-button', '授权'), findsOneWidget);

      await press(tester, row('app-auth-button'));
      expect(auth.requests, 1);
      expect(auth.reauthorizations, 0);
      expect(inRow('app-auth-state', '已授权 · iPhone · 剩 180 天'), findsOneWidget);
      expect(inRow('app-auth-button', '重新授权'), findsOneWidget);
    });

    testWidgets("with the token it reads the token's app and the days left, and 重新授权 asks again, pressed through "
        'VoiceOver', (tester) async {
      final auth = StubAppAuth(
        expiresAt: DateTime.now().add(const Duration(days: 42, hours: 12)),
        issuedTo: OfficialIdentity.android,
      );
      await DeveloperWorld().show(tester, appAuth: auth);
      expect(inRow('app-auth-state', '已授权 · Android · 剩 42 天'), findsOneWidget);

      final semantics = tester.ensureSemantics();
      tester.semantics.tap(find.semantics.byLabel('重新授权'));
      await tester.pump();
      expect(auth.reauthorizations, 1);
      expect(auth.requests, 0);
      semantics.dispose();
    });

    testWidgets('without a token service both rows are left out', (tester) async {
      await DeveloperWorld().show(tester);
      expect(row('app-auth-state'), findsNothing);
      expect(row('app-auth-button'), findsNothing);
      expect(row('dev-turn'), findsOneWidget);
    });
  });

  testWidgets('‹ in the bar leaves 开发者, pressed or through VoiceOver', (tester) async {
    final semantics = tester.ensureSemantics();
    final world = DeveloperWorld();
    await world.show(tester);
    await tester.tap(find.byKey(const ValueKey('settings-back')));
    await frames(tester, 20);
    expect(find.byType(DeveloperPage), findsNothing);

    await world.push(tester);
    final back = find.semantics.byLabel('返回');
    expect(back.evaluate().single.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    tester.semantics.tap(back);
    await frames(tester, 20);
    expect(find.byType(DeveloperPage), findsNothing);
    semantics.dispose();
  });
}
