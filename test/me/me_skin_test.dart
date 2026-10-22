import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/me/me_glyphs.dart';
import 'package:bilifast/me/me_model.dart';
import 'package:bilifast/me/me_page.dart';
import 'package:bilifast/shared/loading_tv.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/skin/skin.dart';
import 'package:bilifast/skin/skin_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'me_page_support.dart';

Finder _key(String key) => find.byKey(ValueKey(key));

final _picture = _key('me-skin-picture');

const _white = Color(0xFFFFFFFF);

/// A 300 px square picture in three bands, top to bottom: as `head_myself_squared_bg` comes.
const _bandA = Color(0xFF203040);
const _bandB = Color(0xFF406020);
const _bandC = Color(0xFF602040);

Future<File> _squarePicture(WidgetTester tester, Directory folder, [String name = 'head.png']) async =>
    (await tester.runAsync(
      () => drawPicture(folder, name, 300, 300, (canvas) {
        for (final (index, color) in [_bandA, _bandB, _bandC].indexed) {
          canvas.drawRect(Rect.fromLTWH(0, 100.0 * index, 300, 100), Paint()..color = color);
        }
      }),
    ))!;

Skin _skin(File picture, {int? color = 0xFFFFFFFF, bool lightText = true, File? video, bool videoLoop = true}) => Skin(
  equip: skinEquip(color: color, lightText: lightText, videoLoop: videoLoop),
  headMyself: picture,
  headMyselfVideo: video,
);

/// 我的 dressed in [skin], its picture decoded.
Future<MeHarness> _showDressed(
  WidgetTester tester,
  Skin skin, {
  MeView view = const MeShown(kaiProfile, kaiCounts),
}) async {
  final harness = await showMe(tester, view: view, skin: skin);
  await settlePicture(tester);
  expect(_picture, findsOneWidget, reason: 'decoded');
  return harness;
}

/// The screen's colour at [at], drawn at 1×.
Future<Color> _pixel(WidgetTester tester, Offset at) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(_key('screen'));
  late Color color;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = (await image.toByteData())!;
    final index = (at.dy.floor() * image.width + at.dx.floor()) * 4;
    color = Color.fromARGB(
      data.getUint8(index + 3),
      data.getUint8(index),
      data.getUint8(index + 1),
      data.getUint8(index + 2),
    );
    image.dispose();
  });
  return color;
}

Color? _textColor(WidgetTester tester, String text) => tester.widget<Text>(find.text(text)).style?.color;

SystemUiOverlayStyle _statusBar(WidgetTester tester) => tester
    .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.descendant(of: find.byType(MePage), matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>)).first,
    )
    .value;

Iterable<T> _painters<T>(WidgetTester tester, [Finder? within]) => tester
    .widgetList<CustomPaint>(
      within == null ? find.byType(CustomPaint) : find.descendant(of: within, matching: find.byType(CustomPaint)),
    )
    .map((paint) => paint.painter)
    .whereType<T>();

int _rules(WidgetTester tester) =>
    tester.widgetList<ColoredBox>(find.byType(ColoredBox)).where((box) => box.color == MeTheme.countRule).length;

/// 87's colours, as 1.0.0 (25) drew them.
void _expectStock(WidgetTester tester, {bool loggedIn = true}) {
  expect(_picture, findsNothing);
  expect(find.byType(SkinVideo), findsNothing);
  expect(_statusBar(tester), SystemUiOverlayStyle.dark);
  for (final painter in _painters<MeTopGlyphPainter>(tester)) {
    expect(painter.color, MeTheme.topGlyph);
  }
  expect(_textColor(tester, '动态'), MeTheme.countLabel);
  if (!loggedIn) return;
  expect(_textColor(tester, 'KaiC5504'), MeTheme.vipName);
  expect(_textColor(tester, 'B币：2.3'), MeTheme.coins);
  expect(_textColor(tester, '13'), MeTheme.count);
  expect(_rules(tester), 2);
}

void main() {
  testWidgets("the picture fills the width from the screen's very top to the list's, cut at the bottom", (
    tester,
  ) async {
    final picture = await _squarePicture(tester, pictureFolder());
    await _showDressed(tester, _skin(picture));

    expect(tester.getRect(_picture), const Rect.fromLTRB(0, 0, 440, 328), reason: 'down to the list, under the card');
    final image = tester.widget<Image>(_picture);
    expect(image.fit, BoxFit.cover);
    expect(image.alignment, Alignment.topCenter);
    // Scaled to 440 wide, each 100 px band is 146.67 pt tall; the third is cut at 328.
    expect(await _pixel(tester, const Offset(5, 10)), _bandA, reason: 'behind the status bar');
    expect(await _pixel(tester, const Offset(5, 140)), _bandA);
    expect(await _pixel(tester, const Offset(5, 155)), _bandB);
    expect(await _pixel(tester, const Offset(5, 260)), _bandB, reason: 'no white above the card');
    expect(await _pixel(tester, const Offset(5, 335)), _white, reason: 'the list');
  });

  testWidgets("109's white fade over its last 62 pt: from the card's top to the list's, over the bands", (
    tester,
  ) async {
    final picture = await _squarePicture(tester, pictureFolder());
    await _showDressed(tester, _skin(picture));

    expect(tester.getRect(_key('me-skin-fade')), const Rect.fromLTRB(0, 266, 440, 328));
    final fade = (tester.widget<DecoratedBox>(_key('me-skin-fade')).decoration as BoxDecoration).gradient!;
    expect(fade.colors.first, const Color(0x00FFFFFF));
    expect(fade.colors.last, _white);
    // 109 at 300 pt: 0.81 white over the art.
    final at300 = await _pixel(tester, const Offset(5, 300));
    expect(at300.r * 255, moreOrLessEquals(_bandC.r * 255 * 0.19 + 255 * 0.81, epsilon: 6));
  });

  testWidgets('a short wide picture fills the height instead, cut at both sides', (tester) async {
    const left = Color(0xFF203040);
    const middle = Color(0xFF406020);
    const right = Color(0xFF602040);
    final folder = pictureFolder();
    final picture = (await tester.runAsync(
      () => drawPicture(folder, 'wide.png', 600, 200, (canvas) {
        canvas
          ..drawRect(const Rect.fromLTWH(0, 0, 250, 200), Paint()..color = left)
          ..drawRect(const Rect.fromLTWH(250, 0, 100, 200), Paint()..color = middle)
          ..drawRect(const Rect.fromLTWH(350, 0, 250, 200), Paint()..color = right);
      }),
    ))!;
    await _showDressed(tester, _skin(picture));

    // 328 / 200 scales it to 984 wide, 272 cut each side: the screen's edges land at 166 and 434 px.
    expect(await _pixel(tester, const Offset(2, 10)), left);
    expect(await _pixel(tester, const Offset(220, 10)), middle);
    expect(await _pixel(tester, const Offset(437, 10)), right);
    expect(await _pixel(tester, const Offset(437, 250)), right, reason: 'no gap under it');
  });

  testWidgets('the picture stays put with the header while the list scrolls under the card', (tester) async {
    final picture = await _squarePicture(tester, pictureFolder());
    await _showDressed(tester, _skin(picture));
    final rest = tester.getRect(_picture);

    final finger = await tester.startGesture(tester.getCenter(_key('me-settings')));
    for (var i = 0; i < 5; i++) {
      await finger.moveBy(const Offset(0, -20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.getRect(_picture), rest);
    expect(tester.getRect(_key('me-list')).top, 328);
    await finger.up();
    await tester.pumpAndSettle();
  });

  testWidgets('without a card the picture ends at the list all the same, its fade the last 62 pt', (tester) async {
    final picture = await _squarePicture(tester, pictureFolder());
    const plain = MeProfile(mid: 7, name: '普通用户', face: '', level: 3, coins: 12.5, bcoin: 0);
    await _showDressed(tester, _skin(picture), view: const MeShown(plain, kaiCounts));

    expect(tester.getRect(_picture), const Rect.fromLTRB(0, 0, 440, 274));
    expect(tester.getRect(_key('me-skin-fade')), const Rect.fromLTRB(0, 212, 440, 274));
  });

  testWidgets('a video plays over the same area, muted, the picture standing in until it draws', (tester) async {
    final folder = pictureFolder();
    final picture = await _squarePicture(tester, folder);
    final video = File('${folder.path}/head.mp4')..writeAsBytesSync([0, 0, 0, 0]);
    await _showDressed(tester, _skin(picture, video: video, videoLoop: false));

    final player = tester.widget<SkinVideo>(find.byType(SkinVideo));
    expect(player.file.path, video.path);
    expect(player.loop, isFalse, reason: "head_myself_mp4_play isn't loop");
    expect(find.descendant(of: find.byType(SkinVideo), matching: _picture), findsOneWidget);
    expect(tester.getRect(find.byType(SkinVideo)), const Rect.fromLTRB(0, 0, 440, 328));
    expect(tester.getRect(_key('me-skin-fade')), const Rect.fromLTRB(0, 266, 440, 328), reason: 'over the video');
    expect(_textColor(tester, 'KaiC5504'), _white);
  });

  testWidgets("109's ink: the top icons, name, ✏️, B币 and 硬币, 空间 › and the counts in the skin's colour", (
    tester,
  ) async {
    final picture = await _squarePicture(tester, pictureFolder());
    await _showDressed(tester, _skin(picture));

    final top = _painters<MeTopGlyphPainter>(tester).toList();
    expect(top, hasLength(4));
    expect(top.map((painter) => painter.color), everyElement(_white));
    expect(_textColor(tester, 'KaiC5504'), _white, reason: 'white, no longer pink');
    final pencil = tester.widget<ColorFiltered>(
      find.descendant(of: _key('me-edit'), matching: find.byType(ColorFiltered)),
    );
    expect(pencil.colorFilter, const ColorFilter.mode(_white, BlendMode.srcIn));
    expect(_textColor(tester, 'B币：2.3'), _white);
    expect(_textColor(tester, '硬币：878'), _white);
    expect(_textColor(tester, '空间'), _white);
    expect(_painters<MeChevronPainter>(tester, _key('me-space')).single.color, _white);
    for (final text in ['0', '13', '动态', '关注', '粉丝']) {
      expect(
        tester.widgetList<Text>(find.text(text)).map((each) => each.style?.color),
        everyElement(_white),
        reason: text,
      );
    }
    expect(_rules(tester), 0, reason: "109 has no rules between the counts");
  });

  testWidgets('the LV badge, 年度大会员, the 大 disc, the card and the list keep their own colours', (tester) async {
    final picture = await _squarePicture(tester, pictureFolder());
    await _showDressed(tester, _skin(picture));

    expect(find.byType(MeLevelBadge), findsOneWidget);
    final pill = tester.widget<Container>(_key('me-vip-label')).decoration! as ShapeDecoration;
    expect(pill.color, MeTheme.vipLabelFill);
    expect(_textColor(tester, '年度大会员'), MeTheme.vipLabelInk);
    expect(find.byKey(const ValueKey('me-vip-badge')), findsOneWidget);
    expect(
      find
          .descendant(of: _key('me-vip-card'), matching: find.byType(ColoredBox))
          .evaluate()
          .map((element) => (element.widget as ColoredBox).color),
      contains(MeTheme.card),
    );
    expect(_textColor(tester, '续订会员'), MeTheme.cardTitle);
    expect(_textColor(tester, '会员中心'), MeTheme.cardButtonInk);
    expect(_textColor(tester, '更多服务'), MeTheme.servicesTitle);
  });

  testWidgets('a skin of another colour, or of none with light text, inks with that; dark text keeps the dark bar', (
    tester,
  ) async {
    final folder = pictureFolder();
    final picture = await _squarePicture(tester, folder);
    final harness = await _showDressed(tester, _skin(picture, color: 0xFF112233, lightText: false));
    expect(_textColor(tester, 'KaiC5504'), const Color(0xFF112233));
    expect(_statusBar(tester), SystemUiOverlayStyle.dark);

    harness.skin.skin = _skin(picture, color: null);
    await tester.pump();
    expect(_textColor(tester, 'KaiC5504'), MeTheme.skinLightInk);
    expect(_statusBar(tester), SystemUiOverlayStyle.light);

    harness.skin.skin = _skin(picture, color: null, lightText: false);
    await tester.pump();
    expect(tester.getRect(_picture), const Rect.fromLTRB(0, 0, 440, 328), reason: 'still dressed');
    expect(_textColor(tester, 'KaiC5504'), MeTheme.vipName, reason: "no colour named: 87's");
    expect(_rules(tester), 2);
  });

  testWidgets('the status bar turns light over a picture asking for light text', (tester) async {
    final picture = await _squarePicture(tester, pictureFolder());
    await _showDressed(tester, _skin(picture));
    expect(_statusBar(tester), SystemUiOverlayStyle.light);
  });

  testWidgets('the pull asks for the skin again beside the model; the TV comes out as before', (tester) async {
    final picture = await _squarePicture(tester, pictureFolder());
    final harness = await _showDressed(tester, _skin(picture));

    final finger = await tester.startGesture(tester.getCenter(_key('me-list')));
    for (var i = 0; i < 15; i++) {
      await finger.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byType(LoadingTv), findsOneWidget);
    expect(harness.skin.refreshes, 0, reason: 'only on release');
    await finger.up();
    await tester.pump();
    expect(harness.skin.refreshes, 1);
    expect(harness.model.refreshes, 1);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  });

  testWidgets('the pull asks for the skin with none equipped too', (tester) async {
    final harness = await showMe(tester);
    await tester.drag(_key('me-list'), const Offset(0, 300));
    await tester.pump();
    expect(harness.skin.refreshes, 1);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  });

  testWidgets("no skin: 87's page, as 1.0.0 (25)", (tester) async {
    await showMe(tester);
    _expectStock(tester);
  });

  testWidgets("logged out: 87's page whatever the skin", (tester) async {
    final picture = await _squarePicture(tester, pictureFolder());
    await showMe(tester, view: const MeLoggedOut(), skin: _skin(picture));
    await settlePicture(tester, rounds: 20);
    _expectStock(tester, loggedIn: false);
    expect(_textColor(tester, '点击登录'), MeTheme.name);
  });

  testWidgets("a skin without 我的's picture leaves 我的 as it was", (tester) async {
    final folder = pictureFolder();
    final bar = await _squarePicture(tester, folder, 'tail.png');
    await showMe(
      tester,
      skin: Skin(equip: skinEquip(), tailBg: bar),
    );
    _expectStock(tester);
  });

  testWidgets('a video without its picture to stand in leaves 我的 as it was', (tester) async {
    final video = File('${pictureFolder().path}/head.mp4')..writeAsBytesSync([0, 0, 0, 0]);
    await showMe(
      tester,
      skin: Skin(equip: skinEquip(), headMyselfVideo: video),
    );
    await settlePicture(tester, rounds: 5);
    _expectStock(tester);
  });

  testWidgets("until its picture has decoded the page keeps 87's look, so white text never lands on white", (
    tester,
  ) async {
    final picture = await _squarePicture(tester, pictureFolder());
    await showMe(tester, skin: _skin(picture));
    _expectStock(tester);
    await settlePicture(tester);
    expect(_textColor(tester, 'KaiC5504'), _white);
  });

  for (final (name, write) in [
    ('missing', (File file) {}),
    ('not a picture', (File file) => file.writeAsStringSync('not a png')),
  ]) {
    testWidgets("a picture $name leaves 87's look", (tester) async {
      final logs = MemorySink();
      Logger.shared.add(logs);
      addTearDown(() => Logger.shared.remove(logs));
      final picture = File('${pictureFolder().path}/head.png');
      write(picture);
      await showMe(tester, skin: _skin(picture));
      await settlePicture(tester, rounds: 20);
      expect(logs.events.map((event) => event.msg), contains('skin picture failed'));
      _expectStock(tester);
    });
  }

  testWidgets('a skin equipped later dresses the page; one taken off undresses it at once', (tester) async {
    final picture = await _squarePicture(tester, pictureFolder());
    final harness = await showMe(tester);
    _expectStock(tester);

    harness.skin.skin = _skin(picture);
    await tester.pump();
    await settlePicture(tester);
    expect(_textColor(tester, 'KaiC5504'), _white);
    expect(_picture, findsOneWidget);

    harness.skin.skin = null;
    await tester.pump();
    _expectStock(tester);
  });
}
