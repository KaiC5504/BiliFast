import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/live/player/live_player_panels.dart';
import 'package:bilifast/live/player/live_player_view.dart';
import 'package:bilifast/live/room/live_overlays.dart';
import 'package:bilifast/live/room/live_room_model.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/look_alike.dart';
import '../../support/stand_in_fonts.dart';
import 'live_player_fakes.dart';

/// 207, 209, 210 and 222 as KaiC's iPhone draws them, under the system font. With BILIFAST_SHOTS naming a folder
/// outside the repo, the 3× shots are saved there for tools/screen_diff.py.
const _assets = [
  LivePlayerAssets.pause,
  LivePlayerAssets.play,
  LivePlayerAssets.refresh,
  LivePlayerAssets.danmakuOn,
  LivePlayerAssets.danmakuOff,
  LivePlayerAssets.watchMovies,
  LivePlayerAssets.fullScreen,
  LivePlayerAssets.share,
  LivePlayerAssets.gift,
  LivePlayerAssets.moreShare,
  LivePlayerAssets.morePip,
  LivePlayerAssets.moreSettings,
  LivePlayerAssets.moreDanmaku,
  LivePlayerAssets.moreEffects,
  LivePlayerAssets.moreCast,
  LivePlayerAssets.moreReport,
  LivePlayerAssets.moreFeedback,
  LivePlayerAssets.moreAudio,
  LivePlayerAssets.moreColour,
  LivePlayerAssets.moreDesktop,
];

void main() {
  final shots = Platform.environment['BILIFAST_SHOTS'];

  Future<void> shoot(WidgetTester tester, {required bool landscape, LiveOverlay overlay = LiveOverlay.none}) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    BiliFonts.family = BiliFonts.system;
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester, landscape: landscape);
    final rig = await liveRig();
    rig.room.infoValue = const LiveRoomInfo(
      roomId: 7734200,
      uid: 50329118,
      title: '全国大赛 AQ vs LGD',
      anchorName: '夜莲 Annbbers',
      rankChips: ['热门榜', '网游人气第 28'],
    );
    await rig.controller.start();
    rig.room.go(LiveRoomState.live, play: playAt(10000));
    rig.player.emit(const StatusChanged(PlayerStatus.playing));
    final overlays = LiveOverlays()..value = overlay;
    addTearDown(overlays.dispose);
    final boundary = GlobalKey();
    final view = LivePlayerView(
      controller: rig.controller,
      room: rig.room,
      overlays: overlays,
      fullScreen: landscape,
      onBack: () {},
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppScope(services: rig.services, child: child!),
        home: RepaintBoundary(
          key: boundary,
          child: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: Color(0xFF3C3C46))),
              if (landscape)
                Positioned.fill(child: view)
              else
                Positioned(
                  left: 0,
                  right: 0,
                  top: liveBoxTop,
                  height: liveBoxBottom - liveBoxTop,
                  child: view,
                ),
              if (overlay == LiveOverlay.more)
                Positioned.fill(
                  child: LiveMorePanel(controller: rig.controller, room: rig.room, overlays: overlays),
                ),
              if (overlay == LiveOverlay.quality)
                Positioned.fill(
                  child: LiveQualityPicker(
                    controller: rig.controller,
                    room: rig.room,
                    overlays: overlays,
                    landscape: landscape,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    final context = tester.element(find.byType(LivePlayerView));
    await tester.runAsync(() async {
      for (final asset in _assets) {
        await precacheImage(AssetImage(asset), context);
      }
    });
    await tester.pump();
    if (!landscape) {
      rig.controller.setDanmakuOn(false);
      await tester.pump();
    }
    if (shots != null) {
      final name = landscape ? 'live-209${overlay == LiveOverlay.none ? '' : '-${overlay.name}'}' : 'live-207';
      await saveShot(tester, find.byKey(boundary), '$shots/$name.png');
    }
    rig.controller.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
  }

  testWidgets('207: the box with 弹 and the full-screen button, 208\'s note', (tester) async {
    await shoot(tester, landscape: false);
  });

  testWidgets('209: full screen\'s controls', (tester) async {
    await shoot(tester, landscape: true);
  });

  testWidgets('222: ⋮\'s panel', (tester) async {
    await shoot(tester, landscape: true, overlay: LiveOverlay.more);
  });

  testWidgets('210: 画质\'s panel', (tester) async {
    await shoot(tester, landscape: true, overlay: LiveOverlay.quality);
  });
}
