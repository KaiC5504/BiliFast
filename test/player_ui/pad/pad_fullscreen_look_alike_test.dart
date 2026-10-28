import 'dart:io';
import 'dart:typed_data';

import 'package:bilifast/player/bili_player.dart' show PlayerStatus, StatusChanged;
import 'package:bilifast/player_ui/pad/pad_end_fullscreen.dart';
import 'package:bilifast/player_ui/pad/pad_fullscreen_chrome.dart';
import 'package:bilifast/player_ui/player_hud.dart';
import 'package:bilifast/player_ui/player_loading.dart';
import 'package:bilifast/player_ui/seek_bar.dart';
import 'package:bili_core/api.dart' show VideoCard;
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/look_alike.dart';
import '../../support/stand_in_fonts.dart';
import '../../video/mixed_lines.dart' show appTheme;
import 'pad_rig.dart';

/// The iPad's full screen under the system font at 2×, against ipad/08, 14, 15, 16 and 19. With BILIFAST_SHOTS naming a
/// folder outside the repo the shots are saved there for tools/screen_diff.py; with BILIFAST_PAD_REF naming KaiC's
/// `local/official-app-reference/ipad`, the official frame with the controls hidden (09, 19) stands in for the video,
/// so a shot differs from its screenshot only where the controls do. Without it a flat grey 16:9 box stands in.
void main() {
  final shots = Platform.environment['BILIFAST_SHOTS'];
  final reference = Platform.environment['BILIFAST_PAD_REF'];

  Future<Widget> background(WidgetTester tester, String name) async {
    final file = reference == null ? null : File('$reference/$name');
    if (file == null || !file.existsSync()) {
      return const Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Colors.black),
          Center(
            child: AspectRatio(aspectRatio: 16 / 9, child: ColoredBox(color: Color(0xFF8A7563))),
          ),
        ],
      );
    }
    final bytes = Uint8List.fromList(file.readAsBytesSync());
    final image = MemoryImage(bytes, scale: 2);
    return _Precached(image: image);
  }

  Future<void> systemFont(WidgetTester tester) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    await tester.runAsync(SeekBar.precache);
    BiliFonts.family = BiliFonts.system;
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('screen')), '$shots/$name.png', pixelRatio: 2);
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    final precached = find.byType(_Precached);
    if (precached.evaluate().isNotEmpty) {
      final state = tester.state<_PrecachedState>(precached);
      await tester.runAsync(() => state.load(tester.element(precached)));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('08 and 14: the bars where 08 has them', (tester) async {
    await systemFont(tester);
    final rig = rig08();
    await rig.mount(
      tester,
      PadFullScreenChrome(ui: rig.ui),
      background: await background(tester, '09-fullscreen-danmaku.png'),
      theme: appTheme(),
    );
    rig.session.readout.refresh();
    await settle(tester);
    await shoot(tester, 'pad-14');

    expect(tester.takeException(), isNull);
    expect(centreOf(tester, 'pad-back').dx, closeTo(28.3, 1));
    expect(centreOf(tester, 'pad-back').dy, closeTo(52.8, 1));
    expect(tester.getTopLeft(find.byKey(const ValueKey('pad-title'))).dx, closeTo(58.8, 0.5));
    expect(centreOf(tester, 'pad-like').dx, closeTo(739.8, 1));
    expect(centreOf(tester, 'pad-share').dx, closeTo(1090, 1));
    expect(centreOf(tester, 'pad-more'), within(distance: 1, from: const Offset(1160, 52.8)));
    expect(centreOf(tester, 'pad-capture'), within(distance: 1, from: const Offset(1160, 364.3)));
    expect(centreOf(tester, 'pad-lock'), within(distance: 1, from: const Offset(1160, 432.5)));
    expect(centreOf(tester, 'pad-bar').dy, closeTo(732, 1));
    expect(centreOf(tester, 'pad-play'), within(distance: 1, from: const Offset(92, 778)));
    expect(centreOf(tester, 'pad-prev').dx, closeTo(29.1, 1));
    expect(centreOf(tester, 'pad-danmaku').dx, closeTo(157.6, 1));
    expect(centreOf(tester, 'pad-danmaku-settings').dx, closeTo(221.6, 1));
    expect(tester.getTopLeft(find.byKey(const ValueKey('pad-danmaku-field'))).dx, closeTo(264, 1));
    expect(tester.getTopRight(find.byKey(const ValueKey('pad-danmaku-field'))).dx, closeTo(906.9, 2));
    expect(centreOf(tester, 'pad-pip').dx, closeTo(1096.5, 1));
    expect(centreOf(tester, 'pad-exit').dx, closeTo(1159.8, 1));
    expect(centreOf(tester, 'pad-uploader').dy, closeTo(114, 1));
  });

  testWidgets('upright, which no screenshot shows: the same bars at 834 wide', (tester) async {
    await systemFont(tester);
    final rig = rig08();
    await rig.mount(tester, PadFullScreenChrome(ui: rig.ui), landscape: false, theme: appTheme());
    await settle(tester);
    await shoot(tester, 'pad-upright');
    expect(tester.takeException(), isNull);
  });

  testWidgets('18 against 19: the controls over a buffering wait', (tester) async {
    await systemFont(tester);
    final rig = rig08();
    rig.session
      ..title = '中秋节有8个礼物领取点，不要忘记拿礼物哦。'
      ..chapters = const []
      ..duration.value = 115;
    rig.session.clock.jump(61);
    await rig.mount(
      tester,
      Stack(
        fit: StackFit.expand,
        children: [
          PadFullScreenChrome(ui: rig.ui),
          // Held still, so the shot can settle.
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: PlayerLoading(stats: rig.session.stats),
            ),
          ),
        ],
      ),
      background: await background(tester, '19-fullscreen-buffering.png'),
      theme: appTheme(),
    );
    rig.session.player.emit(const StatusChanged(PlayerStatus.buffering));
    rig.session.readout.refresh();
    await settle(tester);
    await shoot(tester, 'pad-18');
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('暂停'), findsOneWidget, reason: "18's ⏸: buffering still means to play");
  });

  testWidgets('15: the hold pill at the top centre over the hidden controls', (tester) async {
    await systemFont(tester);
    final rig = rig08();
    rig.chrome.hide();
    rig.chrome.showHud(const SpeedUpHud());
    await rig.mount(
      tester,
      Stack(
        fit: StackFit.expand,
        children: [
          PadFullScreenChrome(ui: rig.ui),
          PlayerHud(ui: rig.ui),
        ],
      ),
      background: await background(tester, '09-fullscreen-danmaku.png'),
      theme: appTheme(),
    );
    await settle(tester);
    await shoot(tester, 'pad-15');
    final pill = tester.getRect(find.byKey(const ValueKey('hud-speed-pill')));
    expect(pill.center.dx, closeTo(597, 1));
    expect(find.byKey(const ValueKey('pad-strip')), findsOneWidget);
  });

  testWidgets('16: the end screen', (tester) async {
    await systemFont(tester);
    final rig = rig08();
    rig.session
      ..ended = true
      ..shareLink = Uri.parse('https://b23.tv/BV1')
      ..related = [
        for (final (title, views, danmaku, duration) in [
          ('小猫们跳房子大会-东边果园篇【AI全城创作者】', 1703000, 679, 255),
          ('从头到尾 细说小猫们', 54000, 187, 206),
          ('小猫们跳房子大会-旧城车站篇【AI全城创作者】', 5585000, 1667, 270),
          ('小妹帮爸爸做午饭', 248000, 184, 64),
          ('石头', 119000, 67, 61),
          ('小猫杯寻宝者模式-海岛【AI全城创作者】', 373000, 346, 271),
          ('雪花鸟【AI全城创作者】', 733000, 381, 147),
          ('小鸭日记本【AI全城创作者】', 54000, 61, 90),
          ('猫', 1000, 1, 60),
          ('猫', 1000, 1, 60),
          ('猫', 1000, 1, 60),
          ('猫', 1000, 1, 60),
        ])
          VideoCard(
            aid: views,
            bvid: 'BV$views',
            cid: 1,
            title: title,
            cover: '',
            duration: duration,
            ownerMid: 1,
            ownerName: '山顶小松鼠',
            views: views,
            danmaku: danmaku,
            likes: 0,
          ),
      ];
    await rig.mount(
      tester,
      PadEndFullScreen(ui: rig.ui, share: (_) async => true),
      background: await background(tester, '09-fullscreen-danmaku.png'),
      theme: appTheme(),
    );
    await settle(tester);
    await shoot(tester, 'pad-16');
    expect(tester.takeException(), isNull);
    expect(centreOf(tester, 'pad-end-back').dy, closeTo(42, 1));
    expect(centreOf(tester, 'pad-end-share').dx, closeTo(1121, 1));
    expect(centreOf(tester, 'pad-end-replay').dx, closeTo(726, 1));
  });
}

/// The official frame behind the controls, decoded outside the fake clock so it is in for the shot.
class _Precached extends StatefulWidget {
  const _Precached({required this.image});

  final ImageProvider image;

  @override
  State<_Precached> createState() => _PrecachedState();
}

class _PrecachedState extends State<_Precached> {
  Future<void> load(BuildContext context) => precacheImage(widget.image, context);

  @override
  Widget build(BuildContext context) => Image(image: widget.image, fit: BoxFit.fill);
}
