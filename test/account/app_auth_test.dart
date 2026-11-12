import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/app_auth.dart';
import 'package:bilifast/account/app_auth_prompt.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';
import 'fake_web_cookies.dart';

const spiPath = '/x/frontend/finger/spi';
const authCodePath = '/x/passport-tv-login/qrcode/auth_code';
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

const renewed =
    '{"code":0,"message":"0","data":{"status":0,"token_info":{"mid":12345,"access_token":"NEW-ACCESS",'
    '"refresh_token":"NEW-REFRESH","expires_in":15552000},"cookie_info":{"cookies":[]}}}';

String stored({int days = 100, int mid = 12345, OfficialIdentity identity = OfficialIdentity.android}) => jsonEncode(
  AppToken(
    accessToken: 'OLD-ACCESS',
    refreshToken: 'OLD-REFRESH',
    mid: mid,
    expiresAt: DateTime.now().add(Duration(days: days)),
    identity: identity,
  ).toJson(),
);

/// A token as the builds before identities wrote it, with no `identity` field.
String storedBeforeIdentities({int days = 100}) =>
    jsonEncode((jsonDecode(stored(days: days)) as Map<String, Object?>)..remove('identity'));

// A made-up vendor id, and the iPhone-form device id its MD5 gives.
const vendorId = 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE';
const vendorBuvid = 'Y8E3D38DE1B0CE50E090BA2DF2394133AE23';

final androidBuvid = RegExp(r'^XY[0-9A-F]{35}$');
final iphoneBuvid = RegExp(r'^Y[0-9A-F]{35}$');

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

  /// Whether the official app opens; when it does, the user is back at once.
  bool clientInstalled = true;

  final AppEnvironment environment;
  final TokenAppAuth auth;
  final CannedHttp http;
  final TokenKeychain keychain;
  /// The confirm pages opened in the official app.
  final List<Uri> pages;

  BiliClient get client => environment.client;
}

final prompt = find.byKey(const ValueKey('app-auth-prompt'));
final authorize = find.byKey(const ValueKey('settings-confirm-授权'));
final cancel = find.byKey(const ValueKey('settings-confirm-取消'));

void main() {
  late BuildContext host;
  late Events events;
  late Logger logger;

  setUp(() {
    events = Events();
    logger = Logger(session: 'test')..add(events);
  });

  Future<Harness> mount(
    WidgetTester tester, {
    String? token,
    bool loggedIn = true,
    String? devicePath,
    Future<bool> Function(BuildContext context)? confirm,
    bool isIOS = false,
    Future<String?> Function()? idfv,
  }) async {
    final http = Canned.http(loggedIn: loggedIn)
      ..routes[spiPath] = (200, '{"code":0,"message":"ok","data":{"b_3":"B3","b_4":"B4"}}')
      ..routes[authCodePath] = (200, authCodeReply)
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
    late final Harness harness;
    final auth = TokenAppAuth(
      environment: environment,
      navigator: navigator,
      confirm: confirm ?? showAppAuthPrompt,
      devicePath: () => devicePath,
      isIOS: isIOS,
      idfv: idfv ?? () async => vendorId,
      pollInterval: const Duration(milliseconds: 100),
      confirmInClient: (page) async {
        if (!harness.clientInstalled) return false;
        pages.add(page);
        return true;
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
    return harness = Harness(environment, auth, http, keychain, pages);
  }

  /// The toast's two seconds, so no timer is left when the test ends.
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  }

  /// Neither the tokens, the code, the vendor id nor a device id, [deviceIds] being the ones a test's launch made.
  void expectNoSecretsLogged([Iterable<Object?> deviceIds = const []]) {
    final secrets = [
      ...['OLD-ACCESS', 'OLD-REFRESH', 'NEW-ACCESS', 'NEW-REFRESH', 'FAKE-CODE', 'QRFAKE', vendorId, vendorBuvid],
      ...deviceIds.whereType<String>(),
    ];
    for (final line in events.lines) {
      for (final secret in secrets) {
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
      // The renewal runs off the launch's path, which only waits for the stored token.
      expect(h.client.appToken?.accessToken, 'OLD-ACCESS');
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
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
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
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

    testWidgets('a renewal Bilibili rejects drops the token, and the confirm is asked once the account is known',
        (tester) async {
      final h = await mount(tester, token: stored(days: 10));
      h.http.routes[renewPath] = (200, '{"code":-101,"message":"账号未登录"}');
      await h.auth.start();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(h.http.to(renewPath), hasLength(1));
      expect(h.auth.authorized, isFalse);
      expect(h.keychain.deletes, 1);
      expect(h.keychain.saves, isEmpty);
      expect(prompt, findsNothing, reason: 'the account is still unknown');

      await h.environment.refreshAccount();
      await tester.pumpAndSettle();
      expect(prompt, findsOneWidget);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expectNoSecretsLogged();
    });

    testWidgets('a logout while the renewal is out neither holds nor saves the renewed token', (tester) async {
      final h = await mount(tester, token: stored(days: 10));
      h.http.routes[renewPath] = (200, renewed);
      final renewal = h.http.gates[renewPath] = Completer<void>();
      await h.auth.start();
      await h.environment.refreshAccount();
      await tester.pumpAndSettle();
      expect(h.http.to(renewPath), hasLength(1));

      await h.environment.logout();
      renewal.complete();
      await tester.pumpAndSettle();
      expect(h.client.appToken, isNull);
      expect(h.auth.authorized, isFalse);
      expect(h.keychain.saves, isEmpty);
      expect(h.keychain.token, isNull);
      expectNoSecretsLogged();
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

    testWidgets('a rejection that comes back after the renewal leaves the renewed token', (tester) async {
      final h = await mount(tester, token: stored(days: 10));
      h.http.routes[renewPath] = (200, renewed);
      h.http.routes[likePath] = (200, '{"code":-101,"message":"账号未登录"}');
      final renewal = h.http.gates[renewPath] = Completer<void>();
      final like = h.http.gates[likePath] = Completer<void>();
      await h.auth.start();
      await h.environment.refreshAccount();
      await tester.pumpAndSettle();

      final call = h.client.officialLike(aid: 1, on: true);
      await tester.pump();
      expect(h.http.to(likePath), hasLength(1), reason: 'signed with the old token');
      renewal.complete();
      await tester.pumpAndSettle();
      expect(h.client.appToken?.accessToken, 'NEW-ACCESS');

      like.complete();
      await expectLater(call, throwsA(isA<BiliAPIError>()));
      await tester.pumpAndSettle();
      expect(h.client.appToken?.accessToken, 'NEW-ACCESS');
      expect(h.keychain.deletes, 0);
      expect(prompt, findsNothing);
      expectNoSecretsLogged();
    });

    testWidgets("another account's login whose checks failed drops the token once a check reads it", (tester) async {
      final h = await mount(tester, token: stored());
      await h.auth.start();
      await h.environment.refreshAccount();
      await tester.pumpAndSettle();
      expect(h.auth.authorized, isTrue);

      h.http.errors[Canned.navPath] = Exception('offline');
      final login = h.environment.didLogin({'SESSDATA': 'other', 'bili_jct': 'other'});
      for (var second = 0; second < 4; second++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(await login, isFalse);
      expect(h.environment.account, isA<AccountUnknown>());
      expect(h.auth.authorized, isTrue, reason: 'whose login it is is not known yet');

      h.http.errors.remove(Canned.navPath);
      h.http.routes[Canned.navPath] = (200, Canned.navLoggedIn.replaceFirst('"mid":12345', '"mid":67890'));
      await h.environment.refreshAccount();
      await tester.pumpAndSettle();
      expect(h.environment.mid, 67890);
      expect(h.auth.authorized, isFalse);
      expect(h.keychain.deletes, 1);
      expect(h.keychain.token, isNull);
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

  group('request', () {
    testWidgets('授权 opens the confirm page in the official app, polls on return, keeps the token and toasts', (
      tester,
    ) async {
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
      expect(h.http.paths.skip(1), [authCodePath, pollPath]);
      expect(h.pages.single.toString(), 'https://passport.bilibili.com/h5-app/passport/auth/scan?qrcode_id=QRFAKE');
      for (final call in h.http.to(authCodePath).followedBy(h.http.to(pollPath))) {
        expect(call.headers['Cookie'], isNull, reason: 'the TV login is signed, never sent the web login');
      }
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

    testWidgets('a logout while the confirm is out discards the token unsaved', (tester) async {
      final h = await mount(tester);
      await h.environment.refreshAccount();
      final poll = h.http.gates[pollPath] = Completer<void>();
      final answer = h.auth.request(host);
      await tester.pumpAndSettle();
      await tester.tap(authorize);
      await tester.pumpAndSettle();
      expect(h.http.to(pollPath), hasLength(1));

      await h.environment.logout();
      poll.complete();
      await tester.pumpAndSettle();
      expect(await answer, isFalse);
      expect(h.client.appToken, isNull);
      expect(h.keychain.saves, isEmpty);
      expect(find.text('授权成功'), findsNothing);
      expect(events.lines.where((line) => line.contains('app auth discarded')), hasLength(1));
      await settle(tester);
      expectNoSecretsLogged();
    });

    testWidgets('a token confirmed for another account is discarded unsaved', (tester) async {
      final h = await mount(tester);
      h.http.routes[pollPath] = (200, confirmed.replaceFirst('"mid":12345', '"mid":67890'));
      await h.environment.refreshAccount();
      final answer = h.auth.request(host);
      await tester.pumpAndSettle();
      await tester.tap(authorize);
      await tester.pumpAndSettle();
      expect(await answer, isFalse);
      expect(h.client.appToken, isNull);
      expect(h.keychain.saves, isEmpty);
      await settle(tester);
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

    testWidgets('without the official app nothing is polled and the toast says to install it', (tester) async {
      final h = await mount(tester)..clientInstalled = false;
      await h.environment.refreshAccount();
      final answer = h.auth.request(host);
      await tester.pumpAndSettle();
      await tester.tap(authorize);
      await tester.pumpAndSettle();
      expect(await answer, isFalse);
      expect(h.http.to(pollPath), isEmpty);
      expect(find.text('授权失败：请先安装哔哩哔哩客户端'), findsOneWidget);
      await settle(tester);
      expectNoSecretsLogged();
    });

    testWidgets('a code that ran out while the user was away toasts 确认已超时', (tester) async {
      final h = await mount(tester);
      h.http.routes[pollPath] = (200, '{"code":86038,"message":"二维码已失效","data":null}');
      await h.environment.refreshAccount();
      final answer = h.auth.request(host);
      await tester.pumpAndSettle();
      await tester.tap(authorize);
      await tester.pumpAndSettle();
      expect(await answer, isFalse);
      expect(h.http.to(pollPath), hasLength(1));
      expect(find.text('授权失败：确认已超时，请重试'), findsOneWidget);
      await settle(tester);
    });

    testWidgets('back without confirming: a few polls, then 授权失败', (tester) async {
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
      await tester.pump();
      expect(find.text('授权失败：未在哔哩哔哩中确认'), findsOneWidget);
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

    testWidgets('重新授权 asks again and keeps the held token in use until the new one comes', (tester) async {
      final h = await mount(tester, token: stored());
      await h.auth.start();
      await h.environment.refreshAccount();
      await tester.pumpAndSettle();
      final poll = h.http.gates[pollPath] = Completer<void>();
      final answer = h.auth.reauthorize(host);
      await tester.pumpAndSettle();
      expect(prompt, findsOneWidget);
      expect(h.client.appToken?.accessToken, 'OLD-ACCESS');
      await tester.tap(authorize);
      await tester.pumpAndSettle();
      expect(h.http.to(pollPath), hasLength(1));
      expect(h.client.appToken?.accessToken, 'OLD-ACCESS', reason: 'the only token that works so far');
      expect(h.keychain.saves, isEmpty);

      poll.complete();
      await settle(tester);
      expect(await answer, isTrue);
      expect(h.client.appToken?.accessToken, 'NEW-ACCESS');
      expect(jsonDecode(h.keychain.saves.single), h.client.appToken?.toJson());
      expect(h.keychain.deletes, 0, reason: 'written over, so no moment without a token');
      expectNoSecretsLogged();
    });

    testWidgets('a 重新授权 that fails leaves the held token as it was', (tester) async {
      final h = await mount(tester, token: stored());
      h.http.routes[pollPath] = (200, '{"code":86038,"message":"二维码已失效","data":null}');
      await h.auth.start();
      await h.environment.refreshAccount();
      await tester.pumpAndSettle();
      final answer = h.auth.reauthorize(host);
      await tester.pumpAndSettle();
      await tester.tap(authorize);
      await tester.pumpAndSettle();
      expect(await answer, isTrue, reason: 'a token is still held');
      expect(find.text('授权失败：确认已超时，请重试'), findsOneWidget);
      expect(h.client.appToken?.accessToken, 'OLD-ACCESS');
      expect(h.keychain.token, isNotNull);
      expect(h.keychain.saves, isEmpty);
      expect(h.keychain.deletes, 0);
      await settle(tester);
    });
  });

  group('identity', () {
    testWidgets("on iOS a new login is the iPhone app's, and iOS's vendor id is read for the reports", (tester) async {
      final h = await mount(tester, isIOS: true);
      await h.auth.start();
      expect(h.client.loginIdentity, OfficialIdentity.iphone);
      expect(h.client.officialIdentity, OfficialIdentity.iphone);
      expect(h.client.appIdfv, vendorId);
      expect(h.auth.identity, isNull, reason: 'no token yet');
      expectNoSecretsLogged();
    });

    testWidgets("elsewhere it is the Android app's, and no vendor id is asked for", (tester) async {
      var asked = 0;
      final h = await mount(
        tester,
        idfv: () async {
          asked += 1;
          return vendorId;
        },
      );
      await h.auth.start();
      expect(h.client.loginIdentity, OfficialIdentity.android);
      expect(h.client.officialIdentity, OfficialIdentity.android);
      expect(h.client.appIdfv, isNull);
      expect(asked, 0);
    });

    testWidgets("on iOS a token stored before identities existed stays the Android app's: nothing is asked, sent or "
        'written', (tester) async {
      final legacy = storedBeforeIdentities();
      final h = await mount(tester, token: legacy, isIOS: true);
      await h.auth.start();
      await h.environment.refreshAccount();
      await tester.pumpAndSettle();
      expect(h.auth.authorized, isTrue);
      expect(h.auth.identity, OfficialIdentity.android);
      expect(h.client.loginIdentity, OfficialIdentity.iphone);
      expect(h.client.officialIdentity, OfficialIdentity.android, reason: "calls go out as the token's app");
      expect(h.client.appToken?.accessToken, 'OLD-ACCESS');
      expect(h.client.appBuvid, matches(androidBuvid));
      expect(prompt, findsNothing);
      expect(h.http.paths.where((path) => path.contains('passport')), isEmpty);
      expect(h.keychain.token, legacy);
      expect(h.keychain.saves, isEmpty);
      expect(h.keychain.deletes, 0);
      expectNoSecretsLogged([h.client.appBuvid]);
    });

    /// Launches with [token] due for renewal and answers the renewal; the token's JSON as it was kept.
    Future<Map<String, Object?>> renew(WidgetTester tester, String token, {required bool isIOS}) async {
      final h = await mount(tester, token: token, isIOS: isIOS);
      h.http.routes[renewPath] = (200, renewed);
      await h.auth.start();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(h.http.to(renewPath), hasLength(1));
      expect(h.client.appToken?.accessToken, 'NEW-ACCESS');
      final kept = jsonDecode(h.keychain.saves.single) as Map<String, Object?>;
      expect(kept, h.client.appToken?.toJson());
      expectNoSecretsLogged();
      return kept;
    }

    testWidgets("a renewal on iOS keeps an Android token the Android app's, and writes that down", (tester) async {
      final kept = await renew(tester, storedBeforeIdentities(days: 10), isIOS: true);
      expect(kept['identity'], 'android');
    });

    testWidgets("a renewal keeps an iPhone token the iPhone app's, whatever a new login would be", (tester) async {
      final kept = await renew(tester, stored(days: 10, identity: OfficialIdentity.iphone), isIOS: false);
      expect(kept['identity'], 'iphone');
    });

    testWidgets("a confirm on iOS is kept as the iPhone app's token", (tester) async {
      final h = await mount(tester, isIOS: true);
      await h.auth.start();
      await h.environment.refreshAccount();
      await tester.pumpAndSettle();
      await tester.tap(authorize);
      await settle(tester);
      expect(h.client.appToken?.accessToken, 'NEW-ACCESS');
      expect(h.auth.identity, OfficialIdentity.iphone);
      final kept = jsonDecode(h.keychain.saves.single) as Map<String, Object?>;
      expect(kept['identity'], 'iphone');
      expect(kept, h.client.appToken?.toJson());
      expect(h.client.appBuvid, vendorBuvid);
      expectNoSecretsLogged();
    });

    testWidgets("elsewhere a confirm is kept as the Android app's", (tester) async {
      final h = await mount(tester);
      await h.auth.start();
      await h.environment.refreshAccount();
      await tester.pumpAndSettle();
      await tester.tap(authorize);
      await settle(tester);
      expect(h.auth.identity, OfficialIdentity.android);
      expect((jsonDecode(h.keychain.saves.single) as Map<String, Object?>)['identity'], 'android');
      expect(h.client.appBuvid, matches(androidBuvid));
      expectNoSecretsLogged([h.client.appBuvid]);
    });

    testWidgets("重新授权 on iOS swaps an Android token for an iPhone one, the old one and its device id in use until "
        'the confirm lands', (tester) async {
      final h = await mount(tester, token: stored(), isIOS: true);
      await h.auth.start();
      await h.environment.refreshAccount();
      await tester.pumpAndSettle();
      final androidId = h.client.appBuvid;
      expect(androidId, matches(androidBuvid));

      final poll = h.http.gates[pollPath] = Completer<void>();
      final answer = h.auth.reauthorize(host);
      await tester.pumpAndSettle();
      await tester.tap(authorize);
      await tester.pumpAndSettle();
      expect(h.http.to(pollPath), hasLength(1));
      expect(h.client.appToken?.accessToken, 'OLD-ACCESS');
      expect(h.auth.identity, OfficialIdentity.android);
      expect(h.client.appBuvid, androidId);
      expect(h.keychain.saves, isEmpty);

      poll.complete();
      await settle(tester);
      expect(await answer, isTrue);
      expect(h.client.appToken?.accessToken, 'NEW-ACCESS');
      expect(h.auth.identity, OfficialIdentity.iphone);
      expect((jsonDecode(h.keychain.saves.single) as Map<String, Object?>)['identity'], 'iphone');
      expect(h.keychain.deletes, 0);
      expect(h.client.appBuvid, vendorBuvid);
      expectNoSecretsLogged([androidId]);
    });

    testWidgets('the device id named follows the identity through a rejection and the confirm after it', (
      tester,
    ) async {
      final h = await mount(tester, token: stored(), isIOS: true);
      h.http.routes[likePath] = (200, '{"code":-101,"message":"账号未登录"}');
      await h.auth.start();
      await h.environment.refreshAccount();
      await tester.pumpAndSettle();
      final androidId = h.client.appBuvid;
      expect(androidId, matches(androidBuvid), reason: "the held token is the Android app's");

      await expectLater(h.client.officialLike(aid: 1, on: true), throwsA(isA<BiliAPIError>()));
      expect(h.client.officialIdentity, OfficialIdentity.iphone);
      expect(h.client.appBuvid, vendorBuvid, reason: 'with no token, calls go out as a new login would');

      await tester.pumpAndSettle();
      await tester.tap(authorize);
      await settle(tester);
      expect(h.auth.identity, OfficialIdentity.iphone);
      expect(h.client.appBuvid, vendorBuvid);
      expectNoSecretsLogged([androidId]);
    });

    testWidgets('and through 退出登录', (tester) async {
      final h = await mount(tester, token: stored(), isIOS: true);
      await h.auth.start();
      await h.environment.refreshAccount();
      await tester.pumpAndSettle();
      final androidId = h.client.appBuvid;
      expect(androidId, matches(androidBuvid));

      await h.environment.logout();
      await tester.pumpAndSettle();
      expect(h.auth.identity, isNull);
      expect(h.client.appBuvid, vendorBuvid);
      expectNoSecretsLogged([androidId]);
    });

    test("the fakes: none without a token, an app's with one", () {
      expect(NoAppAuth().identity, isNull);
      expect(FakeAppAuth(authorized: false).identity, isNull);
      expect(FakeAppAuth().identity, isNotNull);
    });
  });

  group('a declined confirm', () {
    late String path;
    var asked = 0;
    var answer = false;

    Future<bool> confirm(BuildContext context) async {
      asked += 1;
      return answer;
    }

    setUp(() {
      final folder = Directory.systemTemp.createTempSync('app_auth_declined');
      addTearDown(() => folder.deleteSync(recursive: true));
      path = '${folder.path}${Platform.pathSeparator}app_device.json';
      asked = 0;
      answer = false;
    });

    Map<String, Object?> deviceFile() => jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

    Future<Harness> launch(WidgetTester tester, {String? token}) async {
      final h = await mount(tester, devicePath: path, confirm: confirm, token: token);
      await tester.runAsync(h.auth.start);
      await h.environment.refreshAccount();
      await tester.pumpAndSettle();
      return h;
    }

    testWidgets("isn't asked by itself at the next launch; what needs the token and 开发者 still ask", (tester) async {
      await launch(tester);
      expect(asked, 1);
      expect(deviceFile(), containsPair('authDeclined', true));
      final ids = deviceFile()..remove('authDeclined');
      expect(ids.keys, ['buvid', 'buvidIphone']);

      final next = await launch(tester);
      expect(asked, 1, reason: 'declined before, so the launch asks nothing');
      expect(next.client.appBuvid, ids['buvid']);

      expect(await next.auth.request(host), isFalse);
      expect(asked, 2, reason: '不喜欢 and 不感兴趣 still ask');
      expect(deviceFile(), containsPair('authDeclined', true));

      answer = true;
      expect(await next.auth.reauthorize(host), isTrue);
      expect(asked, 3, reason: '开发者 still asks');
      expect(next.client.appToken?.accessToken, 'NEW-ACCESS');
      expect(deviceFile(), ids, reason: 'a confirm that goes through clears it');
      await settle(tester);
      expectNoSecretsLogged(ids.values);
    });

    testWidgets('取消 on 重新授权 keeps the token and is not remembered as turned down', (tester) async {
      final h = await launch(tester, token: stored());
      expect(asked, 0);
      expect(await h.auth.reauthorize(host), isTrue, reason: 'the token is still held');
      expect(asked, 1);
      expect(h.client.appToken?.accessToken, 'OLD-ACCESS');
      expect(h.keychain.deletes, 0);
      expect(deviceFile(), isNot(contains('authDeclined')));
    });

    testWidgets('a logout clears it, so the next login asks', (tester) async {
      final h = await launch(tester);
      expect(asked, 1);
      expect(deviceFile(), containsPair('authDeclined', true));

      await h.environment.logout();
      await tester.pumpAndSettle();
      expect(deviceFile(), isNot(contains('authDeclined')));

      expect(await h.environment.didLogin(Canned.cookies), isTrue);
      await tester.pumpAndSettle();
      expect(asked, 2);
    });
  });

  group('device id', () {
    test("has PiliPlus's buvid shape", () {
      final id = TokenAppAuth.newBuvid(Random(1));
      expect(id, matches(RegExp(r'^XY[0-9A-F]{35}$')));
      final hex = id.substring(5);
      expect(id.substring(2, 5), '${hex[2]}${hex[12]}${hex[22]}');
    });

    test("the iPhone app's is Y, three of an MD5's digits again, then the MD5 of the vendor id without hyphens", () {
      final md5 = MD5.hex('AAAAAAAABBBBCCCCDDDDEEEEEEEEEEEE').toUpperCase();
      expect(vendorBuvid, 'Y${md5[2]}${md5[12]}${md5[22]}$md5');
      expect(vendorBuvid, hasLength(36));
      expect(TokenAppAuth.newIphoneBuvid(idfv: vendorId), vendorBuvid);
    });

    test('without a vendor id it is made of random bytes, in the same shape', () {
      final id = TokenAppAuth.newIphoneBuvid(random: Random(1));
      expect(id, matches(iphoneBuvid));
      final md5 = id.substring(4);
      expect(id.substring(1, 4), '${md5[2]}${md5[12]}${md5[22]}');
      expect(TokenAppAuth.newIphoneBuvid(random: Random(2)), isNot(id));
      expect(TokenAppAuth.newIphoneBuvid(idfv: '', random: Random(1)), id);
    });

    group('in its file', () {
      late String path;

      setUp(() {
        TestWidgetsFlutterBinding.ensureInitialized();
        final folder = Directory.systemTemp.createTempSync('app_auth_test');
        addTearDown(() => folder.deleteSync(recursive: true));
        path = '${folder.path}${Platform.pathSeparator}app_device.json';
      });

      Map<String, Object?> deviceFile() => jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

      /// A launch with no login and no token, so calls go out as a new login would.
      Future<BiliClient> launch({bool isIOS = false, Future<String?> Function()? idfv}) async {
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
          isIOS: isIOS,
          idfv: idfv ?? () async => vendorId,
          logger: logger,
        );
        await auth.start();
        auth.dispose();
        return environment.client;
      }

      test('both are made once and kept', () async {
        final first = (await launch()).appBuvid;
        expect(first, matches(androidBuvid));
        final file = deviceFile();
        expect(file.keys, ['buvid', 'buvidIphone']);
        expect(file['buvid'], first);
        expect(file['buvidIphone'], matches(iphoneBuvid));

        expect((await launch()).appBuvid, first);
        expect(deviceFile(), file);
        expectNoSecretsLogged(file.values);
      });

      test("on iOS the iPhone app's comes from the vendor id once; later launches keep it whatever iOS says", () async {
        expect((await launch(isIOS: true)).appBuvid, vendorBuvid);
        final file = deviceFile();
        expect(file['buvidIphone'], vendorBuvid);

        const other = '11111111-2222-3333-4444-555555555555';
        final moved = await launch(isIOS: true, idfv: () async => other);
        expect(moved.appIdfv, other, reason: 'the reports name what iOS says now');
        expect(moved.appBuvid, vendorBuvid);

        final failed = await launch(isIOS: true, idfv: () async => throw StateError('no vendor id'));
        expect(failed.appBuvid, vendorBuvid);
        expect(deviceFile(), file);
        expectNoSecretsLogged([...file.values, other]);
      });

      test('a file from before the iPhone identity keeps its id and what it remembered, and gains the other', () async {
        final old = TokenAppAuth.newBuvid(Random(7));
        File(path).writeAsStringSync(jsonEncode({'buvid': old, 'authDeclined': true}));

        expect((await launch(isIOS: true)).appBuvid, vendorBuvid);
        expect(deviceFile(), {'buvid': old, 'buvidIphone': vendorBuvid, 'authDeclined': true});
        expect((await launch()).appBuvid, old, reason: "the Android app's id is the one it had");
        expectNoSecretsLogged([old]);
      });

      test("a vendor id iOS cannot give is tolerated, and only the error's type is logged", () async {
        final failed = await launch(isIOS: true, idfv: () async => throw StateError('made-up reason'));
        expect(failed.loginIdentity, OfficialIdentity.iphone);
        expect(failed.appIdfv, isNull);
        expect(failed.appBuvid, matches(iphoneBuvid));
        final line = events.lines.where((line) => line.contains('app idfv unreadable')).single;
        expect(line, contains('"error":"StateError"'));
        expect(line, isNot(contains('made-up reason')));
        expectNoSecretsLogged(deviceFile().values);
      });

      test('a vendor id iOS has none of yet is no error', () async {
        final none = await launch(isIOS: true, idfv: () async => null);
        expect(none.appIdfv, isNull);
        expect(none.appBuvid, matches(iphoneBuvid));
        expect(events.lines.where((line) => line.contains('idfv')), isEmpty);
      });
    });
  });
}
