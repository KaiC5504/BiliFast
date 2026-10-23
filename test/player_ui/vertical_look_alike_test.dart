import 'dart:io';

import 'package:bili_core/api.dart' show UploaderCard, VideoDetail;
import 'package:bili_core/danmaku.dart';
import 'package:bilifast/danmaku/danmaku_layer.dart';
import 'package:bilifast/danmaku/danmaku_settings_store.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/player/bili_player.dart' show PlayerStatus, StatusChanged;
import 'package:bilifast/player/playback_clock.dart';
import 'package:bilifast/player_ui/seek_bar.dart';
import 'package:bilifast/player_ui/vertical_chrome.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/player_session.dart' show Episode;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_video_actions.dart';
import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import '../video/mixed_lines.dart' show appTheme;
import 'vertical_chrome_test.dart' show Rig;

/// 竖屏 paused as KaiC's iPhone draws it, against 118 (00:05 / 01:02, 合集 · 第18集), at 3×. With BILIFAST_SHOTS naming a
/// folder outside the repo, the shot is saved there for tools/screen_diff.py.
void main() {
  // 118's video: 16:9 across the width, centred at the 竖屏 line.
  const videoTop = 956 * BiliMetrics.verticalVideoCentre - 440 / BiliMetrics.videoAspect / 2;
  const videoBottom = 956 * BiliMetrics.verticalVideoCentre + 440 / BiliMetrics.videoAspect / 2;
  // Under the top row, as VideoPlayerArea lays 竖屏's danmaku out.
  const danmakuTop = 62 - BiliMetrics.verticalTopLift + BiliMetrics.chromeButton + BiliMetrics.verticalDanmakuDrop;

  Rig rig118() => Rig()
    ..session.title = '“没错，你触发保底了”'
    ..session.duration.value = 62
    ..session.detail = VideoDetail.fromJson({
      'bvid': 'BV18',
      'title': '“没错，你触发保底了”',
      'owner': {'mid': 1, 'name': '小小小小小小小流萤', 'face': ''},
      'stat': {'view': 34000, 'reply': 108, 'like': 5064, 'coin': 813, 'favorite': 1946, 'share': 122},
      'ugc_season': {'id': 1, 'title': '合集', 'sections': <Object>[]},
    })
    ..session.episodesAreParts = false
    ..session.episodes = [
      for (var i = 1; i <= 20; i++) Episode(bvid: 'BV$i', cid: i, title: '第$i集', current: i == 18),
    ]
    ..details = FakePageDetails(
      actions: FakeVideoActions(likeCount: 5064, coinCount: 813, favCount: 1946, shareCount: 122),
      uploader: const UploaderCard(
        mid: 1,
        name: '小小小小小小小流萤',
        face: '',
        fans: 30000,
        videos: 10,
        isVip: false,
        following: false,
      ),
      online: '1',
    );

  DisplayDanmaku danmaku(String text, int ms, int color) => DisplayDanmaku(
    elem: DanmakuElem(progressMs: ms, content: text, color: color),
    text: text,
    isOwn: false,
  );

  testWidgets('118: the ▶, the time, the TV on the bar, the 合集 line and the danmaku where 118 has them', (tester) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    await tester.runAsync(SeekBar.precache);
    showAsPhone(tester);
    BiliFonts.family = BiliFonts.system;

    final rig = rig118();
    addTearDown(() {
      rig.chrome.dispose();
      rig.panels.dispose();
      rig.orientation.dispose();
      rig.session.dispose();
      rig.details?.dispose();
    });
    final clock = PlaybackClock()..jump(10);
    final store = DanmakuSettingsStore.memory();
    // Placed so they fly where 118 caught them: 今夕是何年 at 47 pt, the other three at 191 pt.
    final timeline = DanmakuTimeline()
      ..add([
        danmaku('今夕是何年', 4680, 0xFFFFFF),
        danmaku('快带上耳机', 6630, 0xE33C3C),
        danmaku('快带上耳机', 6630, 0xE33C3C),
        danmaku('首页通知书', 6630, 0xD9A7C7),
      ]);
    rig.session.clock.jump(5.4);
    rig.session.readout.refresh();
    rig.session.player.emit(const StatusChanged(PlayerStatus.paused));

    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => RepaintBoundary(key: const ValueKey('screen'), child: child!),
        home: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: BiliColors.videoBackground),
            // A flat stand-in for the picture, so the ▶'s quarter white shows as on 118's board.
            const Positioned(
              left: 0,
              right: 0,
              top: videoTop,
              height: videoBottom - videoTop,
              child: ColoredBox(color: Color(0xFF707E95)),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: danmakuTop,
              bottom: 956 - videoBottom,
              child: DanmakuLayer(
                clock: clock,
                timeline: timeline,
                settings: store,
                presentation: Presentation.vertical,
              ),
            ),
            VerticalChrome(ui: rig.ui),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(VerticalChrome));
    await tester.runAsync(() => precacheImage(const AssetImage(VerticalActionTheme.pausedPlayAsset), context));
    await tester.pumpAndSettle();

    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('screen')), '$shots/vertical-118.png');

    // 118: the ▶'s body spans 557.5-761.5 px, its file's top at 1192 px (397.3 pt).
    final glyph = tester.getRect(
      find.descendant(of: find.byKey(const ValueKey('vertical-paused-play')), matching: find.byType(Image)),
    );
    expect(glyph.left * 3 + 18, closeTo(557.5, 1.5));
    expect(glyph.top * 3, closeTo(1192, 2));

    // 118: the time's digits from 506 to 811 px, their tops at 1469 px and bottoms at 1501.
    final time = tester.getRect(find.byKey(const ValueKey('vertical-paused-time')));
    expect(time.center.dx, closeTo(220, 0.5));

    // 118's lanes: identical lines 69 px apart, the first's ink top at 311 px.
    final layer = tester.state<DanmakuLayerState>(find.byType(DanmakuLayer));
    final lanes = [for (final shown in layer.scene.visible) shown.rect.center.dy + danmakuTop]..sort();
    expect(lanes.toSet(), hasLength(3));
    expect(lanes.last - lanes.first, closeTo(2 * BiliMetrics.danmakuLaneVertical, 0.01));
    expect(lanes.first * 3, closeTo(331.5, 3), reason: '118: the first lane centred about 331.5 px down');
  });
}
