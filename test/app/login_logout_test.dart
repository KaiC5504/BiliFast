import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../account/fake_web_cookies.dart';
import '../playback/fakes.dart';
import 'fake_keychain.dart';

const _spiPath = '/x/frontend/finger/spi';
const _spi = '{"code":0,"message":"ok","data":{"b_3":"B3","b_4":"B4"}}';

/// What the login page hands over.
const _page = {'SESSDATA': 'page-sess', 'bili_jct': 'page-jct', 'DedeUserID': '12345'};

/// A stored login with values distinct enough to look for in the log.
const _stored = {'SESSDATA': 'stored-sess', 'bili_jct': 'stored-jct', 'buvid3': 'b3', 'buvid4': 'b4'};

/// Also records the deletes, and can fail the cookies' one.
class _Keychain extends FakeKeychain {
  _Keychain(super.next);

  final deletes = <String>[];
  Object? deleteCookiesError;

  @override
  Future<void> deleteCookies() async {
    deletes.add('cookies');
    final error = deleteCookiesError;
    if (error != null) throw error;
  }

  @override
  Future<void> deleteAppToken() async => deletes.add('app token');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemorySink memory;

  Future<AppEnvironment> load(FakeKeychain keychain, CannedHttp http, {FakeWebCookies? web}) {
    final logger = Logger(session: 'test');
    memory = MemorySink();
    logger.add(memory);
    return AppEnvironment.load(keychain: keychain, http: http, webCookies: web ?? FakeWebCookies(), logger: logger);
  }

  String log() => memory.events.map((event) => event.encode()).join('\n');

  group('didLogin', () {
    test('merges the page\'s cookies into the jar, writes them to the keychain and comes back logged in', () async {
      final keychain = _Keychain(const StoredCookies({'SESSDATA': 'expired', 'buvid3': 'b3', 'buvid4': 'b4'}));
      final http = Canned.http();
      final environment = await load(keychain, http);
      final seen = <Account>[];
      environment.addListener(() => seen.add(environment.account));

      expect(await environment.didLogin(_page), isTrue);
      const merged = {..._page, 'buvid3': 'b3', 'buvid4': 'b4'};
      expect(environment.cookies.all, merged);
      await pumpEventQueue();
      expect(keychain.saved.last, merged);
      expect(environment.account, isA<LoggedIn>());
      expect(environment.accountLabel, '测试用户');
      expect(environment.mid, 12345);
      expect(http.to(Canned.navPath).single.headers['Cookie'], contains('SESSDATA=page-sess'));
      expect(seen.first, isA<AccountUnknown>(), reason: 'checking the new login, as Swift');
      final event = memory.events.singleWhere((event) => event.msg == 'login');
      expect(event.f['count']?.toJson(), 3);
      expect(log(), isNot(contains('page-sess')));
    });

    test('a keychain read that failed at launch doesn\'t hold the login back from the keychain', () async {
      final keychain = _Keychain(const CookieLoadFailed(-25308));
      final environment = await load(keychain, Canned.http()..routes[_spiPath] = (200, _spi));
      expect(await environment.didLogin(_page), isTrue);
      await pumpEventQueue();
      expect(keychain.saved.last, {..._page, 'buvid3': 'B3', 'buvid4': 'B4'});
    });

    test('asks again after 1 s and 2 s while the account isn\'t logged in', () {
      fakeAsync((async) {
        final http = Canned.http()..routes[Canned.navPath] = (502, '');
        late AppEnvironment environment;
        unawaited(load(_Keychain(const StoredCookies(_stored)), http).then((loaded) => environment = loaded));
        async.flushMicrotasks();
        bool? answer;
        unawaited(environment.didLogin(_page).then((value) => answer = value));
        async.flushMicrotasks();
        expect(http.to(Canned.navPath), hasLength(1));
        expect(environment.accountLabel, '账号确认失败');

        async.elapse(const Duration(seconds: 1));
        expect(http.to(Canned.navPath), hasLength(2));
        http.routes[Canned.navPath] = (200, Canned.navLoggedIn);
        async.elapse(const Duration(milliseconds: 1999));
        expect(http.to(Canned.navPath), hasLength(2));
        expect(answer, isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(http.to(Canned.navPath), hasLength(3));
        expect(answer, isTrue);
        expect(environment.account, isA<LoggedIn>());
      });
    });

    test('gives up after 3 checks', () {
      fakeAsync((async) {
        final http = Canned.http(loggedIn: false);
        late AppEnvironment environment;
        unawaited(load(_Keychain(const StoredCookies(_stored)), http).then((loaded) => environment = loaded));
        async.flushMicrotasks();
        bool? answer;
        unawaited(environment.didLogin(_page).then((value) => answer = value));
        async.elapse(const Duration(seconds: 10));
        expect(answer, isFalse);
        expect(http.to(Canned.navPath), hasLength(3));
        expect(environment.account, isA<LoginExpired>());
      });
    });

    test('a logout while it is checking ends the checks', () {
      fakeAsync((async) {
        final http = Canned.http()..routes[Canned.navPath] = (502, '');
        late AppEnvironment environment;
        unawaited(load(_Keychain(const StoredCookies(_stored)), http).then((loaded) => environment = loaded));
        async.flushMicrotasks();
        bool? answer;
        unawaited(environment.didLogin(_page).then((value) => answer = value));
        async.flushMicrotasks();
        unawaited(environment.logout());
        async.elapse(const Duration(seconds: 10));
        expect(answer, isFalse);
        expect(http.to(Canned.navPath), hasLength(1));
        expect(environment.account, isA<LoggedOut>());
      });
    });
  });

  group('logout', () {
    Future<AppEnvironment> loggedIn(FakeKeychain keychain, CannedHttp http, FakeWebCookies web) async {
      final environment = await load(keychain, http, web: web);
      await environment.refreshAccount();
      expect(environment.account, isA<LoggedIn>());
      return environment;
    }

    test('empties the jar, deletes the keychain cookies and app token, clears the web view and reads 未登录', () async {
      final keychain = _Keychain(const StoredCookies(_stored));
      final web = FakeWebCookies()..jar['SESSDATA'] = 'web-sess';
      final environment = await loggedIn(keychain, Canned.http(), web);
      var notified = 0;
      environment.addListener(() => notified += 1);

      await environment.logout();
      expect(environment.cookies.value('SESSDATA'), isNull);
      expect(environment.cookies.value('bili_jct'), isNull);
      expect(keychain.saved.first, isEmpty, reason: 'the emptied jar is written too');
      expect(keychain.deletes, ['cookies', 'app token']);
      expect(web.allClears, 1);
      expect(web.jar, isEmpty);
      expect(environment.account, isA<LoggedOut>());
      expect(environment.accountLabel, '未登录');
      expect((environment.mid, environment.face), (null, null));
      expect(notified, 1);
    });

    test('a step that fails is logged with no values, and the rest still run', () async {
      final keychain = _Keychain(const StoredCookies(_stored))..deleteCookiesError = PlatformException(code: 'keychain');
      final web = FakeWebCookies()..clearAllError = PlatformException(code: 'webkit');
      final environment = await loggedIn(keychain, Canned.http(), web);

      await environment.logout();
      expect(keychain.deletes, ['cookies', 'app token']);
      expect(web.allClears, 1);
      expect(environment.account, isA<LoggedOut>());
      final failed = memory.events.where((event) => event.msg == 'logout step failed');
      expect([for (final event in failed) event.f['step']?.toJson()], ['keychain cookies', 'web data']);
      expect(log(), isNot(contains('stored-sess')));
    });

    test('after a failed keychain read the emptied jar still reaches the keychain', () async {
      final keychain = _Keychain(const CookieLoadFailed(-25308));
      final environment = await load(keychain, Canned.http());
      environment.cookies.set('SESSDATA', 'kept');
      await pumpEventQueue();
      expect(keychain.saved, isEmpty);

      await environment.logout();
      expect(keychain.saved, [isEmpty]);
    });

    test('the fingerprint cookies come back after it, and later checks use them', () async {
      final keychain = _Keychain(const StoredCookies(_stored));
      final http = Canned.http()..routes[_spiPath] = (200, _spi);
      final environment = await loggedIn(keychain, http, FakeWebCookies());

      await environment.logout();
      await pumpEventQueue();
      expect(http.to(_spiPath), hasLength(1));
      expect(environment.cookies.all, {'buvid3': 'B3', 'buvid4': 'B4'});
      expect(keychain.saved.last, {'buvid3': 'B3', 'buvid4': 'B4'});

      http.routes[Canned.navPath] = (200, Canned.navLoggedOut);
      await environment.refreshAccount();
      expect(http.to(_spiPath), hasLength(1));
      expect(http.to(Canned.navPath).last.headers['Cookie'], 'buvid3=B3; buvid4=B4');
      expect(environment.account, isA<LoggedOut>());
    });

    test('a check already on its way doesn\'t bring the account back', () async {
      final http = Canned.http();
      final environment = await load(_Keychain(const StoredCookies(_stored)), http);
      final gate = Completer<void>();
      http.gates[Canned.navPath] = gate;
      final check = environment.refreshAccount();
      await pumpEventQueue();

      await environment.logout();
      gate.complete();
      await check;
      expect(environment.account, isA<LoggedOut>());
      expect(environment.mid, isNull);
      expect(environment.cookies.value('SESSDATA'), isNull);
    });

    test('a --fake-account run just becomes logged out, asking Bilibili and the keychain nothing', () async {
      final keychain = _Keychain(const NoStoredCookies());
      final http = Canned.http();
      final web = FakeWebCookies();
      final environment = await load(keychain, http, web: web);
      environment.useFakeAccount();

      await environment.logout();
      await pumpEventQueue();
      expect(environment.fake, isFalse);
      expect(environment.account, isA<LoggedOut>());
      expect(environment.mid, isNull);
      expect(http.requests, isEmpty);
      expect(keychain.deletes, isEmpty);
      expect(web.allClears, 0);
    });
  });
}
