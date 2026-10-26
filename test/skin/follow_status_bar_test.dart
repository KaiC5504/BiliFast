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

/// 1320 × 900 px (440 × 300 pt): [top] down to px 360, [bottom] below.
Future<File> _split(String name, {required Color top, required Color bottom}) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
    ..drawRect(const Rect.fromLTWH(0, 0, 1320, 360), Paint()..color = top)
    ..drawRect(const Rect.fromLTRB(0, 360, 1320, 900), Paint()..color = bottom);
  final picture = recorder.endRecording();
  final image = await picture.toImage(1320, 900);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return File('${_folder.path}/$name')..writeAsBytesSync(data!.buffer.asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Skin _skin(File head) => Skin(
  equip: const SkinEquip(id: 1, name: '测试装扮', ver: 1, packageUrl: '', packageMd5: '', colors: SkinColors()),
  headBg: head,
);

void main() {
  setUp(() async {
    _folder = await Directory.systemTemp.createTemp('follow_status_bar');
    addTearDown(() => _folder.delete(recursive: true));
  });

  test("关注's header is 88 pt, cut about the centre over white", () {
    final placement = StatusBarPlacement.follow();
    expect(placement.box, const Size(440, 88));
    expect(placement.alignment, Alignment.center);
  });

  // Without a tab picture 首页's box is 141.67 pt, so the picture rises 79.17 pt and the status bar shows px 237.5 to
  // 423.5; 关注's 88 pt box raises it 106 pt, px 318 to 504. A split at px 360 puts most of one above and most of the
  // other below.
  test("head_bg is measured as 关注 cuts it, apart from 首页: dark below px 360 is white icons on 关注 only", () async {
    final skin = _skin(await _split('dark_below.png', top: _light, bottom: _dark));
    final measured = skin.withStatusBar(await measureSkinStatusBar(skin));
    expect(measured.lightStatusHome, isFalse);
    expect(measured.lightStatusFollow, isTrue);
  });

  test('and dark above it is white icons on 首页 only', () async {
    final skin = _skin(await _split('dark_above.png', top: _dark, bottom: _light));
    final measured = skin.withStatusBar(await measureSkinStatusBar(skin));
    expect(measured.lightStatusHome, isTrue);
    expect(measured.lightStatusFollow, isFalse);
  });

  test("unmeasured, 关注 goes by the skin's color_mode as 首页 does", () {
    final light = Skin(
      equip: const SkinEquip(
        id: 1,
        name: '测试装扮',
        ver: 1,
        packageUrl: '',
        packageMd5: '',
        colors: SkinColors(lightText: true),
      ),
    );
    expect(light.lightStatusFollow, isTrue);
    expect(light.withStatusBar(const SkinStatusBar(home: 0.01)).lightStatusFollow, isTrue, reason: 'no 关注 measure');
    expect(light.withStatusBar(const SkinStatusBar(follow: 0.9)).lightStatusFollow, isFalse);
  });
}
