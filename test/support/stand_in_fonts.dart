import 'dart:io';

import 'package:flutter/services.dart';

/// The families the system path's text asks for: the Cupertino typography's on iOS, Material's Roboto where a test
/// keeps Android, and the emoji and PingFang SC every style falls back to. The test font manager answers any family it
/// doesn't know with the square test font, which has some Han glyphs (本), so emoji is given the Chinese stand-in too:
/// there is no emoji stand-in, and what PingFang draws on the phone must not stop at the square font first.
const _latinFamilies = ['CupertinoSystemText', 'CupertinoSystemDisplay', 'Roboto'];
const _chineseFamilies = ['Apple Color Emoji', 'PingFang SC'];
const _latinStyles = ['Regular', 'Medium', 'Semibold', 'Bold'];
const _chineseStyles = ['Regular', 'Medium', 'Semibold'];

bool _loaded = false;

/// Loads the iPhone's system font for a test that renders under it (`BiliFonts.family = BiliFonts.system`): stand-ins for SF and
/// PingFang SC (test/fonts, made by tools/make_standin_fonts.py) with their line metrics and ink, so Chinese lines
/// break and sit as on the phone and Latin comes close. Without them the system path draws Flutter's square test font.
Future<void> loadSystemFontStandIns() async {
  if (_loaded) return;
  Future<ByteData> read(String name) async => ByteData.sublistView(await File('test/fonts/$name.ttf').readAsBytes());
  for (final family in _latinFamilies) {
    final loader = FontLoader(family);
    for (final style in _latinStyles) {
      loader.addFont(read('StandInText-$style'));
    }
    await loader.load();
  }
  for (final family in _chineseFamilies) {
    final loader = FontLoader(family);
    for (final style in _chineseStyles) {
      loader.addFont(read('StandInSC-$style'));
    }
    await loader.load();
  }
  _loaded = true;
}
