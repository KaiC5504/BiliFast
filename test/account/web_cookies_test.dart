import 'package:bilifast/account/web_cookies.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('bilifast/web_cookies');
  final calls = <String>[];
  Object? bilibiliReply;

  setUp(() {
    calls.clear();
    bilibiliReply = {'SESSDATA': 'sess', 'bili_jct': 'jct'};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'bilibili' ? bilibiliReply : null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('reads the bilibili.com cookies by name', () async {
    expect(await ChannelWebCookies().bilibili(), {'SESSDATA': 'sess', 'bili_jct': 'jct'});
    expect(calls, ['bilibili']);
  });

  test('no reply reads as no cookies', () async {
    bilibiliReply = null;
    expect(await ChannelWebCookies().bilibili(), isEmpty);
  });

  test('clears the bilibili.com cookies, and everything', () async {
    await ChannelWebCookies().clearBilibili();
    await ChannelWebCookies().clearAll();
    expect(calls, ['clearBilibili', 'clearAll']);
  });

  test('the PC has no web view and nothing stored', () async {
    final cookies = WebCookies.platform();
    expect(cookies, isA<NoWebCookies>());
    expect(await cookies.bilibili(), isEmpty);
    await cookies.clearBilibili();
    await cookies.clearAll();
  });
}
