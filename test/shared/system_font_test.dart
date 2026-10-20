import 'package:bilifast/shared/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String? saved;
  setUp(() => saved = BiliFonts.family);
  tearDown(() => BiliFonts.family = saved);

  test('the system font falls back to emoji, then PingFang SC; MiSans needs no fallback', () {
    BiliFonts.family = null;
    expect(BiliFonts.fallback, ['Apple Color Emoji', 'PingFang SC']);
    BiliFonts.family = BiliFonts.miSans;
    expect(BiliFonts.fallback, isNull);
  });

  test('sizes measured off the official app under the system font (font-check 02, 04); MiSans keeps its own', () {
    BiliFonts.family = null;
    expect(PageTheme.tabLabelText, 12.75);
    expect(PageTheme.danmakuFieldText, 12.75);
    expect(IntroTheme.titleText, 15.25);
    expect(CommentListTheme.threadTitleText, 13.75);
    BiliFonts.family = BiliFonts.miSans;
    expect(PageTheme.tabLabelText, 13.5);
    expect(PageTheme.danmakuFieldText, 13.5);
    expect(IntroTheme.titleText, 16);
    expect(CommentListTheme.threadTitleText, 15);
  });
}
