import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/devtools/crash_log.dart';
import 'package:bilifast/devtools/log_files.dart';
import 'package:bilifast/devtools/log_forwarder.dart';
import 'package:bilifast/devtools/log_server_discovery.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/screens/player_test_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/fake_player.dart';

final class FakeLogFiles implements LogFiles {
  String? path;
  Object? failure;
  int exports = 0;

  @override
  Future<void> clear() async {}

  @override
  Future<String?> export() async {
    exports += 1;
    if (failure case final failure?) throw failure;
    return path;
  }
}

final class FakeDiscovery implements LogServerDiscovery {
  final controller = StreamController<List<LogServerEndpoint>>.broadcast(sync: true);

  @override
  Stream<List<LogServerEndpoint>> browse() => controller.stream;
}

Widget stageStandIn(BuildContext context, PlaybackController controller,
        {required bool showStats, required bool danmakuEnabled}) =>
    const SizedBox(key: ValueKey('stage'));

/// 开发者's log tools: the PCs found over Bonjour, 导出日志 and 测试崩溃.
void main() {
  late Logger logger;
  late FakeLogFiles files;
  late FakeDiscovery discovery;
  late LogForwarder logs;
  late List<(String, Rect?)> shared;

  setUp(() {
    logger = Logger(session: 'test');
    files = FakeLogFiles();
    discovery = FakeDiscovery();
    logs = LogForwarder(
      logger: logger,
      discovery: discovery,
      poster: (endpoint) => (body) async {},
      initialTarget: '',
    );
    shared = [];
  });

  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(440, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(logs.dispose);
    final environment = await AppEnvironment.load(
        keychain: FakeKeychain(const StoredCookies(Canned.cookies)), http: Canned.http(), logger: logger);
    Future<PlaybackController> start() async => PlaybackController(
          client: environment.client,
          engine: FakeEngine(),
          player: FakePlayer(),
          clock: ManualClock().clock,
          startTimer: FakeTimers().start,
          logger: logger,
        );
    final playback = AppPlayback(start);
    addTearDown(playback.dispose);
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      logFiles: files,
      logs: logs,
    );
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => AppScope(services: services, child: child!),
      home: PlayerTestPage(
        environment: environment,
        startPlayback: playback.create,
        releasePlayback: playback.release,
        logs: logs,
        stageBuilder: stageStandIn,
        shareFile: (path, origin) async => shared.add((path, origin)),
      ),
    ));
    await tester.pump();
  }

  Future<void> press(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.pump();
    await tester.tap(find.byKey(key));
    await tester.pump();
  }

  /// Lets a toast run its course, so no timer is left behind.
  Future<void> settleToast(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
  }

  group('PCs found over Bonjour', () {
    const pc = LogServerEndpoint(name: 'KaiC-PC', host: '192.168.1.5', port: 47321);

    testWidgets('are rows above the typed address; tapping one sends the logs there', (tester) async {
      await show(tester);
      await press(tester, const ValueKey('log-switch'));
      discovery.controller.add(const [pc]);
      await tester.pump();

      final row = find.byKey(const ValueKey('log-server-KaiC-PC'));
      expect(row, findsOneWidget);
      expect(find.text('192.168.1.5:47321'), findsOneWidget);
      expect(tester.getTopLeft(row).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('log-address'))).dy));
      expect(find.byIcon(Icons.check), findsNothing);
      expect(logs.sink, isNull);

      await press(tester, const ValueKey('log-server-KaiC-PC'));
      expect(logs.target?.host, '192.168.1.5');
      expect(logs.target?.port, 47321);
      expect(logs.sink, isNotNull);
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('log-status'))).data, logs.status);
      expect(logs.status, isNot('请选择电脑，或输入 IP:端口'));

      await press(tester, const ValueKey('log-server-KaiC-PC'));
      expect(logs.service, isNull, reason: 'a second tap goes back to the typed address');
      expect(find.text('请选择电脑，或输入 IP:端口'), findsOneWidget);
    });

    testWidgets('a PC that goes away leaves the list', (tester) async {
      await show(tester);
      await press(tester, const ValueKey('log-switch'));
      discovery.controller.add(const [pc]);
      await tester.pump();
      discovery.controller.add(const []);
      await tester.pump();
      expect(find.byKey(const ValueKey('log-server-KaiC-PC')), findsNothing);
      expect(find.byKey(const ValueKey('log-address')), findsOneWidget);
    });
  });

  group('导出日志', () {
    testWidgets('hands the prepared file to the share sheet', (tester) async {
      files.path = '/caches/BiliFast-logs.jsonl';
      await show(tester);
      await press(tester, const ValueKey('log-export'));
      await tester.pump();
      expect(files.exports, 1);
      expect(shared, hasLength(1));
      expect(shared.single.$1, '/caches/BiliFast-logs.jsonl');
      expect(shared.single.$2, isNotNull, reason: 'an iPad points the sheet at the button');
      expect(find.byKey(const ValueKey('toast')), findsNothing);
    });

    testWidgets('with nothing logged says so and shares nothing', (tester) async {
      await show(tester);
      await press(tester, const ValueKey('log-export'));
      await tester.pump();
      expect(files.exports, 1);
      expect(find.text('没有可导出的日志'), findsOneWidget);
      expect(shared, isEmpty);
      await settleToast(tester);
    });

    testWidgets('a failed export says so', (tester) async {
      files.failure = const FileSystemException('disk full');
      await show(tester);
      await press(tester, const ValueKey('log-export'));
      await tester.pump();
      expect(find.text('导出日志失败'), findsOneWidget);
      expect(shared, isEmpty);
      await settleToast(tester);
    });

    testWidgets('is one export at a time', (tester) async {
      final release = Completer<String?>();
      final slow = _SlowLogFiles(release.future);
      files = slow;
      await show(tester);
      await press(tester, const ValueKey('log-export'));
      expect(find.text('准备中…'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('log-export'))).onPressed, isNull);
      release.complete('/caches/BiliFast-logs.jsonl');
      await tester.pump();
      await tester.pump();
      expect(slow.exports, 1);
      expect(shared, hasLength(1));
      expect(find.text('导出'), findsOneWidget);
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

    testWidgets('asks first, and 取消 crashes nothing', (tester) async {
      await show(tester);
      installCrashLog();
      await press(tester, const ValueKey('test-crash'));
      await tester.pumpAndSettle();
      expect(find.text('让应用立即崩溃？'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('crash-cancel')));
      await tester.pumpAndSettle();
      expect(find.text('让应用立即崩溃？'), findsNothing);
      expect(tester.takeException(), isNull);
      expect(crashes(), isEmpty);
    });

    testWidgets('崩溃 throws an error nothing catches, and CrashLog reports it', (tester) async {
      await show(tester);
      installCrashLog();
      await press(tester, const ValueKey('test-crash'));
      await tester.pumpAndSettle();
      expect(crashes(), isEmpty, reason: 'nothing is thrown before the confirm');
      await tester.tap(find.byKey(const ValueKey('crash-confirm')));
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
    });
  });
}

final class _SlowLogFiles extends FakeLogFiles {
  _SlowLogFiles(this._result);

  final Future<String?> _result;

  @override
  Future<String?> export() async {
    exports += 1;
    return _result;
  }
}
