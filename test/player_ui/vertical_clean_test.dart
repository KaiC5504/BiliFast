import 'package:bili_core/api.dart' show PlaySource, VideoDetail;
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/player/bili_player.dart' show PlayerStatus, StatusChanged;
import 'package:bilifast/player_ui/portrait_controls.dart' show FullScreenPainter;
import 'package:bilifast/player_ui/speed_lock.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/story/story_drag.dart';
import 'package:bilifast/video/story/story_feed.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'vertical_chrome_test.dart' show Rig, actionsOf, centre, opacityOf, rig09;

final class FakeFeed extends StoryFeed {
  FakeFeed(this.entries);

  @override
  final List<StoryEntry> entries;

  @override
  int index = 0;

  @override
  bool get loading => false;

  @override
  bool moveNext() {
    if (index + 1 >= entries.length) return false;
    index += 1;
    notifyListeners();
    return true;
  }

  @override
  bool movePrevious() {
    if (index == 0) return false;
    index -= 1;
    notifyListeners();
    return true;
  }
}

StoryEntry entry(String bvid, {int width = 1080, int height = 1920, bool following = false}) => StoryEntry(
  bvid: bvid,
  title: '下一个视频的标题',
  cover: '',
  ownerMid: 2,
  ownerName: '下一位UP主',
  ownerFans: 23000,
  following: following,
  width: width,
  height: height,
  duration: 81,
  views: 556000,
  likes: 40000,
  replies: 398,
  coins: 2230,
  favourites: 3146,
  shares: 1652,
  source: PlaySource.unknown,
);

/// 09's page made upright, with 清屏, the feed, the drag and the lock as the video page hands them over.
Rig storyRig({bool upright = true}) => rig09()
  ..session.isVertical = upright
  ..clean = ValueNotifier(false)
  ..storyDrag = StoryDrag()
  ..speedLock = SpeedLock()
  ..story = ValueNotifier(FakeFeed([entry('BV1'), entry('BV2')]));

Finder screenMode() => find.byKey(const ValueKey('vertical-screen-mode'));

String screenModeAsset(WidgetTester tester) => (tester.widget<Image>(screenMode()).image as AssetImage).assetName;

/// Every fade and dim over the control keyed [key], as drawn.
double drawnOpacity(WidgetTester tester, String key) =>
    opacityOf(tester, key) *
    tester
        .widgetList<Opacity>(find.ancestor(of: find.byKey(ValueKey(key)), matching: find.byType(Opacity)))
        .fold(1.0, (opacity, dim) => opacity * dim.opacity);

const info = [
  'vertical-back',
  'vertical-more',
  'vertical-like',
  'vertical-uploader',
  'vertical-follow',
  'vertical-title',
];
const kept = ['vertical-bar', 'vertical-danmaku-field', 'vertical-danmaku', 'vertical-detail', 'vertical-landscape'];

void main() {
  group('the last bottom button by the video\'s shape', () {
    testWidgets('upright: the phone, which turns 清屏 on and off and stays in 竖屏', (tester) async {
      final rig = storyRig();
      await rig.mount(tester);
      await tester.pumpAndSettle();
      expect(screenModeAsset(tester), VerticalActionTheme.screenModeAsset);
      expect(find.bySemanticsLabel('清屏'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('vertical-landscape')));
      await tester.pumpAndSettle();
      expect(rig.clean!.value, isTrue);
      expect(rig.orientation.presentation, Presentation.vertical);
      expect(screenModeAsset(tester), VerticalCleanTheme.screenModeCleanAsset);
      expect(tester.getRect(screenMode()), const Rect.fromLTWH(401, 889, 24, 24));
      expect(find.bySemanticsLabel('退出清屏'), findsOneWidget);

      tester.semantics.tap(find.semantics.byLabel('退出清屏'));
      await tester.pumpAndSettle();
      expect(rig.clean!.value, isFalse);
      expect(screenModeAsset(tester), VerticalActionTheme.screenModeAsset);
    });

    testWidgets('a square video counts as upright', (tester) async {
      final rig = storyRig(upright: false)..session.videoShape = (width: 1080, height: 1080);
      await rig.mount(tester);
      expect(screenMode(), findsOneWidget);
    });

    testWidgets('wide: the corners, going to landscape; 清屏 is left alone', (tester) async {
      final rig = storyRig(upright: false)..session.videoShape = (width: 1920, height: 1080);
      await rig.mount(tester);
      expect(screenMode(), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('vertical-landscape')),
          matching: find.byWidgetPredicate((widget) => widget is CustomPaint && widget.painter is FullScreenPainter),
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('横屏全屏'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('vertical-landscape')));
      expect(rig.orientation.presentation, Presentation.landscape);
      expect(rig.clean!.value, isFalse);
    });
  });

  group('清屏 (180, 186)', () {
    testWidgets('takes ‹, ⋮, the column, the uploader and the title, and their touches; the bar and the bottom row '
        'stay where they were', (tester) async {
      final rig = storyRig();
      await rig.mount(tester);
      await tester.pumpAndSettle();
      final before = {for (final key in kept) key: tester.getRect(find.byKey(ValueKey(key)))};

      rig.clean!.value = true;
      await tester.pumpAndSettle();
      for (final key in info) {
        expect(opacityOf(tester, key), 0, reason: key);
      }
      for (final key in kept) {
        expect(opacityOf(tester, key), 1, reason: key);
        expect(tester.getRect(find.byKey(ValueKey(key))), before[key], reason: key);
      }
      await tester.tap(find.byKey(const ValueKey('vertical-back')), warnIfMissed: false);
      await tester.tap(find.byKey(const ValueKey('vertical-like')), warnIfMissed: false);
      await tester.tap(find.byKey(const ValueKey('vertical-follow')), warnIfMissed: false);
      expect(rig.backs, 0);
      expect(actionsOf(rig).calls, isEmpty);

      rig.clean!.value = false;
      await tester.pumpAndSettle();
      for (final key in info) {
        expect(opacityOf(tester, key), 1, reason: key);
      }
    });

    testWidgets('N人正在看 stays, dimmed and moved to the left edge as on 180', (tester) async {
      final rig = storyRig();
      await rig.mount(tester);
      await tester.pumpAndSettle();
      final text = find.text('479人正在看');
      final y = tester.getCenter(text).dy;

      rig.clean!.value = true;
      await tester.pumpAndSettle();
      // 180: the mark's ink from 9 pt, the text's from 25.3, five sixths of 09's size.
      expect(tester.getTopLeft(text).dx, closeTo(25.33, 0.5));
      expect(tester.widget<Text>(text).style!.fontSize, VerticalCleanTheme.onlineText);
      expect(tester.getCenter(text).dy, closeTo(y, 0.5));
      expect(opacityOf(tester, 'vertical-online'), closeTo(VerticalCleanTheme.onlineOpacity, 0.001));
    });

    testWidgets('paused: ▶ with the time at the bottom left where 180 has them, no big ▶; a tap plays', (tester) async {
      final rig = storyRig()..clean!.value = true;
      rig.session.duration.value = 78;
      rig.session.clock.jump(7.2);
      rig.session.readout.refresh();
      await rig.mount(tester);
      rig.session.player.emit(const StatusChanged(PlayerStatus.paused));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('vertical-paused-play')), findsNothing);
      expect(find.byKey(const ValueKey('vertical-paused-time')), findsNothing);
      final glyph = tester.getRect(
        find.descendant(of: find.byKey(const ValueKey('vertical-clean-play')), matching: find.byType(CustomPaint)),
      );
      // 180: the ▶'s ink 16.3-34.7 × 832-852.3 pt.
      expect(glyph.left, closeTo(16.33, 0.1));
      expect(glyph.top, closeTo(832, 0.2));
      expect(glyph.width, closeTo(VerticalCleanTheme.playWidth, 0.01));
      expect(glyph.height, closeTo(VerticalCleanTheme.playHeight, 0.01));
      final time = find.byKey(const ValueKey('vertical-clean-time'));
      expect(find.text('00:07 / 01:18', findRichText: true), findsOneWidget);
      expect(tester.getTopLeft(time).dx, VerticalCleanTheme.timeLeft);
      expect(tester.getCenter(time).dy, closeTo(glyph.center.dy + VerticalCleanTheme.timeDrop, 0.5));
      expect(find.bySemanticsLabel('播放'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('vertical-clean-play')));
      expect(rig.session.calls, ['togglePlay']);
      expect(rig.chrome.shows, 1);
    });

    testWidgets('playing it reads 暂停 and pauses', (tester) async {
      final rig = storyRig()..clean!.value = true;
      await rig.mount(tester);
      rig.session.player.emit(const StatusChanged(PlayerStatus.playing));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('暂停'), findsOneWidget);
      tester.semantics.tap(find.semantics.byLabel('暂停'));
      expect(rig.session.calls, ['togglePlay']);
    });

    testWidgets('off, there is no play button at the bottom left', (tester) async {
      final rig = storyRig();
      await rig.mount(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vertical-clean-play')), findsNothing);
      expect(find.byKey(const ValueKey('vertical-clean-time')), findsNothing);
    });
  });

  group('the held 2× (182, 183)', () {
    for (final clean in [false, true]) {
      testWidgets('holding and armed leave only the progress line${clean ? ' in 清屏' : ''}; locked, all comes back', (
        tester,
      ) async {
        final rig = storyRig()..clean!.value = clean;
        await rig.mount(tester);
        await tester.pumpAndSettle();
        final aside = [
          if (!clean) ...info,
          'vertical-danmaku-field',
          'vertical-danmaku',
          'vertical-detail',
          'vertical-landscape',
          'vertical-online',
          if (clean) 'vertical-clean-play',
        ];

        for (final phase in [SpeedLockPhase.holding, SpeedLockPhase.armed]) {
          rig.speedLock!.value = phase;
          await tester.pumpAndSettle();
          for (final key in aside) {
            expect(opacityOf(tester, key), 0, reason: '$phase $key');
          }
          expect(opacityOf(tester, 'vertical-bar'), 1);
        }
        await tester.tap(find.byKey(const ValueKey('vertical-detail')), warnIfMissed: false);
        expect(rig.orientation.presentation, Presentation.vertical);

        rig.speedLock!.value = SpeedLockPhase.locked;
        await tester.pumpAndSettle();
        for (final key in aside) {
          final dimmed = clean && key == 'vertical-online';
          expect(opacityOf(tester, key), dimmed ? VerticalCleanTheme.onlineOpacity : 1, reason: key);
        }
      });
    }
  });

  group('the page under the finger (185)', () {
    testWidgets('all but the top row moves with it at a tenth, and comes back as it lands', (tester) async {
      final rig = storyRig();
      await rig.mount(tester);
      await tester.pumpAndSettle();
      const moved = ['vertical-like', 'vertical-uploader', 'vertical-title', 'vertical-bar', 'vertical-detail'];
      const still = ['vertical-back', 'vertical-online', 'vertical-more'];
      final before = {for (final key in [...moved, ...still]) key: centre(tester, key)};

      rig.storyDrag!
        ..start()
        ..update(-300);
      await tester.pump();
      for (final key in moved) {
        expect(centre(tester, key), within(distance: 0.01, from: before[key]! + const Offset(0, -300)), reason: key);
        expect(drawnOpacity(tester, key), VerticalCleanTheme.movingOpacity, reason: key);
      }
      for (final key in still) {
        expect(centre(tester, key), before[key], reason: key);
        expect(drawnOpacity(tester, key), 1, reason: key);
      }

      rig.storyDrag!.settleTo(-600);
      await tester.pump();
      expect(
        centre(tester, 'vertical-bar'),
        within(distance: 0.01, from: before['vertical-bar']! + const Offset(0, -600)),
      );

      rig.storyDrag!.land();
      await tester.pump();
      for (final key in moved) {
        expect(centre(tester, key), within(distance: 0.01, from: before[key]!), reason: key);
        expect(drawnOpacity(tester, key), 1, reason: key);
      }
    });

    testWidgets('just swiped, the uploader, counts, title and last button are the feed\'s until the details are in', (
      tester,
    ) async {
      final rig = storyRig();
      final feed = rig.story!.value! as FakeFeed;
      feed.entries[1] = entry('BV2', width: 1920, height: 1080);
      await rig.mount(tester);
      await tester.pumpAndSettle();
      expect(find.text('我们一起去养猪'), findsOneWidget);
      final places = {
        for (final key in ['vertical-name', 'vertical-avatar', 'vertical-title', 'vertical-like', 'vertical-share'])
          key: tester.getRect(find.byKey(ValueKey(key))),
      };

      feed.moveNext();
      await tester.pumpAndSettle();
      expect(find.text('下一位UP主'), findsOneWidget);
      expect(find.text('我们一起去养猪'), findsNothing);
      expect(find.text('2.3万粉丝'), findsOneWidget);
      expect(find.textContaining('下一个视频的标题', findRichText: true), findsOneWidget);
      expect(find.textContaining('55.6万播放', findRichText: true), findsOneWidget);
      for (final count in ['4万', '398', '2230', '3146', '1652']) {
        expect(find.text(count), findsOneWidget, reason: count);
      }
      expect(screenMode(), findsNothing, reason: 'the arriving video is wide');
      // Where the page's own would be: the column, the title's last line, the uploader's left edge.
      for (final key in ['vertical-like', 'vertical-share']) {
        expect(tester.getRect(find.byKey(ValueKey(key))), places[key], reason: key);
      }
      expect(tester.getBottomLeft(find.byKey(const ValueKey('vertical-title'))), places['vertical-title']!.bottomLeft);
      expect(tester.getTopLeft(find.byKey(const ValueKey('vertical-avatar'))).dx, places['vertical-avatar']!.left);
      expect(tester.getTopLeft(find.byKey(const ValueKey('vertical-name'))).dx, places['vertical-name']!.left);

      rig.session
        ..detail = detail2()
        ..changed();
      await tester.pumpAndSettle();
      expect(find.text('下一位UP主'), findsNothing);
      expect(find.text('第二个'), findsOneWidget);
      expect(find.text('352'), findsOneWidget, reason: "the page's actions again");
    });
  });
}

VideoDetail detail2() => VideoDetail.fromJson({
  'bvid': 'BV2',
  'title': '第二个',
  'owner': {'mid': 2, 'name': '第二个', 'face': ''},
  'stat': {'view': 1},
});
