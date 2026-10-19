import 'dart:ui' as ui;

import 'package:bili_core/api.dart' hide RichText;
import 'package:bilifast/comments/comment_row.dart' show CommentPictures;
import 'package:bilifast/comments/picture_viewer.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _pictures = [
  CommentPicture(url: 'https://i0.hdslb.com/bfs/new_dyn/a.jpg', width: 1080, height: 1920),
  CommentPicture(url: 'http://i0.hdslb.com/bfs/new_dyn/b.png', width: 0, height: 0),
  CommentPicture(url: 'https://example.com/c.jpg', width: 400, height: 300),
];

const _top = 62.0;

final class Rig {
  int closes = 0;

  Future<void> mount(
    WidgetTester tester, {
    List<CommentPicture> pictures = _pictures,
    int initialIndex = 0,
    bool disableAnimations = false,
  }) async {
    tester.view.physicalSize = const Size(1320, 2868);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: const Size(440, 956),
          devicePixelRatio: 3,
          padding: const EdgeInsets.only(top: _top),
          disableAnimations: disableAnimations,
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: PictureViewer(pictures: pictures, initialIndex: initialIndex, onClose: () => closes++),
        ),
      ),
    );
  }
}

List<String> _urls(WidgetTester tester) => [
  for (final image in tester.widgetList<Image>(find.byType(Image))) (image.image as NetworkImage).url,
];

Finder get _count => find.byWidgetPredicate((widget) => widget is Text && RegExp(r'^\d+/\d+$').hasMatch(widget.data!));

String? _countText(WidgetTester tester) => tester.widgetList<Text>(_count).map((text) => text.data).firstOrNull;

InteractiveViewer _viewer(WidgetTester tester) => tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));

double _scale(WidgetTester tester) => _viewer(tester).transformationController!.value.getMaxScaleOnAxis();

ScrollPhysics? _physics(WidgetTester tester) => tester.widget<PageView>(find.byType(PageView)).physics;

Future<void> _doubleTap(WidgetTester tester, Offset at) async {
  await tester.tapAt(at);
  await tester.pump(kDoubleTapMinTime);
  await tester.tapAt(at);
}

Future<void> _swipe(WidgetTester tester, double dx) async {
  await tester.fling(find.byType(PageView), Offset(dx, 0), 1000);
  await tester.pumpAndSettle();
}

/// An image load the test finishes or fails by hand.
final class _Load extends ImageStreamCompleter {
  void finish(ui.Image image) => setImage(ImageInfo(image: image.clone()));
  void fail() => reportError(exception: Exception('refused'), silent: true);
}

NetworkImage _key(String url) => NetworkImage(url, headers: BiliClient.mediaHeaders);

/// Puts [url] in the image cache as [load], or as an already decoded image.
Future<_Load> _cache(WidgetTester tester, String url, {bool loaded = false}) async {
  final load = _Load();
  PaintingBinding.instance.imageCache.putIfAbsent(_key(url), () => load);
  if (loaded) load.finish(await _image(tester));
  return load;
}

Future<ui.Image> _image(WidgetTester tester) async => (await tester.runAsync(() => createTestImage(width: 4, height: 4)))!;

void _clearImages() {
  PaintingBinding.instance.imageCache
    ..clear()
    ..clearLiveImages();
}

Finder get _spinner => find.byType(CupertinoActivityIndicator);

const _long = CommentPicture(url: 'https://i0.hdslb.com/bfs/new_dyn/long.jpg', width: 1080, height: 8000);
const _longAddress = 'https://i0.hdslb.com/bfs/new_dyn/long.jpg@1080w.webp';

/// The long picture's box: full width and as tall as its shape makes it.
Finder get _longBox => find.byWidgetPredicate((widget) => widget is SizedBox && widget.height == 440 * 8000 / 1080);

void main() {
  testWidgets('opens at the tapped picture on black, fading in, with the count under the safe area', (tester) async {
    final rig = Rig();
    await rig.mount(tester, initialIndex: 1);
    final fade = find.ancestor(of: find.byType(PageView), matching: find.byType(Opacity));
    expect(tester.widget<Opacity>(fade).opacity, 0);
    await tester.pump(CommentTextTheme.viewerFadeIn ~/ 2);
    expect(tester.widget<Opacity>(fade).opacity, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(fade).opacity, 1);

    expect(
      tester
          .widget<ColoredBox>(find.ancestor(of: find.byType(PageView), matching: find.byType(ColoredBox)).first)
          .color,
      CommentTextTheme.viewerBackground,
    );
    expect(_countText(tester), '2/3');
    final count = tester.widget<Text>(_count);
    expect(count.style?.fontSize, CommentTextTheme.viewerCountText);
    expect(count.style?.color, CommentTextTheme.viewerText);
    expect(count.style?.fontFamily, BiliFonts.family);
    expect(tester.getTopLeft(_count).dy, _top + CommentTextTheme.viewerCountTop);
    expect(tester.getCenter(_count).dx, 220);
  });

  testWidgets('under Reduce Motion it is there at once', (tester) async {
    final rig = Rig();
    await rig.mount(tester, disableAnimations: true);
    final fade = find.ancestor(of: find.byType(PageView), matching: find.byType(Opacity));
    expect(tester.widget<Opacity>(fade).opacity, 1);
  });

  testWidgets('pictures load fitted inside the screen, never cropped and never above their own size', (tester) async {
    final rig = Rig();
    await rig.mount(tester, initialIndex: 1);
    await tester.pumpAndSettle();
    expect(_urls(tester), ['https://i0.hdslb.com/bfs/new_dyn/b.png@1320w_2868h.webp']);
    expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);

    await _swipe(tester, 300);
    expect(_urls(tester), ['https://i0.hdslb.com/bfs/new_dyn/a.jpg@1080w_1920h.webp']);

    await rig.mount(tester, initialIndex: 2);
    await tester.pumpAndSettle();
    expect(_urls(tester), ['https://example.com/c.jpg']);
  });

  testWidgets('swipes page between the pictures and the count follows', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    await tester.pumpAndSettle();
    expect(_countText(tester), '1/3');

    await _swipe(tester, -300);
    expect(_countText(tester), '2/3');
    await _swipe(tester, -300);
    expect(_countText(tester), '3/3');
    await _swipe(tester, -300);
    expect(_countText(tester), '3/3');
    await _swipe(tester, 300);
    expect(_countText(tester), '2/3');
    expect(rig.closes, 0);
  });

  testWidgets('one picture shows no count; an out-of-range index opens the last', (tester) async {
    final rig = Rig();
    await rig.mount(tester, pictures: _pictures.take(1).toList());
    await tester.pumpAndSettle();
    expect(_count, findsNothing);

    await rig.mount(tester, pictures: _pictures, initialIndex: 9);
    await tester.pumpAndSettle();
    expect(_countText(tester), '3/3');
  });

  testWidgets('a double tap zooms in around the finger and locks paging; another zooms back out', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    await tester.pumpAndSettle();
    const point = Offset(300, 500);

    await _doubleTap(tester, point);
    await tester.pump();
    await tester.pump(CommentTextTheme.viewerZoomDuration ~/ 2);
    expect(_scale(tester), inExclusiveRange(1, CommentTextTheme.viewerDoubleTapScale));
    await tester.pumpAndSettle();
    final zoomed = _viewer(tester).transformationController!.value;
    expect(zoomed.getMaxScaleOnAxis(), moreOrLessEquals(CommentTextTheme.viewerDoubleTapScale));
    expect(MatrixUtils.transformPoint(zoomed, point), offsetMoreOrLessEquals(point));
    expect(_physics(tester), isA<NeverScrollableScrollPhysics>());
    expect(_viewer(tester).panEnabled, isTrue);

    await _swipe(tester, -300);
    expect(_countText(tester), '1/3');

    await _doubleTap(tester, point);
    await tester.pumpAndSettle();
    expect(_scale(tester), moreOrLessEquals(1));
    expect(_physics(tester), isNull);
    expect(_viewer(tester).panEnabled, isFalse);
    await _swipe(tester, -300);
    expect(_countText(tester), '2/3');
    expect(rig.closes, 0);
  });

  testWidgets('under Reduce Motion a double tap zooms at once', (tester) async {
    final rig = Rig();
    await rig.mount(tester, disableAnimations: true);
    await _doubleTap(tester, const Offset(220, 478));
    await tester.pump();
    expect(_scale(tester), moreOrLessEquals(CommentTextTheme.viewerDoubleTapScale));
    await tester.pumpAndSettle();
  });

  testWidgets('pinching zooms in, no further than the maximum', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    await tester.pumpAndSettle();
    final first = await tester.startGesture(const Offset(170, 478));
    final second = await tester.startGesture(const Offset(270, 478), pointer: 2);
    for (var step = 0; step < 40; step++) {
      await first.moveBy(const Offset(-4, 0));
      await second.moveBy(const Offset(4, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(_scale(tester), greaterThan(2));
    expect(_scale(tester), lessThanOrEqualTo(CommentTextTheme.viewerMaxScale));
    expect(_countText(tester), '1/3');
    expect(_physics(tester), isA<NeverScrollableScrollPhysics>());
    expect(rig.closes, 0);
  });

  testWidgets('a tap closes it, zoomed or not', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(220, 478));
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    expect(rig.closes, 1);

    await _doubleTap(tester, const Offset(220, 478));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(100, 800));
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    expect(rig.closes, 2);

    await rig.mount(tester, pictures: const []);
    await tester.tapAt(const Offset(220, 478));
    await tester.pumpAndSettle();
    expect(rig.closes, 3);
  });

  testWidgets('accessibility: each picture is 图片 i/N, and 关闭 closes', (tester) async {
    final semantics = tester.ensureSemantics();
    final rig = Rig();
    await rig.mount(tester, initialIndex: 1);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('图片 2/3'), findsOneWidget);
    expect(find.bySemanticsLabel('2/3'), findsNothing);
    expect(
      tester.getSemantics(find.bySemanticsLabel('关闭')),
      matchesSemantics(label: '关闭', isButton: true, hasTapAction: true),
    );
    tester.semantics.tap(find.semantics.byLabel('关闭'));
    await tester.pump();
    expect(rig.closes, 1);

    await tester.tap(find.bySemanticsLabel('关闭'));
    await tester.pump();
    expect(rig.closes, 2);
    semantics.dispose();
  });

  testWidgets('pinching in on a picture at full size leaves it at full size', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    await tester.pumpAndSettle();
    expect(_viewer(tester).minScale, 1);
    final first = await tester.startGesture(const Offset(120, 478));
    final second = await tester.startGesture(const Offset(320, 478), pointer: 2);
    for (var step = 0; step < 40; step++) {
      await first.moveBy(const Offset(2, 0));
      await second.moveBy(const Offset(-2, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(_scale(tester), moreOrLessEquals(1));
    expect(_physics(tester), isNull);
  });

  group('loading', () {
    const fullAddress = 'https://i0.hdslb.com/bfs/new_dyn/a.jpg@1080w_1920h.webp';

    Finder image(String url) =>
        find.byWidgetPredicate((widget) => widget is Image && (widget.image as NetworkImage).url == url);
    double thumbnailOpacity(WidgetTester tester, String url) =>
        tester.widget<AnimatedOpacity>(find.ancestor(of: image(url), matching: find.byType(AnimatedOpacity)).first).opacity;
    // The picture's own fade comes after the thumbnail's in the stack the picture builds while it loads.
    double pictureOpacity(WidgetTester tester) => tester
        .widget<AnimatedOpacity>(find.descendant(of: image(fullAddress), matching: find.byType(AnimatedOpacity)).last)
        .opacity;

    testWidgets("the list's thumbnail shows under a spinner until the picture arrives, then fades out", (tester) async {
      _clearImages();
      final full = await _cache(tester, fullAddress);
      final thumbnail = CommentPictures.thumbnail(_pictures[0].url, width: 360);
      await _cache(tester, CommentPictures.thumbnail(_pictures[0].url, width: 180), loaded: true);
      await _cache(tester, thumbnail, loaded: true);
      final rig = Rig();
      await rig.mount(tester, pictures: _pictures.take(1).toList());
      await tester.pump(CommentTextTheme.viewerFadeIn);
      expect(_urls(tester), [fullAddress, thumbnail]);
      expect(_spinner, findsOneWidget);
      final spinner = tester.widget<CupertinoActivityIndicator>(_spinner);
      expect(spinner.color, CommentTextTheme.viewerText);
      expect(spinner.radius, CommentTextTheme.viewerSpinnerRadius);
      expect(tester.getCenter(_spinner), const Offset(220, 478));
      expect(thumbnailOpacity(tester, thumbnail), 1);
      expect(pictureOpacity(tester), 0);

      full.finish(await _image(tester));
      await tester.pump();
      expect(_spinner, findsNothing);
      await tester.pumpAndSettle();
      expect(thumbnailOpacity(tester, thumbnail), 0);
      expect(pictureOpacity(tester), 1);
      expect(find.byType(PictureFailedGlyph), findsNothing);
      _clearImages();
    });

    testWidgets('with no thumbnail cached it waits on black under the spinner; a cached picture shows at once', (
      tester,
    ) async {
      _clearImages();
      final full = await _cache(tester, fullAddress);
      final rig = Rig();
      await rig.mount(tester, pictures: _pictures.take(1).toList());
      await tester.pump();
      expect(_urls(tester), [fullAddress]);
      expect(_spinner, findsOneWidget);
      full.finish(await _image(tester));
      await tester.pumpAndSettle();

      await rig.mount(tester, pictures: const []);
      await rig.mount(tester, pictures: _pictures.take(1).toList());
      await tester.pump();
      expect(_spinner, findsNothing);
      expect(_urls(tester), [fullAddress]);
      expect(find.byType(AnimatedOpacity), findsNothing);
      _clearImages();
    });

    testWidgets('a picture that fails shows the picture glyph in the middle, and a tap still closes', (tester) async {
      _clearImages();
      final full = await _cache(tester, fullAddress);
      await _cache(tester, CommentPictures.thumbnail(_pictures[0].url, width: 360), loaded: true);
      final rig = Rig();
      await rig.mount(tester, pictures: _pictures.take(1).toList());
      await tester.pump();
      expect(find.byType(PictureFailedGlyph), findsNothing);

      full.fail();
      await tester.pump();
      expect(_spinner, findsNothing);
      expect(_urls(tester), [fullAddress]);
      final glyph = find.byType(PictureFailedGlyph);
      expect(glyph, findsOneWidget);
      expect(tester.getSize(glyph), const Size.square(CommentTextTheme.viewerFailedGlyph));
      expect(tester.getCenter(glyph), const Offset(220, 478));

      await tester.tapAt(const Offset(220, 300));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      expect(rig.closes, 1);
      _clearImages();
    });
  });

  group('long pictures', () {
    test("taller than the screen's shape is long, and is asked for by width alone", () {
      const screen = Size(440, 956);
      expect(isLongPicture(_long, screen), isTrue);
      expect(isLongPicture(const CommentPicture(url: 'u', width: 1080, height: 2400), screen), isTrue);
      expect(isLongPicture(_pictures[0], screen), isFalse);
      expect(isLongPicture(_pictures[1], screen), isFalse);
      expect(isLongPicture(_long, Size.zero), isFalse);

      const pixels = Size(1320, 2868);
      expect(viewerAddress(_long, pixels, long: true), _longAddress);
      expect(
        viewerAddress(
          const CommentPicture(url: '//i0.hdslb.com/bfs/new_dyn/w.png', width: 3000, height: 20000),
          pixels,
          long: true,
        ),
        'https://i0.hdslb.com/bfs/new_dyn/w.png@1320w.webp',
      );
      expect(viewerAddress(_long, pixels, long: false), 'https://i0.hdslb.com/bfs/new_dyn/long.jpg@1080w_2868h.webp');
      expect(viewerAddress(_pictures[2], pixels, long: true), 'https://example.com/c.jpg');
    });

    testWidgets('a long picture fills the width from its top and scrolls; it still pages, zooms and closes', (
      tester,
    ) async {
      final rig = Rig();
      await rig.mount(tester, pictures: [_long, _pictures[0]]);
      await tester.pumpAndSettle();
      expect(_urls(tester), [_longAddress]);
      const height = 440 * 8000 / 1080;
      expect(tester.getRect(_longBox), const Rect.fromLTWH(0, 0, 440, height));
      expect(_viewer(tester).constrained, isFalse);
      expect(_viewer(tester).panEnabled, isTrue);
      expect(_physics(tester), isNull);

      final finger = await tester.startGesture(const Offset(220, 800));
      for (var step = 0; step < 30; step++) {
        await finger.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await finger.up();
      await tester.pumpAndSettle();
      final scrolled = tester.getTopLeft(_longBox);
      expect(scrolled.dy, lessThan(-500));
      expect(scrolled.dx, moreOrLessEquals(0));
      expect(_scale(tester), moreOrLessEquals(1));
      expect(_countText(tester), '1/2');
      expect(rig.closes, 0);

      await _doubleTap(tester, const Offset(220, 478));
      await tester.pumpAndSettle();
      expect(_scale(tester), moreOrLessEquals(CommentTextTheme.viewerDoubleTapScale));
      expect(_physics(tester), isA<NeverScrollableScrollPhysics>());
      await _doubleTap(tester, const Offset(220, 478));
      await tester.pumpAndSettle();
      expect(_scale(tester), moreOrLessEquals(1));
      final back = tester.getRect(_longBox);
      expect(back.left, moreOrLessEquals(0));
      expect(back.top, lessThan(0));
      expect(back.bottom, greaterThanOrEqualTo(956));

      await _swipe(tester, -300);
      expect(_countText(tester), '2/2');
      await _swipe(tester, 300);
      expect(_countText(tester), '1/2');
      await tester.tapAt(const Offset(220, 478));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      expect(rig.closes, 1);
    });

    testWidgets("a long picture's spinner and failure glyph sit in the middle of the screen, not of the picture", (
      tester,
    ) async {
      _clearImages();
      final load = await _cache(tester, _longAddress);
      final rig = Rig();
      await rig.mount(tester, pictures: const [_long]);
      await tester.pump();
      expect(tester.getCenter(_spinner), const Offset(220, 478));
      load.fail();
      await tester.pump();
      expect(tester.getCenter(find.byType(PictureFailedGlyph)), const Offset(220, 478));
      expect(tester.getRect(_longBox).height, moreOrLessEquals(440 * 8000 / 1080));
      _clearImages();
    });
  });
}
