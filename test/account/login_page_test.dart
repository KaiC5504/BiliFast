import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/account/login_page.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import 'fake_web_cookies.dart';

void main() {
  testWidgets('on the PC the page says 请在手机上登录 under a 登录 bar with a close control', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('请在手机上登录'), findsOneWidget);
    expect(find.bySemanticsLabel('关闭'), findsOneWidget);
    expect(find.byType(WebViewWidget), findsNothing);
  });

  group('LoginWatcher', () {
    test('hands the bilibili.com cookies over once, the first time a non-empty SESSDATA is there', () {
      fakeAsync((async) {
        final web = FakeWebCookies()..jar['buvid3'] = 'b3';
        final sessions = <Map<String, String>>[];
        final watcher = LoginWatcher(cookies: web, onSession: sessions.add);
        unawaited(watcher.check());
        async.flushMicrotasks();
        expect(web.reads, 0, reason: 'nothing is read before the page is cleared and watched');

        watcher.start();
        async.elapse(const Duration(seconds: 1));
        expect(web.reads, 1);
        web.jar['SESSDATA'] = '';
        async.elapse(const Duration(seconds: 1));
        expect(sessions, isEmpty, reason: 'an empty SESSDATA is no login');

        web.jar.addAll({'SESSDATA': 'sess', 'bili_jct': 'jct'});
        // A page finish and a URL change together, with the timer still running.
        unawaited(watcher.check());
        unawaited(watcher.check());
        async.elapse(const Duration(seconds: 3));
        expect(sessions, [
          {'buvid3': 'b3', 'SESSDATA': 'sess', 'bili_jct': 'jct'},
        ]);
        final reads = web.reads;
        async.elapse(const Duration(seconds: 5));
        expect(web.reads, reads, reason: 'it stops once it has the login');
      });
    });

    test('a read that fails is tried again on the next tick', () {
      fakeAsync((async) {
        final web = FakeWebCookies()
          ..jar['SESSDATA'] = 'sess'
          ..readError = PlatformException(code: 'webkit');
        final sessions = <Map<String, String>>[];
        LoginWatcher(cookies: web, onSession: sessions.add).start();
        async.elapse(const Duration(seconds: 1));
        expect(sessions, isEmpty);
        web.readError = null;
        async.elapse(const Duration(seconds: 1));
        expect(sessions, hasLength(1));
      });
    });

    test('once disposed it hands nothing over, even from a read already on its way', () {
      fakeAsync((async) {
        final web = FakeWebCookies()..jar['SESSDATA'] = 'sess';
        final sessions = <Map<String, String>>[];
        final watcher = LoginWatcher(cookies: web, onSession: sessions.add)..start();
        unawaited(watcher.check());
        watcher.dispose();
        async.elapse(const Duration(seconds: 3));
        expect(sessions, isEmpty);
        expect(web.reads, 1);
      });
    });

    test('started again after a login Bilibili turned down, it hands the next one over', () {
      fakeAsync((async) {
        final web = FakeWebCookies()..jar['SESSDATA'] = 'first';
        final sessions = <String?>[];
        final watcher = LoginWatcher(cookies: web, onSession: (cookies) => sessions.add(cookies['SESSDATA']))..start();
        async.elapse(const Duration(seconds: 2));
        web.jar['SESSDATA'] = 'second';
        watcher.start();
        async.elapse(const Duration(seconds: 2));
        expect(sessions, ['first', 'second']);
      });
    });

    test('wired to the account, a login is taken once and the account comes back logged in', () {
      fakeAsync((async) {
        final web = FakeWebCookies();
        final http = Canned.http();
        late AppEnvironment environment;
        unawaited(AppEnvironment.load(
          keychain: FakeKeychain(const NoStoredCookies()),
          webCookies: web,
          http: http,
          logger: Logger(session: 'test'),
        ).then((loaded) => environment = loaded));
        async.flushMicrotasks();
        final answers = <bool>[];
        final watcher = LoginWatcher(
          cookies: web,
          onSession: (cookies) => unawaited(environment.didLogin(cookies).then(answers.add)),
        )..start();
        web.jar.addAll({'SESSDATA': 'sess', 'bili_jct': 'jct', 'buvid3': 'b3', 'buvid4': 'b4'});
        unawaited(watcher.check());
        async.elapse(const Duration(seconds: 5));
        expect(answers, [true]);
        expect(http.to(Canned.navPath), hasLength(1));
        expect(environment.account, isA<LoggedIn>());
        expect(environment.cookies.value('SESSDATA'), 'sess');
      });
    });
  });
}
