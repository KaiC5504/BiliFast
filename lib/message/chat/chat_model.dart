import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../message_api.dart';

/// One chat's messages (202, 203) or a notice box's (200, 201): the newest page first, older pages one call at a time,
/// the bar's 不接受推送 and 加关注, and sending.
class ChatModel extends ChangeNotifier {
  ChatModel({required this.api, required this.session, required this.selfMid, Logger? logger})
    : _logger = logger ?? Logger.shared;

  final MessageApi api;
  final ChatSession session;

  /// The account's mid, which tells its own messages from the other side's.
  final int? Function() selfMid;
  final Logger _logger;

  final _messages = <ChatMessage>[];

  /// Sent here and not yet answered; drawn as they are until the answer replaces them.
  final _pending = Set<ChatMessage>.identity();

  bool _loading = false;
  Object? _error;
  bool _loadingOlder = false;
  bool _olderFailed = false;
  bool _hasMore = false;
  int _minSeqno = 0;
  ChatSettings? _settings;
  bool _changingPush = false;
  bool _sendingFollow = false;
  bool? _following;
  bool _disposed = false;

  /// Oldest first.
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  bool isPending(ChatMessage message) => _pending.contains(message);

  /// The first page is out.
  bool get loading => _loading;

  /// The first page failed; null once one arrives.
  Object? get error => _error;

  bool get loadingOlder => _loadingOlder;
  bool get olderFailed => _olderFailed;
  bool get hasMore => _hasMore;

  /// A person's chat: the bar over it (202) and the composer. Notice boxes and groups have neither.
  bool get isPerson => session.box == null && session.sessionType == 1;

  /// The bar's state, null until it arrives or when the chat has no bar.
  ChatSettings? get settings => _settings;

  /// 203 has no bar: a person the account already followed when the chat opened. One followed since keeps it, reading
  /// 已关注.
  bool get showsBar => isPerson && _settings != null && !_settings!.following;

  /// As last changed here or on another page, else as the bar's answer said.
  bool get following => _following ?? _settings?.following ?? false;

  bool isOwn(ChatMessage message) => session.box == null && message.senderMid == selfMid();

  /// The newest page; returns it so the page can ack the session up to its newest message, null when it failed.
  Future<ChatMessagePage?> start() async {
    if (_loading) return null;
    _loading = true;
    _error = null;
    _notify();
    try {
      final page = await api.messages(session);
      if (_disposed) return null;
      _messages
        ..clear()
        ..addAll(page.messages);
      _hasMore = page.hasMore;
      _minSeqno = page.minSeqno;
      return page;
    } catch (error) {
      _logger.warn(LogCategory.api, 'chat messages failed', {'error': _reason(error)});
      _error = error;
      return null;
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// The page before the oldest shown; one call at a time, and none after a failure until [retryOlder].
  Future<void> loadOlder() async {
    if (_loadingOlder || _olderFailed || !_hasMore || _loading || _minSeqno <= 0) return;
    _loadingOlder = true;
    _notify();
    try {
      final before = _minSeqno;
      final page = await api.messages(session, beforeSeqno: before);
      if (_disposed) return;
      final known = {for (final message in _messages) message.seqno};
      _messages.insertAll(0, page.messages.where((message) => !known.contains(message.seqno)));
      // Paging goes on only while the cursor moves back: a page of nothing but take-backs decodes empty yet moves it,
      // and one that repeats what's shown would otherwise be asked again every frame.
      final moved = page.minSeqno > 0 && page.minSeqno < before;
      _hasMore = page.hasMore && moved;
      if (moved) _minSeqno = page.minSeqno;
    } catch (error) {
      _logger.warn(LogCategory.api, 'older chat messages failed', {'error': _reason(error)});
      _olderFailed = true;
    } finally {
      _loadingOlder = false;
      _notify();
    }
  }

  void retryOlder() {
    _olderFailed = false;
    unawaited(loadOlder());
  }

  /// The bar's state for a person; a failure leaves the bar out.
  Future<void> loadSettings() async {
    if (!isPerson) return;
    try {
      final settings = await api.chatSettings(session.talkerId);
      if (_disposed) return;
      _settings = settings;
      _notify();
    } catch (error) {
      _logger.warn(LogCategory.api, 'chat settings failed', {'error': _reason(error)});
    }
  }

  /// Another page's 关注 of this person, taken in place of the bar's answer.
  void followChanged(bool following) {
    if (_following == following) return;
    _following = following;
    _notify();
  }

  /// 不接受推送 and back. Throws what the call threw.
  Future<void> togglePush() async {
    final settings = _settings;
    if (settings == null || _changingPush) return;
    _changingPush = true;
    try {
      final on = !settings.pushOn;
      await api.setChatPush(session.talkerId, on: on);
      if (_disposed) return;
      final now = _settings ?? settings;
      _settings = ChatSettings(following: now.following, pushOn: on, showPush: now.showPush);
      _notify();
    } finally {
      _changingPush = false;
    }
  }

  /// 加关注, once while it is out. Throws what the call threw.
  Future<void> follow() async {
    if (following || _sendingFollow) return;
    _sendingFollow = true;
    try {
      await api.follow(session.talkerId, on: true);
      if (_disposed) return;
      _following = true;
      _notify();
    } finally {
      _sendingFollow = false;
    }
  }

  /// Sends [text] (already trimmed, not empty): it shows at once at the bottom and is replaced by the message as
  /// Bilibili took it; on failure it is taken away again and the error thrown.
  Future<void> send(String text) async {
    final local = ChatMessage(
      seqno: (_messages.isEmpty ? 0 : _messages.last.seqno) + 1,
      senderMid: selfMid() ?? 0,
      kind: ChatMessageKind.text,
      text: text,
      time: DateTime.now(),
    );
    _messages.add(local);
    _pending.add(local);
    _notify();
    try {
      final sent = await api.send(session.talkerId, text);
      if (_disposed) return;
      final index = _messages.indexWhere((message) => identical(message, local));
      if (index >= 0) _messages[index] = sent;
    } catch (error) {
      _logger.warn(LogCategory.api, 'chat send failed', {'error': _reason(error)});
      _messages.removeWhere((message) => identical(message, local));
      rethrow;
    } finally {
      _pending.remove(local);
      _notify();
    }
  }

  /// Never the error's text: a transport's names the address.
  static String _reason(Object error) => switch (error) {
    BiliAPIError(:final code) => 'api $code',
    BiliHTTPError(:final status) => 'http $status',
    _ => '${error.runtimeType}',
  };

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
