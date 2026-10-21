import 'dart:io';

import 'package:bili_core/api.dart' hide RichText;
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/space/fake_space_api.dart';
import 'package:bilifast/space/space_video_menu.dart';
import 'package:bilifast/space/space_videos.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import '../search/results/results_support.dart';
import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import '../video/mixed_lines.dart' show appTheme;

// Its own file: the stand-ins replace Roboto and the Cupertino families for every later test in the isolate.

/// Where 69's and 70's tab row ends (its hairline's bottom), so where the list starts.
const _top69 = 1234 / 3;
const _top70 = 1390 / 3;

SpaceVideo _video(
  int i,
  String title, {
  required int duration,
  required int play,
  required int danmaku,
  required String date,
  List<String> badges = const [],
}) => SpaceVideo(
  aid: 7000 + i,
  bvid: 'BV1look$i',
  title: title,
  cover: '',
  duration: duration,
  play: play,
  danmaku: danmaku,
  publishedText: date,
  badges: badges,
);

// Made-up rows shaped like 69's and 70's: the same lengths, scripts and punctuation, so lines break where theirs do.
final _rows69 = [
  _video(1, '“我们的生活和天气一样总是变来变去”', duration: 28, play: 776000, danmaku: 1120, date: '5月25日'),
  _video(2, '“这是一个你只能在这里看到的作品！！”', duration: 82, play: 432000, danmaku: 431, date: '1月19日'),
  _video(3, '“一次走过三千里的旅程”', duration: 22, play: 294000, danmaku: 89, date: '6月8日'),
  _video(
    4,
    // 69 breaks after the second "，": iOS draws a full-width comma narrower than Flutter does, so ours is a glyph
    // shorter to break there too.
    '“太远了，路边的花已经开了，我想说的是，我不在了你也要好好生活 ”',
    duration: 28,
    play: 253000,
    danmaku: 173,
    date: '6月4日',
  ),
  _video(5, '“自在这一刻”', duration: 28, play: 227000, danmaku: 46, date: '6月15日', badges: const ['合作']),
];

final _rows70 = [
  _video(1, 'landscape风景推荐【山与海】篇', duration: 114, play: 605, danmaku: 8, date: '1小时前'),
  _video(2, 'landscape风景推荐【南方城】篇', duration: 96, play: 1736, danmaku: 21, date: '7小时前'),
  _video(3, 'landscape风景推荐【白雪日落】篇', duration: 94, play: 5240, danmaku: 223, date: '昨天 21:00'),
  _video(4, 'landscape风景推荐【东方明】篇', duration: 104, play: 5206, danmaku: 61, date: '昨天 15:00'),
  _video(5, 'landscape风景推荐【北方星】篇', duration: 99, play: 3100, danmaku: 40, date: '昨天 09:00'),
];

/// 投稿 as KaiC's iPhone draws it, under the system font, against 69's, 70's and 74's measures (px / 3). With
/// BILIFAST_SHOTS naming a folder outside the repo, the 3× shots are saved there for tools/screen_diff.py.
void main() {
  Future<void> show(
    WidgetTester tester, {
    required double top,
    required SpaceProfile profile,
    required List<SpaceVideo> rows,
  }) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    // The services' font store puts MiSans back, so the system font comes after them.
    final AppServices services = await resultServices(loggedIn: true, api: FakePageApi());
    BiliFonts.family = BiliFonts.system;
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, page) => RepaintBoundary(
          key: const ValueKey('shot'),
          child: AppScope(services: services, child: page!),
        ),
        home: Scaffold(
          backgroundColor: BiliColors.card,
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: top)),
              SpaceVideosSliver(
                profile: profile,
                api: FakeSpaceApi(videoList: rows),
              ),
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

  testWidgets('69: six chips, 最多播放 and the rows where 69 has them', (tester) async {
    await show(
      tester,
      top: _top69,
      profile: const SpaceProfile(
        mid: 1,
        name: '测试UP主',
        face: '',
        orders: [SpaceOrder.mostPlayed, SpaceOrder.latest],
        chips: [
          SpaceChip(kind: SpaceChipKind.video, title: '视频'),
          SpaceChip(kind: SpaceChipKind.article, title: '图文'),
          SpaceChip(kind: SpaceChipKind.season, title: '旅行', seasonId: 1),
          SpaceChip(kind: SpaceChipKind.season, title: '音乐', seasonId: 2),
          SpaceChip(kind: SpaceChipKind.season, title: '游戏', seasonId: 3),
          SpaceChip(kind: SpaceChipKind.series, title: '动画剪辑', seriesId: 4),
        ],
      ),
      rows: _rows69,
    );
    await shoot(tester, '69-space-videos-ours');

    final chip = tester.getRect(find.byKey(const ValueKey('space-chip-0')));
    expect(chip.top, closeTo(1253 / 3, 0.01));
    expect(chip.left, 12);
    expect(chip.height, 28);
    expect(chip.width, moreOrLessEquals(131 / 3, epsilon: 0.5));
    expect(tester.getRect(find.byKey(const ValueKey('space-chip-5'))).right, moreOrLessEquals(1087 / 3, epsilon: 1));
    expect(find.text('最多播放'), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const ValueKey('space-row-BV1look1'))).dy + 10, closeTo(1472 / 3, 0.01));
    expect(tester.getTopLeft(find.byKey(const ValueKey('space-row-BV1look2'))).dy + 10, closeTo(1751 / 3, 0.01));
  });

  testWidgets('70: 视频 and a long chip cut short, 最新发布 and the rows where 70 has them', (tester) async {
    await show(
      tester,
      top: _top70,
      profile: const SpaceProfile(
        mid: 1,
        name: '测试UP主',
        face: '',
        chips: [
          SpaceChip(kind: SpaceChipKind.video, title: '视频'),
          SpaceChip(kind: SpaceChipKind.season, title: 'Wallpaper风景推荐合集', seasonId: 1),
        ],
      ),
      rows: _rows70,
    );
    await shoot(tester, '70-space-followed-ours');

    final long = tester.getRect(find.byKey(const ValueKey('space-chip-1')));
    expect(long.left, closeTo(68, 0.34));
    final words = tester.renderObject<RenderParagraph>(
      find.descendant(of: find.byKey(const ValueKey('space-chip-1')), matching: find.byType(RichText)),
    );
    expect(words.didExceedMaxLines, isTrue, reason: 'cut with …');
    // 70's is 119.33; the stand-in's … is a 1 em one where SF's is about 10 pt.
    expect(long.width, lessThanOrEqualTo(SpaceVideosTheme.chipMaxText + 2 * SpaceVideosTheme.chipPadX));
    expect(tester.getTopLeft(find.byKey(const ValueKey('space-row-BV1look1'))).dy + 10, closeTo(1628 / 3, 0.01));
    expect(find.text('最新发布'), findsOneWidget);
  });

  testWidgets('74: the ⋮ popover under the first row’s dots', (tester) async {
    await show(
      tester,
      top: _top70,
      profile: const SpaceProfile(
        mid: 1,
        name: '测试UP主',
        face: '',
        chips: [
          SpaceChip(kind: SpaceChipKind.video, title: '视频'),
          SpaceChip(kind: SpaceChipKind.article, title: '图文'),
          SpaceChip(kind: SpaceChipKind.season, title: '城市夜景', seasonId: 1),
        ],
      ),
      rows: _rows70,
    );
    await tester.tap(find.byKey(const ValueKey('space-more-BV1look1')));
    await settle(tester);
    await shoot(tester, '74-space-video-more-menu-ours');

    final menu = tester.getRect(find.byKey(const ValueKey('space-menu')));
    expect(menu, Rect.fromLTRB(235, 1874 / 3, 435, 1874 / 3 + 104));
    // 74's tip is at 420.83, the dots' centre at 420.
    expect(tester.widget<SpaceVideoMenu>(find.byType(SpaceVideoMenu)).arrowX, closeTo(1262.5 / 3 - 235, 0.01));
  });
}
