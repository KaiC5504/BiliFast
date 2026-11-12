import 'package:bilifast/player_ui/vertical_chrome_preview.dart';
import 'package:bilifast/shared/cover_preset.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/story/story_drag.dart';
import 'package:bilifast/video/story/story_pager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_story_feed.dart';

const screen = 956.0;
const frame = Duration(microseconds: 16667);

void main() {
  late StoryDrag drag;
  late ValueNotifier<bool> clean;
  late StoryPager pager;
  late FakeStoryFeed feed;

  setUp(() {
    drag = StoryDrag();
    clean = ValueNotifier(true);
    pager = StoryPager(drag: drag, clean: clean, vsync: const TestVSync())..extent = screen;
    feed = FakeStoryFeed([storyEntry('BV1'), storyEntry('BV2'), storyEntry('BV3')]);
    pager.feed = feed;
    addTearDown(() {
      pager.dispose();
      drag.dispose();
      clean.dispose();
      feed.dispose();
    });
  });

  /// The finger moving [travel] points over [frames] frames, one update a frame, then let go at [velocity].
  Future<void> swipe(WidgetTester tester, double travel, {int frames = 6, required double velocity}) async {
    drag.start();
    for (var i = 0; i < frames; i++) {
      drag.update(travel / frames);
      await tester.pump(frame);
    }
    drag.end(velocity);
  }

  /// Frames until the page is at rest, with the offset each one drew.
  Future<List<double>> settle(WidgetTester tester, {Duration step = frame}) async {
    final offsets = <double>[];
    for (var i = 0; i < 100 && drag.moving; i++) {
      await tester.pump(step);
      offsets.add(drag.offset);
    }
    expect(drag.moving, isFalse, reason: 'it lands');
    return offsets;
  }

  int ms(int frames, [Duration step = frame]) => (step * frames).inMilliseconds;

  testWidgets('a normal swipe up moves exactly one screen to the next video and lands it, 220-270 ms in all, no bounce',
      (tester) async {
    // The finger: about 100 pt in 0.1 s (185, 186).
    await swipe(tester, -100, velocity: -1000);
    expect(drag.offset, closeTo(-100, 1e-9), reason: 'one to one under the finger');
    final offsets = await settle(tester);
    expect(feed.moves, [1], reason: 'moved once, to the next');
    expect(drag.offset, 0, reason: 'landed in the same frame it moved');
    final settled = ms(offsets.length);
    expect(settled, inInclusiveRange(120, 170));
    expect(100 + settled, inInclusiveRange(220, 270));
    final travel = offsets.sublist(0, offsets.length - 1);
    expect(travel.first, lessThan(-100));
    for (var i = 1; i < travel.length; i++) {
      expect(travel[i], lessThan(travel[i - 1]), reason: 'always on towards the next');
    }
    expect(travel.last, greaterThanOrEqualTo(-screen), reason: 'never past one screen');
    expect(travel.last, closeTo(-screen, StoryPagerTheme.landWithin * 2));
  });

  testWidgets('the settle halves the distance left every frame', (tester) async {
    await swipe(tester, -100, velocity: -1000);
    final offsets = await settle(tester);
    final left = [for (final offset in offsets.sublist(0, offsets.length - 1)) offset + screen];
    expect(left.first, closeTo((screen - 100) * StoryPagerTheme.settleRatioPerFrame, 1));
    for (var i = 1; i < left.length; i++) {
      expect(left[i] / left[i - 1], closeTo(StoryPagerTheme.settleRatioPerFrame, 0.02));
    }
  });

  testWidgets('a 120 Hz screen lands as soon as a 60 Hz one', (tester) async {
    const fast = Duration(microseconds: 8333);
    await swipe(tester, -100, velocity: -1000);
    final offsets = await settle(tester, step: fast);
    expect(feed.moves, [1]);
    expect(ms(offsets.length, fast), inInclusiveRange(120, 170));
  });

  testWidgets('a slow drag let go at 64% of the screen finishes the rest in about 120 ms', (tester) async {
    await swipe(tester, -screen * 0.64, frames: 60, velocity: 0);
    final offsets = await settle(tester);
    expect(feed.moves, [1]);
    expect(ms(offsets.length), inInclusiveRange(100, 150));
  });

  testWidgets('a short slow drag goes back and opens nothing', (tester) async {
    await swipe(tester, -screen * 0.3, frames: 30, velocity: -150);
    final offsets = await settle(tester);
    expect(feed.moves, isEmpty);
    expect(drag.offset, 0);
    expect(offsets.every((offset) => offset <= 0 && offset > -screen * 0.3), isTrue, reason: 'straight back');
    expect(clean.value, isTrue, reason: '清屏 stays with the video');
  });

  testWidgets('a short fling moves; a drag up flung back down returns', (tester) async {
    await swipe(tester, -60, frames: 3, velocity: -1200);
    await settle(tester);
    expect(feed.moves, [1]);

    await swipe(tester, -200, frames: 10, velocity: 800);
    await settle(tester);
    expect(feed.moves, [1], reason: 'flung the other way');
  });

  testWidgets('a swipe down on the first video resists, springs back and opens nothing', (tester) async {
    drag.start();
    drag.update(200);
    expect(drag.offset, closeTo(200 * StoryPagerTheme.resistance, 0.001));
    drag.end(1500);
    final offsets = await settle(tester);
    expect(feed.moves, isEmpty);
    expect(offsets.every((offset) => offset >= 0 && offset <= 60), isTrue, reason: 'no bounce past the top');
    expect(drag.offset, 0);
  });

  testWidgets('a swipe up with no next video loaded resists too', (tester) async {
    final alone = FakeStoryFeed([storyEntry('BV1')]);
    addTearDown(alone.dispose);
    pager.feed = alone;
    await swipe(tester, -300, velocity: -1500);
    await settle(tester);
    expect(alone.moves, isEmpty);
  });

  testWidgets('a swipe down goes back to the video before', (tester) async {
    await swipe(tester, -100, velocity: -1000);
    await settle(tester);
    await swipe(tester, 100, velocity: 1000);
    final offsets = await settle(tester);
    expect(feed.moves, [1, 0]);
    expect(offsets.sublist(0, offsets.length - 1).last, closeTo(screen, StoryPagerTheme.landWithin * 2));
  });

  testWidgets('a finger taking the page while it settles picks it up where it is', (tester) async {
    await swipe(tester, -100, velocity: -1000);
    await tester.pump(frame);
    await tester.pump(frame);
    final at = drag.offset;
    expect(drag.settling, isTrue);
    drag.start();
    await tester.pump(frame);
    expect(drag.offset, at, reason: 'the settle stopped');
    drag.update(-10);
    expect(drag.offset, at - 10);
    drag.update(400);
    expect(drag.offset, at + 390, reason: 'one to one, no jump');
    drag.end(0);
    await settle(tester);
    expect(feed.moves, isEmpty, reason: 'let go short of half the screen');
  });

  testWidgets('a finger taking a page springing back from the first video keeps its resistance', (tester) async {
    drag.start();
    drag.update(200);
    drag.end(0);
    await tester.pump(frame);
    final at = drag.offset;
    drag.start();
    drag.update(10);
    expect(drag.offset, closeTo(at + 10 * StoryPagerTheme.resistance, 0.001));
    drag.end(0);
    await settle(tester);
  });

  testWidgets('the accessibility moves settle as a swipe does, and refuse with no neighbour', (tester) async {
    expect(pager.movePrevious(), isFalse, reason: 'the first video');
    expect(pager.moveNext(), isTrue);
    expect(pager.moveNext(), isFalse, reason: 'already moving');
    final offsets = await settle(tester);
    expect(feed.moves, [1]);
    expect(ms(offsets.length), inInclusiveRange(120, 170));
    expect(pager.movePrevious(), isTrue);
    await settle(tester);
    expect(feed.moves, [1, 0]);
  });

  testWidgets('landing turns 清屏 off and holds the arrived still until the player shows its first frame',
      (tester) async {
    expect(pager.arrived, isNull);
    await swipe(tester, -100, velocity: -1000);
    await settle(tester);
    expect(clean.value, isFalse);
    expect(pager.arrived?.bvid, 'BV2');
    pager.framed('BV1');
    expect(pager.arrived?.bvid, 'BV2', reason: "the last video's frame doesn't count");
    pager.framed(null);
    expect(pager.arrived?.bvid, 'BV2');
    pager.framed('BV2');
    expect(pager.arrived, isNull);
  });

  testWidgets('without a feed the drag goes back at once and has no shape', (tester) async {
    pager.feed = null;
    expect(drag.shape, isNull);
    expect(drag.onRelease, isNull);
    drag
      ..start()
      ..update(-300)
      ..end(-1500);
    expect(drag.offset, 0);
    expect(drag.moving, isFalse);
  });

  group('the neighbours', () {
    Future<void> show(WidgetTester tester) async {
      tester.view.physicalSize = const Size(440, screen);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(fit: StackFit.expand, children: [StoryNeighbours(pager: pager)]),
        ),
      );
    }

    Finder pageOf(String bvid) => find.byWidgetPredicate(
      (widget) => widget is VerticalChromePreview && widget.entry.bvid == bvid,
    );

    Finder stillOf(String bvid) => find.byWidgetPredicate((widget) => widget is RemoteImage && widget.url == pic(bvid));

    testWidgets('the next video waits one screen below, at the size its shape gives it, and follows the finger',
        (tester) async {
      final wide = FakeStoryFeed([
        storyEntry('BV1'),
        storyEntry('BV2', cover: pic('BV2'), width: 1920, height: 1080),
      ]);
      addTearDown(wide.dispose);
      pager.feed = wide;
      await show(tester);
      expect(pager.extent, screen);
      expect(tester.getRect(stillOf('BV2')), Rect.fromLTWH(0, screen + 956 * 0.415 - 440 * 9 / 16 / 2, 440, 247.5));
      final image = tester.widget<RemoteImage>(stillOf('BV2'));
      expect((image.cover, image.preset, image.size), (true, CoverPreset.player, const Size(440, 247.5)));

      drag
        ..start()
        ..update(-300);
      await tester.pump();
      expect(tester.getRect(stillOf('BV2')).top, closeTo(screen - 300 + 956 * 0.415 - 247.5 / 2, 0.01));
      expect(tester.getRect(pageOf('BV2')), const Rect.fromLTWH(0, screen - 300, 440, screen));
      final dim = tester.widget<Opacity>(find.ancestor(of: pageOf('BV2'), matching: find.byType(Opacity)).first);
      expect(dim.opacity, VerticalCleanTheme.movingOpacity);
      drag.end(0);
      await settle(tester);
    });

    testWidgets("an upright video's still is its own shape in the upright band, its first frame before its cover",
        (tester) async {
      final upright = FakeStoryFeed([
        storyEntry('BV1'),
        storyEntry('BV2', cover: pic('cover'), firstFrame: pic('BV2')),
      ]);
      addTearDown(upright.dispose);
      pager.feed = upright;
      await show(tester);
      final band = 956 * BiliMetrics.verticalUprightCentre * 2;
      const height = 440 * 16 / 9;
      expect(tester.getRect(stillOf('BV2')), Rect.fromLTWH(0, screen + band / 2 - height / 2, 440, height));
      expect(tester.widget<RemoteImage>(stillOf('BV2')).preset, CoverPreset.exact);
    });

    testWidgets('the video before waits one screen above; the one landed on holds its still in place', (tester) async {
      final pictured = FakeStoryFeed([
        storyEntry('BV1', cover: pic('BV1')),
        storyEntry('BV2', cover: pic('BV2')),
        storyEntry('BV3', cover: pic('BV3')),
      ]);
      addTearDown(pictured.dispose);
      pager.feed = pictured;
      await show(tester);
      expect(pageOf('BV1'), findsNothing, reason: 'nothing before the first');
      expect(tester.getRect(pageOf('BV2')).top, screen);
      final element = tester.element(stillOf('BV2'));

      expect(pager.moveNext(), isTrue);
      await settle(tester);
      expect(tester.getRect(pageOf('BV1')).top, -screen);
      expect(tester.getRect(pageOf('BV3')).top, screen);
      expect(pageOf('BV2'), findsNothing, reason: 'its live controls are the page');
      expect(tester.getRect(stillOf('BV2')).top, greaterThanOrEqualTo(0));
      expect(tester.getRect(stillOf('BV2')).bottom, lessThanOrEqualTo(screen));
      expect(identical(tester.element(stillOf('BV2')), element), isTrue, reason: 'the same picture, no reload');

      pager.framed('BV2');
      await tester.pump();
      expect(stillOf('BV2'), findsNothing);
    });

    testWidgets('they take no touches and say nothing to VoiceOver', (tester) async {
      await show(tester);
      final preview = find.byType(VerticalChromePreview).first;
      expect(
        tester.widgetList<IgnorePointer>(find.ancestor(of: preview, matching: find.byType(IgnorePointer))),
        contains(isA<IgnorePointer>().having((widget) => widget.ignoring, 'ignoring', isTrue)),
      );
      expect(
        tester.widgetList<ExcludeSemantics>(find.ancestor(of: preview, matching: find.byType(ExcludeSemantics))),
        contains(isA<ExcludeSemantics>().having((widget) => widget.excluding, 'excluding', isTrue)),
      );
    });
  });
}
