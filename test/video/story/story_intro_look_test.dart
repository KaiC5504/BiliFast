import 'dart:io';

import 'package:bili_core/api.dart' show DescPart, VideoCard, VideoDetail, VideoOwner, VideoStat;
import 'package:bilifast/shared/cover_placeholder.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/intro/intro_tab.dart';
import 'package:bilifast/video/story/story_intro.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/look_alike.dart';
import '../../support/stand_in_fonts.dart';
import '../mixed_lines.dart' show appTheme;

/// The 竖屏 sheet's 简介 under the system font, on the sheet's white where 265, 269 and 271 put it (the half sheet's
/// top less its header), with their titles, counts and related cards; covers are the loading grey. With
/// BILIFAST_SHOTS naming a folder outside the repo, the 3× shots are saved there for tools/screen_diff.py.
const _top = StorySheetTheme.halfTop + StorySheetTheme.headerHeight;

int _unix(int year, int month, int day, int hour, int minute) =>
    DateTime(year, month, day, hour, minute).millisecondsSinceEpoch ~/ 1000;

VideoDetail _detail({
  required String bvid,
  required String title,
  required String desc,
  required int views,
  required int danmaku,
  required int pubdate,
}) => VideoDetail(
  bvid: bvid,
  aid: 1,
  title: title,
  cover: '',
  pubdate: pubdate,
  duration: 60,
  desc: desc,
  descParts: [if (desc.isNotEmpty) DescPart(text: desc)],
  copyright: 1,
  owner: const VideoOwner(mid: 1, name: 'UP', face: ''),
  stat: VideoStat(view: views, danmaku: danmaku, reply: 98, favorite: 0, coin: 0, share: 0, like: 0),
  pages: const [],
  season: null,
  staff: const [],
  width: 1080,
  height: 1920,
  honor: null,
  redirectURL: null,
);

final _upright = _detail(
  bvid: 'BV1jzxz6gEYu',
  title: '伊森锐评小羊崽技术：这次真像本人打的！',
  desc: '-',
  views: 60000,
  danmaku: 109,
  pubdate: _unix(2026, 10, 31, 12, 6),
);

final _wide = _detail(
  bvid: 'BV17PjyzjECX',
  title: '【cxy】表哥看小羊崽第一视角 感觉她微调好快啊但是怎么一直瞄脚?',
  desc: '',
  views: 125000,
  danmaku: 16,
  pubdate: _unix(2025, 5, 29, 15, 20),
);

VideoCard _card(int index, String title, String owner, int views, int danmaku, int duration) => VideoCard(
  aid: index,
  bvid: 'BV$index',
  cid: index,
  title: title,
  cover: '',
  duration: duration,
  ownerMid: index,
  ownerName: owner,
  views: views,
  danmaku: danmaku,
  likes: 0,
);

List<VideoCard> _related({required bool wide}) => [
  _card(0, '是小羊崽赢了，还是伊森输了', '小阿飞的日常', 151000, 5, 41),
  _card(1, '小羊崽爆了！被队友搞怪当众喊妈！一脸惊讶害羞，脸都红了，太可爱了', '瓦罗兰特的王', 19000, 3, 38),
  _card(2, '小羊崽的自证', 'Kelete_JY', 183000, 5, 24),
  if (wide)
    _card(3, '小羊崽又爆了，罕见的展示小羊蹄和小羊爪爪、甚至还比耶，太可爱了', '瓦罗兰特的王', 39000, 1, 27)
  else
    _card(3, '【大东彦】评价修炼一年归来的小羊崽视角，有预瞄了，但是还差一点', '不会枪的lansir', 436000, 22, 32),
  for (var i = 4; i < 14; i++) _card(i, '小羊崽的自证', '小阿飞的日常', 10000, 1, 30),
  _card(14, '网络人物志第266期：小羊崽', '人物记录馆', 77000, 16, 117),
  _card(15, '小羊崽三机位直播十万人观看，荔枝破防', '蘑菇啊', 276000, 18, 37),
  _card(16, '唯一塌的在道歉，真正塌的百万撤离了', '麓麓爱玩游戏', 135000, 2, 30),
  _card(17, '小羊崽再次展现小羊蹄，给大家看自己的手指，称自己也很喜欢', '瓦罗兰特的王', 102000, 4, 20),
  _card(18, '小羊崽还是太有实力了', '栗子游戏说', 107000, 4, 29),
  _card(19, '【无畏契约】【小羊崽事件】众主播对小羊崽的操作提出质疑，你怎么看', 'FPS蛋舰长', 498000, 329, 371),
];

void main() {
  Future<ScrollController> render(WidgetTester tester, VideoDetail detail, {required bool wide}) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester);
    BiliFonts.family = BiliFonts.system;
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => RepaintBoundary(
          key: const ValueKey('screen'),
          child: MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
        ),
        home: Material(
          color: BiliColors.card,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: _top,
                bottom: 0,
                child: PrimaryScrollController(
                  controller: scroll,
                  child: StoryIntro(
                    content: IntroContent(
                      detail: detail,
                      related: _related(wide: wide),
                    ),
                    onOpenRelated: (_) {},
                    onSeek: (_) {},
                    onOpenVideo: (_) {},
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      final context = tester.element(find.byType(StoryIntro));
      for (final asset in [
        'assets/images/card/stat_play.png',
        'assets/images/card/stat_danmaku.png',
        'assets/images/card/up_badge.png',
        CoverPlaceholder.asset,
      ]) {
        await precacheImage(AssetImage(asset), context);
      }
    });
    await tester.pumpAndSettle();
    return scroll;
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('screen')), '$shots/$name.png');
  }

  Rect cover(WidgetTester tester, int index) => tester.getRect(
    find.descendant(of: find.byKey(ValueKey(('story-related', index))), matching: find.byType(ClipRRect)),
  );

  testWidgets('265: the first row of covers 12 pt in, 203 × 114.33, 9 apart, 523.67 pt down', (tester) async {
    await render(tester, _upright, wide: false);
    await shoot(tester, '265-ours');
    expect(cover(tester, 0).left, 12);
    expect(cover(tester, 0).width, 203);
    expect(cover(tester, 0).height, moreOrLessEquals(343 / 3));
    expect(cover(tester, 1).left, 224);
    expect(cover(tester, 0).top, moreOrLessEquals(1571 / 3, epsilon: 0.34));
    expect(cover(tester, 2).top - cover(tester, 0).top, moreOrLessEquals(190));
  });

  testWidgets('269: a two-line title and no description, the first covers 520.67 pt down', (tester) async {
    await render(tester, _wide, wide: true);
    await shoot(tester, '269-ours');
    expect(cover(tester, 0).top, moreOrLessEquals(1562 / 3, epsilon: 0.34));
  });

  testWidgets('271: scrolled to the end, 相关视频 pinned under the tab row and 已经到底了… under the last row', (tester) async {
    final scroll = await render(tester, _upright, wide: false);
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    await shoot(tester, '271-ours');
    final heading = tester.getRect(find.byKey(const ValueKey('story-intro-heading')));
    expect(heading.bottom, moreOrLessEquals(1226 / 3));
    expect(cover(tester, 18).top, moreOrLessEquals(2100 / 3, epsilon: 0.34));
    expect(
      tester.getCenter(find.byKey(const ValueKey('story-intro-end'))).dy,
      moreOrLessEquals(2718 / 3, epsilon: 0.34),
    );
  });
}
