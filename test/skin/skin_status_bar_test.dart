import 'dart:io';
import 'dart:ui' as ui;

import 'package:bili_core/api.dart';
import 'package:bilifast/skin/skin.dart';
import 'package:bilifast/skin/skin_status_bar.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// Stand-in art drawn here, never the official pictures.
const _dark = Color(0xFF161513);
const _light = Color(0xFFF5EBD7);

late Directory _folder;

/// A PNG of [width] × [height] px painted by [paint], in the test's folder.
Future<File> _png(String name, int width, int height, void Function(Canvas canvas, Size size) paint) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder), Size(width.toDouble(), height.toDouble()));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return File('${_folder.path}/$name')..writeAsBytesSync(data!.buffer.asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<File> _solid(String name, Color color, {int width = 1320, int height = 318}) =>
    _png(name, width, height, (canvas, size) => canvas.drawRect(Offset.zero & size, Paint()..color = color));

/// [top] down to [split] px, [bottom] below.
Future<File> _banded(
  String name, {
  required int height,
  required int split,
  required Color top,
  required Color bottom,
}) => _png(name, 1320, height, (canvas, size) {
  canvas
    ..drawRect(Rect.fromLTWH(0, 0, size.width, split.toDouble()), Paint()..color = top)
    ..drawRect(Rect.fromLTRB(0, split.toDouble(), size.width, size.height), Paint()..color = bottom);
});

Skin _skin({File? head, File? tab, File? me, File? video, int? color, bool lightText = false}) => Skin(
  equip: SkinEquip(
    id: 1,
    name: '测试装扮',
    ver: 1,
    packageUrl: '',
    packageMd5: '',
    colors: SkinColors(color: color, lightText: lightText),
  ),
  headBg: head,
  headTabBg: tab,
  headMyself: me,
  headMyselfVideo: video,
);

Future<Skin> _measured(Skin skin) async => skin.withStatusBar(await measureSkinStatusBar(skin));

void main() {
  setUp(() async {
    _folder = await Directory.systemTemp.createTemp('skin_status_bar');
    addTearDown(() => _folder.delete(recursive: true));
  });

  test('a dark header gives white icons on 首页 and 我的 over a skin asking for dark text', () async {
    final skin = await _measured(
      _skin(head: await _solid('head.png', _dark), me: await _solid('me.png', _dark, height: 1320)),
    );
    expect(skin.statusBar!.home, closeTo(_dark.computeLuminance(), 0.002));
    expect(skin.statusBar!.me, closeTo(_dark.computeLuminance(), 0.002));
    expect(skin.lightStatusHome, isTrue);
    expect(skin.lightStatusMe, isTrue);
  });

  test('a light header gives black icons on both over a skin asking for light text', () async {
    final skin = await _measured(
      _skin(head: await _solid('head.png', _light), me: await _solid('me.png', _light, height: 1320), lightText: true),
    );
    expect(skin.statusBar!.home, closeTo(_light.computeLuminance(), 0.01));
    expect(skin.lightStatusHome, isFalse);
    expect(skin.lightStatusMe, isFalse);
  });

  test(
    'only the status bar counts: a header dark behind it and light below is dark, and the other way light',
    () async {
      // At 3× the status bar is the pictures' first 186 px: 首页's head_bg is 106 pt to the top row's bottom, and
      // 我的's square picture runs 440 pt down, so measured whole the light four fifths would win.
      final darkTop = await _banded('dark_top.png', height: 318, split: 186, top: _dark, bottom: _light);
      final lightTop = await _banded('light_top.png', height: 318, split: 186, top: _light, bottom: _dark);
      final darkTopSquare = await _banded('dark_top_square.png', height: 1320, split: 186, top: _dark, bottom: _light);
      final lightTopSquare = await _banded(
        'light_top_square.png',
        height: 1320,
        split: 186,
        top: _light,
        bottom: _dark,
      );
      final tab = await _solid('tab.png', _dark, height: 108);
      final dark = await _measured(_skin(head: darkTop, tab: tab, me: darkTopSquare));
      expect(dark.lightStatusHome, isTrue);
      expect(dark.lightStatusMe, isTrue);
      final light = await _measured(_skin(head: lightTop, tab: tab, me: lightTopSquare, lightText: true));
      expect(light.lightStatusHome, isFalse);
      expect(light.lightStatusMe, isFalse);
    },
  );

  test("each picture is cut as its page cuts it: 首页's about the centre, 我的's from the top", () async {
    // 1320 × 900 px is 440 × 300 pt. Without a tab picture 首页's box is 141.67 tall, so the picture rises 79.17 pt
    // and the status bar shows px 237.5 to 423.5: dark there, light above and below.
    final picture = await _png('cut.png', 1320, 900, (canvas, size) {
      canvas
        ..drawRect(Offset.zero & size, Paint()..color = _light)
        ..drawRect(Rect.fromLTRB(0, 237, size.width, 424), Paint()..color = _dark);
    });
    final skin = await _measured(_skin(head: picture, me: picture));
    expect(skin.lightStatusHome, isTrue);
    expect(skin.lightStatusMe, isFalse, reason: "我的's top 186 px are light");
  });

  test("fine dark lines on a light ground read by their share, as 109's ornament does: white", () async {
    // Half #0A0A0A and half beige: the plain mean, 0.30, would pick black; the log average is 0.13.
    const beige = Color(0xFFD9C9A3);
    final lines = await _png('lines.png', 1320, 1320, (canvas, size) {
      canvas.drawRect(Offset.zero & size, Paint()..color = beige);
      for (var x = 0.0; x < size.width; x += 48) {
        canvas.drawRect(Rect.fromLTWH(x, 0, 24, size.height), Paint()..color = const Color(0xFF0A0A0A));
      }
    });
    final skin = await _measured(_skin(me: lines));
    expect(skin.statusBar!.me, inInclusiveRange(0.10, 0.16));
    expect(skin.lightStatusMe, isTrue);
  });

  test("a see-through picture is judged over what is drawn under it, 首页's grey", () async {
    final clear = await _solid('clear.png', const Color(0x00000000));
    final skin = await _measured(_skin(head: clear, lightText: true));
    expect(skin.statusBar!.home, closeTo(const Color(0xFFF1F2F3).computeLuminance(), 0.01));
    expect(skin.lightStatusHome, isFalse);
  });

  test("a picture that can't be read keeps color_mode's choice", () async {
    final broken = File('${_folder.path}/broken.png')..writeAsBytesSync([for (var i = 0; i < 200; i++) i * 31 % 256]);
    for (final lightText in [true, false]) {
      final skin = await _measured(_skin(head: broken, me: broken, lightText: lightText));
      expect(skin.statusBar!.home, isNull);
      expect(skin.statusBar!.me, isNull);
      expect(skin.lightStatusHome, lightText);
      expect(skin.lightStatusMe, lightText);
    }
    expect(_skin(head: broken, lightText: true).lightStatusHome, isTrue, reason: 'unmeasured, the same');
  });

  test("我的 with a header video goes by the header's text colour, color_mode without one", () async {
    final video = File('${_folder.path}/head_myself_mp4_bg.mp4')..writeAsBytesSync([0, 0, 0, 0x18]);
    final light = await _solid('me.png', _light, height: 1320);
    final white = await _measured(_skin(me: light, video: video, color: 0xFFFFFFFF));
    expect(white.statusBar!.me, isNull, reason: 'the picture under the video is not measured');
    expect(white.lightStatusMe, isTrue);
    expect(
      (await _measured(_skin(me: light, video: video, color: 0xFF222222, lightText: true))).lightStatusMe,
      isFalse,
    );
    expect((await _measured(_skin(me: light, video: video, lightText: true))).lightStatusMe, isTrue);
    expect((await _measured(_skin(me: light, video: video))).lightStatusMe, isFalse);
  });

  test('white wins where its contrast ratio beats black\'s', () {
    expect(SkinStatusBar.whiteOverColor(const Color(0xFF161513)), isTrue);
    expect(SkinStatusBar.whiteOverColor(const Color(0xFF757575)), isTrue);
    expect(SkinStatusBar.whiteOverColor(const Color(0xFF777777)), isFalse);
    expect(SkinStatusBar.whiteOverColor(const Color(0xFFFFFFFF)), isFalse);
  });
}
