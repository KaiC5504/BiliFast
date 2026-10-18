import 'package:bili_core/api.dart' show VideoTag, VideoTagKind;
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/intro/tag_chips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const bgm = VideoTag(id: 1, name: '晴天', kind: VideoTagKind.bgm);
const topic = VideoTag(id: 2, name: '动漫', kind: VideoTagKind.topic);
const plain = VideoTag(id: 3, name: '必剪创作', kind: VideoTagKind.normal);
const long = VideoTag(id: 4, name: '一个很长很长很长很长很长的话题名字', kind: VideoTagKind.topic);

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

  testWidgets('a long name is cut at the chip, then scrolls round once and comes to rest', (tester) async {
    await show(tester, const [long]);

    final name = find.byType(ChipName);
    double shift() => tester
        .widget<Transform>(find.descendant(of: name, matching: find.byType(Transform)).first)
        .transform
        .getTranslation()
        .x;
    expect(tester.getSize(name).width, IntroListTheme.chipTextMax);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump(IntroListTheme.marqueeRest);
    expect(shift(), 0);
    await tester.pump(const Duration(seconds: 2));
    expect(shift(), lessThan(0));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.getSize(name).width, IntroListTheme.chipTextMax);
  });

  testWidgets('with reduced motion a long name stays still', (tester) async {
    await show(tester, const [long], still: true);

    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.getSize(find.byType(ChipName)).width, IntroListTheme.chipTextMax);
  });

  testWidgets('a short name takes only its own width and never moves', (tester) async {
    await show(tester, const [topic]);

    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.getSize(find.byType(ChipName)).width, lessThan(IntroListTheme.chipTextMax));
  });
}
