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

  /// 不接受推送; throws [UnsupportedError] when no call for it is known.
  Future<void> setChatPush(int talkerId, {required bool on});

  /// 加关注 from a chat's bar, through `/x/relation/modify`.
  Future<void> follow(int mid, {required bool on});

  /// 消息设置's three pickers; throws [UnsupportedError] when no call for them is known.
  Future<Map<NoticeSettingKind, NoticeAudience>> noticeSettings();

  Future<void> setNoticeSetting(NoticeSettingKind kind, NoticeAudience audience);
}

/// [MessageApi] on [BiliClient]; [mid] is the logged-in account's, for sending.
class ClientMessageApi implements MessageApi {
  ClientMessageApi(this._client, {required this.mid});

  // ignore: unused_field
  final BiliClient _client;
  final int Function() mid;

  @override
  Future<MessageUnread> unread() => throw UnimplementedError();

  @override
  Future<NoticePage<ReplyNotice>> replies({NoticeCursor? cursor}) => throw UnimplementedError();

  @override
  Future<NoticePage<ReplyNotice>> mentions({NoticeCursor? cursor}) => throw UnimplementedError();

  @override
  Future<NoticePage<LikeNotice>> likes({NoticeCursor? cursor}) => throw UnimplementedError();

  @override
  Future<void> deleteNotice(NoticeFeed feed, int id) => throw UnimplementedError();

  @override
  Future<void> muteNotice(NoticeFeed feed, int id) => throw UnimplementedError();

  @override
  Future<RelationPage> newFans(int mid, {required int page}) => throw UnimplementedError();

  @override
  Future<ChatSessionPage> sessions({int? next}) => throw UnimplementedError();

  @override
  Future<ChatMessagePage> messages(ChatSession session, {int? beforeSeqno}) => throw UnimplementedError();

  @override
  Future<void> read(ChatSession session, {required int seqno}) => throw UnimplementedError();

  @override
  Future<ChatMessage> send(int talkerId, String text) => throw UnimplementedError();

  @override
  Future<void> readAll() => throw UnimplementedError();

  @override
  Future<ChatSettings> chatSettings(int talkerId) => throw UnimplementedError();

  @override
  Future<void> setChatPush(int talkerId, {required bool on}) => throw UnimplementedError();

  @override
  Future<void> follow(int mid, {required bool on}) => throw UnimplementedError();

  @override
  Future<Map<NoticeSettingKind, NoticeAudience>> noticeSettings() => throw UnimplementedError();

  @override
  Future<void> setNoticeSetting(NoticeSettingKind kind, NoticeAudience audience) => throw UnimplementedError();
}
