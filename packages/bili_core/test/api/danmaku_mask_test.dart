import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:test/test.dart';

import 'fake_http.dart';

/// Made up: no real mask address is ever kept in a test.
const _maskUrl = 'https://upos-sz-madeup-cmask.bilivideo.com/maskfile/test/1-made-up.webmask?deadline=1&upsig=s3cr3t';

PlayerInfo _infoWith(Object? mask) => PlayerInfo.fromJson(
  jsonDecode(jsonEncode({'last_play_cid': 1001, 'view_points': <Object>[], 'dm_mask': ?mask})),
);

Map<String, Object?> _mask(Object? url, {Object? fps = 30}) => {
  'cid': 1001,
  'plat': 0,
  'fps': fps,
  'time': 0,
  'mask_url': url,
};

/// Answers every request with [status], [headers] and [body], and keeps what was asked.
final class _Cdn implements HTTPTransport {
  _Cdn(this.status, this.body, {this.headers = const {}});

  final int status;
  final Uint8List body;
  final Map<String, String> headers;
  final List<HTTPRequest> requests = [];

  @override
  Future<HTTPResponse> send(HTTPRequest request) async {
    requests.add(request);
    return HTTPResponse(status: status, headers: headers, body: body, finalURL: request.url);
  }
}

/// Fails as cupertino_http does: its message ends with the request's URL, query and all.
final class _Offline implements HTTPTransport {
  @override
  Future<HTTPResponse> send(HTTPRequest request) async =>
      throw _OfflineError('The Internet connection appears to be offline. uri=${request.url}');
}

final class _OfflineError implements Exception {
  _OfflineError(this.message);

  final String message;

  @override
  String toString() => 'NSErrorClientException: $message';
}

final class _Events implements LogSink {
  final List<LogEvent> events = [];

  @override
  void receive(LogEvent event) => events.add(event);

  String get text => events.map((event) => event.encode()).join('\n');
}

void main() {
  group('PlayerInfo reads dm_mask', () {
    test('when the part has a mask', () {
      expect(
        _infoWith(_mask(_maskUrl)).mask,
        DanmakuMaskInfo(cid: 1001, plat: 0, fps: 30, time: 0, url: Uri.parse(_maskUrl)),
      );
    });

    test('as none when it is absent', () {
      expect(_infoWith(null).mask, isNull);
    });

    test('a protocol-relative address as https', () {
      final mask = _infoWith(_mask(_maskUrl.replaceFirst('https:', ''))).mask;
      expect(mask?.url, Uri.parse(_maskUrl));
    });

    test("as none when the address isn't https on Bilibili's video CDN", () {
      final path = '/maskfile/test/1-made-up.webmask?upsig=s3cr3t';
      for (final refused in [
        'http://upos-sz-madeup-cmask.bilivideo.com$path',
        'https://evil.example.com$path',
        'https://evilbilivideo.com$path',
        'https://bilivideo.com.evil.example$path',
        'https://upos-sz-madeup-cmask.bilivideo.com:8443$path',
        'https://user@upos-sz-madeup-cmask.bilivideo.com$path',
        'https://upos-anything.akamaized.net$path',
        '//evil.example.com$path',
        'not an address',
        '',
      ]) {
        expect(_infoWith(_mask(refused)).mask, isNull, reason: refused);
      }
    });

    test("keeps a refused address's host alone, for the log", () {
      expect(_infoWith(_mask('https://evil.example.com/m.webmask?upsig=s3cr3t')).refusedMaskHost, 'evil.example.com');
      expect(_infoWith(_mask('http://upos-sz-madeup-cmask.bilivideo.com/m.webmask')).refusedMaskHost,
          'upos-sz-madeup-cmask.bilivideo.com');
      expect(_infoWith(_mask('not an address')).refusedMaskHost, '?');
      expect(_infoWith(_mask(_maskUrl)).refusedMaskHost, isNull);
    });

    test("on the CDN's other hosts", () {
      for (final allowed in [
        'https://upos-sz-madeup.bilivideo.cn/m.webmask?upsig=s3cr3t',
        'https://upos-hz-mirrorakam.akamaized.net/m.webmask?upsig=s3cr3t',
        'https://UPOS-SZ-MADEUP-CMASK.BILIVIDEO.COM/m.webmask',
      ]) {
        expect(_infoWith(_mask(allowed)).mask, isNotNull, reason: allowed);
      }
    });

    test('as none when it is malformed', () {
      expect(_infoWith('a string').mask, isNull);
      expect(_infoWith(<Object>[]).mask, isNull);
      expect(_infoWith(_mask(null)).mask, isNull);
      expect(_infoWith(_mask(42)).mask, isNull);
      expect(_infoWith(_mask(_maskUrl, fps: 'thirty')).mask, isNull);
    });

    test('absent numbers as 0', () {
      final mask = _infoWith({'mask_url': _maskUrl}).mask;
      expect(mask, DanmakuMaskInfo(cid: 0, plat: 0, fps: 0, time: 0, url: Uri.parse(_maskUrl)));
    });

    test('into the equality of PlayerInfo and of the mask, its address included', () {
      final one = _infoWith(_mask(_maskUrl));
      expect(one, _infoWith(_mask(_maskUrl)));
      expect(one.hashCode, _infoWith(_mask(_maskUrl)).hashCode);
      expect(one, isNot(_infoWith(null)));
      final other = _infoWith(_mask(_maskUrl.replaceFirst('s3cr3t', 'other')));
      expect(other, isNot(one));
      expect(other.mask, isNot(one.mask));
      expect(one.mask?.hashCode, _infoWith(_mask(_maskUrl)).mask?.hashCode);
    });

    test("whose description never shows the address", () {
      final text = '${_infoWith(_mask(_maskUrl)).mask}';
      expect(text, 'DanmakuMaskInfo(cid: 1001, plat: 0, fps: 30, time: 0)');
    });
  });

  group('maskRange', () {
    late _Events log;
    late Logger logger;
    final url = Uri.parse(_maskUrl);
    final file = Uint8List.fromList([for (var i = 0; i < 100; i++) i]);

    setUp(() {
      log = _Events();
      logger = Logger(session: 'test')..add(log);
    });

    BiliClient clientOver(HTTPTransport transport) => BiliClient(
      transport: transport,
      cookies: CookieJar({'SESSDATA': 'session', 'bili_jct': 'csrf'}),
      now: () => testNow,
      logger: logger,
    );

    void expectNoAddress(String text) {
      for (final leak in ['s3cr3t', 'upsig', 'deadline', 'maskfile', '.webmask', '?']) {
        expect(text, isNot(contains(leak)), reason: leak);
      }
    }

    test('asks the range with the media headers and no cookies, and takes a 206', () async {
      final cdn = _Cdn(206, Uint8List.sublistView(file, 16, 48), headers: {'content-range': 'bytes 16-47/100'});
      final bytes = await clientOver(cdn).maskRange(url, start: 16, end: 47);
      expect(bytes, Uint8List.sublistView(file, 16, 48));
      final request = cdn.requests.single;
      expect(request.method, 'GET');
      expect(request.url, url);
      expect(request.headers, {
        'User-Agent': BiliClient.userAgent,
        'Referer': BiliClient.referer,
        'Range': 'bytes=16-47',
      });
    });

    test('asks to the end of the file when there is no end', () async {
      final cdn = _Cdn(206, Uint8List.sublistView(file, 60));
      expect(await clientOver(cdn).maskRange(url, start: 60), Uint8List.sublistView(file, 60));
      expect(cdn.requests.single.headers['Range'], 'bytes=60-');
    });

    test('cuts a whole file answered with 200 to the range', () async {
      final client = clientOver(_Cdn(200, file));
      expect(await client.maskRange(url, start: 16, end: 47), Uint8List.sublistView(file, 16, 48));
      expect(await client.maskRange(url, start: 60), Uint8List.sublistView(file, 60));
      expect(await client.maskRange(url, start: 90, end: 200), Uint8List.sublistView(file, 90));
      await expectLater(client.maskRange(url, start: 100), throwsA(isA<BiliDecodingError>()));
    });

    test('refuses a 206 that starts elsewhere, and cuts one that runs past the end asked', () async {
      final elsewhere = _Cdn(206, Uint8List.sublistView(file, 0, 32), headers: {'content-range': 'bytes 0-31/100'});
      await expectLater(
        clientOver(elsewhere).maskRange(url, start: 16, end: 47),
        throwsA(isA<BiliDecodingError>()),
      );
      final longer = _Cdn(206, Uint8List.sublistView(file, 16), headers: {'content-range': 'bytes 16-99/100'});
      expect(await clientOver(longer).maskRange(url, start: 16, end: 47), Uint8List.sublistView(file, 16, 48));
    });

    test("asks nothing of a host off Bilibili's video CDN", () async {
      final cdn = _Cdn(206, file);
      final client = clientOver(cdn);
      for (final refused in [
        'http://upos-sz-madeup-cmask.bilivideo.com/m.webmask?upsig=s3cr3t',
        'https://evil.example.com/m.webmask?upsig=s3cr3t',
        'https://upos-anything.akamaized.net/m.webmask?upsig=s3cr3t',
        'https://api.bilibili.com/m.webmask?upsig=s3cr3t',
      ]) {
        await expectLater(
          client.maskRange(Uri.parse(refused), start: 0, end: 15),
          throwsA(isA<BiliInvalidLinkError>().having((error) => '$error', 'text', isNot(contains('s3cr3t')))),
          reason: refused,
        );
      }
      expect(cdn.requests, isEmpty);
    });

    test('asks nothing for a range that runs backwards', () async {
      final cdn = _Cdn(206, file);
      await expectLater(clientOver(cdn).maskRange(url, start: -1, end: 15), throwsRangeError);
      await expectLater(clientOver(cdn).maskRange(url, start: 20, end: 19), throwsRangeError);
      expect(cdn.requests, isEmpty);
    });

    test('fails on another status with the status alone, and logs the host at most', () async {
      Object? failure;
      try {
        await clientOver(_Cdn(403, Uint8List(0))).maskRange(url, start: 0, end: 15);
      } on Object catch (error) {
        failure = error;
      }
      expect(failure, const BiliError.http(403));
      expectNoAddress('$failure');
      expect(log.events.single.f['host'], const LogString('upos-sz-madeup-cmask.bilivideo.com'));
      expect(log.events.single.f['status'], const LogInt(403));
      expectNoAddress(log.text);
    });

    test("a transport failure keeps the error's type, never the address", () async {
      Object? failure;
      try {
        await clientOver(_Offline()).maskRange(url, start: 0, end: 15);
      } on Object catch (error) {
        failure = error;
      }
      expect(failure, const BiliError.network('_OfflineError'));
      expectNoAddress('$failure');
      expectNoAddress(log.text);
    });

    test('logs a success without the address', () async {
      await clientOver(_Cdn(206, Uint8List.sublistView(file, 0, 16))).maskRange(url, start: 0, end: 15);
      expect(log.events.single.msg, 'mask range');
      expect(log.events.single.f['bytes'], const LogInt(16));
      expectNoAddress(log.text);
    });
  });
}
