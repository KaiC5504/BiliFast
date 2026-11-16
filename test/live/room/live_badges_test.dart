import 'package:bili_core/api.dart';
import 'package:bilifast/live/live_badges.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );

  testWidgets('荣耀等级: nothing at level 0; the badge and the number on its 36 × 16 capsule', (tester) async {
    await pump(tester, const LiveWealthChip(level: 0));
    expect(find.byKey(const ValueKey('live-wealth')), findsNothing);

    for (final level in [7, 17, 117]) {
      await pump(tester, LiveWealthChip(level: level, onDark: true));
      expect(find.text('$level'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('live-wealth'))),
        const Size(LiveRoomTheme.wealthWidth, LiveRoomTheme.wealthHeight),
      );
    }
    expect(LiveWealthChip.fill(4, onDark: true), LiveRoomTheme.wealthFills[0]);
    expect(LiveWealthChip.fill(25, onDark: true), LiveRoomTheme.wealthFills[1]);
    expect(LiveWealthChip.fill(31, onDark: true), LiveRoomTheme.wealthFills[2]);
    expect(LiveWealthChip.fill(29), LiveRoomTheme.wealthLightFill);
    expect([4, 10, 11, 20, 21, 30, 31, 36].map(LiveWealthChip.tier), [0, 0, 1, 1, 2, 2, 3, 3]);
  });

  testWidgets('a medal: its name and level on its colours; a guard brings the anchor; unlit is grey', (tester) async {
    await pump(tester, const LiveMedalChip(medal: LiveMedal(name: '测试', level: 21, colorStart: 0xFF112233)));
    expect(find.text('测试'), findsOneWidget);
    expect(find.text('21'), findsOneWidget);
    expect(find.byKey(const ValueKey('live-medal-guard')), findsNothing);
    BoxDecoration decoration() =>
        tester
                .widget<Container>(
                  find.descendant(of: find.byKey(const ValueKey('live-medal')), matching: find.byType(Container)).first,
                )
                .decoration!
            as BoxDecoration;
    expect((decoration().gradient! as LinearGradient).colors.first, const Color(0xFF112233));

    await pump(tester, const LiveMedalChip(medal: LiveMedal(name: '测试', level: 21, guardLevel: 3)));
    expect(find.byKey(const ValueKey('live-medal-guard')), findsOneWidget);

    await pump(tester, const LiveMedalChip(medal: LiveMedal(name: '测试', level: 3, lit: false)));
    expect((decoration().gradient! as LinearGradient).colors.first, LiveRoomTheme.medalUnlit);
  });

  testWidgets('a face keeps its size; a guard draws its frame around it', (tester) async {
    await pump(tester, const LiveFace(url: '', size: 27));
    expect(tester.getSize(find.byType(LiveFace)), const Size.square(27));
    expect(find.byKey(const ValueKey('live-face-guard-1')), findsNothing);

    for (final level in [1, 2, 3]) {
      await pump(tester, LiveFace(url: '', size: 27, guardLevel: level));
      expect(tester.getSize(find.byType(LiveFace)), const Size.square(27));
      final frame = find.byKey(ValueKey('live-face-guard-$level'));
      expect(frame, findsOneWidget);
      expect(tester.getSize(frame).width, moreOrLessEquals(27 * LiveRoomTheme.guardFrameScale));
    }
  });
}
