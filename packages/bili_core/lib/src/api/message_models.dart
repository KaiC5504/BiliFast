/// 消息's lists: the red counts, 回复与@, 收到喜欢, the 私信 sessions and their messages, and the 消息设置 switches.
/// The website's calls with the web login's cookies (`/x/msgfeed/…`, `api.vc.bilibili.com`'s session and IM calls).
library;

import 'dynamic_models.dart' show DynamicVerify;

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
    this.top = false,
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

  /// 置顶.
  final bool top;

  /// One of the official notice boxes, drawn with its pink icon (196's 服务通知, 社区中心); null for a person.
  final NoticeBox? box;

  /// 大会员's pink name, and the 大 badge on the face.
  final bool vipPink;
  final bool bigVip;
  final DynamicVerify verify;

  /// The face's frame (`pendant.image`), empty for none.
  final String pendant;

  ChatSession copyWith({int? unread, int? ackSeqno, String? lastText, DateTime? time}) => ChatSession(
    talkerId: talkerId,
    sessionType: sessionType,
    name: name,
    face: face,
    lastText: lastText ?? this.lastText,
    time: time ?? this.time,
    unread: unread ?? this.unread,
    ackSeqno: ackSeqno ?? this.ackSeqno,
    maxSeqno: maxSeqno,
    top: top,
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

/// A person's card (`account/v1/user/cards`), naming the sessions get_sessions leaves bare.
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

  /// 5: withdrawn (撤回).
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

  /// `msg_seqno`: the message's place in the session, the ack and the paging go by it.
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
