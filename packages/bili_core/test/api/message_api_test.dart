import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:test/test.dart';

import 'fake_http.dart';
import 'fixtures.dart';

const _navPath = '/x/web-interface/nav';
const _unreadPath = '/x/msgfeed/unread';
const _singleUnreadPath = '/session_svr/v1/session_svr/single_unread';
const _replyPath = '/x/msgfeed/reply';
const _atPath = '/x/msgfeed/at';
const _likePath = '/x/msgfeed/like';
const _delPath = '/x/msgfeed/del';
const _noticePath = '/x/msgfeed/notice';
const _sessionsPath = '/session_svr/v1/session_svr/get_sessions';
const _cardsPath = '/x/im/user_infos';
const _messagesPath = '/svr_sync/v1/svr_sync/fetch_session_msgs';
const _ackPath = '/session_svr/v1/session_svr/update_ack';
const _sendPath = '/web_im/v1/web_im/send_msg';
const _systemPath = '/x/sys-msg/query_notify_list';
const _cursorPath = '/x/sys-msg/update_cursor';
const _sessionSettingsPath = '/link_setting/v1/link_setting/get_session_ss';
const _pushPath = '/link_setting/v1/link_setting/set_push_ss';
const _settingsPath = '/link_setting/v1/link_setting/get';
const _setSettingsPath = '/link_setting/v1/link_setting/set';

const _vc = 'api.vc.bilibili.com';
const _center = 'message.bilibili.com';
const _web = {'build': '0', 'mobi_app': 'web'};
const _mixinKey = 'ea1db124af3c7062474693fa704f4ff8';

const _ok = '{"code":0,"msg":"0","message":"0","ttl":1,"data":{}}';

const _feedUnread =
    '{"code":0,"message":"0","ttl":1,"data":{"at":3,"chat":0,"coin":0,"danmu":0,"favorite":0,"like":10,'
    '"recv_like":10,"recv_reply":4,"reply":1,"sys_msg":2,"sys_msg_style":1,"up":1}}';

const _singleUnread =
    '{"code":0,"msg":"0","message":"0","ttl":1,"data":{"unfollow_unread":1,"follow_unread":6,'
    '"unfollow_push_msg":2,"dustbin_push_msg":0,"dustbin_unread":3,"biz_msg_unfollow_unread":4,'
    '"biz_msg_follow_unread":5,"custom_unread":1}}';

/// Made-up notices: a reply to a comment under a video, a reply under a post with its picture, and one without an id.
const _replies = r'''
{"code":0,"message":"0","ttl":1,"data":{"cursor":{"is_end":false,"id":3000002,"time":1760000100},"items":[
 {"id":3000001,"user":{"mid":20000901,"fans":0,"nickname":"测试回复一","avatar":"https://i0.hdslb.com/bfs/face/a.jpg","mid_link":"","follow":true},
  "item":{"subject_id":80433022,"root_id":4000001,"source_id":4000003,"target_id":4000002,"type":"reply","business_id":1,
   "business":"评论","title":"测试视频标题","desc":"","image":"","uri":"https://www.bilibili.com/video/BV1GJ411x7h7",
   "native_uri":"bilibili://comment/detail/1/80433022/4000001/?anchor=4000003","detail_title":"",
   "root_reply_content":"测试根评论","source_content":"测试回复内容[doge]","target_reply_content":"测试被回复评论",
   "at_details":[],"topic_details":[],"hide_reply_button":false,"hide_like_button":true,"like_state":1,"danmu":null,"message":""},
  "counts":1,"is_multi":0,"reply_time":1760000200},
 {"id":3000002,"user":{"mid":"20000902","nickname":"测试回复二","avatar":"","follow":false},
  "item":{"subject_id":"1073543151725051921","root_id":0,"source_id":4000004,"target_id":0,"type":"dynamic","business_id":17,
   "business":"动态","title":"测试动态","image":"https://i0.hdslb.com/bfs/new_dyn/x.jpg",
   "uri":"https://www.bilibili.com/opus/1073543151725051921#reply4000004",
   "native_uri":"bilibili://opus/detail/1073543151725051921?comment_root_id=4000004&comment_on=1",
   "root_reply_content":"测试根评论二","source_content":"测试第二条","target_reply_content":"","hide_reply_button":true,"like_state":0},
  "reply_time":1760000100},
 {"user":{"mid":1},"item":{}}
],"last_view_at":1760000150}}''';

const _mentions = r'''
{"code":0,"message":"0","ttl":1,"data":{"cursor":{"is_end":true,"id":3100001,"time":1760000300},"items":[
 {"id":3100001,"user":{"mid":20000903,"nickname":"测试提及","avatar":""},
  "item":{"subject_id":80433022,"root_id":4100001,"source_id":4100002,"target_id":0,"type":"reply","business_id":1,"business":"评论",
   "title":"测试视频标题","image":"","uri":"","native_uri":"","source_content":"@测试用户 你看"},
  "at_time":1760000300}
]}}''';

/// The first page's `latest` repeats a row of `total`; later pages repeat `latest` too.
const _likes = r'''
{"code":0,"message":"0","ttl":1,"data":{
 "latest":{"items":[
  {"id":5000003,"users":[{"mid":20000911,"nickname":"测试点赞一","avatar":"https://i0.hdslb.com/bfs/face/l1.jpg","follow":false},
    {"mid":20000912,"nickname":"测试点赞二","avatar":"","follow":true}],
   "item":{"item_id":4000010,"pid":0,"type":"reply","business":"评论","business_id":1,"title":"测试我的评论","desc":"","image":"",
    "uri":"https://www.bilibili.com/video/BV1GJ411x7h7#reply4000010","native_uri":"bilibili://video/80433022?comment_root_id=4000010"},
   "counts":5,"like_time":1760000300,"notice_state":0}],"last_view_at":1760000000},
 "total":{"cursor":{"is_end":false,"id":5000001,"time":1760000000},"items":[
  {"id":5000003,"users":[{"mid":20000911,"nickname":"测试点赞一","avatar":""}],"item":{"item_id":4000010,"business":"评论"},
   "counts":5,"like_time":1760000300,"notice_state":0},
  {"id":5000001,"users":[{"mid":20000913,"nickname":"测试点赞三","avatar":""}],
   "item":{"item_id":6000001,"business":"弹幕","title":"测试我的弹幕","image":"https://i0.hdslb.com/bfs/x.jpg","uri":"","native_uri":""},
   "counts":0,"like_time":1760000000,"notice_state":1}]}}}''';

/// A person whose last message is an auto reply, two official accounts, a picture the account sent, a withdrawn
/// message, a group, and a session with no talker.
const _sessions = r'''
{"code":0,"msg":"0","message":"0","ttl":1,"data":{"session_list":[
 {"talker_id":20000921,"session_type":1,"top_ts":1760000000000000,"ack_seqno":100,"session_ts":1760000500000001,"unread_count":2,
  "max_seqno":102,"system_msg_type":0,"is_follow":1,
  "last_msg":{"sender_uid":20000921,"receiver_type":1,"receiver_id":12345,"msg_type":1,"content":"{\"content\":\"谢谢关注\\n 测试\"}",
   "msg_seqno":102,"timestamp":1760000500,"msg_key":7300000000000000001,"msg_status":0,"msg_source":8}},
 {"talker_id":844424930131966,"session_type":1,"top_ts":0,"ack_seqno":1,"session_ts":1760000400000000,"unread_count":0,"max_seqno":5,
  "system_msg_type":7,"account_info":{"name":"UP主小助手","pic_url":"https://message.biliimg.com/bfs/im/up.png"},
  "last_msg":{"sender_uid":844424930131966,"msg_type":10,"content":"{\"title\":\"测试通知标题\",\"text\":\"测试通知正文\"}",
   "msg_seqno":5,"timestamp":1760000400,"msg_key":1,"msg_status":0,"msg_source":6}},
 {"talker_id":844424930131900,"session_type":1,"session_ts":1760000300000000,"unread_count":1,"ack_seqno":8,"max_seqno":9,
  "system_msg_type":0,"account_info":{"name":"服务通知","pic_url":"https://message.biliimg.com/bfs/im/service.png"},
  "last_msg":{"sender_uid":844424930131900,"msg_type":10,"content":"{\"title\":\"测试服务通知\"}","msg_seqno":9,
   "timestamp":1760000300,"msg_key":2,"msg_status":0}},
 {"talker_id":20000922,"session_type":1,"session_ts":1760000200000000,"unread_count":0,"max_seqno":30,
  "last_msg":{"sender_uid":12345,"msg_type":2,"content":"{\"url\":\"https://message.biliimg.com/bfs/im_new/p.jpg\",\"width\":300,\"height\":200}",
   "msg_seqno":30,"timestamp":1760000200,"msg_key":3,"msg_status":0}},
 {"talker_id":20000923,"session_type":1,"session_ts":1760000100000000,
  "last_msg":{"sender_uid":20000923,"msg_type":1,"content":"{\"content\":\"测试撤回内容\"}","msg_seqno":40,"timestamp":1760000100,
   "msg_key":4,"msg_status":1}},
 {"talker_id":221082140,"session_type":2,"group_name":"测试应援团","group_cover":"https://i0.hdslb.com/bfs/face/g.jpg",
  "session_ts":1760000050000000,"unread_count":3,"max_seqno":20,
  "last_msg":{"sender_uid":0,"receiver_type":2,"msg_type":306,"content":"{\"group_id\":221082140,\"content\":\"欢迎测试入群\"}",
   "msg_seqno":20,"timestamp":1760000050,"msg_key":5,"msg_status":0,"msg_source":13}},
 {"session_type":1}
],"has_more":1,"anti_disturb_cleaning":false,"system_msg":{"7":844424930131966},"show_level":true}}''';

/// Newest first, as the answer gives them: a text with an emote, the take-back of the message below it, that
/// withdrawn message, an auto reply, a picture, the grey tip, a video push, an unknown type, and one without a seqno.
const _messages = r'''
{"code":0,"msg":"0","message":"0","ttl":1,"data":{"messages":[
 {"sender_uid":20000921,"receiver_type":1,"receiver_id":12345,"msg_type":1,"content":"{\"content\":\"你好[doge]\"}","msg_seqno":105,
  "timestamp":1760000600,"msg_key":7300000000000000005,"msg_status":0,"new_face_version":1,"msg_source":2},
 {"sender_uid":12345,"msg_type":5,"content":"7300000000000000003","msg_seqno":104,"timestamp":1760000590,"msg_key":7300000000000000004,
  "msg_status":0,"msg_source":7},
 {"sender_uid":12345,"msg_type":1,"content":"{\"content\":\"测试已撤回的话\"}","msg_seqno":103,"timestamp":1760000580,
  "msg_key":7300000000000000003,"msg_status":1,"msg_source":7},
 {"sender_uid":20000921,"msg_type":1,"content":"{\"content\":\"感谢关注[脱单doge]\"}","msg_seqno":102,"timestamp":1760000500,
  "msg_key":7300000000000000002,"msg_status":0,"msg_source":8},
 {"sender_uid":20000921,"msg_type":2,"content":"{\"url\":\"https://message.biliimg.com/bfs/im_new/p.jpg\",\"height\":200,\"width\":300.0,\"imageType\":\"jpeg\",\"original\":1,\"size\":54.1}",
  "msg_seqno":101,"timestamp":1760000400,"msg_key":7300000000000000001,"msg_status":0},
 {"sender_uid":0,"msg_type":18,"content":"{\"content\":\"[{\\\"text\\\":\\\"对方主动回复或关注你前，最多发送1条消息\\\",\\\"color_day\\\":\\\"#9499A0\\\"}]\"}",
  "msg_seqno":100,"timestamp":1760000300,"msg_key":7300000000000000000,"msg_status":0,"msg_source":18},
 {"sender_uid":20000921,"msg_type":11,"content":"{\"title\":\"测试推送视频\",\"rid\":80433022,\"bvid\":\"BV1GJ411x7h7\"}","msg_seqno":99,
  "timestamp":1760000200,"msg_key":6,"msg_status":0,"msg_source":6},
 {"sender_uid":20000921,"msg_type":999,"content":"{}","msg_seqno":98,"timestamp":1760000100,"msg_key":7,"msg_status":0},
 {"msg_type":1}
],"has_more":1,"min_seqno":98,"max_seqno":105,"e_infos":[
 {"text":"[doge]","url":"https://i0.hdslb.com/bfs/emote/doge.png","size":1},
 {"text":"[脱单doge]","uri":"https://i0.hdslb.com/bfs/emote/tdoge.png","size":1},
 {"text":"[未用]","url":"https://i0.hdslb.com/bfs/emote/u.png"}]}}''';

const _noticeCard = r'''
{"code":0,"msg":"0","message":"0","ttl":1,"data":{"messages":[
 {"sender_uid":844424930131966,"msg_type":10,"msg_seqno":5,"timestamp":1760000400,"msg_key":1,"msg_status":0,"msg_source":6,
  "content":"{\"title\":\"测试装扮通知\",\"text\":\"测试正文\",\"jump_text\":\"立即查看\",\"jump_uri\":\"https://www.bilibili.com/h5/x\",\"modules\":[{\"title\":\"有效期\",\"detail\":\"永久有效\"},\"坏模块\"],\"jump_text_2\":\"\",\"jump_uri_2\":\"\",\"jump_text_3\":\"\",\"jump_uri_3\":\"https://www.bilibili.com/h5/y\",\"jump_uri_config\":{\"all_uri\":\"https://www.bilibili.com/h5/all\",\"web_uri\":\"\",\"text\":\"\"},\"jump_uri_2_config\":{\"text\":\"更多装扮\"},\"jump_uri_3_config\":{\"text\":\"\"}}"}
],"has_more":0,"min_seqno":5,"max_seqno":5}}''';

const _cards = r'''
{"code":0,"message":"0","ttl":1,"data":[
 {"mid":20000921,"name":"测试私信一","face":"https://i0.hdslb.com/bfs/face/c1.jpg","sign":"","vip":{"type":2,"status":1,"avatar_subscript":1},
  "pendant":{"image":"https://i0.hdslb.com/bfs/garb/p.png"},"official":{"type":0}},
 {"mid":"20000922","name":"测试私信二","face":"","vip":{"vipType":1,"vipStatus":1,"avatar_subscript":0},"official":{"type":1}},
 {"mid":20000923,"name":"测试私信三","face":"","vip":{"vipType":0,"vipStatus":0},"official":{"type":-1}},
 {"name":"坏数据"}
]}''';

const _sent =
    '{"code":0,"message":"0","ttl":1,"data":{"msg_key":7300000000000000009,"e_infos":[{"text":"[doge]",'
    '"url":"https://i0.hdslb.com/bfs/emote/doge.png","size":1}],"msg_content":"{\\"content\\":\\"测试发送[doge]\\"}",'
    '"key_hit_infos":{}}}';

/// 2025-10-09 17:01:40 in Beijing is 1760000500; the second notice's `time_at` won't parse, so its cursor tells.
const _systemNotices = r'''
{"code":0,"message":"0","ttl":1,"data":[
 {"id":9000002,"cursor":1760000500000000000,"type":1,"title":"测试系统通知二",
  "content":"测试内容，详见#{活动页}{\"//www.bilibili.com/blackboard/x.html\"}。","time_at":"2025-10-09 17:01:40","card_type":2},
 {"id":9000001,"cursor":1760000400000000000,"type":1,"title":"测试系统通知一",
  "content":"{\"web\":\"测试网页正文 https://www.bilibili.com/x\",\"app\":\"测试app正文\"}","time_at":"bad time"},
 {"id":1,"title":"没有游标"}
]}''';

void main() {
  late FakeHTTP http;
  late BiliClient client;
  late MemorySink sink;

  setUp(() {
    http = FakeHTTP();
    http.routes[_navPath] = (200, Fixtures.navLoggedIn);
    sink = MemorySink();
    client = BiliClient(
      transport: http,
      cookies: CookieJar({'SESSDATA': 'MADE-UP-SESSION', 'bili_jct': 'MADE-UP-CSRF', 'buvid3': 'b3', 'buvid4': 'b4'}),
      now: () => testNow,
      logger: Logger(session: 'test')..add(sink),
    );
  });

  String log() => sink.events.map((event) => event.encode()).join('\n');

  /// The form back into fields, names percent-decoded too (send_msg's `msg[…]` brackets go out escaped).
  Map<String, String> form(HTTPRequest request) => {
    for (final MapEntry(:key, :value) in formFields(http.bodyText(request)).entries) Uri.decodeComponent(key): value,
  };

  /// The signed query rebuilt from the request's own fields: the signature covers exactly them.
  void expectSigned(HTTPRequest request) {
    final query = http.query(request);
    final fields = Map.of(query)
      ..remove('w_rid')
      ..remove('wts');
    expect(request.url.query, WBI.signedQuery(fields, mixinKey: _mixinKey, wts: int.parse(query['wts']!)));
  }

  group('red counts', () {
    test('msgfeed unread asks /x/msgfeed/unread as the website, unsigned', () async {
      http.routes[_unreadPath] = (200, _feedUnread);
      final unread = await client.msgfeedUnread();
      expect(unread, (reply: 1, at: 3, like: 10, system: 2));
      final request = http.requestsTo(_unreadPath).single;
      expect((request.method, request.url.host), ('GET', 'api.bilibili.com'));
      expect(http.query(request), _web);
      expect(request.headers['Referer'], 'https://message.bilibili.com/');
    });

    test('私信 unread is followed plus unfollowed, from api.vc with the login cookies', () async {
      http.routes[_singleUnreadPath] = (200, _singleUnread);
      expect(await client.chatUnread(), 7);
      final request = http.requestsTo(_singleUnreadPath).single;
      expect((request.method, request.url.host), ('GET', _vc));
      expect(http.query(request), {'unread_type': '0', ..._web});
      expect(request.headers['Cookie'], contains('SESSDATA=MADE-UP-SESSION'));
    });
  });

  group('回复与@', () {
    test('the first page asks no cursor; the next sends the last id and reply_time', () async {
      http.routes[_replyPath] = (200, _replies);
      final page = await client.replyNotices();
      expect(http.query(http.requestsTo(_replyPath).single), {'platform': 'web', ..._web});
      expect((page.next?.id, page.next?.time), (3000002, 1760000100));
      await client.replyNotices(cursor: page.next);
      expect(http.query(http.requestsTo(_replyPath).last), {
        'platform': 'web',
        ..._web,
        'id': '3000002',
        'reply_time': '1760000100',
      });
    });

    test('each reply decodes what the row draws and acts on; one without an id costs only itself', () async {
      http.routes[_replyPath] = (200, _replies);
      final [first, second] = (await client.replyNotices()).items;
      expect(first.id, 3000001);
      expect(first.feed, NoticeFeed.reply);
      expect(
        (first.user.mid, first.user.name, first.user.face, first.user.following),
        (20000901, '测试回复一', 'https://i0.hdslb.com/bfs/face/a.jpg', true),
      );
      expect((first.business, first.businessId, first.subjectId), ('reply', 1, 80433022));
      expect((first.rootId, first.sourceId, first.targetId), (4000001, 4000003, 4000002));
      expect(first.text, '测试回复内容[doge]');
      expect(first.targetText, '测试被回复评论');
      expect(first.title, '测试视频标题');
      expect(first.uri, 'https://www.bilibili.com/video/BV1GJ411x7h7');
      expect(first.nativeUri, startsWith('bilibili://comment/detail/1/80433022/'));
      expect((first.liked, first.canReply, first.canLike, first.fromUploader), (true, true, false, false));
      expect(first.time.millisecondsSinceEpoch, 1760000200000);

      expect(second.user.mid, 20000902);
      expect((second.business, second.businessId, second.subjectId), ('dynamic', 17, 1073543151725051921));
      expect(second.targetText, '测试根评论二', reason: 'no target_reply_content, so the root comment');
      expect(second.image, 'https://i0.hdslb.com/bfs/new_dyn/x.jpg');
      expect((second.liked, second.canReply, second.canLike), (false, false, true));
    });

    test('@我 pages by at_time, and is_end ends it', () async {
      http.routes[_atPath] = (200, _mentions);
      final page = await client.atNotices(cursor: const NoticeCursor(id: 3100009, time: 1760000900));
      expect(http.query(http.requestsTo(_atPath).single), {
        'platform': 'web',
        ..._web,
        'id': '3100009',
        'at_time': '1760000900',
      });
      final mention = page.items.single;
      expect((mention.feed, mention.text, mention.user.name), (NoticeFeed.at, '@测试用户 你看', '测试提及'));
      expect(mention.time.millisecondsSinceEpoch, 1760000300000);
      expect(page.next, isNull);
    });
  });

  group('收到喜欢', () {
    test('the first page shows latest then total, a row in both once; later pages leave latest out', () async {
      http.routes[_likePath] = (200, _likes);
      final first = await client.likeNotices();
      expect(first.items.map((notice) => notice.id), [5000003, 5000001]);
      expect(http.query(http.requestsTo(_likePath).single), {'platform': 'web', ..._web});
      expect((first.next?.id, first.next?.time), (5000001, 1760000000));

      final next = await client.likeNotices(cursor: first.next);
      expect(http.query(http.requestsTo(_likePath).last)['like_time'], '1760000000');
      expect(next.items.map((notice) => notice.id), [5000003, 5000001], reason: 'only total, which has both');
    });

    test('a like row: its likers newest first, the total, what was liked and whether it still notifies', () async {
      http.routes[_likePath] = (200, _likes);
      final [latest, older] = (await client.likeNotices()).items;
      expect(latest.users.map((user) => (user.mid, user.name)), [(20000911, '测试点赞一'), (20000912, '测试点赞二')]);
      expect(latest.users.last.following, isTrue);
      expect((latest.count, latest.business, latest.itemId, latest.title), (5, '评论', 4000010, '测试我的评论'));
      expect(latest.nativeUri, 'bilibili://video/80433022?comment_root_id=4000010');
      expect(latest.notifying, isTrue);
      expect(latest.time.millisecondsSinceEpoch, 1760000300000);
      expect((older.count, older.business, older.image), (1, '弹幕', 'https://i0.hdslb.com/bfs/x.jpg'));
      expect(older.notifying, isFalse);
    });
  });

  group('a row\'s 删除 and 不再通知', () {
    test('删除 posts tp per list with the csrf token twice', () async {
      http.routes['POST $_delPath'] = (200, '{"code":0,"message":"0","ttl":1}');
      await client.deleteNotice(NoticeFeed.like, 5000003);
      await client.deleteNotice(NoticeFeed.reply, 3000001);
      await client.deleteNotice(NoticeFeed.at, 3100001);
      final [like, reply, at] = http.requestsTo(_delPath);
      expect(like.method, 'POST');
      expect(like.url.host, 'api.bilibili.com');
      expect(form(like), {'tp': '0', 'id': '5000003', ..._web, 'csrf_token': 'MADE-UP-CSRF', 'csrf': 'MADE-UP-CSRF'});
      expect(form(reply)['tp'], '1');
      expect(form(at)['tp'], '2');
    });

    test('不再通知 sends notice_state 1, turning it back on 0', () async {
      http.routes['POST $_noticePath'] = (200, '{"code":0,"message":"0","ttl":1}');
      await client.setNoticeNotify(NoticeFeed.like, 5000003, on: false);
      await client.setNoticeNotify(NoticeFeed.like, 5000003, on: true);
      final [off, on] = http.requestsTo(_noticePath);
      expect(form(off), {
        'tp': '0',
        'id': '5000003',
        'notice_state': '1',
        'platform': 'web',
        ..._web,
        'csrf_token': 'MADE-UP-CSRF',
        'csrf': 'MADE-UP-CSRF',
      });
      expect(form(on)['notice_state'], '0');
    });
  });

  group('sessions', () {
    test('get_sessions is asked WBI-signed on api.vc, folded as the website, end_ts for the next page', () async {
      http.routes[_sessionsPath] = (200, _sessions);
      final page = await client.chatSessions();
      final request = http.requestsTo(_sessionsPath).single;
      expect((request.method, request.url.host), ('GET', _vc));
      final query = http.query(request);
      expect(
        query
          ..remove('w_rid')
          ..remove('wts'),
        {'session_type': '1', 'group_fold': '1', 'unfollow_fold': '0', 'sort_rule': '2', ..._web},
      );
      expectSigned(request);
      expect(page.next, 1760000050000000);

      await client.chatSessions(endTs: page.next);
      expect(http.query(http.requestsTo(_sessionsPath).last)['end_ts'], '1760000050000000');
    });

    test('each session: the last message as 196 shows it, unread, seqnos, 置顶 and its notice box', () async {
      http.routes[_sessionsPath] = (200, _sessions);
      final sessions = (await client.chatSessions()).sessions;
      expect(sessions, hasLength(6));
      final [person, helper, service, picture, withdrawn, group] = sessions;

      expect((person.talkerId, person.sessionType, person.name, person.face), (20000921, 1, '', ''));
      expect(person.lastText, '[自动回复] 谢谢关注 测试');
      expect((person.unread, person.ackSeqno, person.maxSeqno, person.top), (2, 100, 102, true));
      expect(person.time.microsecondsSinceEpoch, 1760000500000001);
      expect(person.box, isNull);

      expect((helper.name, helper.face), ('UP主小助手', 'https://message.biliimg.com/bfs/im/up.png'));
      expect(helper.box, NoticeBox.creator);
      expect(helper.lastText, '测试通知标题');
      expect(helper.top, isFalse);

      expect((service.name, service.box, service.unread), ('服务通知', NoticeBox.service, 1));
      expect(picture.lastText, '[图片]');
      expect(withdrawn.lastText, '对方撤回了一条消息');
      expect((group.sessionType, group.name, group.face), (2, '测试应援团', 'https://i0.hdslb.com/bfs/face/g.jpg'));
      expect(group.lastText, '欢迎测试入群');
    });

    test('user cards name the bare sessions: 大会员 pink, the 大, verify and the frame', () async {
      http.routes[_cardsPath] = (200, _cards);
      final [one, two, three] = await client.chatUserCards([20000921, 20000922, 20000923]);
      final request = http.requestsTo(_cardsPath).single;
      expect((request.method, request.url.host), ('GET', _vc));
      expect(http.query(request), {'uids': '20000921,20000922,20000923', ..._web});
      expect((one.mid, one.name, one.face), (20000921, '测试私信一', 'https://i0.hdslb.com/bfs/face/c1.jpg'));
      expect((one.vipPink, one.bigVip, one.verify), (true, true, DynamicVerify.personal));
      expect(one.pendant, 'https://i0.hdslb.com/bfs/garb/p.png');
      expect((two.mid, two.vipPink, two.bigVip, two.verify), (20000922, true, false, DynamicVerify.organisation));
      expect((three.vipPink, three.bigVip, three.verify, three.pendant), (false, false, DynamicVerify.none, ''));
    });

    test('no mids asks nothing', () async {
      expect(await client.chatUserCards(const []), isEmpty);
      expect(http.requests, isEmpty);
    });
  });

  group('a chat', () {
    test('fetch_session_msgs is signed, 20 a page, end_seqno for older ones', () async {
      http.routes[_messagesPath] = (200, _messages);
      final page = await client.chatMessages(20000921);
      final request = http.requestsTo(_messagesPath).single;
      expect((request.method, request.url.host), ('GET', _vc));
      final query = http.query(request);
      expect(
        query
          ..remove('w_rid')
          ..remove('wts'),
        {'talker_id': '20000921', 'session_type': '1', 'size': '20', 'sender_device_id': '1', ..._web},
      );
      expectSigned(request);
      expect((page.hasMore, page.minSeqno, page.maxSeqno), (true, 98, 105));

      await client.chatMessages(20000921, beforeSeqno: page.minSeqno);
      expect(http.query(http.requestsTo(_messagesPath).last)['end_seqno'], '98');
    });

    test(
      'messages come oldest first, each as it draws; a take-back is dropped and what it took back loses its text',
      () async {
        http.routes[_messagesPath] = (200, _messages);
        final messages = (await client.chatMessages(20000921)).messages;
        expect(messages.map((message) => message.seqno), [98, 99, 100, 101, 102, 103, 105]);
        final [unknown, push, tip, picture, autoReply, withdrawn, text] = messages;

        expect(
          (text.kind, text.text, text.senderMid, text.key),
          (ChatMessageKind.text, '你好[doge]', 20000921, 7300000000000000005),
        );
        expect(text.emotes, {'[doge]': 'https://i0.hdslb.com/bfs/emote/doge.png'});
        expect(text.autoReply, isFalse);
        expect(text.time.millisecondsSinceEpoch, 1760000600000);

        expect((withdrawn.kind, withdrawn.text, withdrawn.senderMid), (ChatMessageKind.withdrawn, '', 12345));
        expect((autoReply.kind, autoReply.autoReply), (ChatMessageKind.text, true));
        expect(autoReply.emotes, {'[脱单doge]': 'https://i0.hdslb.com/bfs/emote/tdoge.png'});
        expect(
          (picture.kind, picture.picture, picture.pictureWidth, picture.pictureHeight),
          (ChatMessageKind.picture, 'https://message.biliimg.com/bfs/im_new/p.jpg', 300, 200),
        );
        expect((tip.kind, tip.text), (ChatMessageKind.tip, '对方主动回复或关注你前，最多发送1条消息'));
        expect((push.kind, push.text), (ChatMessageKind.other, '[视频]测试推送视频'));
        expect((unknown.kind, unknown.text), (ChatMessageKind.other, ''));
      },
    );

    test('a notice card: title, body, labelled lines and up to three buttons', () async {
      http.routes[_messagesPath] = (200, _noticeCard);
      final card = (await client.chatMessages(844424930131966)).messages.single;
      expect((card.kind, card.title, card.text), (ChatMessageKind.notice, '测试装扮通知', '测试正文'));
      expect(card.fields, [(title: '有效期', detail: '永久有效')]);
      expect(card.links, [
        (text: '立即查看', uri: 'https://www.bilibili.com/h5/all'),
        (text: '查看详情', uri: 'https://www.bilibili.com/h5/y'),
      ]);
    });

    test('opening a chat acks it: update_ack posted on api.vc with the session and seqno', () async {
      http.routes['POST $_ackPath'] = (200, _ok);
      await client.ackChat(20000921, seqno: 105);
      final request = http.requestsTo(_ackPath).single;
      expect((request.method, request.url.host), ('POST', _vc));
      expect(request.url.query, isEmpty);
      expect(form(request), {
        'talker_id': '20000921',
        'session_type': '1',
        'ack_seqno': '105',
        ..._web,
        'csrf_token': 'MADE-UP-CSRF',
        'csrf': 'MADE-UP-CSRF',
      });
    });

    test('send_msg: the w_ fields signed in the URL, the message in the form, one dev_id per client', () async {
      http.routes['POST $_sendPath'] = (200, _sent);
      final sent = await client.sendChatText(senderMid: 12345, talkerId: 20000921, text: '测试发送[doge]');
      await client.sendChatText(senderMid: 12345, talkerId: 20000921, text: '第二条');
      final [first, second] = http.requestsTo(_sendPath);
      expect((first.method, first.url.host), ('POST', _vc));
      final query = http.query(first);
      final devId = query['w_dev_id']!;
      expect(devId, matches(RegExp(r'^[0-9A-F]{8}-[0-9A-F]{4}-4[0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12}$')));
      expect(query['w_sender_uid'], '12345');
      expect(query['w_receiver_id'], '20000921');
      expect(query['wts'], '${testNow.millisecondsSinceEpoch ~/ 1000}');
      expectSigned(first);
      expect(form(first), {
        'msg[sender_uid]': '12345',
        'msg[receiver_id]': '20000921',
        'msg[receiver_type]': '1',
        'msg[msg_type]': '1',
        'msg[msg_status]': '0',
        'msg[dev_id]': devId,
        'msg[timestamp]': '${testNow.millisecondsSinceEpoch ~/ 1000}',
        'msg[new_face_version]': '1',
        'msg[content]': '{"content":"测试发送[doge]"}',
        'from_firework': '0',
        ..._web,
        'csrf_token': 'MADE-UP-CSRF',
        'csrf': 'MADE-UP-CSRF',
      });
      expect(http.query(second)['w_dev_id'], devId);

      expect(
        (sent.kind, sent.text, sent.senderMid, sent.key, sent.seqno),
        (ChatMessageKind.text, '测试发送[doge]', 12345, 7300000000000000009, 0),
      );
      expect(sent.emotes, {'[doge]': 'https://i0.hdslb.com/bfs/emote/doge.png'});
      expect(sent.time.millisecondsSinceEpoch, testNow.millisecondsSinceEpoch);
      expect(log(), isNot(contains('测试发送')));
      expect(log(), isNot(contains('MADE-UP-CSRF')));
      expect(log(), isNot(contains('20000921')));
    });

    test('a different client makes its own dev_id', () async {
      http.routes['POST $_sendPath'] = (200, _sent);
      final other = makeTestClient(http, cookies: {'SESSDATA': 's', 'bili_jct': 'j'});
      await client.sendChatText(senderMid: 12345, talkerId: 20000921, text: '一');
      await other.sendChatText(senderMid: 12345, talkerId: 20000921, text: '二');
      final [mine, theirs] = http.requestsTo(_sendPath);
      expect(http.query(mine)['w_dev_id'], isNot(http.query(theirs)['w_dev_id']));
    });

    test('nothing to send is refused unsent; a refusal throws its code', () async {
      await expectLater(client.sendChatText(senderMid: 12345, talkerId: 20000921, text: '  '), throwsArgumentError);
      expect(http.requestsTo(_sendPath), isEmpty);
      http.routes['POST $_sendPath'] = (200, '{"code":21047,"message":"测试限制","ttl":1}');
      await expectLater(
        client.sendChatText(senderMid: 12345, talkerId: 20000921, text: '测试'),
        throwsA(const BiliError.api(code: 21047, message: '测试限制')),
      );
    });

    test('the bar: 加关注 from follow_status, 不接受推送 from push_setting', () async {
      http.routes[_sessionSettingsPath] = (
        200,
        '{"code":0,"msg":"0","message":"0","ttl":1,"data":{"follow_status":6,"special":1,"push_setting":1,"show_push_setting":1}}',
      );
      final settings = await client.chatSettings(20000921);
      final request = http.requestsTo(_sessionSettingsPath).single;
      expect((request.method, request.url.host), ('GET', _vc));
      expect(http.query(request), {'talker_uid': '20000921', ..._web});
      expect((settings.following, settings.pushOn, settings.showPush), (true, false, true));
    });

    test('不接受推送 posts set_push_ss: setting 1 off, 0 on', () async {
      http.routes['POST $_pushPath'] = (200, _ok);
      await client.setChatPush(20000921, on: false);
      await client.setChatPush(20000921, on: true);
      final [off, on] = http.requestsTo(_pushPath);
      expect(off.url.host, _vc);
      expect(form(off), {
        'talker_uid': '20000921',
        'setting': '1',
        ..._web,
        'csrf_token': 'MADE-UP-CSRF',
        'csrf': 'MADE-UP-CSRF',
      });
      expect(form(on)['setting'], '0');
    });
  });

  group('系统通知', () {
    test('query_notify_list on message.bilibili.com, 20 a page, cursor for older ones', () async {
      http.routes[_systemPath] = (200, _systemNotices);
      final page = await client.systemNotices();
      final request = http.requestsTo(_systemPath).single;
      expect((request.method, request.url.host), ('GET', _center));
      expect(http.query(request), {'page_size': '20', ..._web});
      expect(request.headers['Cookie'], contains('SESSDATA=MADE-UP-SESSION'));
      expect((page.minSeqno, page.maxSeqno, page.hasMore), (1760000400000000000, 1760000500000000000, false));

      await client.systemNotices(cursor: page.minSeqno);
      expect(http.query(http.requestsTo(_systemPath).last)['cursor'], '1760000400000000000');
    });

    test('each notice: oldest first, the web text, its links lifted out of the markup, Beijing time', () async {
      http.routes[_systemPath] = (200, _systemNotices);
      final [older, newer] = (await client.systemNotices()).messages;
      expect(
        (newer.kind, newer.seqno, newer.key, newer.senderMid),
        (ChatMessageKind.notice, 1760000500000000000, 9000002, 0),
      );
      expect((newer.title, newer.text), ('测试系统通知二', '测试内容，详见活动页。'));
      expect(newer.links, [(text: '活动页', uri: 'https://www.bilibili.com/blackboard/x.html')]);
      expect(newer.time.millisecondsSinceEpoch, 1760000500000);
      expect((older.title, older.text, older.links.isEmpty), ('测试系统通知一', '测试网页正文 https://www.bilibili.com/x', true));
      expect(older.time.millisecondsSinceEpoch, 1760000400000, reason: 'from the cursor, in nanoseconds');
    });

    test('no notices is an empty last page', () async {
      http.routes[_systemPath] = (200, '{"code":0,"message":"0","ttl":1,"data":null}');
      final page = await client.systemNotices();
      expect((page.messages.isEmpty, page.hasMore, page.minSeqno), (true, false, 0));
    });

    test('marking them read is update_cursor, a GET with the csrf token', () async {
      http.routes[_cursorPath] = (200, '{"code":0,"message":"0","ttl":1}');
      await client.ackSystemNotices(1760000500000000000);
      final request = http.requestsTo(_cursorPath).single;
      expect((request.method, request.url.host), ('GET', _center));
      expect(http.query(request), {'cursor': '1760000500000000000', 'has_up': '0', ..._web, 'csrf': 'MADE-UP-CSRF'});
      expect(log(), isNot(contains('MADE-UP-CSRF')));
    });
  });

  group('一键已读', () {
    void answerAll({required String unread}) {
      http.routes[_unreadPath] = (200, unread);
      http.routes[_sessionsPath] = (200, _sessions);
      http.routes['POST $_ackPath'] = (200, _ok);
      http.routes[_systemPath] = (200, _systemNotices);
      http.routes[_cursorPath] = (200, '{"code":0,"message":"0","ttl":1}');
      http.routes[_replyPath] = (200, _replies);
      http.routes[_atPath] = (200, _mentions);
      http.routes[_likePath] = (200, _likes);
    }

    test('acks every unread session on the first page, moves 系统通知 on, and reads the lists with unread', () async {
      answerAll(unread: '{"code":0,"message":"0","ttl":1,"data":{"reply":1,"at":0,"like":2,"sys_msg":1}}');
      await client.readAllMessages();
      expect(
        [
          for (final request in http.requests)
            if (request.url.path != _navPath) request.url.path,
        ],
        [_unreadPath, _sessionsPath, _ackPath, _ackPath, _ackPath, _systemPath, _cursorPath, _replyPath, _likePath],
      );
      final acks = [
        for (final request in http.requestsTo(_ackPath))
          (form(request)['talker_id'], form(request)['session_type'], form(request)['ack_seqno']),
      ];
      expect(acks, [('20000921', '1', '102'), ('844424930131900', '1', '9'), ('221082140', '2', '20')]);
      expect(http.query(http.requestsTo(_cursorPath).single)['cursor'], '1760000500000000000');
    });

    test('with nothing unread it only looks', () async {
      answerAll(unread: '{"code":0,"message":"0","ttl":1,"data":{"reply":0,"at":0,"like":0,"sys_msg":0}}');
      http.routes[_sessionsPath] = (
        200,
        '{"code":0,"msg":"0","message":"0","ttl":1,"data":{"session_list":null,"has_more":0}}',
      );
      await client.readAllMessages();
      expect(
        [
          for (final request in http.requests)
            if (request.url.path != _navPath) request.url.path,
        ],
        [_unreadPath, _sessionsPath],
      );
    });

    test('it stops at the first refusal', () async {
      answerAll(unread: '{"code":0,"message":"0","ttl":1,"data":{"reply":1,"at":1,"like":1,"sys_msg":1}}');
      http.routes['POST $_ackPath'] = (200, '{"code":-412,"message":"测试拦截","ttl":1}');
      await expectLater(client.readAllMessages(), throwsA(isA<BiliAPIError>().having((e) => e.code, 'code', -412)));
      expect(http.requestsTo(_ackPath), hasLength(1));
      expect(http.requestsTo(_systemPath), isEmpty);
    });
  });

  group('消息设置', () {
    test('link_setting/get reads the three pickers from the new fields', () async {
      http.routes[_settingsPath] = (
        200,
        '{"code":0,"msg":"0","message":"0","ttl":1,"data":{"set_like":5,"set_comment":2,"set_at":2,"set_recv_reply":1,'
            '"set_recv_like":2,"set_new_follow":0,"msg_notify":1}}',
      );
      final settings = await client.noticeSettings();
      final request = http.requestsTo(_settingsPath).single;
      expect((request.method, request.url.host), ('GET', _vc));
      expect(http.query(request), _web);
      expect(settings, {
        NoticeSettingKind.replies: NoticeAudience.following,
        NoticeSettingKind.likes: NoticeAudience.off,
        NoticeSettingKind.fans: NoticeAudience.everyone,
      });
    });

    test('a choice posts only its own field to link_setting/set', () async {
      http.routes['POST $_setSettingsPath'] = (200, _ok);
      await client.setNoticeSetting(NoticeSettingKind.likes, NoticeAudience.off);
      await client.setNoticeSetting(NoticeSettingKind.replies, NoticeAudience.following);
      await client.setNoticeSetting(NoticeSettingKind.fans, NoticeAudience.everyone);
      final [likes, replies, fans] = http.requestsTo(_setSettingsPath);
      expect(likes.url.host, _vc);
      expect(form(likes), {'set_recv_like': '2', ..._web, 'csrf_token': 'MADE-UP-CSRF', 'csrf': 'MADE-UP-CSRF'});
      expect(form(replies)['set_recv_reply'], '1');
      expect(form(fans)['set_new_follow'], '0');
    });
  });

  group('failures', () {
    test('an answer with a code throws it, and the log has the path and code but no text', () async {
      http.routes[_messagesPath] = (200, '{"code":700013,"msg":"测试解散","message":"测试解散","ttl":1}');
      await expectLater(
        client.chatMessages(221082140, sessionType: 2),
        throwsA(const BiliError.api(code: 700013, message: '测试解散')),
      );
      expect(log(), contains(_messagesPath));
      expect(log(), contains('700013'));
      expect(log(), isNot(contains('221082140')));
    });

    test('logged out, every write throws needsLogin before anything is sent', () async {
      client.cookies.remove('bili_jct');
      final writes = <Future<Object?> Function()>[
        () => client.deleteNotice(NoticeFeed.reply, 1),
        () => client.setNoticeNotify(NoticeFeed.like, 1, on: false),
        () => client.ackChat(1, seqno: 1),
        () => client.sendChatText(senderMid: 1, talkerId: 2, text: '测试'),
        () => client.ackSystemNotices(1),
        () => client.setChatPush(1, on: false),
        () => client.setNoticeSetting(NoticeSettingKind.fans, NoticeAudience.off),
      ];
      for (final write in writes) {
        await expectLater(write(), throwsA(isA<BiliError>().having((error) => error.needsLogin, 'needsLogin', isTrue)));
      }
      expect(http.requests.where((request) => request.url.path != _navPath), isEmpty);
    });

    test('a body that is not JSON is a decoding error naming no content', () async {
      http.routes[_sessionsPath] = (200, 'not json 测试正文');
      await expectLater(client.chatSessions(), throwsA(isA<BiliDecodingError>()));
      expect(log(), isNot(contains('测试正文')));
    });
  });

  group('the PC guard', () {
    BiliClient guarded() => BiliClient(
      transport: GuardedTransport(http, logger: Logger(session: 'test')),
      cookies: CookieJar({'SESSDATA': 's', 'bili_jct': 'j', 'buvid3': 'b3', 'buvid4': 'b4'}),
      now: () => testNow,
      logger: Logger(session: 'test'),
    );

    test('the acks, sending and settings never leave the PC; the reads do', () async {
      final api = guarded();
      const refused = BiliAPIError(code: GuardedTransport.readOnlyCode, message: 'PC 只读，未发送');
      await expectLater(api.ackChat(1, seqno: 2), throwsA(refused));
      await expectLater(api.ackSystemNotices(3), throwsA(refused));
      await expectLater(api.sendChatText(senderMid: 1, talkerId: 2, text: '测试'), throwsA(refused));
      await expectLater(api.deleteNotice(NoticeFeed.like, 4), throwsA(refused));
      await expectLater(api.setNoticeSetting(NoticeSettingKind.likes, NoticeAudience.off), throwsA(refused));
      expect(
        http.requests.where((request) => request.url.path != _navPath).map((request) => request.url.path),
        isEmpty,
      );

      http.routes[_singleUnreadPath] = (200, _singleUnread);
      expect(await api.chatUnread(), 7);
    });
  });
}
