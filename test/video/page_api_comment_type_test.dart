import 'dart:convert';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/video/page_api.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';

const _list = '/x/v2/reply/wbi/main';
const _thread = '/x/v2/reply/reply';
const _add = '/x/v2/reply/add';
const _like = '/x/v2/reply/action';
const _hate = '/x/v2/reply/hate';
const _delete = '/x/v2/reply/del';
const _ok = '{"code":0,"message":"0","ttl":1,"data":null}';

/// A made-up comment in the web answer's shape.
const _reply =
    '{"rpid":5001,"oid":1100000000000000701,"type":17,"mid":30001,'
    '"member":{"mid":"30001","uname":"测试评论者"},"content":{"message":"测试评论"}}';

void main() {
  late CannedHttp http;
  late ClientPageApi api;

  setUp(() {
    http = Canned.http()
      ..routes[_list] = (200, '{"code":0,"data":{"cursor":{"is_end":true,"all_count":1},"replies":[$_reply]}}')
      ..routes[_thread] = (200, '{"code":0,"data":{"page":{"num":1,"size":20,"count":1},"root":$_reply,"replies":[]}}')
      ..routes[_add] = (200, '{"code":0,"message":"0","data":{"success_action":0,"reply":$_reply}}')
      ..routes[_like] = (200, _ok)
      ..routes[_hate] = (200, _ok)
      ..routes[_delete] = (200, _ok);
    api = ClientPageApi(
      BiliClient(transport: http, cookies: CookieJar(Canned.cookies), logger: Logger(session: 'test')),
    );
  });

  Map<String, String> form(HTTPRequest request) => Uri.splitQueryString(utf8.decode(request.body!));

  /// Every comment call once on [oid], with [type] when it is given.
  Future<void> everyCall(int oid, {int? type}) async {
    if (type == null) {
      await api.comments(aid: oid, sort: CommentSort.hot);
      await api.thread(aid: oid, root: 5001, page: 1, sort: CommentSort.time);
      await api.postComment(aid: oid, message: '测试回复', root: 5001, parent: 5001);
      await api.likeComment(aid: oid, rpid: 5001, on: true);
      await api.hateComment(aid: oid, rpid: 5001, on: true);
      await api.deleteComment(aid: oid, rpid: 5001);
      return;
    }
    await api.comments(aid: oid, sort: CommentSort.hot, type: type);
    await api.thread(aid: oid, root: 5001, page: 1, sort: CommentSort.time, type: type);
    await api.postComment(aid: oid, message: '测试回复', root: 5001, parent: 5001, type: type);
    await api.likeComment(aid: oid, rpid: 5001, on: true, type: type);
    await api.hateComment(aid: oid, rpid: 5001, on: true, type: type);
    await api.deleteComment(aid: oid, rpid: 5001, type: type);
  }

  /// The (oid, type) each of the six calls put on the wire, in call order.
  List<(String?, String?)> sent() => [
    for (final path in [_list, _thread]) _pair(http.to(path).single.url.queryParameters),
    for (final path in [_add, _like, _hate, _delete]) _pair(form(http.to(path).single)),
  ];

  for (final type in [11, 12, 17]) {
    test('a post\'s area type $type reaches the wire on every comment call', () async {
      const oid = 1100000000000000701;
      await everyCall(oid, type: type);
      expect(sent(), List.filled(6, ('$oid', '$type')));
      expect(http.to(_add).single.headers['Referer'], 'https://t.bilibili.com/');
    });
  }

  test('a video\'s comments stay type 1, posted from the video\'s page', () async {
    await everyCall(80433022);
    expect(sent(), List.filled(6, ('80433022', '1')));
    expect(http.to(_add).single.headers['Referer'], 'https://www.bilibili.com/video/av80433022');
  });
}

(String?, String?) _pair(Map<String, String> fields) => (fields['oid'], fields['type']);
