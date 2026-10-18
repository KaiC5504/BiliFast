import 'dart:async';

import 'package:flutter/widgets.dart';

import '../devtools/crash_log.dart';
import '../devtools/log_forwarder.dart';
import '../home/recent_store.dart';
import '../playback/playback_controller.dart';
import 'app_environment.dart';

/// The one player and engine, started at launch and shared by the video page and the developer page. It hears the
/// app come back to the foreground and the system run short of memory for whichever page is playing.
class AppPlayback with WidgetsBindingObserver {
  AppPlayback(this._start) {
    unawaited(obtain().then((_) {}, onError: (Object _) {}));
    WidgetsBinding.instance.addObserver(this);
  }

  final Future<PlaybackController> Function() _start;
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
    if (state == AppLifecycleState.resumed) unawaited(_ready?.appResumed());
  }

  @override
  void didHaveMemoryPressure() => _ready?.memoryPressure();
}

/// What every page reaches: the account and API client, the shared player, 最近打开, and the log forwarder in dev
/// builds (null otherwise).
class AppServices {
  const AppServices({required this.environment, required this.playback, required this.recents, this.logs});

  final AppEnvironment environment;
  final AppPlayback playback;
  final RecentStore recents;
  final LogForwarder? logs;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope oldWidget) => !identical(services, oldWidget.services);
}
