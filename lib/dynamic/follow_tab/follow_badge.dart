import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/widgets.dart';

import '../../app/app_environment.dart';
import '../../search/results/video_row.dart' show searchLogReason;
import '../dynamic_api.dart';

/// The newest post 关注's 全部 showed each account, kept on the phone (`follow_badge.json`): what [FollowBadge]
/// counts from, across launches.
class FollowBaselines {
  FollowBaselines._(this._path, this._baselines, this._logger);

  /// Kept in memory only, for tests and for platforms without a support folder.
  factory FollowBaselines.memory({Logger? logger}) => FollowBaselines._(null, {}, logger ?? Logger.shared);

  /// [path] null keeps it in memory. A file that can't be read is set aside as `.bad` and starts empty; an entry of
  /// the wrong type is skipped, logged by its key.
  static Future<FollowBaselines> load(String? path, {Logger? logger}) async {
    final log = logger ?? Logger.shared;
    if (path == null) return FollowBaselines._(null, {}, log);
    final file = File(path);
    if (!await file.exists()) return FollowBaselines._(path, {}, log);
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, Object?>) throw const FormatException('not an object');
      final baselines = <int, String>{};
      for (final MapEntry(:key, :value) in json.entries) {
        final mid = int.tryParse(key);
        if (mid != null && value is String && value.isNotEmpty) {
          baselines[mid] = value;
        } else {
          log.warn(LogCategory.app, 'follow baseline ignored', {'key': mid == null ? 'not a uid' : Redactor.mid(mid)});
        }
      }
      return FollowBaselines._(path, baselines, log);
    } catch (error) {
      log.warn(LogCategory.app, 'follow baselines unreadable, starting empty', {'error': _reason(error)});
    }
    try {
      await file.rename('$path.bad');
    } catch (error) {
      log.warn(LogCategory.app, 'follow baselines not set aside', {'error': _reason(error)});
    }
    return FollowBaselines._(path, {}, log);
  }

  final String? _path;
  final Logger _logger;
  final Map<int, String> _baselines;
  Future<void> _writing = Future.value();

  String? of(int mid) => _baselines[mid];

  /// Keeps [baseline] for [mid] and saves it; throws when the write fails (logged), the baseline kept in memory all
  /// the same.
  Future<void> set(int mid, String baseline) {
    if (_baselines[mid] == baseline) return Future.value();
    _baselines[mid] = baseline;
    final path = _path;
    if (path == null) return Future.value();
    final text = jsonEncode({for (final MapEntry(:key, :value) in _baselines.entries) '$key': value});
    // One write after another, so an older state never lands last; a failed one doesn't stop the next.
    final write = _writing.then((_) => _write(path, text));
    _writing = write.then((_) {}, onError: (Object _) {});
    return write;
  }

  Future<void> _write(String path, String text) async {
    try {
      await File(path).parent.create(recursive: true);
      final temporary = File('$path.tmp');
      await temporary.writeAsString(text, flush: true);
      await temporary.rename(path);
    } catch (error) {
      _logger.warn(LogCategory.app, 'follow baselines not saved', {'error': _reason(error)});
      rethrow;
    }
  }

  /// The error without the text that failed: a FormatException's toString quotes it.
  static String _reason(Object error) => switch (error) {
    FormatException(:final message) => message,
    FileSystemException(:final message, :final osError) => osError == null ? message : '$message: $osError',
    _ => '${error.runtimeType}',
  };

  /// Waits for the writes made so far; for tests.
  Future<void> settle() => _writing;
}

/// 关注's red count on the bottom bar (238), one for the app ([AppServices.followBadge]): posts of every kind since
/// the newest one 关注's 全部 showed this account. No count until 全部 has shown a first page, and none logged out.
///
/// A logout or an expired login clears the count, and an answer still out for the account before is dropped.
class FollowBadge extends ChangeNotifier {
  FollowBadge({
    required this.api,
    required this.environment,
    FollowBaselines? baselines,
    this.resumeGap = const Duration(minutes: 1),
    DateTime Function()? now,
    Logger? logger,
  }) : _baselines = baselines ?? FollowBaselines.memory(),
       _now = now ?? DateTime.now,
       _logger = logger ?? Logger.shared,
       _account = environment.account {
    environment.addListener(_accountChanged);
    environment.logins.addListener(_loginCompleted);
  }

  final DynamicApi api;
  final AppEnvironment environment;
  final FollowBaselines _baselines;
  final DateTime Function() _now;
  final Logger _logger;

  /// How long after the count was last asked a return to the app asks it again.
  final Duration resumeGap;

  /// The last count, with the account it was asked for: between a login's account check and its count the
  /// environment can already hold the next account.
  ({int mid, int count})? _answer;

  /// The account as it last settled; unknown only until the launch's check answers.
  Account _account;

  /// Bumped by every login and logout, [seen] and [clear], so an answer asked before is dropped.
  int _generation = 0;

  bool _started = false;
  bool _disposed = false;
  _Foreground? _foreground;

  /// The turn to logged in has asked the count already, so the login count that follows asks nothing more.
  bool _loginCounted = false;

  Future<void>? _call;
  DateTime? _lastAsked;

  /// The number on 关注's place; 0 logged out or before a baseline.
  int get count {
    final mid = environment.mid;
    final answer = _answer;
    if (!_loggedIn || mid == null || answer == null || answer.mid != mid) return 0;
    return answer.count;
  }

  bool get _loggedIn => environment.account is LoggedIn;

  /// What the account's count is asked from; null logged out or before 全部 has shown it a first page.
  String? get _baseline {
    final mid = environment.mid;
    return _loggedIn && mid != null ? _baselines.of(mid) : null;
  }

  /// Starts the count's upkeep: once at launch, on a return to the app at most once per [resumeGap], on each login.
  /// Called by the shell once; again does nothing. An account still unknown is asked for once it reads logged in.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    final foreground = _foreground = _Foreground(() => unawaited(refresh()));
    WidgetsBinding.instance.addObserver(foreground);
    unawaited(_ask());
  }

  /// Asks the count again; [force] skips the [resumeGap] limit. A call already out answers for this one.
  Future<void> refresh({bool force = false}) {
    if (_disposed) return Future.value();
    if (_call case final running?) return running;
    final last = _lastAsked;
    if (!force && last != null && _now().difference(last) < resumeGap) return Future.value();
    return _ask();
  }

  Future<void> _ask() {
    if (_call case final running?) return running;
    final mid = environment.mid;
    final baseline = _baseline;
    if (_disposed || mid == null || baseline == null) return Future.value();
    _lastAsked = _now();
    late final Future<void> call;
    call = _fetch(_generation, mid, baseline).whenComplete(() {
      if (identical(_call, call)) _call = null;
    });
    return _call = call;
  }

  Future<void> _fetch(int generation, int mid, String baseline) async {
    final int answer;
    try {
      answer = await api.updateCount(baseline);
    } catch (error) {
      if (!_current(generation)) return;
      _logger.warn(LogCategory.api, 'follow badge failed', {'error': searchLogReason(error)});
      // The login is gone on Bilibili's side, whatever the app still holds: the badge mustn't keep its number.
      if (error is BiliError && error.needsLogin) _show(null);
      return;
    }
    if (!_current(generation)) return;
    _logger.info(LogCategory.api, 'follow badge', {'count': answer});
    _show((mid: mid, count: answer));
  }

  void _show(({int mid, int count})? answer) {
    final before = count;
    _answer = answer;
    if (count != before) _notify();
  }

  /// 全部's first page landed with [baseline]: the count starts over from it.
  void seen(String baseline) {
    final mid = environment.mid;
    if (_disposed || baseline.isEmpty || !_loggedIn || mid == null) return;
    _generation++;
    // The store logs a failed save; the baseline holds for this run all the same.
    unawaited(_baselines.set(mid, baseline).then((_) {}, onError: (Object _) {}));
    _answer = (mid: mid, count: 0);
    _notify();
  }

  /// 关注 was opened over a count: it goes at once. An answer still out can't bring it back.
  void clear() {
    if (_disposed) return;
    _generation++;
    if (_answer case final answer?) _show((mid: answer.mid, count: 0));
  }

  void _accountChanged() {
    final now = environment.account;
    if (now is AccountUnknown) {
      // didLogin passes through here on its way to logged in; the login count after it then knows whether the turn
      // to logged in has asked.
      _loginCounted = false;
      _notify();
      return;
    }
    final was = _account;
    _account = now;
    if (now is! LoggedIn) {
      _clear();
      _notify();
      return;
    }
    if (was is! LoggedIn) {
      _loginCounted = true;
      if (_started) unawaited(_ask());
    }
    _notify();
  }

  /// A login over an account that already read logged in leaves the account where it was, and may be another one.
  void _loginCompleted() {
    if (_loginCounted) {
      _loginCounted = false;
      return;
    }
    if (!_loggedIn) return;
    _clear();
    if (_started) unawaited(_ask());
    _notify();
  }

  void _clear() {
    _generation++;
    _answer = null;
    _call = null;
    _lastAsked = null;
  }

  bool _current(int generation) => generation == _generation && !_disposed;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    environment.removeListener(_accountChanged);
    environment.logins.removeListener(_loginCompleted);
    if (_foreground case final foreground?) WidgetsBinding.instance.removeObserver(foreground);
    super.dispose();
  }
}

/// A return to the app.
class _Foreground with WidgetsBindingObserver {
  _Foreground(this._resumed);

  final VoidCallback _resumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _resumed();
  }
}
