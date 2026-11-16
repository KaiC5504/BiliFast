import 'package:bili_core/api.dart';
import 'package:bilifast/home/hot/hot_share_sheet.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';

import '../fake_login_gate.dart';
import 'hot_support.dart';

void main() {
  late FakePageApi pageApi;
  late FakeLoginGate gate;
  late HotHarness harness;

  setUp(() {
    pageApi = FakePageApi();
    gate = FakeLoginGate();
    harness = HotHarness();
  });

  final sheet = find.byKey(const ValueKey('hot-share-sheet'));

  Future<void> open(WidgetTester tester, {bool loggedIn = true}) async {
    await pumpHot(tester, await hotServices(loggedIn: loggedIn, pageApi: pageApi, gate: gate), harness.list());
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('hot-more-BV1hot3')));
    await settle(tester);
    expect(sheet, findsOneWidget);
  }

  testWidgets("217's targets in order, then 稍后再看", (tester) async {
    await open(tester);
    for (final target in HotShareTarget.values) {
      expect(find.byKey(ValueKey('hot-share-${target.name}')), findsOneWidget, reason: target.label);
    }
    final lefts = [
      for (final target in HotShareTarget.values) tester.getRect(find.byKey(ValueKey('hot-share-${target.name}'))).left,
    ];
    expect(lefts, [for (var i = 0; i < HotShareTarget.values.length; i++) 12.0 + 66 * i]);
    expect(
      [for (final target in HotShareTarget.values) target.label],
      ['Facebook', 'X', 'WhatsApp', '微信', '朋友圈', '下载分享', 'QQ'],
    );
    expect(find.text('稍后再看'), findsOneWidget);
  });

  testWidgets("a share target closes the sheet and hands the video's link to the share sheet", (tester) async {
    for (final target in [HotShareTarget.facebook, HotShareTarget.weChat, HotShareTarget.moments]) {
      harness = HotHarness();
      await open(tester);
      await tester.tap(find.byKey(ValueKey('hot-share-${target.name}')));
      await settle(tester);
      expect(sheet, findsNothing, reason: target.label);
      expect(harness.shared, [Uri.parse('https://www.bilibili.com/video/BV1hot3')], reason: target.label);
    }
  });

  testWidgets('QQ, off the right edge, is reached by scrolling the row', (tester) async {
    await open(tester);
    await tester.drag(find.byKey(const ValueKey('hot-share-weChat')), const Offset(-200, 0));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('hot-share-qq')));
    await settle(tester);
    expect(harness.shared, hasLength(1));
  });

  testWidgets('a share that fails says so', (tester) async {
    harness.shareError = Exception('no sheet');
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('hot-share-x')));
    await settle(tester);
    expect(find.text('分享失败'), findsOneWidget);
    await toastGone(tester);
  });

  testWidgets('下载分享 toasts 暂未开放 and shares nothing', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('hot-share-download')));
    await settle(tester);
    expect(sheet, findsNothing);
    expect(find.text('暂未开放'), findsOneWidget);
    expect(harness.shared, isEmpty);
    await toastGone(tester);
  });

  testWidgets('稍后再看 adds the video and toasts', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('hot-share-watch-later')));
    await settle(tester);
    expect(pageApi.calls, ['addToWatchLater aid=7003']);
    expect(find.text('已添加至稍后再看'), findsOneWidget);
    expect(sheet, findsNothing);
    await toastGone(tester);
  });

  testWidgets('logged out, 稍后再看 opens the login page and adds nothing', (tester) async {
    await open(tester, loggedIn: false);
    await tester.tap(find.byKey(const ValueKey('hot-share-watch-later')));
    await settle(tester);
    expect(gate.requests, 1);
    expect(pageApi.calls, isEmpty);
  });

  testWidgets('a failed 稍后再看 says why; one that needs a login asks for it', (tester) async {
    pageApi.failures['addToWatchLater'] = const BiliAPIError(code: 90001, message: '稍后再看已满');
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('hot-share-watch-later')));
    await settle(tester);
    expect(find.text('稍后再看已满'), findsOneWidget);
    await toastGone(tester);

    pageApi.failures['addToWatchLater'] = const BiliAPIError(code: -101, message: '账号未登录');
    await tester.tap(find.byKey(const ValueKey('hot-more-BV1hot3')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('hot-share-watch-later')));
    await settle(tester);
    expect(gate.requests, 1);
  });

  testWidgets('× and the dim close it, doing nothing', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('hot-share-close')));
    await settle(tester);
    expect(sheet, findsNothing);

    await tester.tap(find.byKey(const ValueKey('hot-more-BV1hot3')));
    await settle(tester);
    await tester.tapAt(const Offset(220, 200));
    await settle(tester);
    expect(sheet, findsNothing);
    expect(harness.shared, isEmpty);
    expect(pageApi.calls, isEmpty);
  });

  testWidgets('every button answers accessibility presses', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);
    tester.semantics.tap(find.semantics.byLabel('微信'));
    await settle(tester);
    expect(harness.shared, hasLength(1));

    await tester.tap(find.byKey(const ValueKey('hot-more-BV1hot3')));
    await settle(tester);
    tester.semantics.tap(find.semantics.byLabel('稍后再看'));
    await settle(tester);
    expect(pageApi.calls, hasLength(1));
    await toastGone(tester);

    await tester.tap(find.byKey(const ValueKey('hot-more-BV1hot3')));
    await settle(tester);
    // The dim is labelled 关闭 too; × is the button.
    tester.semantics.tap(
      find.semantics.byPredicate((node) {
        final data = node.getSemanticsData();
        return data.label == '关闭' && data.flagsCollection.isButton && data.hasAction(SemanticsAction.tap);
      }),
    );
    await settle(tester);
    expect(sheet, findsNothing);
    semantics.dispose();
  });
}
