import 'package:bilifast/account/app_auth_client.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final page = Uri.parse('https://passport.bilibili.com/h5-app/passport/auth/scan?qrcode_id=QRFAKE&from=tv');

void main() {
  testWidgets("opens the page in the official app's browser and completes once BiliFast is back", (tester) async {
    final opened = <Uri>[];
    var done = false;
    final answer = confirmInBilibili(
      page,
      isIOS: true,
      open: (link) async {
        opened.add(link);
        return true;
      },
    )..then((_) => done = true);
    await tester.pump();
    expect(opened.single.scheme, 'bilibili');
    expect(opened.single.host, 'browser');
    expect(opened.single.queryParameters['url'], page.toString());

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(done, isFalse, reason: 'still away in the official app');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(await answer, isTrue);
  });

  testWidgets('an app that would not open answers false at once', (tester) async {
    expect(await confirmInBilibili(page, isIOS: true, open: (_) async => false), isFalse);
    expect(await confirmInBilibili(page, isIOS: true, open: (_) async => throw StateError('no handler')), isFalse);
  });

  testWidgets('off iOS, a scheme nothing handles is never opened', (tester) async {
    var opens = 0;
    final answer = await confirmInBilibili(
      page,
      isIOS: false,
      canOpen: (_) async => false,
      open: (_) async {
        opens += 1;
        return true;
      },
    );
    expect(answer, isFalse);
    expect(opens, 0);
  });
}
