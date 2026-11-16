import 'dart:async';

import 'package:bili_core/api.dart';

import '../video/fake_page_api.dart' show FakePageApi;
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

  /// The `--fake-account` demo, dated back from [now]: 2 replies, 1 @, 1 like and 3 私信 unread; 回复与@, 收到喜欢 and
  /// 新增粉丝 with each kind of row; 服务通知's and 社区中心's cards, eight people's chats and 系统通知. Names are 演示…,
  /// every text made up, faces and pictures empty so nothing is fetched. The video rows are the PC's
  /// `--fake-notify-tap` video, the first on FakePageApi's demo thread; the post rows are FakeDynamicApi's first post.
  factory FakeMessageApi.demo({DateTime? now, int pageSize = 20}) {
    final demo = _Demo(now ?? DateTime.now());
    return FakeMessageApi(
      counts: const MessageUnread(reply: 2, at: 1, like: 1, chat: 3),
      replyList: demo.replies(),
      mentionList: demo.mentions(),
      likeList: demo.likes(),
      fanList: _Demo.fans,
      sessionList: demo.sessions(),
      chats: demo.chats(),
      chatSettingsOf: const {
        _Demo.sheep: ChatSettings(),
        _Demo.dream: ChatSettings(following: true),
        _Demo.tangerine: ChatSettings(following: true, pushOn: false),
      },
      pageSize: pageSize,
    );
  }

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

/// The demo's rows, dated back from [now].
class _Demo {
  _Demo(this.now);

  final DateTime now;

  static const self = 1;
  static const sheep = 501;
  static const dream = 502;
  static const tangerine = 503;
  static const idle = 504;
  static const studio = 505;
  static const gunner = 506;
  static const robot = 507;
  static const riceCake = 508;
  static const service = 9101;
  static const community = 9102;

  /// BV13as367Ebh's.
  static const _aid = 117614407850785;
  static const _videoTitle = '「演示」第六话 | 出发';
  static const _videoUri = 'https://www.bilibili.com/video/BV13as367Ebh';
  static const _post = 9001;
  static const _postTitle = '演示动态的第一行，写得稍微长一点';
  static const _postUri = 'https://t.bilibili.com/$_post';
  static const _link = 'https://www.bilibili.com/';

  static const _up = NoticeUser(mid: 301, name: '演示UP主', face: '', following: true);
  static const _passer = NoticeUser(mid: 302, name: '演示路人', face: '');
  static const _star = NoticeUser(mid: 303, name: '演示星河', face: '', following: true);
  static const _night = NoticeUser(mid: 304, name: '演示小夜', face: '');
  static const _orange = NoticeUser(mid: 305, name: '演示阿橙', face: '');
  static const _feather = NoticeUser(mid: 306, name: '演示羽毛', face: '');
  static const _biscuit = NoticeUser(mid: 307, name: '演示饼干', face: '');
  static const _oldFriend = NoticeUser(mid: 308, name: '演示旧友', face: '');

  static const fans = [
    RelationUser(
      user: FollowingUser(mid: 401, name: '演示新粉丝', face: '', sign: '演示签名：刚刚关注了你'),
      attribute: RelationUser.none,
    ),
    RelationUser(
      user: FollowingUser(mid: 402, name: '演示老朋友', face: '', vipPink: true),
      attribute: RelationUser.mutualValue,
    ),
    RelationUser(
      user: FollowingUser(mid: 403, name: '演示路过的', face: '', verify: DynamicVerify.personal),
      attribute: RelationUser.none,
    ),
  ];

  static const _skinLinks = [(text: '立即查看', uri: _link), (text: '更多个性装扮', uri: _link)];

  DateTime ago({int days = 0, int hours = 0, int minutes = 0}) =>
      now.subtract(Duration(days: days, hours: hours, minutes: minutes));

  ReplyNotice _reply(
    int id,
    NoticeUser user,
    String text,
    DateTime time, {
    required int root,
    required int source,
    String targetText = '',
    NoticeFeed feed = NoticeFeed.reply,
    bool post = false,
    bool fromUploader = false,
    bool liked = false,
  }) => ReplyNotice(
    id: id,
    feed: feed,
    user: user,
    business: 'reply',
    businessId: post ? 11 : 1,
    subjectId: post ? _post : _aid,
    rootId: root,
    sourceId: source,
    targetId: root,
    text: text,
    time: time,
    targetText: targetText,
    title: post ? _postTitle : _videoTitle,
    uri: post ? _postUri : _videoUri,
    nativeUri: post
        ? 'bilibili://following/detail/$_post?comment_root_id=$root&comment_secondary_id=$source'
        : 'bilibili://video/$_aid?comment_root_id=$root&comment_secondary_id=$source',
    fromUploader: fromUploader,
    liked: liked,
  );

  List<ReplyNotice> replies() => [
    _reply(
      6008,
      _up,
      '谢谢喜欢！下一期也在做了，敬请期待～',
      ago(minutes: 5),
      root: FakePageApi.demoFocusRoot,
      source: FakePageApi.demoFocusReply,
      targetText: '演示：这期的剪辑节奏太舒服了',
      fromUploader: true,
    ),
    _reply(
      6007,
      _passer,
      '同感，我也是看了三遍[doge]',
      ago(minutes: 42),
      root: 5101,
      source: 5102,
      targetText: '演示：这期的剪辑节奏太舒服了',
      liked: true,
    ),
    _reply(
      6006,
      _star,
      '演示一段长一点的回复：我觉得你说得对，不过第二段那里其实还有一个细节，镜头转过去的时候背景里有人在挥手，仔细看才能发现[doge]',
      ago(hours: 3),
      root: 5201,
      source: 5202,
      targetText: '演示：今天也是普通的一天',
      post: true,
    ),
    // On the video itself: the row shows its cover where the others show the account's comment.
    ReplyNotice(
      id: 6005,
      feed: NoticeFeed.reply,
      user: _night,
      business: 'video',
      businessId: 1,
      subjectId: _aid,
      rootId: 0,
      sourceId: 5301,
      targetId: 0,
      text: '这个视频的配乐叫什么呀？',
      time: ago(days: 1, hours: 2),
      title: _videoTitle,
      uri: _videoUri,
      nativeUri: 'bilibili://video/$_aid?comment_root_id=5301',
    ),
    _reply(
      6004,
      _orange,
      '哈哈哈哈[笑哭]',
      ago(days: 2),
      root: 5401,
      source: 5402,
      targetText: '演示：第一次见到这么认真的分析',
      liked: true,
    ),
    _reply(
      6003,
      _feather,
      '收藏了，回头慢慢看',
      ago(days: 9),
      root: 5501,
      source: 5502,
      targetText: '演示：整理了一份时间线，放在置顶了',
      post: true,
    ),
    _reply(6002, _biscuit, '支持一下！', ago(days: 75), root: 5601, source: 5602, targetText: '演示：更新啦'),
    _reply(6001, _oldFriend, '去年的评论也被翻出来了[吃瓜]', ago(days: 400), root: 5701, source: 5702, targetText: '演示：去年今日打卡'),
  ];

  List<ReplyNotice> mentions() => [
    _reply(6102, _star, '@测试账号 快来看这个[doge]', ago(hours: 5), root: 5801, source: 5802, feed: NoticeFeed.at, post: true),
    _reply(6101, _passer, '@测试账号 你之前说的就是这个吧', ago(days: 6), root: 5901, source: 5902, feed: NoticeFeed.at),
  ];

  List<LikeNotice> likes() => [
    LikeNotice(
      id: 6205,
      users: const [_star, _passer, _orange],
      count: 12,
      business: '评论',
      itemId: 7005,
      title: '演示：这期的剪辑节奏太舒服了',
      uri: _videoUri,
      time: ago(minutes: 20),
    ),
    LikeNotice(
      id: 6204,
      users: const [_night],
      count: 1,
      business: '评论',
      itemId: 7004,
      title: '演示：第一次见到这么认真的分析',
      uri: _videoUri,
      time: ago(hours: 6),
    ),
    LikeNotice(
      id: 6203,
      users: const [_feather, _biscuit],
      count: 2,
      business: '弹幕',
      itemId: 7003,
      title: '演示弹幕：前方高能',
      uri: _videoUri,
      time: ago(days: 1),
    ),
    LikeNotice(
      id: 6202,
      users: const [_up, _star, _night],
      count: 5,
      business: '视频',
      itemId: 7002,
      title: _videoTitle,
      uri: _videoUri,
      time: ago(days: 20),
    ),
    LikeNotice(
      id: 6201,
      users: const [_oldFriend, _passer],
      count: 3,
      business: '动态',
      itemId: 7001,
      title: _postTitle,
      uri: _postUri,
      notifying: false,
      time: ago(days: 380),
    ),
  ];

  late final List<_Person> _people = [
    _Person(
      _Chat(service)
        ..notice(
          '演示装扮到账通知',
          '亲爱的演示用户，恭喜你获得演示花园装扮！快去我的个性装扮看看吧～更多装扮等你解锁>>',
          ago(days: 20),
          fields: const [(title: '有效期', detail: '永久有效')],
          links: _skinLinks,
        )
        ..notice(
          '演示装扮到账通知',
          '亲爱的演示用户，恭喜你获得演示星空装扮！快去我的个性装扮看看吧～',
          ago(days: 18),
          fields: const [(title: '有效期', detail: '30天')],
          links: _skinLinks,
        )
        ..notice(
          '演示收藏集到账通知',
          '恭喜你集齐演示收藏集的全部卡片，奖励已经发放到你的账户，快去看看吧>>',
          ago(days: 15),
          fields: const [(title: '有效期', detail: '永久有效')],
          links: _skinLinks,
        )
        ..theirs('演示装扮收藏集活动开启，免费福利券待领取！领取请戳>>$_link', ago(days: 10))
        ..theirs('活动第二周福利已送达，新增周边加码，领取>>【$_link】', ago(days: 2, hours: 5)),
      NoticeBox.service.label,
      box: NoticeBox.service,
    ),
    _Person(
      _Chat(community)
        ..notice(
          '演示登录提醒',
          '你的演示账号在新设备上登录成功，如非本人操作，请及时修改密码',
          ago(days: 6, hours: 3),
          fields: _login('演示浏览器', ago(days: 6, hours: 3)),
          links: const [(text: '查看详情', uri: _link)],
        )
        ..notice(
          '演示登录提醒',
          '你的演示账号在新设备上登录成功，如非本人操作，请及时修改密码',
          ago(days: 4),
          fields: _login('演示设备', ago(days: 4)),
          links: const [(text: '查看详情', uri: _link)],
        ),
      NoticeBox.community.label,
      box: NoticeBox.community,
    ),
    _Person(
      _Chat(sheep)
        ..tip(ago(days: 2, minutes: 10))
        ..mine('你好，想问一下视频里用的是什么软件剪的？', ago(days: 2))
        ..theirs('是演示剪辑器，免费的[doge]', ago(hours: 3, minutes: 5))
        ..picture(ago(hours: 3))
        ..theirs('这张是界面的截图，可以参考一下', ago(hours: 1, minutes: 1))
        ..theirs('有问题再问我就好～', ago(hours: 1)),
      '演示小羊',
      unread: 2,
    ),
    _Person(
      _Chat(dream)
        ..mine('关注了！很喜欢你的视频', ago(hours: 22))
        ..theirs('谢谢关注！每周五更新，记得来看[星星眼]', ago(hours: 20), autoReply: true),
      '演示梦境',
      unread: 1,
      vipPink: true,
      verify: DynamicVerify.personal,
    ),
    _Person(
      _Chat(tangerine)
        ..theirs('感谢关注，有什么想看的可以私信投稿哦～', ago(days: 3, minutes: 30), autoReply: true)
        ..tip(ago(days: 3)),
      '演示橘子',
      vipPink: true,
      bigVip: true,
    ),
    _Person(
      _Chat(idle)
        ..mine('晚上好[微笑]', ago(days: 12, hours: 2))
        ..theirs('晚上好呀[打call][打call]', ago(days: 12, hours: 1, minutes: 50))
        ..mine('下次直播是什么时候？', ago(days: 12, hours: 1))
        ..theirs('大概周末吧，到时候动态里会说的', ago(days: 12)),
      '演示摆摆',
    ),
    _Person(
      _Chat(studio)..theirs('演示头像框活动开始啦，参与就有机会领取限定挂件！详情戳>>$_link', ago(days: 40)),
      '演示装扮站',
      verify: DynamicVerify.organisation,
    ),
    _Person(
      _Chat(gunner)
        ..mine('请问可以转载你的视频吗？会注明出处的', ago(days: 96))
        ..theirs('可以的，注明出处就好[OK]', ago(days: 95)),
      '演示枪手',
      vipPink: true,
      bigVip: true,
    ),
    _Person(
      _Chat(robot)..theirs('你好，这里是演示机器人。回复数字获取帮助：1 使用说明 2 常见问题', ago(days: 130)),
      '演示机器人',
      verify: DynamicVerify.personal,
    ),
    _Person(
      _Chat(riceCake)
        ..theirs('新年快乐！[喜欢]', ago(days: 401))
        ..withdrawn(ago(days: 400, hours: 1))
        ..mine('新年快乐～', ago(days: 400)),
      '演示年糕',
    ),
  ];

  List<ChatSession> sessions() => [for (final person in _people) person.session];

  /// Each session's messages, and 系统通知's under 0.
  Map<int, List<ChatMessage>> chats() => {
    for (final person in _people) person.chat.talker: person.chat.messages,
    0: _systemNotices().messages,
  };

  _Chat _systemNotices() => _Chat(0)
    ..notice('演示系统通知', '你的演示稿件已通过审核，快去看看吧', ago(days: 30))
    ..notice('演示活动通知', '演示活动报名已开启，参与即有机会获得演示奖励', ago(days: 8), links: const [(text: '查看详情', uri: _link)]);

  static List<({String title, String detail})> _login(String device, DateTime at) => [
    (title: '设备/平台', detail: device),
    (title: '登录方式', detail: '扫码登录'),
    (title: '参考登录地', detail: '演示城市'),
    (title: '登录时间', detail: _clock(at)),
  ];

  static String _clock(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  }
}

/// One demo chat, oldest first, numbered as it grows.
class _Chat {
  _Chat(this.talker);

  final int talker;
  final messages = <ChatMessage>[];

  void _add(
    int sender,
    ChatMessageKind kind,
    DateTime time, {
    String text = '',
    String title = '',
    List<({String title, String detail})> fields = const [],
    List<({String text, String uri})> links = const [],
    int pictureWidth = 0,
    int pictureHeight = 0,
    bool autoReply = false,
  }) {
    final seqno = messages.length + 1;
    messages.add(
      ChatMessage(
        seqno: seqno,
        key: talker * 100 + seqno,
        senderMid: sender,
        kind: kind,
        text: text,
        title: title,
        fields: fields,
        links: links,
        pictureWidth: pictureWidth,
        pictureHeight: pictureHeight,
        autoReply: autoReply,
        time: time,
      ),
    );
  }

  void theirs(String text, DateTime time, {bool autoReply = false}) =>
      _add(talker, ChatMessageKind.text, time, text: text, autoReply: autoReply);

  void mine(String text, DateTime time) => _add(_Demo.self, ChatMessageKind.text, time, text: text);

  void tip(DateTime time) => _add(talker, ChatMessageKind.tip, time, text: '对方主动回复或关注你前，最多发送1条消息');

  void picture(DateTime time) => _add(talker, ChatMessageKind.picture, time, pictureWidth: 1080, pictureHeight: 720);

  void withdrawn(DateTime time) => _add(talker, ChatMessageKind.withdrawn, time);

  void notice(
    String title,
    String text,
    DateTime time, {
    List<({String title, String detail})> fields = const [],
    List<({String text, String uri})> links = const [],
  }) => _add(talker, ChatMessageKind.notice, time, title: title, text: text, fields: fields, links: links);
}

/// A demo session: its chat, and how the list draws it.
class _Person {
  _Person(
    this.chat,
    this.name, {
    this.unread = 0,
    this.vipPink = false,
    this.bigVip = false,
    this.verify = DynamicVerify.none,
    this.box,
  });

  final _Chat chat;
  final String name;
  final int unread;
  final bool vipPink;
  final bool bigVip;
  final DynamicVerify verify;
  final NoticeBox? box;

  /// Its last message as 196 shows it; a tip line under it leaves it shown.
  ChatSession get session {
    final last = chat.messages.last;
    final shown = chat.messages.lastWhere((message) => message.kind != ChatMessageKind.tip, orElse: () => last);
    return ChatSession(
      talkerId: chat.talker,
      name: name,
      face: '',
      lastText: switch (shown) {
        ChatMessage(kind: ChatMessageKind.picture) => '[图片]',
        ChatMessage(kind: ChatMessageKind.notice, :final title) => title,
        ChatMessage(autoReply: true, :final text) => '[自动回复] $text',
        ChatMessage(:final text) => text,
      },
      time: last.time,
      unread: unread,
      ackSeqno: last.seqno - unread,
      maxSeqno: last.seqno,
      box: box,
      vipPink: vipPink,
      bigVip: bigVip,
      verify: verify,
    );
  }
}
