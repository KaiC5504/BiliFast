import 'dart:io';

import 'package:bilifast/shared/action_glyphs.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/intro/action_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_video_actions.dart';
import '../../support/look_alike.dart';
import '../../support/stand_in_fonts.dart';
import '../mixed_lines.dart' show appTheme;

/// The action row with 不喜欢 on (88) and off (89), under the system font as KaiC's iPhone draws it, with 88's counts.
/// The row sits where 88's does: 点赞's ink starts 544.67 pt down, 2 pt into its 24 pt box. With BILIFAST_SHOTS naming
/// a folder outside the repo, the 3× shots are saved there for tools/screen_diff.py.
const _rowTop = 544.67 - 2 - ActionTheme.topGap;

void main() {
  Future<void> render(WidgetTester tester, {required bool disliked}) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester);
    BiliFonts.family = BiliFonts.system;
    final actions = FakeVideoActions(
      disliked: disliked,
      likeCount: 2771,
      coinCount: 703,
      favCount: 659,
      shareCount: 108,
    );
    addTearDown(actions.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => RepaintBoundary(
          key: const ValueKey('screen'),
          child: MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
        ),
        home: Material(
          color: BiliColors.card,
          child: Stack(
            children: [
              Positioned(left: 0, right: 0, top: _rowTop, child: ActionRow(actions: actions)),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) {
      await saveShot(tester, find.byKey(const ValueKey('screen')), '$shots/dislike-${disliked ? 'on' : 'off'}.png');
    }
  }

  Color thumb(WidgetTester tester) => tester
      .widget<ActionIcon>(find.byWidgetPredicate((widget) => widget is ActionIcon && widget.glyph == ActionGlyph.dislike))
      .color;

  Color? name(WidgetTester tester) => tester.widget<Text>(find.text('不喜欢')).style?.color;

  testWidgets('88: 不喜欢 on, its thumb pink and its name still grey', (tester) async {
    await render(tester, disliked: true);
    expect(thumb(tester), BiliColors.pink);
    expect(name(tester), ActionTheme.count);
    expect(find.text('2771'), findsOneWidget);
  });

  testWidgets('89: 不喜欢 off, grey as the other actions', (tester) async {
    await render(tester, disliked: false);
    expect(thumb(tester), ActionTheme.icon);
    expect(name(tester), ActionTheme.count);
  });
}
