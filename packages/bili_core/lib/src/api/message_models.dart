/// 消息's lists: the red counts, 回复与@, 收到喜欢, the 私信 sessions and their messages, and the 消息设置 pickers.
/// The website's calls with the web login's cookies (`/x/msgfeed/…`, `api.vc.bilibili.com`'s session and IM calls).
library;

import 'dart:convert';

import 'dynamic_models.dart' show DynamicVerify;
import 'json.dart';

/// What the red badges count (`/x/msgfeed/unread` and `session_svr/single_unread`).
final class MessageUnread {
  const MessageUnread({this.reply = 0, this.at = 0, this.like = 0, this.system = 0, this.chat = 0});

  final int reply;
  final int at;
  final int like;

  /// 系统通知 (`sys_msg`).
  final int system;

  /// 私信 unread across every session, followed or not.
  final int chat;

  int get total => reply + at + like + system + chat;

  MessageUnread copyWith({int? reply, int? at, int? like, int? system, int? chat}) => MessageUnread(
    reply: reply ?? this.reply,
    at: at ?? this.at,
    like: like ?? this.like,
    system: system ?? this.system,
    chat: chat ?? this.chat,
  );

  @override
  bool operator ==(Object other) =>
      other is MessageUnread &&
      other.reply == reply &&
      other.at == at &&
      other.like == like &&
      other.system == system &&
      other.chat == chat;

  @override
  int get hashCode => Object.hash(reply, at, like, system, chat);
}

/// `/x/msgfeed/unread`'s part of [MessageUnread].
typedef FeedUnread = ({int reply, int at, int like, int system});

/// Someone in a notice: who replied, mentioned or liked.
final class NoticeUser {
  const NoticeUser({required this.mid, required this.name, required this.face, this.following = false});

  final int mid;
  final String name;
  final String face;

  /// The account follows them (`follow`).
  final bool following;
}

/// The three msgfeed lists.
enum NoticeFeed { reply, at, like }

/// Where the next page of a msgfeed list starts: the last item's `id` and its time (`reply_time`, `at_time`,
/// `like_time`), as the answer's `cursor` gives them.
final class NoticeCursor {
  const NoticeCursor({required this.id, required this.time});

  final int id;
  final int time;
}

/// A page of a msgfeed list; [next] is null at the end (`cursor.is_end`).
final class NoticePage<T> {
  const NoticePage({required this.items, this.next});

  final List<T> items;
  final NoticeCursor? next;
}

/// One row of 回复与@ (197): a reply to the account (or, under @我, a mention) and what it was on.
final class ReplyNotice {
  const ReplyNotice({
    required this.id,
    required this.feed,
    required this.user,
    required this.business,
    required this.businessId,
    required this.subjectId,
    required this.rootId,
    required this.sourceId,
    required this.targetId,
    required this.text,
    required this.time,
    this.targetText = '',
    this.title = '',
    this.image = '',
    this.uri = '',
    this.nativeUri = '',
    this.fromUploader = false,
    this.liked = false,
    this.canReply = true,
    this.canLike = true,
  });

  /// The notice's own id (删除 and the cursor).
  final int id;

  /// [NoticeFeed.reply] or [NoticeFeed.at].
  final NoticeFeed feed;
  final NoticeUser user;

  /// `item.type`: what was replied to or mentioned in (`reply` a comment, `video`, `dynamic`, `article`, …).
  final String business;

  /// `item.business_id`: the comment area's type (1 a video, 11 and 17 a post, 12 an article…).
  final int businessId;

  /// `item.subject_id`: the comment area's oid (the video's aid, the post's id).
  final int subjectId;

  /// `item.root_id`: the thread's root comment; 0 when the reply is itself a root.
  final int rootId;

  /// `item.source_id`: the reply's own rpid, the one 回复 and 点赞 act on.
  final int sourceId;

  /// `item.target_id`: the comment that was replied to.
  final int targetId;

  /// What they wrote (`source_content`), emote codes such as [doge] left as text, as 197 shows them.
  final String text;

  /// The account's comment that was replied to (`target_reply_content`, else `root_reply_content`), shown at the
  /// right (197); empty when the subject is shown by [title] or [image].
  final String targetText;

  /// `item.title`: the video's or post's title.
  final String title;

  /// `item.image`: the subject's picture, shown at the right in place of [targetText] where there is one.
  final String image;

  /// `item.uri` and `item.native_uri`: where a tap leads (the video page on 评论, the post).
  final String uri;
  final String nativeUri;

  /// The replier is the subject's uploader (197's UP tag).
  final bool fromUploader;

  /// The account has liked the reply (`like_state`).
  final bool liked;

  /// `hide_reply_button` and `hide_like_button`, turned round.
  final bool canReply;
  final bool canLike;

  final DateTime time;

  ReplyNotice copyWith({bool? liked}) => ReplyNotice(
    id: id,
    feed: feed,
    user: user,
    business: business,
    businessId: businessId,
    subjectId: subjectId,
    rootId: rootId,
    sourceId: sourceId,
    targetId: targetId,
    text: text,
    time: time,
    targetText: targetText,
    title: title,
    image: image,
    uri: uri,
    nativeUri: nativeUri,
    fromUploader: fromUploader,
    liked: liked ?? this.liked,
    canReply: canReply,
    canLike: canLike,
  );
}

/// One row of 收到喜欢 (198): the latest likers of one thing and how many liked it in all.
final class LikeNotice {
  const LikeNotice({
    required this.id,
    required this.users,
    required this.count,
    required this.business,
    required this.time,
    this.itemId = 0,
    this.title = '',
    this.image = '',
    this.uri = '',
    this.nativeUri = '',
    this.notifying = true,
  });

  final int id;

  /// The latest likers, newest first (198 draws two).
  final List<NoticeUser> users;

  /// Everyone who liked it (`counts`): 等总计N人.
  final int count;

  /// `item.business`: 评论, 弹幕, 视频, 动态 (198's 我的评论, 我的弹幕).
  final String business;

  /// `item.item_id`, for its likers' list.
  final int itemId;

  /// What was liked, shown at the right: the comment's or danmaku's text, or a title.
  final String title;
  final String image;
  final String uri;
  final String nativeUri;

  /// New likes on it still notify (`notice_state` 0); 不再通知 turns it off.
  final bool notifying;

  final DateTime time;
}

/// The official notice boxes: 196's pink rows and 212's ⋮ entries. [system] is 系统通知's own list
/// (`sys-msg/query_notify_list`); the others are sessions with an official account.
enum NoticeBox {
  service('服务通知'),
  community('社区中心'),
  system('系统通知'),
  creator('创作助手');

  const NoticeBox(this.label);

  final String label;
}

/// A row of 消息's session list (196).
final class ChatSession {
  const ChatSession({
    required this.talkerId,
    required this.name,
    required this.face,
    required this.lastText,
    required this.time,
    this.sessionType = 1,
    this.unread = 0,
    this.ackSeqno = 0,
    this.maxSeqno = 0,
    this.topTs = 0,
    this.box,
    this.vipPink = false,
    this.bigVip = false,
    this.verify = DynamicVerify.none,
    this.pendant = '',
  });

  /// The other side's mid, or the official account's.
  final int talkerId;

  /// `session_type`: 1 a person, 2 a group.
  final int sessionType;
  final String name;
  final String face;

  /// The last message as the list shows it: text, [图片], [自动回复] … (196).
  final String lastText;
  final DateTime time;
  final int unread;

  /// `ack_seqno` and `max_seqno`: reading the session acks up to [maxSeqno] (`update_ack`).
  final int ackSeqno;
  final int maxSeqno;

  /// When it was 置顶 (`top_ts`, in microseconds), 0 for a session not pinned.
  final int topTs;

  /// 置顶.
  bool get top => topTs > 0;

  /// One of the official notice boxes, drawn with its pink icon (196's 服务通知, 社区中心); null for a person.
  final NoticeBox? box;

  /// 大会员's pink name, and the 大 badge on the face.
  final bool vipPink;
  final bool bigVip;
  final DynamicVerify verify;

  /// The face's frame (`pendant.image`), empty for none.
  final String pendant;

  ChatSession copyWith({int? unread, int? ackSeqno, String? lastText, DateTime? time, int? topTs}) => ChatSession(
    talkerId: talkerId,
    sessionType: sessionType,
    name: name,
    face: face,
    lastText: lastText ?? this.lastText,
    time: time ?? this.time,
    unread: unread ?? this.unread,
    ackSeqno: ackSeqno ?? this.ackSeqno,
    maxSeqno: maxSeqno,
    topTs: topTs ?? this.topTs,
    box: box,
    vipPink: vipPink,
    bigVip: bigVip,
    verify: verify,
    pendant: pendant,
  );
}

/// A page of [ChatSession]s, newest first; [next] is the `end_ts` to ask the next page from, null at the end.
final class ChatSessionPage {
  const ChatSessionPage({required this.sessions, this.next});

  final List<ChatSession> sessions;
  final int? next;
}

/// A person's card (`x/im/user_infos`), naming the sessions get_sessions leaves bare.
final class ChatUserCard {
  const ChatUserCard({
    required this.mid,
    required this.name,
    required this.face,
    this.vipPink = false,
    this.bigVip = false,
    this.verify = DynamicVerify.none,
    this.pendant = '',
  });

  final int mid;
  final String name;
  final String face;
  final bool vipPink;
  final bool bigVip;
  final DynamicVerify verify;
  final String pendant;
}

/// What a message draws as (`msg_type`).
enum ChatMessageKind {
  /// 1: text, emote codes among it.
  text,

  /// 2: a picture.
  picture,

  /// 10: an official notice card (200, 201): [ChatMessage.title], [ChatMessage.text], [ChatMessage.fields] and
  /// [ChatMessage.links].
  notice,

  /// A message its sender took back (撤回, `msg_status` 1), drawn as 对方/你撤回了一条消息 without its text. The take-back
  /// itself (`msg_type` 5) isn't listed, as on the website.
  withdrawn,

  /// 18 and other grey lines in the middle (202's 对方主动回复或关注你前，最多发送1条消息).
  tip,

  /// Anything else; drawn as its [ChatMessage.text] when there is one.
  other,
}

/// One message of a session (`fetch_session_msgs`), or one 系统通知.
final class ChatMessage {
  const ChatMessage({
    required this.seqno,
    required this.senderMid,
    required this.kind,
    required this.time,
    this.key = 0,
    this.text = '',
    this.title = '',
    this.fields = const [],
    this.links = const [],
    this.picture = '',
    this.pictureWidth = 0,
    this.pictureHeight = 0,
    this.emotes = const {},
    this.autoReply = false,
  });

  /// `msg_seqno`: the message's place in the session, the ack and the paging go by it. 0 for a message just sent
  /// (send_msg's answer has none) until the session is fetched again; a 系统通知's cursor.
  final int seqno;

  /// `msg_key`.
  final int key;
  final int senderMid;
  final ChatMessageKind kind;

  /// The text: a text message's, a notice card's body, a tip's line.
  final String text;

  /// A notice card's title (200's 收到个性装扮成功通知).
  final String title;

  /// A notice card's labelled lines (200's 有效期 永久有效).
  final List<({String title, String detail})> fields;

  /// A notice card's buttons (200's 立即查看, 更多个性装扮), each with where it leads.
  final List<({String text, String uri})> links;

  /// A picture message's address and size.
  final String picture;
  final int pictureWidth;
  final int pictureHeight;

  /// The emote codes in [text] and their pictures (`e_infos`).
  final Map<String, String> emotes;

  /// Sent by the other side's 自动回复 (203's 此条消息为自动回复).
  final bool autoReply;

  final DateTime time;
}

/// A page of a session's messages, oldest first; [hasMore] when older ones are left before [minSeqno].
final class ChatMessagePage {
  const ChatMessagePage({required this.messages, this.hasMore = false, this.minSeqno = 0, this.maxSeqno = 0});

  final List<ChatMessage> messages;
  final bool hasMore;
  final int minSeqno;
  final int maxSeqno;
}

/// The bar over a chat (202): 加关注, and whether the session's messages notify (`get_session_ss`).
final class ChatSettings {
  const ChatSettings({this.following = false, this.pushOn = true, this.showPush = true});

  final bool following;
  final bool pushOn;

  /// The answer offers the push switch at all (`show_push_setting`).
  final bool showPush;
}

/// 消息设置's pickers (188's 回复与@, 收到喜欢, 新增粉丝: 215, 216, 195).
enum NoticeSettingKind { replies, likes, fans }

/// 所有人, 关注的人, 不接收任何消息提醒 (215).
enum NoticeAudience { everyone, following, off }

/// The decoders, each taking the envelope's `data`, and the settings' wire values.
abstract final class MessageDecode {
  /// `/x/msgfeed/unread`. Its `up` (UP主助手), `coin`, `danmu` and `favorite` counts aren't part of 消息.
  static FeedUnread feedUnread(Object? json) {
    final data = JsonObject.from(json, 'msgfeed unread');
    return (
      reply: data.count('reply'),
      at: data.count('at'),
      like: data.count('like', 'recv_like'),
      system: data.count('sys_msg'),
    );
  }

  /// `single_unread`: people's messages, followed and not, and the official notice cards (`biz_msg_*`: 196 lists
  /// 服务通知 among the sessions, so its unread counts toward 消息's badge). Left out: `custom_unread` (客服),
  /// `unfollow_push_msg` and the intercepted `dustbin_unread` and `dustbin_push_msg`.
  static int chatUnread(Object? json) {
    final data = JsonObject.from(json, 'single unread');
    return data.count('follow_unread') +
        data.count('unfollow_unread') +
        data.count('biz_msg_follow_unread') +
        data.count('biz_msg_unfollow_unread');
  }

  /// `/x/msgfeed/reply` or `/x/msgfeed/at`.
  static NoticePage<ReplyNotice> replies(Object? json, NoticeFeed feed) {
    final data = JsonObject.from(json, 'msgfeed page');
    final items = data.lenientList('items', (item) => _replyNotice(item, feed));
    return NoticePage(items: items, next: items.isEmpty ? null : _cursor(data.nested('cursor')));
  }

  /// `/x/msgfeed/like`: the likes since the list was last seen come under `latest`, the rest under `total`, which
  /// alone pages on; later pages repeat `latest`, so only the [firstPage] keeps it.
  static NoticePage<LikeNotice> likes(Object? json, {required bool firstPage}) {
    final data = JsonObject.from(json, 'like page');
    final total = data.nested('total');
    final older = total?.lenientList('items', _likeNotice) ?? const <LikeNotice>[];
    final latest = firstPage ? data.nested('latest')?.lenientList('items', _likeNotice) : null;
    final seen = <int>{};
    return NoticePage(
      items: [
        for (final notice in [...?latest, ...older])
          if (seen.add(notice.id)) notice,
      ],
      next: older.isEmpty ? null : _cursor(total?.nested('cursor')),
    );
  }

  /// `get_sessions`; [ChatSessionPage.next] is the last session's `session_ts`, the website's `end_ts` for the next
  /// page.
  static ChatSessionPage sessions(Object? json) {
    final data = JsonObject.from(json, 'sessions');
    final sessions = data.lenientList('session_list', _session);
    return ChatSessionPage(
      sessions: sessions,
      next: data.flag('has_more') && sessions.isNotEmpty ? sessions.last.time.microsecondsSinceEpoch : null,
    );
  }

  /// `x/im/user_infos`' list; a map of cards by mid reads the same.
  static List<ChatUserCard> userCards(Object? json) => switch (json) {
    final List<Object?> cards => lossy(cards, _userCard),
    final Map<String, Object?> byMid => lossy(byMid.values.toList(), _userCard),
    _ => const [],
  };

  /// `fetch_session_msgs`, turned oldest first. An empty session answers `min_seqno` 2⁶⁴−1, which reads as 0 here.
  static ChatMessagePage messages(Object? json) {
    final data = JsonObject.from(json, 'session messages');
    final emotes = _emotes(data);
    final raw = data.lenientList('messages', (message) => message);
    final messages = lossy(raw, (message) => _chatMessage(message, emotes)).nonNulls.toList()
      ..sort((a, b) => a.seqno.compareTo(b.seqno));
    return ChatMessagePage(
      messages: messages,
      hasMore: data.flag('has_more'),
      minSeqno: raw.isEmpty ? 0 : _seqno(data.map['min_seqno']) ?? messages.firstOrNull?.seqno ?? 0,
      maxSeqno: raw.isEmpty ? 0 : _seqno(data.map['max_seqno']) ?? messages.lastOrNull?.seqno ?? 0,
    );
  }

  /// send_msg's answer: the message as sent, with no seqno (the answer has none).
  static ChatMessage sent(Object? json, {required int senderMid, required String text, required DateTime time}) {
    final data = JsonObject.from(json, 'sent message');
    return ChatMessage(
      seqno: 0,
      key: _seqno(data.map['msg_key']) ?? 0,
      senderMid: senderMid,
      kind: ChatMessageKind.text,
      time: time,
      text: text,
      emotes: _used(_emotes(data), text),
    );
  }

  /// `sys-msg/query_notify_list`, turned oldest first; a full page of [pageSize] may have more before it.
  static ChatMessagePage systemNotices(Object? json, {required int pageSize}) {
    final raw = json is List ? List<Object?>.of(json) : const <Object?>[];
    final notices = lossy(raw, _systemNotice)..sort((a, b) => a.seqno.compareTo(b.seqno));
    return ChatMessagePage(
      messages: notices,
      hasMore: notices.isNotEmpty && raw.length >= pageSize,
      minSeqno: notices.firstOrNull?.seqno ?? 0,
      maxSeqno: notices.lastOrNull?.seqno ?? 0,
    );
  }

  /// `get_session_ss`: `follow_status` is the account's relation to them (悄悄关注, 关注, 互粉 count as following).
  static ChatSettings chatSettings(Object? json) {
    final data = JsonObject.from(json, 'session settings');
    return ChatSettings(
      following: const {1, 2, 6}.contains(_id(data.map['follow_status'])),
      pushOn: (_id(data.map['push_setting']) ?? 0) == 0,
      showPush: data.map['show_push_setting'] == null || data.flag('show_push_setting'),
    );
  }

  /// `link_setting/get`; a setting the answer leaves out is left out here too.
  static Map<NoticeSettingKind, NoticeAudience> noticeSettings(Object? json) {
    final data = JsonObject.from(json, 'link settings');
    return {for (final kind in NoticeSettingKind.values) kind: ?_audience(data.map[settingField(kind)])};
  }

  /// `link_setting`'s field for [kind]: the new 回复与@, 收到喜欢 and 新增粉丝 fields, not the old `set_comment`,
  /// `set_at` and `set_like`.
  static String settingField(NoticeSettingKind kind) => switch (kind) {
    NoticeSettingKind.replies => 'set_recv_reply',
    NoticeSettingKind.likes => 'set_recv_like',
    NoticeSettingKind.fans => 'set_new_follow',
  };

  /// 0 所有人, 1 关注的人, 2 不接收: one scale for all three fields.
  static String audienceValue(NoticeAudience audience) => switch (audience) {
    NoticeAudience.everyone => '0',
    NoticeAudience.following => '1',
    NoticeAudience.off => '2',
  };
}

const _empty = JsonObject(<String, Object?>{});

/// Ids come as numbers or as strings of digits, depending on the call.
int? _id(Object? value) => asInt(value) ?? (value is String ? int.tryParse(value.trim()) : null);

/// Seqnos and msg_keys run past 2⁵³, so only an exact integer counts; 2⁶⁴−1 arrives as a double and reads as none.
int? _seqno(Object? value) => value is int ? value : (value is String ? int.tryParse(value.trim()) : null);

DateTime _seconds(Object? value) => DateTime.fromMillisecondsSinceEpoch((_id(value) ?? 0) * 1000);

String _firstText(List<String?> texts) =>
    texts.firstWhere((text) => text != null && text.isNotEmpty, orElse: () => '')!;

NoticeCursor? _cursor(JsonObject? cursor) {
  if (cursor == null || cursor.flag('is_end')) return null;
  final id = _id(cursor.map['id']);
  if (id == null || id <= 0) return null;
  return NoticeCursor(id: id, time: _id(cursor.map['time']) ?? 0);
}

NoticeUser _noticeUser(JsonObject? user) => NoticeUser(
  mid: _id(user?.map['mid']) ?? 0,
  name: user?.text('nickname') ?? '',
  face: user?.text('avatar') ?? '',
  following: user?.flag('follow') ?? false,
);

NoticeAudience? _audience(Object? value) => switch (_id(value)) {
  null => null,
  0 => NoticeAudience.everyone,
  1 => NoticeAudience.following,
  _ => NoticeAudience.off,
};

/// The answer has no field saying the replier is the subject's uploader (197's UP tag), so [ReplyNotice.fromUploader]
/// stays false.
ReplyNotice _replyNotice(Object? json, NoticeFeed feed) {
  final row = JsonObject.from(json, 'reply notice');
  final id = _id(row.map['id']) ?? (throw const DecodeError('reply notice: missing id'));
  final item = row.nested('item') ?? _empty;
  return ReplyNotice(
    id: id,
    feed: feed,
    user: _noticeUser(row.nested('user')),
    business: item.text('type') ?? '',
    businessId: _id(item.map['business_id']) ?? 0,
    subjectId: _id(item.map['subject_id']) ?? 0,
    rootId: _id(item.map['root_id']) ?? 0,
    sourceId: _id(item.map['source_id']) ?? 0,
    targetId: _id(item.map['target_id']) ?? 0,
    text: item.text('source_content') ?? '',
    time: _seconds(row.map[feed == NoticeFeed.at ? 'at_time' : 'reply_time']),
    targetText: _firstText([item.text('target_reply_content'), item.text('root_reply_content')]),
    title: item.text('title') ?? '',
    image: item.text('image') ?? '',
    uri: item.text('uri') ?? '',
    nativeUri: item.text('native_uri') ?? '',
    liked: item.flag('like_state'),
    canReply: !item.flag('hide_reply_button'),
    canLike: !item.flag('hide_like_button'),
  );
}

LikeNotice _likeNotice(Object? json) {
  final row = JsonObject.from(json, 'like notice');
  final id = _id(row.map['id']) ?? (throw const DecodeError('like notice: missing id'));
  final item = row.nested('item') ?? _empty;
  final users = row.lenientList('users', (json) => _noticeUser(JsonObject.from(json, 'liker')));
  final counts = row.count('counts');
  return LikeNotice(
    id: id,
    users: users,
    count: counts > 0 ? counts : users.length,
    business: item.text('business') ?? '',
    time: _seconds(row.map['like_time']),
    itemId: _id(item.map['item_id']) ?? 0,
    title: item.text('title') ?? '',
    image: item.text('image') ?? '',
    uri: item.text('uri') ?? '',
    nativeUri: item.text('native_uri') ?? '',
    notifying: (_id(row.map['notice_state']) ?? 0) == 0,
  );
}

/// A session's name and face come from `account_info` (official accounts) or the group's, else from the user cards
/// (`chatUserCards`). The website's list has no 服务通知 or 社区中心 type: an official account is boxed by its
/// `account_info.name`, else by `system_msg_type` (5 系统通知, 7 UP主小助手 as 创作助手).
ChatSession _session(Object? json) {
  final session = JsonObject.from(json, 'session');
  final talkerId = _id(session.map['talker_id']) ?? (throw const DecodeError('session: missing talker_id'));
  final type = _id(session.map['session_type']) ?? 1;
  final account = session.nested('account_info');
  final group = type == 2;
  final last = session.nested('last_msg');
  final sessionTs = _seqno(session.map['session_ts']) ?? 0;
  final name = account?.text('name') ?? (group ? session.text('group_name') : null) ?? '';
  return ChatSession(
    talkerId: talkerId,
    sessionType: type,
    name: name,
    face: account?.text('pic_url') ?? (group ? session.text('group_cover') : null) ?? '',
    lastText: last == null ? '' : _lastText(last, talkerId),
    time: sessionTs > 0 ? DateTime.fromMicrosecondsSinceEpoch(sessionTs) : _seconds(last?.map['timestamp']),
    unread: session.count('unread_count'),
    ackSeqno: _seqno(session.map['ack_seqno']) ?? 0,
    maxSeqno: _seqno(session.map['max_seqno']) ?? 0,
    topTs: _seqno(session.map['top_ts']) ?? 0,
    box: _box(account == null ? null : name, _id(session.map['system_msg_type']) ?? 0),
  );
}

/// Never [NoticeBox.system]: the app reads that box as 系统通知's own list (`sys-msg`), so a session marked so would
/// be paged and acked as that list instead of as itself.
NoticeBox? _box(String? officialName, int systemType) {
  for (final box in NoticeBox.values) {
    if (box != NoticeBox.system && box.label == officialName) return box;
  }
  return systemType == 7 ? NoticeBox.creator : null;
}

bool _vipPink(JsonObject? vip) =>
    _id(vip?.map['vipStatus'] ?? vip?.map['status']) == 1 && (_id(vip?.map['vipType'] ?? vip?.map['type']) ?? 0) > 0;

/// The 大 on the face: `avatar_subscript` where the answer has it, else a 大会员 that lasts.
bool _bigVip(JsonObject? vip) {
  if (vip == null) return false;
  if (vip.map['avatar_subscript'] != null) return _id(vip.map['avatar_subscript']) == 1;
  return _vipPink(vip);
}

DynamicVerify _verify(Object? type) => switch (_id(type)) {
  0 => DynamicVerify.personal,
  1 => DynamicVerify.organisation,
  _ => DynamicVerify.none,
};

ChatUserCard _userCard(Object? json) {
  final card = JsonObject.from(json, 'user card');
  final mid = _id(card.map['mid']) ?? (throw const DecodeError('user card: missing mid'));
  final vip = card.nested('vip');
  return ChatUserCard(
    mid: mid,
    name: _firstText([card.text('name'), card.text('uname')]),
    face: card.text('face') ?? '',
    vipPink: _vipPink(vip),
    bigVip: _bigVip(vip),
    verify: _verify((card.nested('official') ?? card.nested('official_verify'))?.map['type']),
    pendant: card.nested('pendant')?.text('image') ?? '',
  );
}

/// A message's `content` is JSON in a string; anything else (a take-back's bare msg_key) reads as empty.
JsonObject _content(Object? raw) {
  final value = raw is String ? _json(raw) : raw;
  return value is Map<String, Object?> ? JsonObject(value) : _empty;
}

Object? _json(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

/// `msg_source` 8-11: 被关注回复, 收到消息回复, 关键词回复 and 大航海上船回复, which the website marks 此条消息为自动回复.
bool _autoReply(JsonObject message) => switch (_id(message.map['msg_source'])) {
  8 || 9 || 10 || 11 => true,
  _ => false,
};

/// What a message reads as in one line, as the website's session list puts it.
String _preview(int type, JsonObject content) {
  final title = content.text('title') ?? '';
  return switch (type) {
    1 => content.text('content') ?? '',
    2 => '[图片]',
    6 => '[自定义表情]',
    7 => '[${(content.text('headline') ?? '').isEmpty ? '分享' : '转发'}]$title',
    10 || 13 => title,
    11 => '[视频]$title',
    12 => '[文章]$title',
    14 => '[分享]$title',
    16 => content.text('reply_content') ?? '',
    18 => '',
    _ => content.text('content') ?? '',
  };
}

final _spaces = RegExp(r'\s+');

/// 196's grey line: an auto reply as `[自动回复] …` (the phone's space, where the website has none).
String _lastText(JsonObject message, int talkerId) {
  if (_id(message.map['msg_status']) == 1 || _id(message.map['msg_type']) == 5) {
    return '${_id(message.map['sender_uid']) == talkerId ? '对方' : '你'}撤回了一条消息';
  }
  final text = _preview(_id(message.map['msg_type']) ?? 0, _content(message.map['content']));
  return (_autoReply(message) ? '[自动回复] $text' : text).replaceAll(_spaces, ' ').trim();
}

Map<String, String> _emotes(JsonObject data) => {
  for (final emote in data.lenientList('e_infos', (json) => JsonObject.from(json, 'emote')))
    if (emote.text('text') case final code? when code.isNotEmpty)
      if (_firstText([emote.text('url'), emote.text('uri')]) case final url when url.isNotEmpty) code: url,
};

Map<String, String> _used(Map<String, String> emotes, String text) => {
  for (final MapEntry(:key, :value) in emotes.entries)
    if (text.contains(key)) key: value,
};

/// The take-back itself (`msg_type` 5) is dropped, as the website drops it; the message it took back carries
/// `msg_status` 1 and is kept without its text.
ChatMessage? _chatMessage(Object? json, Map<String, String> emotes) {
  final message = JsonObject.from(json, 'chat message');
  final seqno = _seqno(message.map['msg_seqno']) ?? (throw const DecodeError('chat message: missing msg_seqno'));
  final type = _id(message.map['msg_type']) ?? 0;
  if (type == 5) return null;
  final sender = _id(message.map['sender_uid']) ?? 0;
  final key = _seqno(message.map['msg_key']) ?? 0;
  final time = _seconds(message.map['timestamp']);
  final autoReply = _autoReply(message);
  ChatMessage make(ChatMessageKind kind, {String text = ''}) =>
      ChatMessage(seqno: seqno, key: key, senderMid: sender, kind: kind, time: time, text: text, autoReply: autoReply);
  if (_id(message.map['msg_status']) == 1) return make(ChatMessageKind.withdrawn);
  final content = _content(message.map['content']);
  switch (type) {
    case 1:
      final text = content.text('content') ?? '';
      return ChatMessage(
        seqno: seqno,
        key: key,
        senderMid: sender,
        kind: ChatMessageKind.text,
        time: time,
        text: text,
        emotes: _used(emotes, text),
        autoReply: autoReply,
      );
    case 2 || 6:
      return ChatMessage(
        seqno: seqno,
        key: key,
        senderMid: sender,
        kind: ChatMessageKind.picture,
        time: time,
        picture: content.text('url') ?? '',
        pictureWidth: asDouble(content.map['width'])?.round() ?? 0,
        pictureHeight: asDouble(content.map['height'])?.round() ?? 0,
        autoReply: autoReply,
      );
    case 10:
      return ChatMessage(
        seqno: seqno,
        key: key,
        senderMid: sender,
        kind: ChatMessageKind.notice,
        time: time,
        title: content.text('title') ?? '',
        text: content.text('text') ?? '',
        fields: content.lenientList('modules', _noticeField),
        links: _noticeLinks(content),
        autoReply: autoReply,
      );
    case 18:
      return make(ChatMessageKind.tip, text: _tipLines(content.text('content')));
    case 53:
      return make(ChatMessageKind.tip, text: _subscribeTip(content));
    case >= 301 && <= 306:
      return make(ChatMessageKind.tip, text: content.text('content') ?? '');
  }
  // The website draws a bare line from no one (a group's 欢迎…入群) as a tip.
  final line = content.text('content') ?? '';
  if (sender == 0 && line.isNotEmpty) return make(ChatMessageKind.tip, text: line);
  return make(ChatMessageKind.other, text: _preview(type, content));
}

({String title, String detail}) _noticeField(Object? json) {
  final module = JsonObject.from(json, 'notice module');
  return (title: module.text('title') ?? '', detail: module.text('detail') ?? '');
}

/// A notice card's up to three buttons. Each one's address is its config's `web_uri`, else `all_uri`, else the bare
/// `jump_uri`; without one there is no button. Its text is the config's, else `jump_text`, else 查看详情.
List<({String text, String uri})> _noticeLinks(JsonObject content) {
  final links = <({String text, String uri})>[];
  for (final suffix in const ['', '_2', '_3']) {
    final config = content.nested('jump_uri${suffix}_config');
    final uri = _firstText([config?.text('web_uri'), config?.text('all_uri'), content.text('jump_uri$suffix')]);
    if (uri.isEmpty) continue;
    links.add((text: _firstText([config?.text('text'), content.text('jump_text$suffix'), '查看详情']), uri: uri));
  }
  return links;
}

/// msg_type 18's `content` is a JSON array, as a string, of `{text, color_day, …}`.
String _tipLines(String? raw) {
  final lines = raw == null ? null : _json(raw);
  if (lines is! List) return raw ?? '';
  return [
    for (final line in lines)
      if (line case {'text': final String text}) text,
  ].join();
}

/// msg_type 53's paragraph of words and links.
String _subscribeTip(JsonObject content) {
  final nodes = content.nested('paragraph')?.nested('text')?.lenientList('nodes', (json) => JsonObject.from(json));
  return [
    for (final node in nodes ?? const <JsonObject>[])
      _firstText([
        node.nested('word')?.text('words'),
        node.nested('link')?.nested('show_text')?.text('words'),
        node.text('raw_text'),
      ]),
  ].join();
}

/// `#{label}{"address"}` in a 系统通知: the label stays in the text, the address becomes a link.
final _noticeLink = RegExp(r'#\{(.+?)\}\{"?(.+?)"?\}');

/// A 系统通知: its `content` is the text, or JSON whose `web` field is, as the website reads it.
ChatMessage _systemNotice(Object? json) {
  final notice = JsonObject.from(json, 'system notice');
  final cursor = _seqno(notice.map['cursor']) ?? (throw const DecodeError('system notice: missing cursor'));
  var body = notice.text('content') ?? '';
  if (_json(body) case {'web': final String web}) body = web;
  final links = <({String text, String uri})>[];
  body = body.replaceAllMapped(_noticeLink, (match) {
    final label = match[1]!;
    final address = match[2]!;
    links.add((text: label, uri: address.startsWith('//') ? 'https:$address' : address));
    return label;
  });
  return ChatMessage(
    seqno: cursor,
    key: _seqno(notice.map['id']) ?? 0,
    senderMid: 0,
    kind: ChatMessageKind.notice,
    time: _noticeTime(notice.text('time_at'), cursor),
    title: notice.text('title') ?? '',
    text: body,
    links: links,
  );
}

final _beijingTime = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})$');

/// `time_at` is Beijing time with no zone; failing that, the cursor is a time in nanoseconds.
DateTime _noticeTime(String? timeAt, int cursor) {
  if (_beijingTime.firstMatch(timeAt?.trim() ?? '') case final match?) {
    final [year, month, day, hour, minute, second] = [
      for (var group = 1; group <= 6; group++) int.parse(match[group]!),
    ];
    return DateTime.utc(year, month, day, hour - 8, minute, second).toLocal();
  }
  return cursor > 100000000000000000 ? DateTime.fromMicrosecondsSinceEpoch(cursor ~/ 1000) : DateTime(1970);
}
