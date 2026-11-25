import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/player_notes_view.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'landscape_chrome_test.dart' show Rig;

Finder note(String text) => find.ancestor(of: find.text(text), matching: find.byType(DecoratedBox)).first;

/// Whether [finder] draws: no fade above it is out.
bool drawn(WidgetTester tester, Finder finder) =>
    tester
        .widgetList<Opacity>(find.ancestor(of: finder, matching: find.byType(Opacity)))
        .every((fade) => fade.opacity > 0) &&
    tester
        .widgetList<AnimatedOpacity>(find.ancestor(of: finder, matching: find.byType(AnimatedOpacity)))
        .every((fade) => fade.opacity > 0);

void main() {
  testWidgets("274's notes stack at the bottom left, the newest lowest, 8 apart, flush with the safe area", (
    tester,
  ) async {
    final rig = Rig();
    await rig.mount(tester);
    expect(find.byType(PlayerNotesView), findsOne);

    rig.session.notes
      ..add('Hi-Res无损音质开启中，请稍候')
      ..add('Hi-Res无损音质已开启');
    await tester.pump();
    final older = tester.getRect(note('Hi-Res无损音质开启中，请稍候'));
    final newer = tester.getRect(note('Hi-Res无损音质已开启'));
    expect(newer.top - older.bottom, closeTo(PlayerNotesTheme.gap, 0.01));
    expect(newer.bottom, closeTo(440 - PlayerNotesTheme.bottom, 0.01));
    expect(older.left, 62);
    expect(newer.left, 62);
    expect(older.height, closeTo(PlayerNotesTheme.height, 0.01));
    // Each fits its words, 12 pt in either side.
    final words = tester.getRect(find.text('Hi-Res无损音质已开启'));
    expect(words.left - newer.left, closeTo(PlayerNotesTheme.inset, 0.01));
    expect(newer.right - words.right, closeTo(PlayerNotesTheme.inset, 0.01));
    final box = tester.widget<DecoratedBox>(note('Hi-Res无损音质已开启')).decoration as BoxDecoration;
    expect(box.color, PlayerNotesTheme.fill);
    expect(box.borderRadius, BorderRadius.circular(PlayerNotesTheme.radius));
    // Above the time line's box, which starts at 316.
    expect(newer.bottom, lessThan(316));

    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('they show with the controls up, hidden, or under a panel, and take no touches', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    rig.session.notes.add('Hi-Res无损音质已开启');
    await tester.pump();
    final text = find.text('Hi-Res无损音质已开启');
    expect(drawn(tester, text), isTrue);
    expect(
      tester.widgetList<IgnorePointer>(find.ancestor(of: text, matching: find.byType(IgnorePointer))).first.ignoring,
      isTrue,
    );

    rig.chrome.hide();
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(text, findsOne);
    expect(drawn(tester, text), isTrue);

    rig.panels.open(PlayerPanel.quality);
    await tester.pump(const Duration(milliseconds: 300));
    expect(text, findsOne);
    expect(drawn(tester, text), isTrue);

    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('each goes after its time, and a third pushes the oldest out', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    rig.session.notes
      ..add('一')
      ..add('二')
      ..add('三');
    await tester.pump();
    expect(find.text('一'), findsNothing);
    expect(find.text('二'), findsOne);
    expect(find.text('三'), findsOne);
    expect(tester.getRect(note('二')).top, lessThan(tester.getRect(note('三')).top));

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('二'), findsNothing);
    expect(find.text('三'), findsNothing);
  });
}
