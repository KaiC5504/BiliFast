import 'dart:convert';

import 'package:bili_core/api.dart';
import 'package:test/test.dart';

import 'fake_http.dart';
import 'fixtures.dart';

/// Shaped after a live /x/v2/reply/main response (2026-10-17); every name, id and text here is invented.
abstract final class CommentFixtures {
  static const memberA = r'''
{"mid":"1001","uname":"测试用户甲","sex":"保密","sign":"","avatar":"https://i0.hdslb.com/bfs/face/face-a.jpg","rank":"10000",
"level_info":{"current_level":6,"current_min":0,"current_exp":0,"next_exp":0},
"pendant":{"pid":4318,"name":"挂件","image":"https://i0.hdslb.com/bfs/garb/item/pendant-a.png","expire":0},
"vip":{"vipType":2,"vipStatus":1,"label":{"path":"","text":""}},
"user_sailing":{"pendant":null,"cardbg":{"id":32261,"name":"装扮","image":"https://i0.hdslb.com/bfs/garb/item/card-a.png","fan":{"is_fan":1,"number":95,"color":"#f35543","name":"装扮","num_desc":"000095","num_prefix":"NO."}},"cardbg_with_focus":null}}''';

  static const memberB = r'''
{"mid":"1002","uname":"测试用户乙","avatar":"https://i0.hdslb.com/bfs/face/face-b.jpg",
"level_info":{"current_level":3},"pendant":{"pid":0,"name":"","image":""},"vip":{"vipType":1,"vipStatus":0},"user_sailing":null}''';

  static String reply(
          {required int rpid,
          required String member,
          required String message,
          String extra = '',
          String content = '',
          String replies = 'null'}) =>
      '{"rpid":$rpid,"oid":80433022,"type":1,"mid":1001,"root":0,"parent":0,"count":12,"rcount":10,"state":0,"ctime":1760000000,\n'
      '"like":321,"action":1,"member":$member,\n'
      '"content":{"message":"$message","members":[]${content.isEmpty ? '' : ',$content'}},\n'
      '"replies":$replies,"up_action":{"like":false,"reply":false},"reply_control":{"time_desc":"3天前发布"$extra}}';

  /// The root comment with an emote, a mention, a jump link, a picture, an up-liked flag and a location.
  static const rich = r'''
{"rpid":9001,"oid":80433022,"type":1,"mid":1001,"root":0,"parent":0,"count":12,"rcount":10,"state":0,"ctime":1760000000,
"like":321,"action":1,"member":''' +
      memberA +
      r''',"content":{"message":"看[doge]\n@测试用户乙 在03:15 BV1GJ411x7h7 蓝链",
"emote":{"[doge]":{"id":1,"url":"https://i0.hdslb.com/bfs/emote/doge.png","meta":{"size":1}}},
"at_name_to_mid":{"测试用户乙":1002},
"jump_url":{"蓝链":{"title":"链接标题","state":0,"pc_url":"//search.bilibili.com/all?keyword=x","app_url_schema":"bilibili://search"}},
"pictures":[{"img_src":"https://i0.hdslb.com/bfs/new_dyn/pic-1.jpg","img_width":1080,"img_height":1920.5,"img_size":12.3}],
"members":[],"max_line":6},
"replies":[''' +
      subReply +
      r'''],"up_action":{"like":true,"reply":false},
"reply_control":{"time_desc":"3天前发布","location":"IP属地：广东"}}''';

  /// A reply to a user who has since renamed: the text keeps the old name, at_name_to_mid holds the new one.
  static const subReply = r'''
{"rpid":9002,"oid":80433022,"type":1,"mid":1002,"root":9001,"parent":9001,"count":0,"rcount":0,"ctime":1760000500,"like":7,"action":0,
"member":''' +
      memberB +
      r''',"content":{"message":"回复 @旧名字 :同意[笑哭]","at_name_to_mid":{"新名字":1001},
"emote":{"[笑哭]":{"url":"https://i0.hdslb.com/bfs/emote/cry.png","meta":{"size":2}}},"members":[]},
"replies":null,"parent_reply_member":{"name":"旧名字"},"up_action":{"like":false,"reply":false},"reply_control":{"time_desc":"2天前发布"}}''';

  static final plain = reply(rpid: 9003, member: memberB, message: '普通评论');
  static final pinned = reply(rpid: 9100, member: memberA, message: '置顶评论', extra: ',"location":"IP属地：北京"');

  static String page(
          {required List<String> replies, List<String> top = const [], required String cursor, String? control}) =>
      '{"code":0,"message":"OK","ttl":1,"data":{"cursor":$cursor,"replies":[${replies.join(',')}],'
      '"top_replies":[${top.join(',')}]${control == null ? '' : ',"control":$control'}}}';

  /// The section's own write prompts, as the list and thread responses carry them; the texts are invented.
  static const control = '{"input_disable":false,"root_input_text":"随便聊聊吧～","child_input_text":" 说说你的看法 ",'
      '"giveup_input_text":"下次再聊吧","screenshot_icon_state":1,"upload_picture_icon_state":1}';

  static const cursorMore =
      '{"is_begin":true,"prev":0,"next":2,"is_end":false,"pagination_reply":{"next_offset":"CAEiAggC"},"mode":3,"all_count":1234}';
  static const cursorEnd = '{"is_begin":false,"prev":2,"next":0,"is_end":true,"mode":3,"all_count":42}';

  static final firstPage = page(replies: [rich, plain], top: [pinned], cursor: cursorMore);
  static final lastPage = page(replies: [plain], top: [pinned], cursor: cursorEnd);

  static final thread =
      '{"code":0,"message":"OK","ttl":1,"data":{"page":{"num":2,"size":20,"count":45,"acount":45},"root":$plain,'
      '"replies":[$rich,$subReply]}}';

  static const emotePanel = r'''
{"code":0,"message":"OK","ttl":1,"data":{"packages":[
{"id":1,"text":"小黄脸","url":"https://i0.hdslb.com/bfs/emote/pkg-1.png","type":3,"attr":0,"emote":[
{"id":10,"package_id":1,"text":"[doge]","url":"https://i0.hdslb.com/bfs/emote/doge.png","type":1,"meta":{"size":1}},
{"id":11,"package_id":1,"text":"[大笑]","url":"https://i0.hdslb.com/bfs/emote/lol.png","type":1,"meta":{"size":2}}]},
{"id":2,"text":"颜文字","url":"https://i0.hdslb.com/bfs/emote/pkg-2.png","type":4,"emote":[
{"id":20,"package_id":2,"text":"(⌒▽⌒)","url":"","type":4,"meta":{"size":1}},
{"id":21,"package_id":2,"text":"orz"}]},
{"id":3,"url":"https://i0.hdslb.com/bfs/emote/pkg-3.png","type":1,"emote":null}]}}''';
}

const navPath = '/x/web-interface/nav';
const signedPath = '/x/v2/reply/wbi/main';
const unsignedPath = '/x/v2/reply/main';
const threadPath = '/x/v2/reply/reply';
const addPath = '/x/v2/reply/add';
const spiPath = '/x/frontend/finger/spi';

void main() {
  late FakeHTTP http;
  late BiliClient client;

  setUp(() {
    http = FakeHTTP();
    http.routes[navPath] = (200, Fixtures.navLoggedIn);
    client = makeTestClient(http, cookies: {'bili_jct': 'T', 'SESSDATA': 's', 'buvid3': 'b3', 'buvid4': 'b4'});
  });

  test('comment page decodes members, pictures, pinned and cursor', () async {
    http.routes[signedPath] = (200, CommentFixtures.firstPage);
    final page = await client.comments(aid: 80433022, sort: CommentSort.hot);
    expect(page.total, 1234);
    expect(page.nextOffset, 'CAEiAggC');
    expect(page.isEnd, isFalse);
    expect(page.comments.map((comment) => comment.rpid), [9001, 9003]);

    final root = page.comments[0];
    expect(root.id, 9001);
    expect([root.oid, root.mid, root.root, root.parent, root.ctime, root.likes], [80433022, 1001, 0, 0, 1760000000, 321]);
    expect(root.replyCount, 10);
    expect(root.action, 1);
    expect(root.upLiked, isTrue);
    expect(root.isPinned, isFalse);
    expect(root.location, '广东');
    expect(
        root.member,
        const CommentMember(
            mid: 1001,
            name: '测试用户甲',
            face: 'https://i0.hdslb.com/bfs/face/face-a.jpg',
            level: 6,
            isVip: true,
            pendant: 'https://i0.hdslb.com/bfs/garb/item/pendant-a.png',
            fanCardImage: 'https://i0.hdslb.com/bfs/garb/item/card-a.png',
            fanCardNumber: '000095',
            fanCardColor: '#f35543'));
    expect(root.pictures,
        const [CommentPicture(url: 'https://i0.hdslb.com/bfs/new_dyn/pic-1.jpg', width: 1080, height: 1920.5)]);
    expect(root.runs, const [
      RichRun.text('看'),
      RichRun.emote(token: '[doge]', url: 'https://i0.hdslb.com/bfs/emote/doge.png', size: 1),
      RichRun.text('\n'),
      RichRun.mention(name: '测试用户乙', mid: 1002),
      RichRun.text(' 在'),
      RichRun.timestamp(label: '03:15', seconds: 195),
      RichRun.text(' '),
      RichRun.video(id: 'BV1GJ411x7h7'),
      RichRun.text(' '),
      RichRun.link(title: '链接标题', url: 'https://search.bilibili.com/all?keyword=x'),
    ]);

    final plain = page.comments[1];
    expect(plain.member.pendant, isNull);
    expect(plain.member.fanCardImage, isNull);
    expect(plain.member.fanCardNumber, isNull);
    expect(plain.member.fanCardColor, isNull);
    expect(plain.member.isVip, isFalse);
    expect(plain.member.level, 3);
    expect(plain.location, isNull);
    expect(plain.pictures, isEmpty);
    expect(plain.previewReplies, isEmpty);
    expect(plain.runs, const [RichRun.text('普通评论')]);

    final pinned = page.pinned!;
    expect(pinned.rpid, 9100);
    expect(pinned.isPinned, isTrue);
    expect(pinned.location, '北京');
  });

  test('a 笔记 link leads the text and a vote reads 投票 with its title', () {
    // Shaped after a note comment's content as the web API sends it; ids and text invented.
    const json = r'''
{"rpid":9200,"oid":80433022,"type":1,"mid":1001,"member":{"mid":"1001","uname":"测试用户甲"},
"content":{"message":"我的笔记 https://www.bilibili.com/h5/note-app/view?cvid=1234&pagefrom=comment 选一个{vote:4321}，再看蓝链",
"jump_url":{
"https://www.bilibili.com/h5/note-app/view?cvid=1234&pagefrom=comment":{"title":"笔记标题","state":0,"pc_url":"","prefix_icon":"",
"app_url_schema":"","click_report":"{\"cvid\":\"1234\",\"oid\":\"80433022\"}","extra":{"is_word_search":false}},
"蓝链":{"title":"链接标题","pc_url":"//search.bilibili.com/all?keyword=x","click_report":"","extra":{"is_word_search":true}}},
"vote":{"id":4321,"title":"选哪个","cnt":12,"desc":"","deleted":false},"members":[]}}''';
    final comment = Comment.fromJson(jsonDecode(json));
    expect(comment.runs, const [
      RichRun.link(
        title: '笔记标题',
        url: 'https://www.bilibili.com/h5/note-app/view?cvid=1234&pagefrom=comment',
        note: true,
      ),
      RichRun.text('我的笔记  选一个'),
      RichRun.link(title: '投票: 选哪个', url: 'https://t.bilibili.com/vote/h5/index?vote_id=4321#/result'),
      RichRun.text('，再看'),
      RichRun.link(title: '链接标题', url: 'https://search.bilibili.com/all?keyword=x'),
    ]);
  });

  test('a vote with no title reads 投票, and with no vote the token stays text', () {
    Comment decode(String content) => Comment.fromJson(jsonDecode(
        '{"rpid":1,"member":{"mid":"1","uname":"甲"},"content":{"message":"投{vote:7}"$content}}'));
    expect(decode(',"vote":{"id":7,"title":""}').runs, const [
      RichRun.text('投'),
      RichRun.link(title: '投票', url: 'https://t.bilibili.com/vote/h5/index?vote_id=7#/result'),
    ]);
    expect(decode('').runs, const [RichRun.text('投{vote:7}')]);
    expect(decode(',"vote":{"id":0}').runs, const [RichRun.text('投{vote:7}')]);
  });

  test('preview replies and a renamed reply target', () async {
    http.routes[signedPath] = (200, CommentFixtures.firstPage);
    final page = await client.comments(aid: 80433022, sort: CommentSort.hot);
    final preview = page.comments[0].previewReplies.first;
    expect(preview.rpid, 9002);
    expect(preview.root, 9001);
    expect(preview.parent, 9001);
    expect(preview.action, 0);
    expect(preview.member.mid, 1002);
    expect(preview.runs, const [
      RichRun.text('回复 '),
      RichRun.mention(name: '旧名字', mid: 1001),
      RichRun.text(' :同意'),
      RichRun.emote(token: '[笑哭]', url: 'https://i0.hdslb.com/bfs/emote/cry.png', size: 2),
    ]);
  });

  test('the comments request is signed and carries the cursor', () async {
    http.routes[signedPath] = (200, CommentFixtures.lastPage);
    await client.comments(aid: 80433022, sort: CommentSort.time);
    await client.comments(aid: 80433022, sort: CommentSort.hot, offset: 'CAEiAggC');
    final sent = http.requestsTo(signedPath);
    expect(sent.length, 2);
    final first = http.query(sent[0]);
    expect(first['oid'], '80433022');
    expect(first['type'], '1');
    expect(first['mode'], '2');
    expect(first['pagination_str'], '{"offset":""}');
    expect(first['seek_rpid'], isNull);
    expect(first['w_rid']?.length, 32);
    expect(first['wts'], isNotNull);
    final second = http.query(sent[1]);
    expect(second['mode'], '3');
    expect(second['pagination_str'], '{"offset":"CAEiAggC"}');
    expect(sent[0].headers['Referer'], BiliClient.referer);
  });

  test('the pinned comment is only kept on page one and the end has no offset', () async {
    http.routes[signedPath] = (200, CommentFixtures.lastPage);
    final one = await client.comments(aid: 1, sort: CommentSort.hot, offset: '');
    expect(one.pinned, isNotNull);
    expect(one.isEnd, isTrue);
    expect(one.nextOffset, isNull);
    expect(one.total, 42);
    final later = await client.comments(aid: 1, sort: CommentSort.hot, offset: 'CAEiAggC');
    expect(later.pinned, isNull);
    expect(later.comments.map((comment) => comment.rpid), [9003]);
  });

  test('the write prompts come from control, trimmed, and stay through a later page', () async {
    String page(String? control) =>
        CommentFixtures.page(replies: [CommentFixtures.plain], cursor: CommentFixtures.cursorMore, control: control);
    http.routes[signedPath] = (200, page(CommentFixtures.control));
    final first = await client.comments(aid: 1, sort: CommentSort.hot);
    expect(first.rootPrompt, '随便聊聊吧～');
    expect(first.childPrompt, '说说你的看法');
    // A later page drops the pinned comment through copyWith; the prompts stay.
    final later = await client.comments(aid: 1, sort: CommentSort.hot, offset: 'CAEiAggC');
    expect((later.rootPrompt, later.childPrompt), ('随便聊聊吧～', '说说你的看法'));

    for (final control in [null, '{}', '{"root_input_text":"","child_input_text":"  "}', '{"root_input_text":7}']) {
      http.routes[signedPath] = (200, page(control));
      final answer = await client.comments(aid: 1, sort: CommentSort.hot);
      expect((answer.rootPrompt, answer.childPrompt), (null, null), reason: '$control');
    }
  });

  test('a thread reads its own child prompt', () async {
    final root = CommentFixtures.plain;
    http.routes[threadPath] = (200,
        '{"code":0,"data":{"page":{"num":1,"size":20,"count":1},"root":$root,"replies":[$root],'
            '"control":${CommentFixtures.control}}}');
    final page = await client.thread(aid: 1, root: 9003, page: 1, sort: CommentSort.time);
    expect(page.childPrompt, '说说你的看法');
    expect(page.copyWith(total: 2).childPrompt, '说说你的看法');

    http.routes[threadPath] = (200, CommentFixtures.thread);
    expect((await client.thread(aid: 1, root: 9003, page: 1, sort: CommentSort.time)).childPrompt, isNull);
  });

  test('a missing next offset ends the list', () async {
    const cursor = '{"is_end":false,"all_count":3}';
    http.routes[signedPath] = (200, CommentFixtures.page(replies: [CommentFixtures.plain], cursor: cursor));
    final page = await client.comments(aid: 1, sort: CommentSort.hot);
    expect(page.isEnd, isTrue);
    expect(page.nextOffset, isNull);
  });

  test('one broken comment does not fail the page', () async {
    const broken = '{"rpid":0,"content":{"message":"没有编号"}}';
    http.routes[signedPath] =
        (200, CommentFixtures.page(replies: [broken, CommentFixtures.plain], cursor: CommentFixtures.cursorEnd));
    final page = await client.comments(aid: 1, sort: CommentSort.hot);
    expect(page.comments.map((comment) => comment.rpid), [9003]);
  });

  test('comments fall back to the unsigned route on risk control', () async {
    http.routes[signedPath] = (200, '{"code":-352,"message":"风控校验失败"}');
    http.routes[unsignedPath] = (200, CommentFixtures.firstPage);
    final page = await client.comments(aid: 80433022, sort: CommentSort.hot, offset: 'CAEiAggC');
    expect(page.comments.length, 2);
    expect(http.requestsTo(signedPath).length, 1);
    final retry = http.requestsTo(unsignedPath).first;
    expect(http.requestsTo(unsignedPath).length, 1);
    final query = http.query(retry);
    expect(query['w_rid'], isNull);
    expect(query['wts'], isNull);
    expect(query['oid'], '80433022');
    expect(query['mode'], '3');
    expect(query['pagination_str'], '{"offset":"CAEiAggC"}');
  });

  test('comments fall back on code -403 and HTTP 412, but only once', () async {
    http.routes[signedPath] = (200, '{"code":-403,"message":"访问权限不足"}');
    http.routes[unsignedPath] = (200, CommentFixtures.lastPage);
    await client.comments(aid: 1, sort: CommentSort.hot);
    expect(http.requestsTo(unsignedPath).length, 1);

    http.requests.clear();
    http.routes[signedPath] = (412, '');
    http.routes[spiPath] = (200, Fixtures.spi);
    await client.comments(aid: 1, sort: CommentSort.hot);
    expect(http.requestsTo(unsignedPath).length, 1);

    http.requests.clear();
    http.routes[signedPath] = (200, '{"code":-352,"message":"风控校验失败"}');
    http.routes[unsignedPath] = (200, '{"code":-352,"message":"风控校验失败"}');
    await expectLater(
        client.comments(aid: 1, sort: CommentSort.hot), throwsA(const BiliError.api(code: -352, message: '风控校验失败')));
    expect(http.requestsTo(unsignedPath).length, 1);
  });

  test('closed comments throw the server message', () async {
    for (final (code, message) in [(12002, '评论区已关闭'), (12061, 'UP主已关闭评论区')]) {
      http.requests.clear();
      http.routes[signedPath] = (200, '{"code":$code,"message":"$message"}');
      await expectLater(
          client.comments(aid: 1, sort: CommentSort.hot), throwsA(BiliError.api(code: code, message: message)));
      expect(http.requestsTo(unsignedPath), isEmpty);
    }
  });

  test('postComment reply fields', () async {
    final posted = '{"code":0,"message":"0","data":{"success_action":0,"reply":${CommentFixtures.plain}}}';
    http.routes['POST $addPath'] = (200, posted);

    final reply = await client.postComment(aid: 80433022, message: '回复 & 内容', root: 10, parent: 11);
    expect(reply.rpid, 9003);
    var request = http.requestsTo(addPath).last;
    expect(request.method, 'POST');
    expect(http.bodyText(request),
        'csrf=T&message=%E5%9B%9E%E5%A4%8D%20%26%20%E5%86%85%E5%AE%B9&oid=80433022&parent=11&root=10&type=1');
    expect(request.headers['Referer'], 'https://www.bilibili.com/video/av80433022');

    await client.postComment(aid: 80433022, message: '顶层');
    request = http.requestsTo(addPath).last;
    final body = http.bodyText(request);
    expect(body.contains('root='), isFalse);
    expect(body.contains('parent='), isFalse);
    expect(body.contains('sync_to_dynamic'), isFalse);

    await client.postComment(aid: 80433022, message: '顶层', syncToDynamic: true);
    request = http.requestsTo(addPath).last;
    expect(http.bodyText(request).contains('sync_to_dynamic=1'), isTrue);
  });

  test('postComment without login throws without sending', () async {
    final loggedOut = makeTestClient(http);
    await expectLater(loggedOut.postComment(aid: 1, message: 'x'),
        throwsA(isA<BiliError>().having((error) => error.needsLogin, 'needsLogin', isTrue)));
    expect(http.requestsTo(addPath), isEmpty);
  });

  test('thread query', () async {
    http.routes[threadPath] = (200, CommentFixtures.thread);
    final page = await client.thread(aid: 80433022, root: 9003, page: 2, sort: CommentSort.time);
    final query = http.query(http.requestsTo(threadPath).first);
    expect(query['oid'], '80433022');
    expect(query['type'], '1');
    expect(query['root'], '9003');
    expect(query['pn'], '2');
    expect(query['ps'], '20');
    expect(query['sort'], '0');
    expect(query['w_rid'], isNull);
    expect(page.root.rpid, 9003);
    expect(page.replies.map((comment) => comment.rpid), [9001, 9002]);
    expect(page.total, 45);
    expect(page.isEnd, isFalse);

    await client.thread(aid: 80433022, root: 9003, page: 1, sort: CommentSort.hot);
    expect(http.query(http.requestsTo(threadPath).last)['sort'], '1');
  });

  test('a thread ends on the last page or an empty one', () async {
    final root = CommentFixtures.plain;
    http.routes[threadPath] = (200, '{"code":0,"data":{"page":{"num":3,"size":20,"count":45},"root":$root,"replies":[]}}');
    final empty = await client.thread(aid: 1, root: 9003, page: 3, sort: CommentSort.time);
    expect(empty.isEnd, isTrue);
    http.routes[threadPath] =
        (200, '{"code":0,"data":{"page":{"num":3,"size":20,"count":45},"root":$root,"replies":[$root]}}');
    final last = await client.thread(aid: 1, root: 9003, page: 3, sort: CommentSort.time);
    expect(last.isEnd, isTrue);
    expect(last.replies.length, 1);
  });

  test('like, hate and delete forms', () async {
    const ok = '{"code":0,"message":"0","data":null}';
    http.routes['POST /x/v2/reply/action'] = (200, ok);
    http.routes['POST /x/v2/reply/hate'] = (200, ok);
    http.routes['POST /x/v2/reply/del'] = (200, ok);

    await client.likeComment(aid: 80433022, rpid: 9001, on: true);
    await client.likeComment(aid: 80433022, rpid: 9001, on: false);
    await client.hateComment(aid: 80433022, rpid: 9001, on: true);
    await client.hateComment(aid: 80433022, rpid: 9001, on: false);
    await client.deleteComment(aid: 80433022, rpid: 9001);

    expect(http.requestsTo('/x/v2/reply/action').map(http.bodyText),
        ['action=1&csrf=T&oid=80433022&rpid=9001&type=1', 'action=0&csrf=T&oid=80433022&rpid=9001&type=1']);
    expect(http.requestsTo('/x/v2/reply/hate').map(http.bodyText),
        ['action=1&csrf=T&oid=80433022&rpid=9001&type=1', 'action=0&csrf=T&oid=80433022&rpid=9001&type=1']);
    expect(http.requestsTo('/x/v2/reply/del').map(http.bodyText), ['csrf=T&oid=80433022&rpid=9001&type=1']);
  });

  test('emote packages flag text packages', () async {
    http.routes['/x/emote/user/panel/web'] = (200, CommentFixtures.emotePanel);
    final packages = await client.emotePackages();
    final request = http.requestsTo('/x/emote/user/panel/web').first;
    expect(http.query(request), {'business': 'reply'});
    expect(packages.map((package) => package.id), [1, 2, 3]);
    expect(packages.map((package) => package.isText), [false, true, false]);
    expect(packages[0].name, '小黄脸');
    expect(packages[0].icon, 'https://i0.hdslb.com/bfs/emote/pkg-1.png');
    expect(packages[0].emotes, const [
      Emote(token: '[doge]', url: 'https://i0.hdslb.com/bfs/emote/doge.png', large: false),
      Emote(token: '[大笑]', url: 'https://i0.hdslb.com/bfs/emote/lol.png', large: true),
    ]);
    expect(packages[1].emotes, const [Emote(token: '(⌒▽⌒)', url: '', large: false), Emote(token: 'orz', url: '', large: false)]);
    expect(packages[2].emotes, isEmpty);
    expect(packages[2].name, '');
  });
}
