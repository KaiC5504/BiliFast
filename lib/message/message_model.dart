import 'package:bili_core/api.dart';
import 'package:flutter/foundation.dart';

import '../app/app_environment.dart';
import 'message_api.dart';

/// 消息's state, one for the app ([AppServices.messages]): the red counts and the tab's badge, 消息提醒 (kept on the
/// phone), the session list, and the requests to show 消息 (a tapped 私信 notification).
class MessageModel extends ChangeNotifier {
  MessageModel({required this.api, required this.environment});

  final MessageApi api;
  final AppEnvironment environment;

  final MessageUnread _unread = const MessageUnread();
  final List<ChatSession> _sessions = [];
  final _showRequests = ChangeNotifier();

  /// The counts as last asked.
  MessageUnread get unread => _unread;

  /// 消息设置's 消息提醒: the red badges show at all.
  bool get badgeOn => true;

  Future<void> setBadgeOn(bool on) async {}

  /// The number on 消息's tab: [unread]'s total, 0 while [badgeOn] is off or logged out.
  int get badge => badgeOn ? _unread.total : 0;

  List<ChatSession> get sessions => List.unmodifiable(_sessions);

  /// The session list's first page is out.
  bool get loading => false;

  /// More sessions are left past the last.
  bool get hasMore => false;

  /// The session list's last failure, null once a load succeeds.
  Object? get error => null;

  /// Starts the counts' upkeep: once at launch, on a return to the app at most once a minute, and on each login.
  /// Called by the shell once; again does nothing.
  void start() {}

  /// Asks the counts again; [force] skips the once-a-minute limit (消息 shown).
  Future<void> refreshUnread({bool force = false}) async {}

  /// The session list's first page and the counts, as 消息 shows or is pulled.
  Future<void> refresh() async {}

  Future<void> loadMore() async {}

  /// [feed]'s list was opened: its count goes to 0 (回复与@ clears [NoticeFeed.reply] and [NoticeFeed.at]).
  void feedOpened(NoticeFeed feed) {}

  /// [session] was opened: it is acked up to its newest message and its count goes to 0.
  Future<void> chatOpened(ChatSession session) async {}

  /// 一键已读 (211).
  Future<void> readAll() async {}

  /// Asks the shell to show 消息.
  void requestShow() => _showRequests.notifyListeners();

  /// Fires on [requestShow].
  Listenable get showRequests => _showRequests;

  @override
  void dispose() {
    _showRequests.dispose();
    super.dispose();
  }
}
