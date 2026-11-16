import 'dart:io' show Platform;

import 'ios/ios_device_events.dart';

/// iOS's own memory warnings (UIApplication.didReceiveMemoryWarningNotification), each with the process's
/// phys_footprint in MB, -1 when unknown. Flutter's `didHaveMemoryPressure` also comes on every trip to the
/// background, so it can't tell a real warning apart.
abstract interface class MemoryWarnings {
  /// The warnings of the platform the app runs on.
  static MemoryWarnings platform() => Platform.isIOS ? const IosMemoryWarnings() : const NoMemoryWarnings();

  Stream<int> get warnings;
}

/// DeviceChannel.swift's warnings.
final class IosMemoryWarnings implements MemoryWarnings {
  const IosMemoryWarnings();

  @override
  Stream<int> get warnings => IosDeviceEvents.shared.memoryWarnings;
}

/// The PC never warns.
final class NoMemoryWarnings implements MemoryWarnings {
  const NoMemoryWarnings();

  @override
  Stream<int> get warnings => const Stream.empty();
}
