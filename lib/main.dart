import 'dart:async';
import 'dart:io' show Platform;

import 'package:bili_core/devlog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'account/app_auth.dart';
import 'app/app_environment.dart';
import 'app/app_scope.dart';
import 'app/phone_frame.dart';
import 'app/reduce_motion.dart';
import 'app/route_observer.dart';
import 'comments/emote_store.dart';
import 'danmaku/danmaku_settings_store.dart';
import 'device/orientation.dart';
import 'device/player_device.dart';
import 'devtools/crash_log.dart';
import 'devtools/log_files.dart';
import 'devtools/log_forwarder.dart';
import 'favourites/fake_favourites_api.dart';
import 'home/home_page.dart';
import 'home/recent_store.dart';
import 'playback/codec_memory.dart';
import 'playback/playback_setup.dart';
import 'playback/shared_engine.dart';
import 'screens/player_test_page.dart';
import 'search/fake_search_api.dart';
import 'search/search_history_store.dart';
import 'settings/follow_font.dart';
import 'settings/font_store.dart';
import 'space/fake_space_api.dart';
import 'shared/theme.dart';
import 'video/fake_page_api.dart';
import 'video/player_prefs.dart';
import 'watch_later/fake_watch_later_api.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  CrashLog.install();
  final logs = devToolsEnabled ? await LogForwarder.load(supportFilePath('log_server.json')) : null;
  final logFiles = LogFiles.platform();
  Logger.shared.info(LogCategory.app, 'launch', {
    'platform': Platform.operatingSystem,
    'os': Platform.operatingSystemVersion,
    'devTools': devToolsEnabled,
  });
  if (Platform.isIOS) {
    Logger.shared.info(LogCategory.ui, 'system font fallback', {'pingFang': BiliFonts.settleSystemFallback()});
  }
  final AppEnvironment environment;
  final RecentStore recents;
  final FontStore fonts;
  final SearchHistoryStore searchHistory;
  final DanmakuSettingsStore danmakuSettings;
  final CodecMemory codecMemory;
  try {
    environment = await AppEnvironment.load();
    recents = await RecentStore.load(supportFilePath('recents.json'));
    PlayerPrefs.shared = await PlayerPrefs.load(supportFilePath('player_prefs.json'));
    fonts = await FontStore.load(supportFilePath('font.json'));
    searchHistory = await SearchHistoryStore.load(supportFilePath('search_history.json'));
    danmakuSettings = await DanmakuSettingsStore.load(supportFilePath('danmaku_settings.json'));
    RecentEmotes.shared = await RecentEmotes.load(supportFilePath('emotes_recent.json'));
    codecMemory = await CodecMemory.load(codecMemoryPath());
  } catch (error, stack) {
    // Without this the launch screen would stay up with nothing to say why.
    CrashLog.report(error, stack, source: 'launch');
    runApp(LaunchFailedApp(error: '$error'));
    return;
  }
  // PC checks only: the page's actions, 搜索, UP主空间, 我的收藏 and 稍后再看 answer from memory, and the app token
  // reads authorized, so every button can be pressed with no account traffic.
  final fakeAccount = !Platform.isIOS && args.contains('--fake-account');
  if (fakeAccount) environment.useFakeAccount();
  unawaited(environment.refreshAccount());
  final engine = SharedEngine(startPlatformEngine);
  final playback = AppPlayback(
    () => startPlaybackController(environment.client, engine: engine, codecMemory: codecMemory),
    engine: engine,
    codecMemory: codecMemory,
    muted: args.contains('--mute'),
    onResumed: () => recheckUnknownAccount(environment),
  );
  final navigator = GlobalKey<NavigatorState>();
  final AppAuth appAuth =
      fakeAccount ? FakeAppAuth() : TokenAppAuth(environment: environment, navigator: navigator);
  final device = PlayerDevice.platform();
  applyTurnTakeover(device.orientation, PlayerPrefs.shared);
  PhoneFrame.follow(device.orientation);
  runApp(BiliFastApp(
    services: AppServices(
      environment: environment,
      playback: playback,
      recents: recents,
      device: device,
      fonts: fonts,
      pageApi: fakeAccount ? FakePageApi.demo() : null,
      searchApi: fakeAccount ? FakeSearchApi.demo() : null,
      spaceApi: fakeAccount ? FakeSpaceApi.demo() : null,
      favouritesApi: fakeAccount ? FakeFavouritesApi.demo() : null,
      watchLaterApi: fakeAccount ? FakeWatchLaterApi.demo() : null,
      appAuth: appAuth,
      navigator: navigator,
      searchHistory: searchHistory,
      danmakuSettings: danmakuSettings,
      logFiles: logFiles,
      logs: logs,
    ),
    initialLink: _argument(args, '--play='),
  ));
  unawaited(appAuth.start());
}

/// The launch's account check fails without a network; as Swift's RootView did on becoming active, coming back to
/// the foreground asks again while the account is still unknown.
void recheckUnknownAccount(AppEnvironment environment) {
  if (environment.account is AccountUnknown) unawaited(environment.refreshAccount());
}

/// 开发者's 旋转动画 as last chosen, from the first turn. Not awaited, so the first frame doesn't wait on the host;
/// the controller logs a host that fails.
void applyTurnTakeover(OrientationController orientation, PlayerPrefs prefs) =>
    unawaited(orientation.setTurnTakeover(prefs.turnTakeover));

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
        theme: ThemeData(
          fontFamily: BiliFonts.family,
          fontFamilyFallback: BiliFonts.fallback,
          textTheme: BiliFonts.untracked,
        ),
        home: Scaffold(
          backgroundColor: BiliColors.pageGrey,
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(BiliMetrics.gutter),
                child: Builder(builder: (context) {
                  const title =
                      TextStyle(fontSize: BiliMetrics.titleText, color: BiliColors.text, fontWeight: FontWeight.w600);
                  const detail = TextStyle(fontSize: BiliMetrics.smallText, color: BiliColors.failure);
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('BiliFast 启动失败，请重启应用',
                          textAlign: TextAlign.center,
                          style: title,
                          strutStyle: BiliFonts.strutOf(context, title)),
                      const SizedBox(height: BiliMetrics.rowGap),
                      Text(error,
                          key: const ValueKey('launch-error'),
                          textAlign: TextAlign.center,
                          style: detail,
                          strutStyle: BiliFonts.strutOf(context, detail)),
                    ],
                  );
                }),
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
          fontFamilyFallback: BiliFonts.fallback,
          textTheme: BiliFonts.untracked,
          colorScheme: ColorScheme.fromSeed(seedColor: BiliColors.pink, primary: BiliColors.pink),
          scaffoldBackgroundColor: BiliColors.pageGrey,
          // iOS has no ripples; rows show their own press highlight.
          splashFactory: NoSplash.splashFactory,
        ),
        navigatorKey: services.navigator,
        navigatorObservers: [pageRoutes],
        // The official app keeps its sizes whatever iOS Text Size says, and every size here is measured off it.
        builder: (context, child) => AppScope(
          services: services,
          child: PhoneFrame.wrap(context, ReduceMotion(child: MediaQuery.withNoTextScaling(child: child!))),
        ),
        home: HomePage(
          initialLink: initialLink,
          developerPage: services.logs == null
              ? null
              : (context) => PlayerTestPage(
                    environment: services.environment,
                    startPlayback: services.playback.create,
                    releasePlayback: services.playback.release,
                    logs: services.logs,
                    speedTestHooks: appSpeedTestHooksOn(services.playback.engine),
                    appAuth: services.appAuth,
                  ),
        ),
      ),
    );
  }
}
