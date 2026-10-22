import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:test/test.dart';

import 'fake_http.dart';
import 'fixtures.dart';

/// A clock the test moves; each wait wakes when the clock passes its end, in the order they fall due.
final class _Time {
  Duration now = Duration.zero;
  final _pending = <({Duration due, int order, Completer<void> done})>[];
  int _made = 0;

  Future<void> wait(Duration duration) {
    final done = Completer<void>();
    _pending.add((due: now + duration, order: _made++, done: done));
    return done.future;
  }

  Future<void> elapse(Duration by) async {
    final end = now + by;
    while (true) {
      _pending.sort((a, b) => a.due == b.due ? a.order.compareTo(b.order) : a.due.compareTo(b.due));
      final next = _pending.firstOrNull;
      if (next == null || next.due > end) break;
      _pending.removeAt(0);
      now = next.due;
      next.done.complete();
      await pumpEventQueue();
    }
    now = end;
    await pumpEventQueue();
  }
}

/// Records what reached it and when, answering `{}` or throwing [error].
final class _Inner implements HTTPTransport {
  _Inner([this.time]);

  final _Time? time;
  final sent = <({String method, String path, Duration at})>[];
  Object? error;
  int status = 200;
  String body = '{}';

  List<String> get paths => [for (final request in sent) request.path];

  @override
  Future<HTTPResponse> send(HTTPRequest request) async {
    sent.add((method: request.method, path: request.url.path, at: time?.now ?? Duration.zero));
    final failure = error;
    if (failure != null) throw failure;
    return HTTPResponse(status: status, headers: {}, body: utf8.encode(body), finalURL: request.url);
  }
}

HTTPRequest _get(String path) => HTTPRequest(url: Uri.parse('https://api.bilibili.com$path'));

HTTPRequest _post(String path, {String host = 'https://api.bilibili.com'}) => HTTPRequest(
  url: Uri.parse('$host$path?csrf=secret-jct'),
  method: 'POST',
  body: Uint8List.fromList(utf8.encode('aid=1&csrf=secret-jct')),
);

const _readOnly = BiliAPIError(code: GuardedTransport.readOnlyCode, message: 'PC 只读，未发送');
const _capped = BiliAPIError(code: GuardedTransport.capCode, message: 'PC 本次调用已达上限，请重启应用');
const _halted = BiliAPIError(code: GuardedTransport.haltCode, message: 'B 站风控拦截，本次已停止请求，请稍后重启应用');

void main() {
  late _Time time;
  late _Inner inner;
  late MemorySink memory;
  late Logger logger;

  setUp(() {
    time = _Time();
    inner = _Inner(time);
    memory = MemorySink();
    logger = Logger(session: 'test')..add(memory);
  });

  GuardedTransport guard({
    Set<String> writesAllowed = const {},
    Set<String> uncounted = const {},
    int cap = 200,
  }) => GuardedTransport(
    inner,
    writesAllowed: writesAllowed,
    uncounted: uncounted,
    cap: cap,
    logger: logger,
    clock: () => time.now,
    wait: time.wait,
  );

  String log() => memory.events.map((event) => event.encode()).join('\n');

  group('writes', () {
    test('a GET goes through', () async {
      final transport = guard();
      final response = await transport.send(_get('/x/web-interface/nav'));
      expect(response.status, 200);
      expect(inner.paths, ['/x/web-interface/nav']);
      expect(transport.sent, 1);
    });

    test('a write whose path is not allowed is refused before it is sent', () async {
      final transport = guard(writesAllowed: {'passport.bilibili.com/login/exit/v2'});
      for (final method in ['POST', 'PUT', 'DELETE', 'HEAD', 'post']) {
        final request = HTTPRequest(
          url: Uri.parse('https://api.bilibili.com/x/web-interface/archive/like'),
          method: method,
        );
        await expectLater(transport.send(request), throwsA(_readOnly));
      }
      expect(inner.sent, isEmpty);
      expect(transport.sent, 0);
    });

    test('a write whose path is allowed is sent', () async {
      final transport = guard(writesAllowed: {'passport.bilibili.com/login/exit/v2'});
      await transport.send(_post('/login/exit/v2', host: 'https://passport.bilibili.com'));
      expect(inner.sent.single, (method: 'POST', path: '/login/exit/v2', at: Duration.zero));
      expect(transport.sent, 1);
    });

    test('the refusal is logged once per path, with the method and path only', () async {
      final transport = guard();
      for (var beat = 0; beat < 5; beat++) {
        await expectLater(transport.send(_post('/x/click-interface/web/heartbeat')), throwsA(_readOnly));
      }
      await expectLater(transport.send(_post('/x/v2/reply/add')), throwsA(_readOnly));
      final refused = memory.events.where((event) => event.msg == 'pc guard refused').toList();
      expect([for (final event in refused) event.level], [LogLevel.warn, LogLevel.warn]);
      expect(
        [for (final event in refused) event.f],
        [
          {'method': const LogString('POST'), 'path': const LogString('/x/click-interface/web/heartbeat')},
          {'method': const LogString('POST'), 'path': const LogString('/x/v2/reply/add')},
        ],
      );
      expect(log(), isNot(contains('secret')));
      expect(log(), isNot(contains('aid=')));
    });
  });

  group('pacing', () {
    test('eight go at once, then one a second', () async {
      final transport = guard();
      final answers = [for (var index = 0; index < 10; index++) transport.send(_get('/r$index'))];
      await pumpEventQueue();
      expect(inner.sent, hasLength(8));
      expect(inner.sent.every((request) => request.at == Duration.zero), isTrue);

      await time.elapse(const Duration(milliseconds: 999));
      expect(inner.sent, hasLength(8));
      await time.elapse(const Duration(milliseconds: 1));
      expect(inner.sent, hasLength(9));
      await time.elapse(const Duration(seconds: 1));
      expect(inner.sent, hasLength(10));
      expect(inner.sent.last.at, const Duration(seconds: 2));
      await Future.wait(answers);
      expect(transport.sent, 10);
    });

    test('an idle bucket fills again, one token a second, up to eight', () async {
      final transport = guard();
      for (var index = 0; index < 8; index++) {
        unawaited(transport.send(_get('/first$index')));
      }
      await pumpEventQueue();
      expect(inner.sent, hasLength(8));

      await time.elapse(const Duration(seconds: 3));
      for (var index = 0; index < 4; index++) {
        unawaited(transport.send(_get('/second$index')));
      }
      await pumpEventQueue();
      expect(inner.sent, hasLength(11), reason: 'three tokens came back in three seconds');

      await time.elapse(const Duration(minutes: 1));
      expect(inner.sent, hasLength(12));
      for (var index = 0; index < 9; index++) {
        unawaited(transport.send(_get('/third$index')));
      }
      await pumpEventQueue();
      expect(inner.sent, hasLength(20), reason: 'a minute idle fills the bucket to eight, no more');
    });

    test('waiting requests go in the order they came, a late one after them', () async {
      final transport = guard();
      for (var index = 0; index < 8; index++) {
        unawaited(transport.send(_get('/burst$index')));
      }
      for (final path in ['/a', '/b', '/c']) {
        unawaited(transport.send(_get(path)));
      }
      await time.elapse(const Duration(milliseconds: 1500));
      unawaited(transport.send(_get('/late')));
      await time.elapse(const Duration(seconds: 10));
      expect(inner.paths.skip(8), ['/a', '/b', '/c', '/late']);
      expect([for (final request in inner.sent.skip(8)) request.at.inSeconds], [1, 2, 3, 4]);
    });

    test('real time by default', () async {
      final real = _Inner();
      final transport = GuardedTransport(real, burst: 1, refill: const Duration(milliseconds: 40), logger: logger);
      final watch = Stopwatch()..start();
      await transport.send(_get('/first'));
      expect(watch.elapsed, lessThan(const Duration(milliseconds: 40)));
      await transport.send(_get('/second'));
      expect(watch.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 30)));
      expect(real.paths, ['/first', '/second']);
    });
  });

  group('more writes', () {
    test("the allowed write is matched by host too: the logout's path on another host is refused", () async {
      final transport = guard(writesAllowed: {'passport.bilibili.com/login/exit/v2'});
      await expectLater(transport.send(_post('/login/exit/v2')), throwsA(_readOnly));
      expect(inner.sent, isEmpty);
    });

    test('the GETs that change the account (不感兴趣) are refused as writes', () async {
      final transport = guard();
      await expectLater(transport.send(_get('/x/feed/dislike')), throwsA(_readOnly));
      await expectLater(transport.send(_get('/x/feed/dislike/cancel')), throwsA(_readOnly));
      expect(inner.sent, isEmpty);
    });
  });

  group("Bilibili's risk control", () {
    test('a 412 stops every request for the rest of the run, and the log says so once', () async {
      final transport = guard(writesAllowed: {'passport.bilibili.com/login/exit/v2'});
      inner.status = 412;
      final answer = await transport.send(_get('/x/web-interface/nav'));
      expect(answer.status, 412, reason: 'the caller still sees the answer');
      inner.status = 200;
      await expectLater(transport.send(_get('/x/web-interface/nav')), throwsA(_halted));
      await expectLater(transport.send(_get('/x/frontend/finger/spi')), throwsA(_halted));
      expect(inner.paths, ['/x/web-interface/nav']);
      await transport.send(_post('/login/exit/v2', host: 'https://passport.bilibili.com'));
      expect(inner.paths.last, '/login/exit/v2', reason: 'the logout still goes');
      final halted = memory.events.where((event) => event.msg == 'pc guard halted').single;
      expect(halted.level, LogLevel.error);
      expect(halted.f['status'], const LogInt(412));
    });

    for (final code in [-352, -412]) {
      test('an answer with code $code stops the run too', () async {
        final transport = guard();
        inner.body = '{"code":$code,"message":"风控校验失败","ttl":1}';
        await transport.send(_get('/x/web-interface/wbi/search/type'));
        inner.body = '{}';
        await expectLater(transport.send(_get('/x/web-interface/nav')), throwsA(_halted));
        expect(inner.sent, hasLength(1));
      });
    }

    test('other errors and bodies that are not JSON leave the run going', () async {
      final transport = guard();
      inner.body = '{"code":-404,"message":"啥都木有"}';
      await transport.send(_get('/x/web-interface/view'));
      inner.body = 'not json';
      await transport.send(_get('/x/v2/dm/web/seg.so'));
      inner.body = '{}';
      await transport.send(_get('/x/web-interface/nav'));
      expect(inner.sent, hasLength(3));
    });
  });

  group('cap', () {
    test("the QR login's calls are paced but not counted", () async {
      final transport = guard(cap: 1, uncounted: {'/x/passport-login/web/qrcode/poll'});
      for (var index = 0; index < 5; index++) {
        await transport.send(_get('/x/passport-login/web/qrcode/poll'));
      }
      await transport.send(_get('/x/web-interface/nav'));
      await expectLater(transport.send(_get('/x/web-interface/nav')), throwsA(_capped));
      expect(inner.sent, hasLength(6));
    });

    test('past the cap every request is refused without being sent, and the log says so once', () async {
      final transport = guard(cap: 3);
      for (var index = 0; index < 3; index++) {
        await transport.send(_get('/r$index'));
      }
      await expectLater(transport.send(_get('/over')), throwsA(_capped));
      await expectLater(transport.send(_get('/over-again')), throwsA(_capped));
      expect(inner.paths, ['/r0', '/r1', '/r2']);
      expect(transport.sent, 3);
      final reached = memory.events.where((event) => event.msg == 'pc guard cap reached').single;
      expect(reached.level, LogLevel.error);
      expect(reached.f, {'cap': const LogInt(3)});
    });

    test('the logout still goes past the cap, so a capped run can end its session', () async {
      final transport = guard(cap: 1, writesAllowed: {'passport.bilibili.com/login/exit/v2'});
      await transport.send(_get('/r0'));
      await expectLater(transport.send(_get('/over')), throwsA(_capped));
      await transport.send(_post('/login/exit/v2', host: 'https://passport.bilibili.com'));
      expect(inner.paths, ['/r0', '/login/exit/v2']);
    });

    test("the refusals tell the user they never reached Bilibili", () {
      expect(
        const BiliError.api(code: GuardedTransport.readOnlyCode, message: 'PC 只读，未发送').userMessage,
        'PC 只读，未发送',
      );
      expect(
        const BiliError.api(code: GuardedTransport.capCode, message: 'PC 本次调用已达上限，请重启应用').userMessage,
        'PC 本次调用已达上限，请重启应用',
      );
    });

    test('one that could only wait to be refused is refused at once', () async {
      final transport = guard(cap: 9);
      final answers = [for (var index = 0; index < 9; index++) transport.send(_get('/r$index'))];
      await expectLater(transport.send(_get('/tenth')), throwsA(_capped));
      expect(inner.sent, hasLength(8));
      await time.elapse(const Duration(seconds: 1));
      await Future.wait(answers);
      expect(inner.sent, hasLength(9));
      expect(transport.sent, 9);
    });

    test('refused requests are not counted', () async {
      final transport = guard(cap: 2);
      for (var index = 0; index < 5; index++) {
        await expectLater(transport.send(_post('/x/web-interface/archive/like')), throwsA(_readOnly));
      }
      expect(transport.sent, 0);
      await transport.send(_get('/one'));
      await transport.send(_get('/two'));
      await expectLater(transport.send(_get('/three')), throwsA(_capped));
      await expectLater(transport.send(_post('/x/web-interface/archive/like')), throwsA(_readOnly));
      expect(transport.sent, 2);
      expect(inner.paths, ['/one', '/two']);
    });

    test('a request the inner transport fails on still counts', () async {
      final transport = guard(cap: 1);
      final offline = TimeoutException('no answer');
      inner.error = offline;
      await expectLater(transport.send(_get('/x/web-interface/nav')), throwsA(same(offline)));
      expect(transport.sent, 1);
      inner.error = null;
      await expectLater(transport.send(_get('/x/web-interface/nav')), throwsA(_capped));
      expect(inner.sent, hasLength(1));
    });
  });

  group('through BiliClient', () {
    BiliClient client(HTTPTransport transport) => BiliClient(
      transport: transport,
      cookies: CookieJar({'SESSDATA': 's', 'bili_jct': 'j', 'buvid3': 'b3', 'buvid4': 'b4'}),
      now: () => testNow,
      logger: logger,
    );

    test('a refused write reaches the caller as the guard\'s BiliAPIError, not a network error', () async {
      final http = FakeHTTP()..routes = {'/x/web-interface/archive/like': (200, '{"code":0,"message":"0"}')};
      final api = client(GuardedTransport(http, logger: logger, clock: () => time.now, wait: time.wait));
      await expectLater(api.like(aid: 1, bvid: 'BV1xx411c7mD', on: true), throwsA(_readOnly));
      expect(http.requests, isEmpty);
      expect(memory.events.where((event) => event.cat == LogCategory.api && event.level == LogLevel.error), isEmpty);
    });

    test('a read past the cap reaches the caller as the guard\'s BiliAPIError', () async {
      final http = FakeHTTP()..routes = {'/x/web-interface/nav': (200, Fixtures.navLoggedIn)};
      final api = client(GuardedTransport(http, cap: 1, logger: logger, clock: () => time.now, wait: time.wait));
      expect((await api.nav()).isLogin, isTrue);
      await expectLater(api.nav(), throwsA(_capped));
      expect(http.requests, hasLength(1));
    });
  });
}
