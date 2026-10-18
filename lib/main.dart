import 'dart:async';
import 'dart:io' show Platform;

import 'package:bili_core/devlog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/app_environment.dart';
import 'app/app_scope.dart';
import 'app/phone_frame.dart';
import 'app/reduce_motion.dart';
import 'app/route_observer.dart';
import 'device/player_device.dart';
import 'devtools/crash_log.dart';
import 'devtools/log_forwarder.dart';
import 'home/home_page.dart';
import 'home/recent_store.dart';
import 'playback/playback_setup.dart';
import 'screens/player_test_page.dart';
import 'settings/follow_font.dart';
import 'settings/font_store.dart';
import 'shared/theme.dart';
import 'video/fake_page_api.dart';
import 'video/player_prefs.dart';

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
  final FontStore fonts;
  try {
    environment = await AppEnvironment.load();
    recents = await RecentStore.load(supportFilePath('recents.json'));
    PlayerPrefs.shared = await PlayerPrefs.load(supportFilePath('player_prefs.json'));
    fonts = await FontStore.load(supportFilePath('font.json'));
  } catch (error, stack) {
    // Without this the launch screen would stay up with nothing to say why.
    CrashLog.report(error, stack, source: 'launch');
    runApp(LaunchFailedApp(error: '$error'));
    return;
  }
  // PC checks only: the page's actions answer from memory, so every button can be pressed with no account traffic.
  final fakeAccount = !Platform.isIOS && args.contains('--fake-account');
  if (fakeAccount) environment.useFakeAccount();
  unawaited(environment.refreshAccount());
  final playback = AppPlayback(
    () => startPlaybackController(environment.client),
    onResumed: () => recheckUnknownAccount(environment),
  );
  // Checks run on the PC play silently.
  if (args.contains('--mute')) {
    unawaited(playback.obtain().then((controller) => controller.player.setMuted(true), onError: (Object _) {}));
  }
  final device = PlayerDevice.platform();
  PhoneFrame.follow(device.orientation);
  runApp(BiliFastApp(
    services: AppServices(
      environment: environment,
      playback: playback,
      recents: recents,
      device: device,
      fonts: fonts,
      pageApi: fakeAccount ? FakePageApi.demo() : null,
      logs: logs,
    ),
    initialLink: _argument(args, '--play='),
  ));
}

/// The launch's account check fails without a network; as Swift's RootView did on becoming active, coming back to
/// the foreground asks again while the account is still unknown.
void recheckUnknownAccount(AppEnvironment environment) {
  if (environment.account is AccountUnknown) unawaited(environment.refreshAccount());
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
    return FollowFont(
      fonts: services.fonts,
      builder: (context) => MaterialApp(
        title: 'BiliFast',
        debugShowCheckedModeBanner: false,
        locale: BiliFonts.locale,
        supportedLocales: const [BiliFonts.locale],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          fontFamily: BiliFonts.family,
          colorScheme: ColorScheme.fromSeed(seedColor: BiliColors.pink, primary: BiliColors.pink),
          scaffoldBackgroundColor: BiliColors.pageGrey,
          // iOS has no ripples; rows show their own press highlight.
          splashFactory: NoSplash.splashFactory,
        ),
        navigatorObservers: [pageRoutes],
        builder: (context, child) =>
            AppScope(services: services, child: PhoneFrame.wrap(context, ReduceMotion(child: child!))),
        home: HomePage(
          initialLink: initialLink,
          developerPage: services.logs == null
              ? null
              : (context) => PlayerTestPage(
                    environment: services.environment,
                    startPlayback: services.playback.obtain,
                    logs: services.logs,
                    ownsController: false,
                  ),
        ),
      ),
    );
  }
}
