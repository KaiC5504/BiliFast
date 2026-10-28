import 'dart:io';

import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/intro/intro_tab.dart';
import 'package:bilifast/video/intro/related_list.dart';
import 'package:bilifast/video/pad/pad_body.dart';
import 'package:bilifast/video/player_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_video_actions.dart';
import '../../support/look_alike.dart';
import '../../support/stand_in_fonts.dart';
import '../mixed_lines.dart' show appTheme;
import 'pad_body_fixtures.dart';

/// 简介's head and the related column as ipad/03, 04 and 06 place them, under the system font. Sideways the head is
/// the left column's 756.5 pt under the player (which ends 457.5 down) and the related column the right 437 pt; the
/// column is shown from 136 down so its first row lands on 03's first row after the ad. Upright the head starts 561
/// down (06's avatar 10 below that). With BILIFAST_SHOTS naming a folder outside the repo, the 2× shots are saved
/// there for tools/screen_diff.py.
const _playerBottom = 457.5;
const _leftColumn = 756.5;
const _rightColumn = 1194 - 757.0;
const _columnTop = 136.0;
const _uprightTop = 561.0;

void main() {
  Future<FakeVideoActions> render(WidgetTester tester, {required bool landscape, required String shot}) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    showAsPad(tester, landscape: landscape);
    BiliFonts.family = BiliFonts.system;
    final actions = padActions();
    final details = FakePageDetails(actions: actions, uploader: padUploader, tags: padTags, online: '4000+');
    addTearDown(actions.dispose);
    addTearDown(details.dispose);
    final content = IntroContent(
      detail: padDetail(pubdate: DateTime(2026, 10, 27, 15, 40).millisecondsSinceEpoch ~/ 1000),
      related: padRelated,
    );
    final head = PadIntroHead(
      content: content,
      details: details,
      onSeek: (_) {},
      onOpenVideo: (_) {},
      onPlayEpisode: (Episode _) {},
      onOpenEpisodes: () {},
    );
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
            children: landscape
                ? [
                    Positioned(left: 0, width: _leftColumn, top: _playerBottom, child: head),
                    Positioned(
                      left: 757,
                      width: _rightColumn,
                      top: _columnTop,
                      bottom: 0,
                      child: PadRelatedColumn(cards: padRelated, onOpen: (_) {}, onWatchLater: (_) {}),
                    ),
                  ]
                : [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: _uprightTop,
                      bottom: 0,
                      child: CustomScrollView(
                        slivers: [
                          SliverToBoxAdapter(child: head),
                          RelatedSliver(cards: padRelated, onOpen: (_) {}, onWatchLater: (_) {}),
                        ],
                      ),
                    ),
                  ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) {
      await saveShot(tester, find.byKey(const ValueKey('screen')), '$shots/$shot.png', pixelRatio: 2);
    }
    return actions;
  }

  testWidgets('03: sideways, collapsed, the head under the player and the related column', (tester) async {
    await render(tester, landscape: true, shot: 'pad-03');
    expect(tester.getTopLeft(find.byKey(const ValueKey('uploader-open'))), const Offset(20, _playerBottom + 10));
    expect(find.text('点我发弹幕'), findsOneWidget);
    expect(find.text('查看简介'), findsOneWidget);
    expect(find.text('qwnrt?'), findsNothing);
  });

  testWidgets('04: sideways, 查看简介 opened', (tester) async {
    await render(tester, landscape: true, shot: 'pad-03-closed');
    await tester.tap(find.byKey(const ValueKey('pad-intro-toggle')));
    await tester.pumpAndSettle();
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('screen')), '$shots/pad-04.png', pixelRatio: 2);
    expect(find.text('qwnrt?'), findsOneWidget);
    expect(find.text('AI游戏全世界'), findsOneWidget);
  });

  testWidgets('06: upright, opened, the related rows at the full width', (tester) async {
    await render(tester, landscape: false, shot: 'pad-06-closed');
    expect(find.text('点我发弹幕'), findsNothing, reason: "upright the field is the tab row's");
    await tester.tap(find.byKey(const ValueKey('pad-intro-toggle')));
    await tester.pumpAndSettle();
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('screen')), '$shots/pad-06.png', pixelRatio: 2);
  });
}
