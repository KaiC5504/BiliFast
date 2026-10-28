import 'dart:io';

import 'package:bili_core/api.dart' show Chapter, VideoCard;
import 'package:bilifast/player/bili_player.dart' show PlayerStatus, StatusChanged;
import 'package:bilifast/player_ui/pad/pad_end_inline.dart';
import 'package:bilifast/player_ui/pad/pad_inline_controls.dart';
import 'package:bilifast/player_ui/seek_bar.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import '../video/mixed_lines.dart' show appTheme;
import 'pad_end_inline_test.dart' show EndRig;
import 'pad_inline_controls_test.dart' show PadRig;

/// The iPad page's player controls (03 sideways, 07 upright) and end screen (17) at the page's player size under the
/// system font's stand-ins. With BILIFAST_SHOTS naming a folder outside the repo, each screen is saved there at 2× for
/// tools/screen_diff.py; BILIFAST_PAD_BACKDROP may name a picture (06's bare frame, cut to the player) drawn under the
/// controls, so the shot can be laid over the official one.
const _chapters = [
  Chapter(from: 0, to: 20, title: '开场'),
  Chapter(from: 20, to: 92.5, title: '寻找好位置'),
  Chapter(from: 92.5, to: 205, title: '队长出发'),
  Chapter(from: 205, to: 224, title: '游戏结束'),
  Chapter(from: 224, to: 254, title: 'qwnrt'),
];

const _next = VideoCard(
  aid: 1,
  bvid: 'BV1next',
  cid: 2,
  title: '小猫们跳房子大会-东边果园篇【AI全城创作者】',
  cover: '',
  duration: 255,
  ownerMid: 3,
  ownerName: '木子_',
  views: 1703000,
  danmaku: 679,
  likes: 0,
);

void main() {
  Future<Widget> backdrop(WidgetTester tester) async {
    final path = Platform.environment['BILIFAST_PAD_BACKDROP'];
    if (path == null) return const ColoredBox(color: Color(0xFF6B625B));
    final bytes = await tester.runAsync(() => File(path).readAsBytes());
    return Image.memory(bytes!, fit: BoxFit.fill, gaplessPlayback: true);
  }

  Future<void> render(WidgetTester tester, {required bool landscape, required Widget child, required String name}) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    await tester.runAsync(SeekBar.precache);
    showAsPad(tester, landscape: landscape);
    BiliFonts.family = BiliFonts.system;
    final width = landscape ? 756.5 : 834.0;
    final under = await backdrop(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => RepaintBoundary(key: const ValueKey('screen'), child: child!),
        home: Material(
          color: BiliColors.videoBackground,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 32,
                width: width,
                height: width * 9 / 16,
                child: Stack(fit: StackFit.expand, children: [under, child]),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('screen')), '$shots/$name.png', pixelRatio: 2);
  }

  for (final (name, landscape) in [('pad-03-controls', true), ('pad-07-controls', false)]) {
    testWidgets('$name: the rows at 0:00 of 4:14 with chapters, paused', (tester) async {
      final rig = PadRig()
        ..session.duration.value = 254
        ..session.chapters = _chapters;
      addTearDown(() {
        rig.chrome.dispose();
        rig.panels.dispose();
        rig.orientation.dispose();
        rig.session.dispose();
      });
      rig.session.player.emit(const StatusChanged(PlayerStatus.paused));
      await render(tester, landscape: landscape, name: name, child: PadInlineControls(ui: rig.ui));
      expect(find.text('章节 · 开场'), findsOneWidget);
      expect(find.text('00:00/04:14'), findsOneWidget);
    });
  }

  testWidgets('pad-06-hidden: the chapters along the bottom', (tester) async {
    final rig = PadRig()
      ..session.duration.value = 254
      ..session.chapters = _chapters;
    addTearDown(() {
      rig.chrome.dispose();
      rig.panels.dispose();
      rig.orientation.dispose();
      rig.session.dispose();
    });
    rig.chrome.hide();
    await render(tester, landscape: false, name: 'pad-06-hidden', child: PadInlineControls(ui: rig.ui));
    expect(find.text('寻找好位置'), findsOneWidget);
  });

  testWidgets('pad-17-end: 推荐视频, 重播 and 分享', (tester) async {
    final rig = EndRig()
      ..session.related = const [_next]
      ..session.duration.value = 254
      ..session.chapters = _chapters;
    addTearDown(() {
      rig.chrome.dispose();
      rig.panels.dispose();
      rig.orientation.dispose();
      rig.session.dispose();
    });
    await render(tester, landscape: true, name: 'pad-17-end', child: PadEndInline(ui: rig.ui, share: rig.share));
    expect(find.text('推荐视频'), findsOneWidget);
  });
}
