import 'dart:async';
import 'dart:io' show Platform;

import 'package:bili_core/devlog.dart';
import 'package:flutter/widgets.dart';

import '../device/ios/device_api.g.dart';
import '../device/network_monitor.dart';
import '../video/player_prefs.dart';

/// Whether a video may start by itself (自动播放设置, 172): the user's choices in [PlayerPrefs] against the network
/// the phone is on. The network is asked at launch, on every path change and on every return to the app, and kept,
/// so a list settling a scroll asks synchronously.
class AutoplayPolicy with WidgetsBindingObserver {
  AutoplayPolicy({required this._prefs, required Future<bool> Function() onCellular, Logger? logger})
    : _ask = onCellular,
      _logger = logger ?? Logger.shared;

  /// The phone's network, from NetworkMonitor.swift; the PC is always on Wi-Fi.
  factory AutoplayPolicy.platform({NetworkMonitor? monitor}) {
    if (!Platform.isIOS) return AutoplayPolicy.fixed();
    final host = DeviceHostApi();
    final policy = AutoplayPolicy(
      prefs: () => PlayerPrefs.shared,
      onCellular: () async => await host.network() == NativeNetwork.cellular,
    );
    policy._watch((monitor ?? NetworkMonitor.platform()).changes);
    return policy;
  }

  /// On Wi-Fi for good, reading [PlayerPrefs.shared]; tests and the PC.
  factory AutoplayPolicy.fixed({bool onCellular = false}) =>
      AutoplayPolicy(prefs: () => PlayerPrefs.shared, onCellular: () async => onCellular).._onCellular = onCellular;

  /// What the app reads; main puts the platform's here at launch.
  static AutoplayPolicy shared = AutoplayPolicy.fixed();

  final PlayerPrefs Function() _prefs;
  final Future<bool> Function() _ask;
  final Logger _logger;
  StreamSubscription<bool>? _changes;
  bool _onCellular = false;

  /// On mobile data as last asked.
  bool get onCellular => _onCellular;

  /// 详情页直接播放 and 流量网络下自动播放: a video page opened plays at once.
  bool get detail {
    final prefs = _prefs();
    return prefs.detailAutoplay && _networkAllows(prefs);
  }

  /// 首页自动播放: 推荐's big card plays when it settles on screen.
  bool get home => _allows(_prefs().homeAutoplay);

  /// 动态视频是否自动播放: 动态's video cards, and every other list's, play when they settle on screen.
  bool get list => _allows(_prefs().listAutoplay);

  bool _allows(AutoplayChoice choice) {
    final prefs = _prefs();
    return switch (choice) {
      AutoplayChoice.off => false,
      AutoplayChoice.wifiOnly => !_onCellular,
      AutoplayChoice.always => _networkAllows(prefs),
    };
  }

  bool _networkAllows(PlayerPrefs prefs) => prefs.cellularAutoplay || !_onCellular;

  /// Asks the network again.
  Future<void> refresh() async {
    try {
      final cellular = await _ask();
      if (cellular != _onCellular) _logger.info(LogCategory.app, 'autoplay network', {'cellular': cellular});
      _onCellular = cellular;
    } catch (error) {
      _logger.warn(LogCategory.app, 'autoplay network unknown', {'error': '${error.runtimeType}'});
    }
  }

  void _watch(Stream<bool> changes) {
    WidgetsBinding.instance.addObserver(this);
    _changes = changes.listen((_) => unawaited(refresh()));
    unawaited(refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  @visibleForTesting
  set onCellularForTest(bool value) => _onCellular = value;

  void dispose() {
    final changes = _changes;
    if (changes == null) return;
    unawaited(changes.cancel());
    WidgetsBinding.instance.removeObserver(this);
  }
}
