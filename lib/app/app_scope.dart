import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart' show NodeMode;
import 'package:flutter/widgets.dart';

import '../account/login_gate.dart';
import '../danmaku/block_rule_store.dart';
import '../danmaku/danmaku_settings_store.dart';
import '../device/network_monitor.dart';
import '../device/player_device.dart';
import '../devtools/crash_log.dart';
import '../devtools/log_files.dart';
import '../devtools/log_forwarder.dart';
import '../home/recent_store.dart';
import '../playback/codec_memory.dart';
import '../playback/playback_controller.dart';
import '../playback/shared_engine.dart';
import '../settings/font_store.dart';
import '../video/page_api.dart';
import '../video/pip_keeper.dart';
import 'app_environment.dart';

/// Every video page's player: each page gets a controller and player of its own (BiliNative's one AVPlayer per page),
/// all playing through one [SharedEngine] with one [CodecMemory]. It hears the app come back to the foreground, the
/// system run short of memory and the network path change, tells the engine once and each live controller, and
/// tells [onResumed] of the first.
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
  Future<PlaybackController>? _starting;
  PlaybackController? _ready;

  /// The controller [obtain] started, once it has.
  PlaybackController? get ready => _ready;

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

  /// The one controller pages shared before each made its own: started on first use and never released. After a
  /// failed start, the next call starts it again (a page's 重试).
  Future<PlaybackController> obtain() {
    final starting = _starting;
    if (starting != null) return starting;
    final started = _start().then(
      (controller) async {
        _ready = controller;
        await _muteIfAsked(controller);
        return controller;
      },
      onError: (Object error, StackTrace stack) {
        CrashLog.report(error, stack, source: 'player start', logger: _logger);
        _starting = null;
        Error.throwWithStackTrace(error, stack);
      },
    );
    _starting = started;
    return started;
  }

  Future<void> _muteIfAsked(PlaybackController controller) async {
    if (!muted) return;
    try {
      await controller.player.setMuted(true);
    } catch (error) {
      _logger.warn(LogCategory.player, 'mute failed', {'error': '$error'});
    }
  }

  /// 设置's CDN 节点: the engine running now and any that replaces it. Playbacks already prepared keep their nodes.
  void setNodeMode(NodeMode mode) => engine?.setNodeMode(mode);

  /// 设置's 重置编码记忆: codecs the player refused are tried again, whether a page is open or not.
  void resetCodecMemory() => codecMemory?.reset();

  Set<PlaybackController> get _controllers => {?_ready, ..._pages};

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
    for (final controller in _controllers) {
      unawaited(controller.appResumed());
    }
  }

  /// The shared engine trims its prefetch once; each controller logs and marks the warning.
  @override
  void didHaveMemoryPressure() {
    engine?.dropCache();
    for (final controller in _controllers) {
      controller.memoryPressure();
    }
  }

  void _networkChanged(bool interfaceChanged) {
    _logger.info(LogCategory.player, 'network changed', {'interfaceChanged': interfaceChanged, 'live': live});
    unawaited(engine?.networkChanged(interfaceChanged: interfaceChanged));
  }
}

/// What every page reaches: the account and API client, the players, 最近打开, the phone's rotation and levels,
/// the font, the page body's calls, the login page, the log kept on the phone, and the log forwarder in dev builds
/// (null otherwise).
class AppServices {
  AppServices({
    required this.environment,
    required this.playback,
    required this.recents,
    PlayerDevice? device,
    FontStore? fonts,
    PageApi? pageApi,
    DanmakuSettingsStore? danmakuSettings,
    BlockRuleStore? blockRules,
    LoginGate? loginGate,
    PipKeeper? pipKeeper,
    this.logFiles = const NoLogFiles(),
    this.logs,
  }) : device = device ?? PlayerDevice.inWindow(),
       pipKeeper = pipKeeper ?? PipKeeper(),
       loginGate = loginGate ?? LoginPageGate(environment),
       fonts = fonts ?? FontStore.memory(),
       pageApi = pageApi ?? ClientPageApi(environment.client),
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
    environment.removeListener(_accountChanged);
    environment.logins.removeListener(_loggedIn);
  }

  final AppEnvironment environment;
  final AppPlayback playback;
  final RecentStore recents;
  final PlayerDevice device;
  final FontStore fonts;
  final PageApi pageApi;
  final DanmakuSettingsStore danmakuSettings;

  /// The account's 弹幕屏蔽词, shared by every page.
  late final BlockRuleStore blockRules;

  /// Where every logged-out action goes.
  final LoginGate loginGate;

  /// The app's navigator, for pages pushed from outside a page's context (the small window's restore).
  final navigator = GlobalKey<NavigatorState>();

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
