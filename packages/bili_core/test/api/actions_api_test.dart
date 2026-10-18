import 'package:bili_core/api.dart';
import 'package:test/test.dart';

import 'fake_http.dart';

const bvid = 'BV1GJ411x7h7';
const aid = 80433022;
const videoReferer = 'https://www.bilibili.com/video/BV1GJ411x7h7';
const okEmpty = '{"code":0,"message":"0","ttl":1,"data":null}';

void main() {
  late FakeHTTP http;
  late BiliClient client;

  setUp(() {
    http = FakeHTTP();
    client = makeTestClient(http, cookies: {'bili_jct': 'TOKEN', 'SESSDATA': 's', 'buvid3': 'b3', 'buvid4': 'b4'});
  });

  HTTPRequest sent(String path) {
    final requests = http.requestsTo(path);
    expect(requests, isNotEmpty, reason: 'no request to $path');
    return requests.first;
  }

  test('relation sends aid and bvid and decodes', () async {
    const path = '/x/web-interface/archive/relation';
    http.routes[path] = (
      200,
      '{"code":0,"message":"0","ttl":1,"data":{"attention":true,"favorite":false,"season_fav":false,"like":true,"dislike":false,"coin":2}}'
    );
    final relation = await client.relation(aid: aid, bvid: bvid);
    expect(relation, const VideoRelation(like: true, dislike: false, favorite: false, attention: true, coins: 2));
    final request = sent(path);
    expect(request.method, 'GET');
    expect(http.query(request), {'aid': '80433022', 'bvid': bvid});
  });

  test('relation reads season_fav', () async {
    http.routes['/x/web-interface/archive/relation'] = (200, '{"code":0,"data":{"season_fav":true}}');
    final relation = await client.relation(aid: aid, bvid: bvid);
    expect(relation.seasonFav, isTrue);
  });

  test('relation defaults missing fields and accepts numeric flags', () async {
    http.routes['/x/web-interface/archive/relation'] = (200, '{"code":0,"data":{"like":1,"coin":1}}');
    final relation = await client.relation(aid: aid, bvid: bvid);
    expect(relation, const VideoRelation(like: true, dislike: false, favorite: false, attention: false, coins: 1));
  });

  test('uploader card decodes the nested card and a string mid', () async {
    const path = '/x/web-interface/card';
    http.routes[path] = (
      200,
      r'''
{"code":0,"message":"0","ttl":1,"data":{"card":{"mid":"4242","name":"UP主","face":"https://i0.hdslb.com/bfs/face/face-0001.jpg","fans":1,"attention":9,"vip":{"type":2,"status":1,"label":{"text":"年度大会员"}}},"following":true,"archive_count":321,"article_count":0,"follower":123456,"like_num":99}}'''
    );
    final card = await client.uploaderCard(mid: 4242);
    expect(
        card,
        const UploaderCard(
            mid: 4242,
            name: 'UP主',
            face: 'https://i0.hdslb.com/bfs/face/face-0001.jpg',
            fans: 123456,
            videos: 321,
            isVip: true,
            following: true));
    final request = sent(path);
    expect(request.method, 'GET');
    expect(http.query(request), {'mid': '4242', 'photo': 'false'});
  });

  test('uploader card reads the verification kind', () async {
    for (final (type, kind) in [('0', OfficialKind.person), ('1', OfficialKind.organisation), ('-1', OfficialKind.none)]) {
      http.routes['/x/web-interface/card'] = (
        200,
        '{"code":0,"data":{"card":{"mid":7,"name":"n","face":"f","Official":{"role":0,"title":"","desc":"","type":$type}}}}'
      );
      expect((await client.uploaderCard(mid: 7)).official, kind);
    }
  });

  test('uploader card without vip or following reads as false', () async {
    http.routes['/x/web-interface/card'] = (
      200,
      '{"code":0,"data":{"card":{"mid":7,"name":"普通UP","face":"f","vip":{"type":0,"status":0}},"archive_count":0,"follower":0}}'
    );
    final card = await client.uploaderCard(mid: 7);
    expect(card.mid, 7);
    expect(card.isVip, isFalse);
    expect(card.following, isFalse);
    expect(card.videos, 0);
  });

  test('uploader card without a card object fails', () async {
    http.routes['/x/web-interface/card'] = (200, '{"code":0,"data":{"following":false}}');
    await expectLater(client.uploaderCard(mid: 7), throwsA(isA<BiliDecodingError>()));
  });

  test('like sends like=1', () async {
    const path = '/x/web-interface/archive/like';
    http.routes[path] = (200, '{"code":0,"message":"0","ttl":1,"data":{"toast":"点赞成功"}}');
    await client.like(aid: aid, bvid: bvid, on: true);
    final request = sent(path);
    expect(request.method, 'POST');
    expect(http.bodyText(request), 'aid=80433022&csrf=TOKEN&like=1');
    expect(request.headers['Referer'], videoReferer);
  });

  test('unlike sends like=2', () async {
    const path = '/x/web-interface/archive/like';
    http.routes[path] = (200, okEmpty);
    await client.like(aid: aid, bvid: bvid, on: false);
    expect(http.bodyText(sent(path)), 'aid=80433022&csrf=TOKEN&like=2');
  });

  test('triple sends the web form and decodes', () async {
    const path = '/x/web-interface/archive/like/triple';
    http.routes[path] =
        (200, '{"code":0,"message":"0","ttl":1,"data":{"like":true,"coin":true,"fav":true,"multiply":2,"prompt":false}}');
    final result = await client.triple(aid: aid, bvid: bvid);
    expect(result, const TripleResult(like: true, coin: true, favorite: true, multiply: 2));
    final request = sent(path);
    expect(request.method, 'POST');
    expect(
        http.bodyText(request),
        'aid=80433022&csrf=TOKEN&eab_x=2&ga=1&ramval=0&source=web_normal&spmid=333.788.0.0'
        '&statistics=%7B%22appId%22%3A100%2C%22platform%22%3A5%7D');
    expect(request.headers['Referer'], videoReferer);
  });

  test('a partly done triple keeps each flag', () async {
    http.routes['/x/web-interface/archive/like/triple'] =
        (200, '{"code":0,"data":{"like":true,"coin":false,"fav":true,"multiply":0}}');
    final result = await client.triple(aid: aid, bvid: bvid);
    expect(result, const TripleResult(like: true, coin: false, favorite: true, multiply: 0));
  });

  test('coin sends multiply and select_like', () async {
    const path = '/x/web-interface/coin/add';
    http.routes[path] = (200, '{"code":0,"message":"0","ttl":1,"data":{"like":true}}');
    await client.coin(aid: aid, bvid: bvid, multiply: 2, alsoLike: true);
    final request = sent(path);
    expect(request.method, 'POST');
    expect(http.bodyText(request), 'aid=80433022&csrf=TOKEN&multiply=2&select_like=1');
    expect(request.headers['Referer'], videoReferer);
  });

  test('coin without like sends select_like=0', () async {
    const path = '/x/web-interface/coin/add';
    http.routes[path] = (200, okEmpty);
    await client.coin(aid: aid, bvid: bvid, multiply: 1, alsoLike: false);
    expect(http.bodyText(sent(path)), 'aid=80433022&csrf=TOKEN&multiply=1&select_like=0');
  });

  test('coin error keeps the server message', () async {
    http.routes['/x/web-interface/coin/add'] = (200, '{"code":34005,"message":"超过投币上限啦~","ttl":1}');
    await expectLater(client.coin(aid: aid, bvid: bvid, multiply: 2, alsoLike: false),
        throwsA(const BiliError.api(code: 34005, message: '超过投币上限啦~')));
  });

  test('coin balance reads money from the account host', () async {
    const path = '/site/getCoin';
    http.routes[path] = (200, '{"code":0,"status":true,"data":{"money":123.5}}');
    final balance = await client.coinBalance();
    expect(balance, 123.5);
    final request = sent(path);
    expect(request.method, 'GET');
    expect(request.url.host, 'account.bilibili.com');
    expect(request.headers['Cookie']?.contains('SESSDATA=s'), isTrue);
  });

  test('coin balance accepts a whole number and a missing money', () async {
    http.routes['/site/getCoin'] = (200, '{"code":0,"data":{"money":6}}');
    expect(await client.coinBalance(), 6);
    http.routes['/site/getCoin'] = (200, '{"code":0,"data":{"money":null}}');
    expect(await client.coinBalance(), 0);
  });

  test('favourite folders send the query and decode', () async {
    const path = '/x/v3/fav/folder/created/list-all';
    http.routes[path] = (
      200,
      r'''
{"code":0,"message":"0","ttl":1,"data":{"count":2,"list":[
{"id":1001,"fid":10,"mid":4242,"attr":2,"title":"默认收藏夹","fav_state":1,"media_count":12},
{"id":1002,"fid":11,"mid":4242,"attr":3,"title":"私密夹","fav_state":0,"media_count":0}],"season":null}}'''
    );
    final folders = await client.favouriteFolders(mid: 4242, aid: aid);
    expect(folders, const [
      FavFolder(id: 1001, title: '默认收藏夹', count: 12, isPrivate: false, contains: true, isDefault: false),
      FavFolder(id: 1002, title: '私密夹', count: 0, isPrivate: true, contains: false, isDefault: false),
    ]);
    final request = sent(path);
    expect(request.method, 'GET');
    expect(http.query(request), {'up_mid': '4242', 'rid': '80433022', 'type': '2'});
  });

  test('favourite folder flags', () async {
    http.routes['/x/v3/fav/folder/created/list-all'] = (
      200,
      r'''
{"code":0,"data":{"count":4,"list":[
{"id":1,"attr":0,"title":"a","fav_state":0,"media_count":1},
{"id":2,"attr":1,"title":"b","fav_state":1,"media_count":2},
{"id":3,"attr":2,"title":"c","fav_state":0,"media_count":3},
{"id":4,"attr":3,"title":"d","fav_state":1,"media_count":4}]}}'''
    );
    final folders = await client.favouriteFolders(mid: 4242, aid: aid);
    expect(folders.map((folder) => folder.isPrivate), [false, true, false, true]);
    expect(folders.map((folder) => folder.isDefault), [true, true, false, false]);
    expect(folders.map((folder) => folder.contains), [false, true, false, true]);
    expect(folders.map((folder) => folder.count), [1, 2, 3, 4]);
  });

  test('favourite folders tolerate no list and a broken folder', () async {
    http.routes['/x/v3/fav/folder/created/list-all'] = (200, '{"code":0,"data":{"count":0,"list":null}}');
    expect(await client.favouriteFolders(mid: 1, aid: aid), isEmpty);
    http.routes['/x/v3/fav/folder/created/list-all'] =
        (200, '{"code":0,"data":{"list":[{"title":"没有编号"},{"id":5,"title":"好的"}]}}');
    final folders = await client.favouriteFolders(mid: 1, aid: aid);
    expect(folders.map((folder) => folder.id), [5]);
    expect(folders.first.contains, isFalse);
  });

  test('updateFavourites sends both id lists and the video', () async {
    const path = '/x/v3/fav/resource/batch-deal';
    http.routes[path] = (200, '{"code":0,"message":"0","ttl":1,"data":{"prompt":false}}');
    await client.updateFavourites(aid: aid, add: [1001, 1003], remove: [1002]);
    final request = sent(path);
    expect(request.method, 'POST');
    expect(http.bodyText(request),
        'add_media_ids=1001%2C1003&csrf=TOKEN&del_media_ids=1002&resources=80433022%3A2&rid=80433022&type=2');
  });

  test('updateFavourites with an empty side sends an empty field', () async {
    const path = '/x/v3/fav/resource/batch-deal';
    http.routes[path] = (200, okEmpty);
    await client.updateFavourites(aid: aid, add: [], remove: [7]);
    expect(http.bodyText(sent(path)),
        'add_media_ids=&csrf=TOKEN&del_media_ids=7&resources=80433022%3A2&rid=80433022&type=2');
  });

  test('createFolder sends privacy and returns the new folder', () async {
    const path = '/x/v3/fav/folder/add';
    http.routes[path] = (
      200,
      '{"code":0,"message":"0","ttl":1,"data":{"id":2001,"fid":20,"mid":4242,"attr":1,"title":"新夹 & 子","media_count":0,"fav_state":0}}'
    );
    final folder = await client.createFolder(title: '新夹 & 子', isPrivate: true);
    expect(folder,
        const FavFolder(id: 2001, title: '新夹 & 子', count: 0, isPrivate: true, contains: false, isDefault: true));
    final request = sent(path);
    expect(request.method, 'POST');
    expect(http.bodyText(request), 'csrf=TOKEN&privacy=1&title=%E6%96%B0%E5%A4%B9%20%26%20%E5%AD%90');
  });

  test('creating a public folder sends privacy=0', () async {
    const path = '/x/v3/fav/folder/add';
    http.routes[path] = (200, '{"code":0,"data":{"id":2002,"attr":0,"title":"x"}}');
    await client.createFolder(title: 'x', isPrivate: false);
    expect(http.bodyText(sent(path)), 'csrf=TOKEN&privacy=0&title=x');
  });

  test('countShare sends the aid', () async {
    const path = '/x/web-interface/share/add';
    http.routes[path] = (200, '{"code":0,"message":"0","ttl":1,"data":678}');
    await client.countShare(aid: aid);
    final request = sent(path);
    expect(request.method, 'POST');
    expect(http.bodyText(request), 'aid=80433022&csrf=TOKEN');
  });

  test('follow sends act=1 with the space referer', () async {
    const path = '/x/relation/modify';
    http.routes[path] = (200, okEmpty);
    await client.follow(mid: 4242, on: true);
    final request = sent(path);
    expect(request.method, 'POST');
    expect(http.bodyText(request), 'act=1&csrf=TOKEN&fid=4242&re_src=14');
    expect(request.headers['Referer'], 'https://space.bilibili.com/4242');
  });

  test('season fav and unfav post the season id', () async {
    http.routes['/x/v3/fav/season/fav'] = (200, okEmpty);
    http.routes['/x/v3/fav/season/unfav'] = (200, okEmpty);
    await client.favSeason(seasonId: 1234, on: true);
    await client.favSeason(seasonId: 1234, on: false);
    expect(http.bodyText(sent('/x/v3/fav/season/fav')), 'csrf=TOKEN&platform=web&season_id=1234');
    expect(http.bodyText(sent('/x/v3/fav/season/unfav')), 'csrf=TOKEN&platform=web&season_id=1234');
  });

  test('season fav refusal throws the server message', () async {
    http.routes['/x/v3/fav/season/fav'] = (200, '{"code":11010,"message":"内容不存在"}');
    await expectLater(
      client.favSeason(seasonId: 1, on: true),
      throwsA(isA<BiliError>()),
    );
  });

  test('unfollow sends act=2', () async {
    const path = '/x/relation/modify';
    http.routes[path] = (200, okEmpty);
    await client.follow(mid: 4242, on: false);
    expect(http.bodyText(sent(path)), 'act=2&csrf=TOKEN&fid=4242&re_src=14');
  });

  test('tags decode kinds and send bvid and cid', () async {
    const path = '/x/web-interface/view/detail/tag';
    http.routes[path] = (
      200,
      r'''
{"code":0,"message":"0","ttl":1,"data":[
{"tag_id":111,"tag_name":"测试标签","music_id":"","tag_type":"old_channel","jump_url":""},
{"tag_id":222,"tag_name":"测试话题","music_id":"","tag_type":"topic","jump_url":""},
{"tag_id":333,"tag_name":"发现《测试曲》","music_id":"MA1","tag_type":"bgm","jump_url":""},
{"tag_id":444,"tag_name":"没有类型"}]}'''
    );
    final tags = await client.tags(bvid: bvid, cid: 137649199);
    expect(tags, const [
      VideoTag(id: 111, name: '测试标签', kind: VideoTagKind.normal),
      VideoTag(id: 222, name: '测试话题', kind: VideoTagKind.topic),
      VideoTag(id: 333, name: '发现《测试曲》', kind: VideoTagKind.bgm),
      VideoTag(id: 444, name: '没有类型', kind: VideoTagKind.normal),
    ]);
    final request = sent(path);
    expect(request.method, 'GET');
    expect(http.query(request), {'bvid': bvid, 'cid': '137649199'});
  });

  test('tags with null data are empty', () async {
    http.routes['/x/web-interface/view/detail/tag'] = (200, okEmpty);
    expect(await client.tags(bvid: bvid, cid: 1), isEmpty);
  });

  test('writes without a csrf cookie ask for login without sending', () async {
    final anonymous = makeTestClient(http, cookies: {'buvid3': 'b3', 'buvid4': 'b4'});
    await expectLater(anonymous.like(aid: aid, bvid: bvid, on: true),
        throwsA(isA<BiliError>().having((error) => error.needsLogin, 'needsLogin', isTrue)));
    expect(http.requests, isEmpty);
  });
}
