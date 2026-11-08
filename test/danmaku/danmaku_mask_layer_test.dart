import 'package:bili_core/danmaku.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/danmaku/danmaku_layer.dart';
import 'package:bilifast/danmaku/mask/mask_feed.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player/playback_clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_mask_feed.dart';

/// 人像防挡 in the layer: the frame at the playhead, stretched onto the picture, clips the danmaku inside it and
/// leaves the bars around it alone.
final class Rig {
  final time = ManualClock(10000);
  late final clock = PlaybackClock(clock: time.clock);
  final wake = ValueNotifier(0);
  final timeline = DanmakuTimeline()
    ..add([
      DisplayDanmaku(elem: const DanmakuElem(progressMs: 500, content: '弹幕'), text: '弹幕', isOwn: false),
    ]);
  final feed = FakeMaskFeed();
  late final mask = ValueNotifier<MaskFeed?>(feed);

  static const size = Size(400, 300);

  /// A 16:9 picture letterboxed in the layer.
  static const picture = Rect.fromLTWH(0, 37.5, 400, 225);

  Future<void> mount(WidgetTester tester, {Rect? picture = picture, bool mirrored = false, bool withMask = true}) =>
      tester.pumpWidget(
        Center(
          child: SizedBox.fromSize(
            size: size,
            child: DanmakuLayer(
              clock: clock,
              timeline: timeline,
              wake: wake,
              mask: withMask ? mask : null,
              picture: picture,
              mirrored: mirrored,
            ),
          ),
        ),
      );

  DanmakuLayerState state(WidgetTester tester) => tester.state<DanmakuLayerState>(find.byType(DanmakuLayer));

  RenderObject painter(WidgetTester tester) =>
      tester.renderObject(find.descendant(of: find.byType(DanmakuLayer), matching: find.byType(CustomPaint)));

  void play(double at) {
    clock.handle(const StatusChanged(PlayerStatus.playing));
    clock.handle(PositionChanged(seconds: at, hostMs: time.clock.nowMs(), rate: 1));
    wake.value++;
  }

  void pause() {
    clock.handle(const StatusChanged(PlayerStatus.paused));
    wake.value++;
  }

  Future<void> run(WidgetTester tester, double seconds) async {
    const frameMs = 1000 / 120;
    for (var i = 0; i < (seconds * 120).round(); i++) {
      time.advance(frameMs);
      if (clock.running) {
        clock.handle(PositionChanged(seconds: clock.seconds, hostMs: time.clock.nowMs(), rate: 1));
      }
      await tester.pump(const Duration(microseconds: 8333));
    }
  }

  void dispose() {
    mask.dispose();
    wake.dispose();
  }
}

/// The mask's 160×90 box, filled but for a person standing in its middle third.
MaskFrame person() => (
  path: Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(const Rect.fromLTWH(0, 0, 160, 90))
    ..addRect(const Rect.fromLTWH(60, 0, 40, 90)),
  box: const Size(160, 90),
);

PaintPattern clipsTo({Iterable<Offset> includes = const [], Iterable<Offset> excludes = const []}) =>
    paints..clipPath(pathMatcher: isPathThat(includes: includes, excludes: excludes));

Matcher get unclipped => paintsExactlyCountTimes(#clipPath, 0);

void main() {
  late Rig rig;
  setUp(() => rig = Rig());
  tearDown(() => rig.dispose());

  group('the picture', () {
    const box = Size(440, 956);

    test('适应 fits the video, centred: a wide one letterboxed, an upright one pillarboxed', () {
      expect(
        videoPicture(box, fit: FitMode.fit, video: const Size(1920, 1080)),
        rectMoreOrLessEquals(const Rect.fromLTWH(0, 354.25, 440, 247.5)),
      );
      expect(
        videoPicture(const Size(956, 440), fit: FitMode.fit, video: const Size(1080, 1920)),
        rectMoreOrLessEquals(const Rect.fromLTWH((956 - 247.5) / 2, 0, 247.5, 440)),
      );
    });

    test('填充 covers the box, past its edges', () {
      final cover = videoPicture(const Size(956, 440), fit: FitMode.fill, video: const Size(1920, 1080))!;
      expect(cover.width, 956);
      expect(cover.height, closeTo(956 * 9 / 16, 1e-9));
      expect(cover.center, const Offset(478, 220));
      expect(cover.top, lessThan(0));
    });

    test('拉伸 is the box; 16:9 and 4:3 are frames of that shape fitted in it, whatever the video', () {
      expect(videoPicture(box, fit: FitMode.stretch, video: const Size(1080, 1920)), Offset.zero & box);
      expect(
        videoPicture(box, fit: FitMode.ratio16x9),
        rectMoreOrLessEquals(const Rect.fromLTWH(0, 354.25, 440, 247.5)),
      );
      expect(
        videoPicture(const Size(956, 440), fit: FitMode.ratio4x3, video: const Size(1920, 1080)),
        rectMoreOrLessEquals(Rect.fromLTWH((956 - 440 * 4 / 3) / 2, 0, 440 * 4 / 3, 440)),
      );
    });

    test('适应 and 填充 wait for the video\'s shape', () {
      expect(videoPicture(box, fit: FitMode.fit), isNull);
      expect(videoPicture(box, fit: FitMode.fill), isNull);
    });
  });

  group('the clip path', () {
    const size = Size(400, 300);
    const picture = Rect.fromLTWH(0, 37.5, 400, 225);

    test('the frame stretched onto the picture: the person is cut out, the rest of the picture and the bars kept', () {
      final path = maskClipPath(person(), picture: picture, mirrored: false, size: size);
      // The person's third, 150 to 250 across, in the picture.
      expect(
        path,
        isPathThat(
          includes: const [Offset(50, 150), Offset(350, 150), Offset(200, 10), Offset(200, 290), Offset(420, 150)],
          excludes: const [Offset(160, 150), Offset(240, 150), Offset(200, 40)],
        ),
      );
    });

    test('mirrored, the frame is flipped about the picture\'s middle', () {
      final frame = (path: Path()..addRect(const Rect.fromLTWH(0, 0, 40, 90)), box: const Size(160, 90));
      final straight = maskClipPath(frame, picture: picture, mirrored: false, size: size);
      final flipped = maskClipPath(frame, picture: picture, mirrored: true, size: size);
      expect(straight, isPathThat(includes: const [Offset(50, 150)], excludes: const [Offset(350, 150)]));
      expect(flipped, isPathThat(includes: const [Offset(350, 150)], excludes: const [Offset(50, 150)]));
    });

    test('a non-zero frame keeps its own rule: a hole wound the other way stays a hole, the bars stay drawable', () {
      final frame = (
        path: Path()
          ..addPolygon(const [Offset(0, 0), Offset(160, 0), Offset(160, 90), Offset(0, 90)], true)
          ..addPolygon(const [Offset(60, 0), Offset(60, 90), Offset(100, 90), Offset(100, 0)], true),
        box: const Size(160, 90),
      );
      expect(frame.path.fillType, PathFillType.nonZero);
      final path = maskClipPath(frame, picture: picture, mirrored: false, size: size);
      expect(path.fillType, PathFillType.nonZero);
      expect(
        path,
        isPathThat(
          includes: const [Offset(50, 150), Offset(200, 10), Offset(-20, 150)],
          excludes: const [Offset(200, 150)],
        ),
      );
    });
  });

  group('the layer', () {
    testWidgets('a frame at the playhead clips the danmaku to it; the bars above and below stay drawable', (
      tester,
    ) async {
      rig.feed.frames = (_) => person();
      await rig.mount(tester);
      rig.play(0);
      await rig.run(tester, 1);
      expect(rig.state(tester).scene.visible, isNotEmpty);
      expect(
        rig.painter(tester),
        clipsTo(includes: const [Offset(50, 150), Offset(200, 20)], excludes: const [Offset(200, 150)]),
      );
    });

    testWidgets('no feed, no frame or no picture: drawn as before, no clip', (tester) async {
      await rig.mount(tester, withMask: false);
      rig.play(0);
      await rig.run(tester, 1);
      expect(rig.painter(tester), unclipped);

      await rig.mount(tester);
      await rig.run(tester, 0.1);
      expect(rig.painter(tester), unclipped, reason: 'no frame for the playhead');

      rig.feed.frames = (_) => person();
      await rig.mount(tester, picture: null);
      await rig.run(tester, 0.1);
      expect(rig.painter(tester), unclipped, reason: 'nowhere to put it');

      await rig.mount(tester);
      await rig.run(tester, 0.05);
      expect(rig.painter(tester), clipsTo(excludes: const [Offset(200, 150)]));
    });

    testWidgets('the frame is looked up by the playhead, not the danmaku\'s eased time, and followed every frame', (
      tester,
    ) async {
      await rig.mount(tester);
      rig.play(0);
      await rig.run(tester, 1);
      // A small jump that the danmaku ease into rather than take at once.
      rig.clock.handle(PositionChanged(seconds: rig.clock.seconds + 0.3, hostMs: rig.time.clock.nowMs(), rate: 1));
      rig.feed.asked.clear();
      rig.feed.followed.clear();
      await rig.run(tester, 1 / 120);
      expect(rig.feed.asked.last, rig.clock.seconds);
      expect(rig.feed.followed.single, rig.clock.seconds);
    });

    testWidgets('paused, frames that land afterwards show without the ticker', (tester) async {
      await rig.mount(tester);
      rig.play(0);
      await rig.run(tester, 1);
      rig.pause();
      await rig.run(tester, 0.1);
      expect(rig.state(tester).ticking, isFalse);
      expect(rig.painter(tester), unclipped);
      expect(tester.binding.hasScheduledFrame, isFalse);

      rig.feed.asked.clear();
      rig.feed.land((_) => person());
      expect(rig.feed.asked.single, rig.clock.seconds);
      expect(tester.binding.hasScheduledFrame, isTrue, reason: 'repainted');
      await tester.pump();
      expect(rig.state(tester).ticking, isFalse);
      expect(rig.painter(tester), clipsTo(excludes: const [Offset(200, 150)]));
    });

    testWidgets('a new feed is followed at once; the old one is let go, and none leaves no clip', (tester) async {
      rig.feed.frames = (_) => person();
      await rig.mount(tester);
      rig.play(0);
      await rig.run(tester, 0.5);
      expect(rig.painter(tester), clipsTo(excludes: const [Offset(200, 150)]));

      final next = FakeMaskFeed();
      addTearDown(next.dispose);
      rig.mask.value = next;
      expect(rig.feed.listened, isFalse);
      expect(next.followed.single, rig.clock.seconds);
      await tester.pump();
      expect(rig.painter(tester), unclipped, reason: 'nothing loaded yet');

      rig.mask.value = null;
      expect(next.listened, isFalse);
      await rig.run(tester, 0.1);
      expect(rig.painter(tester), unclipped);
    });

    testWidgets('the clip is built once per frame and picture, and again when either changes', (tester) async {
      final frame = person();
      rig.feed.frames = (_) => frame;
      await rig.mount(tester);
      rig.play(0);
      await rig.run(tester, 0.5);
      final clips = <Path>[];
      PaintPattern capture() => paints
        ..clipPath(
          pathMatcher: predicate<Path>((path) {
            clips.add(path);
            return true;
          }),
        );
      expect(rig.painter(tester), capture());
      await rig.run(tester, 0.1);
      expect(rig.painter(tester), capture());
      expect(clips[1], same(clips[0]));

      rig.feed.frames = (_) => person();
      await rig.run(tester, 0.05);
      expect(rig.painter(tester), capture());
      expect(clips[2], isNot(same(clips[1])), reason: 'a new frame');

      await rig.mount(tester, picture: const Rect.fromLTWH(50, 0, 300, 300), mirrored: true);
      await rig.run(tester, 0.05);
      expect(rig.painter(tester), capture());
      expect(clips[3], isNot(same(clips[2])), reason: 'a new picture');
      expect(
        clips[3],
        isPathThat(includes: const [Offset(20, 150), Offset(100, 150)], excludes: const [Offset(200, 150)]),
      );
    });
  });
}
