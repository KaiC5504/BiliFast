import 'dart:async';
import 'dart:math';

import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show appBuildName, appBuildNumber;

import 'sideload_store.dart';

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
  SideloadModel.none()
    : this(
        source: const _Unsigned(),
        feed: const _NoReleases(),
        reminders: const _NoReminders(),
        store: SideloadStore.memory(),
      );

  /// [version] and [build] are this build's own; with no version known, no release counts as newer.
  SideloadModel({
    required this._source,
    required this._feed,
    required this._reminders,
    required this._store,
    this._version = appBuildName,
    String? build = appBuildNumber,
    DateTime Function()? now,
    Logger? logger,
  }) : _build = build == null ? null : int.tryParse(build),
       _now = now ?? DateTime.now,
       _logger = logger ?? Logger.shared;

  static const reminderTitle = 'BiliFast 签名明天到期';
  static const reminderBody = '记得在 SideStore 或电脑上重新签名，过期后会打不开。已经续签过可以忽略。';

  /// How long before the expiry the reminder comes.
  static const reminderLead = Duration(hours: 24);

  final SignatureSource _source;
  final ReleaseFeed _feed;
  final ReminderHost _reminders;
  final SideloadStore _store;
  final String? _version;
  final int? _build;
  final DateTime Function() _now;
  final Logger _logger;

  SignatureInfo? _signature;
  ReleaseInfo? _latest;
  Future<void>? _starting;
  Future<void>? _asking;
  bool _disposed = false;

  bool get sideloaded => signature != null;

  SignatureInfo? get signature => _signature;

  /// Whole days until [SignatureInfo.expires], never below 0; null when not sideloaded.
  int? get daysLeft {
    final expires = _signature?.expires;
    if (expires == null) return null;
    final days = expires.difference(_now()).inDays;
    return days < 0 ? 0 : days;
  }

  /// The newest release when it is newer than this build.
  ReleaseInfo? get newer {
    final latest = _latest;
    return latest != null && isNewer(latest, version: _version, build: _build) ? latest : null;
  }

  bool get checking => _asking != null;

  /// Whether the 到期前一天提醒 is on (the user said 好 and iOS allowed it).
  bool get reminderOn => sideloaded && _store.reminderOn;

  /// Reads the signature, schedules the reminder if on, then checks for a release once. Never loops.
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    await _store.load();
    try {
      _signature = await _source.read();
    } catch (error) {
      _logger.warn(LogCategory.app, 'sideload signature unreadable', {'error': '${error.runtimeType}'});
    }
    if (_signature == null) {
      _logger.info(LogCategory.app, 'sideload', {'sideloaded': false});
      return;
    }
    _changed();
    // Every re-sign moves the expiry, so the reminder is set again from this launch's profile.
    if (_store.reminderOn) await _scheduleReminder();
    await _ask('launch');
  }

  /// 设置's 检查更新: one more check, unless one is running.
  Future<void> checkNow() async {
    if (!sideloaded) return;
    await _ask('check');
  }

  Future<void> _ask(String via) async {
    if (_asking case final running?) return running;
    final done = Completer<void>();
    _asking = done.future;
    _changed();
    ReleaseInfo? release;
    try {
      release = await _feed.latest();
    } catch (error) {
      _logger.warn(LogCategory.app, 'release check failed', {'reason': '${error.runtimeType}'});
    }
    // A failed check keeps what an earlier one found.
    if (release != null) _latest = release;
    _asking = null;
    done.complete();
    _logger.info(LogCategory.app, 'sideload', {
      'daysLeft': ?daysLeft,
      'newer': newer != null,
      'answered': release != null,
      'via': via,
    });
    _changed();
  }

  /// The first launch of a sideloaded install, until the user answers the reminder question.
  bool get shouldAskReminder => sideloaded && !_store.reminderAnswered;

  /// The user's answer: on yes, iOS's prompt and the reminder for the day before expiry; either way never asked again.
  Future<void> answerReminder(bool yes) async {
    if (!shouldAskReminder) return;
    _store.reminderAnswered = true;
    _changed();
    if (yes) await _turnOn();
  }

  /// 设置's 到期提醒 switch.
  Future<void> setReminder(bool on) async {
    if (!sideloaded || on == reminderOn) return;
    _store.reminderAnswered = true;
    if (on) return _turnOn();
    _store.reminderOn = false;
    _changed();
    try {
      await _reminders.cancel();
    } catch (error) {
      _hostFailed('cancel', error);
    }
  }

  Future<void> _turnOn() async {
    var granted = false;
    try {
      granted = await _reminders.requestPermission();
    } catch (error) {
      _hostFailed('permission', error);
    }
    _logger.info(LogCategory.app, 'sideload reminder', {'granted': granted});
    _store.reminderOn = granted;
    _changed();
    if (granted) await _scheduleReminder();
  }

  /// A day before the expiry; nothing when that moment has passed.
  Future<void> _scheduleReminder() async {
    final expires = _signature?.expires;
    if (expires == null) return;
    final at = expires.subtract(reminderLead);
    if (!at.isAfter(_now())) return;
    try {
      await _reminders.schedule(at, reminderTitle, reminderBody);
    } catch (error) {
      _hostFailed('schedule', error);
    }
  }

  void _hostFailed(String call, Object error) =>
      _logger.warn(LogCategory.app, 'sideload reminder failed', {'call': call, 'error': '${error.runtimeType}'});

  /// Two days or less left, and not warned yet today.
  bool get shouldWarnExpiry {
    final days = daysLeft;
    return days != null && days <= 2 && _store.warnedOn != _today();
  }

  void expiryWarned() {
    if (!sideloaded) return;
    _store.warnedOn = _today();
    _changed();
  }

  /// [newer] exists and its alert hasn't been dismissed for that release.
  bool get shouldAnnounceRelease {
    final release = newer;
    return release != null && _store.announced != _key(release);
  }

  void releaseAnnounced() {
    final release = newer;
    if (release == null) return;
    _store.announced = _key(release);
    _changed();
  }

  /// Whether [release] is above [version] and [build]: the version's dotted numbers first, then the build. An unknown
  /// or unreadable version is never below a release; an unknown build is below only a higher version.
  static bool isNewer(ReleaseInfo release, {required String? version, required int? build}) {
    final current = version == null ? null : _numbers(version);
    final offered = _numbers(release.version);
    if (current == null || offered == null) return false;
    for (var i = 0; i < max(current.length, offered.length); i++) {
      final a = i < offered.length ? offered[i] : 0;
      final b = i < current.length ? current[i] : 0;
      if (a != b) return a > b;
    }
    return build != null && release.build > build;
  }

  static List<int>? _numbers(String version) {
    final numbers = <int>[];
    for (final part in version.trim().split('.')) {
      final number = int.tryParse(part);
      if (number == null || number < 0) return null;
      numbers.add(number);
    }
    return numbers;
  }

  static String _key(ReleaseInfo release) => '${release.version}-${release.build}';

  String _today() {
    final day = _now().toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${day.year}-${two(day.month)}-${two(day.day)}';
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final class _Unsigned implements SignatureSource {
  const _Unsigned();

  @override
  Future<SignatureInfo?> read() async => null;
}

final class _NoReleases implements ReleaseFeed {
  const _NoReleases();

  @override
  Future<ReleaseInfo?> latest() async => null;
}

final class _NoReminders implements ReminderHost {
  const _NoReminders();

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> schedule(DateTime at, String title, String body) async {}

  @override
  Future<void> cancel() async {}
}
