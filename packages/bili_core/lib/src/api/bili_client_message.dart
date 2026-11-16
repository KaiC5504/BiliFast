part of 'bili_client.dart';

/// 消息's calls on the website's endpoints, with the web login's cookies: the red counts, the msgfeed lists, the
/// 私信 sessions and messages, 系统通知, and 消息设置.
extension BiliClientMessage on BiliClient {
  /// `/x/msgfeed/unread`.
  Future<FeedUnread> msgfeedUnread() => throw UnimplementedError();

  /// `session_svr/single_unread`: 私信 unread, followed and not.
  Future<int> chatUnread() => throw UnimplementedError();

  /// 回复我的 (`/x/msgfeed/reply`), from [cursor] when given.
  Future<NoticePage<ReplyNotice>> replyNotices({NoticeCursor? cursor}) => throw UnimplementedError();

  /// @我的 (`/x/msgfeed/at`).
  Future<NoticePage<ReplyNotice>> atNotices({NoticeCursor? cursor}) => throw UnimplementedError();

  /// 收到的赞 (`/x/msgfeed/like`).
  Future<NoticePage<LikeNotice>> likeNotices({NoticeCursor? cursor}) => throw UnimplementedError();

  /// 删除 on a msgfeed row (`/x/msgfeed/del`).
  Future<void> deleteNotice(NoticeFeed feed, int id) => throw UnimplementedError();

  /// 不再通知 on a msgfeed row (`/x/msgfeed/notice`).
  Future<void> setNoticeNotify(NoticeFeed feed, int id, {required bool on}) => throw UnimplementedError();

  /// The 私信 sessions (`session_svr/get_sessions`), newest first, before [endTs] when given. Names and faces are
  /// left for [chatUserCards] where the answer has none.
  Future<ChatSessionPage> chatSessions({int? endTs}) => throw UnimplementedError();

  /// `account/v1/user/cards` for [mids].
  Future<List<ChatUserCard>> chatUserCards(List<int> mids) => throw UnimplementedError();

  /// A session's messages (`svr_sync/fetch_session_msgs`), the newest page, or the one before [beforeSeqno].
  Future<ChatMessagePage> chatMessages(int talkerId, {int sessionType = 1, int? beforeSeqno}) =>
      throw UnimplementedError();

  /// Marks a session read up to [seqno] (`session_svr/update_ack`, a GET that writes).
  Future<void> ackChat(int talkerId, {required int seqno, int sessionType = 1}) => throw UnimplementedError();

  /// Sends [text] (emote codes among it) to [talkerId] as [senderMid] (`web_im/send_msg`, WBI-signed).
  Future<ChatMessage> sendChatText({required int senderMid, required int talkerId, required String text}) =>
      throw UnimplementedError();

  /// 系统通知 (`sys-msg/query_notify_list`), the newest page or the one before [cursor]; each as a
  /// [ChatMessageKind.notice] whose [ChatMessage.seqno] is its cursor.
  Future<ChatMessagePage> systemNotices({int? cursor}) => throw UnimplementedError();

  /// Marks 系统通知 read up to [cursor] (`sys-msg/update_cursor`, a GET that writes).
  Future<void> ackSystemNotices(int cursor) => throw UnimplementedError();

  /// 一键已读 (211).
  Future<void> readAllMessages() => throw UnimplementedError();

  /// The bar over a chat (`link_setting/get_session_ss`).
  Future<ChatSettings> chatSettings(int talkerId) => throw UnimplementedError();

  /// 不接受推送 (`link_setting/set_push_ss`).
  Future<void> setChatPush(int talkerId, {required bool on}) => throw UnimplementedError();

  /// 消息设置's 回复与@, 收到喜欢 and 新增粉丝; throws [UnsupportedError] when no call for them is known.
  Future<Map<NoticeSettingKind, NoticeAudience>> noticeSettings() => throw UnimplementedError();

  Future<void> setNoticeSetting(NoticeSettingKind kind, NoticeAudience audience) => throw UnimplementedError();
}
