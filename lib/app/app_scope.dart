import 'dart:async';

import 'package:flutter/widgets.dart';

import '../account/login_gate.dart';
import '../danmaku/block_rule_store.dart';
import '../danmaku/danmaku_settings_store.dart';
import '../device/player_device.dart';
import '../devtools/crash_log.dart';
import '../devtools/log_files.dart';
import '../devtools/log_forwarder.dart';
import '../home/recent_store.dart';
import '../playback/playback_controller.dart';
import '../settings/font_store.dart';
import '../video/page_api.dart';
import 'app_environment.dart';

/// The one player and engine, started at launch and shared by the video page and the developer page. It hears the
/// app come back to the foreground and the system run short of memory for whichever page is playing, and tells
/// [onResumed] of the first.
class AppPlayback with WidgetsBindingObserver {
  AppPlayback(this._start, {this.onResumed}) {
    unawaited(obtain().then((_) {}, onError: (Object _) {}));
    WidgetsBinding.instance.addObserver(this);
  }

  final Future<PlaybackController> Function() _start;
  final VoidCallback? onResumed;
  Future<PlaybackController>? _starting;
  PlaybackController? _ready;
  final List<(String, void Function(PlaybackController))> _pending = [];

  /// The controller once it has started.
  PlaybackController? get ready => _ready;

  /// Runs [action] on the started controller, or once a start succeeds, without starting one. A failed [action] is
  /// reported with [what] as its source.
  void whenStarted(String what, void Function(PlaybackController controller) action) {
    final ready = _ready;
    if (ready == null) {
      _pending.add((what, action));
    } else {
      _run(what, action, ready);
    }
  }

  static void _run(String what, void Function(PlaybackController) action, PlaybackController controller) {
    try {
      action(controller);
    } catch (error, stack) {
      CrashLog.report(error, stack, source: what);
    }
  }

  /// The shared controller; after a failed start, the next call starts it again (a page's 重试).
  Future<PlaybackController> obtain() {
    final starting = _starting;
    if (starting != null) return starting;
    final started = _start().then(
      (controller) {
        _ready = controller;
        final pending = List.of(_pending);
        _pending.clear();
        for (final (what, action) in pending) {
          _run(what, action, controller);
        }
        return controller;
      },
      onError: (Object error, StackTrace stack) {
        CrashLog.report(error, stack, source: 'player start');
        _starting = null;
        Error.throwWithStackTrace(error, stack);
      },
    );
    _starting = started;
    return started;
  }

  void dispose() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    onResumed?.call();
    unawaited(_ready?.appResumed());
  }

  @override
  void didHaveMemoryPressure() => _ready?.memoryPressure();
}

/// What every page reaches: the account and API client, the shared player, 最近打开, the phone's rotation and levels,
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
    this.logFiles = const NoLogFiles(),
    this.logs,
  }) : device = device ?? PlayerDevice.inWindow(),
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
