import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bilifast/friends/fake_friends_api.dart';
import 'package:bilifast/friends/friends_page.dart';
import 'package:bilifast/friends/friends_route.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../dynamic/following/following_support.dart' show skinOf, violetSkin;
import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import 'friends_support.dart';

// Its own file: the stand-ins replace Roboto and the Cupertino families for every later test in the isolate.

const _p = DynamicVerify.personal;
const _o = DynamicVerify.organisation;

// Made-up people shaped like 163's rows: the same lengths and scripts, badges, pink names and long signs.
final _people = [
  friend(1, name: '测试小元补给屋', sign: '一个演示用的签名，写得足够长才能看到末尾被截断成省略号的样子吧'),
  friend(2, name: '演示dada', sign: '商务合作请联系演示：DemoTeamAB（备注公司+来意）谢谢', vipPink: true, verify: _p),
  friend(3, name: '测试的雀巢', sign: '没有ins 商务合作 加演示 DEMO888 某博@测试', vipPink: true, verify: _p),
  friend(4, name: '演示伦的弄笛者', sign: '致力于做出能让大家喜欢的作品，希望可以和大家一起慢慢变好', vipPink: true, verify: _p),
  friend(5, name: '测试粉蓝', sign: '谢谢演示员们的宠爱！！不定时更新小可爱们的日常', verify: _o),
  friend(6, name: '演示演示数字周边', sign: '数字周边和数字藏品就找我！演示演示（゜-゜）つ', vipPink: true, verify: _o),
  friend(7, name: '测试小姐姐', sign: '发布各种个性装扮的最新资讯，不定期掉落福利', verify: _o),
  friend(8, name: '演示演示拜年纪', sign: '「流光易逝，唯守岁长」', vipPink: true, verify: _o),
  friend(9, name: '测试星穹铁道', sign: '愿此行，终抵群星。', vipPink: true, verify: _o),
  for (var mid = 10; mid <= 14; mid++) friend(mid, name: '测试$mid', sign: '演示'),
];

void _near(Rect actual, Rect expected) {
  for (final (a, b) in [
    (actual.left, expected.left),
    (actual.top, expected.top),
    (actual.right, expected.right),
    (actual.bottom, expected.bottom),
  ]) {
    expect(a, closeTo(b, 0.01), reason: '$actual against $expected');
  }
}

/// 我的好友 as KaiC's iPhone draws it, under the system font and his skin's bar, against 163, 165, 166 and 167 (px / 3).
/// With BILIFAST_SHOTS naming a folder outside the repo, the 3× shots are saved there for tools/screen_diff.py.
void main() {
  Future<void> show(WidgetTester tester, {FriendsTab tab = FriendsTab.following}) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    final services = await friendsServices();
    BiliFonts.family = BiliFonts.system;
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester);
    await pumpFriendsApp(
      tester,
      services,
      FriendsPage(
        initialTab: tab,
        api: FakeFriendsApi(following: _people, collectibleFaces: const {6, 7, 8}),
        skin: skinOf(violetSkin),
      ),
      sized: false,
    );
    await settle(tester);
    // The default faces and the empty picture are assets, decoded off the test's clock.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await settle(tester);
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('shot')), '$shots/$name.png');
  }

  testWidgets('163: the bar, the tabs, the field, the count and the rows', (tester) async {
    await show(tester);
    await shoot(tester, '163-friends-following-ours');

    expect(tester.getRect(byKey('friends-bar')), const Rect.fromLTRB(0, 0, 440, 116));
    _near(tester.getRect(byKey('friends-underline')), const Rect.fromLTRB(128, 154, 156, 156));
    _near(tester.getRect(byKey('friends-search')), const Rect.fromLTRB(12, 163, 428, 193));
    _near(tester.getRect(byKey('friends-row-1')), const Rect.fromLTRB(0, 232, 440, 310));
    expect(tester.getRect(byKey('friends-row-2')).top, closeTo(310, 0.01));
    _near(tester.getRect(byKey('friends-pill-1')), const Rect.fromLTRB(356, 253.67, 428, 277.67));
    _near(tester.getRect(byKey('friends-verified-2')), const Rect.fromLTRB(44.5, 357.5, 61.5, 374.5));
    // 163's 数字藏品 faces: the ◇ level with the bolt, centred 16 left of it.
    _near(tester.getRect(byKey('friends-collectible-6')), const Rect.fromLTRB(28.5, 669.5, 45.5, 686.5));
    _near(tester.getRect(byKey('friends-verified-6')), const Rect.fromLTRB(44.5, 669.5, 61.5, 686.5));
    expect(byKey('friends-collectible-5'), findsNothing);
  });

  testWidgets('165: 粉丝 with nobody', (tester) async {
    await show(tester, tab: FriendsTab.fans);
    await shoot(tester, '165-friends-fans-empty-ours');
    final picture = find.descendant(of: byKey('friends-empty-fans'), matching: find.byType(Image));
    expect(tester.getRect(picture).top, closeTo(286, 0.01));
  });

  testWidgets('166 and 167: the sheets', (tester) async {
    await show(tester);
    await tester.tap(byKey('friends-pill-1'));
    await settle(tester);
    await shoot(tester, '166-friends-followed-sheet-ours');
    expect(tester.getRect(byKey('friends-sheet')).top, closeTo(956 - 157.67, 0.01));

    await tester.tap(byKey('friends-sheet-groups'));
    await settle(tester);
    await shoot(tester, '167-friends-set-group-sheet-ours');
    expect(tester.getRect(byKey('friends-groups')).top, 956 - FriendsTheme.groupSheet);
  });
}
