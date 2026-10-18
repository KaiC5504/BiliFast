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

  test('checks asked for while one is running share its request; a later one asks again', () async {
    final http = Canned.http();
    final environment = await load(FakeKeychain(const StoredCookies(Canned.cookies)), http);
    final answers = await Future.wait([environment.refreshAccount(), environment.refreshAccount()]);
    expect(answers, [true, true]);
    expect(http.to(Canned.navPath), hasLength(1));
    await environment.refreshAccount();
    expect(http.to(Canned.navPath), hasLength(2));
  });
}
