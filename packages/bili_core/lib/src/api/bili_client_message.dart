part of 'bili_client.dart';

const _messageVc = 'https://api.vc.bilibili.com';
const _messageCenter = 'https://message.bilibili.com';
const _messageReferer = 'https://message.bilibili.com/';
const _messageWeb = {'build': '0', 'mobi_app': 'web'};
const _chatPageSize = 20;
const _systemNoticePageSize = 20;

/// send_msg's `dev_id`: the website makes one UUID and keeps it, so each client keeps its own.
final _chatDeviceIds = Expando<String>('chat dev_id');

/// 消息's calls on the website's endpoints, with the web login's cookies: the red counts, the msgfeed lists, the
/// 私信 sessions and messages, 系统通知, and 消息设置. Each is asked as message.bilibili.com asks it (2026-11).
extension BiliClientMessage on BiliClient {
  /// `/x/msgfeed/unread`.
  Future<FeedUnread> msgfeedUnread() => get(
    '/x/msgfeed/unread',
    query: _messageWeb,
    signed: false,
    referer: _messageReferer,
    decode: MessageDecode.feedUnread,
  );

  /// `session_svr/single_unread`: 私信 unread, followed and not.
  Future<int> chatUnread() => get(
    '/session_svr/v1/session_svr/single_unread',
    query: {'unread_type': '0', ..._messageWeb},
    signed: false,
    host: _messageVc,
    referer: _messageReferer,
    decode: MessageDecode.chatUnread,
  );

  /// 回复我的 (`/x/msgfeed/reply`), from [cursor] when given.
  Future<NoticePage<ReplyNotice>> replyNotices({NoticeCursor? cursor}) => get(
    '/x/msgfeed/reply',
    query: _feedQuery(cursor, 'reply_time'),
    signed: false,
    referer: _messageReferer,
    decode: (json) => MessageDecode.replies(json, NoticeFeed.reply),
  );

  /// @我的 (`/x/msgfeed/at`).
  Future<NoticePage<ReplyNotice>> atNotices({NoticeCursor? cursor}) => get(
    '/x/msgfeed/at',
    query: _feedQuery(cursor, 'at_time'),
    signed: false,
    referer: _messageReferer,
    decode: (json) => MessageDecode.replies(json, NoticeFeed.at),
  );

  /// 收到的赞 (`/x/msgfeed/like`).
  Future<NoticePage<LikeNotice>> likeNotices({NoticeCursor? cursor}) => get(
    '/x/msgfeed/like',
    query: _feedQuery(cursor, 'like_time'),
    signed: false,
    referer: _messageReferer,
    decode: (json) => MessageDecode.likes(json, firstPage: cursor == null),
  );

  /// 删除 on a msgfeed row (`/x/msgfeed/del`).
  Future<void> deleteNotice(NoticeFeed feed, int id) async => postVoid(
    '/x/msgfeed/del',
    form: {'tp': _noticeTp(feed), 'id': '$id', ..._messageWeb, 'csrf_token': _messageCsrf()},
    referer: _messageReferer,
  );

  /// 不再通知 on a msgfeed row (`/x/msgfeed/notice`). The website offers it on likes only, as `tp` 0; replies and
  /// mentions send `del`'s `tp` (1, 2), which no capture has confirmed.
  Future<void> setNoticeNotify(NoticeFeed feed, int id, {required bool on}) async => postVoid(
    '/x/msgfeed/notice',
    form: {
      'tp': _noticeTp(feed),
      'id': '$id',
      'notice_state': on ? '0' : '1',
      'platform': 'web',
      ..._messageWeb,
      'csrf_token': _messageCsrf(),
    },
    referer: _messageReferer,
  );

  /// The 私信 sessions (`session_svr/get_sessions`), newest first, before [endTs] when given. Names and faces are
  /// left for [chatUserCards] where the answer has none.
  Future<ChatSessionPage> chatSessions({int? endTs}) => get(
    '/session_svr/v1/session_svr/get_sessions',
    query: {
      'session_type': '1',
      'group_fold': '1',
      'unfollow_fold': '0',
      'sort_rule': '2',
      'end_ts': ?endTs?.toString(),
      ..._messageWeb,
    },
    signed: true,
    host: _messageVc,
    referer: _messageReferer,
    decode: MessageDecode.sessions,
  );

  /// `x/im/user_infos` for [mids]; none asks nothing.
  Future<List<ChatUserCard>> chatUserCards(List<int> mids) async {
    if (mids.isEmpty) return const [];
    return await _messageRead(
          '/x/im/user_infos',
          query: {'uids': mids.join(','), ..._messageWeb},
          host: _messageVc,
          decode: MessageDecode.userCards,
        ) ??
        const [];
  }

  /// A session's messages (`svr_sync/fetch_session_msgs`), the newest page, or the one before [beforeSeqno].
  Future<ChatMessagePage> chatMessages(int talkerId, {int sessionType = 1, int? beforeSeqno}) => get(
    '/svr_sync/v1/svr_sync/fetch_session_msgs',
    query: {
      'talker_id': '$talkerId',
      'session_type': '$sessionType',
      'size': '$_chatPageSize',
      'end_seqno': ?beforeSeqno?.toString(),
      'sender_device_id': '1',
      ..._messageWeb,
    },
    signed: true,
    host: _messageVc,
    referer: _messageReferer,
    decode: MessageDecode.messages,
  );

  /// Marks a session read up to [seqno] (`session_svr/update_ack`). The website posts it as a form; PiliPlus's GET of
  /// the same path is in the PC guard's GET writes too.
  Future<void> ackChat(int talkerId, {required int seqno, int sessionType = 1}) async => postVoid(
    '/session_svr/v1/session_svr/update_ack',
    form: {
      'talker_id': '$talkerId',
      'session_type': '$sessionType',
      'ack_seqno': '$seqno',
      ..._messageWeb,
      'csrf_token': _messageCsrf(),
    },
    host: _messageVc,
    referer: _messageReferer,
  );

  /// Sends [text] (emote codes among it) to [talkerId] as [senderMid] (`web_im/send_msg`). As on the website, the
  /// WBI signature covers the URL's `w_` fields; the message goes in the form.
  Future<ChatMessage> sendChatText({required int senderMid, required int talkerId, required String text}) async {
    if (text.trim().isEmpty) throw ArgumentError('nothing to send');
    final devId = _chatDeviceIds[this] ??= _newChatDeviceId();
    final sentAt = _unixSeconds;
    final envelope = await _postEnvelope(
      '/web_im/v1/web_im/send_msg',
      query: {'w_sender_uid': '$senderMid', 'w_receiver_id': '$talkerId', 'w_dev_id': devId},
      signed: true,
      form: {
        'msg[sender_uid]': '$senderMid',
        'msg[receiver_id]': '$talkerId',
        'msg[receiver_type]': '1',
        'msg[msg_type]': '1',
        'msg[msg_status]': '0',
        'msg[dev_id]': devId,
        'msg[timestamp]': '$sentAt',
        'msg[new_face_version]': '1',
        'msg[content]': jsonEncode({'content': text}),
        'from_firework': '0',
        ..._messageWeb,
        'csrf_token': _messageCsrf(),
      },
      host: _messageVc,
      referer: _messageReferer,
      decode: (json) => MessageDecode.sent(
        json,
        senderMid: senderMid,
        text: text,
        time: DateTime.fromMillisecondsSinceEpoch(sentAt * 1000),
      ),
    );
    return _checked(envelope);
  }

  /// 系统通知 (`sys-msg/query_notify_list`), the newest page or the one before [cursor]; each as a
  /// [ChatMessageKind.notice] whose [ChatMessage.seqno] is its cursor. (The website's own first page merges
  /// `query_unified_notify` and `query_user_notify`; this list pages the same notices, as PiliPlus reads them.)
  Future<ChatMessagePage> systemNotices({int? cursor}) async =>
      await _messageRead(
        '/x/sys-msg/query_notify_list',
        query: {'cursor': ?cursor?.toString(), 'page_size': '$_systemNoticePageSize', ..._messageWeb},
        host: _messageCenter,
        decode: (json) => MessageDecode.systemNotices(json, pageSize: _systemNoticePageSize),
      ) ??
      const ChatMessagePage(messages: []);

  /// Marks 系统通知 read up to [cursor] (`sys-msg/update_cursor`, a GET that writes).
  Future<void> ackSystemNotices(int cursor) async {
    await _messageRead(
      '/x/sys-msg/update_cursor',
      query: {'cursor': '$cursor', 'has_up': '0', ..._messageWeb, 'csrf': _messageCsrf()},
      host: _messageCenter,
      decode: (_) => null,
    );
  }

  /// 一键已读 (211). The official app clears everything with its gRPC `ClearUnread`; the website has no one call, so
  /// this does what its pages do when opened: acks every session on the first page that has unread messages up to
  /// its `max_seqno`, moves 系统通知's cursor to its newest notice, and reads the first page of each msgfeed list that
  /// has unread items, which is all the website does to clear those. Sessions past the first page keep their counts.
  /// It stops at the first failure.
  Future<void> readAllMessages() async {
    final feed = await msgfeedUnread();
    final sessions = await chatSessions();
    for (final session in sessions.sessions) {
      if (session.unread <= 0 || session.maxSeqno <= 0) continue;
      await ackChat(session.talkerId, seqno: session.maxSeqno, sessionType: session.sessionType);
    }
    if (feed.system > 0) {
      final newest = (await systemNotices()).maxSeqno;
      if (newest > 0) await ackSystemNotices(newest);
    }
    if (feed.reply > 0) await replyNotices();
    if (feed.at > 0) await atNotices();
    if (feed.like > 0) await likeNotices();
  }

  /// The bar over a chat (`link_setting/get_session_ss`).
  Future<ChatSettings> chatSettings(int talkerId) => get(
    '/link_setting/v1/link_setting/get_session_ss',
    query: {'talker_uid': '$talkerId', ..._messageWeb},
    signed: false,
    host: _messageVc,
    referer: _messageReferer,
    decode: MessageDecode.chatSettings,
  );

  /// 不接受推送 (`link_setting/set_push_ss`).
  Future<void> setChatPush(int talkerId, {required bool on}) async => postVoid(
    '/link_setting/v1/link_setting/set_push_ss',
    form: {'talker_uid': '$talkerId', 'setting': on ? '0' : '1', ..._messageWeb, 'csrf_token': _messageCsrf()},
    host: _messageVc,
    referer: _messageReferer,
  );

  /// 消息设置's 回复与@, 收到喜欢 and 新增粉丝 (`link_setting/get`'s `set_recv_reply`, `set_recv_like`,
  /// `set_new_follow`); a setting the answer leaves out is missing from the map.
  Future<Map<NoticeSettingKind, NoticeAudience>> noticeSettings() => get(
    '/link_setting/v1/link_setting/get',
    query: _messageWeb,
    signed: false,
    host: _messageVc,
    referer: _messageReferer,
    decode: MessageDecode.noticeSettings,
  );

  /// One picker's choice (`link_setting/set`), the other settings untouched.
  Future<void> setNoticeSetting(NoticeSettingKind kind, NoticeAudience audience) async => postVoid(
    '/link_setting/v1/link_setting/set',
    form: {
      MessageDecode.settingField(kind): MessageDecode.audienceValue(audience),
      ..._messageWeb,
      'csrf_token': _messageCsrf(),
    },
    host: _messageVc,
    referer: _messageReferer,
  );

  Map<String, String> _feedQuery(NoticeCursor? cursor, String timeField) => {
    if (cursor != null) ...{'id': '${cursor.id}', timeField: '${cursor.time}'},
    'platform': 'web',
    ..._messageWeb,
  };

  /// The website's write forms carry the csrf token twice, as `csrf` (which `_send` adds) and `csrf_token`.
  String _messageCsrf() => csrf ?? (throw const BiliError.api(code: -101, message: '账号未登录'));

  /// A read whose success may carry no `data`, or a list.
  Future<T?> _messageRead<T>(
    String path, {
    required Map<String, String> query,
    required String host,
    required JsonDecode<T> decode,
  }) async {
    final envelope = await _getEnvelope(
      path,
      query: query,
      signed: false,
      host: host,
      referer: _messageReferer,
      decode: decode,
    );
    if (envelope.code != 0) throw BiliError.api(code: envelope.code, message: envelope.message ?? '');
    return envelope.data;
  }
}

/// `/x/msgfeed/del`'s `tp`, as the website sends it per list.
String _noticeTp(NoticeFeed feed) => switch (feed) {
  NoticeFeed.like => '0',
  NoticeFeed.reply => '1',
  NoticeFeed.at => '2',
};

/// A version 4 UUID in capitals, as the website's `dev_id`.
String _newChatDeviceId() {
  final bytes = [for (var i = 0; i < 16; i++) BiliClient._random.nextInt(256)];
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = [for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0')].join().toUpperCase();
  return [
    hex.substring(0, 8),
    hex.substring(8, 12),
    hex.substring(12, 16),
    hex.substring(16, 20),
    hex.substring(20),
  ].join('-');
}
