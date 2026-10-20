import 'dart:io';

import 'package:bilifast/shared/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String? saved;
  setUp(() => saved = BiliFonts.family);
  tearDown(() => BiliFonts.family = saved);

  test('in tests the system font falls back to the PingFang stand-in; MiSans needs no fallback', () {
    BiliFonts.family = BiliFonts.system;
    expect(BiliFonts.fallback, ['PingFang SC']);
    BiliFonts.family = BiliFonts.miSans;
    expect(BiliFonts.fallback, isNull);
  });

  // iOS's engine registers no CupertinoSystemText, so a family the phone has in a fallback list draws every run of the
  // system font: 1.0.0 (15) listed Apple Color Emoji and drew digits and spaces emoji-wide and low.
  test('on the phone the system font names no fallback: nothing in the app sets one, and every list goes through it',
      () {
    final theme = File('lib/shared/theme.dart').readAsStringSync();
    expect(theme, contains('static List<String>? systemFallback;'));
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      expect(RegExp(r'systemFallback\s*=[^=]').hasMatch(source), isFalse, reason: file.path);
      for (final line in source.split('\n').where((line) => line.contains('fontFamilyFallback:'))) {
        expect(line, contains('BiliFonts.fallback'), reason: '${file.path}: $line');
      }
    }
  });

  test('sizes measured off the official app under the system font (font-check 02, 04); MiSans keeps its own', () {
    BiliFonts.family = BiliFonts.system;
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
