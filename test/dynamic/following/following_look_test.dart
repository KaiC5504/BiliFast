import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bilifast/dynamic/fake_dynamic_api.dart';
import 'package:bilifast/dynamic/following/following_page.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/look_alike.dart';
import '../../support/stand_in_fonts.dart';
import 'following_support.dart';

// Its own file: the stand-ins replace Roboto and the Cupertino families for every later test in the isolate.

const _p = DynamicVerify.personal;
const _o = DynamicVerify.organisation;

// Made-up people shaped like 129's rows: the same lengths and scripts, badges, pink names and dots.
final _people = [
  followingUser(1, name: '测试kiki', vipPink: true, verify: _p),
  followingUser(2, name: '演示的小号', vipPink: true, verify: _p),
  followingUser(3, name: '演示一个机构', vipPink: true, verify: _o),
  followingUser(4, name: '演示', vipPink: true, verify: _o),
  followingUser(5, name: '测试某人', vipPink: true, verify: _p),
  followingUser(6, name: '测试的花园', vipPink: true, verify: _p),
  followingUser(7, name: '测试某某的旅人', vipPink: true, verify: _p),
  followingUser(8, name: '测试小伙伴', verify: _o),
  followingUser(9, name: '测试就是我_SampleGame', vipPink: true, verify: _p),
  followingUser(10, name: '测试测试演示商店', vipPink: true, verify: _o),
  followingUser(11, name: '测试白云_'),
  followingUser(12, name: '测试云', verify: _o),
  followingUser(13, name: '测试测试纪念日', vipPink: true),
];

FakeDynamicApi _api() => FakeDynamicApi(
  following: _people,
  upList: [for (var mid = 1; mid <= 10; mid++) DynamicUp(mid: mid, name: '', face: '', hasUpdate: true)],
);

/// 我的关注 as KaiC's iPhone draws it, under the system font and his skin's bar, against 129 and 130 (px / 3). With
/// BILIFAST_SHOTS naming a folder outside the repo, the 3× shots are saved there for tools/screen_diff.py.
void main() {
  Future<void> show(WidgetTester tester) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    // The services' font store puts MiSans back, so the system font comes after them.
    final services = await followingServices(api: _api());
    BiliFonts.family = BiliFonts.system;
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester);
    await pumpFollowingApp(tester, services, home: FollowingListPage(skin: skinOf(violetSkin)));
    await settle(tester);
    // The default faces are an asset, decoded off the test's clock.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await settle(tester);
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('shot')), '$shots/$name.png');
  }

  testWidgets('129: the bar, the field, 排序方式 and the rows', (tester) async {
    await show(tester);
    await shoot(tester, '129-dynamic-following-list-ours');

    expect(tester.getRect(find.byKey(const ValueKey('following-bar'))), const Rect.fromLTRB(0, 0, 440, 116));
    expect(tester.getRect(find.byKey(const ValueKey('following-search'))), const Rect.fromLTRB(12, 122, 428, 152));
    expect(tester.getRect(find.byKey(const ValueKey('following-row-1'))), const Rect.fromLTRB(0, 198, 440, 258));
    expect(tester.getRect(find.byKey(const ValueKey('following-row-2'))).top, 258);
    expect(tester.getRect(find.byKey(const ValueKey('following-verified-1'))), const Rect.fromLTRB(39, 235, 53, 249));
    expect(tester.getCenter(find.byKey(const ValueKey('following-dot-1'))), const Offset(422.5, 228));
    expect(find.byKey(const ValueKey('following-dot-11')), findsNothing);
  });

  testWidgets('130: the menu open under 排序方式', (tester) async {
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('following-sort')));
    await settle(tester);
    await shoot(tester, '130-dynamic-following-sort-ours');

    final menu = tester.getRect(find.byKey(const ValueKey('following-menu')));
    expect(menu.top, 198 - FollowingListTheme.notchHeight);
    expect(menu.bottom, 318);
    expect(tester.getRect(find.byKey(const ValueKey('following-menu-dim'))).top, 318);
    expect(tester.getCenter(find.byKey(const ValueKey('following-order-check'))).dx, closeTo(417, 0.01));
  });
}
