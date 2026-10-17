import 'dart:async';
import 'dart:io' show Platform;

import 'package:bili_core/devlog.dart';
import 'package:flutter/material.dart';

import 'app/app_environment.dart';
import 'devtools/crash_log.dart';
import 'devtools/log_forwarder.dart';
import 'playback/playback_controller.dart';
import 'playback/playback_setup.dart';
import 'screens/player_test_page.dart';
import 'shared/theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  CrashLog.install();
  final logs = devToolsEnabled ? LogForwarder() : null;
  Logger.shared.info(LogCategory.app, 'launch', {
    'platform': Platform.operatingSystem,
    'os': Platform.operatingSystemVersion,
    'devTools': devToolsEnabled,
  });
  final environment = await AppEnvironment.load();
  unawaited(environment.refreshAccount());
  runApp(BiliFastApp(
    environment: environment,
    logs: logs,
    startPlayback: () => startPlaybackController(environment.client),
    initialLink: _argument(args, '--play='),
  ));
}

String? _argument(List<String> args, String prefix) =>
    args.where((arg) => arg.startsWith(prefix)).map((arg) => arg.substring(prefix.length)).firstOrNull;

class BiliFastApp extends StatelessWidget {
  const BiliFastApp(
      {super.key, required this.environment, required this.startPlayback, this.logs, this.initialLink});

  final AppEnvironment environment;
  final Future<PlaybackController> Function() startPlayback;
  final LogForwarder? logs;
  final String? initialLink;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BiliFast',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: BiliColors.pink, primary: BiliColors.pink),
        scaffoldBackgroundColor: BiliColors.pageGrey,
      ),
      // Stands in until slice 3 ports the 推荐 home.
      home: PlayerTestPage(
          environment: environment, startPlayback: startPlayback, logs: logs, initialLink: initialLink),
    );
  }
}
