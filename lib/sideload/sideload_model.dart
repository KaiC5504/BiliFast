import 'package:flutter/foundation.dart';

/// A sideloaded install's signature, read from the profile inside the app (`embedded.mobileprovision`). TestFlight
/// and App Store installs carry none, so they never have one.
@immutable
class SignatureInfo {
  const SignatureInfo({required this.expires});

  final DateTime expires;
}

/// The newest published release, as GitHub names it (`v1.3.0-8`).
@immutable
class ReleaseInfo {
  const ReleaseInfo({required this.version, required this.build, required this.page});

  final String version;
  final int build;
  final Uri page;
}

/// Reads this install's signature; null when it isn't sideloaded or the profile can't be read.
abstract interface class SignatureSource {
  Future<SignatureInfo?> read();
}

/// Asks for the newest release; null on any failure. One call per ask, never retried.
abstract interface class ReleaseFeed {
  Future<ReleaseInfo?> latest();
}

/// The day-before reminder, through DeviceHostApi on iOS.
abstract interface class ReminderHost {
  Future<bool> requestPermission();

  Future<void> schedule(DateTime at, String title, String body);

  Future<void> cancel();
}

/// What 设置's 签名 section and the launch alerts show for a sideloaded install. Not sideloaded (TestFlight, the
/// App Store, Windows without `--fake-sideload`), it stays empty and shows nothing.
class SideloadModel extends ChangeNotifier {
  /// An install that isn't sideloaded: everything empty, nothing asked.
  SideloadModel.none();

  bool get sideloaded => signature != null;

  SignatureInfo? get signature => null;

  /// Whole days until [SignatureInfo.expires], never below 0; null when not sideloaded.
  int? get daysLeft => null;

  /// The newest release when it is newer than this build.
  ReleaseInfo? get newer => null;

  bool get checking => false;

  /// Whether the 到期前一天提醒 is on (the user said 好 and iOS allowed it).
  bool get reminderOn => false;

  /// Reads the signature, schedules the reminder if on, then checks for a release once. Never loops.
  Future<void> start() async {}

  /// 设置's 检查更新: one more check, unless one is running.
  Future<void> checkNow() async {}

  /// The first launch of a sideloaded install, until the user answers the reminder question.
  bool get shouldAskReminder => false;

  /// The user's answer: on yes, iOS's prompt and the reminder for the day before expiry; either way never asked again.
  Future<void> answerReminder(bool yes) async {}

  /// 设置's 到期提醒 switch.
  Future<void> setReminder(bool on) async {}

  /// Two days or less left, and not warned yet today.
  bool get shouldWarnExpiry => false;

  void expiryWarned() {}

  /// [newer] exists and its alert hasn't been dismissed for that release.
  bool get shouldAnnounceRelease => false;

  void releaseAnnounced() {}
}
