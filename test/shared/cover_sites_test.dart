import 'dart:io';

import 'package:bili_core/api.dart' show HighlightedText, SearchVideo, SpaceVideo, VideoCard, WatchLaterItem;
import 'package:bilifast/search/results/video_row.dart';
import 'package:bilifast/shared/cover_preset.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:bilifast/shared/theme.dart' show UploaderSheetTheme, WatchLaterTheme;
import 'package:bilifast/space/own/own_tab_cards.dart';
import 'package:bilifast/space/space_video_row.dart';
import 'package:bilifast/space/uploader_sheet_grid.dart';
import 'package:bilifast/video/intro/related_list.dart';
import 'package:bilifast/watch_later/watch_later_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _cover = 'http://i1.hdslb.com/bfs/archive/site.jpg';
const _asked = 'https://i1.hdslb.com/bfs/archive/site.jpg';

const _video = SpaceVideo(aid: 1, bvid: 'BV1site', title: '演示视频', cover: _cover, duration: 61, play: 1200);

/// Every place a video's cover is drawn, by file; each must ask for it at its box's size.
const _sites = [
  'lib/home/feed_card.dart',
  'lib/home/feed_dislike.dart',
  'lib/home/avatar_page.dart',
  'lib/history/watch_history_page.dart',
  'lib/search/results/video_row.dart',
  'lib/space/space_video_row.dart',
  'lib/space/uploader_sheet_grid.dart',
  'lib/space/own/own_tab_cards.dart',
  'lib/watch_later/watch_later_row.dart',
  'lib/favourites/favourite_rows.dart',
  'lib/favourites/favourites_page.dart',
  'lib/video/intro/related_list.dart',
  'lib/video/video_page.dart',
  'lib/player_ui/end_screen_portrait.dart',
  'lib/player_ui/end_screen_landscape.dart',
  'lib/player_ui/panels/episodes_panel.dart',
];

/// Covers that aren't a video's: 追番's posters.
const _notVideoCovers = ['bangumi.cover'];

/// The arguments of each `RemoteImage(…)` in [source] (not `.avatar` or `.precache`).
List<String> _remoteImageCalls(String source) {
  final calls = <String>[];
  for (final match in RegExp(r'RemoteImage\(').allMatches(source)) {
    var depth = 1;
    var at = match.end;
    while (depth > 0 && at < source.length) {
      final char = source[at++];
      if (char == '(') depth++;
      if (char == ')') depth--;
    }
    calls.add(source.substring(match.end, at - 1));
  }
  return calls;
}

/// The call's first argument, up to its first comma outside brackets.
String _firstArgument(String arguments) {
  var depth = 0;
  for (var i = 0; i < arguments.length; i++) {
    final char = arguments[i];
    if ('([{'.contains(char)) depth++;
    if (')]}'.contains(char)) depth--;
    if (char == ',' && depth == 0) return arguments.substring(0, i);
  }
  return arguments;
}

void main() {
  List<StoredNetworkImage> pictures(WidgetTester tester) => [
    for (final image in tester.widgetList<Image>(find.byType(Image)))
      if (image.image case final StoredNetworkImage network) network,
  ];

  Future<void> show(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 1, size: Size(440, 956)),
        child: Material(child: child),
      ),
    ),
  );

  /// Covers asked at their box's exact size, but for those whose site names a webp preset ([webpPresets]), asked by
  /// the preset's address and decoded for the box.
  void expectBoxSized(WidgetTester tester, {Set<CoverPreset> webpPresets = const {}}) {
    final covers = pictures(tester).where((image) => image.url.contains('/bfs/archive/'));
    expect(covers, isNotEmpty);
    final presetAddresses = {for (final preset in webpPresets) '$_asked${preset.suffix}'};
    for (final cover in covers) {
      final box = cover.box;
      expect(box, isNotNull, reason: 'decoded for its box');
      if (presetAddresses.contains(cover.url)) continue;
      expect(cover.url, coverImageUrl(_asked, width: box!.width.round(), height: box.height.round()));
    }
    for (final address in presetAddresses) {
      expect(covers.map((cover) => cover.url), contains(address));
    }
  }

  testWidgets("a related video asks for the cover at its box's size", (tester) async {
    const card = VideoCard(
      aid: 1,
      bvid: 'BV1site',
      cid: 1,
      title: '相关视频',
      cover: _cover,
      duration: 61,
      ownerMid: 1,
      ownerName: 'UP',
      views: 1,
      danmaku: 1,
      likes: 0,
    );
    await show(
      tester,
      CustomScrollView(
        slivers: [
          RelatedSliver(cards: const [card], onOpen: (_) {}, onWatchLater: (_) {}),
        ],
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expectBoxSized(tester);
  });

  testWidgets("UP主空间's row asks for its official preset; the uploader sheet's card and the own space's video card "
      "and folder ask for the cover at their box's size", (tester) async {
    await show(
      tester,
      // A Column rather than a lazy list, so all four are built.
      SingleChildScrollView(
        child: Column(
          children: [
            SpaceVideoRow(video: _video, onOpen: () {}, onMore: (_) {}),
            SizedBox(
              width: 200,
              child: UploaderVideoCard(video: _video, playing: false, onOpen: () {}),
            ),
            SizedBox(
              width: 200,
              height: 200,
              child: OwnVideoCard(video: _video, onOpen: () {}),
            ),
            const SizedBox(
              width: 200,
              height: 120,
              child: FolderCover(cover: _cover, tv: Size(40, 30), tvInk: Colors.white, badgeBottom: 4),
            ),
          ],
        ),
      ),
    );
    expectBoxSized(tester, webpPresets: {CoverPreset.space});
    expect(pictures(tester).where((image) => image.url.contains('/bfs/archive/')), hasLength(4));
  });

  testWidgets("the related videos', UP主空间's and 稍后再看's rows name their official screen's preset, 搜索's the exact "
      "JPEG; the uploader sheet's 208 pt card, no official size of its own, names none", (tester) async {
    const related = VideoCard(
      aid: 1,
      bvid: 'BV1related',
      cid: 1,
      title: '相关视频',
      cover: _cover,
      duration: 61,
      ownerMid: 1,
      ownerName: 'UP',
      views: 1,
      danmaku: 1,
      likes: 0,
    );
    final search = SearchVideo(
      aid: 2,
      bvid: 'BV1search',
      title: HighlightedText.plain('搜索结果'),
      author: 'UP',
      mid: 2,
      cover: _cover,
      play: 1,
      danmaku: 1,
      duration: 61,
      published: null,
    );
    const later = WatchLaterItem(
      aid: 3,
      bvid: 'BV1later',
      cid: 3,
      title: '稍后再看',
      cover: _cover,
      ownerMid: 3,
      ownerName: 'UP',
      duration: 61,
      progress: 30,
      play: 1,
      danmaku: 1,
    );
    // Two columns across the 440 pt sheet.
    const sheetCard = (440 - UploaderSheetTheme.gridSide * 2 - UploaderSheetTheme.gridGap) / 2;
    await show(
      tester,
      CustomScrollView(
        slivers: [
          KeyedSubtree(
            key: const ValueKey('related'),
            child: RelatedSliver(cards: const [related], onOpen: (_) {}, onWatchLater: (_) {}),
          ),
          SliverList.list(
            children: [
              SizedBox(
                key: const ValueKey('search'),
                height: SearchVideoRow.height,
                child: SearchVideoRow(video: search, now: DateTime(2026, 10, 23), onOpen: () {}, onMore: () {}),
              ),
              KeyedSubtree(
                key: const ValueKey('space'),
                child: SpaceVideoRow(video: _video, onOpen: () {}, onMore: (_) {}),
              ),
              SizedBox(
                key: const ValueKey('later'),
                height: WatchLaterTheme.rowHeight,
                child: WatchLaterRow(
                  item: later,
                  editing: false,
                  chosen: false,
                  onOpen: () {},
                  onToggle: () {},
                  onMore: () {},
                ),
              ),
              Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  key: const ValueKey('sheet'),
                  width: sheetCard,
                  child: UploaderVideoCard(video: _video, playing: false, onOpen: () {}),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    Finder covers(String site) => find.descendant(of: find.byKey(ValueKey(site)), matching: find.byType(RemoteImage));
    for (final (site, preset) in [
      ('related', CoverPreset.related),
      ('search', CoverPreset.exact),
      ('space', CoverPreset.space),
      ('later', CoverPreset.history),
      ('sheet', null),
    ]) {
      final drawn = tester.widgetList<RemoteImage>(covers(site));
      expect([for (final cover in drawn) (cover.cover, cover.preset)], [(true, preset)], reason: site);
    }
    expect(tester.getSize(covers('space')), const Size(128, 72), reason: "space's 384 × 216 at 3×");
    expect(tester.getSize(covers('sheet')), const Size(208, 117), reason: 'not 128 × 72');
  });

  test('every video cover in the app is drawn as a cover', () {
    for (final path in _sites) {
      final calls = [
        for (final arguments in _remoteImageCalls(File(path).readAsStringSync()))
          if (_firstArgument(arguments).trim() case final first
              when first.contains('cover') && !_notVideoCovers.contains(first))
            arguments,
      ];
      expect(calls, isNotEmpty, reason: '$path draws a cover');
      for (final arguments in calls) {
        expect(arguments, matches(RegExp(r'\bcover:\s*\w+')), reason: '$path: RemoteImage($arguments)');
      }
    }
  });
}
