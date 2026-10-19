import 'package:bili_core/api.dart' hide RichText;
import 'package:bilifast/comments/picture_viewer.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _pictures = [
  CommentPicture(url: 'https://i0.hdslb.com/bfs/new_dyn/a.jpg', width: 1080, height: 2400),
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
    expect(_urls(tester), ['https://i0.hdslb.com/bfs/new_dyn/a.jpg@1080w_2400h.webp']);

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
}
