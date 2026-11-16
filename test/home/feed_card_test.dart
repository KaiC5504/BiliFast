import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bili_core/api.dart';
import 'package:bili_core/logic.dart' show CountFormat;
import 'package:bilifast/app/zoom_back_route.dart';
import 'package:bilifast/home/feed_card.dart';
import 'package:bilifast/shared/cover_placeholder.dart';
import 'package:bilifast/shared/cover_preset.dart';
import 'package:bilifast/shared/image_disk_cache.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/space/uploader_tap.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import '../support/system_font.dart';
import '../video/mixed_lines.dart' show appTheme;
import 'feed_fakes.dart';

/// From the UP icon's ink to the name's layout box. 01 has 17 px from ink to ink; the name's first glyph ("4") sets
/// its ink a little into its box.
const _upNameGap = 5.0;

Future<Uint8List> _coverPng() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 4, 3), Paint()..color = const Color(0xFF808080));
  final image = await recorder.endRecording().toImage(4, 3);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

/// A phone-shaped view. Setting a pixel ratio alone keeps flutter_test's default physical size, which at a lower
/// ratio reads as a screen past [FormFactor]'s 700 pt cut, an iPad, whose card is another.
void _asPhone(WidgetTester tester, {double ratio = 3}) {
  tester.view
    ..devicePixelRatio = ratio
    ..physicalSize = const Size(440, 956) * ratio;
  addTearDown(tester.view.reset);
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
      _asPhone(tester, ratio: ratio);
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

  testWidgets("the cover names 推荐's preset", (tester) async {
    _asPhone(tester);
    await tester.pumpWidget(
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
    final cover = tester.widget<RemoteImage>(
      find.descendant(of: find.byType(Hero), matching: find.byType(RemoteImage)),
    );
    expect((cover.cover, cover.preset), (true, CoverPreset.feed));
  });

  testWidgets('precacheCover readies the very picture the card draws: the card shows it its first frame, from the one '
      'download', (tester) async {
    _asPhone(tester);
    final picture = (await tester.runAsync(_coverPng))!;
    final folder = (await tester.runAsync(() => Directory.systemTemp.createTemp('feed_precache')))!;
    final downloads = <String>[];
    final cache = ImageDiskCache(
      folder: folder.path,
      fetch: (url, _) async {
        downloads.add('$url');
        return picture;
      },
    );
    ImageDiskCache.shared = cache;
    addTearDown(() {
      ImageDiskCache.shared = null;
      imageCache
        ..clear()
        ..clearLiveImages();
    });
    final precached = FeedCard.fromJson(
      jsonDecode(jsonEncode({...feedItem('BV1early'), 'pic': 'http://i1.hdslb.com/bfs/archive/precached.jpg'})),
    );
    const width = 211.0;
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (built) {
            context = built;
            return const SizedBox();
          },
        ),
      ),
    );
    final ready = await tester.runAsync(
      () => FeedCardView.precacheCover(context, precached.cover, FeedCardSize.cover(width)),
    );
    expect(ready, isTrue);
    expect(downloads, hasLength(1));

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: FeedCardView(card: precached, onOpen: (_) {}, onWatchLater: () {}),
          ),
        ),
      ),
    );
    final network = find.descendant(
      of: find.byType(Hero),
      matching: find.byWidgetPredicate((widget) => widget is Image && widget.image is! AssetImage),
    );
    final drawn = tester.widget<RawImage>(find.descendant(of: network, matching: find.byType(RawImage)));
    expect(drawn.image, isNotNull, reason: "the precache's provider is the card's, already decoded");
    expect(downloads, hasLength(1), reason: 'no second address');
    var stored = false;
    unawaited(cache.settle().then((_) => stored = true));
    for (var i = 0; i < 50 && !stored; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.runAsync(() => folder.delete(recursive: true));
  });

  group('the counts over the cover', () {
    Future<void> show(WidgetTester tester) {
      _asPhone(tester);
      return tester.pumpWidget(
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
    }

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

  group("the footer's uploader", () {
    FeedCard footerCard({
      String? reason,
      bool vertical = false,
      int mid = 7,
      String owner = '4K杜比视界Relaxation',
      String face = 'https://i0.hdslb.com/bfs/face/up.jpg',
    }) => FeedCard(
      aid: 1,
      bvid: 'BV1footer',
      cid: 1,
      title: '超震撼的 8K 视频用于 OLED 显示测试',
      cover: '',
      duration: 794,
      views: 1930,
      danmaku: 0,
      ownerName: owner,
      ownerMid: mid,
      ownerFace: face,
      reason: reason,
      isVertical: vertical,
    );

    /// The card on 01's 211 pt column inside a page's [UploaderTap], which records each uploader it is asked to open.
    Future<({List<UploaderRef> opened, List<ZoomSource> videos})> show(WidgetTester tester, FeedCard shown) async {
      _asPhone(tester);
      final opened = <UploaderRef>[];
      final videos = <ZoomSource>[];
      await tester.pumpWidget(
        MaterialApp(
          home: UploaderTap(
            open: opened.add,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 211,
                child: FeedCardView(card: shown, onOpen: videos.add, onWatchLater: () {}),
              ),
            ),
          ),
        ),
      );
      return (opened: opened, videos: videos);
    }

    final icon = find.byKey(const ValueKey('card-up-icon'));
    final name = find.text('4K杜比视界Relaxation');

    testWidgets("a plain card shows the official UP icon in the name's grey, not a drawn box, where 01 has it", (
      tester,
    ) async {
      await show(tester, footerCard());
      expect(find.text('UP'), findsNothing);
      final picture = tester.widget<Image>(icon);
      expect((picture.image as AssetImage).assetName, 'assets/images/card/up_badge.png');
      expect((picture.width, picture.height), (40 / 3, 34 / 3));
      expect((picture.color, picture.colorBlendMode), (BiliColors.secondaryText, BlendMode.srcIn));
      final card = tester.getRect(find.byType(FeedCardView));
      final drawn = tester.getRect(icon);
      expect(drawn.left - card.left, moreOrLessEquals(28 / 3), reason: "01's ink starts 28 px into the card");
      expect(
        card.bottom - drawn.center.dy,
        moreOrLessEquals(FeedCardSize.footerHeight / 2 - 1 / 3),
        reason: "01's ink is 1 px under the footer's middle",
      );
      expect(name, findsOneWidget);
    });

    testWidgets('a reason tag stands in place of the uploader: the tag, then nothing until ⋮ (01, 2万点赞)', (
      tester,
    ) async {
      await show(tester, footerCard(reason: '2万点赞'));
      expect(find.text('2万点赞'), findsOneWidget);
      expect(name, findsNothing);
      expect(icon, findsNothing);
      expect(find.byKey(const ValueKey('card-uploader')), findsNothing);
      expect(find.byKey(const ValueKey('card-more')), findsOneWidget);
    });

    testWidgets('a 竖屏 card keeps the name after its tag, with no UP icon (01, cards 1 and 3)', (tester) async {
      await show(tester, footerCard(vertical: true));
      expect(find.text('竖屏'), findsOneWidget);
      expect(name, findsOneWidget);
      expect(icon, findsNothing);
      expect(tester.getRect(name).left, greaterThan(tester.getRect(find.text('竖屏')).right));
    });

    Rect pill(WidgetTester tester, String text) =>
        tester.getRect(find.ancestor(of: find.text(text), matching: find.byType(Container)).first);

    testWidgets("01's 竖屏 pill is 28 pt, so the name's box starts 40 pt into the card (46 on 01, its card 6 pt in)", (
      tester,
    ) async {
      await show(tester, footerCard(vertical: true));
      final card = tester.getRect(find.byType(FeedCardView));
      final tag = pill(tester, '竖屏');
      expect(tag.left - card.left, BiliMetrics.cardInset);
      expect(tag.width, moreOrLessEquals(28));
      expect(tester.getRect(name).left - card.left, moreOrLessEquals(40));
    });

    testWidgets("a reason tag keeps its 4 pt sides (01's 2万点赞)", (tester) async {
      await show(tester, footerCard(reason: '2万点赞'));
      expect(pill(tester, '2万点赞').width, moreOrLessEquals(tester.getSize(find.text('2万点赞')).width + 8));
    });

    testWidgets('an uploader with no name opens nothing: the footer is part of the card', (tester) async {
      final shown = await show(tester, footerCard(owner: ''));
      expect(find.byKey(const ValueKey('card-uploader')), findsNothing);
      expect(find.byKey(const ValueKey('card-uploader-semantics')), findsNothing);
      await tester.tap(icon);
      await tester.pump();
      expect(shown.opened, isEmpty);
      expect(shown.videos, hasLength(1));
    });

    testWidgets('an uploader with no face opens their space with none, not an empty address', (tester) async {
      final shown = await show(tester, footerCard(face: ''));
      await tester.tap(name);
      await tester.pump();
      expect([for (final up in shown.opened) (up.mid, up.name, up.face)], [(7, '4K杜比视界Relaxation', null)]);
    });

    for (final vertical in [false, true]) {
      testWidgets('${vertical ? 'on a 竖屏 card ' : ''}a tap on the name opens the uploader as drawn, and not the '
          'video', (tester) async {
        final shown = await show(tester, footerCard(vertical: vertical));
        await tester.tap(name);
        await tester.pump();
        expect(shown.videos, isEmpty);
        expect([for (final up in shown.opened) (up.mid, up.name, up.face)], [
          (7, '4K杜比视界Relaxation', 'https://i0.hdslb.com/bfs/face/up.jpg'),
        ]);
        if (!vertical) {
          await tester.tap(icon);
          await tester.pump();
          expect(shown.opened, hasLength(2), reason: 'the UP icon is part of the same tap');
          expect(shown.videos, isEmpty);
        }
      });
    }

    testWidgets("a finger held on the name doesn't shrink the card, as one on the title does", (tester) async {
      final shown = await show(tester, footerCard());
      double scale() => tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

      final onName = await tester.startGesture(tester.getCenter(name));
      await tester.pump(const Duration(milliseconds: 300));
      expect(scale(), 1);
      await onName.up();
      await tester.pumpAndSettle();
      expect(shown.opened, hasLength(1));

      final onTitle = await tester.startGesture(tester.getCenter(find.text(footerCard().title)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(scale(), BiliMetrics.pressedScale);
      await onTitle.up();
      await tester.pumpAndSettle();
      expect(shown.videos, hasLength(1));
      expect(shown.opened, hasLength(1));
    });

    testWidgets('an uploader with no mid opens nothing: the name is part of the card and opens the video', (
      tester,
    ) async {
      final shown = await show(tester, footerCard(mid: 0));
      expect(find.byKey(const ValueKey('card-uploader')), findsNothing);
      expect(find.byKey(const ValueKey('card-uploader-semantics')), findsNothing);
      await tester.tap(name);
      await tester.pump();
      expect(shown.opened, isEmpty);
      expect(shown.videos, hasLength(1));
    });

    testWidgets("the uploader is its own accessibility button, named by the name, so ghosthand can press it", (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final shown = await show(tester, footerCard());
      expect(
        tester.getSemantics(find.byKey(const ValueKey('card-uploader-semantics'))),
        isSemantics(label: '4K杜比视界Relaxation', isButton: true, hasTapAction: true),
      );
      tester.semantics.tap(find.semantics.byLabel('4K杜比视界Relaxation'));
      await tester.pump();
      expect(shown.opened.single.mid, 7);
      expect(shown.videos, isEmpty);
      semantics.dispose();
    });

    testWidgets('look-alike: the footer under the system font against 01 (BILIFAST_SHOTS)', (tester) async {
      final saved = BiliFonts.family;
      addTearDown(() => BiliFonts.family = saved);
      await tester.runAsync(loadSystemFontStandIns);
      await tester.runAsync(loadIconFonts);
      showAsPhone(tester);
      BiliFonts.family = BiliFonts.system;
      const boundary = ValueKey('shot');
      // 01's second column: the card's left edge 669 px in, its column 633 px wide.
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Material(
            color: BiliColors.pageGrey,
            child: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: boundary,
                child: SizedBox(
                  width: 211,
                  child: FeedCardView(card: footerCard(), onOpen: (_) {}, onWatchLater: () {}),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() => precacheImage(const AssetImage('assets/images/card/up_badge.png'), tester.element(icon)));
      await tester.pump();
      final card = tester.getRect(find.byType(FeedCardView));
      final drawn = tester.getRect(icon);
      expect(drawn.left - card.left, moreOrLessEquals(28 / 3));
      expect(tester.getRect(name).left - drawn.right, moreOrLessEquals(_upNameGap));
      final shots = Platform.environment['BILIFAST_SHOTS'];
      if (shots != null) await saveShot(tester, find.byKey(boundary), '$shots/01-card-footer-ours.png');
    });

    testWidgets("look-alike: a 竖屏 card where 01's first is, under the system font (BILIFAST_SHOTS)", (tester) async {
      final saved = BiliFonts.family;
      addTearDown(() => BiliFonts.family = saved);
      await tester.runAsync(loadSystemFontStandIns);
      await tester.runAsync(loadIconFonts);
      showAsPhone(tester);
      BiliFonts.family = BiliFonts.system;
      const boundary = ValueKey('shot');
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Material(
            color: BiliColors.pageGrey,
            child: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: boundary,
                child: Container(
                  width: 440,
                  color: BiliColors.pageGrey,
                  padding: const EdgeInsets.only(left: 6, right: 223),
                  child: FeedCardView(card: footerCard(vertical: true), onOpen: (_) {}, onWatchLater: () {}),
                ),
              ),
            ),
          ),
        ),
      );
      expect(pill(tester, '竖屏').left, 14);
      expect(pill(tester, '竖屏').right, moreOrLessEquals(42));
      expect(tester.getRect(name).left, moreOrLessEquals(46));
      final shots = Platform.environment['BILIFAST_SHOTS'];
      if (shots != null) await saveShot(tester, find.byKey(boundary), '$shots/01-card-vertical-ours.png');
    });
  });

  group("the iPad card's uploader", () {
    FeedCard padCard({int mid = 7, String face = 'https://i0.hdslb.com/bfs/face/up.jpg'}) => FeedCard(
      aid: 1,
      bvid: 'BV1padup',
      cid: 1,
      title: '奶家人捉迷藏大赛：幽邃地窟篇',
      cover: '',
      duration: 254,
      views: 594000,
      danmaku: 77,
      ownerName: '暴风城老鼠',
      ownerMid: mid,
      ownerFace: face,
      reason: null,
      isVertical: false,
      published: 1761700000,
    );

    Future<({List<UploaderRef> opened, List<ZoomSource> videos})> show(WidgetTester tester, FeedCard shown) async {
      showAsPad(tester);
      final opened = <UploaderRef>[];
      final videos = <ZoomSource>[];
      await tester.pumpWidget(
        MaterialApp(
          home: UploaderTap(
            open: opened.add,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 255,
                child: FeedCardView(card: shown, onOpen: videos.add, onWatchLater: () {}),
              ),
            ),
          ),
        ),
      );
      return (opened: opened, videos: videos);
    }

    final byline = find.byKey(const ValueKey('feed-card-byline'));
    final face = find.byKey(const ValueKey('feed-card-face'));
    final target = find.byKey(const ValueKey('card-uploader'));

    testWidgets("the byline's name and the face open the uploader, not the video, and don't shrink the card", (
      tester,
    ) async {
      final shown = await show(tester, padCard());
      final line = tester.getRect(byline);
      final over = tester.getRect(target);
      expect(over.left, line.left);
      expect(over.width, lessThan(line.width), reason: 'the name only, not the date after it');
      expect(over.top, lessThan(line.center.dy));
      expect(over.bottom, greaterThan(line.center.dy));

      double scale() => tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
      final held = await tester.startGesture(tester.getCenter(target));
      await tester.pump(const Duration(milliseconds: 300));
      expect(scale(), 1);
      await held.up();
      await tester.pump();
      final faceTarget = find.byKey(const ValueKey('card-uploader-face'));
      expect(tester.getRect(faceTarget), tester.getRect(face));
      await tester.tap(faceTarget);
      await tester.pump();
      expect(shown.videos, isEmpty);
      const uploader = (7, '暴风城老鼠', 'https://i0.hdslb.com/bfs/face/up.jpg');
      expect([for (final up in shown.opened) (up.mid, up.name, up.face)], [uploader, uploader]);

      await tester.tapAt(Offset(over.right + 20, over.center.dy));
      await tester.pump();
      expect(shown.videos, hasLength(1), reason: 'the date after the name is the card');
    });

    testWidgets('a face-less uploader opens with none', (tester) async {
      final shown = await show(tester, padCard(face: ''));
      await tester.tap(target);
      await tester.pump();
      expect(shown.opened.single.face, isNull);
    });

    testWidgets('an uploader with no mid opens nothing: the byline and face open the video', (tester) async {
      final shown = await show(tester, padCard(mid: 0));
      expect(target, findsNothing);
      await tester.tap(face);
      await tester.pump();
      expect(shown.opened, isEmpty);
      expect(shown.videos, hasLength(1));
    });

    testWidgets('the uploader is its own accessibility button, named by the name', (tester) async {
      final semantics = tester.ensureSemantics();
      final shown = await show(tester, padCard());
      expect(
        tester.getSemantics(find.byKey(const ValueKey('card-uploader-semantics'))),
        isSemantics(label: '暴风城老鼠', isButton: true, hasTapAction: true),
      );
      tester.semantics.tap(find.semantics.byLabel('暴风城老鼠'));
      await tester.pump();
      expect(shown.opened.single.mid, 7);
      expect(shown.videos, isEmpty);
      semantics.dispose();
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
