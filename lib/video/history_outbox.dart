import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;

import '../app/app_environment.dart';
import '../device/network_monitor.dart';
import 'watch_reporter.dart';

/// `BiliClient.heartbeat`'s shape.
typedef SendHeartbeat = Future<void> Function({required String bvid, required int cid, required int playedTime});

/// The last watch report of one part that got no answer: the seconds played, or -1 for finished.
@immutable
final class PendingReport {
  const PendingReport({required this.bvid, required this.cid, required this.played, required this.at});

  factory PendingReport.fromJson(Map<String, Object?> json) => PendingReport(
    bvid: json['bvid']! as String,
    cid: json['cid']! as int,
    played: json['played']! as int,
    at: DateTime.fromMillisecondsSinceEpoch(json['at']! as int),
  );

  final String bvid;
  final int cid;
  final int played;

  /// When the report was made.
  final DateTime at;

  Map<String, Object?> toJson() => {'bvid': bvid, 'cid': cid, 'played': played, 'at': at.millisecondsSinceEpoch};

  @override
  bool operator ==(Object other) =>
      other is PendingReport && other.bvid == bvid && other.cid == cid && other.played == played && other.at == at;

  @override
  int get hashCode => Object.hash(bvid, cid, played, at);
}

enum _Flushed { sent, gone, dropped, failed }

/// Watch reports that got no answer (offline, timed out), kept until Bilibili takes them, so a part watched with no
/// network still reaches the account's history (KaiC watches on several devices). One per part, the latest; a later
/// report of the part that goes through makes it moot. Kept 30 days, in a JSON file in the support folder. Every
/// heartbeat goes through [send], one at a time with [flush]'s, so Bilibili never hears an older place last.
class HistoryOutbox {
  HistoryOutbox._(this._path, this._held, this._logger, this._now);

  HistoryOutbox.memory({Logger? logger, DateTime Function() now = DateTime.now})
    : this._(null, {}, logger ?? Logger.shared, now);

  static const keptFor = Duration(days: 30);

  /// [path] null keeps the reports in memory only. An unreadable file starts empty; entries that don't decode are
  /// dropped one by one, and so are those past [keptFor].
  static Future<HistoryOutbox> load(String? path, {Logger? logger, DateTime Function() now = DateTime.now}) async {
    final log = logger ?? Logger.shared;
    final held = <(String, int), PendingReport>{};
    if (path != null) {
      final file = File(path);
      try {
        if (await file.exists()) {
          final json = jsonDecode(await file.readAsString());
          if (json is! List) throw const FormatException('not a list');
          var skipped = 0;
          for (final entry in json) {
            try {
              final report = PendingReport.fromJson(entry as Map<String, Object?>);
              held[(report.bvid, report.cid)] = report;
            } on TypeError {
              skipped++;
            }
          }
          if (skipped > 0) log.warn(LogCategory.app, 'history outbox entries skipped', {'skipped': skipped});
        }
      } catch (error) {
        log.warn(LogCategory.app, 'history outbox unreadable, starting empty', {'error': _reason(error)});
      }
    }
    final outbox = HistoryOutbox._(path, held, log, now);
    final dropped = outbox._dropExpired();
    if (held.isNotEmpty || dropped > 0) {
      log.info(LogCategory.app, 'history outbox', {'held': held.length, 'dropped': dropped});
    }
    return outbox;
  }

  final String? _path;
  final Map<(String, int), PendingReport> _held;
  final Logger _logger;
  final DateTime Function() _now;

  /// The end of the last task queued, while any is queued or running.
  Future<void>? _lane;
  Future<void>? _flushing;
  Future<void> _writing = Future.value();

  /// What is waiting, oldest first.
  List<PendingReport> get reports => [..._held.values]..sort((a, b) => a.at.compareTo(b.at));

  /// An unsent report of the part is waiting: what this phone saw of it is newer than anything Bilibili has.
  bool holds(String bvid, int cid) {
    final report = _held[(bvid, cid)];
    return report != null && !_expired(report);
  }

  /// No answer at all; Bilibili's own refusals and the Windows guard's are answers.
  static bool isNetworkFailure(Object error) => error is BiliNetworkError;

  /// Sends one report through [beat] after every one before it, a flush's included. A report that goes through
  /// clears the part's waiting one; one that gets no answer takes its place. Errors reach the caller.
  Future<void> send(String bvid, int cid, int played, Future<void> Function() beat) => _inLane(() async {
    try {
      await beat();
    } catch (error) {
      if (isNetworkFailure(error)) _keep(PendingReport(bvid: bvid, cid: cid, played: played, at: _now()));
      rethrow;
    }
    if (_held.remove((bvid, cid)) != null) _save();
  });

  /// Sends what is waiting, oldest first and one at a time, through [heartbeat]; stops at the first that gets no
  /// answer. A report Bilibili refuses outright (a video gone) is dropped, as sending it again gets the same answer;
  /// a login refused or risk control keeps it for a later flush. A flush already running answers for both.
  Future<void> flush(SendHeartbeat heartbeat) {
    final running = _flushing;
    if (running != null) return running;
    late final Future<void> flushing;
    flushing = _flush(heartbeat).whenComplete(() {
      if (identical(_flushing, flushing)) _flushing = null;
    });
    return _flushing = flushing;
  }

  Future<void> _flush(SendHeartbeat heartbeat) async {
    var dropped = _dropExpired();
    var sent = 0;
    var failed = 0;
    for (final report in reports) {
      final outcome = await _inLane(() async {
        // A page's own report may have settled it while this one waited its turn.
        final waiting = _held[(report.bvid, report.cid)];
        if (waiting == null) return _Flushed.gone;
        try {
          await heartbeat(bvid: waiting.bvid, cid: waiting.cid, playedTime: waiting.played);
        } catch (error) {
          if (!_refusedForGood(error)) return _Flushed.failed;
          _held.remove((waiting.bvid, waiting.cid));
          _save();
          return _Flushed.dropped;
        }
        _held.remove((waiting.bvid, waiting.cid));
        _save();
        return _Flushed.sent;
      });
      switch (outcome) {
        case _Flushed.sent:
          sent++;
        case _Flushed.dropped:
          dropped++;
        case _Flushed.failed:
          failed++;
        case _Flushed.gone:
          break;
      }
      if (outcome == _Flushed.failed) break;
    }
    if (sent + dropped + failed > 0) {
      _logger.info(LogCategory.api, 'history outbox', {
        'sent': sent,
        'dropped': dropped,
        'failed': failed,
        'held': _held.length,
      });
    }
  }

  static bool _refusedForGood(Object error) => switch (error) {
    BiliAPIError(code: -101 || -352 || -412) => false,
    BiliAPIError(code: GuardedTransport.readOnlyCode || GuardedTransport.capCode || GuardedTransport.haltCode) => false,
    BiliAPIError() => true,
    _ => false,
  };

  /// 退出登录: what is waiting was the old account's.
  void clear() {
    if (_held.isEmpty) return;
    final dropped = _held.length;
    _held.clear();
    _save();
    _logger.info(LogCategory.api, 'history outbox', {'dropped': dropped, 'held': 0});
  }

  /// Waits for the reports and writes under way; for tests.
  Future<void> settle() async {
    await _lane;
    await _flushing;
    await _writing;
  }

  void _keep(PendingReport report) {
    final key = (report.bvid, report.cid);
    final added = !_held.containsKey(key);
    _held[key] = report;
    _save();
    if (added) _logger.info(LogCategory.api, 'history outbox', {'queued': 1, 'held': _held.length});
  }

  bool _expired(PendingReport report) => _now().difference(report.at) > keptFor;

  int _dropExpired() {
    final expired = [
      for (final MapEntry(:key, :value) in _held.entries)
        if (_expired(value)) key,
    ];
    if (expired.isEmpty) return 0;
    expired.forEach(_held.remove);
    _save();
    return expired.length;
  }

  /// One task at a time; a failed one doesn't stop the next. Idle, a task starts at once, so the lane never hangs on
  /// a future made in another zone (a test's setUp).
  Future<T> _inLane<T>(Future<T> Function() task) {
    final before = _lane;
    final result = before == null ? Future.sync(task) : before.then((_) => task());
    late final Future<void> end;
    end = result.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
      if (identical(_lane, end)) _lane = null;
    });
    _lane = end;
    return result;
  }

  void _save() {
    final path = _path;
    if (path == null) return;
    final text = jsonEncode([for (final report in reports) report.toJson()]);
    // One write after another, so an older list never lands last.
    _writing = _writing.then((_) => _write(path, text));
  }

  Future<void> _write(String path, String text) async {
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      final temporary = File('$path.tmp');
      await temporary.writeAsString(text, flush: true);
      await temporary.rename(path);
    } catch (error) {
      _logger.warn(LogCategory.app, 'history outbox not saved', {'error': _reason(error)});
    }
  }

  /// The error without the text that failed or the path: a FormatException quotes it.
  static String _reason(Object error) => switch (error) {
    FormatException(:final message) => message,
    FileSystemException(:final message, :final osError) => osError == null ? message : '$message: $osError',
    _ => '${error.runtimeType}',
  };
}

/// Flushes [outbox] while [WatchReporter.canReport] allows: once the account check says logged in (the launch's,
/// a login), whenever the app comes back to the foreground, and on every network change. Logged out, it is cleared.
class HistoryOutboxFlusher with WidgetsBindingObserver {
  HistoryOutboxFlusher({required this.outbox, required this._environment, NetworkMonitor? network}) {
    WidgetsBinding.instance.addObserver(this);
    _account = _environment.account;
    _environment.addListener(_accountChanged);
    _network = (network ?? NetworkMonitor.platform()).changes.listen((_) => flush());
    // The launch's check may have answered before the app's services were made.
    if (_account is LoggedIn) flush();
  }

  final HistoryOutbox outbox;
  final AppEnvironment _environment;
  late final StreamSubscription<bool> _network;
  late Account _account;

  /// Sends what is waiting, if the account may report.
  void flush() {
    if (outbox.reports.isEmpty || !WatchReporter.canReport(_environment)) return;
    unawaited(outbox.flush(_environment.client.heartbeat));
  }

  void _accountChanged() {
    final now = _environment.account;
    final was = _account;
    _account = now;
    if (now is LoggedIn && was is! LoggedIn) flush();
    // Whoever logs in next may be another account.
    if (now is LoggedOut && was is! LoggedOut) outbox.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) flush();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _environment.removeListener(_accountChanged);
    unawaited(_network.cancel());
  }
}
