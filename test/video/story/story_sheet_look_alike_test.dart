import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bilifast/comments/comments_tab.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/page_details.dart' show PageTab;
import 'package:bilifast/video/story/story_sheet.dart';
import 'package:bilifast/video/story/story_sheet_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../comments/comments_tab_test.dart' show FakeComments, Replies;
import '../../support/look_alike.dart';
import '../../support/stand_in_fonts.dart';
import '../mixed_lines.dart' show appTheme;

/// The 竖屏 sheet as KaiC's iPhone draws it, at half on 评论 (264) and full (266), over black with stand-in comments,
/// at 3×. With BILIFAST_SHOTS naming a folder outside the repo, the shots are saved there for tools/screen_diff.py.
void main() {
  final day = DateTime(2026, 11, 3, 12).millisecondsSinceEpoch ~/ 1000;
  List<Comment> comments() => [
    Comment(
      rpid: 1,
      ctime: day,
      likes: 35,
      replyCount: 6,
      location: '四川',
      member: const CommentMember(mid: 1, name: '爱喝奶茶的冰凌', level: 6),
      message: '瓦区这么夸张 lol这些主播还是太老实了 大多数真的退了',
    ),
    Comment(
      rpid: 2,
      ctime: day - 2 * 86400,
      likes: 249,
      location: '山东',
      member: const CommentMember(mid: 2, name: '示桓', level: 6),
      message: '谁懂啊，这种冤家的甜甜甜',
    ),
  ];

  Future<StorySheetController> shoot(WidgetTester tester, SheetStop stop, String name) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester);
    BiliFonts.family = BiliFonts.system;

    final controller = StorySheetController(vsync: tester);
    addTearDown(controller.dispose);
    final model = FakeComments(comments: comments(), isEndValue: true)..rootPromptValue = '勇敢滴少年啊快去创造热评~';
    addTearDown(model.dispose);
    final replies = ValueNotifier<int?>(98);
    addTearDown(replies.dispose);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appTheme(),
        builder: (context, child) => RepaintBoundary(key: const ValueKey('screen'), child: child!),
        home: Material(
          color: BiliColors.videoBackground,
          child: StorySheetView(
            controller: controller,
            intro: const SizedBox.expand(),
            comments: CommentsTab(model: model, callbacks: Replies().callbacks),
            replies: replies,
          ),
        ),
      ),
    );
    controller.open(PageTab.comments);
    if (stop == SheetStop.full) controller.toggle();
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(StorySheetView));
    await tester.runAsync(() async {
      await precacheImage(const AssetImage(StorySheetTheme.expandAsset), context);
      await precacheImage(const AssetImage(StorySheetTheme.collapseAsset), context);
    });
    await tester.pumpAndSettle();
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('screen')), '$shots/$name.png');
    return controller;
  }

  testWidgets('264: half on 评论, its header and the list under it', (tester) async {
    await shoot(tester, SheetStop.half, 'sheet-264');
    final sheet = tester.getRect(find.byKey(const ValueKey('story-sheet')));
    expect(sheet.top, StorySheetTheme.halfTop);
    expect(sheet.bottom, 956);
    // 264's underline: 319-366 px across, 1094-1105 down.
    final underline = tester.getRect(find.byKey(const ValueKey('story-sheet-underline')));
    expect(underline.top, moreOrLessEquals(1094 / 3, epsilon: 0.34));
    expect(underline.size, const Size(16, 4));
    // The disc: 1212-1283 px across, 1016-1087 down.
    final disc = tester.getCenter(find.byKey(const ValueKey('story-sheet-button')));
    expect(disc.dx, moreOrLessEquals(1248 / 3, epsilon: 0.34));
    expect(disc.dy, moreOrLessEquals(1052 / 3, epsilon: 0.34));
    // The write bar at the screen's bottom.
    expect(tester.getRect(find.byKey(const ValueKey('comment-bar'))).bottom, moreOrLessEquals(956));
  });

  testWidgets('266: full, chevrons in', (tester) async {
    await shoot(tester, SheetStop.full, 'sheet-266');
    final sheet = tester.getRect(find.byKey(const ValueKey('story-sheet')));
    expect(sheet.top, StorySheetTheme.fullTop);
    expect(sheet.bottom, 956);
    final icon = tester.widget<Image>(
      find.descendant(of: find.byKey(const ValueKey('story-sheet-button')), matching: find.byType(Image)),
    );
    expect((icon.image as AssetImage).assetName, StorySheetTheme.collapseAsset);
  });
}
