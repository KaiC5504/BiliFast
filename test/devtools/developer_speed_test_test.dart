import 'dart:async';
import 'dart:io' show SocketException;

import 'package:bilifast/devtools/developer_page.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/playback/shared_engine.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/speedtest/speed_test_plan.dart';
import 'package:bilifast/speedtest/speed_test_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';
import '../speedtest/fake_target.dart';
import 'developer_world.dart';

const quick = <String, Object?>{
  'order': 'AB',
  'seeks': 0,
  'hints': 0,
  'backJumps': 0,
  'dwellSeconds': 0,
  'fastSeconds': 0,
};

/// 网络's 速度测试: a player only once a run asks for one, shown only while the run plays, on the shared engine with
/// each variant's engine its own; the run's numbers under it.
void main() {
  late List<String> engines;

  setUp(() => engines = []);

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

  final stage = find.byKey(const ValueKey('speedtest-stage'));
  final start = find.byKey(const ValueKey('speedtest-start'));
  final stop = find.byKey(const ValueKey('speedtest-stop'));
  final results = find.byKey(const ValueKey('speedtest-results'));

  Future<void> startTest(WidgetTester tester, [String links = bv]) async {
    await tester.enterText(find.byKey(const ValueKey('speedtest-links')), links);
    FocusManager.instance.primaryFocus?.unfocus();
    // The field's scroll to its caret ignores taps until it ends.
    await frames(tester);
    await press(tester, start);
    await frames(tester, 20);
  }

  Future<void> firstFrame(WidgetTester tester, DeveloperWorld world) async {
    world.players.single.emit(const StatusChanged(PlayerStatus.playing));
    await frames(tester, 20);
  }

  testWidgets('the player shows only while a run plays, a 16:9 box in the card, and the numbers stay after it', (
    tester,
  ) async {
    final world = DeveloperWorld();
    // The first pass on the video is cold; B is compared with the warm A after it.
    await world.show(tester, logs: quietLogs(), hooks: hooksFor({...quick, 'order': 'ABA'}));
    expect(stage, findsNothing);
    expect(world.players, isEmpty);
    expect(find.text('开始速度测试'), findsOneWidget);

    await startTest(tester);
    expect(stage, findsOneWidget);
    expect(find.descendant(of: stage, matching: find.byKey(const ValueKey('stage'))), findsOneWidget);
    expect(tester.getSize(stage), const Size(440, 440 * 9 / 16));
    expect(tester.getTopLeft(stage).dy, greaterThan(tester.getTopLeft(stop).dy), reason: 'under 停止速度测试');
    expect(find.text('停止速度测试'), findsOneWidget);
    expect(find.textContaining('计划 test-1（内置，没有连接电脑） · 第 1/3 次 · A · 4K · 等待首帧'), findsOneWidget);

    await firstFrame(tester, world);
    expect(find.textContaining('第 2/3 次 · B'), findsOneWidget);
    await firstFrame(tester, world);
    await firstFrame(tester, world);

    expect(stage, findsNothing);
    expect(start, findsOneWidget);
    expect(results, findsOneWidget);
    for (final label in ['A 4K 冷 ×1', 'A 4K 热 ×1', 'B 4K 热 ×1', 'B−A 4K 热']) {
      expect(
        find.descendant(of: results, matching: find.text(label)),
        findsOneWidget,
        reason: label,
      );
    }
    expect(find.textContaining('完成'), findsOneWidget);
    expect(engines, ['A', 'A', 'B', 'A', 'app']);
    expect(
      world.players.single.calls,
      containsAllInOrder(['muted true', 'keep awake true', 'muted false', 'keep awake false']),
    );
    expect(
      world.http.to(Canned.viewPath).length + world.http.to(Canned.signedViewPath).length,
      1,
      reason: 'one open per video',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('停止速度测试 stops the run, gives the sound and the screen back and takes the player away', (tester) async {
    final world = DeveloperWorld();
    await world.show(tester, logs: quietLogs(), hooks: hooksFor(quick));
    await startTest(tester);
    expect(stage, findsOneWidget);
    await press(tester, stop);
    await frames(tester, 20);
    expect(find.textContaining('已停止'), findsOneWidget);
    expect(start, findsOneWidget);
    expect(stage, findsNothing);
    expect(results, findsNothing);
    expect(world.players.single.calls, containsAllInOrder(['muted true', 'muted false', 'keep awake false']));
  });

  testWidgets('a second run reuses the first run\'s player', (tester) async {
    final world = DeveloperWorld();
    await world.show(tester, logs: quietLogs(), hooks: hooksFor({...quick, 'order': 'A'}));
    await startTest(tester);
    await firstFrame(tester, world);
    expect(stage, findsNothing);
    await startTest(tester);
    expect(stage, findsOneWidget);
    await firstFrame(tester, world);
    expect(world.players, hasLength(1));
    expect(world.playback.live, 1);
  });

  testWidgets('开始速度测试 and 停止速度测试 answer VoiceOver, as ghosthand presses them', (tester) async {
    final semantics = tester.ensureSemantics();
    final world = DeveloperWorld();
    await world.show(tester, logs: quietLogs(), hooks: hooksFor(quick));
    await tester.enterText(find.byKey(const ValueKey('speedtest-links')), bv);
    tester.semantics.tap(find.semantics.byLabel('开始速度测试'));
    await frames(tester, 20);
    expect(stage, findsOneWidget);
    tester.semantics.tap(find.semantics.byLabel('停止速度测试'));
    await frames(tester, 20);
    expect(stage, findsNothing);
    expect(find.textContaining('已停止'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the plan is asked of the PC the logs go to, only while they are switched on', (tester) async {
    final asked = <String?>[];
    final logs = quietLogs();
    final world = DeveloperWorld();
    await world.show(
      tester,
      logs: logs,
      hooks: SpeedTestHooks(
        choosePlan: (server) async {
          asked.add(server?.host);
          throw const SpeedTestPlanError('stop here');
        },
        startEngine: (variant) async => FakeEngine(),
        appEngine: () async => FakeEngine(),
      ),
    );
    logs.setManual('10.0.0.2:47321');
    await startTest(tester);
    logs.setEnabled(true);
    await tester.pump();
    await startTest(tester);
    logs.setEnabled(false);
    await tester.pump();
    expect(asked, [null, '10.0.0.2']);
  });

  testWidgets('a plan the PC got wrong is shown and nothing plays', (tester) async {
    final world = DeveloperWorld();
    await world.show(
      tester,
      logs: quietLogs(),
      hooks: hooksFor(quick, planError: const SpeedTestPlanError('方案 B 的 config 有引擎不认识或类型不对的项：typo')),
    );
    await startTest(tester);
    expect(find.byKey(const ValueKey('speedtest-error')), findsOneWidget);
    expect(find.textContaining('typo'), findsOneWidget);
    expect(stage, findsNothing);
    expect(engines, isEmpty);
    expect(world.players.single.calls, isNot(contains('muted true')));
  });

  testWidgets('a player that fails to start says so by the error\'s kind, never its text, and 开始 tries again', (
    tester,
  ) async {
    final world = DeveloperWorld()..startError = StateError('https://upos-sz-mirrorcos.bilivideo.com/v.m4s?upsig=secret');
    await world.show(tester, logs: quietLogs(), hooks: hooksFor({...quick, 'order': 'A'}));
    await startTest(tester);
    expect(find.text('播放器启动失败：StateError'), findsOneWidget);
    expect(find.textContaining('upsig'), findsNothing);
    expect(stage, findsNothing);
    expect(world.playback.live, 0);

    world.startError = const SocketException('Connection refused (https://upos-sz-mirrorcos.bilivideo.com/?upsig=1)');
    await startTest(tester);
    expect(find.text('播放器启动失败：网络连接失败，请检查网络后重试'), findsOneWidget);
    expect(find.textContaining('upsig'), findsNothing);

    await startTest(tester);
    expect(find.byKey(const ValueKey('speedtest-error')), findsNothing);
    expect(stage, findsOneWidget);
    await firstFrame(tester, world);
  });

  group('the run\'s player', () {
    PlanChoice quickPlan() => PlanChoice(plan: planWith(quick), source: PlanSource.builtin, note: '');

    testWidgets('is the app\'s, on the shared engine; leaving releases it and the engine runs on', (tester) async {
      final world = DeveloperWorld();
      await world.show(tester, logs: quietLogs(), hooks: hooksFor(quick));
      expect(world.playback.live, 0);
      await startTest(tester);
      expect(world.playback.live, 1);

      world.pop();
      await frames(tester, 30);
      expect(tester.takeException(), isNull);
      expect(find.byType(DeveloperPage), findsNothing);
      expect(world.playback.live, 0);
      expect(world.players.single.disposed, isTrue);
      expect(world.engines.single.disposed, isFalse);
    });

    testWidgets('asked for and still starting when the page goes, is released once it arrives', (tester) async {
      final world = DeveloperWorld();
      await world.show(tester, logs: quietLogs(), hooks: hooksFor(quick));
      final gate = world.startGate = Completer<void>();
      await startTest(tester);
      expect(find.text('播放器启动中…'), findsOneWidget);
      world.pop();
      await frames(tester, 20);
      gate.complete();
      await frames(tester);
      expect(world.players.single.disposed, isTrue);
      expect(world.playback.live, 0);
      expect(engines, isEmpty, reason: 'no run starts on a page that has gone');
    });

    testWidgets('alone has its engine swapped; leaving mid run releases it and its variant, and a video page\'s player '
        'stays on the shared engine', (tester) async {
      final world = DeveloperWorld();
      final variants = <FakeEngine>[];
      var putBacks = 0;
      final hooks = SpeedTestHooks(
        choosePlan: (server) async => quickPlan(),
        startEngine: (variant) async {
          final started = FakeEngine();
          variants.add(started);
          return started;
        },
        appEngine: () {
          putBacks += 1;
          return world.shared.lease();
        },
      );
      await world.show(tester, logs: quietLogs(), hooks: hooks);
      final page = await world.playback.create();
      await page.open(bv);
      await startTest(tester);
      final developer = world.controllers.last;
      expect(variants, isNotEmpty);
      expect(developer.engine, same(variants.last));
      expect((page.engine as EngineLease).engine, same(world.engines.single));

      world.pop();
      await frames(tester, 30);
      expect(world.playback.live, 1, reason: 'the video page\'s');
      expect(world.players.last.disposed, isTrue);
      expect(variants.every((variant) => variant.disposed), isTrue);
      expect(putBacks, 0, reason: 'nothing to put back on a player that went with the page');
      expect(world.engines, hasLength(1));
      expect(world.engines.single.disposed, isFalse);
      expect((page.engine as EngineLease).engine, same(world.engines.single));
      expect(page.phase, isNot(PlaybackPhase.failed));
    });

    testWidgets('an engine swap still starting when 开发者 goes is dropped with it', (tester) async {
      final world = DeveloperWorld();
      final gate = Completer<void>();
      final variants = <FakeEngine>[];
      final hooks = SpeedTestHooks(
        choosePlan: (server) async => quickPlan(),
        startEngine: (variant) async {
          final started = FakeEngine();
          variants.add(started);
          // The first pass's own engine, for its replay.
          if (variants.length == 2) await gate.future;
          return started;
        },
        appEngine: world.shared.lease,
      );
      await world.show(tester, logs: quietLogs(), hooks: hooks);
      await startTest(tester);
      expect(variants, hasLength(2));
      world.pop();
      await frames(tester, 30);
      gate.complete();
      await frames(tester, 10);
      expect(variants.every((variant) => variant.disposed), isTrue);
      expect(variants.last.prepared, isEmpty, reason: 'the replay that asked for it was overtaken');
      expect(world.playback.live, 0);
      expect(world.engines.single.disposed, isFalse);
    });
  });
}
