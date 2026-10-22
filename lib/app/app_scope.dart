import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart' show NodeMode;
import 'package:flutter/widgets.dart';

import '../account/app_auth.dart';
import '../account/login_gate.dart';
import '../danmaku/block_rule_store.dart';
import '../danmaku/danmaku_settings_store.dart';
import '../device/network_monitor.dart';
import '../device/player_device.dart';
import '../devtools/crash_log.dart';
import '../devtools/log_files.dart';
import '../devtools/log_forwarder.dart';
import '../favourites/favourites_api.dart';
import '../home/recent_store.dart';
import '../me/me_api.dart';
import '../playback/codec_memory.dart';
import '../playback/playback_controller.dart';
import '../playback/shared_engine.dart';
import '../search/search_api.dart';
import '../search/search_history_store.dart';
import '../settings/font_store.dart';
import '../skin/skin_api.dart';
import '../skin/skin_model.dart';
import '../space/follow_book.dart';
import '../space/space_api.dart';
import '../video/page_api.dart';
import '../video/pip_keeper.dart';
import '../watch_later/watch_later_api.dart';
import 'app_environment.dart';

/// Hands each page a controller and player of its own (BiliNative's one AVPlayer per page), all on one [SharedEngine]
/// and [CodecMemory], and passes on the app's foreground, memory and network events.
class AppPlayback with WidgetsBindingObserver {
  AppPlayback(
    this._start, {
    this.onResumed,
    this.engine,
    this.codecMemory,
    NetworkMonitor? network,
    this.muted = false,
    Logger? logger,
  }) : _logger = logger ?? Logger.shared {
    WidgetsBinding.instance.addObserver(this);
    // At launch, so the first page doesn't wait for the isolate and its server; a failed start is tried again by the
    // first page.
    unawaited(engine?.current().then((_) {}, onError: (Object error, StackTrace stack) {
      CrashLog.report(error, stack, source: 'engine start', logger: _logger);
    }));
    _network = (network ?? NetworkMonitor.platform()).changes.listen(_networkChanged);
  }

  final Future<PlaybackController> Function() _start;
  final VoidCallback? onResumed;

  /// What the controllers [_start] makes play through; null in tests whose controllers bring their own engines.
  final SharedEngine? engine;

  /// The codecs this phone's player refused, one memory for every page.
  final CodecMemory? codecMemory;

  /// `--mute`: every player made here starts muted, so checks on the PC play silently.
  final bool muted;
  final Logger _logger;
  late final StreamSubscription<bool> _network;

  final Set<PlaybackController> _pages = {};

  /// A controller of its own for one video page (BiliNative's one AVPlayer per page), on the shared engine.
  Future<PlaybackController> create() async {
    final PlaybackController controller;
    try {
      controller = await _start();
    } catch (error, stack) {
      CrashLog.report(error, stack, source: 'player start', logger: _logger);
      rethrow;
    }
    _pages.add(controller);
    await _muteIfAsked(controller);
    _logger.info(LogCategory.player, 'player created', {'live': live});
    return controller;
  }

  /// The page is done with [controller]: it stops and everything it holds is freed.
  void release(PlaybackController controller) {
    if (!_pages.remove(controller)) return;
    controller.dispose();
    _logger.info(LogCategory.player, 'player released', {'live': live});
  }

  /// Page controllers made and not yet released, for the leak checks.
  int get live => _pages.length;

  /// A player that can't be muted isn't handed out: under `--mute` it would play out loud.
  Future<void> _muteIfAsked(PlaybackController controller) async {
    if (!muted) return;
    try {
      await controller.player.setMuted(true);
    } catch (error) {
      _logger.error(LogCategory.player, 'mute failed', {'error': '$error'});
      release(controller);
      rethrow;
    }
  }

  /// 设置's CDN 节点: the engine running now and any that replaces it. Playbacks already prepared keep their nodes.
  void setNodeMode(NodeMode mode) => engine?.setNodeMode(mode);

  /// 设置's 重置编码记忆: codecs the player refused are tried again, whether a page is open or not.
  void resetCodecMemory() => codecMemory?.reset();

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_network.cancel());
  }

  /// The controllers' probes of the server go to the shared engine as one ([SharedEngine]): when it had to restart,
  /// each controller with a prepared source prepares it again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    onResumed?.call();
    for (final controller in List.of(_pages)) {
      unawaited(controller.appResumed());
    }
  }

  /// The shared engine trims its prefetch once; each controller logs and marks the warning.
  @override
  void didHaveMemoryPressure() {
    engine?.dropCache();
    for (final controller in List.of(_pages)) {
      controller.memoryPressure();
    }
  }

  void _networkChanged(bool interfaceChanged) {
    _logger.info(LogCategory.player, 'network changed', {'interfaceChanged': interfaceChanged, 'live': live});
    unawaited(engine?.networkChanged(interfaceChanged: interfaceChanged));
  }
}

/// What every page reaches: the account and API client, the official API's token, the players, 最近打开, the phone's
/// rotation and levels, the font, the page body's, 搜索's, UP主空间's, 我的收藏's, 稍后再看's and 我的's calls, 关注 changes,
/// 搜索历史, the login page, the log kept on the phone, and the log forwarder in dev builds (null otherwise).
class AppServices {
  AppServices({
    required this.environment,
    required this.playback,
    required this.recents,
    PlayerDevice? device,
    FontStore? fonts,
    PageApi? pageApi,
    this._searchApi,
    this._spaceApi,
    this._favouritesApi,
    this._watchLaterApi,
    this._meApi,
    this._skinApi,
    this.skinFolder,
    AppAuth? appAuth,
    GlobalKey<NavigatorState>? navigator,
    SearchHistoryStore? searchHistory,
    DanmakuSettingsStore? danmakuSettings,
    BlockRuleStore? blockRules,
    LoginGate? loginGate,
    PipKeeper? pipKeeper,
    this.logFiles = const NoLogFiles(),
    this.logs,
  }) : appAuth = appAuth ?? NoAppAuth(),
       navigator = navigator ?? GlobalKey<NavigatorState>(),
       device = device ?? PlayerDevice.inWindow(),
       pipKeeper = pipKeeper ?? PipKeeper(),
       loginGate = loginGate ?? LoginPageGate(environment),
       fonts = fonts ?? FontStore.memory(),
       pageApi = pageApi ?? ClientPageApi(environment.client),
       searchHistory = searchHistory ?? SearchHistoryStore.memory(),
       danmakuSettings = danmakuSettings ?? DanmakuSettingsStore.memory() {
    this.blockRules =
        blockRules ?? BlockRuleStore(api: this.pageApi, isLoggedIn: () => environment.account is LoggedIn);
    _account = environment.account;
    environment.addListener(_accountChanged);
    environment.logins.addListener(_loggedIn);
  }

  late Account _account;

  /// Every login fetches the account's 屏蔽词 at once (Swift's didLogin); the launch's check is left to the first
  /// page, which refreshes them itself.
  void _loggedIn() => unawaited(blockRules.refresh(force: true));

  /// A logout, or a login Bilibili no longer accepts, drops the old account's 屏蔽词.
  void _accountChanged() {
    final now = environment.account;
    // didLogin passes through unknown on its way to logged in.
    if (now is AccountUnknown) return;
    final was = _account;
    _account = now;
    if (was is LoggedIn && (now is LoggedOut || now is LoginExpired)) unawaited(blockRules.refresh());
  }

  void dispose() {
    appAuth.dispose();
    environment.removeListener(_accountChanged);
    environment.logins.removeListener(_loggedIn);
  }

  final AppEnvironment environment;
  final AppPlayback playback;
  final RecentStore recents;
  final PlayerDevice device;
  final FontStore fonts;
  final PageApi pageApi;
  final SearchApi? _searchApi;

  /// Made on first use, so tests whose environment has no client never ask for one.
  late final SearchApi searchApi = _searchApi ?? ClientSearchApi(environment.client);

  final SpaceApi? _spaceApi;

  /// UP主空间's calls, made on first use like [searchApi].
  late final SpaceApi spaceApi = _spaceApi ?? ClientSpaceApi(environment.client);

  final FavouritesApi? _favouritesApi;

  /// 我的收藏's calls, made on first use like [searchApi].
  late final FavouritesApi favouritesApi = _favouritesApi ?? ClientFavouritesApi(environment.client);

  final WatchLaterApi? _watchLaterApi;

  /// 稍后再看's calls, made on first use like [searchApi].
  late final WatchLaterApi watchLaterApi = _watchLaterApi ?? ClientWatchLaterApi(environment.client);

  final MeApi? _meApi;

  /// 我的's calls, made on first use like [searchApi].
  late final MeApi meApi = _meApi ?? ClientMeApi(environment.client);

  final SkinApi? _skinApi;

  /// The equipped 装扮's calls, made on first use like [searchApi].
  late final SkinApi skinApi = _skinApi ?? ClientSkinApi(environment.client);

  /// Where skin packages are unpacked (the support folder's `skins`); null keeps nothing across launches.
  final String? skinFolder;

  /// The equipped 装扮, null for the stock look. Made on first use and started by `main`.
  late final SkinModel skin = SkinModel(api: skinApi, environment: environment, folder: skinFolder);

  /// The official API's login token.
  final AppAuth appAuth;

  /// 关注 changes, so every page showing an uploader agrees.
  final follows = FollowBook();

  /// 搜索历史, kept on the device, not on the account.
  final SearchHistoryStore searchHistory;
  final DanmakuSettingsStore danmakuSettings;

  /// The account's 弹幕屏蔽词, shared by every page.
  late final BlockRuleStore blockRules;

  /// Where every logged-out action goes.
  final LoginGate loginGate;

  /// The app's navigator, for pages pushed from outside a page's context (the small window's restore, the launch's
  /// confirm of the app token).
  final GlobalKey<NavigatorState> navigator;

  /// The closed page the small window is playing, if any.
  final PipKeeper pipKeeper;

  final LogFiles logFiles;
  final LogForwarder? logs;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope oldWidget) => !identical(services, oldWidget.services);
}
