import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/home_page.dart';
import 'package:bilifast/home/home_tab_bar.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/search/fake_search_api.dart';
import 'package:bilifast/search/search_glyphs.dart';
import 'package:bilifast/settings/font_store.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import '../video/mixed_lines.dart';
import 'feed_fakes.dart';

/// 01's default word, long enough to be cut short.
const _word = '爆了！崩铁4.7即将赠送限五！孩子们快来领取';

/// 首页 as KaiC's iPhone draws it, under the system font, against 01's measures (px / 3). With BILIFAST_SHOTS naming a
/// folder outside the repo, the 3× shot is saved there for tools/screen_diff.py.
void main() {
  testWidgets('首页 under the system font: the top row and the bottom bar where 01 has them', (tester) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester);

    final http = FeedHttp()
      ..pages[1] = [
        feedItem('BV1aaa', title: '猫猫为亚运会加油', reason: '1万点赞'),
        feedItem('BV1bbb', title: '海底捞过生日？这里弟子各有喜怒哀乐'),
        feedItem('BV1ccc', title: '荣荣猜你左手拿的是手机'),
        feedItem('BV1ddd', title: '超震撼的 8K 视频用于 OLED 显示测试'),
      ];
    final logger = Logger(session: 'test');
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(StoredCookies(Canned.cookies)),
      http: http,
      logger: logger,
    );
    await environment.refreshAccount();
    final playback = AppPlayback(() => throw StateError('no playback here'));
    addTearDown(playback.dispose);
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      fonts: FontStore.memory()..select(FontChoice.system),
      searchApi: FakeSearchApi(defaultWord: _word),
    );
    BiliFonts.family = BiliFonts.system;
    const screen = ValueKey('screen');
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => RepaintBoundary(
          key: screen,
          child: AppScope(services: services, child: child!),
        ),
        home: const HomePage(),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final avatar = tester.getRect(find.byKey(const ValueKey('home-avatar')));
    final field = tester.getRect(find.byKey(const ValueKey('home-search')));
    expect(avatar.center.dy, 84);
    expect(field, const Rect.fromLTRB(64, 67, 364, 101));
    // 01 measures them from the rim's outer edge: the rim insets nothing.
    final magnifier = tester.getRect(
      find.descendant(of: find.byKey(const ValueKey('home-search')), matching: find.byType(SearchGlyphIcon)),
    );
    expect(magnifier.center.dx, moreOrLessEquals(field.left + HomeTabBarTheme.fieldGlyphCentre));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('home-search-word'))).dx,
      moreOrLessEquals(field.left + HomeTabBarTheme.fieldTextStart),
    );

    final bar = tester.getRect(find.byType(HomeTabBar));
    expect(bar.top, 873);
    expect(bar.bottom, 956);
    for (final (i, tab) in HomeTab.values.indexed) {
      final slot = tester.getRect(find.byKey(ValueKey('home-tab-${tab.name}')));
      expect(slot.center.dx, 44 + 88.0 * i);
    }

    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(screen), '$shots/01-home-ours.png');
  });
}
