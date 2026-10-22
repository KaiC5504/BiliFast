import 'package:bili_core/api.dart';
import 'package:test/test.dart';

import 'fake_http.dart';

const resourcesPath = '/x/v3/fav/resource/list';
const tabsPath = '/x/v3/fav/tab';
const tabFavPath = '/x/v3/fav/tab/fav';
const unfavAllPath = '/x/v3/fav/resource/unfav-all';
const okEmpty = '{"code":0,"message":"0","ttl":1,"data":null}';

// Every id, name and title below is made up; the shapes are PiliPlus's (`models_new/fav/`) and the official app's
// (`FavoritesTabList`, `FavoritesMediasItem`, `FavoritesTabs`).

const resourcesAnswer = r'''
{"code":0,"message":"0","ttl":1,"data":{
"info":{"id":1000201,"fid":10002,"mid":101,"attr":3,"title":"私密的","cover":"https://i0.hdslb.com/bfs/archive/c0.jpg",
 "upper":{"mid":101,"name":"测试用户","face":"https://i0.hdslb.com/bfs/face/f0.jpg"},"media_count":8},
"medias":[
 {"id":80433022,"type":2,"title":"第一个","cover":"https://i0.hdslb.com/bfs/archive/c1.jpg","duration":11,
  "upper":{"mid":201,"name":"UP甲"},"attr":0,"cnt_info":{"collect":3,"play":8040,"danmaku":0},"fav_time":1700000000,
  "bvid":"BV1GJ411x7h7"},
 {"id":170001,"type":2,"title":"失效的","cover":"","duration":53,"upper":{"mid":202,"name":"UP乙"},"attr":9,
  "cnt_info":{"play":21000,"danmaku":1},"bv_id":"BV17x411w7KC"},
 {"id":5000,"type":12,"title":"一首歌","upper":{"mid":203,"name":"UP丙"}},
 {"id":"broken","type":2}
],
"has_more":true}}''';

const tabsAnswer = r'''
{"code":0,"message":"0","ttl":1,"data":{"default_tab":1,"tabs":[
 {"tab_id":1,"tab_name":"收藏","uri":"","red_dot":false,"sub_tabs":[
  {"tab_id":11,"tab_name":"收藏夹","uri":""},{"tab_id":12,"tab_name":"视频","uri":""}]},
 {"tab_id":2,"tab_name":"追更","uri":"","red_dot":false}
]}}''';

const tabFavAnswer = r'''
{"code":0,"message":"0","ttl":1,"data":{"total":9,"has_more":true,"has_invalid":false,"list":[
 {"oid":80433022,"otype":2,"title":"第一个","cover":"https://i0.hdslb.com/bfs/archive/c1.jpg","link":"",
  "fav_time":1700000000,"page":1,"playback_position":100,"playback_desc":"00:11",
  "upper":{"mid":201,"name":"UP甲","jump_link":""},"ugc":{"first_cid":3001},"cnt_info":{"thumb_up":0},
  "card_type":1,"is_invalid":false,"left_text":"8040","left_icon_type":1,"right_text":"0","right_icon_type":2},
 {"oid":170001,"otype":2,"title":"第二个","playback_position":120,"playback_desc":"00:53","left_text":"2.1万",
  "right_text":"1","is_invalid":true},
 {"oid":7,"otype":12,"title":"一首歌"}
],"next_oid":170001,"next_otype":2,"next_score":1699999999}}''';

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

  group('bvidOf', () {
    test('gives the ids Bilibili gives', () {
      expect(bvidOf(80433022), 'BV1GJ411x7h7');
      expect(bvidOf(170001), 'BV17x411w7KC');
    });
  });

  test('a folder page sends the web query and keeps only the videos it can read', () async {
    http.routes[resourcesPath] = (200, resourcesAnswer);
    final page = await client.favFolderVideos(folderId: 1000201, page: 2);
    expect(http.query(sent(resourcesPath)), {
      'media_id': '1000201',
      'pn': '2',
      'ps': '20',
      'keyword': '',
      'order': 'mtime',
      'type': '0',
      'tid': '0',
      'platform': 'web',
    });
    expect(page.hasMore, isTrue);
    final info = page.info!;
    expect(info.title, '私密的');
    expect(info.count, 8);
    expect(info.ownerName, '测试用户');
    expect(info.isPrivate, isTrue);
    expect([for (final video in page.videos) video.aid], [80433022, 170001]);
    final first = page.videos.first;
    expect(first.bvid, 'BV1GJ411x7h7');
    expect(first.duration, 11);
    expect(first.ownerName, 'UP甲');
    expect(first.play, 8040);
    expect(first.danmaku, 0);
    expect(first.invalid, isFalse);
    expect(page.videos[1].bvid, 'BV17x411w7KC', reason: 'bv_id is the other spelling');
    expect(page.videos[1].invalid, isTrue);
  });

  test('a card’s covers ask for three', () async {
    http.routes[resourcesPath] = (200, resourcesAnswer);
    await client.favFolderVideos(folderId: 1000201, page: 1, pageSize: 3);
    expect(http.query(sent(resourcesPath))['ps'], '3');
  });

  test('an empty folder answers no medias, and no data reads as an empty page', () async {
    http.routes[resourcesPath] = (
      200,
      r'{"code":0,"data":{"info":{"id":1,"title":"空","media_count":0},"medias":null,"has_more":false}}',
    );
    final page = await client.favFolderVideos(folderId: 1, page: 1);
    expect(page.videos, isEmpty);
    expect(page.hasMore, isFalse);
    expect(page.info!.count, 0);
    http.routes[resourcesPath] = (200, okEmpty);
    final none = await client.favFolderVideos(folderId: 1, page: 1);
    expect(none.videos, isEmpty);
    expect(none.hasMore, isFalse);
  });

  test('a refused folder page throws its code', () async {
    http.routes[resourcesPath] = (200, '{"code":-101,"message":"账号未登录","ttl":1}');
    await expectLater(
      client.favFolderVideos(folderId: 1, page: 1),
      throwsA(isA<BiliAPIError>().having((error) => error.code, 'code', -101)),
    );
  });

  test('the 视频 tab is found among the sub tabs by its name', () async {
    http.routes[tabsPath] = (200, tabsAnswer);
    expect(await client.favVideosTab(), 12);
    expect(http.query(sent(tabsPath)), {'tab_id': '0'});
  });

  test('a top-level 视频 tab counts too, and none reads as null', () {
    expect(
      favVideosTabId({
        'tabs': [
          {'tab_id': 5, 'tab_name': '视频'},
        ],
      }),
      5,
    );
    expect(
      favVideosTabId({
        'tabs': [
          {'tab_id': 5, 'tab_name': '收藏夹'},
        ],
      }),
      isNull,
    );
    expect(favVideosTabId(<String, Object?>{}), isNull);
  });

  test('a 视频 tab is found at any depth, its id a number or a string', () {
    expect(
      favVideosTabId({
        'default_tab': 1,
        'tabs': {
          'items': [
            {
              'tab_id': '1',
              'tab_name': '收藏',
              'sub_tabs': [
                {'tab_id': '12', 'tab_name': ' 视频 '},
              ],
            },
          ],
        },
      }),
      12,
    );
    expect(
      favVideosTabId({
        'tabs': [
          {'id': 7, 'name': '视频'},
        ],
      }),
      7,
    );
  });

  test("an answer without 视频 is outlined for the log by its tabs' names and ids", () async {
    expect(
      favTabsOutline({
        'default_tab': 1,
        'tabs': [
          {
            'tab_id': 1,
            'tab_name': '收藏',
            'sub_tabs': [
              {'tab_id': 11, 'tab_name': '收藏夹'},
            ],
          },
          {'tab_id': 2, 'tab_name': '追更'},
        ],
      }),
      'keys default_tab,tabs; tabs 收藏=1[收藏夹=11], 追更=2',
    );
    expect(favTabsOutline(null), 'no data');
    http.routes[tabsPath] = (200, '{"code":0,"message":"0","ttl":1,"data":{"tabs":[]}}');
    expect(await client.favVideosTab(), isNull);
  });

    test('视频 starts from zero and pages by the answer’s cursor', () async {
    http.routes[tabFavPath] = (200, tabFavAnswer);
    final page = await client.favAllVideos(tabId: 12);
    expect(http.query(sent(tabFavPath)), {
      'start_oid': '0',
      'start_otype': '0',
      'tab_id': '12',
      'start_score': '0',
      'page_type': '1',
    });
    expect(page.hasMore, isTrue);
    expect(page.total, 9);
    expect(page.next, const FavTabCursor(oid: 170001, otype: 2, score: 1699999999));
    expect([for (final item in page.items) item.aid], [80433022, 170001], reason: 'the song is left out');
    final first = page.items.first;
    expect(first.bvid, 'BV1GJ411x7h7');
    expect(first.cid, 3001);
    expect(first.progress, 100);
    expect(first.progressText, '00:11');
    expect(first.plays, '8040');
    expect(first.danmaku, '0');
    expect(first.ownerName, 'UP甲');
    expect(page.items[1].progress, 100, reason: 'a position past 100 is clamped');
    expect(page.items[1].invalid, isTrue);

    http.requests.clear();
    await client.favAllVideos(tabId: 12, after: page.next);
    expect(http.query(sent(tabFavPath)), {
      'start_oid': '170001',
      'start_otype': '2',
      'tab_id': '12',
      'start_score': '1699999999',
      'page_type': '1',
    });
  });

  test('the last page of 视频 has no cursor', () async {
    http.routes[tabFavPath] = (200, r'{"code":0,"data":{"total":1,"has_more":false,"list":[],"next_oid":0}}');
    final page = await client.favAllVideos(tabId: 12);
    expect(page.hasMore, isFalse);
    expect(page.next, isNull);
  });

  test('取消收藏 everywhere posts the video with the csrf', () async {
    http.routes[unfavAllPath] = (200, okEmpty);
    await client.unfavouriteEverywhere(aid: 80433022);
    final request = sent(unfavAllPath);
    expect(request.method, 'POST');
    expect(formFields(http.bodyText(request)), {'rid': '80433022', 'type': '2', 'csrf': 'TOKEN'});
  });
}
