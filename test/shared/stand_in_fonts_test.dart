import 'package:bilifast/shared/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/stand_in_fonts.dart';

const _fallback = ['Apple Color Emoji', 'PingFang SC'];

TextPainter _laid(String text, {double size = 20, String family = BiliFonts.system}) => TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontFamily: family, fontFamilyFallback: _fallback, fontSize: size),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

void main() {
  setUpAll(loadSystemFontStandIns);

  test('the system font\'s fallback names the families the stand-ins load', () {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    BiliFonts.family = BiliFonts.system;
    expect(BiliFonts.fallback, _fallback);
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
    expect(line.height, (14 * (1950 + 494) / 2048).roundToDouble());
    expect(line.width, inExclusiveRange(14 * 8 * 0.4, 14 * 8 * 0.7));
  });

  test('both Cupertino families and Roboto are the SF stand-in', () {
    final width = _laid('Wi-Fi 1080P').width;
    expect(_laid('Wi-Fi 1080P', family: 'CupertinoSystemDisplay').width, width);
    expect(_laid('Wi-Fi 1080P', family: 'Roboto').width, width);
  });

  group('BiliFonts.strut', () {
    List<double> baselines(String text, {required bool strut}) {
      final saved = BiliFonts.family;
      addTearDown(() => BiliFonts.family = saved);
      BiliFonts.family = BiliFonts.system;
      const style = TextStyle(fontFamily: BiliFonts.system, fontFamilyFallback: _fallback, fontSize: 14, height: 1.6);
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        strutStyle: strut ? BiliFonts.strut(style) : null,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 60);
      return [for (final line in painter.computeLineMetrics()) line.baseline];
    }

    test('without it a line mixing Latin and Chinese is a point taller and its baseline a point lower', () {
      final chinese = baselines('设置版本设置版本', strut: false);
      final mixed = baselines('KaiC 设置 KaiC 设置', strut: false);
      expect(mixed.first - chinese.first, closeTo(1, 0.01));
      expect(mixed[1] - mixed[0], closeTo(23, 0.01));
    });

    test('with it every line keeps the Chinese pitch and baseline', () {
      final chinese = baselines('设置版本设置版本', strut: true);
      final mixed = baselines('KaiC 设置 KaiC 设置', strut: true);
      expect(mixed.first, chinese.first);
      expect(mixed[1] - mixed[0], closeTo(22, 0.01));
    });

    testWidgets('strutOf takes the height the text inherits', (tester) async {
      final saved = BiliFonts.family;
      addTearDown(() => BiliFonts.family = saved);
      BiliFonts.family = BiliFonts.system;
      StrutStyle? found;
      await tester.pumpWidget(DefaultTextStyle(
        style: const TextStyle(fontSize: 14, height: 1.43),
        child: Builder(builder: (context) {
          found = BiliFonts.strutOf(context, const TextStyle(fontSize: 16));
          return const SizedBox.shrink();
        }),
      ));
      expect(found?.fontSize, 16);
      expect(found?.height, 1.43);
      expect(found?.fontFamily, 'PingFang SC');
      expect(found?.forceStrutHeight, isTrue);
    });

    test('none under MiSans, or for a style with no height', () {
      final saved = BiliFonts.family;
      addTearDown(() => BiliFonts.family = saved);
      BiliFonts.family = BiliFonts.miSans;
      expect(BiliFonts.strut(const TextStyle(fontSize: 14, height: 1.6)), isNull);
      BiliFonts.family = BiliFonts.system;
      expect(BiliFonts.strut(const TextStyle(fontSize: 14)), isNull);
    });
  });
}
