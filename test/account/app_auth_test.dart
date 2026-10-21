import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/app_auth.dart';
import 'package:bilifast/account/app_auth_page.dart';
import 'package:bilifast/account/app_auth_prompt.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';
import 'fake_web_cookies.dart';

const spiPath = '/x/frontend/finger/spi';
const authCodePath = '/x/passport-tv-login/qrcode/auth_code';
const confirmPath = '/x/passport-tv-login/h5/qrcode/confirm';
const pollPath = '/x/passport-tv-login/qrcode/poll';
const renewPath = '/x/passport-login/oauth2/refresh_token';
const likePath = '/x/v2/view/like';

// Every value is made up; Canned's account is mid 12345.
const authCodeReply =
    '{"code":0,"message":"0","data":{"url":"https://passport.bilibili.com/h5-app/passport/auth/scan?qrcode_id=QRFAKE",'
    '"auth_code":"FAKE-CODE"}}';
const waiting = '{"code":86039,"message":"二维码尚未确认","data":null}';
const confirmed =
    '{"code":0,"message":"0","data":{"mid":12345,"access_token":"NEW-ACCESS","refresh_token":"NEW-REFRESH",'
    '"expires_in":15552000}}';

String reply(int code) => '{"code":$code,"message":"m","ttl":1,"data":null}';

String stored({int days = 100, int mid = 12345}) => jsonEncode(
  AppToken(
    accessToken: 'OLD-ACCESS',
    refreshToken: 'OLD-REFRESH',
    mid: mid,
    expiresAt: DateTime.now().add(Duration(days: days)),
  ).toJson(),
);

/// The keychain's two items: the login's cookies, and the app token as the app wrote it.
class TokenKeychain implements KeychainStore {
  TokenKeychain({this.cookies, this.token});

  final Map<String, String>? cookies;
  String? token;
  Object? loadError;
  int deletes = 0;
  final saves = <String>[];

  /// Holds the login's cookie write, as a slow keychain would.
  Completer<void>? saveGate;

  @override
  Future<CookieLoad> loadCookies() async => cookies == null ? const NoStoredCookies() : StoredCookies(cookies!);

  @override
  Future<bool> saveCookies(Map<String, String> cookies) async {
    await saveGate?.future;
    return true;
  }

  @override
  Future<void> deleteCookies() async {}

  @override
  Future<String?> loadAppToken() async {
    final error = loadError;
    if (error != null) throw error;
    return token;
  }

  @override
  Future<bool> saveAppToken(String token) async {
    saves.add(token);
    this.token = token;
    return true;
  }

  @override
  Future<void> deleteAppToken() async {
    deletes += 1;
    token = null;
  }
}

class Events implements LogSink {
  final lines = <String>[];

  @override
  void receive(LogEvent event) => lines.add(event.encode());
}

class Harness {
  Harness(this.environment, this.auth, this.http, this.keychain, this.pages);

  final AppEnvironment environment;
  final TokenAppAuth auth;
  final CannedHttp http;
  final TokenKeychain keychain;
  final List<Uri> pages;

  BiliClient get client => environment.client;
}

final prompt = find.byKey(const ValueKey('app-auth-prompt'));
final authorize = find.byKey(const ValueKey('settings-confirm-授权'));
final cancel = find.byKey(const ValueKey('settings-confirm-取消'));
final confirmPage = find.text('confirm page');

void main() {
  late BuildContext host;
  late Events events;
  late Logger logger;

  setUp(() {
    events = Events();
    logger = Logger(session: 'test')..add(events);
  });

  Future<Harness> mount(WidgetTester tester, {String? token, bool loggedIn = true}) async {
    final http = Canned.http(loggedIn: loggedIn)
      ..routes[spiPath] = (200, '{"code":0,"message":"ok","data":{"b_3":"B3","b_4":"B4"}}')
      ..routes[authCodePath] = (200, authCodeReply)
      ..routes[confirmPath] = (200, reply(0))
      ..routes[pollPath] = (200, confirmed);
    final keychain = TokenKeychain(cookies: loggedIn ? Canned.cookies : null, token: token);
    final environment = await AppEnvironment.load(
      keychain: keychain,
      http: http,
      webCookies: FakeWebCookies(),
      logger: logger,
    );
    final navigator = GlobalKey<NavigatorState>();
    final pages = <Uri>[];
    final auth = TokenAppAuth(
      environment: environment,
      navigator: navigator,
      devicePath: () => null,
      pollInterval: const Duration(milliseconds: 100),
      pagePollInterval: const Duration(seconds: 1),
      pageTimeout: const Duration(seconds: 10),
      confirmPage: (url, cookies) {
        pages.add(url);
        return MaterialPageRoute<bool>(builder: (_) => const Scaffold(body: Text('confirm page')));
      },
      logger: logger,
    );
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Builder(
          builder: (context) {
            host = context;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );
    return Harness(environment, auth, http, keychain, pages);
  }

  /// The toast's two seconds, so no timer is left when the test ends.
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  }

  void expectNoSecretsLogged() {
    for (final line in events.lines) {
      for (final secret in ['OLD-ACCESS', 'OLD-REFRESH', 'NEW-ACCESS', 'NEW-REFRESH', 'FAKE-CODE', 'QRFAKE']) {
        expect(line, isNot(contains(secret)));
      }
    }
  }

  group('launch', () {
    testWidgets('a stored token not near its end is held, and nothing is sent or asked', (tester) async {
      final h = await mount(tester, token: stored(days: 100));
      await h.auth.start();
      await h.environment.refreshAccount();
      await tester.pumpAndSettle();
      expect(h.auth.authorized, isTrue);
      expect(h.client.appToken?.accessToken, 'OLD-ACCESS');
      expect(h.auth.expiresAt, h.client.appToken?.expiresAt);
      expect(h.http.paths.where((path) => path.contains('passport')), isEmpty);
      expect(prompt, findsNothing);
      expect(h.client.appBuvid, matches(RegExp(r'^XY[0-9A-F]{35}$')));
      expectNoSecretsLogged();
    });

    testWidgets('logged in without a token, the confirm opens once, after the account check', (tester) async {
      final h = await mount(tester);
      await h.auth.start();
      await tester.pumpAndSettle();
      expect(prompt, findsNothing, reason: 'the account is still unknown');

      await h.environment.refreshAccount();
      await tester.pumpAndSettle();
      expect(prompt, findsOneWidget);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(prompt, findsNothing);

      await h.environment.refreshAccount();
      await tester.pumpAndSettle();
      expect(prompt, findsNothing, reason: 'once a launch');
      expect(h.http.to(authCodePath), isEmpty);
    });

    testWidgets('on Windows (no keychain, logged out) it holds nothing, asks nothing and sends nothing', (tester) async {
      final http = CannedHttp()
        ..routes[Canned.navPath] = (200, Canned.navLoggedOut)
        ..routes[spiPath] = (200, '{"code":0,"message":"ok","data":{"b_3":"B3","b_4":"B4"}}');
      final environment = await AppEnvironment.load(
        keychain: const NoKeychainStore(),
        http: http,
        webCookies: FakeWebCookies(),
        logger: logger,
      );
      final navigator = GlobalKey<NavigatorState>();
      final auth = TokenAppAuth(environment: environment, navigator: navigator, devicePath: () => null, logger: logger);
      addTearDown(auth.dispose);
      await tester.pumpWidget(MaterialApp(navigatorKey: navigator, home: const SizedBox.expand()));
      await auth.start();
      await environment.refreshAccount();
      await tester.pumpAndSettle();
      expect(environment.account, isA<LoggedOut>());
      expect(auth.authorized, isFalse);
      expect(prompt, findsNothing);
      expect(http.paths.toSet(), {spiPath, Canned.navPath}, reason: "only the account check's");
      expect(environment.client.appBuvid, matches(RegExp(r'^XY[0-9A-F]{35}$')));
    });

    testWidgets("the Swift app's bare token is deleted and counts as none", (tester) async {
      final h = await mount(tester, token: 'legacy-bare-token');
      await h.auth.start();
      expect(h.keychain.deletes, 1);
      expect(h.keychain.token, isNull);
      expect(h.auth.authorized, isFalse);
      await h.environment.refreshAccount();
      await tester.pumpAndSettle();
      expect(prompt, findsOneWidget);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      for (final line in events.lines) {
        expect(line, isNot(contains('legacy-bare-token')));
      }
    });

    testWidgets('an expired token is dropped and the confirm asked', (tester) async {
      final h = await mount(tester, token: stored(days: -1));
      await h.auth.start();
      expect(h.keychain.deletes, 1);
      expect(h.auth.authorized, isFalse);
      expect(h.http.to(renewPath), isEmpty);
      await h.environment.refreshAccount();
      await tester.pumpAndSettle();
      expect(prompt, findsOneWidget);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
    });

    testWidgets("a token from another account is dropped once the account is known", (tester) async {
      final h = await mount(tester, token: stored(mid: 999));
      await h.auth.start();
      expect(h.auth.authorized, isTrue);
      await h.environment.refreshAccount();
      await tester.pumpAndSettle();
      expect(h.auth.authorized, isFalse);
      expect(h.keychain.deletes, 1);
      expect(prompt, findsOneWidget);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
    });

    testWidgets('within 30 days of its end, one renewal call, and the new token is kept', (tester) async {
      final h = await mount(tester, token: stored(days: 10));
      h.http.routes[renewPath] = (
        200,
        '{"code":0,"message":"0","data":{"status":0,"token_info":{"mid":12345,"access_token":"NEW-ACCESS",'
            '"refresh_token":"NEW-REFRESH","expires_in":15552000},"cookie_info":{"cookies":[]}}}',
      );
      await h.auth.start();
      expect(h.http.to(renewPath), hasLength(1));
      expect(h.client.appToken?.accessToken, 'NEW-ACCESS');
      final kept = AppToken.fromJson(jsonDecode(h.keychain.saves.single));
      expect(kept.accessToken, 'NEW-ACCESS');
      expect(kept.refreshToken, 'NEW-REFRESH');
      expect(kept.expiresAt.difference(DateTime.now()).inDays, inInclusiveRange(178, 180));
      await h.environment.refreshAccount();
      await tester.pumpAndSettle();
      expect(prompt, findsNothing);
      expectNoSecretsLogged();
    });

    testWidgets('a failed renewal keeps the old token and logs only the code', (tester) async {
      final h = await mount(tester, token: stored(days: 10));
      h.http.routes[renewPath] = (200, reply(-400));
      await h.auth.start();
      expect(h.http.to(renewPath), hasLength(1));
      expect(h.client.appToken?.accessToken, 'OLD-ACCESS');
      expect(h.keychain.deletes, 0);
      expect(events.lines.where((line) => line.contains('app token renewal failed')).single, contains('"code":-400'));
      await h.environment.refreshAccount();
      await tester.pumpAndSettle();
      expect(prompt, findsNothing);
      expectNoSecretsLogged();
    });

    testWidgets('a keychain that throws on the read asks nothing at launch', (tester) async {
      final h = await mount(tester);
      h.keychain.loadError = Exception('keychain locked');
      await h.auth.start();
      await h.environment.refreshAccount();
      await tester.pumpAndSettle();
      expect(prompt, findsNothing);
      expect(h.keychain.deletes, 0);
    });
  });

  group('a token that stops working', () {
    testWidgets('a rejected token is dropped and the confirm asked once a launch', (tester) async {
      final h = await mount(tester, token: stored());
      h.http.routes[likePath] = (200, '{"code":-101,"message":"账号未登录"}');
      await h.auth.start();
      await h.environment.refreshAccount();
      await tester.pumpAndSettle();

      var changes = 0;
      h.auth.addListener(() => changes++);
      await expectLater(h.client.officialLike(aid: 1, on: true), throwsA(isA<BiliAPIError>()));
      expect(h.auth.authorized, isFalse);
      expect(changes, greaterThan(0));
      await tester.pumpAndSettle();
      expect(h.keychain.deletes, 1);
      expect(prompt, findsOneWidget);

      await tester.tap(authorize);
      await settle(tester);
      expect(h.client.appToken?.accessToken, 'NEW-ACCESS');

      await expectLater(h.client.officialLike(aid: 1, on: true), throwsA(isA<BiliAPIError>()));
      await tester.pumpAndSettle();
      expect(h.auth.authorized, isFalse);
      expect(h.keychain.deletes, 2);
      expect(prompt, findsNothing, reason: 'asked again once, not every time');
      expectNoSecretsLogged();
    });

    testWidgets('退出登录 clears the token', (tester) async {
      final h = await mount(tester, token: stored());
      await h.auth.start();
      await h.environment.refreshAccount();
      await tester.pumpAndSettle();
      var changes = 0;
      h.auth.addListener(() => changes++);
      await h.environment.logout();
      await tester.pumpAndSettle();
      expect(h.client.appToken, isNull);
      expect(h.auth.authorized, isFalse);
      expect(changes, greaterThan(0));
      expect(h.keychain.token, isNull);
      expect(prompt, findsNothing);
    });

    testWidgets('a new login without a token asks once', (tester) async {
      final h = await mount(tester, loggedIn: false);
      await h.auth.start();
      await h.environment.refreshAccount();
      await tester.pumpAndSettle();
      expect(prompt, findsNothing);

      h.http.routes[Canned.navPath] = (200, Canned.navLoggedIn);
      expect(await h.environment.didLogin(Canned.cookies), isTrue);
      await tester.pumpAndSettle();
      expect(prompt, findsOneWidget);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(prompt, findsNothing);
    });

    testWidgets("a login reading logged in while its page is up asks only once the page has closed", (tester) async {
      final h = await mount(tester, loggedIn: false);
      await h.auth.start();
      await h.environment.refreshAccount();
      await tester.pumpAndSettle();
      late BuildContext loginPage;
      unawaited(
        Navigator.of(host).push(
          MaterialPageRoute<bool>(
            builder: (context) {
              loginPage = context;
              return const Scaffold(body: Text('login page'));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      h.http.routes[Canned.navPath] = (200, Canned.navLoggedIn);
      final gate = h.keychain.saveGate = Completer<void>();
      final login = h.environment.didLogin(Canned.cookies);
      await tester.pumpAndSettle();
      expect(h.environment.account, isA<LoggedIn>());
      expect(prompt, findsNothing, reason: 'the login page would close the confirm instead of itself');

      gate.complete();
      // As LoginFlow does: the page pops itself once the login lands.
      unawaited(
        login.then((loggedIn) {
          if (loggedIn) Navigator.of(loginPage).pop(true);
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('login page'), findsNothing);
      expect(prompt, findsOneWidget);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(prompt, findsNothing);
    });
  });

  group('the confirm', () {
    testWidgets('a pop from elsewhere is no 授权', (tester) async {
      await mount(tester);
      final answer = showAppAuthPrompt(host);
      await tester.pumpAndSettle();
      expect(prompt, findsOneWidget);
      Navigator.of(host).pop(true);
      await tester.pumpAndSettle();
      expect(await answer, isFalse);
    });

    testWidgets('its dim is 取消, and 授权 answers true', (tester) async {
      await mount(tester);
      final dimmed = showAppAuthPrompt(host);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(await dimmed, isFalse);

      final pressed = showAppAuthPrompt(host);
      await tester.pumpAndSettle();
      await tester.tap(authorize);
      await tester.pumpAndSettle();
      expect(await pressed, isTrue);
    });
  });

  group('the confirm page', () {
    testWidgets('on the PC it says to confirm on the phone, and ✕ closes it answering false', (tester) async {
      await mount(tester);
      final closed = Navigator.of(host).push(AppAuthPage.route(Uri.parse('https://passport.bilibili.com/x'), {}));
      await tester.pumpAndSettle();
      expect(find.text('授权官方接口'), findsOneWidget);
      expect(find.text('请在手机上授权'), findsOneWidget);

      // As ghosthand presses it on the PC.
      final semantics = tester.ensureSemantics();
      tester.semantics.tap(find.semantics.byLabel('关闭'));
      await tester.pumpAndSettle();
      semantics.dispose();
      expect(await closed, isFalse);
      expect(find.byType(AppAuthPage), findsNothing);
    });
  });

  group('request', () {
    testWidgets('授权 confirms with the web login, polls, keeps the token and toasts', (tester) async {
      final h = await mount(tester);
      await h.environment.refreshAccount();
      final answer = h.auth.request(host);
      await tester.pumpAndSettle();
      expect(find.text(AppAuthPromptRoute.title), findsOneWidget);
      expect(find.text(AppAuthPromptRoute.message), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('授权'), findsOneWidget);
      expect(h.http.requests, hasLength(1), reason: 'only the account check before 授权');

      await tester.tap(authorize);
      await tester.pump();
      await tester.pump();
      expect(find.text('授权成功'), findsOneWidget);
      expect(await answer, isTrue);
      expect(h.auth.authorized, isTrue);
      expect(h.client.appToken?.accessToken, 'NEW-ACCESS');
      expect(jsonDecode(h.keychain.saves.single), h.client.appToken?.toJson());
      expect(h.http.paths.skip(1), [authCodePath, confirmPath, pollPath]);
      final confirm = h.http.to(confirmPath).single;
      expect(utf8.decode(confirm.body!), 'auth_code=FAKE-CODE&csrf=j');
      expect(confirm.headers['Cookie'], contains('SESSDATA=s'));
      expect(h.pages, isEmpty);
      await settle(tester);
      expectNoSecretsLogged();
    });

    testWidgets('取消 sends nothing and answers false', (tester) async {
      final h = await mount(tester);
      await h.environment.refreshAccount();
      final answer = h.auth.request(host);
      await tester.pumpAndSettle();
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(await answer, isFalse);
      expect(h.http.to(authCodePath), isEmpty);
    });

    testWidgets('logged out it answers false without asking', (tester) async {
      final h = await mount(tester, loggedIn: false);
      await h.environment.refreshAccount();
      expect(await h.auth.request(host), isFalse);
      await tester.pumpAndSettle();
      expect(prompt, findsNothing);
    });

    testWidgets('a second caller gets the request already up', (tester) async {
      final h = await mount(tester);
      await h.environment.refreshAccount();
      final first = h.auth.request(host);
      final second = h.auth.request(host);
      final third = h.auth.reauthorize(host);
      expect(identical(first, second), isTrue);
      expect(identical(first, third), isTrue);
      await tester.pumpAndSettle();
      expect(prompt, findsOneWidget);
      await tester.tap(authorize);
      await settle(tester);
      expect(await first, isTrue);
      expect(h.http.to(authCodePath), hasLength(1));
    });

    testWidgets('a refused confirm opens the page, polls while it is up, and closes it with the token', (tester) async {
      final h = await mount(tester);
      h.http.routes[confirmPath] = (200, '{"code":86096,"message":"请使用最新版本扫码登录"}');
      h.http.routes[pollPath] = (200, waiting);
      await h.environment.refreshAccount();
      final answer = h.auth.request(host);
      await tester.pumpAndSettle();
      await tester.tap(authorize);
      await tester.pumpAndSettle();
      expect(confirmPage, findsOneWidget);
      expect(h.pages.single.toString(), startsWith('https://passport.bilibili.com/h5-app/passport/auth/scan'));

      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(h.http.to(pollPath), hasLength(2));
      expect(h.auth.authorized, isFalse);

      h.http.routes[pollPath] = (200, confirmed);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(confirmPage, findsNothing);
      expect(await answer, isTrue);
      expect(h.client.appToken?.accessToken, 'NEW-ACCESS');
      expect(find.text('授权成功'), findsOneWidget);
      await settle(tester);
      expectNoSecretsLogged();
    });

    testWidgets('closing the page stops the polls and answers false', (tester) async {
      final h = await mount(tester);
      h.http.routes[confirmPath] = (200, '{"code":-403,"message":"访问权限不足"}');
      h.http.routes[pollPath] = (200, waiting);
      await h.environment.refreshAccount();
      final answer = h.auth.request(host);
      await tester.pumpAndSettle();
      await tester.tap(authorize);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      final polled = h.http.to(pollPath).length;

      Navigator.of(tester.element(confirmPage)).pop(false);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      expect(await answer, isFalse);
      expect(h.http.to(pollPath).length, lessThanOrEqualTo(polled + 1));
      expect(find.textContaining('授权失败'), findsNothing);
    });

    testWidgets('a page left up past its time closes with 授权失败', (tester) async {
      final h = await mount(tester);
      h.http.routes[confirmPath] = (200, '{"code":-403,"message":"访问权限不足"}');
      h.http.routes[pollPath] = (200, waiting);
      await h.environment.refreshAccount();
      final answer = h.auth.request(host);
      await tester.pumpAndSettle();
      await tester.tap(authorize);
      await tester.pumpAndSettle();
      for (var second = 0; second < 10; second++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pumpAndSettle();
      expect(h.http.to(pollPath), hasLength(10));
      expect(confirmPage, findsNothing);
      expect(await answer, isFalse);
      expect(find.text('授权失败：请稍后重试'), findsOneWidget);
      await settle(tester);
    });

    testWidgets('a confirm the poll never sees stops after a few polls with 授权失败', (tester) async {
      final h = await mount(tester);
      h.http.routes[pollPath] = (200, waiting);
      await h.environment.refreshAccount();
      final answer = h.auth.request(host);
      await tester.pumpAndSettle();
      await tester.tap(authorize);
      for (var poll = 0; poll < 10; poll++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(await answer, isFalse);
      expect(h.http.to(pollPath), hasLength(TokenAppAuth.quickPolls));
      expect(h.pages, isEmpty);
      await tester.pump();
      expect(find.text('授权失败：请稍后重试'), findsOneWidget);
      await settle(tester);
    });

    testWidgets('a failed code request toasts its reason', (tester) async {
      final h = await mount(tester);
      h.http.routes[authCodePath] = (200, '{"code":-3,"message":"API校验密匙错误"}');
      await h.environment.refreshAccount();
      final answer = h.auth.request(host);
      await tester.pumpAndSettle();
      await tester.tap(authorize);
      await tester.pumpAndSettle();
      expect(await answer, isFalse);
      expect(find.text('授权失败：B 站返回错误 -3：API校验密匙错误'), findsOneWidget);
      await settle(tester);
    });

    testWidgets('重新授权 drops the token, then asks', (tester) async {
      final h = await mount(tester, token: stored());
      await h.auth.start();
      await h.environment.refreshAccount();
      await tester.pumpAndSettle();
      final answer = h.auth.reauthorize(host);
      expect(h.auth.authorized, isFalse);
      await tester.pumpAndSettle();
      expect(h.keychain.deletes, 1);
      await tester.tap(authorize);
      await settle(tester);
      expect(await answer, isTrue);
      expect(h.client.appToken?.accessToken, 'NEW-ACCESS');
    });
  });

  group('device id', () {
    test("has PiliPlus's buvid shape", () {
      final id = TokenAppAuth.newBuvid(Random(1));
      expect(id, matches(RegExp(r'^XY[0-9A-F]{35}$')));
      final hex = id.substring(5);
      expect(id.substring(2, 5), '${hex[2]}${hex[12]}${hex[22]}');
    });

    test('is made once and kept in its file', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final folder = await Directory.systemTemp.createTemp('app_auth_test');
      addTearDown(() => folder.delete(recursive: true));
      final path = '${folder.path}${Platform.pathSeparator}app_device.json';
      Future<String?> launch() async {
        final environment = await AppEnvironment.load(
          keychain: const NoKeychainStore(),
          http: CannedHttp(),
          webCookies: FakeWebCookies(),
          logger: logger,
        );
        final auth = TokenAppAuth(
          environment: environment,
          navigator: GlobalKey<NavigatorState>(),
          devicePath: () => path,
          logger: logger,
        );
        await auth.start();
        auth.dispose();
        return environment.client.appBuvid;
      }

      final first = await launch();
      expect(first, matches(RegExp(r'^XY[0-9A-F]{35}$')));
      expect(await launch(), first);
      expect(jsonDecode(await File(path).readAsString()), {'buvid': first});
      for (final line in events.lines) {
        expect(line, isNot(contains(first!)));
      }
    });
  });
}
