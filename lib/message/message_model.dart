import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/widgets.dart';

import '../app/app_environment.dart';
import '../search/results/video_row.dart' show searchLogReason;
import 'message_api.dart';
import 'message_prefs.dart';

/// 消息's state, one for the app ([AppServices.messages]): the red counts and the tab's badge, 消息提醒 (kept on the
/// phone), the session list, and the requests to show 消息 (a tapped 私信 notification).
///
/// Nothing is asked unless the account reads logged in. A logout or an expired login clears everything shown, and an
/// answer still out for the account before is dropped.
class MessageModel extends ChangeNotifier {
  MessageModel({
    required this.api,
    required this.environment,
    MessagePrefs? prefs,
    this.resumeGap = const Duration(minutes: 1),
    DateTime Function()? now,
    Logger? logger,
  }) : _prefs = prefs ?? MessagePrefs.memory(),
       _now = now ?? DateTime.now,
       _logger = logger ?? Logger.shared,
       _account = environment.account {
    environment.addListener(_accountChanged);
    environment.logins.addListener(_loginCompleted);
  }

  final MessageApi api;
  final AppEnvironment environment;
  final MessagePrefs _prefs;
  final DateTime Function() _now;
  final Logger _logger;

  /// How long after the counts were last asked a return to the app asks them again.
  final Duration resumeGap;

  MessageUnread _unread = const MessageUnread();
  final List<ChatSession> _sessions = [];
  final _showRequests = ChangeNotifier();

  /// The account as it last settled; unknown only until the launch's check answers.
  Account _account;

  /// Bumped by every login and logout, so an answer for the account before is dropped.
  int _generation = 0;

  bool _started = false;
  bool _disposed = false;
  _Foreground? _foreground;

  /// The turn to logged in has asked the counts already, so the login count that follows asks nothing more.
  bool _loginCounted = false;

  Future<void>? _unreadCall;
  DateTime? _lastUnread;

  /// Counts read here since the count call went out: its answer, asked before, can't raise them.
  final _readHere = <_Count>{};

  Future<void>? _sessionCall;
  bool _sessionCallIsFirst = false;
  bool _loading = false;
  int? _next;
  bool _hasMore = false;
  Object? _error;

  /// 消息 has asked for the list in this run, so a login asks its first page again.
  bool _sessionsWanted = false;

  /// The counts as last asked.
  MessageUnread get unread => _unread;

  /// 消息设置's 消息提醒: the red badges show at all.
  bool get badgeOn => _prefs.badgeOn;

  Future<void> setBadgeOn(bool on) async {
    if (on == _prefs.badgeOn) return;
    _prefs.badgeOn = on;
    _notify();
    await _prefs.settle();
  }

  /// The number on 消息's tab: [unread]'s total, 0 while [badgeOn] is off or logged out.
  int get badge => badgeOn && _loggedIn ? _unread.total : 0;

  List<ChatSession> get sessions => List.unmodifiable(_sessions);

  /// The session list's first page is out.
  bool get loading => _loading;

  /// More sessions are left past the last.
  bool get hasMore => _hasMore;

  /// The session list's last failure, null once a load succeeds.
  Object? get error => _error;

  bool get _loggedIn => environment.account is LoggedIn;

  /// Starts the counts' upkeep: once at launch, on a return to the app at most once a minute, and on each login.
  /// Called by the shell once; again does nothing. An account still unknown is asked for once it reads logged in.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    final foreground = _foreground = _Foreground(() => unawaited(refreshUnread()));
    WidgetsBinding.instance.addObserver(foreground);
    if (_loggedIn) unawaited(_askUnread());
  }

  /// Asks the counts again; [force] skips the once-a-minute limit (消息 shown). A call already out answers for this
  /// one.
  Future<void> refreshUnread({bool force = false}) {
    if (_disposed || !_loggedIn) return Future.value();
    if (_unreadCall case final running?) return running;
    final last = _lastUnread;
    if (!force && last != null && _now().difference(last) < resumeGap) return Future.value();
    return _askUnread();
  }

  Future<void> _askUnread() {
    if (_unreadCall case final running?) return running;
    _lastUnread = _now();
    _readHere.clear();
    late final Future<void> call;
    call = _fetchUnread(_generation).whenComplete(() {
      if (identical(_unreadCall, call)) _unreadCall = null;
    });
    return _unreadCall = call;
  }

  Future<void> _fetchUnread(int generation) async {
    final MessageUnread answer;
    try {
      answer = await api.unread();
    } catch (error) {
      if (_current(generation)) {
        _logger.warn(LogCategory.api, 'message unread failed', {'error': searchLogReason(error)});
      }
      return;
    }
    if (!_current(generation)) return;
    // A count read while the call was out stays as low as it went; anything new shows at the next ask.
    int kept(_Count count, int answered, int shown) => _readHere.contains(count) ? math.min(answered, shown) : answered;
    final counts = MessageUnread(
      reply: kept(_Count.reply, answer.reply, _unread.reply),
      at: kept(_Count.at, answer.at, _unread.at),
      like: kept(_Count.like, answer.like, _unread.like),
      system: kept(_Count.system, answer.system, _unread.system),
      chat: kept(_Count.chat, answer.chat, _unread.chat),
    );
    if (counts == _unread) return;
    _unread = counts;
    _notify();
  }

  /// The session list's first page and the counts, as 消息 shows or is pulled. A first page already out answers for
  /// this one; a next page out is waited for first, so one session call is out at a time.
  Future<void> refresh() async {
    if (_disposed || !_loggedIn) return;
    _sessionsWanted = true;
    await Future.wait([refreshUnread(force: true), _refreshSessions()]);
  }

  Future<void> _refreshSessions() async {
    for (var running = _sessionCall; running != null; running = _sessionCall) {
      if (_sessionCallIsFirst) return running;
      await running;
    }
    if (_disposed || !_loggedIn) return;
    return _askSessions(first: true);
  }

  /// The next page of sessions; nothing while one is out, at the end, or after a failure until [refresh] succeeds.
  Future<void> loadMore() {
    if (_disposed || !_loggedIn || !_hasMore || _error != null) return Future.value();
    if (_sessionCall case final running?) return running;
    return _askSessions(first: false);
  }

  Future<void> _askSessions({required bool first}) {
    final next = first ? null : _next;
    if (first) {
      _loading = true;
      _notify();
    }
    late final Future<void> call;
    call = _fetchSessions(_generation, next: next, first: first).whenComplete(() {
      if (identical(_sessionCall, call)) _sessionCall = null;
    });
    _sessionCallIsFirst = first;
    return _sessionCall = call;
  }

  Future<void> _fetchSessions(int generation, {required int? next, required bool first}) async {
    try {
      final page = await api.sessions(next: next);
      if (!_current(generation)) return;
      var added = page.sessions.length;
      if (first) {
        _sessions
          ..clear()
          ..addAll(page.sessions);
      } else {
        final fresh = [
          for (final session in page.sessions)
            if (_indexOf(session) < 0) session,
        ];
        _sessions.addAll(fresh);
        added = fresh.length;
      }
      _next = page.next;
      // A page that adds no one ends the list, so nothing asks on and on.
      _hasMore = page.next != null && added > 0;
      _error = null;
    } catch (error) {
      if (!_current(generation)) return;
      _logger.warn(LogCategory.ui, 'message sessions failed', {
        'page': first ? 'first' : 'next',
        'error': searchLogReason(error),
      });
      _error = error;
    }
    if (first) _loading = false;
    _notify();
  }

  int _indexOf(ChatSession session) => _sessions.indexWhere(
    (each) => each.talkerId == session.talkerId && each.sessionType == session.sessionType && each.box == session.box,
  );

  /// [feed]'s list was opened: its count goes to 0 (回复与@ clears [NoticeFeed.reply] and [NoticeFeed.at]).
  void feedOpened(NoticeFeed feed) {
    if (_disposed) return;
    switch (feed) {
      case NoticeFeed.reply || NoticeFeed.at:
        _read(_unread.copyWith(reply: 0, at: 0), const {_Count.reply, _Count.at});
      case NoticeFeed.like:
        _read(_unread.copyWith(like: 0), const {_Count.like});
    }
  }

  /// [session] was opened: it is acked up to its newest message and its count goes to 0. The list's own copy of it
  /// counts over the one given; 系统通知's count is [MessageUnread.system], its box not being in the list. The count
  /// drops at once; a failed ack is logged and leaves it so.
  Future<void> chatOpened(ChatSession session) async {
    if (_disposed || !_loggedIn) return;
    final index = _indexOf(session);
    final listed = index < 0 ? session : _sessions[index];
    final system = session.box == NoticeBox.system;
    final count = system ? math.max(listed.unread, _unread.system) : listed.unread;
    if (count <= 0) return;
    final seqno = math.max(session.maxSeqno, listed.maxSeqno);
    if (index >= 0) _sessions[index] = listed.copyWith(unread: 0, ackSeqno: seqno);
    if (system) {
      _read(_unread.copyWith(system: 0), const {_Count.system}, listChanged: index >= 0);
    } else {
      _read(_unread.copyWith(chat: math.max(0, _unread.chat - count)), const {_Count.chat}, listChanged: index >= 0);
    }
    final generation = _generation;
    try {
      await api.read(listed, seqno: seqno);
    } catch (error) {
      if (_current(generation)) _logger.warn(LogCategory.api, 'message read failed', {'error': searchLogReason(error)});
    }
  }

  /// 一键已读 (211): once Bilibili accepts it, every count and every session's goes to 0. Throws when it doesn't,
  /// the counts left as they were.
  Future<void> readAll() async {
    if (_disposed || !_loggedIn) return;
    final generation = _generation;
    try {
      await api.readAll();
    } catch (error) {
      _logger.warn(LogCategory.api, 'message read all failed', {'error': searchLogReason(error)});
      rethrow;
    }
    if (!_current(generation)) return;
    for (var i = 0; i < _sessions.length; i++) {
      if (_sessions[i].unread > 0) _sessions[i] = _sessions[i].copyWith(unread: 0, ackSeqno: _sessions[i].maxSeqno);
    }
    _read(const MessageUnread(), _Count.values.toSet(), listChanged: true);
  }

  /// The counts [read] were read here and now stand at [counts].
  void _read(MessageUnread counts, Set<_Count> read, {bool listChanged = false}) {
    _readHere.addAll(read);
    if (counts == _unread && !listChanged) return;
    _unread = counts;
    _notify();
  }

  /// Asks the shell to show 消息.
  void requestShow() => _showRequests.notifyListeners();

  /// Fires on [requestShow].
  Listenable get showRequests => _showRequests;

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
      _accountArrived();
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
    _accountArrived();
    _notify();
  }

  void _accountArrived() {
    if (_started) unawaited(_askUnread());
    if (_sessionsWanted) unawaited(_refreshSessions());
  }

  void _clear() {
    _generation++;
    _unread = const MessageUnread();
    _unreadCall = null;
    _lastUnread = null;
    _readHere.clear();
    _sessions.clear();
    _sessionCall = null;
    _loading = false;
    _next = null;
    _hasMore = false;
    _error = null;
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
    _showRequests.dispose();
    super.dispose();
  }
}

enum _Count { reply, at, like, system, chat }

/// A return to the app.
class _Foreground with WidgetsBindingObserver {
  _Foreground(this._resumed);

  final VoidCallback _resumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _resumed();
  }
}
