import 'package:bili_core/api.dart' show DescPart, VideoCard, VideoDetail, VideoOwner, VideoStat;
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/intro/desc_text.dart';
import 'package:bilifast/video/intro/intro_tab.dart';
import 'package:bilifast/video/story/story_intro.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mixed_lines.dart' show appTheme;

const _top = StorySheetTheme.halfTop + StorySheetTheme.headerHeight;

VideoDetail _detail({String title = '伊森锐评小羊崽技术：这次真像本人打的！', List<DescPart> desc = const []}) => VideoDetail(
  bvid: 'BV1jzxz6gEYu',
  aid: 1,
  title: title,
  cover: '',
  pubdate: DateTime(2026, 10, 31, 12, 6).millisecondsSinceEpoch ~/ 1000,
  duration: 60,
  desc: desc.map((part) => part.text).join(),
  descParts: desc,
  copyright: 1,
  owner: const VideoOwner(mid: 1, name: 'UP', face: ''),
  stat: const VideoStat(view: 60000, danmaku: 109, reply: 98, favorite: 0, coin: 0, share: 0, like: 0),
  pages: const [],
  season: null,
  staff: const [],
  width: 1080,
  height: 1920,
  honor: null,
  redirectURL: null,
);

List<VideoCard> _cards(int count) => [
  for (var i = 0; i < count; i++)
    VideoCard(
      aid: i,
      bvid: 'BV$i',
      cid: i,
      title: '相关视频第$i个',
      cover: '',
      duration: 41,
      ownerMid: i,
      ownerName: '小阿飞的日常',
      views: 151000,
      danmaku: 5,
      likes: 0,
    ),
];

Finder _card(int index) => find.byKey(ValueKey(('story-related', index)));

class _Rig {
  final opened = <int>[];
  final seeks = <double>[];
  final videos = <String>[];
  final scroll = ScrollController();

  Future<void> mount(WidgetTester tester, IntroContent content) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(440, 956),
            padding: EdgeInsets.only(top: 62, bottom: 34),
            disableAnimations: true,
          ),
          child: Material(
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
                      content: content,
                      onOpenRelated: opened.add,
                      onSeek: seeks.add,
                      onOpenVideo: videos.add,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }
}

void main() {
  testWidgets('the title wraps in 18 pt medium, 12 in from the left', (tester) async {
    final rig = _Rig();
    const long = '【cxy】表哥看小羊崽第一视角 感觉她微调好快啊但是怎么一直瞄脚?';
    await rig.mount(tester, IntroContent(detail: _detail(title: long)));

    final title = tester.widget<Text>(find.text(long));
    expect(title.maxLines, isNull);
    expect(title.style!.fontSize, StoryIntroTheme.titleText);
    expect(title.style!.fontWeight, StoryIntroTheme.titleWeight);
    expect(title.style!.color, BiliColors.text);
    final box = tester.getRect(find.text(long));
    expect(box.left, BiliMetrics.gutter);
    expect(box.height, moreOrLessEquals(StoryIntroTheme.titleLine * 2, epsilon: 0.5));
    expect(box.top, moreOrLessEquals(_top + StoryIntroTheme.titleTop));
  });

  testWidgets('the stats line: views, danmaku, the date and time and the BV id, in grey, under the title', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.mount(tester, IntroContent(detail: _detail()));

    final stats = find.byKey(const ValueKey('story-intro-stats'));
    final texts = [
      for (final text in tester.widgetList<Text>(find.descendant(of: stats, matching: find.byType(Text)))) text,
    ];
    expect(texts.map((text) => text.data), ['6万', '109', '2026年10月31日 12:06', 'BV1jzxz6gEYu']);
    for (final text in texts) {
      expect(text.style!.color, BiliColors.secondaryText);
    }
    expect(find.descendant(of: stats, matching: find.byType(CustomPaint)), findsNWidgets(2));
    final title = tester.getRect(find.byKey(const ValueKey('story-intro-title')));
    expect(tester.getRect(stats).top, moreOrLessEquals(title.bottom + StoryIntroTheme.statsGap));
  });

  testWidgets('the description draws as the page draws it: timestamps seek, video ids open', (tester) async {
    final rig = _Rig();
    await rig.mount(
      tester,
      IntroContent(
        detail: _detail(desc: const [DescPart(text: '从03:15开始，看 BV1AB411c7mD')]),
      ),
    );

    expect(find.byType(DescriptionText), findsOneWidget);
    final text = tester.widget<Text>(find.descendant(of: find.byType(DescriptionText), matching: find.byType(Text)));
    expect(text.textSpan!.style!.fontSize, IntroTheme.descText);
    expect(text.textSpan!.style!.color, BiliColors.secondaryText);

    await tester.tapOnText(find.textRange.ofSubstring('03:15'));
    await tester.tapOnText(find.textRange.ofSubstring('BV1AB411c7mD'));
    expect(rig.seeks, [195]);
    expect(rig.videos, ['BV1AB411c7mD']);
  });

  testWidgets('no description leaves nothing between the stats and 相关视频', (tester) async {
    final rig = _Rig();
    await rig.mount(tester, IntroContent(detail: _detail(), related: _cards(4)));

    expect(find.byType(DescriptionText), findsNothing);
    final stats = tester.getRect(find.byKey(const ValueKey('story-intro-stats')));
    final heading = tester.getRect(find.byKey(const ValueKey('story-intro-heading')));
    expect(heading.top, moreOrLessEquals(stats.bottom + StoryIntroTheme.headingGap));
  });

  testWidgets('相关视频 shows at most 20 cards, two to a row, from the related list in order', (tester) async {
    final rig = _Rig();
    await rig.mount(tester, IntroContent(detail: _detail(), related: _cards(25)));

    expect(find.text('相关视频'), findsOneWidget);
    expect(tester.getRect(_card(0)).left, StoryIntroTheme.gridInset);
    expect(tester.getRect(_card(1)).left, StoryIntroTheme.gridInset + 203 + StoryIntroTheme.gridGap);
    expect(tester.getRect(_card(1)).top, tester.getRect(_card(0)).top);
    expect(find.text('相关视频第0个'), findsOneWidget);
    expect(find.text('相关视频第1个'), findsOneWidget);

    rig.scroll.jumpTo(rig.scroll.position.maxScrollExtent);
    await tester.pump();
    expect(_card(19), findsOneWidget);
    expect(_card(20), findsNothing);
    expect(find.text('相关视频第19个'), findsOneWidget);
    expect(find.text('相关视频第20个'), findsNothing);
  });

  testWidgets('a card shows its counts, duration, title and uploader', (tester) async {
    final rig = _Rig();
    await rig.mount(tester, IntroContent(detail: _detail(), related: _cards(2)));

    final card = _card(0);
    for (final text in ['15.1万', '5', '00:41', '相关视频第0个', '小阿飞的日常']) {
      expect(
        find.descendant(of: card, matching: find.text(text)),
        findsOneWidget,
        reason: text,
      );
    }
    final title = tester.widget<Text>(find.descendant(of: card, matching: find.text('相关视频第0个')));
    expect(title.maxLines, 2);
    expect(title.overflow, TextOverflow.ellipsis);
    final cover = tester.getRect(find.descendant(of: card, matching: find.byType(ClipRRect)));
    // 203 × 9/16 to the whole pixel, at this view's 1 px per pt.
    expect(cover.size, const Size(203, 114));
  });

  testWidgets('a tap on a card opens it by its index in the related list', (tester) async {
    final rig = _Rig();
    await rig.mount(tester, IntroContent(detail: _detail(), related: _cards(20)));

    await tester.tap(_card(1));
    await tester.tap(_card(0));
    rig.scroll.jumpTo(rig.scroll.position.maxScrollExtent);
    await tester.pump();
    await tester.tap(_card(19));
    await tester.tap(_card(18));
    expect(rig.opened, [1, 0, 19, 18]);
  });

  testWidgets('相关视频 stays pinned under the tab row while the grid scrolls under it', (tester) async {
    final rig = _Rig();
    await rig.mount(tester, IntroContent(detail: _detail(), related: _cards(20)));
    final heading = find.byKey(const ValueKey('story-intro-heading'));
    final unpinned = tester.getRect(heading).top;
    expect(unpinned, greaterThan(_top));

    rig.scroll.jumpTo(600);
    await tester.pump();
    expect(tester.getRect(heading).top, _top);
    expect(tester.getRect(heading).height, moreOrLessEquals(StoryIntroTheme.headingExtent));
    expect(
      tester.getRect(find.text('相关视频')).center.dy,
      moreOrLessEquals(_top + StoryIntroTheme.headingCentre, epsilon: 0.5),
    );

    // A card that has scrolled up under the heading is covered by it: a tap there opens nothing.
    final under = Offset(100, _top + StoryIntroTheme.headingExtent / 2);
    final covered = [
      for (var i = 0; i < 20; i++)
        if (_card(i).evaluate().isNotEmpty && tester.getRect(_card(i)).contains(under)) i,
    ];
    expect(covered, hasLength(1));
    await tester.tapAt(under);
    expect(rig.opened, isEmpty);

    rig.scroll.jumpTo(rig.scroll.position.maxScrollExtent);
    await tester.pump();
    expect(tester.getRect(heading).top, _top);
  });

  testWidgets('the list ends with 已经到底了… centred under the last row, clear of the home indicator', (tester) async {
    final rig = _Rig();
    await rig.mount(tester, IntroContent(detail: _detail(), related: _cards(5)));
    rig.scroll.jumpTo(rig.scroll.position.maxScrollExtent);
    await tester.pump();

    final end = find.text('已经到底了…');
    expect(end, findsOneWidget);
    final line = tester.getRect(end);
    expect(line.center.dx, moreOrLessEquals(220));
    final last = tester.getRect(_card(4));
    expect(line.center.dy, moreOrLessEquals(last.bottom + StoryIntroTheme.endCentre, epsilon: 0.5));
    expect(956 - (last.bottom + StoryIntroTheme.endHeight), moreOrLessEquals(34));
  });

  testWidgets('nothing shows until the detail arrives', (tester) async {
    final rig = _Rig();
    await rig.mount(tester, IntroContent(related: _cards(4)));

    expect(find.byType(Text), findsNothing);
    expect(find.byKey(const ValueKey('intro-retry')), findsNothing);
    expect(find.byType(CustomScrollView), findsOneWidget);
  });

  testWidgets('a detail that never came offers 加载失败，点击重试, as the page does', (tester) async {
    final rig = _Rig();
    var retries = 0;
    await rig.mount(tester, IntroContent(detailFailed: true, onRetryDetail: () => retries++));

    expect(find.byType(IntroRetryLine), findsOneWidget);
    expect(tester.getCenter(find.byKey(const ValueKey('intro-retry'))).dx, moreOrLessEquals(220));
    await tester.tap(find.byKey(const ValueKey('intro-retry')));
    expect(retries, 1);
  });

  testWidgets('no related videos: no heading, no grid and no end line', (tester) async {
    final rig = _Rig();
    await rig.mount(tester, IntroContent(detail: _detail()));

    expect(find.byKey(const ValueKey('story-intro-title')), findsOneWidget);
    expect(find.text('相关视频'), findsNothing);
    expect(_card(0), findsNothing);
    expect(find.text('已经到底了…'), findsNothing);
  });

  testWidgets("it scrolls with the sheet's primary scroll controller", (tester) async {
    final rig = _Rig();
    await rig.mount(tester, IntroContent(detail: _detail(), related: _cards(20)));

    expect(rig.scroll.hasClients, isTrue);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
    await tester.pump();
    expect(rig.scroll.offset, greaterThan(100));
  });
}
