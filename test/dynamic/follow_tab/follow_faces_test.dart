import 'package:bili_core/api.dart';
import 'package:bilifast/dynamic/fake_dynamic_api.dart';
import 'package:bilifast/dynamic/follow_tab/follow_parts.dart';
import 'package:bilifast/home/home_tab_bar.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'follow_fixtures.dart';

/// 29's 最常访问 as the portal could answer it (names made up, no pictures): the third face's fields in the forms the
/// website varies between, and the account itself among them.
final _portal = <String, Object?>{
  'my_info': {'mid': '20000900'},
  'live_users': {
    'count': 1,
    'items': [
      {'mid': 20000909, 'uname': '测试直播中'},
    ],
  },
  'up_list': {
    'has_more': false,
    'offset': '',
    'items': [
      {'mid': 20000901, 'uname': '测试常看一', 'face': '', 'has_update': true},
      {'mid': 20000902, 'uname': '测试常看二', 'face': '', 'has_update': true},
      {'mid': '20000903', 'uname': '测试常看三_DongGaming', 'has_update': 1, 'is_reserve_recall': true},
      {'mid': 20000904, 'uname': '测试常看四', 'face': '', 'has_update': true},
      {'mid': 20000900, 'uname': '测试我', 'face': '', 'has_update': true},
      {'mid': 20000905, 'uname': '测试常看五', 'face': '', 'has_update': false},
    ],
  },
};

void main() {
  setUp(() => FollowPosts.cardOverride = (item, inline) => SizedBox(height: 300, child: Text('post ${item.id}')));
  tearDown(() => FollowPosts.cardOverride = null);

  testWidgets('every face the portal lists shows in its order, the third (a string mid, a 1 for its update) dotted', (
    tester,
  ) async {
    final list = DynamicDecode.ups(_portal);
    await showShell(
      tester,
      api: FakeDynamicApi(posts: posts(2), upList: list.ups),
    );
    await tester.tap(find.byKey(ValueKey('home-tab-${HomeTab.follow.name}')));
    await settle(tester);

    final mids = [20000901, 20000902, 20000903, 20000904, 20000900, 20000905];
    final lefts = [
      for (final mid in mids) tester.getTopLeft(find.byKey(ValueKey('follow-face-$mid'), skipOffstage: false)).dx,
    ];
    for (var i = 1; i < lefts.length; i++) {
      expect(lefts[i], greaterThan(lefts[i - 1]), reason: 'face ${mids[i]} after ${mids[i - 1]}');
    }
    expect(find.text('测试常看三_DongGaming'), findsOneWidget);
    expect(find.byKey(const ValueKey('follow-dot-20000903')), findsOneWidget);
    expect(find.byKey(const ValueKey('follow-dot-20000905'), skipOffstage: false), findsNothing);
    expect(
      find.byKey(const ValueKey('follow-face-20000909'), skipOffstage: false),
      findsNothing,
      reason: 'a live face leads apart from the ordinary faces',
    );
  });
}
