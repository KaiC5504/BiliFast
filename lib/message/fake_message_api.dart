import 'dart:async';

import 'package:bili_core/api.dart';

import 'message_api.dart';

/// Made-up answers for tests and `--fake-account` on the PC: no call leaves the machine. Lists page by [pageSize];
/// writes change what later reads answer. [calls] lists what was asked, in order (never a message's text);
/// [failures] makes a call throw, [holds] keeps it waiting; both are keyed by the method's name.
class FakeMessageApi implements MessageApi {
  FakeMessageApi({
    this.counts = const MessageUnread(),
    List<ReplyNotice> replyList = const [],
    List<ReplyNotice> mentionList = const [],
    List<LikeNotice> likeList = const [],
    this.fanList = const [],
    List<ChatSession> sessionList = const [],
    Map<int, List<ChatMessage>>? chats,
    Map<int, ChatSettings>? chatSettingsOf,
    Map<NoticeSettingKind, NoticeAudience>? settings,
    this.selfMid = 1,
    this.pageSize = 20,
  }) : replyList = [...replyList],
       mentionList = [...mentionList],
       likeList = [...likeList],
       sessionList = [...sessionList],
       chats = {for (final entry in (chats ?? const {}).entries) entry.key: [...entry.value]},
       chatSettingsOf = {...?chatSettingsOf},
       settings = {
         for (final kind in NoticeSettingKind.values) kind: NoticeAudience.everyone,
         ...?settings,
       };

  /// The `--fake-account` demo.
  factory FakeMessageApi.demo() => FakeMessageApi();

  MessageUnread counts;
  final List<ReplyNotice> replyList;
  final List<ReplyNotice> mentionList;
  final List<LikeNotice> likeList;
  final List<RelationUser> fanList;
  final List<ChatSession> sessionList;

  /// Each session's messages by talker, oldest first; 系统通知's under 0.
  final Map<int, List<ChatMessage>> chats;
  final Map<int, ChatSettings> chatSettingsOf;
  final Map<NoticeSettingKind, NoticeAudience> settings;
  final int selfMid;
  final int pageSize;

  final calls = <String>[];
  final failures = <String, Object>{};
  final holds = <String, Completer<void>>{};

  /// Messages sent, in order.
  final sent = <({int talkerId, String text})>[];

  /// Notices muted with 不再通知, in order.
  final muted = <({NoticeFeed feed, int id})>[];

  /// Sessions marked read, in order.
  final reads = <({int talkerId, int seqno})>[];

  final follows = <({int mid, bool on})>[];
  final pushes = <({int talkerId, bool on})>[];

  Future<T> _answer<T>(String name, String call, T Function() answer) async {
    calls.add(call);
    if (holds[name] case final hold?) await hold.future;
    if (failures[name] case final failure?) throw failure;
    return answer();
  }

  /// Rows after [cursor] (by id, as the lists are newest first), a page of them, and the next cursor.
  NoticePage<T> _notices<T>(List<T> all, NoticeCursor? cursor, int Function(T) id, DateTime Function(T) time) {
    final start = cursor == null ? 0 : all.indexWhere((item) => id(item) == cursor.id) + 1;
    final end = (start + pageSize).clamp(0, all.length);
    final items = start >= all.length ? <T>[] : all.sublist(start, end);
    return NoticePage(
      items: items,
      next: end < all.length && items.isNotEmpty
          ? NoticeCursor(id: id(items.last), time: time(items.last).millisecondsSinceEpoch ~/ 1000)
          : null,
    );
  }

  @override
  Future<MessageUnread> unread() => _answer('unread', 'unread', () => counts);

  @override
  Future<NoticePage<ReplyNotice>> replies({NoticeCursor? cursor}) => _answer(
    'replies',
    'replies ${cursor?.id ?? 0}',
    () => _notices(replyList, cursor, (item) => item.id, (item) => item.time),
  );

  @override
  Future<NoticePage<ReplyNotice>> mentions({NoticeCursor? cursor}) => _answer(
    'mentions',
    'mentions ${cursor?.id ?? 0}',
    () => _notices(mentionList, cursor, (item) => item.id, (item) => item.time),
  );

  @override
  Future<NoticePage<LikeNotice>> likes({NoticeCursor? cursor}) => _answer(
    'likes',
    'likes ${cursor?.id ?? 0}',
    () => _notices(likeList, cursor, (item) => item.id, (item) => item.time),
  );

  @override
  Future<void> deleteNotice(NoticeFeed feed, int id) => _answer('deleteNotice', 'deleteNotice ${feed.name} $id', () {
    switch (feed) {
      case NoticeFeed.reply:
        replyList.removeWhere((item) => item.id == id);
      case NoticeFeed.at:
        mentionList.removeWhere((item) => item.id == id);
      case NoticeFeed.like:
        likeList.removeWhere((item) => item.id == id);
    }
  });

  @override
  Future<void> muteNotice(NoticeFeed feed, int id) =>
      _answer('muteNotice', 'muteNotice ${feed.name} $id', () => muted.add((feed: feed, id: id)));

  @override
  Future<RelationPage> newFans(int mid, {required int page}) => _answer('newFans', 'newFans page=$page', () {
    final start = (page - 1) * pageSize;
    final end = (start + pageSize).clamp(0, fanList.length);
    return RelationPage(
      users: start >= fanList.length ? const [] : fanList.sublist(start, end),
      total: fanList.length,
      hasMore: end < fanList.length,
    );
  });

  @override
  Future<ChatSessionPage> sessions({int? next}) => _answer('sessions', 'sessions ${next ?? 0}', () {
    final ordered = [...sessionList]..sort((a, b) => b.time.compareTo(a.time));
    final start = next == null ? 0 : ordered.indexWhere((session) => session.time.millisecondsSinceEpoch < next);
    if (start < 0) return const ChatSessionPage(sessions: []);
    final end = (start + pageSize).clamp(0, ordered.length);
    final page = ordered.sublist(start, end);
    return ChatSessionPage(
      sessions: page,
      next: end < ordered.length ? page.last.time.millisecondsSinceEpoch : null,
    );
  });

  int _chatKey(ChatSession session) => session.box == NoticeBox.system ? 0 : session.talkerId;

  @override
  Future<ChatMessagePage> messages(ChatSession session, {int? beforeSeqno}) =>
      _answer('messages', 'messages ${session.talkerId} ${beforeSeqno ?? 0}', () {
        final all = chats[_chatKey(session)] ?? const <ChatMessage>[];
        final older = [
          for (final message in all)
            if (beforeSeqno == null || message.seqno < beforeSeqno) message,
        ];
        final start = (older.length - pageSize).clamp(0, older.length);
        final page = older.sublist(start);
        return ChatMessagePage(
          messages: page,
          hasMore: start > 0,
          minSeqno: page.isEmpty ? 0 : page.first.seqno,
          maxSeqno: page.isEmpty ? 0 : page.last.seqno,
        );
      });

  @override
  Future<void> read(ChatSession session, {required int seqno}) =>
      _answer('read', 'read ${session.talkerId} $seqno', () {
        reads.add((talkerId: session.talkerId, seqno: seqno));
        final index = sessionList.indexWhere((each) => each.talkerId == session.talkerId);
        if (index >= 0) sessionList[index] = sessionList[index].copyWith(unread: 0, ackSeqno: seqno);
      });

  @override
  Future<ChatMessage> send(int talkerId, String text) => _answer('send', 'send $talkerId', () {
    sent.add((talkerId: talkerId, text: text));
    final list = chats.putIfAbsent(talkerId, () => []);
    final message = ChatMessage(
      seqno: (list.isEmpty ? 0 : list.last.seqno) + 1,
      key: sent.length,
      senderMid: selfMid,
      kind: ChatMessageKind.text,
      text: text,
      time: DateTime.now(),
    );
    list.add(message);
    return message;
  });

  @override
  Future<void> readAll() => _answer('readAll', 'readAll', () {
    counts = const MessageUnread();
    for (var i = 0; i < sessionList.length; i++) {
      sessionList[i] = sessionList[i].copyWith(unread: 0);
    }
  });

  @override
  Future<ChatSettings> chatSettings(int talkerId) =>
      _answer('chatSettings', 'chatSettings $talkerId', () => chatSettingsOf[talkerId] ?? const ChatSettings());

  @override
  Future<void> setChatPush(int talkerId, {required bool on}) =>
      _answer('setChatPush', 'setChatPush $talkerId $on', () {
        pushes.add((talkerId: talkerId, on: on));
        final was = chatSettingsOf[talkerId] ?? const ChatSettings();
        chatSettingsOf[talkerId] = ChatSettings(following: was.following, pushOn: on, showPush: was.showPush);
      });

  @override
  Future<void> follow(int mid, {required bool on}) => _answer('follow', 'follow $mid $on', () {
    follows.add((mid: mid, on: on));
    final was = chatSettingsOf[mid] ?? const ChatSettings();
    chatSettingsOf[mid] = ChatSettings(following: on, pushOn: was.pushOn, showPush: was.showPush);
  });

  @override
  Future<Map<NoticeSettingKind, NoticeAudience>> noticeSettings() =>
      _answer('noticeSettings', 'noticeSettings', () => {...settings});

  @override
  Future<void> setNoticeSetting(NoticeSettingKind kind, NoticeAudience audience) =>
      _answer('setNoticeSetting', 'setNoticeSetting ${kind.name} ${audience.name}', () => settings[kind] = audience);
}
