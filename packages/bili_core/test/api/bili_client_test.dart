import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_core/api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'fake_http.dart';
import 'fixtures.dart';

const navPath = '/x/web-interface/nav';
const viewPath = '/x/web-interface/view';
const playPath = '/x/player/wbi/playurl';
const spiPath = '/x/frontend/finger/spi';

void main() {
  test('nav decodes logged out and keys are cached for signing', () async {
    final http = FakeHTTP()..routes = {navPath: (200, Fixtures.navLoggedOut), playPath: (200, Fixtures.playURL)};
    final client = makeTestClient(http);
    final nav = await client.nav();
    expect(nav.isLogin, isFalse);
    await client.playURL(bvid: 'BV1GJ411x7h7', cid: 1, quality: 120);
    await client.playURL(bvid: 'BV1GJ411x7h7', cid: 1, quality: 120);
    expect(http.requestsTo(navPath).length, 1);
  });

  test('play URL sends DASH flags, signature and headers', () async {
    final http = FakeHTTP()..routes = {navPath: (200, Fixtures.navLoggedIn), playPath: (200, Fixtures.playURL)};
    final client = makeTestClient(http, cookies: {'SESSDATA': 'abc', 'buvid3': 'b3'});
    final info = await client.playURL(bvid: 'BV1GJ411x7h7', cid: 137649199, quality: 120);
    expect(info.dash?.video.length, 4);
    final request = http.requestsTo(playPath).first;
    final query = http.query(request);
    expect(query['fnval'], '4048');
    expect(query['fourk'], '1');
    expect(query['qn'], '120');
    expect(query['wts'], '1702204169');
    expect(query['w_rid']?.length, 32);
    expect(request.headers['Referer'], 'https://www.bilibili.com/');
    expect(request.headers['User-Agent'], BiliClient.userAgent);
    expect(request.headers['Cookie'], 'SESSDATA=abc; buvid3=b3');
  });

  test('ensureRiskCookies fetches only when missing', () async {
    final http = FakeHTTP()..routes = {spiPath: (200, Fixtures.spi)};
    final client = makeTestClient(http);
    await client.ensureRiskCookies();
    expect(client.cookies.value('buvid3'), 'B3-VALUE-infoc');
    expect(client.cookies.value('buvid4'), 'B4-VALUE');
    await client.ensureRiskCookies();
    expect(http.requestsTo(spiPath).length, 1);
  });

  test('API error code throws', () async {
    final http = FakeHTTP()..routes = {viewPath: (200, Fixtures.notFound)};
    try {
      await makeTestClient(http).view(bvid: 'BV1GJ411x7h7');
      fail('expected an error');
    } on BiliError catch (error) {
      expect(error, const BiliError.api(code: -404, message: '啥都木有'));
      expect(error.userMessage, '视频不存在或已被删除');
    }
  });

  test('durl only throws notDash', () async {
    final http = FakeHTTP()..routes = {navPath: (200, Fixtures.navLoggedIn), playPath: (200, Fixtures.durlOnly)};
    try {
      await makeTestClient(http).playURL(bvid: 'BV1GJ411x7h7', cid: 1, quality: 80);
      fail('expected notDash');
    } on BiliError catch (error) {
      expect(error, BiliError.notDash);
      expect(error.userMessage, '这个视频不是 DASH 格式，暂不支持');
    }
  });

  test('risk control is retried once with fresh cookies', () async {
    final http = FakeHTTP()..routes = {viewPath: (412, ''), spiPath: (200, Fixtures.spi)};
    final client = makeTestClient(http, cookies: {'buvid3': 'old', 'buvid4': 'old'});
    await expectLater(client.view(bvid: 'BV1GJ411x7h7'), throwsA(const BiliError.http(412)));
    expect(http.requestsTo(viewPath).length, 2);
    expect(http.requestsTo(spiPath).length, 1);
    expect(client.cookies.value('buvid3'), 'B3-VALUE-infoc');
  });

  test('resolve short link follows redirect', () async {
    final http = FakeHTTP()..routes = {viewPath: (200, Fixtures.view)};
    http.redirects['b23.tv/xyZ123a'] = Uri.parse('https://www.bilibili.com/video/BV1GJ411x7h7?p=2&share_source=copy');
    final (:view, :page) = await makeTestClient(http).resolve(VideoLink.short(Uri.parse('https://b23.tv/xyZ123a')));
    expect(view.bvid, 'BV1GJ411x7h7');
    expect(page, 2);
    expect(http.query(http.requestsTo(viewPath).first)['bvid'], 'BV1GJ411x7h7');
  });

  test('resolve requests a plain-http short link over https', () async {
    final http = FakeHTTP()..routes = {viewPath: (200, Fixtures.view)};
    http.redirects['b23.tv/xyZ123a'] = Uri.parse('https://www.bilibili.com/video/BV1GJ411x7h7');
    await makeTestClient(http, cookies: {'SESSDATA': 'abc', 'buvid3': 'b3'})
        .resolve(VideoLink.short(Uri.parse('http://b23.tv/xyZ123a')));
    final first = http.requests.first;
    expect(first.url.scheme, 'https');
    expect(first.url.host, 'b23.tv');
    expect(first.headers['Cookie'], isNull);
  });

  test('empty WBI keys fail instead of signing with a bad key', () async {
    final http = FakeHTTP();
    const emptyKeys = '{"code":-101,"message":"账号未登录","data":{"isLogin":false,"wbi_img":{"img_url":"","sub_url":""}}}';
    http.routes = {navPath: (200, emptyKeys), playPath: (200, Fixtures.playURL)};
    await expectLater(
        makeTestClient(http).playURL(bvid: 'BV1GJ411x7h7', cid: 1, quality: 80), throwsA(isA<BiliDecodingError>()));
    expect(http.requestsTo(playPath), isEmpty);
  });

  test('redirect drops the body off Bilibili hosts', () {
    Uint8List? redirected(String url) => ClientHTTPTransport.redirectedRequest(
            HTTPRequest(url: Uri.parse(url), method: 'POST', body: utf8.encode('csrf=T')))
        .body;
    expect(redirected('https://api.bilibili.com/x/v2/history/toview/add'), utf8.encode('csrf=T'));
    expect(redirected('https://evil.example/steal'), isNull);
  });

  test('redirect keeps the Cookie on Bilibili hosts only', () {
    String? redirected(String url) {
      final result = ClientHTTPTransport.redirectedRequest(
          HTTPRequest(url: Uri.parse(url), headers: {'Cookie': 'SESSDATA=abc', 'User-Agent': 'agent'}));
      expect(result.headers['User-Agent'], 'agent');
      return result.headers['Cookie'];
    }

    expect(redirected('https://www.bilibili.com/video/BV1GJ411x7h7'), 'SESSDATA=abc');
    expect(redirected('https://api.bilibili.com/x/web-interface/view'), 'SESSDATA=abc');
    expect(redirected('https://bilibili.com/'), 'SESSDATA=abc');
    expect(redirected('https://evil.example/steal'), isNull);
    expect(redirected('https://bilibili.com.evil.example/'), isNull);
    expect(redirected('https://notbilibili.com/'), isNull);
  });

  test('cookie jar header and parse', () {
    final jar = CookieJar(CookieJar.parse('SESSDATA=abc; buvid3=x=y; empty'));
    expect(jar.value('buvid3'), 'x=y');
    expect(jar.headerValue, 'SESSDATA=abc; buvid3=x=y');
    var changes = 0;
    jar.onChange = (_) => changes += 1;
    jar.set('bili_jct', 'z');
    jar.removeAll();
    expect(changes, 2);
    expect(jar.headerValue, isNull);
  });

  // Swift left redirects to URLSession; here the transport follows them itself, so its loop is tested too.
  group('ClientHTTPTransport', () {
    test('a redirect off Bilibili loses the Cookie and the body, and finalURL is the last hop', () async {
      final seen = <http.Request>[];
      final client = MockClient((request) async {
        seen.add(request);
        if (request.url.host == 'api.bilibili.com') {
          return http.Response('', 307, headers: {'location': 'https://evil.example/steal'});
        }
        return http.Response('ok', 200);
      });
      final transport = ClientHTTPTransport(client: client);
      final response = await transport.send(HTTPRequest(
        url: Uri.parse('https://api.bilibili.com/x/v2/history/toview/add'),
        method: 'POST',
        headers: {'Cookie': 'SESSDATA=abc', 'User-Agent': 'agent'},
        body: utf8.encode('csrf=T'),
      ));
      expect(response.status, 200);
      expect(response.finalURL, Uri.parse('https://evil.example/steal'));
      expect(seen.length, 2);
      expect(seen[0].headers['Cookie'], 'SESSDATA=abc');
      expect(seen[0].body, 'csrf=T');
      expect(seen[1].method, 'POST');
      expect(seen[1].headers.containsKey('Cookie'), isFalse);
      expect(seen[1].headers['User-Agent'], 'agent');
      expect(seen[1].bodyBytes, isEmpty);
    });

    test('a 302 after a POST continues as a GET; Bilibili hops keep the Cookie', () async {
      final seen = <http.Request>[];
      final client = MockClient((request) async {
        seen.add(request);
        if (request.url.path == '/a') return http.Response('', 302, headers: {'location': '/b'});
        return http.Response('done', 200, headers: {'X-Thing': '1'});
      });
      final response = await ClientHTTPTransport(client: client).send(HTTPRequest(
        url: Uri.parse('https://www.bilibili.com/a'),
        method: 'POST',
        headers: {'Cookie': 'SESSDATA=abc', 'Content-Type': 'application/x-www-form-urlencoded'},
        body: utf8.encode('x=1'),
      ));
      expect(utf8.decode(response.body), 'done');
      expect(response.headers['x-thing'], '1');
      expect(response.finalURL, Uri.parse('https://www.bilibili.com/b'));
      expect(seen[1].method, 'GET');
      expect(seen[1].bodyBytes, isEmpty);
      expect(seen[1].headers['Cookie'], 'SESSDATA=abc');
      expect(seen[1].headers.containsKey('Content-Type'), isFalse);
    });

    test('a server that never answers times out', () async {
      final client = MockClient((request) => Completer<http.Response>().future);
      final transport = ClientHTTPTransport(client: client, timeout: const Duration(milliseconds: 50));
      await expectLater(
          transport.send(HTTPRequest(url: Uri.parse('https://api.bilibili.com/x'))), throwsA(isA<TimeoutException>()));
    });
  });
}
