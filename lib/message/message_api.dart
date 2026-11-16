import 'package:bili_core/api.dart';

/// 消息's calls: the red counts, 回复与@, 收到喜欢, 新增粉丝, the 私信 sessions and chats, 系统通知 and 消息设置.
abstract interface class MessageApi {
  /// Both red counts: the msgfeed lists' and 私信's.
  Future<MessageUnread> unread();

  /// 回复我的, from [cursor] when given.
  Future<NoticePage<ReplyNotice>> replies({NoticeCursor? cursor});

  /// @我的.
  Future<NoticePage<ReplyNotice>> mentions({NoticeCursor? cursor});

  /// 收到的赞.
  Future<NoticePage<LikeNotice>> likes({NoticeCursor? cursor});

  /// 删除 on a row of 回复与@ or 收到喜欢 (214).
  Future<void> deleteNotice(NoticeFeed feed, int id);

  /// 不再通知 on a row (214).
  Future<void> muteNotice(NoticeFeed feed, int id);

  /// 新增粉丝: the account [mid]'s fans, newest first, page [page] from 1.
  Future<RelationPage> newFans(int mid, {required int page});

  /// The 私信 sessions with their names and faces, newest first; [next] from the page before.
  Future<ChatSessionPage> sessions({int? next});

  /// [session]'s newest messages, or those before [beforeSeqno]; 系统通知's list for [NoticeBox.system].
  Future<ChatMessagePage> messages(ChatSession session, {int? beforeSeqno});

  /// Marks [session] read up to [seqno] (系统通知's cursor for [NoticeBox.system]).
  Future<void> read(ChatSession session, {required int seqno});

  /// Sends [text] to [talkerId]; the message as sent.
  Future<ChatMessage> send(int talkerId, String text);

  /// 一键已读 (211).
  Future<void> readAll();

  /// The bar over a chat (202).
  Future<ChatSettings> chatSettings(int talkerId);

  /// 不接受推送 (`link_setting/set_push_ss`).
  Future<void> setChatPush(int talkerId, {required bool on});

  /// 加关注 from a chat's bar, through `/x/relation/modify`.
  Future<void> follow(int mid, {required bool on});

  /// 消息设置's three pickers (`link_setting/get`).
  Future<Map<NoticeSettingKind, NoticeAudience>> noticeSettings();

  /// One of them (`link_setting/set`).
  Future<void> setNoticeSetting(NoticeSettingKind kind, NoticeAudience audience);
}

/// [MessageApi] on [BiliClient]; [mid] is the logged-in account's, for sending.
class ClientMessageApi implements MessageApi {
  ClientMessageApi(this._client, {required this.mid});

  final BiliClient _client;
  final int Function() mid;

  /// The two calls go out together; when the first fails, the second's answer is let go unheard.
  @override
  Future<MessageUnread> unread() async {
    final feed = _client.msgfeedUnread();
    final chat = _client.chatUnread();
    try {
      return combineUnread(await feed, await chat);
    } catch (_) {
      chat.ignore();
      rethrow;
    }
  }

  @override
  Future<NoticePage<ReplyNotice>> replies({NoticeCursor? cursor}) => _client.replyNotices(cursor: cursor);

  @override
  Future<NoticePage<ReplyNotice>> mentions({NoticeCursor? cursor}) => _client.atNotices(cursor: cursor);

  @override
  Future<NoticePage<LikeNotice>> likes({NoticeCursor? cursor}) => _client.likeNotices(cursor: cursor);

  @override
  Future<void> deleteNotice(NoticeFeed feed, int id) => _client.deleteNotice(feed, id);

  @override
  Future<void> muteNotice(NoticeFeed feed, int id) => _client.setNoticeNotify(feed, id, on: false);

  @override
  Future<RelationPage> newFans(int mid, {required int page}) => _client.fans(mid: mid, page: page);

  /// get_sessions leaves some people bare; one cards call per page names them.
  @override
  Future<ChatSessionPage> sessions({int? next}) async {
    final page = await _client.chatSessions(endTs: next);
    final bare = unnamedTalkers(page.sessions);
    if (bare.isEmpty) return page;
    final cards = await _client.chatUserCards(bare);
    return ChatSessionPage(sessions: namedSessions(page.sessions, cards), next: page.next);
  }

  @override
  Future<ChatMessagePage> messages(ChatSession session, {int? beforeSeqno}) => session.box == NoticeBox.system
      ? _client.systemNotices(cursor: beforeSeqno)
      : _client.chatMessages(session.talkerId, sessionType: session.sessionType, beforeSeqno: beforeSeqno);

  /// A chat already acked that far asks nothing.
  @override
  Future<void> read(ChatSession session, {required int seqno}) async {
    if (session.box == NoticeBox.system) {
      if (seqno > 0) await _client.ackSystemNotices(seqno);
      return;
    }
    if (seqno <= session.ackSeqno) return;
    await _client.ackChat(session.talkerId, seqno: seqno, sessionType: session.sessionType);
  }

  @override
  Future<ChatMessage> send(int talkerId, String text) =>
      _client.sendChatText(senderMid: mid(), talkerId: talkerId, text: text);

  @override
  Future<void> readAll() => _client.readAllMessages();

  @override
  Future<ChatSettings> chatSettings(int talkerId) => _client.chatSettings(talkerId);

  @override
  Future<void> setChatPush(int talkerId, {required bool on}) => _client.setChatPush(talkerId, on: on);

  @override
  Future<void> follow(int mid, {required bool on}) => _client.follow(mid: mid, on: on);

  @override
  Future<Map<NoticeSettingKind, NoticeAudience>> noticeSettings() => _client.noticeSettings();

  @override
  Future<void> setNoticeSetting(NoticeSettingKind kind, NoticeAudience audience) =>
      _client.setNoticeSetting(kind, audience);

  static MessageUnread combineUnread(FeedUnread feed, int chat) =>
      MessageUnread(reply: feed.reply, at: feed.at, like: feed.like, system: feed.system, chat: chat);

  /// The people [sessions] has no name for, once each. Group sessions are left out: their talker is a group, not a
  /// person a card could name.
  static List<int> unnamedTalkers(List<ChatSession> sessions) => {
    for (final session in sessions)
      if (session.name.isEmpty && session.sessionType == 1 && session.talkerId > 0) session.talkerId,
  }.toList();

  /// [sessions] with the bare ones named from [cards]; what a session has of its own stays.
  static List<ChatSession> namedSessions(List<ChatSession> sessions, List<ChatUserCard> cards) {
    final byMid = {for (final card in cards) card.mid: card};
    return [
      for (final session in sessions)
        switch (byMid[session.talkerId]) {
          final card? when session.name.isEmpty && session.sessionType == 1 => _named(session, card),
          _ => session,
        },
    ];
  }

  static ChatSession _named(ChatSession session, ChatUserCard card) => ChatSession(
    talkerId: session.talkerId,
    sessionType: session.sessionType,
    name: card.name,
    face: session.face.isEmpty ? card.face : session.face,
    lastText: session.lastText,
    time: session.time,
    unread: session.unread,
    ackSeqno: session.ackSeqno,
    maxSeqno: session.maxSeqno,
    top: session.top,
    box: session.box,
    vipPink: session.vipPink || card.vipPink,
    bigVip: session.bigVip || card.bigVip,
    verify: session.verify == DynamicVerify.none ? card.verify : session.verify,
    pendant: session.pendant.isEmpty ? card.pendant : session.pendant,
  );
}
