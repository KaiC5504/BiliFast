import 'package:bili_core/api.dart';
import 'package:bilifast/dynamic/card/dynamic_card.dart';
import 'package:bilifast/dynamic/card/dynamic_pictures.dart';
import 'package:bilifast/dynamic/card/dynamic_repost.dart';
import 'package:bilifast/dynamic/fake_dynamic_api.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../shared/stored_pictures.dart';
import 'card_host.dart';

const _long = DynamicPicture(url: '', width: 1080, height: 7000);
const _tall = DynamicPicture(url: '', width: 1080, height: 1920);
const _wide = DynamicPicture(url: '', width: 1920, height: 1080);

/// The lone tall frame (29): two cells wide and at most 475:357.5.
const _loneWidth = DynamicCardTheme.pictureCell * 2 + DynamicCardTheme.pictureGap;
const _loneHeight = _loneWidth * DynamicCardTheme.pictureTallest;

void _expectLoneFrame(Size size) {
  expect(size.width, closeTo(_loneWidth, 0.01));
  expect(size.height, closeTo(_loneHeight, 0.01));
}

Finder get _frame => find.byKey(const ValueKey('dynamic-picture-0'));
Finder get _label => find.byKey(const ValueKey('dynamic-picture-long'));

RemoteImage _image(WidgetTester tester, Finder frame) =>
    tester.widget<RemoteImage>(find.descendant(of: frame, matching: find.byType(RemoteImage)));

DynamicItem _repost(List<DynamicPicture> pictures, {String id = 'o1'}) => post(
  'r-$id',
  kind: DynamicKind.forward,
  nodes: const [DynamicTextNode('转发说')],
  original: post(
    id,
    kind: DynamicKind.draw,
    author: const DynamicAuthor(mid: 55, name: '原作者', face: ''),
    nodes: const [DynamicTextNode('原动态的文字')],
    major: DynamicPictures(pictures: pictures),
  ),
);

void main() {
  test('long is taller than DynamicCardTheme.longPicture times the width; an unknown size never is', () {
    expect(DynamicCardTheme.longPicture, 2.6);
    expect(DynamicPictureGrid.isLong(const DynamicPicture(url: '', width: 1000, height: 2600)), isFalse);
    expect(DynamicPictureGrid.isLong(const DynamicPicture(url: '', width: 1000, height: 2601)), isTrue);
    expect(DynamicPictureGrid.isLong(_long), isTrue);
    expect(DynamicPictureGrid.isLong(_tall), isFalse);
    expect(DynamicPictureGrid.isLong(const DynamicPicture(url: '', height: 7000)), isFalse);
  });

  group('a plain post', () {
    testWidgets("29: a long picture alone fills the lone tall frame from its top, 长图 on its bottom right", (
      tester,
    ) async {
      await pumpCardHost(
        tester,
        DynamicCard(
          item: post(
            '1',
            kind: DynamicKind.draw,
            major: const DynamicPictures(pictures: [_long]),
          ),
        ),
      );
      final frame = tester.getRect(_frame);
      expect(frame.left, DynamicCardTheme.gutter);
      _expectLoneFrame(frame.size);
      expect(frame.width, closeTo(240, 0.01));
      expect(_image(tester, _frame).alignment, Alignment.topCenter);

      final label = tester.getRect(_label);
      expect(label.right, closeTo(frame.right - DynamicCardTheme.longLabelRight, 0.01));
      expect(label.bottom, closeTo(frame.bottom - DynamicCardTheme.longLabelBottom, 0.01));
      expect(label.height, closeTo(DynamicCardTheme.longLabelHeight, 0.01));
      final text = tester.getRect(find.descendant(of: _label, matching: find.text('长图')));
      expect(label.width, closeTo(text.width + DynamicCardTheme.longLabelPadding * 2, 0.01));
      expect(text.center.dy, closeTo(label.center.dy, 0.01));
      final box = tester.widget<Container>(_label).decoration! as BoxDecoration;
      expect(box.color, DynamicCardTheme.longLabelFill);
      expect(box.borderRadius, BorderRadius.circular(DynamicCardTheme.longLabelRadius));
      final style = tester.widget<Text>(find.text('长图')).style!;
      expect(style.fontSize, DynamicCardTheme.longLabelText);
      expect(style.color, DynamicCardTheme.longLabelInk);
      expect(style.fontFamily, BiliFonts.family);
    });

    testWidgets('a tall picture under the line keeps the centre crop and no label', (tester) async {
      await pumpCardHost(
        tester,
        DynamicCard(
          item: post(
            '1',
            kind: DynamicKind.draw,
            major: const DynamicPictures(pictures: [_tall]),
          ),
        ),
      );
      _expectLoneFrame(tester.getSize(_frame));
      expect(_image(tester, _frame).alignment, Alignment.center);
      expect(_label, findsNothing);
    });

    testWidgets('grid cells keep their crop and no label, long or not', (tester) async {
      await pumpCardHost(
        tester,
        DynamicCard(
          item: post(
            '1',
            kind: DynamicKind.draw,
            major: const DynamicPictures(pictures: [_long, _long, _tall]),
          ),
        ),
      );
      for (var i = 0; i < 3; i++) {
        expect(_image(tester, find.byKey(ValueKey('dynamic-picture-$i'))).alignment, Alignment.center);
      }
      expect(_label, findsNothing);
    });

    testWidgets("the post page's lone long picture is drawn from its top under 长图 too", (tester) async {
      await pumpCardHost(tester, const DynamicPictureGrid(pictures: [_long], detail: true));
      expect(tester.getSize(_frame).width, 440, reason: "the post page's lone tall frame is the whole width");
      expect(_image(tester, _frame).alignment, Alignment.topCenter);
      expect(_label, findsOneWidget);
    });

    testWidgets('it asks the whole picture by the frame width, so the CDN keeps its top', (tester) async {
      const url = 'https://i1.hdslb.com/bfs/new_dyn/long.jpg';
      final pictures = await StoredPictures.keep(tester);
      await pumpCardHost(
        tester,
        DynamicCard(
          item: post(
            '1',
            kind: DynamicKind.draw,
            major: const DynamicPictures(pictures: [DynamicPicture(url: url, width: 1080, height: 7000)]),
          ),
        ),
      );
      await StoredPictures.arrive(tester);
      final image = tester.widget<Image>(find.descendant(of: _frame, matching: find.byType(Image)));
      expect((image.image as StoredNetworkImage).url, widthImageUrl(url, width: 240));
      expect(image.alignment, Alignment.topCenter);
      expect(pictures.downloads, [widthImageUrl(url, width: 240)]);
      await pictures.drop(tester);
    });

    testWidgets("the frame reads 图片 1/1 and opens the viewer; 长图 isn't read", (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpCardHost(
        tester,
        DynamicCard(
          item: post(
            '1',
            kind: DynamicKind.draw,
            major: const DynamicPictures(pictures: [_long]),
          ),
        ),
      );
      expect(
        tester.getSemantics(_frame),
        matchesSemantics(label: '图片 1/1', isButton: true, isImage: true, hasTapAction: true),
      );
      expect(find.bySemanticsLabel(RegExp('长图')), findsNothing);
      semantics.dispose();
    });
  });

  group('a repost', () {
    testWidgets("29: one picture sits in the post's lone frame, not the row, the label on a long one", (tester) async {
      await pumpCardHost(tester, DynamicCard(item: _repost(const [_long])));
      expect(find.byKey(const ValueKey('dynamic-picture-strip')), findsNothing);
      final block = tester.getRect(find.byKey(const ValueKey('dynamic-repost-block')));
      final text = tester.getRect(find.byKey(const ValueKey('dynamic-repost-text-o1')));
      final frame = tester.getRect(_frame);
      expect(frame.left - block.left, DynamicCardTheme.gutter);
      _expectLoneFrame(frame.size);
      final lastLineMiddle = text.bottom - DynamicCardTheme.textLine / 2;
      expect(frame.top - lastLineMiddle, closeTo(68 / 3, 0.01));
      expect(block.bottom - frame.bottom, closeTo(DynamicCardTheme.repostBottom, 0.01));
      expect(_image(tester, _frame).alignment, Alignment.topCenter);
      expect(_label, findsOneWidget);
      expect(tester.getRect(_label).right, closeTo(frame.right - DynamicCardTheme.longLabelRight, 0.01));
    });

    testWidgets("a wide one takes the plain post's lone wide frame, centred, no label", (tester) async {
      await pumpCardHost(tester, DynamicRepostBlock(original: _repost(const [_wide]).original!));
      final block = tester.getRect(find.byKey(const ValueKey('dynamic-repost-block')));
      final frame = tester.getRect(_frame);
      expect(frame.left - block.left, DynamicCardTheme.gutter);
      expect(frame.width, 440 - DynamicCardTheme.gutter * 2);
      expect(frame.height, closeTo(frame.width * 1080 / 1920, 0.01));
      expect(_image(tester, _frame).alignment, Alignment.center);
      expect(_label, findsNothing);
    });

    testWidgets('136: two or more keep the sideways row, a long one at its shape with no label', (tester) async {
      await pumpCardHost(tester, DynamicRepostBlock(original: _repost(const [_long, _tall]).original!));
      expect(find.byKey(const ValueKey('dynamic-picture-strip')), findsOneWidget);
      expect(tester.getSize(_frame).height, DynamicCardTheme.repostStrip);
      expect(tester.getSize(_frame).width, closeTo(DynamicCardTheme.repostStrip * 1080 / 7000, 0.01));
      expect(_label, findsNothing);
    });

    testWidgets("on the post page a lone picture keeps the list's frame and opens through onOpen", (tester) async {
      final asked = <int>[];
      await pumpCardHost(
        tester,
        DynamicRepostBlock(detail: true, onOpen: asked.add, original: _repost(const [_long]).original!),
      );
      final block = tester.getRect(find.byKey(const ValueKey('dynamic-repost-block')));
      final frame = tester.getRect(_frame);
      expect(frame.left - block.left, DynamicCardTheme.repostDetailInset);
      _expectLoneFrame(frame.size);
      await tester.tap(_frame);
      await tester.pump();
      expect(asked, [0]);
      expect(find.byKey(const ValueKey('dynamic-picture-viewer')), findsNothing);
    });

    testWidgets('a tap opens the viewer at the picture, which lays it full width from its top and scrolls it', (
      tester,
    ) async {
      final host = await pumpCardHost(tester, DynamicCard(item: _repost(const [_long])));
      await tester.tap(_label);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const ValueKey('dynamic-picture-viewer')), findsOneWidget);
      expect(host.opened.posts, isEmpty, reason: 'the picture opens, not the original');
      const height = 440 * 7000 / 1080;
      final whole = find.descendant(
        of: find.byKey(const ValueKey('dynamic-picture-viewer')),
        matching: find.byWidgetPredicate((widget) => widget is SizedBox && widget.height == height),
      );
      expect(tester.getRect(whole), const Rect.fromLTWH(0, 0, 440, height));

      final finger = await tester.startGesture(const Offset(220, 800));
      for (var step = 0; step < 30; step++) {
        await finger.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await finger.up();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.getTopLeft(whole).dy, lessThan(-500));
      expect(
        find.byKey(const ValueKey('dynamic-picture-viewer')),
        findsOneWidget,
        reason: 'a drag scrolls, not closes',
      );
    });
  });

  test("the demo's 全部 opens with 29's two long pictures, ahead of the other kinds", () async {
    final api = FakeDynamicApi.demo();
    final page = await api.feed(DynamicFeedType.all);
    final [repost, plain, ...] = page.items;
    final original = repost.original!;
    expect(repost.kind, DynamicKind.forward);
    expect((original.major! as DynamicPictures).pictures.single.height, 7000);
    expect(DynamicPictureGrid.isLong((original.major! as DynamicPictures).pictures.single), isTrue);
    expect(DynamicPictureGrid.isLong((plain.major! as DynamicPictures).pictures.single), isTrue);
    expect(plain.original, isNull);
    expect(page.items.skip(2).first.id, FakeDynamicApi.demoPosts.first.id);
    expect(await api.detail(original.id), same(original));
  });
}
