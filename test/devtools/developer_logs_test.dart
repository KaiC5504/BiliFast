import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/devtools/crash_log.dart';
import 'package:bilifast/devtools/log_server_discovery.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'developer_world.dart';

/// 开发者's 日志: 发送日志到电脑 with the PCs found over Bonjour and a typed address, 导出日志 and 测试崩溃.
void main() {
  late List<(String, Rect?)> shared;

  setUp(() => shared = []);

  Finder key(String name) => find.byKey(ValueKey(name));

  /// Lets a toast run its course, so no timer is left behind.
  Future<void> settleToast(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
  }

  group('发送日志到电脑', () {
    testWidgets('switched on, then pointed at a typed address by 连接', (tester) async {
      final logs = quietLogs();
      await DeveloperWorld().show(tester, logs: logs);
      expect(find.text('未开启'), findsOneWidget);
      expect(key('log-address'), findsNothing, reason: 'the address shows once it is on');

      await press(tester, key('log-switch'));
      expect(logs.enabled, isTrue);
      expect(find.text('请选择电脑，或输入 IP:端口'), findsOneWidget);
      await tester.enterText(key('log-address'), '10.0.0.2:47321');
      await press(tester, key('log-connect'));
      expect(logs.target?.host, '10.0.0.2');
      expect(tester.widget<Text>(key('log-status')).data, logs.status);
      expect(logs.status, isNot('请选择电脑，或输入 IP:端口'));

      await press(tester, key('log-switch'));
      expect(logs.enabled, isFalse);
      expect(find.text('未开启'), findsOneWidget);
    });

    testWidgets('the switch and 连接 answer VoiceOver, and submitting the field connects too', (tester) async {
      final semantics = tester.ensureSemantics();
      final logs = quietLogs();
      await DeveloperWorld().show(tester, logs: logs);
      tester.semantics.tap(find.semantics.byLabel('发送日志到电脑'));
      await tester.pump();
      expect(logs.enabled, isTrue);

      await tester.enterText(key('log-address'), '10.0.0.3');
      tester.semantics.tap(find.semantics.byLabel('连接'));
      await tester.pump();
      expect(logs.target?.host, '10.0.0.3');
      expect(logs.target?.port, LogServerEndpoint.defaultPort);

      await tester.enterText(key('log-address'), '10.0.0.4:5000');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(logs.target?.host, '10.0.0.4');
      // Stops the sink's timers before the test ends.
      logs.setEnabled(false);
      await tester.pump();
      semantics.dispose();
    });

    group('PCs found over Bonjour', () {
      const pc = LogServerEndpoint(name: 'KaiC-PC', host: '192.168.1.5', port: 47321);

      testWidgets('are rows above the typed address; tapping one sends the logs there', (tester) async {
        final discovery = FakeDiscovery();
        final logs = quietLogs(discovery: discovery);
        await DeveloperWorld().show(tester, logs: logs);
        await press(tester, key('log-switch'));
        discovery.controller.add(const [pc]);
        await tester.pump();

        final row = key('log-server-KaiC-PC');
        expect(row, findsOneWidget);
        expect(find.descendant(of: row, matching: find.text('192.168.1.5:47321')), findsOneWidget);
        expect(tester.getTopLeft(row).dy, lessThan(tester.getTopLeft(key('log-address')).dy));
        expect(find.byIcon(Icons.check), findsNothing);
        expect(logs.sink, isNull);

        await press(tester, row);
        expect(logs.target?.host, '192.168.1.5');
        expect(logs.target?.port, 47321);
        expect(logs.sink, isNotNull);
        expect(find.descendant(of: row, matching: find.byIcon(Icons.check)), findsOneWidget);
        expect(tester.widget<Text>(key('log-status')).data, logs.status);

        await press(tester, row);
        expect(logs.service, isNull, reason: 'a second tap goes back to the typed address');
        expect(find.text('请选择电脑，或输入 IP:端口'), findsOneWidget);
      });

      testWidgets('a PC that goes away leaves the list', (tester) async {
        final discovery = FakeDiscovery();
        await DeveloperWorld().show(tester, logs: quietLogs(discovery: discovery));
        await press(tester, key('log-switch'));
        discovery.controller.add(const [pc]);
        await tester.pump();
        discovery.controller.add(const []);
        await tester.pump();
        expect(key('log-server-KaiC-PC'), findsNothing);
        expect(key('log-address'), findsOneWidget);
      });
    });

    testWidgets('without a forwarder only 导出日志 and 测试崩溃 are left', (tester) async {
      await DeveloperWorld().show(tester);
      expect(key('log-switch'), findsNothing);
      expect(key('log-status'), findsNothing);
      expect(key('log-export'), findsOneWidget);
      expect(key('test-crash'), findsOneWidget);
    });
  });

  group('导出日志', () {
    testWidgets('hands the prepared file to the share sheet, pointed at the row', (tester) async {
      final world = DeveloperWorld();
      world.logFiles.path = '/caches/BiliFast-logs.jsonl';
      await world.show(tester, shareFile: (path, origin) async => shared.add((path, origin)));
      expect(find.descendant(of: key('log-export'), matching: find.text('最近 20 MB')), findsOneWidget);
      await press(tester, key('log-export'));
      await tester.pump();
      expect(world.logFiles.exports, 1);
      expect(shared.single.$1, '/caches/BiliFast-logs.jsonl');
      expect(shared.single.$2, tester.getRect(key('log-export')), reason: 'an iPad points the sheet at the row');
      expect(key('toast'), findsNothing);
    });

    testWidgets('answers VoiceOver', (tester) async {
      final semantics = tester.ensureSemantics();
      final world = DeveloperWorld();
      world.logFiles.path = '/caches/BiliFast-logs.jsonl';
      await world.show(tester, shareFile: (path, origin) async => shared.add((path, origin)));
      tester.semantics.tap(find.semantics.byLabel(RegExp('导出日志')));
      await tester.pump();
      await tester.pump();
      expect(shared, hasLength(1));
      semantics.dispose();
    });

    testWidgets('with nothing logged says so and shares nothing', (tester) async {
      final world = DeveloperWorld();
      await world.show(tester, shareFile: (path, origin) async => shared.add((path, origin)));
      await press(tester, key('log-export'));
      await tester.pump();
      expect(world.logFiles.exports, 1);
      expect(find.text('没有可导出的日志'), findsOneWidget);
      expect(shared, isEmpty);
      await settleToast(tester);
    });

    testWidgets('a failed export says so', (tester) async {
      final world = DeveloperWorld();
      world.logFiles.failure = const FileSystemException('disk full');
      await world.show(tester, shareFile: (path, origin) async => shared.add((path, origin)));
      await press(tester, key('log-export'));
      await tester.pump();
      expect(find.text('导出日志失败'), findsOneWidget);
      expect(shared, isEmpty);
      await settleToast(tester);
    });

    testWidgets('a share sheet that fails to open says so, and logs only the error\'s type', (tester) async {
      final sink = MemorySink();
      Logger.shared.add(sink);
      addTearDown(() => Logger.shared.remove(sink));
      final world = DeveloperWorld();
      world.logFiles.path = '/caches/BiliFast-logs.jsonl';
      await world.show(tester, shareFile: (path, origin) async => throw StateError('$path?upsig=secret'));
      await press(tester, key('log-export'));
      await tester.pump();
      expect(find.text('无法打开分享'), findsOneWidget);
      final failed = sink.events.singleWhere((event) => event.msg == 'log share failed');
      expect(failed.f['error'], const LogString('StateError'));
      await settleToast(tester);
    });

    testWidgets('is one export at a time', (tester) async {
      final release = Completer<String?>();
      final world = DeveloperWorld();
      world.logFiles.pending = release.future;
      await world.show(tester, shareFile: (path, origin) async => shared.add((path, origin)));
      await press(tester, key('log-export'));
      expect(find.descendant(of: key('log-export'), matching: find.text('准备中…')), findsOneWidget);
      await press(tester, key('log-export'));
      release.complete('/caches/BiliFast-logs.jsonl');
      await tester.pump();
      await tester.pump();
      expect(world.logFiles.exports, 1);
      expect(shared, hasLength(1));
      expect(find.descendant(of: key('log-export'), matching: find.text('最近 20 MB')), findsOneWidget);
    });
  });

  group('测试崩溃', () {
    late MemorySink crashLog;

    /// CrashLog as main() installs it, on its own logger; the test's handlers are put back afterwards.
    void installCrashLog() {
      final flutterHandler = FlutterError.onError;
      final platformHandler = PlatformDispatcher.instance.onError;
      addTearDown(() {
        FlutterError.onError = flutterHandler;
        PlatformDispatcher.instance.onError = platformHandler;
      });
      crashLog = MemorySink();
      CrashLog.install(logger: Logger(session: 'crash')..add(crashLog));
    }

    List<LogEvent> crashes() => [
      for (final event in crashLog.events)
        if (event.msg == 'crash') event,
    ];

    testWidgets('asks first in 设置\'s alert, and 取消 crashes nothing', (tester) async {
      await DeveloperWorld().show(tester);
      installCrashLog();
      await press(tester, key('test-crash'));
      await tester.pumpAndSettle();
      expect(find.text('让应用立即崩溃？'), findsOneWidget);
      await tester.tap(key('settings-confirm-取消'));
      await tester.pumpAndSettle();
      expect(find.text('让应用立即崩溃？'), findsNothing);
      expect(tester.takeException(), isNull);
      expect(crashes(), isEmpty);
    });

    testWidgets('back closes the alert before it leaves the page', (tester) async {
      final world = DeveloperWorld();
      await world.show(tester);
      await press(tester, key('test-crash'));
      await tester.pumpAndSettle();
      await world.navigator.currentState!.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('让应用立即崩溃？'), findsNothing);
      expect(key('test-crash'), findsOneWidget);
    });

    testWidgets('崩溃 throws an error nothing catches, and CrashLog reports it; the row answers VoiceOver', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await DeveloperWorld().show(tester);
      installCrashLog();
      tester.semantics.tap(find.semantics.byLabel('测试崩溃'));
      await tester.pumpAndSettle();
      expect(crashes(), isEmpty, reason: 'nothing is thrown before the confirm');
      await tester.tap(key('settings-confirm-崩溃'));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isA<DeveloperTestCrash>());
      final report = crashes();
      expect(report, isNotEmpty);
      expect(report.first.level, LogLevel.error);
      expect(report.first.f['error'], const LogString('开发者测试崩溃'));
      expect(report.first.f['source'], const LogString('flutter'));
      await tester.pumpAndSettle();
      expect(find.text('让应用立即崩溃？'), findsNothing);
      semantics.dispose();
    });
  });
}
