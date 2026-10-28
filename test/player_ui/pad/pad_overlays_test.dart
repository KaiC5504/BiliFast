import 'package:bili_core/api.dart' show Chapter, VideoShot;
import 'package:bilifast/player/bili_player.dart' show PlayerStatus, StatusChanged;
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/player_gestures.dart';
import 'package:bilifast/player_ui/player_hud.dart';
import 'package:bilifast/player_ui/player_loading.dart';
import 'package:bilifast/player_ui/seek_preview.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_player_session.dart';
import '../../support/look_alike.dart';
import '../player_gestures_test.dart' as gestures;
import '../seek_preview_test.dart' show testSheets;

/// The 2× hold, buffering, the seek preview and the gestures over the iPad's full screen (1194 × 834).
void main() {
  Size arrowsOf(WidgetTester tester) =>
      tester.getSize(find.descendant(of: find.byType(SpeedArrows), matching: find.byType(CustomPaint)).first);

  Future<gestures.Rig> mountHud(WidgetTester tester, {required bool pad}) async {
    final rig = gestures.Rig();
    addTearDown(() {
      rig.chrome.dispose();
      rig.panels.dispose();
      rig.orientation.dispose();
      rig.session.dispose();
    });
    if (pad) {
      showAsPad(tester, landscape: true);
    } else {
      showAsPhone(tester, landscape: true);
    }
    await rig.mountFullScreen(tester);
    rig.chrome.showHud(const SpeedUpHud());
    await tester.pumpAndSettle();
    return rig;
  }

  testWidgets("15: the hold's pill sits at the top centre with the iPad's smaller arrows", (tester) async {
    await mountHud(tester, pad: true);
    final box = tester.getRect(
      find.ancestor(of: find.byKey(const ValueKey('hud-speed-pill')), matching: find.byType(Container)).first,
    );
    expect(box.center.dx, closeTo(597, 0.5));
    expect(box.top, BiliMetrics.hudTop);
    expect(box.height, BiliMetrics.hudHeight);
    expect(
      arrowsOf(tester),
      const Size(PadFullScreenTheme.hudArrowStep + PadFullScreenTheme.hudArrowWidth, PadFullScreenTheme.hudArrowHeight),
    );
    expect(find.text('倍速中'), findsOneWidget);
  });

  testWidgets("the phone's pill keeps its own arrows", (tester) async {
    await mountHud(tester, pad: false);
    expect(arrowsOf(tester), const Size(BiliMetrics.hudArrowStep + BiliMetrics.hudArrowWidth, BiliMetrics.hudArrowHeight));
  });

  testWidgets('18, 19: 正在缓冲... with the speed, the TV on the screen\'s middle, as 18 and 19 place it', (tester) async {
    showAsPad(tester, landscape: true);
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(1194, 834), disableAnimations: true),
          child: PlayerLoading(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text(PlayerLoading.message), findsOneWidget);
    final text = tester.getRect(find.byKey(const ValueKey('player-loading-text')));
    expect(text.center.dx, closeTo(597, 0.5));
    // Under the TV centred on the screen's 417, as on the phone: 19's ink centres 448.5 pt down, the stand-ins' 447.5.
    expect(text.top, 417 + PlayerLoadingTheme.tvSize / 2 + PlayerLoadingTheme.gap);
  });

  Future<FakePlayerSession> mountPreview(WidgetTester tester, {double at = 25, VideoShot? shot}) async {
    showAsPad(tester, landscape: true);
    final session = FakePlayerSession()
      ..duration.value = 254
      ..chapters = const [
        Chapter(from: 0, to: 20.1, title: '开场'),
        Chapter(from: 20.1, to: 92.3, title: '寻找好位置'),
      ]
      ..seekFrames.value = shot;
    session.scrubbing.value = at;
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Positioned.fill(
              child: SeekPreview(
                session: session,
                shown: true,
                padBar: const Rect.fromLTRB(74.5, 720, 1194 - 74.5, 744),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  VideoShot shot({double cellWidth = 160, double cellHeight = 90}) => VideoShot(
    sheets: const ['https://i0.hdslb.com/bfs/videoshot/sheet.jpg'],
    columns: 10,
    rows: 10,
    times: [for (var i = 0; i <= 100; i++) i * 3],
    cellWidth: cellWidth,
    cellHeight: cellHeight,
  );

  testSheets('24: the 144 × 81 frame over the TV, 16 pt to its left, its bottom 20.2 pt above the bar', (tester) async {
    await mountPreview(tester, shot: shot());
    final frame = tester.getRect(find.byKey(const ValueKey('seek-preview-frame')));
    expect(frame.size, const Size(144, 81));
    // 25 s of 254 along the TV's travel (83.5 to 1110.5).
    const thumb = 83.5 + (1110.5 - 83.5) * 25 / 254;
    expect(frame.center.dx, closeTo(thumb - 16, 0.5));
    expect(frame.bottom, closeTo(732 - 20.2, 0.5));

    final time = tester.getRect(find.byKey(const ValueKey('seek-preview-time')));
    expect(time.center.dx, closeTo(frame.center.dx, 0.5));
    expect(find.text('00:25/04:14'), findsOneWidget);
    expect(find.byType(SpeedArrows), findsOneWidget);

    final title = tester.getRect(find.byKey(const ValueKey('seek-preview-chapter')));
    expect(find.text('寻找好位置'), findsOneWidget);
    expect(title.center.dx, closeTo(frame.center.dx, 0.5));
    expect(title.bottom, closeTo(frame.top - PadFullScreenTheme.previewTitleGap, 0.5));
  });

  testSheets('near the start the frame stays on the screen; a tall video keeps the height at its own shape', (
    tester,
  ) async {
    await mountPreview(tester, at: 0, shot: shot(cellWidth: 90, cellHeight: 160));
    final frame = tester.getRect(find.byKey(const ValueKey('seek-preview-frame')));
    expect(frame.height, 81);
    expect(frame.width, closeTo(81 * 90 / 160, 0.01));
    expect(frame.left, greaterThanOrEqualTo(PadFullScreenTheme.previewEdge));
  });

  testWidgets('without frames the time shows alone where the frame would be', (tester) async {
    await mountPreview(tester);
    expect(find.byKey(const ValueKey('seek-preview-frame')), findsNothing);
    expect(find.text('00:25/04:14'), findsOneWidget);
  });

  group('gestures at the iPad\'s size', () {
    Future<gestures.Rig> mount(WidgetTester tester) async {
      final rig = gestures.Rig();
      addTearDown(() {
        rig.chrome.dispose();
        rig.panels.dispose();
        rig.orientation.dispose();
        rig.session.dispose();
      });
      showAsPad(tester, landscape: true);
      await rig.mountFullScreen(tester);
      return rig;
    }

    testWidgets('a tap toggles the controls, a double tap plays or pauses', (tester) async {
      final rig = await mount(tester);
      await tester.tapAt(const Offset(597, 417));
      await tester.pump(PlayerGestureLayer.doubleTapWindow);
      expect(rig.chrome.visible, isFalse);
      await tester.tapAt(const Offset(597, 417));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(const Offset(597, 417));
      await tester.pump();
      expect(rig.calls, ['togglePlay']);
    });

    testWidgets('holding plays at 2× with the pill, the controls hidden; letting go puts it back', (tester) async {
      final rig = await mount(tester);
      rig.session.player.emit(const StatusChanged(PlayerStatus.playing));
      await tester.pump();
      final hold = await tester.startGesture(const Offset(900, 400));
      await tester.pump(PlayerGestureLayer.holdDelay + const Duration(milliseconds: 50));
      expect(rig.calls, ['speedUp true']);
      expect(rig.chrome.hud.value, isA<SpeedUpHud>());
      expect(rig.chrome.visible, isFalse);
      await hold.up();
      await tester.pump();
      expect(rig.calls.last, 'speedUp false');
      expect(rig.chrome.hud.value, isNull);
    });

    testWidgets('up and down: brightness on the left half, volume on the right; sideways seeks', (tester) async {
      final rig = await mount(tester);
      await tester.dragFrom(const Offset(300, 500), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(rig.device.sets.where((set) => set.startsWith('brightness')), isNotEmpty);

      await tester.dragFrom(const Offset(900, 500), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(rig.device.sets.where((set) => set.startsWith('volume')), isNotEmpty);

      final drag = await tester.startGesture(const Offset(400, 400));
      await drag.moveBy(const Offset(30, 0));
      await drag.moveBy(const Offset(200, 0));
      await tester.pump();
      expect(rig.chrome.hud.value, isA<SeekHud>());
      await drag.up();
      await tester.pump();
      expect(rig.callsStarting('commitSeek'), isNotEmpty);
    });
  });
}
