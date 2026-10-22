import 'package:bili_core/api.dart';
import 'package:bilifast/favourites/fake_favourites_api.dart';
import 'package:bilifast/favourites/folder_page.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:bilifast/space/own/own_home_tab.dart';
import 'package:bilifast/space/own/own_tab_cards.dart';
import 'package:bilifast/space/own/own_tab_glyphs.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'own_tabs_support.dart';

OwnSpace _full({bool hidden = true}) => OwnSpace(
  favourites: SpaceSection(
    count: 2,
    hidden: hidden,
    items: [
      ownFolder(0, title: '默认收藏夹'),
      ownFolder(1, title: '测试私密', count: 8, isPrivate: true, cover: 'https://i0.hdslb.com/bfs/test/cover.jpg'),
    ],
  ),
  bangumi: SpaceSection(count: 5, hidden: hidden, items: [for (var i = 0; i < 5; i++) ownBangumi(i)]),
  coins: SpaceSection(
    count: 2,
    hidden: hidden,
    items: [ownVideo(0, play: 37000, danmaku: 0, duration: 12), ownVideo(1, play: 285000, danmaku: 232, duration: 21)],
  ),
  likes: SpaceSection(count: 2, hidden: hidden, items: [ownVideo(2), ownVideo(3)]),
  garbs: SpaceSection(
    count: 2,
    hidden: hidden,
    items: const [
      SpaceGarbCard(title: '测试装扮 一', image: '', fansNumber: 'NO.000001'),
      SpaceGarbCard(title: '测试装扮 二', image: ''),
    ],
  ),
  garbTotal: 7779,
);

void main() {
  late List<SpaceTabKind> more;
  late List<VideoRoute> opened;

  setUp(() {
    more = [];
    opened = [];
  });

  Future<void> show(WidgetTester tester, OwnSpace? own, {FakeFavouritesApi? favourites}) async {
    final services = await ownTabServices(favouritesApi: favourites);
    await pumpOwnTab(
      tester,
      services,
      OwnHomeSliver(profile: ownProfile(own), onMore: more.add, open: (context, route) => opened.add(route)),
    );
    await settle(tester);
  }

  Finder section(String name) => find.byKey(ValueKey('own-home-section-$name'), skipOffstage: false);

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
    await settle(tester, 4);
  }

  testWidgets('draws every section in 114 and 115’s order, each title with its count', (tester) async {
    await show(tester, _full());
    final names = ['favourites', 'bangumi', 'coins', 'likes', 'garbs'];
    final tops = [for (final name in names) tester.getTopLeft(section(name)).dy];
    expect(tops, orderedEquals([...tops]..sort()));
    for (final title in ['收藏', '追番', '最近投币的视频', '最近点赞的视频', '拥有的个性装扮']) {
      expect(find.text(title, skipOffstage: false), findsOneWidget);
    }
    String count(String name) =>
        tester.widget<Text>(find.byKey(ValueKey('own-home-count-$name'), skipOffstage: false)).data!;
    expect(count('favourites'), '2');
    expect(count('bangumi'), '5');
    expect(count('garbs'), '2/7779');
    expect(find.byKey(const ValueKey('own-home-count-coins'), skipOffstage: false), findsNothing);
    expect(find.byKey(const ValueKey('own-home-count-likes'), skipOffstage: false), findsNothing);
    expect(find.text('我的游戏', skipOffstage: false), findsNothing);
  });

  testWidgets('a hidden section draws the eye-slash after its title, a shown one none', (tester) async {
    await show(tester, _full());
    for (final name in ['favourites', 'bangumi', 'coins', 'likes', 'garbs']) {
      expect(find.byKey(ValueKey('own-home-eye-$name'), skipOffstage: false), findsOneWidget, reason: name);
    }
    expect(find.byType(HiddenEye, skipOffstage: false), findsNWidgets(5));

    await show(tester, _full(hidden: false));
    expect(find.byType(HiddenEye, skipOffstage: false), findsNothing);
  });

  testWidgets('the eye-slash sits after the count, or after a title without one', (tester) async {
    await show(tester, _full());
    final count = tester.getRect(find.byKey(const ValueKey('own-home-count-favourites')));
    final eye = tester.getRect(find.byKey(const ValueKey('own-home-eye-favourites')));
    expect(eye.left, moreOrLessEquals(count.right + OwnSpaceTabsTheme.eyeGap, epsilon: 0.01));
    expect(eye.center.dy, moreOrLessEquals(count.center.dy, epsilon: 0.01));
    final title = tester.getRect(find.text('最近投币的视频', skipOffstage: false));
    final coinsEye = tester.getRect(find.byKey(const ValueKey('own-home-eye-coins'), skipOffstage: false));
    expect(coinsEye.left, moreOrLessEquals(title.right + 9, epsilon: 0.01));
  });

  testWidgets('a section with nothing to show is left out, whatever its count', (tester) async {
    await show(
      tester,
      OwnSpace(
        favourites: const SpaceSection(count: 3),
        bangumi: SpaceSection(count: 1, items: [ownBangumi(0)]),
        coins: const SpaceSection(count: 4),
        likes: SpaceSection(items: [ownVideo(0)]),
        garbs: const SpaceSection(count: 2),
        garbTotal: 10,
      ),
    );
    expect(section('favourites'), findsNothing);
    expect(section('coins'), findsNothing);
    expect(section('garbs'), findsNothing);
    expect(section('bangumi'), findsOneWidget);
    expect(section('likes'), findsOneWidget);
  });

  testWidgets('no own extras draws no section', (tester) async {
    await show(tester, null);
    for (final name in ['favourites', 'bangumi', 'coins', 'likes', 'garbs']) {
      expect(section(name), findsNothing);
    }
  });

  testWidgets('each section draws one row: 2 folders, 3 posters, 2 videos, 3 装扮', (tester) async {
    await show(
      tester,
      OwnSpace(
        favourites: SpaceSection(count: 9, items: [for (var i = 0; i < 4; i++) ownFolder(i)]),
        bangumi: SpaceSection(count: 9, items: [for (var i = 0; i < 6; i++) ownBangumi(i)]),
        coins: SpaceSection(count: 9, items: [for (var i = 0; i < 4; i++) ownVideo(i)]),
        likes: SpaceSection(count: 9, items: [for (var i = 10; i < 13; i++) ownVideo(i)]),
        garbs: SpaceSection(
          count: 9,
          items: [for (var i = 0; i < 5; i++) SpaceGarbCard(title: '测试装扮 $i', image: '')],
        ),
        garbTotal: 99,
      ),
    );
    expect(find.byType(OwnFolderCard, skipOffstage: false), findsNWidgets(2));
    expect(find.byType(OwnPoster, skipOffstage: false), findsNWidgets(3));
    expect(find.byType(OwnVideoCard, skipOffstage: false), findsNWidgets(4));
    expect(find.byType(OwnGarbCard, skipOffstage: false), findsNWidgets(3));
  });

  testWidgets('cards sit two and three a row across the gutters', (tester) async {
    await show(tester, _full());
    final first = tester.getRect(find.byKey(const ValueKey('own-home-folder-100')));
    final second = tester.getRect(find.byKey(const ValueKey('own-home-folder-101')));
    expect(first.left, 12);
    expect(first.width, 203);
    expect(first.height, 173);
    expect(second.left, 225);
    expect(second.right, 428);
    final posters = [for (var i = 0; i < 3; i++) tester.getRect(find.byKey(ValueKey('own-home-poster-${800 + i}')))];
    expect(posters.map((rect) => rect.left), [
      12,
      moreOrLessEquals(154.67, epsilon: 0.01),
      moreOrLessEquals(297.33, epsilon: 0.01),
    ]);
    expect(posters.first.height, moreOrLessEquals(175, epsilon: 0.01));
    // The first header's line centred 22 down, the cards 22.5 under it.
    expect(tester.getCenter(find.text('收藏')).dy, moreOrLessEquals(22, epsilon: 0.01));
    expect(first.top, 44.5);
  });

  testWidgets('a folder card: its title and line, the TV without a cover, the picture with one', (tester) async {
    await show(tester, _full());
    expect(find.text('默认收藏夹'), findsOneWidget);
    expect(find.text('0个内容 · 公开'), findsOneWidget);
    expect(find.text('8个内容 · 私密'), findsOneWidget);
    final empty = find.byKey(const ValueKey('own-home-folder-100'));
    final covered = find.byKey(const ValueKey('own-home-folder-101'));
    expect(find.descendant(of: empty, matching: find.byType(CoverTv)), findsOneWidget);
    expect(
      tester.widget<RemoteImage>(find.descendant(of: covered, matching: find.byType(RemoteImage))).url,
      'https://i0.hdslb.com/bfs/test/cover.jpg',
    );
    expect(find.descendant(of: empty, matching: find.byType(FolderStackBadge)), findsOneWidget);
    expect(find.descendant(of: covered, matching: find.byType(FolderStackBadge)), findsOneWidget);
  });

  testWidgets('a video card: ▶ plays, danmaku and the length as 115 words them', (tester) async {
    await show(tester, _full());
    final card = find.byKey(const ValueKey('own-home-coins-BV1owntest1'), skipOffstage: false);
    await reveal(tester, card);
    expect(find.descendant(of: card, matching: find.text('28.5万')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('232')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('0:21')), findsOneWidget);
    final first = find.byKey(const ValueKey('own-home-coins-BV1owntest0'));
    expect(find.descendant(of: first, matching: find.text('3.7万')), findsOneWidget);
    expect(find.descendant(of: first, matching: find.text('0:12')), findsOneWidget);
  });

  test('the length leaves the minutes unpadded', () {
    expect(ownClock(12), '0:12');
    expect(ownClock(725), '12:05');
    expect(ownClock(3723), '1:02:03');
    expect(ownClock(-4), '0:00');
  });

  testWidgets('a 装扮 card draws its NO. in a pill only when it has one', (tester) async {
    await show(tester, _full());
    await reveal(tester, find.byKey(const ValueKey('own-home-garb-1'), skipOffstage: false));
    final numbered = find.byKey(const ValueKey('own-home-garb-0'));
    final plain = find.byKey(const ValueKey('own-home-garb-1'));
    expect(find.descendant(of: numbered, matching: find.text('NO.000001')), findsOneWidget);
    expect(find.descendant(of: numbered, matching: find.byKey(const ValueKey('own-garb-number'))), findsOneWidget);
    expect(find.descendant(of: plain, matching: find.byKey(const ValueKey('own-garb-number'))), findsNothing);
  });

  testWidgets('a folder card opens its folder', (tester) async {
    final favourites = FakeFavouritesApi(folders: [favFolder(1, count: 8, isPrivate: true, title: '测试私密')]);
    await show(tester, _full(), favourites: favourites);
    await tester.tap(find.byKey(const ValueKey('own-home-folder-101')));
    await settle(tester, 20);
    final page = tester.widget<FolderPage>(find.byType(FolderPage));
    expect(page.folder.id, 101);
    expect(page.folder.title, '测试私密');
    expect(page.folder.isPrivate, isTrue);
    expect(page.api, same(favourites));
  });

  testWidgets('a video card opens its video', (tester) async {
    await show(tester, _full());
    final card = find.byKey(const ValueKey('own-home-likes-BV1owntest3'), skipOffstage: false);
    await reveal(tester, card);
    await tester.tap(card);
    await settle(tester);
    expect(opened.map((route) => route.bvid), ['BV1owntest3']);
    expect(opened.single.title, '测试视频 3');
  });

  testWidgets('收藏’s 更多 goes to 收藏, 追番’s to 追番; the other 更多 say 暂未开放', (tester) async {
    await show(tester, _full());
    await tester.tap(find.byKey(const ValueKey('own-home-more-favourites')));
    await tester.tap(find.byKey(const ValueKey('own-home-more-bangumi')));
    await settle(tester);
    expect(more, [SpaceTabKind.favourite, SpaceTabKind.bangumi]);

    for (final name in ['coins', 'likes', 'garbs']) {
      final button = find.byKey(ValueKey('own-home-more-$name'), skipOffstage: false);
      await reveal(tester, button);
      await tester.tap(button);
      await settle(tester, 2);
      expect(find.text('暂未开放'), findsOneWidget, reason: name);
      await toastGone(tester);
    }
    expect(more, [SpaceTabKind.favourite, SpaceTabKind.bangumi]);
  });

  testWidgets('a poster and a 装扮 card say 暂未开放', (tester) async {
    await show(tester, _full());
    await tester.tap(find.byKey(const ValueKey('own-home-poster-801')));
    await settle(tester, 2);
    expect(find.text('暂未开放'), findsOneWidget);
    await toastGone(tester);

    final garb = find.byKey(const ValueKey('own-home-garb-0'), skipOffstage: false);
    await reveal(tester, garb);
    await tester.tap(garb);
    await settle(tester, 2);
    expect(find.text('暂未开放'), findsOneWidget);
    await toastGone(tester);
    expect(opened, isEmpty);
    expect(more, isEmpty);
  });

  testWidgets('the eye-slash is drawn, not pressed', (tester) async {
    await show(tester, _full());
    final eye = find.byKey(const ValueKey('own-home-eye-favourites'));
    expect(find.ancestor(of: eye, matching: find.byType(GestureDetector)), findsNothing);
  });

  testWidgets('the page’s grey runs on to the screen’s bottom under a short 主页', (tester) async {
    await show(tester, OwnSpace(likes: SpaceSection(items: [ownVideo(0)])));
    final fill = find.descendant(of: find.byType(SliverFillRemaining), matching: find.byType(SizedBox));
    expect(tester.getRect(fill).bottom, 956);
    expect(tester.getRect(fill).height, greaterThan(0));
    final decorated = tester.widget<DecoratedSliver>(find.byType(DecoratedSliver));
    expect((decorated.decoration as BoxDecoration).color, const Color(0xFFF6F7F8));
  });
}
