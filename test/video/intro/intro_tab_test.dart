import 'package:bili_core/api.dart'
    show UgcSeason, UploaderCard, OfficialKind, VideoCard, VideoDetail, VideoOwner, VideoStat, VideoTag, VideoTagKind;
import 'package:bilifast/shared/action_glyphs.dart';
import 'package:bilifast/shared/menu.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/collapsing_player.dart';
import 'package:bilifast/video/intro/action_row.dart';
import 'package:bilifast/video/intro/collection_row.dart';
import 'package:bilifast/video/intro/intro_tab.dart';
import 'package:bilifast/video/intro/part_strip.dart';
import 'package:bilifast/video/intro/related_list.dart';
import 'package:bilifast/video/intro/tag_chips.dart';
import 'package:bilifast/video/intro/title_block.dart';
import 'package:bilifast/video/intro/uploader_row.dart';
import 'package:bilifast/video/player_session.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_video_actions.dart';

const bv = 'BV1GJ411x7h7';

VideoDetail detail({UgcSeason? season, String? notice}) => VideoDetail(
  bvid: bv,
  aid: 80433022,
  title: '恭喜你，终于触发了B站大保底！',
  cover: '',
  pubdate: 0,
  duration: 712,
  desc: '',
  descParts: const [],
  copyright: 1,
  owner: const VideoOwner(mid: 1, name: '星宇动漫社', face: ''),
  stat: const VideoStat(view: 37000, danmaku: 337, reply: 213, favorite: 3907, coin: 1210, share: 148, like: 9131),
  pages: const [],
  season: season,
  staff: const [],
  width: 1920,
  height: 1080,
  honor: null,
  redirectURL: null,
  argueMessage: notice,
);

VideoCard card(String bvid) => VideoCard(
  aid: 2,
  bvid: bvid,
  cid: 3,
  title: '【天气之子 x 你的名字】有被治愈到！',
  cover: '',
  duration: 60,
  ownerMid: 4,
  ownerName: '天气之子',
  views: 82830000,
  danmaku: 1,
  likes: 4116000,
);

const parts = [
  Episode(bvid: bv, cid: 1, title: 'P1 第一集', current: true, duration: 712),
  Episode(bvid: bv, cid: 2, title: 'P2 第二集', current: false, duration: 100),
];

const seasonEpisodes = [
  Episode(bvid: 'BV1a', cid: 11, title: '第一话', current: false),
  Episode(bvid: bv, cid: 12, title: '第二话', current: true),
];

void main() {
  late FakePageDetails details;
  late List<String> calls;

  setUp(() {
    details = FakePageDetails(
      uploader: const UploaderCard(
        mid: 1,
        name: '星宇动漫社',
        face: '',
        fans: 475000,
        videos: 410,
        isVip: true,
        following: false,
        official: OfficialKind.person,
      ),
      tags: const [VideoTag(id: 2, name: '动漫二创激励计划', kind: VideoTagKind.topic)],
      online: '53',
    );
    calls = [];
  });

  tearDown(() => details.dispose());

  Future<void> host(
    WidgetTester tester,
    IntroContent content, {
    bool still = false,
    double reserve = 0,
    ScrollController? scroll,
  }) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget tab = IntroTab(
      content: content,
      details: details,
      onSeek: (seconds) => calls.add('seek $seconds'),
      onOpenVideo: (id) => calls.add('open $id'),
      onPlayEpisode: (episode) => calls.add('play ${episode.cid}'),
      onOpenEpisodes: () => calls.add('episodes'),
      onOpenRelated: (card) => calls.add('related ${card.bvid}'),
      onWatchLater: (card) => calls.add('later ${card.bvid}'),
    );
    if (scroll != null) tab = PrimaryScrollController(controller: scroll, child: tab);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(440, 956),
            padding: const EdgeInsets.only(bottom: 34),
            disableAnimations: still,
          ),
          child: Scaffold(
            body: PlayerReserve(height: reserve, child: tab),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// The section types in the column's order.
  List<Type> sections(WidgetTester tester) {
    final column = find.ancestor(
      of: find.byType(UploaderRow, skipOffstage: false),
      matching: find.byType(Column, skipOffstage: false),
    );
    return [for (final widget in tester.widget<Column>(column.first).children) widget.runtimeType];
  }

  testWidgets('before the detail arrives: nothing shows and nothing spins, only room above the home indicator', (
    tester,
  ) async {
    await host(tester, const IntroContent());
    for (final type in [UploaderRow, TitleBlock, ActionRow, PartStrip, CollectionRow, TagChips, RelatedSliver]) {
      expect(find.byType(type, skipOffstage: false), findsNothing, reason: '$type');
    }
    expect(find.byType(CupertinoActivityIndicator, skipOffstage: false), findsNothing);
    expect(find.byType(CircularProgressIndicator, skipOffstage: false), findsNothing);
    expect(
      find.byType(CustomScrollView, skipOffstage: false),
      findsOneWidget,
      reason: 'the scroll view is there, keeping its position',
    );
  });

  testWidgets('neither parts nor 合集: uploader, title, chips, then the related list; the action row only once the '
      'actions exist', (tester) async {
    await host(tester, IntroContent(detail: detail(), related: [card('BV1x')]));
    expect(sections(tester), [UploaderRow, TitleBlock, TagChips]);
    expect(find.byType(RelatedSliver, skipOffstage: false), findsOneWidget);

    final actions = FakeVideoActions();
    details
      ..actions = actions
      ..changed();
    await tester.pump();
    expect(sections(tester), [UploaderRow, TitleBlock, ActionRow, TagChips]);
    expect(tester.widget<ActionRow>(find.byType(ActionRow, skipOffstage: false)).actions, same(actions));
    expect(
      tester.widget<UploaderRow>(find.byType(UploaderRow, skipOffstage: false)).actions,
      same(actions),
      reason: '关注 is the actions\'',
    );
  });

  testWidgets('a video in parts: the part strip after the action row; a chip plays its part, the header opens 选集', (
    tester,
  ) async {
    details.actions = FakeVideoActions();
    await host(tester, IntroContent(detail: detail(), episodes: parts, episodesAreParts: true));
    expect(sections(tester), [UploaderRow, TitleBlock, ActionRow, PartStrip, TagChips]);
    final strip = tester.widget<PartStrip>(find.byType(PartStrip, skipOffstage: false));
    expect(strip.parts, parts);
    strip.onChoose(parts.last);
    strip.onOpenList();
    expect(calls, ['play 2', 'episodes']);
  });

  testWidgets('a 合集: its row, named after the 合集, with the episodes; it opens 选集', (tester) async {
    details.actions = FakeVideoActions();
    final season = UgcSeason(id: 1, title: 'MAD系列', intro: '', sections: const []);
    await host(
      tester,
      IntroContent(
        detail: detail(season: season),
        episodes: seasonEpisodes,
      ),
    );
    expect(sections(tester), [UploaderRow, TitleBlock, ActionRow, CollectionRow, TagChips]);
    final row = tester.widget<CollectionRow>(find.byType(CollectionRow, skipOffstage: false));
    expect(row.title, 'MAD系列');
    expect(row.episodes, seasonEpisodes);
    row.onOpen();
    expect(calls, ['episodes']);
  });

  for (final (notice, lower) in [(null, 0.0), ('个人观点，仅供参考', 16.0)]) {
    testWidgets('the icons, the coin, the 合集 card and the chips land where the official has them below the tab row\'s '
        'hairline, ${notice == null ? 'without a notice (03)' : '16 lower under a notice (font-check 02)'}', (
      tester,
    ) async {
      details.actions = FakeVideoActions();
      final season = UgcSeason(id: 1, title: 'MAD系列', intro: '', sections: const []);
      await host(
        tester,
        IntroContent(
          detail: detail(season: season, notice: notice),
          episodes: seasonEpisodes,
        ),
      );

      double iconCentre(ActionGlyph glyph) =>
          tester.getCenter(find.byWidgetPredicate((widget) => widget is ActionIcon && widget.glyph == glyph)).dy;
      // Measured on the official shots to a fifth of a pixel.
      const within = 0.07;
      expect(iconCentre(ActionGlyph.like), closeTo(134.86 + lower, within));
      expect(iconCentre(ActionGlyph.coin), closeTo(136 + lower, within));
      final card = tester.getRect(find.byType(PressHighlight));
      expect(card.top, closeTo(180 + lower, within));
      expect(card.bottom, closeTo(216 + lower, within));
      final chip = tester.getRect(find.ancestor(of: find.byType(ChipName), matching: find.byType(Container)).first);
      expect(chip.top, closeTo(234 + lower, within));
    });
  }

  testWidgets('the sections get the details\' card, N人正在看, tags and the page\'s callbacks', (tester) async {
    final related = [card('BV1x'), card('BV1y')];
    await host(tester, IntroContent(detail: detail(), related: related));
    final uploader = tester.widget<UploaderRow>(find.byType(UploaderRow, skipOffstage: false));
    expect(uploader.card, same(details.uploader));
    expect(uploader.detail.bvid, bv);
    final title = tester.widget<TitleBlock>(find.byType(TitleBlock, skipOffstage: false));
    expect(title.online, same(details.online));
    expect(title.tags, same(details.tags));
    title.onSeek(83);
    title.onOpenVideo('av170001');
    expect(tester.widget<TagChips>(find.byType(TagChips, skipOffstage: false)).tags, same(details.tags));
    final list = tester.widget<RelatedSliver>(find.byType(RelatedSliver, skipOffstage: false));
    expect(list.cards, same(related));
    list.onOpen(related.first);
    list.onWatchLater(related.last);
    expect(calls, ['seek 83.0', 'open av170001', 'related BV1x', 'later BV1y']);
  });

  testWidgets('the column fades up into place for a new video, and simply appears with reduced motion', (tester) async {
    await host(tester, const IntroContent());
    await tester.pumpWidget(Container());
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IntroTab(
            content: IntroContent(detail: detail()),
            details: details,
            onSeek: (_) {},
            onOpenVideo: (_) {},
            onPlayEpisode: (_) {},
            onOpenEpisodes: () {},
            onOpenRelated: (_) {},
            onWatchLater: (_) {},
          ),
        ),
      ),
    );
    Opacity fade() => tester.widget<Opacity>(
      find
          .ancestor(
            of: find.byType(UploaderRow, skipOffstage: false),
            matching: find.byType(Opacity, skipOffstage: false),
          )
          .first,
    );
    expect(fade().opacity, 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(fade().opacity, inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 400));
    expect(fade().opacity, 1);

    await host(tester, IntroContent(detail: detail()), still: true);
    expect(
      find.ancestor(
        of: find.byType(UploaderRow, skipOffstage: false),
        matching: find.byType(Opacity, skipOffstage: false),
      ),
      findsNothing,
    );
  });

  testWidgets('the list starts the player\'s reserve below its top and scrolls with the page\'s primary controller', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await host(
      tester,
      IntroContent(detail: detail(), related: [for (var i = 0; i < 10; i++) card('BV1x$i')]),
      reserve: 180,
      scroll: scroll,
    );
    expect(tester.getTopLeft(find.byType(UploaderRow)).dy, 180);
    await tester.drag(find.byType(UploaderRow), const Offset(0, -150));
    await tester.pump();
    expect(scroll.offset, greaterThan(100));
    expect(tester.getTopLeft(find.byType(UploaderRow)).dy, closeTo(180 - scroll.offset, 0.01));
  });

  testWidgets('the list ends with room for the home indicator', (tester) async {
    await host(tester, IntroContent(detail: detail(), related: [card('BV1x')]));
    final scroll = tester.widget<CustomScrollView>(find.byType(CustomScrollView, skipOffstage: false));
    final last = scroll.slivers.last as SliverToBoxAdapter;
    expect((last.child! as SizedBox).height, 34 + PageTheme.introBottom);
  });
}
