import 'dart:convert';

import 'package:bili_core/api.dart';
import 'package:test/test.dart';

import 'composer_api_test.dart' show boundaryOf, multipartParts;
import 'fake_http.dart';

const createdPath = '/x/v3/fav/folder/created/list';
const addPath = '/x/v3/fav/folder/add';
const uploadPath = '/x/upload/web/image';

// Every id, title and address below is made up; the shapes are PiliPlus's (`models_new/fav/fav_folder`).
const createdAnswer = r'''
{"code":0,"message":"0","ttl":1,"data":{"count":3,"has_more":true,"list":[
{"id":1000101,"fid":10001,"mid":101,"attr":0,"title":"默认收藏夹","cover":"","media_count":0},
{"id":1000201,"fid":10002,"mid":101,"attr":3,"title":"私密的","cover":"http://i0.hdslb.com/bfs/archive/c1.jpg",
 "media_count":8},
{"id":1000301,"fid":10003,"mid":101,"attr":2,"title":"公开的","media_count":"--"},
{"title":"坏的"}
]}}''';

const uploadAnswer = r'''
{"code":0,"message":"0","ttl":1,"data":{"location":"https://i0.hdslb.com/bfs/medialist/cover/made-up.jpg","etag":"x"}}''';

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
    return requests.last;
  }

  group('createdFolders', () {
    test('asks a page of the account’s folders and reads count, privacy, the default and each cover', () async {
      http.routes[createdPath] = (200, createdAnswer);
      final page = await client.createdFolders(mid: 101);
      expect(sent(createdPath).method, 'GET');
      expect(http.query(sent(createdPath)), {'pn': '1', 'ps': '20', 'up_mid': '101'});
      expect([for (final folder in page.folders) folder.title], ['默认收藏夹', '私密的', '公开的']);
      expect([for (final folder in page.folders) folder.count], [0, 8, 0]);
      expect([for (final folder in page.folders) folder.isPrivate], [false, true, false]);
      expect(page.folders.first.isDefault, isTrue);
      expect(page.folders[1].isDefault, isFalse);
      expect(page.covers, {1000201: 'http://i0.hdslb.com/bfs/archive/c1.jpg'}, reason: 'none for an empty cover');
      expect(page.hasMore, isTrue);

      await client.createdFolders(mid: 101, page: 3, pageSize: 10);
      expect(http.query(sent(createdPath)), {'pn': '3', 'ps': '10', 'up_mid': '101'});
    });

    test('no data reads as no folders', () async {
      http.routes[createdPath] = (200, '{"code":0,"message":"0","ttl":1,"data":null}');
      final page = await client.createdFolders(mid: 101);
      expect(page.folders, isEmpty);
      expect(page.hasMore, isFalse);
    });

    test('a refusal throws its code', () async {
      http.routes[createdPath] = (200, '{"code":-101,"message":"账号未登录","ttl":1}');
      await expectLater(
        client.createdFolders(mid: 101),
        throwsA(isA<BiliAPIError>().having((error) => error.code, 'code', -101)),
      );
    });
  });

  group('uploadFolderCover', () {
    test('posts the picture as multipart to the medialist bucket with the csrf, and answers its location', () async {
      http.routes['POST $uploadPath'] = (200, uploadAnswer);
      final bytes = [0xFF, 0xD8, 0xFF, 0xE0, 0x0D, 0x0A, 0x2D, 0x2D, 0xFF, 0xD9];
      final location = await client.uploadFolderCover(bytes: bytes, filename: 'image_picker_1.jpg');
      expect(location, 'https://i0.hdslb.com/bfs/medialist/cover/made-up.jpg');
      final request = sent(uploadPath);
      expect(request.method, 'POST');
      expect(request.url.host, 'api.bilibili.com');
      expect(request.timeout, BiliClient.uploadTimeout);
      final parts = multipartParts(request.body!, boundaryOf(request));
      final fields = {
        for (final part in parts)
          if (!part.headers['content-disposition']!.contains('filename='))
            part.headers['content-disposition']!: utf8.decode(part.body),
      };
      expect(fields, {
        'form-data; name="bucket"': 'medialist',
        'form-data; name="dir"': 'cover',
        'form-data; name="csrf"': 'TOKEN',
      });
      final file = parts.singleWhere((part) => part.headers['content-disposition']!.contains('filename='));
      expect(file.headers['content-disposition'], 'form-data; name="file"; filename="image_picker_1.jpg"');
      expect(file.headers['content-type'], 'image/jpeg');
      expect(file.body, bytes);
    });

    test('an answer without a location is a decoding error; a refusal throws the server’s words', () async {
      http.routes['POST $uploadPath'] = (200, '{"code":0,"message":"0","data":{"etag":"x"}}');
      await expectLater(client.uploadFolderCover(bytes: [1], filename: 'a.png'), throwsA(isA<BiliDecodingError>()));
      http.routes['POST $uploadPath'] = (200, '{"code":0,"message":"0","data":{"location":""}}');
      await expectLater(client.uploadFolderCover(bytes: [1], filename: 'a.png'), throwsA(isA<BiliDecodingError>()));
      http.routes['POST $uploadPath'] = (200, '{"code":-400,"message":"文件过大"}');
      await expectLater(
        client.uploadFolderCover(bytes: [1], filename: 'a.png'),
        throwsA(const BiliError.api(code: -400, message: '文件过大')),
      );
    });
  });

  group('createFolder', () {
    test('sends the cover only when there is one', () async {
      http.routes[addPath] = (200, '{"code":0,"message":"0","data":{"id":1000401,"title":"新的","attr":2}}');
      await client.createFolder(
        title: '新的',
        isPrivate: false,
        cover: 'https://i0.hdslb.com/bfs/medialist/cover/made-up.jpg',
      );
      expect(formFields(http.bodyText(sent(addPath))), {
        'title': '新的',
        'privacy': '0',
        'cover': 'https://i0.hdslb.com/bfs/medialist/cover/made-up.jpg',
        'csrf': 'TOKEN',
      });
      await client.createFolder(title: '新的', isPrivate: false);
      expect(formFields(http.bodyText(sent(addPath))), {'title': '新的', 'privacy': '0', 'csrf': 'TOKEN'});
    });
  });
}
