import 'package:bilifast/shared/theme.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/stand_in_fonts.dart';

TextPainter _laid(String text, {double size = 20, String family = 'CupertinoSystemText'}) => TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontFamily: family, fontFamilyFallback: const ['Apple Color Emoji', 'PingFang SC'], fontSize: size),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

void main() {
  setUpAll(loadSystemFontStandIns);

  test('the system font\'s fallback names the families the stand-ins load', () {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    BiliFonts.family = null;
    expect(BiliFonts.fallback, ['Apple Color Emoji', 'PingFang SC']);
  });

  // Lines are whole points, as on the phone.
  test('Chinese is one em a glyph and sits on PingFang\'s 1.4 em line', () {
    final line = _laid('设置版本', size: 16);
    expect(line.width, 64);
    expect(line.height, (16 * 1.4).roundToDouble());
  });

  test('本 comes from the PingFang stand-in, not the square test font the emoji family would otherwise answer with', () {
    expect(_laid('本').height, closeTo(20 * 1.4, 0.01));
  });

  test('Latin alone takes SF\'s line, and is narrower than the square font', () {
    final line = _laid('KaiC5504', size: 14);
    expect(line.height, (14 * (1980 + 432) / 2048).roundToDouble());
    expect(line.width, inExclusiveRange(14 * 8 * 0.4, 14 * 8 * 0.7));
  });

  test('both Cupertino families and Roboto are the SF stand-in', () {
    final width = _laid('Wi-Fi 1080P').width;
    expect(_laid('Wi-Fi 1080P', family: 'CupertinoSystemDisplay').width, width);
    expect(_laid('Wi-Fi 1080P', family: 'Roboto').width, width);
  });
}
