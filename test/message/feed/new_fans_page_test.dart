import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/message/fake_message_api.dart';
import 'package:bilifast/message/feed/new_fans_page.dart';
import 'package:bilifast/message/settings/notice_picker_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../home/fake_login_gate.dart';
import 'feed_support.dart';

RelationUser fan(int mid, {int attribute = RelationUser.none}) => RelationUser(
  user: FollowingUser(mid: mid, name: '演示粉丝$mid', face: '', sign: '演示签名'),
  attribute: attribute,
);

/// Records whose fans were asked.
class _Fans extends FakeMessageApi {
  _Fans() : super();

  final mids = <int>[];

  @override
  Future<RelationPage> newFans(int mid, {required int page}) {
    mids.add(mid);
    return super.newFans(mid, page: page);
  }
}

void main() {
  late RecordingOpeners opens;

  setUp(() => opens = RecordingOpeners());

  Future<AppServices> open(
    WidgetTester tester,
    FakeMessageApi api, {
    bool loggedIn = true,
    bool checked = true,
    FakeLoginGate? gate,
  }) async {
    final services = await feedServices(api, loggedIn: loggedIn, checked: checked, loginGate: gate);
    await pumpFeed(tester, services, NewFansPage(opens: opens));
    return services;
  }

  String pillOf(WidgetTester tester, int mid) =>
      tester.widget<Text>(find.descendant(of: byKey('friends-pill-$mid'), matching: byKey('friends-pill-label'))).data!;

  testWidgets('199: nobody new shows the empty picture under the plain bar', (tester) async {
    final api = _Fans();
    final services = await open(tester, api);
    expect(find.text('新增粉丝'), findsOneWidget);
    expect(find.text('这里还什么都没有呢～'), findsOneWidget);
    expect(api.calls, ['newFans page=1']);
    expect(api.mids, [services.environment.mid]);
  });

  testWidgets('fans show as 我的好友\'s rows; 回关 follows back and every page agrees', (tester) async {
    final api = FakeMessageApi(
      fanList: [
        fan(1),
        fan(2, attribute: RelationUser.mutualValue),
      ],
    );
    final services = await open(tester, api);
    expect(pillOf(tester, 1), '回关');
    expect(pillOf(tester, 2), '已互粉');
    await tester.tap(byKey('friends-pill-1'));
    await settle(tester);
    expect(api.follows, [(mid: 1, on: true)]);
    expect(services.follows.following(1), isTrue);
    expect(pillOf(tester, 1), '已互粉');
    await settle(tester, 60);
  });

  testWidgets('a 回关 Bilibili refuses goes back to 回关', (tester) async {
    final api = FakeMessageApi(fanList: [fan(1)]);
    final answer = Completer<void>();
    api
      ..holds['follow'] = answer
      ..failures['follow'] = const BiliError.api(code: 22009, message: '关注已达上限');
    await open(tester, api);
    await tester.tap(byKey('friends-pill-1'));
    await tester.pump();
    expect(pillOf(tester, 1), '已互粉', reason: 'shown at once');
    answer.complete();
    await settle(tester);
    expect(pillOf(tester, 1), '回关');
    expect(find.text('关注已达上限'), findsOneWidget);
    await settle(tester, 60);
  });

  testWidgets('a row opens the fan\'s space', (tester) async {
    await open(tester, FakeMessageApi(fanList: [fan(5)]));
    await tester.tap(byKey('friends-row-5'));
    await settle(tester);
    expect(opens.spaces.single.mid, 5);
  });

  testWidgets('the next page is asked by number near the end', (tester) async {
    final api = FakeMessageApi(fanList: [for (var mid = 1; mid <= 50; mid++) fan(mid)], pageSize: 30);
    await open(tester, api);
    expect(api.calls, ['newFans page=1']);
    await tester.drag(byKey('feed-fans-list'), const Offset(0, -900));
    await settle(tester);
    expect(api.calls, ['newFans page=1', 'newFans page=2']);
  });

  testWidgets('the gear opens 新增粉丝\'s 消息提醒', (tester) async {
    await open(tester, FakeMessageApi());
    await tester.tap(byKey('feed-gear'));
    await settle(tester);
    expect(tester.widget<NoticePickerPage>(find.byType(NoticePickerPage)).kind, NoticeSettingKind.fans);
  });

  testWidgets('logged out, the gear asks for the login before 消息提醒', (tester) async {
    final gate = FakeLoginGate();
    final api = FakeMessageApi(fanList: [fan(1)]);
    await open(tester, api, loggedIn: false, gate: gate);
    await tester.tap(byKey('feed-gear'));
    await settle(tester);
    expect(gate.requests, 1);
    expect(find.byType(NoticePickerPage), findsNothing);
    expect(api.calls, isEmpty);
  });

  testWidgets('the fans start once the account is known; a failure then waits for 重试', (tester) async {
    final api = FakeMessageApi(fanList: [fan(1)]);
    api.failures['newFans'] = const BiliError.http(500);
    final services = await open(tester, api, checked: false);
    expect(api.calls, isEmpty, reason: 'the fans need the account\'s mid');
    await services.environment.refreshAccount();
    await settle(tester);
    expect(api.calls, ['newFans page=1']);
    expect(byKey('feed-fans-failed'), findsOneWidget);
    await services.environment.refreshAccount();
    await settle(tester);
    expect(api.calls, ['newFans page=1']);
  });
}
