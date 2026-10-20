import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ios/device_api.g.dart';
import 'ios/ios_device_events.dart';

enum StatusNetwork { wifi, cellular, none }

/// What iOS's status bar would show, for the one landscape full screen draws in its place (04): the network and the
/// battery. The time is the page's own clock.
@immutable
final class DeviceStatus {
  const DeviceStatus({required this.battery, required this.charging, required this.network});

  /// A full battery on Wi-Fi: Windows, tests, and the phone before its first report.
  static const full = DeviceStatus(battery: 1, charging: false, network: StatusNetwork.wifi);

  /// 0 to 1; null when iOS can't tell.
  final double? battery;

  /// Charging, or full while on power.
  final bool charging;
  final StatusNetwork network;

  @override
  bool operator ==(Object other) =>
      other is DeviceStatus && other.battery == battery && other.charging == charging && other.network == network;

  @override
  int get hashCode => Object.hash(battery, charging, network);

  @override
  String toString() => 'DeviceStatus(battery: $battery, charging: $charging, network: ${network.name})';
}

/// The battery and network for the drawn status bar, watched only while landscape full screen shows it.
abstract interface class StatusBarFeed {
  ValueListenable<DeviceStatus> get status;

  /// On while the drawn status bar is on screen; the phone's battery monitoring follows it.
  void watch(bool on);
}

/// [DeviceStatus.full] for good: Windows and tests.
final class FixedStatusBarFeed implements StatusBarFeed {
  FixedStatusBarFeed([DeviceStatus status = DeviceStatus.full]) : status = ValueNotifier(status);

  @override
  final ValueNotifier<DeviceStatus> status;

  @override
  void watch(bool on) {}
}

/// DeviceChannel.swift's reports. Watches are counted, so two screens can watch at once.
final class IosStatusBarFeed implements StatusBarFeed {
  IosStatusBarFeed(this._api, IosDeviceEvents events) {
    _reports = events.statusReports.listen(_report);
  }

  final DeviceHostApi _api;
  late final StreamSubscription<DeviceStatusReport> _reports;
  int _watchers = 0;

  @override
  final ValueNotifier<DeviceStatus> status = ValueNotifier(DeviceStatus.full);

  @override
  void watch(bool on) {
    final before = _watchers;
    _watchers = on ? _watchers + 1 : (_watchers > 0 ? _watchers - 1 : 0);
    if ((before == 0) != (_watchers == 0)) unawaited(_api.setStatusEvents(_watchers > 0));
  }

  void _report(DeviceStatusReport report) => status.value = DeviceStatus(
    battery: report.battery < 0 ? null : report.battery.clamp(0, 1).toDouble(),
    charging: report.charging,
    network: switch (report.network) {
      NativeNetwork.wifi => StatusNetwork.wifi,
      NativeNetwork.cellular => StatusNetwork.cellular,
      NativeNetwork.none => StatusNetwork.none,
    },
  );

  void dispose() => unawaited(_reports.cancel());
}
