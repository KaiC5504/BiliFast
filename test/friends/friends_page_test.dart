import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bilifast/app/swipe_back_route.dart';
import 'package:bilifast/friends/fake_friends_api.dart';
import 'package:bilifast/friends/friends_page.dart';
import 'package:bilifast/friends/friends_route.dart';
import 'package:bilifast/shared/loading_tv.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/space/space_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../home/fake_login_gate.dart';
import 'friends_support.dart';

Color? _colour(WidgetTester tester, String key) => tester.widget<Text>(byKey(key)).style?.color;

Color? _tabColour(WidgetTester tester, FriendsTab tab) => _colour(tester, 'friends-tab-label-${tab.name}');

double _underlineX(WidgetTester tester) => tester.getCenter(byKey('friends-underline')).dx;

String _pill(WidgetTester tester, int mid) => tester
    .widget<Text>(find.descendant(of: byKey('friends-pill-$mid'), matching: byKey('friends-pill-label')))
    .data!;

void main() {
  testWidgets('openFriends pushes the plain swipe-back route on the asked tab, and ‹ goes back', (tester) async {
    final services = await friendsServices();
    services.environment.useFakeAccount();
    await pumpFriendsApp(
      tester,
      services,
      Builder(
        builder: (context) => Center(
          child: GestureDetector(
            key: const ValueKey('open'),
            behavior: HitTestBehavior.opaque,
            onTap: () => openFriends(context, tab: FriendsTab.fans),
            child: const SizedBox.square(dimension: 80),
          ),
        ),
      ),
    );
    await tester.tap(byKey('open'));
    await settle(tester);
    expect(find.byType(FriendsPage), findsOneWidget);
    expect(ModalRoute.of(tester.element(find.byType(FriendsPage))), isA<SwipeBackPageRoute<void>>());
    expect(find.text('我的好友'), findsOneWidget);
    expect(_tabColour(tester, FriendsTab.fans), FriendsTheme.tabChosen);
    expect(_tabColour(tester, FriendsTab.following), FriendsTheme.tabInk);
    // The fake account's demo fans, one not followed back.
    expect(_pill(tester, 899), '回关');

    await tester.tap(byKey('friends-back'));
    await settle(tester);
    expect(find.byType(FriendsPage), findsNothing);
  });

  testWidgets('关注: the TV, then the count, the order and rows with pink names, badges and signs', (tester) async {
    final api = FakeFriendsApi(
      following: [
        friend(1, name: '粉色名字', sign: '一行签名', vipPink: true, verify: DynamicVerify.personal),
        friend(2, name: '普通名字', verify: DynamicVerify.organisation),
        ...[for (var mid = 3; mid <= 14; mid++) friend(mid)],
      ],
    );
    final hold = api.holds['followings'] = Completer<void>();
    await openFriendsPage(tester, api);
    expect(find.byType(LoadingTvState), findsOneWidget);
    expect(byKey('friends-count'), findsNothing);

    api.holds.remove('followings');
    hold.complete();
    await settle(tester);
    expect(find.byType(LoadingTvState), findsNothing);
    expect(find.text('搜索我的关注'), findsOneWidget);
    expect(find.text('我的关注'), findsOneWidget);
    expect(find.text('14人'), findsOneWidget);
    expect(find.text('最近关注'), findsOneWidget);
    expect(_colour(tester, 'friends-name-1'), FriendsTheme.vipName);
    expect(_colour(tester, 'friends-name-2'), FriendsTheme.name);
    expect(find.text('一行签名'), findsOneWidget);
    expect(byKey('friends-verified-1'), findsOneWidget);
    expect(byKey('friends-verified-2'), findsOneWidget);
    expect(byKey('friends-verified-3'), findsNothing);
    expect(_pill(tester, 1), '已关注');
    expect(tester.getSize(byKey('friends-row-1')).height, FriendsTheme.row);
    expect(api.calls, ['followings recent page=1']);
  });

  testWidgets('the order swaps 最近关注 and 最近访问 on a tap, each reloading the list in its order', (tester) async {
    final api = FakeFriendsApi(following: friends(3));
    await openFriendsPage(tester, api);
    expect(tester.getTopLeft(byKey('friends-row-1')).dy, lessThan(tester.getTopLeft(byKey('friends-row-3')).dy));

    await tester.tap(byKey('friends-sort'));
    await settle(tester);
    expect(find.text('最近访问'), findsOneWidget);
    expect(find.text('最近关注'), findsNothing);
    expect(tester.getTopLeft(byKey('friends-row-3')).dy, lessThan(tester.getTopLeft(byKey('friends-row-1')).dy));

    await tester.tap(byKey('friends-sort'));
    await settle(tester);
    expect(find.text('最近关注'), findsOneWidget);
    expect(api.calls, ['followings recent page=1', 'followings mostVisited page=1', 'followings recent page=1']);
  });

  testWidgets('pages on near the end of the list', (tester) async {
    final api = FakeFriendsApi(following: friends(45));
    await openFriendsPage(tester, api);
    await tester.drag(byKey('friends-following'), const Offset(0, -1500));
    await settle(tester);
    await tester.drag(byKey('friends-following'), const Offset(0, -1500));
    await settle(tester);
    await tester.drag(byKey('friends-following'), const Offset(0, -1500));
    await settle(tester);
    expect(api.calls, ['followings recent page=1', 'followings recent page=2', 'followings recent page=3']);
    expect(byKey('friends-row-45'), findsOneWidget);
  });

  testWidgets('a failed first page says so with 重试, and 重试 loads it', (tester) async {
    final api = FakeFriendsApi(following: friends(3))
      ..failures['followings'] = const BiliError.api(code: -500, message: '服务器开小差了');
    await openFriendsPage(tester, api);
    expect(byKey('friends-failed-following'), findsOneWidget);
    api.failures.remove('followings');
    await tester.tap(byKey('friends-retry-following'));
    await settle(tester);
    expect(byKey('friends-row-3'), findsOneWidget);
  });

  testWidgets('tabs: a tap on 粉丝 slides there and asks the fans once, a swipe comes back', (tester) async {
    final api = FakeFriendsApi(following: friends(3));
    await openFriendsPage(tester, api);
    final followingX = _underlineX(tester);
    expect(followingX, closeTo(220 - 78, 0.01));
    expect(_tabColour(tester, FriendsTab.following), FriendsTheme.tabChosen);
    expect(callCount(api, 'fans'), 0);

    await tester.tap(byKey('friends-tab-fans'));
    await settle(tester);
    expect(_underlineX(tester), closeTo(220 + 78, 0.01));
    expect(_tabColour(tester, FriendsTab.fans), FriendsTheme.tabChosen);
    expect(_tabColour(tester, FriendsTab.following), FriendsTheme.tabInk);
    expect(callCount(api, 'fans'), 1);

    await tester.fling(byKey('friends-pager'), const Offset(300, 0), 1500);
    await settle(tester);
    expect(_underlineX(tester), closeTo(followingX, 0.01));
    expect(_tabColour(tester, FriendsTab.following), FriendsTheme.tabChosen);
    expect(byKey('friends-row-1'), findsOneWidget);

    await tester.tap(byKey('friends-tab-fans'));
    await settle(tester);
    expect(callCount(api, 'fans'), 1, reason: 'the fans are kept, not asked again');
  });

  testWidgets('粉丝 with nobody: the empty picture and 这里还什么都没有呢～', (tester) async {
    final api = FakeFriendsApi(following: friends(2));
    await openFriendsPage(tester, api, tab: FriendsTab.fans);
    expect(byKey('friends-empty-fans'), findsOneWidget);
    expect(find.text('这里还什么都没有呢～'), findsOneWidget);
    final picture = find.descendant(of: byKey('friends-empty-fans'), matching: find.byType(Image));
    expect(tester.getSize(picture), const Size.square(FriendsTheme.emptyPicture));
    // 165: its top 130.33 under the tab rule, the rule's bottom 155.67 down the screen (no status bar here: 93.67).
    final ruleBottom = tester.getBottomLeft(byKey('friends-bar')).dy + FriendsTheme.tabRow + FriendsTheme.tabRule;
    expect(tester.getTopLeft(picture).dy, closeTo(ruleBottom + FriendsTheme.emptyTop, 0.01));
    expect(tester.getCenter(picture).dx, 220);
    expect(api.calls, ['followings recent page=1', 'fans page=1']);
  });

  testWidgets('粉丝 filled: 回关 for those not followed back follows them, ≡ 已互粉 for mutuals', (tester) async {
    final api = FakeFriendsApi(following: [friend(1)], fanList: [friend(1), friend(2, name: '新粉丝')]);
    await openFriendsPage(tester, api, tab: FriendsTab.fans);
    expect(_pill(tester, 1), '已互粉');
    expect(_pill(tester, 2), '回关');

    await tester.tap(byKey('friends-pill-2'));
    await settle(tester);
    expect(api.follows, [(mid: 2, on: true)]);
    expect(_pill(tester, 2), '已互粉');
    expect(find.text('关注成功'), findsOneWidget);
    await settle(tester, 60);
  });

  testWidgets('a row opens the person’s space', (tester) async {
    final api = FakeFriendsApi(following: friends(3));
    await openFriendsPage(tester, api);
    await tester.tap(byKey('friends-row-2'));
    await settle(tester);
    expect(find.byType(SpacePage), findsOneWidget);
  });

  testWidgets('搜索我的关注: 取消 beside the field, the results after the pause, the text never asked aloud', (
    tester,
  ) async {
    final api = FakeFriendsApi(following: [friend(1, name: '星夜蓝羽_'), friend(2, name: '崩坏星穹铁道'), friend(3, name: '画粉蓝')]);
    await openFriendsPage(tester, api);
    final wide = tester.getSize(byKey('friends-search')).width;
    expect(wide, 440 - 24);

    await tester.tap(byKey('friends-search-field'));
    await tester.pump();
    expect(byKey('friends-search-cancel'), findsOneWidget);
    expect(tester.getSize(byKey('friends-search')).width, closeTo(440 - 12 - FriendsTheme.fieldEndSearching, 0.01));

    await tester.enterText(byKey('friends-search-field'), '星');
    await tester.pump(const Duration(milliseconds: 100));
    expect(callCount(api, 'searchFollowings'), 0, reason: 'typing waits for a pause');
    await settle(tester);
    expect(api.calls.last, 'searchFollowings page=1');
    expect(api.calls.join(), isNot(contains('星')));
    expect(byKey('friends-sort'), findsNothing, reason: 'the count and the order give way to the results');
    expect(byKey('friends-results'), findsOneWidget);
    expect(byKey('friends-row-1'), findsOneWidget);
    expect(byKey('friends-row-2'), findsOneWidget);
    expect(byKey('friends-row-3'), findsNothing);
    // 168: the results start 7 under the field.
    expect(
      tester.getTopLeft(byKey('friends-row-1')).dy,
      closeTo(tester.getBottomLeft(byKey('friends-search')).dy + FriendsTheme.resultsTop, 0.01),
    );

    await tester.tap(byKey('friends-search-clear'));
    await settle(tester);
    expect(tester.widget<TextField>(byKey('friends-search-field')).controller!.text, isEmpty);
    expect(byKey('friends-sort'), findsOneWidget);

    await tester.enterText(byKey('friends-search-field'), '画');
    await settle(tester);
    expect(byKey('friends-row-3'), findsOneWidget);
    await tester.tap(byKey('friends-search-cancel'));
    await settle(tester);
    expect(byKey('friends-search-cancel'), findsNothing);
    expect(byKey('friends-sort'), findsOneWidget);
    expect(byKey('friends-row-1'), findsOneWidget);
    expect(tester.getSize(byKey('friends-search')).width, wide);
  });

  testWidgets('已关注 brings up 166’s sheet; back, the dim and 取消 each put it away and leave the page', (tester) async {
    final api = FakeFriendsApi(following: friends(3));
    await openFriendsPage(tester, api);
    await tester.tap(byKey('friends-pill-1'));
    await settle(tester);
    expect(byKey('friends-sheet'), findsOneWidget);
    expect(find.text('设置分组'), findsOneWidget);
    expect(find.text('取消关注'), findsOneWidget);
    expect(tester.getBottomLeft(byKey('friends-sheet')).dy, 956);
    // The dim starts under the bar: the bar is left as it is (166).
    expect(tester.getTopLeft(byKey('friends-sheet-dim')).dy, tester.getBottomLeft(byKey('friends-bar')).dy);

    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(byKey('friends-sheet'), findsNothing);
    expect(find.byType(FriendsPage), findsOneWidget);

    await tester.tap(byKey('friends-pill-1'));
    await settle(tester);
    await tester.tapAt(const Offset(220, 300));
    await settle(tester);
    expect(byKey('friends-sheet'), findsNothing);

    await tester.tap(byKey('friends-pill-1'));
    await settle(tester);
    await tester.tap(byKey('friends-sheet-cancel'));
    await settle(tester);
    expect(byKey('friends-sheet'), findsNothing);
    expect(api.follows, isEmpty);

    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(FriendsPage), findsNothing);
  });

  testWidgets('取消关注 unfollows: the pill turns pink 关注, FollowBook hears it, and 关注 follows again', (tester) async {
    final api = FakeFriendsApi(following: friends(3));
    final services = await openFriendsPage(tester, api);
    await tester.tap(byKey('friends-pill-2'));
    await settle(tester);
    await tester.tap(byKey('friends-sheet-unfollow'));
    await settle(tester);
    expect(api.follows, [(mid: 2, on: false)]);
    expect(services.follows.following(2), isFalse);
    expect(_pill(tester, 2), '关注');
    expect(find.text('取消关注成功'), findsOneWidget);
    await settle(tester, 60);

    await tester.tap(byKey('friends-pill-2'));
    await settle(tester);
    expect(byKey('friends-sheet'), findsNothing, reason: 'a pink pill follows at once');
    expect(api.follows, [(mid: 2, on: false), (mid: 2, on: true)]);
    expect(services.follows.following(2), isTrue);
    expect(_pill(tester, 2), '已关注');
    await settle(tester, 60);
  });

  testWidgets('a refused 取消关注 puts the pill back and says why', (tester) async {
    final api = FakeFriendsApi(following: friends(3))
      ..failures['follow'] = const BiliError.api(code: 22001, message: '不能对自己进行此操作');
    final services = await openFriendsPage(tester, api);
    await tester.tap(byKey('friends-pill-1'));
    await settle(tester);
    await tester.tap(byKey('friends-sheet-unfollow'));
    await settle(tester);
    expect(_pill(tester, 1), '已关注');
    expect(services.follows.following(1), isNull);
    expect(find.text('不能对自己进行此操作'), findsOneWidget);
    await settle(tester, 60);
  });

  testWidgets('a 关注 changed on another page shows on the row', (tester) async {
    final api = FakeFriendsApi(following: friends(3));
    final services = await openFriendsPage(tester, api);
    services.follows.changed(3, following: false);
    await settle(tester);
    expect(_pill(tester, 3), '关注');
  });

  testWidgets('设置分组: 特别关注 and its circle, 保存至默认分组 until one is ticked, then 保存 sends it', (tester) async {
    final api = FakeFriendsApi(following: friends(3));
    await openFriendsPage(tester, api);
    await tester.tap(byKey('friends-pill-1'));
    await settle(tester);
    await tester.tap(byKey('friends-sheet-groups'));
    await settle(tester);
    expect(byKey('friends-sheet'), findsNothing);
    expect(byKey('friends-groups'), findsOneWidget);
    expect(tester.getSize(byKey('friends-groups')).height, FriendsTheme.groupSheet);
    expect(find.text('特别关注'), findsOneWidget);
    expect(find.text('第一时间收到该分组下用户更新稿件的通知'), findsOneWidget);
    expect(find.text('默认分组'), findsNothing);
    expect(byKey('friends-group--10-open'), findsOneWidget);
    expect(find.text('保存至默认分组'), findsOneWidget);
    expect(api.calls.sublist(1), ['tags', 'tagsOf 1']);

    await tester.tap(byKey('friends-new-group'));
    await tester.pump();
    expect(find.text('暂未开放'), findsOneWidget);
    await settle(tester, 60);

    await tester.tap(byKey('friends-group--10'));
    await tester.pump();
    expect(byKey('friends-group--10-ticked'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    await tester.tap(byKey('friends-groups-save'));
    await settle(tester);
    expect(api.saved.single.mid, 1);
    expect(api.saved.single.tags, {RelationTag.special});
    expect(api.calls.last, 'setTags 1 -10');
    expect(byKey('friends-groups'), findsNothing);
    expect(find.text('设置成功'), findsOneWidget);
    await settle(tester, 60);

    // Again for the same person: ticked as saved, the 分组 not asked twice; untick and it goes back to 默认分组.
    await tester.tap(byKey('friends-pill-1'));
    await settle(tester);
    await tester.tap(byKey('friends-sheet-groups'));
    await settle(tester);
    expect(byKey('friends-group--10-ticked'), findsOneWidget);
    expect(api.calls.where((call) => call == 'tags'), hasLength(1));
    expect(callCount(api, 'tagsOf'), 2);
    await tester.tap(byKey('friends-group--10'));
    await tester.pump();
    expect(find.text('保存至默认分组'), findsOneWidget);
    await tester.tap(byKey('friends-groups-save'));
    await settle(tester);
    expect(api.calls.last, 'setTags 1 ');
    expect(api.saved.last.tags, isEmpty);
    await settle(tester, 60);
  });

  testWidgets('设置分组 saved unchanged sends nothing, and back closes it', (tester) async {
    final api = FakeFriendsApi(following: friends(3));
    await openFriendsPage(tester, api);
    await tester.tap(byKey('friends-pill-1'));
    await settle(tester);
    await tester.tap(byKey('friends-sheet-groups'));
    await settle(tester);
    await tester.tap(byKey('friends-groups-save'));
    await settle(tester);
    expect(byKey('friends-groups'), findsNothing);
    expect(callCount(api, 'setTags'), 0);

    await tester.tap(byKey('friends-pill-1'));
    await settle(tester);
    await tester.tap(byKey('friends-sheet-groups'));
    await settle(tester);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(byKey('friends-groups'), findsNothing);
    expect(find.byType(FriendsPage), findsOneWidget);
  });

  testWidgets('logged out: 登录 in place of the lists, through the login gate', (tester) async {
    final gate = FakeLoginGate();
    final api = FakeFriendsApi(following: friends(3));
    await openFriendsPage(tester, api, loggedIn: false, loginGate: gate);
    expect(byKey('friends-logged-out'), findsOneWidget);
    expect(api.calls, isEmpty);
    await tester.tap(byKey('friends-login'));
    await settle(tester);
    expect(gate.requests, 1);
  });
}
