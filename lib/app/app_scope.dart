import 'dart:async';

import 'package:flutter/widgets.dart';

import '../devtools/log_forwarder.dart';
import '../home/recent_store.dart';
import '../playback/playback_controller.dart';
import 'app_environment.dart';

/// The one player and engine, started at launch and shared by the video page and the developer page. It hears the
/// app come back to the foreground and the system run short of memory for whichever page is playing.
class AppPlayback with WidgetsBindingObserver {
  AppPlayback(Future<PlaybackController> Function() start) : controller = start() {
    controller.then((ready) => _ready = ready, onError: (Object _) {});
    WidgetsBinding.instance.addObserver(this);
  }

  final Future<PlaybackController> controller;
  PlaybackController? _ready;

  /// The controller once it has started.
  PlaybackController? get ready => _ready;

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
