import 'package:bili_core/api.dart' show PlaySource;
import 'package:bilifast/player_ui/portrait_controls.dart' show FullScreenPainter;
import 'package:bilifast/player_ui/seek_bar.dart';
import 'package:bilifast/player_ui/vertical_chrome_preview.dart';
import 'package:bilifast/video/story/story_feed.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'vertical_chrome_test.dart' show Rig;
import 'vertical_clean_test.dart' show entry;

Future<void> mountPreview(WidgetTester tester, StoryEntry entry) async {
  tester.view
    ..physicalSize = const Size(440, 956)
    ..devicePixelRatio = 1
    ..padding = const FakeViewPadding(top: 62, bottom: 34);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: ColoredBox(color: Colors.black, child: VerticalChromePreview(entry: entry)),
    ),
  );
}

Rect rectOf(WidgetTester tester, String key) => tester.getRect(find.byKey(ValueKey(key)));

void main() {
  testWidgets("a neighbour's controls from its entry, without the top bar", (tester) async {
    await mountPreview(tester, entry('BV2'));
    expect(tester.takeException(), isNull);
    expect(find.text('下一位UP主'), findsOneWidget);
    expect(find.text('2.3万粉丝'), findsOneWidget);
    expect(find.text('关注'), findsOneWidget);
    expect(find.textContaining('下一个视频的标题', findRichText: true), findsOneWidget);
    expect(find.textContaining('55.6万播放', findRichText: true), findsOneWidget);
    for (final count in ['4万', '398', '2230', '3146', '1652']) {
      expect(find.text(count), findsOneWidget, reason: count);
    }
    expect(find.text('发弹幕'), findsOneWidget);
    expect(find.text('详情页'), findsOneWidget);
    expect(find.byKey(const ValueKey('vertical-preview-screen-mode')), findsOneWidget, reason: 'upright');
    expect(find.textContaining('人正在看'), findsNothing);
    expect(find.bySemanticsLabel('返回'), findsNothing);
    expect(find.bySemanticsLabel('更多'), findsNothing);
    final bar = tester.widget<SeekBar>(find.byType(SeekBar));
    expect(bar.position(), 0);
    expect(bar.style, SeekBarStyle.dot);
  });

  testWidgets("it sits exactly where the page's own controls do", (tester) async {
    final rig = Rig()..session.isVertical = true;
    await rig.mount(tester);
    final bar = rectOf(tester, 'vertical-bar');
    final badge = tester.getCenter(find.text('详情页'));
    final field = tester.getTopLeft(find.text('发弹幕'));

    await mountPreview(tester, entry('BV2'));
    expect(rectOf(tester, 'vertical-preview-bar'), bar);
    expect(tester.getCenter(find.text('详情页')), badge);
    expect(tester.getTopLeft(find.text('发弹幕')), field);
    expect(rectOf(tester, 'vertical-preview-screen-mode'), const Rect.fromLTWH(401, 889, 24, 24));
    // 09's column: centred 27 in from the right, its last count's line ending at 860.5.
    expect(tester.getCenter(find.text('1652')).dx, closeTo(413, 0.5));
    expect(rectOf(tester, 'vertical-preview-share').bottom, closeTo(860.5, 0.01));
    expect(rectOf(tester, 'vertical-preview-avatar').left, 13);
    expect(rectOf(tester, 'vertical-preview-title').left, 12);
  });

  testWidgets('a wide neighbour shows the corners; one followed has no pill; a 合集 one reads 合集 · 第N集', (
    tester,
  ) async {
    final wide = StoryEntry(
      bvid: 'BV3',
      title: '标题',
      cover: '',
      ownerMid: 3,
      ownerName: '名字',
      following: true,
      width: 1920,
      height: 1080,
      seasonTitle: '某个合集',
      seasonIndex: 4,
      seasonTotal: 9,
      source: PlaySource.unknown,
    );
    await mountPreview(tester, wide);
    expect(find.byKey(const ValueKey('vertical-preview-screen-mode')), findsNothing);
    expect(
      find.byWidgetPredicate((widget) => widget is CustomPaint && widget.painter is FullScreenPainter),
      findsOneWidget,
    );
    expect(find.text('关注'), findsNothing);
    expect(find.text('已关注'), findsNothing);
    expect(find.textContaining('粉丝'), findsNothing, reason: 'fans unknown');
    final text = tester.renderObject<RenderParagraph>(find.byKey(const ValueKey('vertical-preview-title'))).text;
    expect(text.toPlainText(), allOf(contains('合集'), contains('第4集'), contains('标题')));
    expect(text.toPlainText(), isNot(contains('播放')), reason: 'no plays known');
  });

  testWidgets('takes no touches and says nothing to VoiceOver', (tester) async {
    await mountPreview(tester, entry('BV2'));
    expect(find.bySemanticsLabel('点赞'), findsNothing);
    expect(find.bySemanticsLabel('关注'), findsNothing);
    expect(find.bySemanticsLabel('发弹幕'), findsNothing);
    final ignoring = tester.widgetList<IgnorePointer>(
      find.ancestor(of: find.text('下一位UP主'), matching: find.byType(IgnorePointer)),
    );
    expect(ignoring.any((widget) => widget.ignoring), isTrue);
  });
}
