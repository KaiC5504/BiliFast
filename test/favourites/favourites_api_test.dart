import 'dart:convert';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/favourites/favourites_api.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';

const _batchDeal = '/x/v3/fav/resource/batch-deal';
const _created = '/x/v3/fav/folder/created/list';
const _add = '/x/v3/fav/folder/add';
const _upload = '/x/upload/web/image';
const _ok = '{"code":0,"message":"0","ttl":1}';

// Every id, title and address below is made up.
const _createdAnswer = r'''
{"code":0,"message":"0","ttl":1,"data":{"count":2,"has_more":false,"list":[
{"id":1000101,"fid":10001,"mid":12345,"attr":0,"title":"默认收藏夹","cover":"","media_count":0},
{"id":1000201,"fid":10002,"mid":12345,"attr":3,"title":"私密的","cover":"http://i0.hdslb.com/bfs/archive/c1.jpg",
 "media_count":8}
]}}''';

void main() {
  late CannedHttp http;
  late ClientFavouritesApi api;

  setUp(() {
    http = CannedHttp();
    api = ClientFavouritesApi(
      BiliClient(
        transport: http,
        cookies: CookieJar(Canned.cookies),
        logger: Logger(session: 'test'),
      ),
    );
  });

  Map<String, String> form(HTTPRequest request) => Uri.splitQueryString(utf8.decode(request.body!));

  test('取消收藏 in a folder posts batch-deal taking the video out of that folder only', () async {
    http.routes[_batchDeal] = (200, _ok);
    await api.removeFromFolder(folderId: 1000201, aid: 80433022);
    final request = http.to(_batchDeal).single;
    expect(request.method, 'POST');
    expect(request.url.host, 'api.bilibili.com');
    expect(form(request), {
      'rid': '80433022',
      'type': '2',
      'resources': '80433022:2',
      'add_media_ids': '',
      'del_media_ids': '1000201',
      'csrf': Canned.cookies['bili_jct'],
    });
  });

  test('the folders come from created/list, a page at a time, with their covers', () async {
    http.routes[_created] = (200, _createdAnswer);
    final page = await api.folders(mid: 12345, page: 2);
    expect(http.to(_created).single.url.queryParameters, {'pn': '2', 'ps': '20', 'up_mid': '12345'});
    expect([for (final folder in page.folders) folder.title], ['默认收藏夹', '私密的']);
    expect(page.covers, {1000201: 'http://i0.hdslb.com/bfs/archive/c1.jpg'});
    expect(page.hasMore, isFalse);
  });

  test('创建 sends the 简介 and the cover only when there are some', () async {
    http.routes[_add] = (200, '{"code":0,"message":"0","data":{"id":1000301,"title":"新的","attr":2,"media_count":0}}');
    final folder = await api.createFolder(
      title: '新的',
      intro: '简介',
      isPrivate: false,
      cover: 'https://i0.hdslb.com/bfs/medialist/cover/x.jpg',
    );
    expect(folder.id, 1000301);
    expect(form(http.to(_add).single), {
      'title': '新的',
      'intro': '简介',
      'privacy': '0',
      'cover': 'https://i0.hdslb.com/bfs/medialist/cover/x.jpg',
      'csrf': Canned.cookies['bili_jct'],
    });
    await api.createFolder(title: '新的', intro: '', isPrivate: true);
    expect(form(http.to(_add).last), {'title': '新的', 'privacy': '1', 'csrf': Canned.cookies['bili_jct']});
  });

  test('a cover uploads to the medialist bucket and answers its address', () async {
    http.routes[_upload] = (
      200,
      '{"code":0,"message":"0","data":{"location":"https://i0.hdslb.com/bfs/medialist/cover/y.jpg"}}',
    );
    final address = await api.uploadCover(bytes: [0xFF, 0xD8, 0xFF], filename: 'image_picker_1.jpg');
    expect(address, 'https://i0.hdslb.com/bfs/medialist/cover/y.jpg');
    final request = http.to(_upload).single;
    expect(request.method, 'POST');
    expect(request.headers['Content-Type'], startsWith('multipart/form-data; boundary='));
    final body = latin1.decode(request.body!);
    expect(body, contains('name="bucket"\r\n\r\nmedialist\r\n'));
    expect(body, contains('name="dir"\r\n\r\ncover\r\n'));
    expect(body, contains('name="file"; filename="image_picker_1.jpg"'));
  });
}
