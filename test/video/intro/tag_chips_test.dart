import 'package:bili_core/api.dart' show VideoTag, VideoTagKind;
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/intro/collection_row.dart' show Chevron;
import 'package:bilifast/video/intro/tag_chips.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const bgm = VideoTag(id: 1, name: '晴天', kind: VideoTagKind.bgm);
const topic = VideoTag(id: 2, name: '动漫', kind: VideoTagKind.topic);
const plain = VideoTag(id: 3, name: '必剪创作', kind: VideoTagKind.normal);
const long = VideoTag(id: 4, name: '一个很长很长很长很长很长的话题名字', kind: VideoTagKind.topic);
const longBgm = VideoTag(id: 5, name: '《グランドエスケープ》（Movie edit）feat.三浦透子', kind: VideoTagKind.bgm);

const row = 440 - BiliMetrics.gutter * 2;

/// The capsule round the [index]th chip's name.
Rect pill(WidgetTester tester, [int index = 0]) =>
    tester.getRect(find.ancestor(of: find.byType(ChipName).at(index), matching: find.byType(Container)).first);

Future<void> show(WidgetTester tester, List<VideoTag> tags, {bool still = false}) async {
  tester.view.physicalSize = const Size(440, 956);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (still) {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  await tester.pumpWidget(
    MaterialApp(
      home: Material(
        child: Align(
          alignment: Alignment.topCenter,
          child: TagChips(tags: tags),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows the BGM and topic chips, not the plain tags', (tester) async {
    await show(tester, const [bgm, plain, topic]);

    expect(find.text('晴天'), findsOneWidget);
    expect(find.text('动漫'), findsOneWidget);
    expect(find.text('必剪创作'), findsNothing);
  });

  testWidgets('capsules 26 tall, the first at the gutter, the row owning its gap above', (tester) async {
    await show(tester, const [bgm, topic]);

    final first = tester.getRect(find.ancestor(of: find.text('晴天'), matching: find.byType(Container)).first);
    expect(first.left, BiliMetrics.gutter);
    expect(first.top, moreOrLessEquals(IntroListTheme.sectionTop));
    expect(first.height, IntroListTheme.chipHeight);
    final second = tester.getRect(find.ancestor(of: find.text('动漫'), matching: find.byType(Container)).first);
    expect(second.left - first.right, moreOrLessEquals(IntroListTheme.chipGap));
  });

  testWidgets('draws nothing without a BGM or topic tag', (tester) async {
    await show(tester, const [plain]);
    expect(tester.getSize(find.byType(TagChips)), Size.zero);

    await show(tester, const []);
    expect(tester.getSize(find.byType(TagChips)), Size.zero);
  });

  testWidgets('the chips lead nowhere yet, so they are labels, not buttons', (tester) async {
    final handle = tester.ensureSemantics();
    await show(tester, const [bgm]);

    final node = tester.getSemantics(find.bySemanticsLabel('晴天'));
    expect(node, isNot(isSemantics(isButton: true)));
    expect(node, isNot(isSemantics(hasTapAction: true)));
    handle.dispose();
  });

  testWidgets('a long name is cut at the chip, half the row when alone (18), then scrolls round once and rests', (
    tester,
  ) async {
    await show(tester, const [long]);

    final name = find.byType(ChipName);
    double shift() => tester
        .widget<Transform>(find.descendant(of: name, matching: find.byType(Transform)).first)
        .transform
        .getTranslation()
        .x;
    expect(pill(tester).width, moreOrLessEquals(row / 2));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump(IntroListTheme.marqueeRest);
    expect(shift(), 0);
    await tester.pump(const Duration(seconds: 2));
    expect(shift(), lessThan(0));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(pill(tester).width, moreOrLessEquals(row / 2));
  });

  testWidgets('three chips share the row, so three long ones would fill it (03)', (tester) async {
    await show(tester, const [longBgm, topic, long]);

    final third = (row - IntroListTheme.chipGap * 2) / 3;
    expect(pill(tester, 0).width, moreOrLessEquals(third));
    expect(pill(tester, 1).width, lessThan(third));
    expect(pill(tester, 2).width, moreOrLessEquals(third));
    await tester.pumpAndSettle();
  });

  testWidgets('a fourth long chip keeps the width of three, and the row scrolls to it', (tester) async {
    const fourth = VideoTag(id: 6, name: '第四个很长很长很长很长的话题', kind: VideoTagKind.topic);
    await show(tester, const [longBgm, long, long, fourth]);

    final third = (row - IntroListTheme.chipGap * 2) / 3;
    expect(pill(tester, 1).width, moreOrLessEquals(third));
    await tester.drag(find.byType(ListView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    final last = tester.getRect(find.ancestor(of: find.text(fourth.name), matching: find.byType(Container)).first);
    expect(last.width, moreOrLessEquals(third));
    expect(last.right, lessThanOrEqualTo(440));
  });

  testWidgets('only the first name too long for its chip scrolls; a later one ends in … (03)', (tester) async {
    await show(tester, const [longBgm, long]);

    final names = find.byType(ChipName);
    expect(find.descendant(of: names.at(0), matching: find.byType(Transform)), findsWidgets);
    expect(find.descendant(of: names.at(1), matching: find.byType(Transform)), findsNothing);
    final cut = tester.widget<Text>(find.descendant(of: names.at(1), matching: find.byType(Text)));
    expect(cut.overflow, TextOverflow.ellipsis);
    expect(pill(tester, 1).width, moreOrLessEquals((row - IntroListTheme.chipGap) / 2));
    await tester.pumpAndSettle();
  });

  testWidgets('with reduced motion a long name stays still', (tester) async {
    await show(tester, const [long], still: true);

    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(pill(tester).width, moreOrLessEquals(row / 2));
  });

  testWidgets('a name ending in 》 leaves its blank half em out, so the › follows its ink closely (font-check 02)', (
    tester,
  ) async {
    const closing = VideoTag(id: 7, name: '发现《昔涟》', kind: VideoTagKind.bgm);
    await show(tester, const [closing, topic]);
    final painter = TextPainter(
      text: TextSpan(text: closing.name, style: ChipName.style()),
      textDirection: TextDirection.ltr,
    )..layout();
    addTearDown(painter.dispose);
    final shown = painter.width - IntroListTheme.chipText / 2;

    final name = tester.getRect(find.byType(ChipName).first);
    expect(name.width, moreOrLessEquals(shown));
    final chevron = tester.getRect(find.byType(Chevron).first);
    expect(chevron.left - name.right, moreOrLessEquals(IntroListTheme.chipChevronGap));
    expect(pill(tester).right - chevron.right, moreOrLessEquals(IntroListTheme.chipTrailing));
    const chrome =
        IntroListTheme.chipLead +
        IntroListTheme.musicGlyphWidth +
        IntroListTheme.chipIconGap +
        IntroListTheme.chipChevronGap +
        IntroListTheme.chipChevronWidth +
        IntroListTheme.chipTrailing;
    expect(pill(tester).width, moreOrLessEquals(chrome + shown));
    expect(pill(tester, 1).left - pill(tester).right, moreOrLessEquals(IntroListTheme.chipGap));
    final drawn = tester.widget<Text>(find.text(closing.name));
    expect(drawn.overflow, TextOverflow.visible, reason: 'the 》 itself still draws whole');
    expect(drawn.softWrap, isFalse);
  });

  test('a name is measured with the system font\'s fallback, as it is drawn, and with none under MiSans', () {
    final family = BiliFonts.family;
    addTearDown(() => BiliFonts.family = family);

    BiliFonts.family = BiliFonts.system;
    expect(ChipName.style().fontFamilyFallback, ['Apple Color Emoji', 'PingFang SC']);
    BiliFonts.family = BiliFonts.miSans;
    expect(ChipName.style().fontFamilyFallback, isNull);
  });

  testWidgets('under the system font the drawn name falls back as the measured one does', (tester) async {
    final family = BiliFonts.family;
    addTearDown(() => BiliFonts.family = family);
    BiliFonts.family = BiliFonts.system;
    await show(tester, const [bgm]);

    final style = tester.renderObject<RenderParagraph>(find.text('晴天')).text.style!;
    expect(style.fontFamilyFallback, ['Apple Color Emoji', 'PingFang SC']);
  });

  testWidgets('a short name takes only its own width and never moves', (tester) async {
    await show(tester, const [topic]);

    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(pill(tester).width, lessThan(row / 2));
  });
}
