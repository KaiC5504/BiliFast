import 'package:bilifast/player_ui/speed_lock.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/story/story_drag.dart';
import 'package:bilifast/video/story/story_feed.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'vertical_chrome_preview_test.dart' show mountPreview;
import 'vertical_chrome_test.dart' show RelatedFeed, Rig, rig09;
import 'vertical_clean_test.dart' show FakeFeed, entry;

typedef Layout = ({Rect avatar, Rect title, Rect bar, Rect field});

/// The 搜索 row's room under the title: kept for a video with the row (118) and for the video an ordinary page entered
/// 竖屏 on, gone for one without (270, 185 at 10.5 s), whose uploader and title sit 38 pt lower.
void main() {
  Rig onFeed(StoryFeed feed) => rig09()
    ..session.isVertical = true
    ..clean = ValueNotifier(false)
    ..storyDrag = StoryDrag()
    ..speedLock = SpeedLock()
    ..story = ValueNotifier(feed);

  Rect rectOf(WidgetTester tester, String key) => tester.getRect(find.byKey(ValueKey(key)));

  Future<Layout> layout(WidgetTester tester, Rig rig) async {
    await rig.mount(tester);
    await tester.pumpAndSettle();
    return (
      avatar: rectOf(tester, 'vertical-avatar'),
      title: rectOf(tester, 'vertical-title'),
      bar: rectOf(tester, 'vertical-bar'),
      field: rectOf(tester, 'vertical-danmaku-field'),
    );
  }

  void expectLower(Layout without, Layout kept) {
    expect(without.avatar.top - kept.avatar.top, closeTo(BiliMetrics.verticalSearchRoom, 0.001));
    expect(without.title.top - kept.title.top, closeTo(BiliMetrics.verticalSearchRoom, 0.001));
    expect((without.bar, without.field), (kept.bar, kept.field), reason: 'the bar and the bottom row stay');
  }

  testWidgets("an ordinary page keeps the room for its own video, as for a feed video with a row; one without has its "
      'uploader and title 38 pt lower', (tester) async {
    final page = await layout(tester, rig09()..session.isVertical = true);
    final withRow = await layout(tester, onFeed(FakeFeed([entry('BV1', searchRow: true)])));
    final without = await layout(tester, onFeed(FakeFeed([entry('BV1')])));
    expect(withRow, page);
    expectLower(without, page);
  });

  testWidgets('a video just swiped to goes by its own entry before its details are in', (tester) async {
    final kept = await layout(tester, onFeed(FakeFeed([entry('BV1'), entry('BV2', searchRow: true)])..index = 1));
    final none = await layout(tester, onFeed(FakeFeed([entry('BV1', searchRow: true), entry('BV2')])..index = 1));
    expect(find.text('下一位UP主'), findsOneWidget, reason: "the entry's uploader stands in");
    expectLower(none, kept);
  });

  testWidgets('a page opened from the sheet\'s 相关视频 keeps none (270)', (tester) async {
    final page = await layout(tester, rig09()..session.isVertical = true);
    final related = await layout(tester, onFeed(RelatedFeed([entry('BV1'), entry('BV2')])));
    expectLower(related, page);
  });

  testWidgets('without the room the uploader, the title and the bar still take their own touches', (tester) async {
    final rig = onFeed(FakeFeed([entry('BV1')]))
      ..uploaders = []
      ..introSheet = true;
    await rig.mount(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vertical-avatar')));
    expect(rig.uploaders!.single.mid, 1);
    await tester.tap(find.byKey(const ValueKey('vertical-title')));
    expect(rig.introSheets, 1);
    // The title's line reaches into the bar's touch area: the bar keeps it.
    final bar = rectOf(tester, 'vertical-bar');
    final title = rectOf(tester, 'vertical-title');
    expect(title.bottom, greaterThan(bar.top));
    await tester.tapAt(Offset(100, (bar.top + title.bottom) / 2));
    expect(rig.introSheets, 1);
  });

  testWidgets("清屏's play and time stay over the bar with or without the room", (tester) async {
    Future<(Rect, Rect)> cleanPlay(Rig rig) async {
      rig.clean!.value = true;
      await rig.mount(tester);
      await tester.pumpAndSettle();
      return (rectOf(tester, 'vertical-clean-play'), rectOf(tester, 'vertical-clean-time'));
    }

    final kept = await cleanPlay(onFeed(FakeFeed([entry('BV1', searchRow: true)])));
    final rig = onFeed(FakeFeed([entry('BV1')]));
    expect(await cleanPlay(rig), kept);
    await tester.tap(find.byKey(const ValueKey('vertical-clean-play')));
    expect(rig.session.calls, ['togglePlay']);
  });

  testWidgets("a neighbour's still controls go by its entry", (tester) async {
    await mountPreview(tester, entry('BV2', searchRow: true));
    final kept = (
      avatar: rectOf(tester, 'vertical-preview-avatar'),
      title: rectOf(tester, 'vertical-preview-title'),
      bar: rectOf(tester, 'vertical-preview-bar'),
      field: tester.getRect(find.text('发弹幕')),
    );
    await mountPreview(tester, entry('BV2'));
    final none = (
      avatar: rectOf(tester, 'vertical-preview-avatar'),
      title: rectOf(tester, 'vertical-preview-title'),
      bar: rectOf(tester, 'vertical-preview-bar'),
      field: tester.getRect(find.text('发弹幕')),
    );
    expectLower(none, kept);
  });
}
