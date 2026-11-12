import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;

import '../app/app_environment.dart';
import '../device/network_monitor.dart';
import 'watch_reporter.dart';

/// `BiliClient.heartbeat`'s shape.
typedef SendHeartbeat = Future<void> Function({required String bvid, required int cid, required int playedTime});

/// The account's latest 历史记录 page (`BiliClient.history`).
typedef ReadRecentHistory = Future<HistoryPage> Function();

/// The last watch report of one video that got no answer, in the part it was made in: the seconds played, or -1 for
/// finished.
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

/// A play's end report for the official iPhone reports (docs/reference/official-iphone-calls.md), as it would go out
/// while the play runs and as it stands once the play is over, with the history report after it: the report's own
/// numbers and ids, its source's strings and the account that watched. No token and nothing signed is kept.
@immutable
final class PendingPlay {
  const PendingPlay({
    required this.mid,
    required this.report,
    required this.finished,
    required this.at,
    this.reported = false,
    this.strikes = 0,
  });

  factory PendingPlay.fromJson(Map<String, Object?> json) => PendingPlay(
    mid: json['mid']! as int,
    report: WatchReport(
      aid: json['aid']! as int,
      cid: json['cid']! as int,
      duration: json['duration']! as int,
      session: json['session']! as String,
      source: PlaySource(
        fromSpmid: json['from_spmid']! as String,
        from: json['from']! as String,
        trackId: json['track_id'] as String?,
        flowData: json['flow_data'] as String?,
        spmid: json['spmid']! as String,
        historySource: json['history_source'] as String?,
      ),
      spmid: json['spmid']! as String,
      startTs: json['start_ts']! as int,
      playedTime: json['played']! as int,
      actualPlayedTime: json['actual_played']! as int,
      totalTime: json['total']! as int,
      pausedTime: json['paused']! as int,
      lastProgress: json['last']! as int,
      maxProgress: json['max']! as int,
      quality: json['quality']! as int,
      autoPlay: json['auto_play']! as int,
    ),
    finished: json['finished']! as bool,
    at: DateTime.fromMillisecondsSinceEpoch(json['at']! as int),
    reported: json['reported']! as bool,
    strikes: json['strikes'] as int? ?? 0,
  );

  /// The account the play was watched as; only that account's token reports it.
  final int mid;
  final WatchReport report;

  /// The video played to its end, which the history report says as -1.
  final bool finished;

  /// When these numbers were taken.
  final DateTime at;

  /// The end report is settled; only the history report is left.
  final bool reported;

  /// The flushes in which a call of its own faulted; [HistoryOutbox.maxStrikes] give it up.
  final int strikes;

  PendingPlay get settled =>
      PendingPlay(mid: mid, report: report, finished: finished, at: at, reported: true, strikes: strikes);

  PendingPlay get struck =>
      PendingPlay(mid: mid, report: report, finished: finished, at: at, reported: reported, strikes: strikes + 1);

  Map<String, Object?> toJson() => {
    'session': report.session,
    'mid': mid,
    'aid': report.aid,
    'cid': report.cid,
    'duration': report.duration,
    'spmid': report.spmid,
    'from': report.source.from,
    'from_spmid': report.source.fromSpmid,
    'track_id': ?report.source.trackId,
    'flow_data': ?report.source.flowData,
    'history_source': ?report.source.historySource,
    'start_ts': report.startTs,
    'played': report.playedTime,
    'actual_played': report.actualPlayedTime,
    'total': report.totalTime,
    'paused': report.pausedTime,
    'last': report.lastProgress,
    'max': report.maxProgress,
    'quality': report.quality,
    'auto_play': report.autoPlay,
    'finished': finished,
    'reported': reported,
    if (strikes > 0) 'strikes': strikes,
    'at': at.millisecondsSinceEpoch,
  };
}

/// How a kept play goes out as account [mid]: [end] sends its end report, [history] its place in the account's
/// history. Each throws what the client threw, or [AnotherAccountsPlay] with nothing sent.
@immutable
final class PlaySender {
  const PlaySender({required this.mid, required this.end, required this.history});

  final int mid;
  final Future<void> Function(PendingPlay play) end;
  final Future<void> Function(PendingPlay play) history;
}

/// Thrown by a [PlaySender]'s call that sent nothing, because the token held as it was about to go is another
/// account's: the outbox drops the play as it drops any other account's.
final class AnotherAccountsPlay implements Exception {
  const AnotherAccountsPlay();
}

enum _Flushed { sent, gone, dropped, noAnswer, kept, struck }

/// Watch reports that got no answer (offline, timed out), kept until Bilibili takes them, so a part watched with no
/// network still reaches the account's history (KaiC watches on several devices). One per video, the latest, as
/// Bilibili keeps one place per video whatever the part; a later report of the video that goes through makes it moot.
/// Kept 30 days, in a JSON file in the support folder. Every heartbeat goes through [send], one at a time with
/// [flush]'s, so Bilibili never hears an older place last.
///
/// Under the official iPhone reports a play says what was watched only as it ends, so it is kept while it runs
/// ([keepPlay], then [endPlay]): a play the app was killed in, or one that ended with no network, goes out from
/// [sendPlays] or the next [flush], each play once, oldest first.
class HistoryOutbox {
  HistoryOutbox._(this._path, this._held, this._plays, this._logger, this._now);

  HistoryOutbox.memory({Logger? logger, DateTime Function() now = DateTime.now})
    : this._(null, {}, {}, logger ?? Logger.shared, now);

  static const keptFor = Duration(days: 30);

  /// A flush holding a report older than this asks the account's history first: another device may have watched the
  /// video since.
  static const checkAfter = Duration(minutes: 5);

  /// The flushes a play may fault in before it is given up, so one Bilibili never takes doesn't go out at every flush
  /// for [keptFor].
  static const maxStrikes = 5;

  /// The plays one pass sends, two calls each: a long queue goes out over the flushes that follow, never as one
  /// burst against the account.
  static const playsPerPass = 5;

  /// [path] null keeps the reports in memory only. An unreadable file starts empty; entries that don't decode are
  /// dropped one by one, and so are those past [keptFor].
  static Future<HistoryOutbox> load(String? path, {Logger? logger, DateTime Function() now = DateTime.now}) async {
    final log = logger ?? Logger.shared;
    final held = <String, PendingReport>{};
    final plays = <String, PendingPlay>{};
    if (path != null) {
      final file = File(path);
      try {
        if (await file.exists()) {
          final json = jsonDecode(await file.readAsString());
          if (json is! List) throw const FormatException('not a list');
          var skipped = 0;
          for (final entry in json) {
            try {
              final fields = entry as Map<String, Object?>;
              // Only a play names its session.
              if (fields.containsKey('session')) {
                final play = PendingPlay.fromJson(fields);
                plays[play.report.session] = play;
                continue;
              }
              final report = PendingReport.fromJson(fields);
              final kept = held[report.bvid];
              if (kept == null || kept.at.isBefore(report.at)) held[report.bvid] = report;
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
    final outbox = HistoryOutbox._(path, held, plays, log, now);
    final dropped = outbox._dropExpired();
    if (held.isNotEmpty || plays.isNotEmpty || dropped > 0) {
      log.info(LogCategory.app, 'history outbox', {'held': held.length + plays.length, 'dropped': dropped});
    }
    return outbox;
  }

  final String? _path;

  /// By bvid.
  final Map<String, PendingReport> _held;

  /// By session: the plays running as they stand, and those over whose reports have not gone out.
  final Map<String, PendingPlay> _plays;

  /// The plays still running in this launch. Their end report is not made yet, so nothing sends them; one the app
  /// was killed in is over by the next launch.
  final Set<String> _running = {};
  final Logger _logger;
  final DateTime Function() _now;

  /// Reports [send] has taken and not yet settled, by part.
  final Map<(String, int), int> _inFlight = {};

  /// Bumped by [clear], so a report out at a logout that then gets no answer isn't kept for the next account.
  int _generation = 0;

  /// The end of the last task queued, while any is queued or running.
  Future<void>? _lane;
  Future<void>? _flushing;

  /// A flush was asked for while one ran.
  bool _again = false;
  Future<void> _writing = Future.value();

  /// What is waiting, oldest first.
  List<PendingReport> get reports => [..._held.values]..sort((a, b) => a.at.compareTo(b.at));

  /// The plays that are over and wait to be reported, oldest first.
  List<PendingPlay> get plays => [
    for (final play in _plays.values)
      if (!_running.contains(play.report.session)) play,
  ]..sort((a, b) => a.at.compareTo(b.at));

  /// A report of the part is waiting or on its way: what this phone saw of it is newer than anything Bilibili has.
  bool holds(String bvid, int cid) {
    if ((_inFlight[(bvid, cid)] ?? 0) > 0) return true;
    if (_plays.values.any((play) => play.report.cid == cid && !_expired(play.at))) return true;
    final report = _held[bvid];
    return report != null && report.cid == cid && !_expired(report.at);
  }

  /// [play] is not over yet: its end report as it would go out now is kept, so a play the app is killed in reaches
  /// Bilibili from the next launch's flush.
  void keepPlay(PendingPlay play) {
    _running.add(play.report.session);
    _plays[play.report.session] = play;
    _save();
  }

  /// The play is over: what was last kept of it waits for [sendPlays] or a [flush].
  void endPlay(String session) => _running.remove(session);

  /// A play that ends with nothing to report (logged out since it began).
  void dropPlay(String session) {
    _running.remove(session);
    if (_plays.remove(session) != null) _save();
  }

  /// Sends the plays that are over through [sender], as a [flush] does, without waiting for one: a page's play goes
  /// out as it ends, after any older one still waiting.
  Future<void> sendPlays(PlaySender sender, {required ReadRecentHistory recent}) async {
    var moved = const <String>{};
    if (plays.any((play) => _now().difference(play.at) > checkAfter)) {
      try {
        moved = _playsMovedOn((await recent()).items);
      } catch (_) {
        // The client logged why. Nothing goes out before the account's history is known; the next flush asks again.
        return;
      }
    }
    await _sendPlays(sender, moved);
  }

  /// No answer at all; Bilibili's own refusals and the Windows guard's are answers.
  static bool isNetworkFailure(Object error) => error is BiliNetworkError;

  /// Sends one report through [beat] after every one before it, a flush's included. A report that goes through
  /// clears the video's waiting one, older whatever its part; one that gets no answer takes its place. Errors reach
  /// the caller.
  Future<void> send(String bvid, int cid, int played, Future<void> Function() beat) {
    final part = (bvid, cid);
    _inFlight[part] = (_inFlight[part] ?? 0) + 1;
    final generation = _generation;
    return _inLane(() async {
      try {
        await beat();
      } catch (error) {
        if (isNetworkFailure(error) && generation == _generation) {
          _keep(PendingReport(bvid: bvid, cid: cid, played: played, at: _now()));
        }
        rethrow;
      }
      if (_held.remove(bvid) != null) _save();
    }).whenComplete(() {
      final left = (_inFlight[part] ?? 1) - 1;
      if (left > 0) {
        _inFlight[part] = left;
      } else {
        _inFlight.remove(part);
      }
    });
  }

  /// Sends what is waiting, oldest first and one at a time, through [heartbeat]; stops at the first that gets no
  /// answer. Holding a report older than [checkAfter], it first reads [recent] once and drops each report whose video
  /// the account has watched since (another device). A report Bilibili refuses outright (a video gone) is dropped, as
  /// sending it again gets the same answer; a login refused or risk control keeps it for a later flush. A flush asked
  /// for while one runs gets one more pass if that one ended with no answer (the network may be back).
  ///
  /// With [plays] the plays that are over go out after the heartbeats, under the same rules; each sends its end
  /// report, then its place in the history unless the account has watched the video since. Without it (no iPhone
  /// token now) they wait. A play whose own call faults (an HTTP error status, an answer that doesn't decode) holds
  /// nothing up: the flush goes on to the next, and [maxStrikes] such flushes give the play up. A pass sends
  /// [playsPerPass] plays at most; the rest wait for the next flush.
  Future<void> flush(SendHeartbeat heartbeat, {required ReadRecentHistory recent, PlaySender? plays}) {
    final running = _flushing;
    if (running != null) {
      _again = true;
      return running;
    }
    late final Future<void> flushing;
    flushing = _run(heartbeat, recent, plays).whenComplete(() {
      if (identical(_flushing, flushing)) _flushing = null;
    });
    return _flushing = flushing;
  }

  Future<void> _run(SendHeartbeat heartbeat, ReadRecentHistory recent, PlaySender? sender) async {
    _again = false;
    while (await _pass(heartbeat, recent, sender) && _again) {
      _again = false;
    }
  }

  /// Whether it ended with no answer.
  Future<bool> _pass(SendHeartbeat heartbeat, ReadRecentHistory recent, PlaySender? sender) async {
    var dropped = _dropExpired();
    var stale = 0;
    var sent = 0;
    var failed = 0;
    var noAnswer = false;
    var moved = const <String>{};
    final made = [
      for (final report in reports) report.at,
      if (sender != null)
        for (final play in plays) play.at,
    ];
    if (made.any((at) => _now().difference(at) > checkAfter)) {
      try {
        final items = (await recent()).items;
        stale = _dropWatchedSince(items);
        moved = _playsMovedOn(items);
      } catch (error) {
        failed++;
        noAnswer = isNetworkFailure(error);
      }
    }
    if (failed == 0) {
      for (final report in reports) {
        final outcome = await _inLane(() async {
          // A page's own report may have settled it, or a newer one taken its place, while this one waited its turn.
          final waiting = _held[report.bvid];
          if (waiting == null) return _Flushed.gone;
          try {
            await heartbeat(bvid: waiting.bvid, cid: waiting.cid, playedTime: waiting.played);
          } catch (error) {
            if (isNetworkFailure(error)) return _Flushed.noAnswer;
            if (!_refusedForGood(error)) return _Flushed.kept;
            _remove(waiting);
            return _Flushed.dropped;
          }
          _remove(waiting);
          return _Flushed.sent;
        });
        switch (outcome) {
          case _Flushed.sent:
            sent++;
          case _Flushed.dropped:
            dropped++;
          case _Flushed.noAnswer || _Flushed.kept:
            failed++;
          // Only a play is struck.
          case _Flushed.gone || _Flushed.struck:
            break;
        }
        if (outcome == _Flushed.noAnswer || outcome == _Flushed.kept) {
          noAnswer = outcome == _Flushed.noAnswer;
          break;
        }
      }
    }
    if (failed == 0 && sender != null) {
      final result = await _sendPlays(sender, moved);
      sent += result.sent;
      dropped += result.dropped;
      failed += result.failed;
      noAnswer = result.noAnswer;
    }
    if (sent + dropped + stale + failed > 0) {
      _logger.info(LogCategory.api, 'history outbox', {
        'sent': sent,
        'dropped': dropped,
        'stale': stale,
        'failed': failed,
        'held': _held.length + plays.length,
      });
    }
    return noAnswer;
  }

  /// The [playsPerPass] oldest plays that are over, one at a time. It stops at the first the whole queue waits behind
  /// and steps past one struck for a fault of its own.
  Future<({int sent, int dropped, int failed, bool noAnswer})> _sendPlays(PlaySender sender, Set<String> moved) async {
    var sent = 0;
    var dropped = 0;
    var failed = 0;
    for (final play in plays.take(playsPerPass)) {
      final session = play.report.session;
      final outcome = await _inLane(() => _sendPlay(session, sender, place: !moved.contains(session)));
      switch (outcome) {
        case _Flushed.sent:
          sent++;
        case _Flushed.dropped:
          dropped++;
        case _Flushed.struck:
          failed++;
        case _Flushed.gone:
          break;
        case _Flushed.noAnswer || _Flushed.kept:
          return (sent: sent, dropped: dropped, failed: failed + 1, noAnswer: outcome == _Flushed.noAnswer);
      }
    }
    return (sent: sent, dropped: dropped, failed: failed, noAnswer: false);
  }

  /// The end report, then the place unless it is no longer this phone's to set ([place] false). A call Bilibili
  /// refuses outright is given up, and the other still goes: the place matters whatever became of the end report.
  /// Sent means Bilibili took every call made; a play with a call given up is dropped.
  Future<_Flushed> _sendPlay(String session, PlaySender sender, {required bool place}) async {
    // A logout may have dropped it, or another pass sent it, while this one waited its turn.
    var play = _plays[session];
    if (play == null || _running.contains(session)) return _Flushed.gone;
    if (play.mid != sender.mid) {
      _removePlay(play);
      return _Flushed.dropped;
    }
    var refused = false;
    if (!play.reported) {
      try {
        await sender.end(play);
      } catch (error) {
        final left = _failed(play, error);
        if (left != null) return left;
        refused = true;
      }
      if (!identical(_plays[session], play)) return _Flushed.gone;
      play = _plays[session] = play.settled;
      // On disk before the place is asked for: killed in between, the next launch would send the end report again
      // and Bilibili count the play's time twice.
      _save();
      await _writing;
      if (!identical(_plays[session], play)) return _Flushed.gone;
    }
    if (place) {
      try {
        await sender.history(play);
      } catch (error) {
        final left = _failed(play, error);
        if (left != null) return left;
        refused = true;
      }
    }
    _removePlay(play);
    return refused ? _Flushed.dropped : _Flushed.sent;
  }

  /// What a failed call makes of [play]; null when Bilibili refused the call for good and the play goes on without
  /// it. A fault of the play's own strikes it, and the last strike drops it.
  _Flushed? _failed(PendingPlay play, Object error) {
    if (error is AnotherAccountsPlay) {
      _removePlay(play);
      return _Flushed.dropped;
    }
    final waits = _waits(error);
    if (waits != _Flushed.struck) return waits;
    final session = play.report.session;
    if (!identical(_plays[session], play)) return _Flushed.gone;
    final struck = play.struck;
    if (struck.strikes < maxStrikes) {
      _plays[session] = struck;
      _save();
      return _Flushed.struck;
    }
    _plays.remove(session);
    _save();
    _logger.warn(LogCategory.api, 'watch report', {
      'kind': 'given up',
      'strikes': struck.strikes,
      'error': '${error.runtimeType}',
      'code': ?switch (error) {
        BiliAPIError(:final code) => code,
        BiliHTTPError(:final status) => status,
        _ => null,
      },
    });
    return _Flushed.dropped;
  }

  /// How a failed call leaves its play; null when Bilibili refused it for good. The whole queue waits behind no
  /// answer, and behind an answer about the login or the install, which costs the play nothing: a refused login (-2
  /// is the official API's, an app token it no longer takes, which a new confirm mends), a missing token, risk
  /// control (HTTP 412 too) and the Windows guard. A server-side code that may pass, and whatever else is no answer
  /// from Bilibili's API (an HTTP error status, an answer that doesn't decode), is that play's own fault.
  static _Flushed? _waits(Object error) => switch (error) {
    BiliNetworkError() => _Flushed.noAnswer,
    BiliNoAppTokenError() || BiliAPIError(code: -2) || BiliHTTPError(status: 412) => _Flushed.kept,
    BiliAPIError(code: -500 || -503 || -509 || -799) => _Flushed.struck,
    BiliAPIError() => _refusedForGood(error) ? null : _Flushed.kept,
    _ => _Flushed.struck,
  };

  void _removePlay(PendingPlay play) {
    final session = play.report.session;
    if (!identical(_plays[session], play)) return;
    _plays.remove(session);
    _save();
  }

  /// The plays that are over whose video [items] shows watched since: the account's place in it is newer than theirs.
  Set<String> _playsMovedOn(List<HistoryItem> items) {
    final watched = <int, int>{};
    for (final item in items) {
      watched[item.aid] = max(watched[item.aid] ?? 0, item.viewAt);
    }
    return {
      for (final play in plays)
        if ((watched[play.report.aid] ?? 0) * 1000 >= play.at.millisecondsSinceEpoch) play.report.session,
    };
  }

  void _remove(PendingReport report) {
    if (!identical(_held[report.bvid], report)) return;
    _held.remove(report.bvid);
    _save();
  }

  /// Drops the reports whose video [items] shows watched at or after the report was made.
  int _dropWatchedSince(List<HistoryItem> items) {
    final watched = <String, int>{};
    for (final item in items) {
      watched[item.bvid] = max(watched[item.bvid] ?? 0, item.viewAt);
    }
    final moved = [
      for (final report in _held.values)
        if ((watched[report.bvid] ?? 0) * 1000 >= report.at.millisecondsSinceEpoch) report.bvid,
    ];
    if (moved.isEmpty) return 0;
    moved.forEach(_held.remove);
    _save();
    return moved.length;
  }

  static bool _refusedForGood(Object error) => switch (error) {
    BiliAPIError(code: -101 || -352 || -412) => false,
    BiliAPIError(code: GuardedTransport.readOnlyCode || GuardedTransport.capCode || GuardedTransport.haltCode) => false,
    BiliAPIError() => true,
    _ => false,
  };

  /// 退出登录: what is waiting was the old account's, and so is any report still out, and any play still running.
  void clear() {
    _generation++;
    final dropped = _held.length + _plays.length;
    if (dropped == 0) return;
    _held.clear();
    _plays.clear();
    _running.clear();
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
    final added = !_held.containsKey(report.bvid);
    _held[report.bvid] = report;
    _save();
    if (added) _logger.info(LogCategory.api, 'history outbox', {'queued': 1, 'held': _held.length});
  }

  bool _expired(DateTime at) => _now().difference(at) > keptFor;

  int _dropExpired() {
    final expired = [
      for (final report in _held.values)
        if (_expired(report.at)) report.bvid,
    ];
    final old = [
      for (final play in _plays.values)
        if (_expired(play.at)) play.report.session,
    ];
    if (expired.isEmpty && old.isEmpty) return 0;
    expired.forEach(_held.remove);
    old.forEach(_plays.remove);
    _save();
    return expired.length + old.length;
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
    final text = jsonEncode([
      for (final report in reports) report.toJson(),
      for (final play in _plays.values) play.toJson(),
    ]);
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
    if (outbox.reports.isEmpty && outbox.plays.isEmpty || !WatchReporter.canReport(_environment)) return;
    final client = _environment.client;
    unawaited(outbox.flush(client.heartbeat, recent: client.history, plays: WatchReporter.playSender(client)));
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
