import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';
import 'fake_keychain.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppEnvironment> load(FakeKeychain keychain, CannedHttp http) =>
      AppEnvironment.load(keychain: keychain, http: http, logger: Logger(session: 'test'));

  test('the stored keychain login gives the account name, with no login screen', () async {
    final keychain = FakeKeychain(const StoredCookies(Canned.cookies));
    final http = Canned.http();
    final environment = await load(keychain, http);
    expect(environment.accountLabel, '正在确认账号…');

    expect(await environment.refreshAccount(), isTrue);
    expect(environment.accountLabel, '测试用户');
    expect(environment.account, isA<LoggedIn>().having((account) => account.vip, 'vip', isTrue));
    expect(environment.mid, 12345);
    expect(http.to(Canned.navPath).single.headers['Cookie'], contains('SESSDATA=s'));
    expect(keychain.saved, isEmpty, reason: 'nothing changed in the jar');
  });

  test('no stored login reads 未登录', () async {
    final environment = await load(FakeKeychain(const NoStoredCookies()), Canned.http(loggedIn: false)
      ..routes['/x/frontend/finger/spi'] = (200, '{"code":0,"message":"ok","data":{"b_3":"B3","b_4":"B4"}}'));
    await environment.refreshAccount();
    expect(environment.account, isA<LoggedOut>());
    expect(environment.accountLabel, '未登录');
  });

  test('cookies Bilibili no longer accepts read as expired', () async {
    final environment = await load(FakeKeychain(const StoredCookies(Canned.cookies)), Canned.http(loggedIn: false));
    await environment.refreshAccount();
    expect(environment.account, isA<LoginExpired>());
  });

  test('jar changes are written back to the keychain', () async {
    final keychain = FakeKeychain(const StoredCookies(Canned.cookies));
    final environment = await load(keychain, Canned.http());
    environment.cookies.set('buvid3', 'new');
    await Future<void>.delayed(Duration.zero);
    expect(keychain.saved.single['buvid3'], 'new');
    expect(keychain.saved.single['SESSDATA'], 's');
  });

  test('after a failed keychain read nothing is written until a read works', () async {
    final keychain = FakeKeychain(const CookieLoadFailed(-25308));
    final environment = await load(keychain, Canned.http());
    environment.cookies.set('buvid3', 'b3');
    environment.cookies.set('buvid4', 'b4');
    await Future<void>.delayed(Duration.zero);
    expect(keychain.saved, isEmpty);

    keychain.next = const StoredCookies({'SESSDATA': 'kept'});
    await environment.refreshAccount();
    expect(environment.cookies.value('SESSDATA'), 'kept');
    expect(environment.cookies.value('buvid3'), 'b3');
    expect(keychain.saved.last, {'SESSDATA': 'kept', 'buvid3': 'b3', 'buvid4': 'b4'});
  });

  test('a keychain still unreadable when Bilibili says logged out leaves the account unknown, not 未登录', () async {
    final keychain = FakeKeychain(const CookieLoadFailed(-25308));
    // The jar starts without buvids, so the risk cookies are fetched first.
    final http = Canned.http(loggedIn: false)
      ..routes['/x/frontend/finger/spi'] = (200, '{"code":0,"message":"ok","data":{"b_3":"B3","b_4":"B4"}}');
    final environment = await load(keychain, http);

    expect(await environment.refreshAccount(), isTrue);
    expect(environment.account, isA<AccountUnknown>());
    expect(environment.accountCheckFailed, isTrue);

    // Coming back to the app asks again; by then the keychain reads.
    keychain.next = const StoredCookies(Canned.cookies);
    http.routes[Canned.navPath] = (200, Canned.navLoggedIn);
    await environment.refreshAccount();
    expect(environment.account, isA<LoggedIn>());
    expect(environment.cookies.value('SESSDATA'), Canned.cookies['SESSDATA']);
  });

  test('a keychain still unreadable when nav fails leaves the account unknown too', () async {
    final keychain = FakeKeychain(const CookieLoadFailed(-25308));
    final http = Canned.http()..routes.remove(Canned.navPath);
    final environment = await load(keychain, http);

    expect(await environment.refreshAccount(), isFalse);
    expect(environment.account, isA<AccountUnknown>());
    expect(environment.accountCheckFailed, isTrue);
  });

  test('a keychain channel that throws counts as a failed read', () async {
    final keychain = FakeKeychain(const StoredCookies(Canned.cookies))
      ..throws = PlatformException(code: 'unavailable');
    final environment = await load(keychain, Canned.http());
    environment.cookies.set('buvid3', 'b3');
    await Future<void>.delayed(Duration.zero);
    expect(keychain.saved, isEmpty);
  });

  test('a URLSession transport that throws while building falls back to dart:io with an error logged', () async {
    final logger = Logger(session: 'test');
    final memory = MemorySink();
    logger.add(memory);
    final transport = httpTransportOrFallback(() => throw StateError('no native bindings'), logger);
    expect(transport, isA<ClientHTTPTransport>());
    final event = memory.events.single;
    expect((event.level, event.msg), (LogLevel.error, 'http transport failed, using dart:io'));

    final environment = await AppEnvironment.load(
        keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
        httpFactory: () => throw StateError('no native bindings'),
        logger: logger);
    expect(environment.cookies.value('SESSDATA'), 's');
  });

  test('a network failure with cookies keeps the account unknown', () async {
    final http = Canned.http()..routes[Canned.navPath] = (502, '');
    final environment = await load(FakeKeychain(const StoredCookies(Canned.cookies)), http);
    expect(await environment.refreshAccount(), isFalse);
    expect(environment.account, isA<AccountUnknown>());
    expect(environment.accountLabel, '账号确认失败');
  });

  test('a --fake-account run is 测试账号 with mid 1, and its account checks ask Bilibili nothing', () async {
    final http = Canned.http();
    final environment = await load(FakeKeychain(const StoredCookies(Canned.cookies)), http);
    var notified = 0;
    environment.addListener(() => notified += 1);
    environment.useFakeAccount();
    expect(environment.fake, isTrue);
    expect(notified, 1);

    expect(await environment.refreshAccount(), isTrue);
    expect(http.requests, isEmpty);
    expect(environment.account, isA<LoggedIn>().having((account) => account.name, 'name', '测试账号'));
    expect(environment.mid, 1);
    expect(environment.accountLabel, '测试账号');
  });

  group('guarded (Windows)', () {
    const likePath = '/x/web-interface/archive/like';
    const logoutPath = '/login/exit/v2';
    const ok = (200, '{"code":0,"message":"0"}');

    test("a write is refused before it is sent, reads go, and the website's logout is let through", () async {
      final http = Canned.http()
        ..routes[likePath] = ok
        ..routes[logoutPath] = ok;
      final environment = await AppEnvironment.load(
          keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
          http: http,
          guarded: true,
          logger: Logger(session: 'test'));

      await expectLater(environment.client.like(aid: 1, bvid: 'BV1GJ411x7h7', on: true),
          throwsA(const BiliAPIError(code: GuardedTransport.readOnlyCode, message: 'PC 只读，未发送')));
      expect(http.to(likePath), isEmpty);
      expect(await environment.refreshAccount(), isTrue);
      expect(environment.account, isA<LoggedIn>());
      await environment.client.postVoid(logoutPath, host: BiliClient.passport);
      expect(http.to(logoutPath).single.url.host, 'passport.bilibili.com');
    });

    test('unguarded (the phone), writes go out as before', () async {
      final http = Canned.http()..routes[likePath] = ok;
      final environment = await load(FakeKeychain(const StoredCookies(Canned.cookies)), http);
      await environment.client.like(aid: 1, bvid: 'BV1GJ411x7h7', on: true);
      expect(http.to(likePath).single.method, 'POST');
    });
  });

  test('checks asked for while one is running share its request; a later one asks again', () async {
    final http = Canned.http();
    final environment = await load(FakeKeychain(const StoredCookies(Canned.cookies)), http);
    final answers = await Future.wait([environment.refreshAccount(), environment.refreshAccount()]);
    expect(answers, [true, true]);
    expect(http.to(Canned.navPath), hasLength(1));
    await environment.refreshAccount();
    expect(http.to(Canned.navPath), hasLength(2));
  });

  test('launch asks nav once: 首页\'s search word, signed with the WBI keys, shares the account check\'s', () async {
    const searchDefaultPath = '/x/web-interface/wbi/search/default';
    final http = Canned.http()
      ..routes[searchDefaultPath] = (200, '{"code":0,"message":"0","data":{"show_name":"默认词"}}')
      ..gates[Canned.navPath] = Completer<void>();
    final environment = await load(FakeKeychain(const StoredCookies(Canned.cookies)), http);
    final check = environment.refreshAccount();
    final word = environment.client.searchDefaultWord();
    await pumpEventQueue();
    http.gates[Canned.navPath]!.complete();
    expect(await check, isTrue);
    expect(await word, '默认词');
    expect(http.to(Canned.navPath), hasLength(1));
    expect(http.to(searchDefaultPath), hasLength(1));
  });

  test('the check keeps its logged-in nav and when it came, until the account changes', () async {
    final http = Canned.http();
    final environment = await load(FakeKeychain(const StoredCookies(Canned.cookies)), http);
    expect(environment.accountNav, isNull);
    final before = DateTime.now();
    await environment.refreshAccount();
    final answer = environment.accountNav!;
    expect(answer.nav.mid, 12345);
    expect(answer.at.isBefore(before), isFalse);

    http.routes[Canned.navPath] = (200, Canned.navLoggedOut);
    await environment.refreshAccount();
    expect(environment.account, isA<LoginExpired>());
    expect(environment.accountNav, isNull);

    http.routes[Canned.navPath] = (200, Canned.navLoggedIn);
    await environment.refreshAccount();
    expect(environment.accountNav, isNotNull);
    await environment.logout();
    expect(environment.accountNav, isNull);
  });
}
