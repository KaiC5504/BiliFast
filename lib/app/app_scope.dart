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

  /// The controller once it has started.
  PlaybackController? get ready => _ready;

  /// The shared controller; after a failed start, the next call starts it again (a page's 重试).
  Future<PlaybackController> obtain() {
    final starting = _starting;
    if (starting != null) return starting;
    final started = _start().then(
      (controller) => _ready = controller,
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
