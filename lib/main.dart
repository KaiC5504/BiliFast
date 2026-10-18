import 'dart:async';
import 'dart:io' show Platform;

import 'package:bili_core/devlog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/app_environment.dart';
import 'app/app_scope.dart';
import 'devtools/crash_log.dart';
import 'devtools/log_forwarder.dart';
import 'home/home_page.dart';
import 'home/recent_store.dart';
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
  final AppEnvironment environment;
  final RecentStore recents;
  try {
    environment = await AppEnvironment.load();
    recents = await RecentStore.load(supportFilePath('recents.json'));
  } catch (error, stack) {
    // Without this the launch screen would stay up with nothing to say why.
    CrashLog.report(error, stack, source: 'launch');
    runApp(LaunchFailedApp(error: '$error'));
    return;
  }
  unawaited(environment.refreshAccount());
  runApp(BiliFastApp(
    services: AppServices(
      environment: environment,
      playback: AppPlayback(() => startPlaybackController(environment.client)),
      recents: recents,
      logs: logs,
    ),
    initialLink: _argument(args, '--play='),
  ));
}

/// What the app shows when it could not start.
class LaunchFailedApp extends StatelessWidget {
  const LaunchFailedApp({super.key, required this.error});

  final String error;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'BiliFast',
        debugShowCheckedModeBanner: false,
        locale: BiliFonts.locale,
        supportedLocales: const [BiliFonts.locale],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(fontFamily: BiliFonts.family),
        home: Scaffold(
          backgroundColor: BiliColors.pageGrey,
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(BiliMetrics.gutter),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('BiliFast 启动失败，请重启应用',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: BiliMetrics.titleText, color: BiliColors.text, fontWeight: FontWeight.w600)),
                    const SizedBox(height: BiliMetrics.rowGap),
                    Text(error,
                        key: const ValueKey('launch-error'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: BiliMetrics.smallText, color: BiliColors.failure)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

String? _argument(List<String> args, String prefix) =>
    args.where((arg) => arg.startsWith(prefix)).map((arg) => arg.substring(prefix.length)).firstOrNull;

class BiliFastApp extends StatelessWidget {
  const BiliFastApp({super.key, required this.services, this.initialLink});

  final AppServices services;
  final String? initialLink;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BiliFast',
      debugShowCheckedModeBanner: false,
      locale: BiliFonts.locale,
      supportedLocales: const [BiliFonts.locale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        fontFamily: BiliFonts.family,
        colorScheme: ColorScheme.fromSeed(seedColor: BiliColors.pink, primary: BiliColors.pink),
        scaffoldBackgroundColor: BiliColors.pageGrey,
      ),
      builder: (context, child) => AppScope(services: services, child: child!),
      home: HomePage(
        initialLink: initialLink,
        developerPage: services.logs == null
            ? null
            : (context) => PlayerTestPage(
                  environment: services.environment,
                  startPlayback: () => services.playback.controller,
                  logs: services.logs,
                  ownsController: false,
                ),
      ),
    );
  }
}
