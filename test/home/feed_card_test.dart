import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bili_core/api.dart';
import 'package:bili_core/logic.dart' show CountFormat;
import 'package:bilifast/home/feed_card.dart';
import 'package:bilifast/shared/cover_placeholder.dart';
import 'package:bilifast/shared/image_disk_cache.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import '../support/system_font.dart';
import 'feed_fakes.dart';

Future<Uint8List> _coverPng() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 4, 3), Paint()..color = const Color(0xFF808080));
  final image = await recorder.endRecording().toImage(4, 3);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

void main() {
  final card = FeedCard.fromJson(jsonDecode(jsonEncode(feedItem('BV1long', title: '很长很长的标题' * 6, reason: '关注的人赞过'))));

  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets('at text scale $scale the card is as tall as FeedCardSize says and nothing overflows', (tester) async {
      const width = 160.0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: FeedCardView(card: card, onOpen: (_) {}, onWatchLater: () {}),
              ),
            ),
          ),
        ),
      );
      final drawn = tester.getSize(find.byType(FeedCardView)).height;
      expect(drawn, closeTo(FeedCardSize.height(width, TextScaler.linear(scale)), 0.01));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets("on 01's 211 pt column a card is 242 pt tall, so with the grid's gap its covers are 248 pt apart", (
    tester,
  ) async {
    expect(FeedCardSize.height(211, TextScaler.noScaling) + BiliMetrics.feedSpacing, moreOrLessEquals(248));
  });

  testWidgets("the cover asks for its own box's exact size in device pixels at the screen's ratio", (tester) async {
    expect(FeedCardSize.cover(211), const Size(211, 158.25));
    addTearDown(tester.view.resetDevicePixelRatio);
    int exact(double pixels) => (pixels - 0.01).ceil();
    for (final ratio in [2.0, 3.0]) {
      tester.view.devicePixelRatio = ratio;
      for (final width in [160.0, 211.0, 300.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: FeedCardView(card: card, onOpen: (_) {}, onWatchLater: () {}),
              ),
            ),
          ),
        );
        final pictures = tester
            .widgetList<Image>(find.descendant(of: find.byType(FeedCardView), matching: find.byType(Image)))
            .map((image) => image.image)
            .whereType<StoredNetworkImage>();
        final box = FeedCardSize.cover(width);
        final (pixelWidth, pixelHeight) = (exact(box.width * ratio), exact(box.height * ratio));
        expect(
          pictures.single.url,
          coverImageUrl(card.cover, width: pixelWidth, height: pixelHeight),
          reason: '$width pt at ${ratio}x',
        );
        expect(pictures.single.box, Size(pixelWidth.toDouble(), pixelHeight.toDouble()));
        if (width == 211 && ratio == 3) expect(pictures.single.box, const Size(633, 475));
      }
    }
  });

  group('the counts over the cover', () {
    Future<void> show(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 211,
            child: FeedCardView(card: card, onOpen: (_) {}, onWatchLater: () {}),
          ),
        ),
      ),
    );

    Rect coverOf(WidgetTester tester) => tester.getRect(find.byType(AspectRatio).first);

    testWidgets("are 01's: the official icons tinted white, 10.33 pt from the cover's left edge, centred with the "
        'digits 13 pt above its bottom', (tester) async {
      await show(tester);
      final cover = coverOf(tester);
      final icons = tester
          .widgetList<Image>(find.descendant(of: find.byType(FeedCardView), matching: find.byType(Image)))
          .where((image) => switch (image.image) {
            AssetImage(:final assetName) => assetName.contains('/card/'),
            _ => false,
          })
          .toList();
      expect([for (final icon in icons) (icon.image as AssetImage).assetName], [
        'assets/images/card/stat_play.png',
        'assets/images/card/stat_danmaku.png',
      ]);
      for (final icon in icons) {
        expect((icon.width, icon.height), (40 / 3, 34 / 3));
        expect((icon.color, icon.colorBlendMode), (BiliColors.onCover, BlendMode.srcIn));
      }
      final play = tester.getRect(find.byWidget(icons.first));
      expect(play.left - cover.left, moreOrLessEquals(31 / 3));
      expect(cover.bottom - play.center.dy, moreOrLessEquals(13));

      final views = find.text(CountFormat.short(card.views));
      final style = tester.renderObject<RenderParagraph>(views).text.style!;
      expect(style.fontSize, 29 / 3);
      expect(style.fontFeatures, isNull, reason: 'proportional figures, as 01 draws "1:13" 15.67 pt wide');
      expect(tester.getRect(views).left - play.right, moreOrLessEquals(BiliMetrics.cardStatIconGap));
      expect(
        cover.bottom - tester.getRect(views).center.dy,
        moreOrLessEquals(13 - BiliMetrics.cardStatTextDrop),
        reason: 'the line set a little low, where its digits land on the icons',
      );
    });

    testWidgets("a cover still loading has no shade under the counts; one that comes shows it the same frame, with no "
        'fade', (tester) async {
      final picture = (await tester.runAsync(_coverPng))!;
      final folder = (await tester.runAsync(() => Directory.systemTemp.createTemp('feed_card')))!;
      final cache = ImageDiskCache(folder: folder.path, fetch: (_, _) async => picture);
      ImageDiskCache.shared = cache;
      addTearDown(() => ImageDiskCache.shared = null);
      await show(tester);

      final shade = find.byWidgetPredicate(
        (widget) => switch (widget) {
          DecoratedBox(decoration: BoxDecoration(gradient: _?)) => true,
          _ => false,
        },
      );
      final over = find.ancestor(of: shade, matching: find.byType(AnimatedOpacity));
      expect(find.byType(CoverPlaceholder), findsOneWidget);
      expect(tester.widget<AnimatedOpacity>(over).opacity, 0, reason: 'the flat official grey while it loads');

      for (var i = 0; i < 30 && tester.widget<AnimatedOpacity>(over).opacity == 0; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      final shown = tester.widget<AnimatedOpacity>(over);
      expect(shown.opacity, 1);
      expect(shown.duration, Duration.zero, reason: 'a late cover pops in, as in 14');
      // The store's file is written on after the picture shows, and its steps wait on frames.
      var stored = false;
      unawaited(cache.settle().then((_) => stored = true));
      for (var i = 0; i < 50 && !stored; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await tester.runAsync(() => folder.delete(recursive: true));
    });
  });

  testWidgets('under the system font, the counts over the cover fall back to PingFang SC', (tester) async {
    Future<void> show() => tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 200,
            child: FeedCardView(card: card, onOpen: (_) {}, onWatchLater: () {}),
          ),
        ),
      ),
    );
    await expectSystemFallback(tester, show, find.text(CountFormat.short(card.views)));
    await expectSystemFallback(tester, show, find.text(FeedCardView.duration(card.duration)));
  });
}
