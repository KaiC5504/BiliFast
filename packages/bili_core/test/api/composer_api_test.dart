import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:test/test.dart';

import 'fake_http.dart';
import 'fixtures.dart';

/// Shaped after bilibili-API-collect's followings, followings search and upload_bfs answers; every name and id here
/// is invented.
abstract final class ComposerFixtures {
  static const followings = r'''
{"code":0,"message":"0","ttl":1,"data":{"list":[
{"mid":2001,"attribute":2,"mtime":1760000000,"tag":null,"special":0,"uname":"关注甲","face":"https://i0.hdslb.com/bfs/face/a.jpg","sign":"签名"},
{"mid":"2002","attribute":2,"uname":"关注乙","face":"http://i1.hdslb.com/bfs/face/b.jpg"},
{"mid":2003,"attribute":2,"uname":""},
{"attribute":2,"uname":"没有编号"},
{"mid":2004,"uname":"没有头像"}],"re_version":0,"total":5}}''';

  static const searched = r'''
{"code":0,"message":"0","ttl":1,"data":{"list":[{"mid":2001,"uname":"关注甲","face":"https://i0.hdslb.com/bfs/face/a.jpg"}],"total":1}}''';

  static const uploaded = r'''
{"code":0,"message":"0","ttl":1,"data":{"image_url":"http://i0.hdslb.com/bfs/new_dyn/pic-1.jpg","image_width":1080,"image_height":1920,"img_size":245.67}}''';
}

const followingsPath = '/x/relation/followings';
const searchPath = '/x/relation/followings/search';
const uploadPath = '/x/dynamic/feed/draw/upload_bfs';
const addPath = '/x/v2/reply/add';
const navPath = '/x/web-interface/nav';

/// One part of a multipart body: its headers and its bytes.
typedef Part = ({Map<String, String> headers, List<int> body});

/// Splits a multipart/form-data body on [boundary], byte for byte so a file's bytes come back exactly.
List<Part> multipartParts(Uint8List body, String boundary) {
  final delimiter = ascii.encode('--$boundary');
  final starts = <int>[];
  for (var at = 0; at <= body.length - delimiter.length; at++) {
    var match = true;
    for (var k = 0; k < delimiter.length; k++) {
      if (body[at + k] != delimiter[k]) {
        match = false;
        break;
      }
    }
    if (match) starts.add(at);
  }
  final parts = <Part>[];
  for (var index = 0; index < starts.length - 1; index++) {
    // Each part runs from after "--boundary\r\n" to before the "\r\n" that leads into the next delimiter.
    final chunk = body.sublist(starts[index] + delimiter.length + 2, starts[index + 1] - 2);
    var split = -1;
    for (var at = 0; at < chunk.length - 3; at++) {
      if (chunk[at] == 13 && chunk[at + 1] == 10 && chunk[at + 2] == 13 && chunk[at + 3] == 10) {
        split = at;
        break;
      }
    }
    final headers = <String, String>{};
    for (final line in utf8.decode(chunk.sublist(0, split)).split('\r\n')) {
      final colon = line.indexOf(':');
      headers[line.substring(0, colon).toLowerCase()] = line.substring(colon + 1).trim();
    }
    parts.add((headers: headers, body: chunk.sublist(split + 4)));
  }
  final tail = utf8.decode(body.sublist(starts.last));
  if (tail != '--$boundary--\r\n') throw StateError('multipart body does not end with the closing delimiter: $tail');
  return parts;
}

String boundaryOf(HTTPRequest request) {
  final type = request.headers['Content-Type'] ?? '';
  expect(type, startsWith('multipart/form-data; boundary='));
  return type.substring('multipart/form-data; boundary='.length);
}

void main() {
  late FakeHTTP http;
  late BiliClient client;
  late MemorySink sink;

  setUp(() {
    http = FakeHTTP();
    http.routes[navPath] = (200, Fixtures.navLoggedIn);
    sink = MemorySink();
    client = BiliClient(
      transport: http,
      cookies: CookieJar({'bili_jct': 'CSRF-SECRET', 'SESSDATA': 'SESSION-SECRET', 'buvid3': 'b3', 'buvid4': 'b4'}),
      now: () => testNow,
      logger: Logger(session: 'test')..add(sink),
    );
  });

  test('an empty query lists one page of the most recently followed, unsigned', () async {
    http.routes[followingsPath] = (200, ComposerFixtures.followings);
    final found = await client.followings(mid: 1001);
    final query = http.query(http.requestsTo(followingsPath).single);
    expect(query, {'vmid': '1001', 'pn': '1', 'ps': '50', 'order': 'desc', 'order_type': ''});
    expect(http.requestsTo(searchPath), isEmpty);
    expect(found, const [
      MentionCandidate(mid: 2001, name: '关注甲', face: 'https://i0.hdslb.com/bfs/face/a.jpg'),
      MentionCandidate(mid: 2002, name: '关注乙', face: 'http://i1.hdslb.com/bfs/face/b.jpg'),
      MentionCandidate(mid: 2004, name: '没有头像'),
    ]);
  });

  test('a blank query is an empty one', () async {
    http.routes[followingsPath] = (200, ComposerFixtures.followings);
    await client.followings(mid: 1001, query: '  ');
    expect(http.requestsTo(followingsPath).length, 1);
    expect(http.requestsTo(searchPath), isEmpty);
  });

  test('a query searches the followings, signed, with the website\'s fields', () async {
    http.routes[searchPath] = (200, ComposerFixtures.searched);
    final found = await client.followings(mid: 1001, query: ' 关注 甲 ');
    final request = http.requestsTo(searchPath).single;
    final query = http.query(request);
    expect(query['vmid'], '1001');
    expect(query['name'], '关注 甲');
    expect(query['pn'], '1');
    expect(query['ps'], '20');
    expect(query['order'], 'desc');
    expect(query['order_type'], 'attention');
    expect(query['gaia_source'], 'main_web');
    expect(query['web_location'], '333.999');
    expect(query['w_rid']?.length, 32);
    expect(query['wts'], isNotNull);
    expect(http.requestsTo(followingsPath), isEmpty);
    expect(found, const [MentionCandidate(mid: 2001, name: '关注甲', face: 'https://i0.hdslb.com/bfs/face/a.jpg')]);
  });

  test('no matches is an empty list, with or without the list or the data', () async {
    for (final answer in [
      '{"code":0,"data":{"list":[],"total":0}}',
      '{"code":0,"data":{"list":null,"total":0}}',
      '{"code":0,"data":{"total":0}}',
      '{"code":0,"data":null}',
    ]) {
      http.routes[searchPath] = (200, answer);
      expect(await client.followings(mid: 1001, query: '无人'), isEmpty, reason: answer);
    }
  });

  test('a refused list throws the server message', () async {
    http.routes[followingsPath] = (200, '{"code":22115,"message":"用户已设置隐私，无法查看"}');
    await expectLater(client.followings(mid: 1001), throwsA(const BiliError.api(code: 22115, message: '用户已设置隐私，无法查看')));
  });

  test('followings without a viewer throws needsLogin without sending', () async {
    await expectLater(
      client.followings(mid: 0, query: '甲'),
      throwsA(isA<BiliError>().having((error) => error.needsLogin, 'needsLogin', isTrue)),
    );
    expect(http.requests, isEmpty);
  });

  test('a picture uploads as multipart with biz, category, csrf and the file\'s exact bytes', () async {
    http.routes['POST $uploadPath'] = (200, ComposerFixtures.uploaded);
    final bytes = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x0D, 0x0A, 0x2D, 0x2D, 0x80, 0xFE, 0xFF, 0xD9];
    final picture = await client.uploadCommentPicture(bytes: bytes, filename: 'image_picker_1.jpg');
    expect(
      picture,
      const UploadedPicture(
        url: 'http://i0.hdslb.com/bfs/new_dyn/pic-1.jpg',
        width: 1080,
        height: 1920,
        sizeKb: 245.67,
      ),
    );

    final request = http.requestsTo(uploadPath).single;
    expect(request.method, 'POST');
    expect(request.headers['Origin'], 'https://www.bilibili.com');
    expect(request.headers['Referer'], BiliClient.referer);
    expect(request.headers['Cookie'], contains('SESSDATA=SESSION-SECRET'));
    final parts = multipartParts(request.body!, boundaryOf(request));
    final fields = {
      for (final part in parts)
        if (!part.headers['content-disposition']!.contains('filename='))
          part.headers['content-disposition']!: utf8.decode(part.body),
    };
    expect(fields, {
      'form-data; name="biz"': 'new_dyn',
      'form-data; name="category"': 'daily',
      'form-data; name="csrf"': 'CSRF-SECRET',
    });
    final file = parts.singleWhere((part) => part.headers['content-disposition']!.contains('filename='));
    expect(file.headers['content-disposition'], 'form-data; name="file_up"; filename="image_picker_1.jpg"');
    expect(file.headers['content-type'], 'image/jpeg');
    expect(file.body, bytes);
  });

  test('each upload gets its own boundary', () async {
    http.routes['POST $uploadPath'] = (200, ComposerFixtures.uploaded);
    await client.uploadCommentPicture(bytes: [1], filename: 'a.jpg');
    await client.uploadCommentPicture(bytes: [1], filename: 'a.jpg');
    final sent = http.requestsTo(uploadPath);
    expect(boundaryOf(sent[0]), isNot(boundaryOf(sent[1])));
  });

  test('the file\'s type follows its extension, and a quote cannot break out of the file name', () async {
    http.routes['POST $uploadPath'] = (200, ComposerFixtures.uploaded);
    final cases = {
      'shot.PNG': 'image/png',
      'moving.gif': 'image/gif',
      'still.jpeg': 'image/jpeg',
      'web.webp': 'image/webp',
      'phone.heic': 'image/heic',
      'no-extension': 'application/octet-stream',
    };
    for (final MapEntry(key: filename, value: type) in cases.entries) {
      await client.uploadCommentPicture(bytes: [1, 2], filename: filename);
      final request = http.requestsTo(uploadPath).last;
      final file = multipartParts(request.body!, boundaryOf(request)).last;
      expect(file.headers['content-type'], type, reason: filename);
    }

    await client.uploadCommentPicture(bytes: [1], filename: 'a"\r\nb.jpg');
    final request = http.requestsTo(uploadPath).last;
    final file = multipartParts(request.body!, boundaryOf(request)).last;
    expect(file.headers['content-disposition'], 'form-data; name="file_up"; filename="a%22%0D%0Ab.jpg"');
  });

  test('an upload answer without an address is a decoding error', () async {
    http.routes['POST $uploadPath'] = (200, '{"code":0,"message":"0","data":{"image_width":1}}');
    await expectLater(client.uploadCommentPicture(bytes: [1], filename: 'a.jpg'), throwsA(isA<BiliDecodingError>()));
  });

  test('a refused upload throws the server message', () async {
    http.routes['POST $uploadPath'] = (200, '{"code":-400,"message":"文件过大"}');
    await expectLater(
      client.uploadCommentPicture(bytes: [1], filename: 'a.jpg'),
      throwsA(const BiliError.api(code: -400, message: '文件过大')),
    );
  });

  test('an upload without login throws needsLogin without sending', () async {
    final loggedOut = makeTestClient(http);
    await expectLater(
      loggedOut.uploadCommentPicture(bytes: [1], filename: 'a.jpg'),
      throwsA(isA<BiliError>().having((error) => error.needsLogin, 'needsLogin', isTrue)),
    );
    expect(http.requestsTo(uploadPath), isEmpty);
  });

  test('a comment carries its mentions and pictures as JSON, and neither when there are none', () async {
    http.routes['POST $addPath'] = (
      200,
      '{"code":0,"data":{"reply":{"rpid":9,"member":{"mid":"1","uname":"我"},"content":{"message":"x"}}}}',
    );
    await client.postComment(
      aid: 80433022,
      message: '@关注甲 @Name 看图',
      mentions: {'关注甲': 2001, 'Name': 2002},
      pictures: const [
        UploadedPicture(url: 'http://i0.hdslb.com/bfs/new_dyn/pic-1.jpg', width: 1080, height: 1920, sizeKb: 245.67),
        UploadedPicture(url: 'http://i0.hdslb.com/bfs/new_dyn/pic-2.png', width: 300, height: 200, sizeKb: 12),
      ],
    );
    final fields = formFields(http.bodyText(http.requestsTo(addPath).last));
    expect(jsonDecode(fields['at_name_to_mid']!), {'关注甲': 2001, 'Name': 2002});
    expect(jsonDecode(fields['pictures']!), [
      {
        'img_src': 'http://i0.hdslb.com/bfs/new_dyn/pic-1.jpg',
        'img_width': 1080,
        'img_height': 1920,
        'img_size': 245.67,
      },
      {'img_src': 'http://i0.hdslb.com/bfs/new_dyn/pic-2.png', 'img_width': 300, 'img_height': 200, 'img_size': 12},
    ]);
    expect(fields['message'], '@关注甲 @Name 看图');
    expect(fields['csrf'], 'CSRF-SECRET');

    await client.postComment(aid: 80433022, message: '没有附件');
    final plain = formFields(http.bodyText(http.requestsTo(addPath).last));
    expect(plain.containsKey('at_name_to_mid'), isFalse);
    expect(plain.containsKey('pictures'), isFalse);
  });

  test('the log never carries the csrf token, the session cookie or the search', () async {
    http.routes[followingsPath] = (200, ComposerFixtures.followings);
    http.routes[searchPath] = (200, ComposerFixtures.searched);
    http.routes['POST $uploadPath'] = (200, ComposerFixtures.uploaded);
    await client.followings(mid: 1001);
    await client.followings(mid: 1001, query: '关注甲');
    await client.uploadCommentPicture(bytes: [1, 2, 3], filename: 'a.jpg');
    final log = sink.events.map((event) => event.encode()).join('\n');
    expect(log, contains(uploadPath));
    expect(log, isNot(contains('CSRF-SECRET')));
    expect(log, isNot(contains('SESSION-SECRET')));
    expect(log, isNot(contains('关注甲')));
  });

  test('upload_bfs data and followings entries decode on their own', () {
    expect(
      UploadedPicture.fromJson({'image_url': 'u', 'image_width': 10.0, 'image_height': 20, 'img_size': 3}),
      const UploadedPicture(url: 'u', width: 10, height: 20, sizeKb: 3),
    );
    expect(
      UploadedPicture.fromJson({'image_url': 'u'}),
      const UploadedPicture(url: 'u', width: 0, height: 0, sizeKb: 0),
    );
    expect(() => UploadedPicture.fromJson({'image_url': ''}), throwsA(isA<DecodeError>()));
    expect(const UploadedPicture(url: 'u', width: 1, height: 2, sizeKb: 0.5).toJson(), {
      'img_src': 'u',
      'img_width': 1,
      'img_height': 2,
      'img_size': 0.5,
    });
    expect(MentionCandidate.fromJson({'mid': 5, 'uname': 'n'}), const MentionCandidate(mid: 5, name: 'n'));
    expect(() => MentionCandidate.fromJson({'mid': 5}), throwsA(isA<DecodeError>()));
    expect(() => MentionCandidate.fromJson({'uname': 'n'}), throwsA(isA<DecodeError>()));
  });
}
