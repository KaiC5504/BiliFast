import 'dart:io';

import 'package:bili_core/api.dart' show OfficialIdentity;
import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bilifast/devtools/developer_page.dart';
import 'package:bilifast/devtools/node_probe_section.dart';
import 'package:bilifast/offline/disk/background_trials.dart';
import 'package:bilifast/settings/settings_confirm.dart';
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
      row('dev-codec-memory'),
      row('app-auth-state'),
      find.text('日志'),
      row('log-switch'),
      row('log-export'),
      row('dev-clear-logs'),
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

  group('重置编码记忆 and 清除日志, moved from 设置', () {
    late MemorySink sink;

    setUp(() {
      sink = MemorySink();
      Logger.shared.add(sink);
      addTearDown(() => Logger.shared.remove(sink));
    });

    final confirm = find.byType(SettingsConfirm);
    Finder confirmButton(String label) => find.byKey(ValueKey('settings-confirm-$label'));
    Finder inConfirm(String text) => find.descendant(of: confirm, matching: find.text(text));
    List<LogEvent> logged(String msg) => [
      for (final event in sink.events)
        if (event.msg == msg) event,
    ];

    Future<void> ask(WidgetTester tester, String key) async {
      await press(tester, row(key));
      await tester.pumpAndSettle();
    }

    testWidgets('重置编码记忆 asks in 设置\'s words, and 重置 forgets the codecs that failed', (tester) async {
      final world = DeveloperWorld();
      await world.show(tester);
      world.codecMemory.markFailed('av1');
      await ask(tester, 'dev-codec-memory');
      expect(inConfirm('重置编码记忆？'), findsOneWidget);
      expect(inConfirm('本机播放失败过的编码会重新参与尝试。'), findsOneWidget);
      expect(world.codecMemory.failedKinds, {'av1'}, reason: 'nothing is reset before the confirm');

      await tester.tap(confirmButton('重置'));
      await tester.pumpAndSettle();
      expect(world.codecMemory.failedKinds, isEmpty);
      expect(confirm, findsNothing);
      expect(logged('developer clear').single.f['what'], const LogString('codecMemory'));
      expect(world.logFiles.clears, 0);
    });

    testWidgets('清除日志 asks in 设置\'s words, and 清除 clears the phone\'s log files', (tester) async {
      final world = DeveloperWorld();
      await world.show(tester, logs: quietLogs());
      world.codecMemory.markFailed('av1');
      await ask(tester, 'dev-clear-logs');
      expect(inConfirm('清除日志？'), findsOneWidget);
      expect(inConfirm('手机上保存的调试日志会被删除，已发送到电脑的不受影响。'), findsOneWidget);
      expect(world.logFiles.clears, 0);

      await tester.tap(confirmButton('清除'));
      await tester.pumpAndSettle();
      expect(world.logFiles.clears, 1);
      expect(confirm, findsNothing);
      expect(logged('developer clear').single.f['what'], const LogString('logs'));
      expect(world.codecMemory.failedKinds, {'av1'});
    });

    testWidgets('a clear that fails logs only the error\'s type', (tester) async {
      final world = DeveloperWorld();
      world.logFiles.clearFailure = const FileSystemException('busy', '/caches/BiliFast-logs.jsonl');
      await world.show(tester);
      await ask(tester, 'dev-clear-logs');
      await tester.tap(confirmButton('清除'));
      await tester.pumpAndSettle();
      expect(world.logFiles.clears, 1);
      final warning = logged('log files not cleared').single;
      expect(warning.f['error'], const LogString('FileSystemException'));
      expect(confirm, findsNothing);
    });

    testWidgets('取消 and back close each confirm and do nothing; back leaves the page only after', (tester) async {
      final world = DeveloperWorld();
      await world.show(tester);
      world.codecMemory.markFailed('av1');
      for (final key in ['dev-codec-memory', 'dev-clear-logs']) {
        await ask(tester, key);
        await tester.tap(confirmButton('取消'));
        await tester.pumpAndSettle();
        expect(confirm, findsNothing, reason: key);

        await ask(tester, key);
        await world.navigator.currentState!.maybePop();
        await tester.pumpAndSettle();
        expect(confirm, findsNothing, reason: key);
        expect(find.byType(DeveloperPage), findsOneWidget, reason: 'back closed the confirm, not the page');
      }
      expect(world.codecMemory.failedKinds, {'av1'});
      expect(world.logFiles.clears, 0);
      expect(logged('developer clear'), isEmpty);

      await world.navigator.currentState!.maybePop();
      await tester.pumpAndSettle();
      expect(find.byType(DeveloperPage), findsNothing);
    });

    testWidgets('both rows and their confirms answer VoiceOver, and an open confirm hides the page behind it', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final world = DeveloperWorld();
      await world.show(tester);
      world.codecMemory.markFailed('av1');

      tester.semantics.tap(find.semantics.byLabel('重置编码记忆'));
      await tester.pumpAndSettle();
      expect(inConfirm('重置编码记忆？'), findsOneWidget);
      expect(find.semantics.byLabel('清除日志'), findsNothing, reason: 'the rows behind are blocked');
      tester.semantics.tap(find.semantics.byLabel('重置'));
      await tester.pumpAndSettle();
      expect(world.codecMemory.failedKinds, isEmpty);

      tester.semantics.tap(find.semantics.byLabel('清除日志'));
      await tester.pumpAndSettle();
      expect(inConfirm('清除日志？'), findsOneWidget);
      tester.semantics.tap(find.semantics.byLabel('清除'));
      await tester.pumpAndSettle();
      expect(world.logFiles.clears, 1);
      expect(find.semantics.byLabel('重置编码记忆'), findsOne);
      semantics.dispose();
    });

    testWidgets('测试崩溃 still asks its own question after a clear', (tester) async {
      final world = DeveloperWorld();
      await world.show(tester);
      await ask(tester, 'dev-clear-logs');
      await tester.tap(confirmButton('取消'));
      await tester.pumpAndSettle();
      await ask(tester, 'test-crash');
      expect(inConfirm('让应用立即崩溃？'), findsOneWidget);
      expect(confirmButton('崩溃'), findsOneWidget);
      expect(confirmButton('清除'), findsNothing);
      await tester.tap(confirmButton('取消'));
      await tester.pumpAndSettle();
      expect(world.logFiles.clears, 0);
      expect(tester.takeException(), isNull);
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
