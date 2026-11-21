import 'dart:io';

import 'package:bili_core/api.dart' show UploaderCard, VideoDetail;
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/player/bili_player.dart' show PlayerStatus, StatusChanged;
import 'package:bilifast/player_ui/seek_bar.dart';
import 'package:bilifast/player_ui/vertical_chrome.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/story/story_drag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_video_actions.dart';
import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import '../video/mixed_lines.dart' show appTheme;
import 'vertical_chrome_test.dart' show RelatedFeed, Rig;
import 'vertical_clean_test.dart' show entry;

/// A 竖屏 page opened from the sheet's 相关视频, as 270 has it at 2.0 s (相关视频 (1/20), a 4:3 video), at 3× under the
/// system font. With BILIFAST_SHOTS naming a folder outside the repo, the shot is saved there for tools/screen_diff.py.
void main() {
  testWidgets('270 at 2.0 s: ‹, 相关视频 (1/20) centred in a dark capsule, ⋮', (tester) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    await tester.runAsync(SeekBar.precache);
    showAsPhone(tester);
    BiliFonts.family = BiliFonts.system;

    final rig = Rig()
      ..session.title = '是小羊崽赢了，还是伊森输了'
      ..session.duration.value = 41
      ..session.videoShape = (width: 1440, height: 1080)
      ..session.detail = VideoDetail.fromJson({
        'bvid': 'BV1',
        'title': '是小羊崽赢了，还是伊森输了',
        'owner': {'mid': 1, 'name': '小阿飞的日常', 'face': ''},
        'stat': {'view': 151000, 'reply': 46, 'like': 678, 'coin': 6, 'favorite': 59, 'share': 11},
      })
      ..details = FakePageDetails(
        actions: FakeVideoActions(likeCount: 678, coinCount: 6, favCount: 59, shareCount: 11),
        uploader: const UploaderCard(
          mid: 1,
          name: '小阿飞的日常',
          face: '',
          fans: 3690,
          videos: 10,
          isVip: false,
          following: false,
        ),
        online: '12',
      )
      ..clean = ValueNotifier(false)
      ..storyDrag = StoryDrag()
      ..story = ValueNotifier(RelatedFeed([entry('BV1'), entry('BV2')]));
    addTearDown(() {
      rig.chrome.dispose();
      rig.panels.dispose();
      rig.orientation.dispose();
      rig.session.dispose();
      rig.details?.dispose();
      rig.clean?.dispose();
      rig.storyDrag?.dispose();
      rig.story?.value?.dispose();
      rig.story?.dispose();
    });
    rig.session.clock.jump(0.4);
    rig.session.readout.refresh();
    rig.session.player.emit(const StatusChanged(PlayerStatus.playing));

    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => RepaintBoundary(key: const ValueKey('screen'), child: child!),
        home: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: BiliColors.videoBackground),
            // 270's 4:3 picture spans 698-1687 px.
            const Positioned(
              left: 0,
              right: 0,
              top: 698 / 3,
              height: 990 / 3,
              child: ColoredBox(color: Color(0xFF6B6658)),
            ),
            VerticalChrome(ui: rig.ui),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(rig.orientation.presentation, Presentation.vertical);

    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('screen')), '$shots/vertical-270.png');

    // 270 at 2.0 s: the capsule 467-853 × 180-276 px, its text's ink 516-799 × 209-247 px. The stand-in's space is
    // wider than SF's, so ours runs about 4 px longer.
    final capsule = tester.getRect(find.byKey(const ValueKey('vertical-counter')));
    expect(capsule.left * 3, closeTo(467, 4));
    expect(capsule.right * 3, closeTo(854, 4));
    expect(capsule.top * 3, closeTo(180, 1));
    expect(capsule.bottom * 3, closeTo(276, 1));
    final text = tester.getRect(find.text('相关视频 (1/20)'));
    // The hairline insets it a third more.
    expect(text.left - capsule.left, closeTo(StoryCounterTheme.padding + StoryCounterTheme.edgeWidth, 0.01));
    // Its ink sits 1 pt under its line box's centre, so the box is 1 pt under the capsule's.
    expect(text.center.dy - capsule.center.dy, closeTo(StoryCounterTheme.textDrop, 0.01));
  });
}
