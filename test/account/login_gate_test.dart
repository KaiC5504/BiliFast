import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:bilifast/account/login_page.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import 'fake_web_cookies.dart';

void main() {
  late BuildContext host;

  Future<AppEnvironment> mount(WidgetTester tester) async {
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const NoStoredCookies()),
      webCookies: FakeWebCookies(),
      http: CannedHttp(),
      logger: Logger(session: 'test'),
    );
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        host = context;
        return const SizedBox.expand();
      }),
    ));
    return environment;
  }

  testWidgets('logged in, it answers true at once with no page', (tester) async {
    final environment = await mount(tester);
    environment.useFakeAccount();
    expect(await LoginPageGate(environment).request(host), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets('logged out, it pushes the login page once and closing it answers false', (tester) async {
    final environment = await mount(tester);
    final first = LoginPageGate(environment).request(host);
    final second = LoginPageGate(environment).request(host);
    expect(identical(first, second), isTrue, reason: 'a second request waits on the page already up');
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('请在手机上登录'), findsOneWidget);

    bool? answer;
    unawaited(first.then((value) => answer = value));
    await tester.tap(find.byKey(const ValueKey('login-close')));
    await tester.pumpAndSettle();
    expect(answer, isFalse);
    expect(find.byType(LoginPage), findsNothing);

    final again = LoginPageGate(environment).request(host);
    expect(identical(again, first), isFalse);
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('the page coming back logged in answers true', (tester) async {
    final environment = await mount(tester);
    final answer = LoginPageGate(environment).request(host);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(LoginPage))).pop(true);
    await tester.pumpAndSettle();
    expect(await answer, isTrue);
  });
}
