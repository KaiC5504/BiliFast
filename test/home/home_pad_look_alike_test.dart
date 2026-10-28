import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/phone_frame.dart';
import 'package:bilifast/home/home_tab_bar.dart';
import 'package:bilifast/home/main_shell.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/search/fake_search_api.dart';
import 'package:bilifast/settings/font_store.dart';
import 'package:bilifast/shared/cover_placeholder.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import '../video/mixed_lines.dart';
import 'feed_fakes.dart';

/// 02's search word, cut short upright and whole sideways.
const _word = '星之海传说森林之歌pc';

const _screen = ValueKey('screen');

/// A web feed row with the uploader's face and a date, as 01's and 02's cards show them.
Map<String, Object?> _row(String bvid, String title, {String? reason, int daysAgo = 1}) => {
  ...feedItem(bvid, title: title, reason: reason),
  'title': title,
  'owner': {'mid': 7, 'name': '山顶小松鼠', 'face': 'https://i0.hdslb.com/bfs/face/$bvid.jpg'},
  'pubdate': DateTime.now().subtract(Duration(days: daysAgo)).millisecondsSinceEpoch ~/ 1000,
};

FeedHttp _feed() => FeedHttp()
  ..pages[1] = [
    _row('BV1aaa', '小猫们找朋友大会：深林山洞篇【AI全城创作者】'),
    _row('BV1bbb', '【插件制作】我的PC小人走到屏幕上了！！', reason: '2万点赞', daysAgo: 6),
    _row('BV1ccc', 'ABC官方合作联名游戏【足球男孩：奔向远方】，遇见快乐赛场！'),
    _row('BV1ddd', '设计者：小游戏作者甲 设计作品', daysAgo: 3),
    _row('BV1eee', '狂写千行codes，我在电脑上做出了Capella......'),
    _row('BV1fff', '【回看2023】老歌再听日记'),
    _row('BV1ggg', '准备好走进探索森林的旅程了吗？'),
    _row('BV1hhh', '中秋节有8个礼物领取点，不要忘记拿礼物哦。'),
    _row('BV1iii', '小明哥的超级侠本领到底有多大？太酷了'),
  ];

/// 首页 at the iPad's size under the system font, its feed answered by [http], inside a boundary keyed [_screen].
Future<void> _showHome(WidgetTester tester, FeedHttp http, {required bool landscape}) async {
  final saved = BiliFonts.family;
  addTearDown(() => BiliFonts.family = saved);
  await tester.runAsync(loadSystemFontStandIns);
  showAsPad(tester, landscape: landscape);
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
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      builder: (context, child) => RepaintBoundary(
        key: _screen,
        child: AppScope(services: services, child: child!),
      ),
      home: const MainShell(),
    ),
  );
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  final context = tester.element(find.byType(MainShell));
  await tester.runAsync(
    () => Future.wait([
      for (final asset in [
        DefaultAvatar.asset,
        CoverPlaceholder.asset,
        'assets/images/card/stat_play.png',
        'assets/images/card/stat_danmaku.png',
        for (final tab in PadTab.values) ...[tab.art(selected: false), tab.art(selected: true)],
      ])
        precacheImage(AssetImage(asset), context),
    ]),
  );
  await tester.pump();
}

Rect _rect(WidgetTester tester, String key) => tester.getRect(find.byKey(ValueKey(key)));

/// 首页 as KaiC's iPad draws it, under the system font, against ipad/01's and 02's measures (px / 2). With
/// BILIFAST_SHOTS naming a folder outside the repo, the 2× shots are saved there for tools/screen_diff.py.
void main() {
  for (final landscape in [true, false]) {
    final shot = landscape ? '01-home-landscape' : '02-home-portrait';
    final width = landscape ? PhoneFrame.padLandscape.width : PhoneFrame.padPortrait.width;
    final card = landscape ? 375.0 : 255.0;
    final cover = landscape ? 212.0 : 145.0;

    testWidgets('$shot: the top row, three columns of $card pt cards and the bar where the iPad has them', (
      tester,
    ) async {
      await _showHome(tester, _feed(), landscape: landscape);

      expect(_rect(tester, 'home-avatar'), const Rect.fromLTWH(20, 25, 40, 40));
      final field = _rect(tester, 'home-search');
      expect(field.left, 75);
      expect(field.top, 30);
      expect(field.height, 30);
      expect(field.right, lessThanOrEqualTo(width / 2 - 162.5 - 40), reason: 'it stops 40 pt short of the tabs');
      expect(_rect(tester, 'home-tab-recommend').center.dx, moreOrLessEquals(width / 2 - 65, epsilon: 0.5));
      expect(_rect(tester, 'home-history').center, Offset(width - 90, 45));
      expect(tester.getRect(find.byType(Divider).first).top, 69.5);

      final first = _rect(tester, 'feed-card-BV1aaa');
      final second = _rect(tester, 'feed-card-BV1bbb');
      final third = _rect(tester, 'feed-card-BV1ccc');
      final fourth = _rect(tester, 'feed-card-BV1ddd');
      expect(first.left, 22);
      expect(first.width, card);
      expect(second.left - first.right, 12);
      expect(third.right, width - 23, reason: 'whole-point cards, the odd point left at the right');
      expect(fourth.left, 22, reason: 'the fourth card starts the second row');
      expect(first.top, 88);
      expect(fourth.top - first.top, cover + 99);

      final bar = tester.getRect(find.byType(HomeTabBar));
      expect(bar.top, (landscape ? 834 : 1194) - 20 - 50);
      for (final (i, tab) in PadTab.values.indexed) {
        expect(_rect(tester, 'home-tab-${tab.key}').center.dx, width / 2 - 177 + 118.0 * i);
      }

      final shots = Platform.environment['BILIFAST_SHOTS'];
      if (shots != null) await saveShot(tester, find.byKey(_screen), '$shots/pad-$shot-ours.png', pixelRatio: 2);
    });
  }

  testWidgets('turning the iPad reflows 推荐 at once: 375 pt cards sideways, 255 upright, three to a row both ways', (
    tester,
  ) async {
    await _showHome(tester, _feed(), landscape: true);
    expect(_rect(tester, 'feed-card-BV1aaa').width, 375);
    showAsPad(tester);
    await tester.pump();
    expect(_rect(tester, 'feed-card-BV1aaa').width, 255);
    expect(_rect(tester, 'feed-card-BV1ddd').left, 22);
    showAsPad(tester, landscape: true);
    await tester.pump();
    expect(_rect(tester, 'feed-card-BV1aaa').width, 375);
    expect(_rect(tester, 'feed-card-BV1ddd').left, 22);
  });
}
