import 'package:bilifast/shared/action_glyphs.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/actions/video_actions.dart';
import 'package:bilifast/video/intro/action_row.dart';
import 'package:bilifast/video/intro/triple_ring.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_video_actions.dart';

Future<void> mount(WidgetTester tester, FakeVideoActions actions, {bool still = false}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: const Size(440, 956), disableAnimations: still),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: 440, child: ActionRow(actions: actions)),
        ),
      ),
    ),
  );
}

/// As on the page: in the intro's scroll view, inside the tabs' pager. Both delay a tap's down by kPressTimeout.
Future<void> mountScrolled(WidgetTester tester, FakeVideoActions actions) async {
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(size: Size(440, 956)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: PageView(
          children: [
            SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 200),
                  ActionRow(actions: actions),
                  const SizedBox(height: 1200),
                ],
              ),
            ),
            const SizedBox.expand(),
          ],
        ),
      ),
    ),
  );
}

ActionIcon icon(WidgetTester tester, ActionGlyph glyph) =>
    tester.widget<ActionIcon>(find.byWidgetPredicate((widget) => widget is ActionIcon && widget.glyph == glyph));

Color? textColour(WidgetTester tester, String text) => tester.widget<Text>(find.text(text)).style?.color;

Offset centreOf(WidgetTester tester, String label) => tester.getCenter(find.bySemanticsLabel(label));

void main() {
  testWidgets('five cells: counts in the short form, labels where there is no count', (tester) async {
    final actions = FakeVideoActions(likeCount: 9131, coinCount: 0, favCount: 123456, shareCount: 148);
    await mount(tester, actions);

    expect(find.text('9131'), findsOneWidget);
    expect(find.text('不喜欢'), findsOneWidget);
    expect(find.text('投币'), findsOneWidget);
    expect(find.text('12.3万'), findsOneWidget);
    expect(find.text('148'), findsOneWidget);
    expect(tester.getSize(find.byType(ActionRow)).height, closeTo(ActionTheme.rowHeight, 0.01));

    final left = tester.getTopLeft(find.byType(ActionRow)).dx;
    final xs = [
      for (final label in ['点赞', '不喜欢', '投币', '收藏', '分享']) centreOf(tester, label).dx - left,
    ];
    const cell = (440 - 2 * BiliMetrics.gutter) / 5;
    for (var i = 0; i < 5; i++) {
      expect(xs[i], closeTo(BiliMetrics.gutter + cell * (i + 0.5), 0.5));
    }
  });

  testWidgets('each tap does its own action', (tester) async {
    final actions = FakeVideoActions();
    await mount(tester, actions);

    for (final label in ['点赞', '不喜欢', '投币', '收藏', '分享']) {
      await tester.tap(find.bySemanticsLabel(label));
      await tester.pump();
    }
    expect(actions.calls, ['toggleLike', 'toggleDislike', 'ask coin', 'ask favourites', 'ask share']);
    await tester.pumpAndSettle();
  });

  testWidgets('without the TV keys 不喜欢 is dimmed but still taps through to its toast', (tester) async {
    final actions = FakeVideoActions(dislikeAvailable: false);
    await mount(tester, actions);
    final dimmed = find.ancestor(of: find.text('不喜欢'), matching: find.byType(Opacity));
    expect(tester.widget<Opacity>(dimmed.first).opacity, ActionTheme.unavailableOpacity);

    await tester.tap(find.bySemanticsLabel('不喜欢'));
    expect(actions.calls, ['toggleDislike']);

    actions
      ..dislikeAvailable = true
      ..changed();
    await tester.pump();
    expect(tester.widget<Opacity>(dimmed.first).opacity, 1);
  });

  testWidgets('what is on turns pink, icon and count, with a pop', (tester) async {
    final actions = FakeVideoActions();
    await mount(tester, actions);
    expect(icon(tester, ActionGlyph.like).color, ActionTheme.icon);
    expect(textColour(tester, '9131'), ActionTheme.count);

    actions
      ..liked = true
      ..coins = 1
      ..favorited = true
      ..changed();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final pop = tester.widget<ScaleTransition>(
      find.ancestor(of: find.byWidget(icon(tester, ActionGlyph.like)), matching: find.byType(ScaleTransition)).first,
    );
    expect(pop.scale.value, greaterThan(1));
    await tester.pumpAndSettle();
    expect(pop.scale.value, 1);

    for (final glyph in [ActionGlyph.like, ActionGlyph.coin, ActionGlyph.favourite]) {
      expect(icon(tester, glyph).color, BiliColors.pink, reason: '$glyph');
    }
    expect(icon(tester, ActionGlyph.share).color, ActionTheme.icon);
    expect(textColour(tester, '9131'), BiliColors.pink);
    expect(textColour(tester, '1210'), BiliColors.pink);
    expect(textColour(tester, '3907'), BiliColors.pink);
    expect(textColour(tester, '148'), ActionTheme.count);
  });

  testWidgets('with animations off the colour changes at once and nothing pops', (tester) async {
    final actions = FakeVideoActions();
    await mount(tester, actions, still: true);
    actions
      ..liked = true
      ..changed();
    await tester.pump();
    final pop = tester.widget<ScaleTransition>(
      find.ancestor(of: find.byWidget(icon(tester, ActionGlyph.like)), matching: find.byType(ScaleTransition)).first,
    );
    expect(pop.scale.value, 1);
    expect(icon(tester, ActionGlyph.like).color, BiliColors.pink);
  });

  testWidgets('holding 点赞 fills the rings and does 三连 with a burst, without toggling the like', (tester) async {
    final actions = FakeVideoActions();
    await mount(tester, actions);
    expect(find.byType(TripleRing), findsNWidgets(3));
    final ring = tester.widget<TripleRing>(find.byType(TripleRing).first);

    final press = await tester.startGesture(centreOf(tester, '点赞'));
    await tester.pump(const Duration(milliseconds: 150));
    expect(ring.progress.value, 0);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 600));
    expect(ring.progress.value, closeTo(0.5, 0.05));
    await tester.pump(const Duration(milliseconds: 650));

    expect(actions.calls, ['triple']);
    expect(ring.progress.value, 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(ring.burst.value, greaterThan(0));

    await press.up();
    await tester.pumpAndSettle();
    expect(actions.calls, ['triple']);
  });

  testWidgets('a 三连 that sends nothing (all three done) does not burst', (tester) async {
    final actions = FakeVideoActions()
      ..liked = true
      ..coins = 2
      ..favorited = true;
    await mount(tester, actions);
    final ring = tester.widget<TripleRing>(find.byType(TripleRing).first);

    final press = await tester.startGesture(centreOf(tester, '点赞'));
    await tester.pump(const Duration(milliseconds: 210));
    await tester.pump(const Duration(milliseconds: 1250));
    expect(actions.calls, ['triple']);
    await tester.pump(const Duration(milliseconds: 100));
    expect(ring.burst.value, 0);
    await press.up();
    await tester.pumpAndSettle();
  });

  testWidgets('letting go before the rings fill does nothing at all', (tester) async {
    final actions = FakeVideoActions();
    await mount(tester, actions);
    final ring = tester.widget<TripleRing>(find.byType(TripleRing).first);

    final press = await tester.startGesture(centreOf(tester, '点赞'));
    await tester.pump(const Duration(milliseconds: 210));
    await tester.pump(const Duration(milliseconds: 700));
    expect(ring.progress.value, greaterThan(0.3));
    await press.up();
    await tester.pumpAndSettle();

    expect(actions.calls, isEmpty);
    expect(ring.progress.value, 0);
  });

  testWidgets('a press shorter than the ring delay is an ordinary tap', (tester) async {
    final actions = FakeVideoActions();
    await mount(tester, actions);

    final press = await tester.startGesture(centreOf(tester, '点赞'));
    await tester.pump(const Duration(milliseconds: 150));
    await press.up();
    await tester.pump(const Duration(seconds: 2));

    expect(actions.calls, ['toggleLike']);
  });

  testWidgets('a press that slides off cancels the ring without liking', (tester) async {
    final actions = FakeVideoActions();
    await mount(tester, actions);
    final ring = tester.widget<TripleRing>(find.byType(TripleRing).first);

    final press = await tester.startGesture(centreOf(tester, '点赞'));
    await tester.pump(const Duration(milliseconds: 210));
    await tester.pump(const Duration(milliseconds: 300));
    await press.moveBy(const Offset(0, 80));
    await tester.pumpAndSettle();
    await press.up();

    expect(actions.calls, isEmpty);
    expect(ring.progress.value, 0);
  });

  group('inside the page\'s scroll view and pager', () {
    testWidgets('the ring starts 0.2 s after the finger lands and 三连 fires 1.2 s later', (tester) async {
      final actions = FakeVideoActions();
      await mountScrolled(tester, actions);
      final ring = tester.widget<TripleRing>(find.byType(TripleRing).first);

      final press = await tester.startGesture(centreOf(tester, '点赞'));
      await tester.pump(const Duration(milliseconds: 190));
      expect(ring.progress.value, 0);
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 600));
      expect(ring.progress.value, closeTo(0.5, 0.05));
      await tester.pump(const Duration(milliseconds: 620));
      expect(actions.calls, ['triple']);

      await press.up();
      await tester.pumpAndSettle();
      expect(actions.calls, ['triple']);
    });

    testWidgets('a 0.25 s press is a hold that was let go, not a like', (tester) async {
      final actions = FakeVideoActions();
      await mountScrolled(tester, actions);

      final press = await tester.startGesture(centreOf(tester, '点赞'));
      await tester.pump(const Duration(milliseconds: 250));
      await press.up();
      await tester.pumpAndSettle();
      expect(actions.calls, isEmpty);
    });

    testWidgets('a quick tap still likes', (tester) async {
      final actions = FakeVideoActions();
      await mountScrolled(tester, actions);

      final press = await tester.startGesture(centreOf(tester, '点赞'));
      await tester.pump(const Duration(milliseconds: 50));
      await press.up();
      await tester.pumpAndSettle();
      expect(actions.calls, ['toggleLike']);
    });

    for (final (name, move) in [('a scroll', const Offset(0, -60)), ('a page swipe', const Offset(-60, 0))]) {
      testWidgets('$name that takes the finger before the tap is sure stops the hold', (tester) async {
        final actions = FakeVideoActions();
        await mountScrolled(tester, actions);
        final ring = tester.widget<TripleRing>(find.byType(TripleRing).first);

        final press = await tester.startGesture(centreOf(tester, '点赞'));
        await tester.pump(const Duration(milliseconds: 30));
        await press.moveBy(move);
        await tester.pump(const Duration(milliseconds: 30));
        await tester.pump(const Duration(seconds: 2));
        expect(ring.progress.value, 0);
        expect(actions.calls, isEmpty);
        await press.up();
        await tester.pumpAndSettle();
        expect(actions.calls, isEmpty);
      });
    }
  });

  testWidgets('every cell presses through accessibility, and 点赞 long-presses into 三连', (tester) async {
    final semantics = tester.ensureSemantics();
    final actions = FakeVideoActions(liked: true);
    await mount(tester, actions);

    expect(
      tester.getSemantics(find.bySemanticsLabel('点赞')),
      isSemantics(label: '点赞', value: '9131', isButton: true, isSelected: true, hasTapAction: true),
    );
    for (final label in ['点赞', '不喜欢', '投币', '收藏', '分享']) {
      tester.semantics.tap(find.semantics.byLabel(label));
    }
    tester.semantics.longPress(find.semantics.byLabel('点赞'));
    expect(actions.calls, ['toggleLike', 'toggleDislike', 'ask coin', 'ask favourites', 'ask share', 'triple']);
    semantics.dispose();
  });

  testWidgets('ActionPrompt names line up with the asks the row makes', (tester) async {
    final actions = FakeVideoActions();
    await mount(tester, actions);
    await tester.tap(find.bySemanticsLabel('投币'));
    expect(actions.prompt, ActionPrompt.coin);
  });
}
