import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/favourites/fake_favourites_api.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/space/fake_space_api.dart';
import 'package:bilifast/space/own/own_bangumi_tab.dart';
import 'package:bilifast/space/own/own_contribute_tab.dart';
import 'package:bilifast/space/own/own_favourites_tab.dart';
import 'package:bilifast/space/own/own_home_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/look_alike.dart';
import '../../support/stand_in_fonts.dart';
import '../../video/mixed_lines.dart' show appTheme;
import 'own_tabs_support.dart';

// Its own file: the stand-ins replace Roboto and the Cupertino families for every later test in the isolate.

/// Where 108's and 114-117's tab row ends (its hairline's bottom), so where a tab's body starts.
const _body = 1650.5 / 3;

/// 115 is scrolled: its 最近投币的视频 is centred 451 px down and its 拥有的个性装扮 2205 (after 我的游戏, not built).
const _coinsHeader = 451 / 3;
const _garbsHeader = 2205 / 3;

// Made-up content shaped like KaiC's: the same lengths, scripts and counts, so lines break where theirs do.
final _home114 = OwnSpace(
  favourites: const SpaceSection(
    count: 2,
    hidden: true,
    items: [
      SpaceFolderCard(id: 1, title: '默认收藏夹', cover: '', count: 0, isPrivate: false),
      SpaceFolderCard(id: 2, title: '测试', cover: '', count: 8, isPrivate: true),
    ],
  ),
  bangumi: SpaceSection(
    count: 5,
    hidden: true,
    items: [for (var i = 0; i < 3; i++) SpaceBangumiCard(seasonId: i, title: '演示番剧 $i', cover: '')],
  ),
);

SpaceVideo _video(int i, String title, {required int play, required int danmaku, required int duration}) => SpaceVideo(
  aid: 5000 + i,
  bvid: 'BV1look$i',
  title: title,
  cover: '',
  duration: duration,
  play: play,
  danmaku: danmaku,
);

final _videos115 = [
  _video(1, '测试视频', play: 37000, danmaku: 0, duration: 12),
  _video(2, '测试测试今日穿搭～', play: 285000, danmaku: 232, duration: 21),
];

final _home115 = OwnSpace(
  coins: SpaceSection(count: 2, hidden: true, items: _videos115),
  likes: SpaceSection(count: 2, hidden: true, items: _videos115),
);

const _garbs115 = OwnSpace(
  garbs: SpaceSection(
    count: 2,
    hidden: true,
    items: [
      SpaceGarbCard(title: '演示装扮卡 金牛座', image: ''),
      SpaceGarbCard(title: '演示装扮 不问天', image: ''),
    ],
  ),
  garbTotal: 7779,
);

const _bangumi117 = [
  SpaceBangumiCard(seasonId: 1, title: '演示番 灰色的公主', cover: '', progress: '全23话'),
  SpaceBangumiCard(seasonId: 2, title: '演示番剧 第三季', cover: '', progress: '全13话'),
  SpaceBangumiCard(seasonId: 3, title: '演示番剧 巅峰之路', cover: '', progress: '全4话'),
  SpaceBangumiCard(seasonId: 4, title: '演示番剧', cover: '', progress: '全13话'),
  SpaceBangumiCard(seasonId: 5, title: 'MADEUP to SHOWING the Live', cover: '', progress: '全1话'),
];

/// The own space's tab bodies as KaiC's iPhone draws them, under the system font, against 108's and 114-117's
/// measures (px / 3), each under a blank stand-in for the page's header ending where the tab row does. With
/// BILIFAST_SHOTS naming a folder outside the repo, the 3× shots are saved there for tools/screen_diff.py.
void main() {
  Future<void> show(WidgetTester tester, Widget sliver, {required double top, AppServices? services}) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    // The services' font store puts MiSans back, so the system font comes after them.
    final scope =
        services ??
        await ownTabServices(
          spaceApi: FakeSpaceApi(bangumiList: _bangumi117),
          favouritesApi: FakeFavouritesApi(
            folders: const [
              FavFolder(id: 1, title: '默认收藏夹', count: 0, isPrivate: false, contains: false, isDefault: true),
              FavFolder(id: 2, title: '测试', count: 8, isPrivate: true, contains: false, isDefault: false),
            ],
          ),
        );
    BiliFonts.family = BiliFonts.system;
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, page) => RepaintBoundary(
          key: const ValueKey('shot'),
          child: AppScope(services: scope, child: page!),
        ),
        home: Scaffold(
          backgroundColor: BiliColors.card,
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: top)),
              sliver,
            ],
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('shot')), '$shots/$name.png');
  }

  testWidgets('114: 收藏 and 追番 where 114 has them', (tester) async {
    await show(
      tester,
      OwnHomeSliver(profile: ownProfile(_home114), onMore: (_) {}),
      top: _body,
    );
    await shoot(tester, '114-own-space-home-ours');

    expect(tester.getCenter(find.text('收藏')).dy, moreOrLessEquals(1716.5 / 3, epsilon: 0.34));
    final folder = tester.getRect(find.byKey(const ValueKey('own-home-folder-1')));
    expect(folder.left, 12);
    expect(folder.top, moreOrLessEquals(1784 / 3, epsilon: 0.34));
    expect(folder.bottom, moreOrLessEquals(2302.5 / 3, epsilon: 0.34));
    expect(tester.getRect(find.byKey(const ValueKey('own-home-folder-2'))).left, 675 / 3);
    // The stand-in draws 13 pt Chinese half a point under its line's middle: the line sits that much above 114's ink.
    expect(tester.getCenter(find.text('默认收藏夹')).dy, moreOrLessEquals(2203 / 3 - 0.5, epsilon: 0.34));
    expect(tester.getCenter(find.text('0个内容 · 公开')).dy, moreOrLessEquals(2264 / 3, epsilon: 0.34));
    expect(tester.getCenter(find.text('追番')).dy, moreOrLessEquals(2418 / 3, epsilon: 0.34));
    expect(tester.getTopLeft(find.byKey(const ValueKey('own-home-poster-1'))).dx, 464 / 3);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('own-home-poster-0'))).dy,
      moreOrLessEquals(2485.5 / 3, epsilon: 0.34),
    );
  });

  testWidgets('115: 最近投币的视频 and 最近点赞的视频 where 115 has them', (tester) async {
    await show(
      tester,
      OwnHomeSliver(profile: ownProfile(_home115), onMore: (_) {}),
      top: _coinsHeader - 22,
    );
    await shoot(tester, '115-own-space-videos-ours');

    expect(tester.getCenter(find.text('最近投币的视频')).dy, moreOrLessEquals(_coinsHeader, epsilon: 0.01));
    final card = tester.getRect(find.byKey(const ValueKey('own-home-coins-BV1look1')));
    expect(card.top, moreOrLessEquals(518.5 / 3, epsilon: 0.34));
    expect(card.bottom, moreOrLessEquals(1036.5 / 3, epsilon: 0.34));
    expect(tester.getCenter(find.text('最近点赞的视频')).dy, moreOrLessEquals(1153 / 3, epsilon: 0.34));
    expect(tester.getCenter(find.text('测试视频').first).dy, moreOrLessEquals(937.5 / 3 - 0.67, epsilon: 0.34));
    expect(tester.getCenter(find.text('0:12').first).dy, moreOrLessEquals(860 / 3, epsilon: 0.5));
  });

  testWidgets('115: 拥有的个性装扮 where 115 has it', (tester) async {
    await show(
      tester,
      OwnHomeSliver(profile: ownProfile(_garbs115), onMore: (_) {}),
      top: _garbsHeader - 22,
    );
    await shoot(tester, '115-own-space-garbs-ours');

    expect(tester.getCenter(find.text('拥有的个性装扮')).dy, moreOrLessEquals(_garbsHeader, epsilon: 0.01));
    final first = tester.getRect(find.byKey(const ValueKey('own-home-garb-0')));
    expect(first.left, 12);
    expect(first.width, moreOrLessEquals(130, epsilon: 0.01));
    expect(first.top, moreOrLessEquals(2272.5 / 3, epsilon: 0.34));
    expect(
      tester.getRect(find.byKey(const ValueKey('own-home-garb-1'))).left,
      moreOrLessEquals(465 / 3, epsilon: 0.34),
    );
  });

  testWidgets('116: 我创建的收藏夹 and its rows where 116 has them', (tester) async {
    await show(tester, const OwnFavouritesSliver(mid: ownMid, count: 2), top: _body);
    await shoot(tester, '116-own-space-favourites-ours');

    expect(tester.getCenter(find.text('我创建的收藏夹')).dy, moreOrLessEquals(1723 / 3, epsilon: 0.34));
    final first = tester.getRect(find.byKey(const ValueKey('own-favourites-row-1')));
    expect(first.top, moreOrLessEquals(1834.5 / 3, epsilon: 0.34));
    expect(
      tester.getRect(find.byKey(const ValueKey('own-favourites-row-2'))).top,
      moreOrLessEquals(2089.5 / 3, epsilon: 0.34),
    );
    expect(tester.getCenter(find.text('默认收藏夹')).dy, moreOrLessEquals(1865 / 3, epsilon: 0.34));
    expect(tester.getCenter(find.text('0个内容 · 公开')).dy, moreOrLessEquals(2028 / 3, epsilon: 0.34));
  });

  testWidgets('117: the posters and 再怎么找也没有啦 where 117 has them', (tester) async {
    await show(tester, const OwnBangumiSliver(mid: ownMid), top: _body);
    await shoot(tester, '117-own-space-bangumi-ours');

    final first = tester.getRect(find.byKey(const ValueKey('own-bangumi-1')));
    expect(first.top, moreOrLessEquals(1684.5 / 3, epsilon: 0.34));
    expect(first.bottom, moreOrLessEquals(2209.5 / 3, epsilon: 0.34));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('own-bangumi-4'))).dy,
      moreOrLessEquals(2245.5 / 3, epsilon: 0.34),
    );
    expect(tester.getCenter(find.text('再怎么找也没有啦')).dy, moreOrLessEquals(2834 / 3, epsilon: 0.34));
    expect(tester.getCenter(find.text('全23话')).dy, moreOrLessEquals((2174 + 1.5) / 3, epsilon: 0.34));
  });

  testWidgets('108: 投稿 with no videos where 108 has it', (tester) async {
    await show(tester, OwnContributeSliver(profile: ownProfile(null)), top: _body);
    await shoot(tester, '108-own-space-contribute-ours');

    expect(tester.getCenter(find.text('发布第一个视频，领新人福利')).dy, moreOrLessEquals(2014 / 3 - 0.5, epsilon: 0.34));
    expect(tester.getCenter(find.text('我要投稿')).dy, moreOrLessEquals(2170.5 / 3, epsilon: 0.5));
    expect(tester.getCenter(find.text('去创作中心领奖')).dy, moreOrLessEquals(2328 / 3, epsilon: 0.34));
  });
}
