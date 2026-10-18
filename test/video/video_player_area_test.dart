import 'package:bilifast/danmaku/danmaku_layer.dart';
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/end_screen_landscape.dart';
import 'package:bilifast/player_ui/end_screen_portrait.dart';
import 'package:bilifast/player_ui/landscape_chrome.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/player_gestures.dart';
import 'package:bilifast/player_ui/player_hud.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/player_ui/portrait_controls.dart';
import 'package:bilifast/player_ui/stats_overlay.dart';
import 'package:bilifast/player_ui/vertical_chrome.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/video_player_area.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player_session.dart';

void main() {
  late FakePlayerSession session;
  late PlayerUi ui;
  late Widget video;
  final areaKey = GlobalKey();
  var backs = 0;

  setUp(() {
    session = FakePlayerSession();
    final chrome = ChromeState();
    final panels = PanelController();
    final orientation = OrientationController();
    addTearDown(() {
      session.dispose();
      chrome.dispose();
      panels.dispose();
      orientation.dispose();
    });
    ui = PlayerUi(
      session: session,
      chrome: chrome,
      panels: panels,
      orientation: orientation,
      device: NoDeviceControls(),
      onBack: () {},
    );
    video = session.player.buildView();
    backs = 0;
  });

  Future<void> show(
    WidgetTester tester,
    Presentation presentation, {
    bool withUi = true,
    bool loading = false,
    String? failure,
    Widget? cover,
    Size size = const Size(440, 956),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerArea(
          key: areaKey,
          presentation: presentation,
          onBack: () => backs++,
          ui: withUi ? ui : null,
          video: video,
          cover: cover,
          loading: loading,
          failure: failure,
          onRetry: () {},
        ),
      ),
    );
  }

  Rect videoRect(WidgetTester tester) => tester.getRect(find.byKey(const ValueKey('fake-video')));

  testWidgets('each presentation gets its own chrome, over the gestures and under the HUD', (tester) async {
    await show(tester, Presentation.inline);
    expect(find.byType(PortraitControls), findsOneWidget);
    expect(find.byType(LandscapeChrome), findsNothing);
    expect(find.byType(VerticalChrome), findsNothing);
    expect(find.byType(PlayerGestureLayer), findsOneWidget);
    expect(find.byType(PlayerHud), findsOneWidget);

    await show(tester, Presentation.landscape, size: const Size(956, 440));
    expect(find.byType(LandscapeChrome), findsOneWidget);
    expect(find.byType(PortraitControls), findsNothing);

    await show(tester, Presentation.vertical);
    expect(find.byType(VerticalChrome), findsOneWidget);
    expect(find.byType(LandscapeChrome), findsNothing);

    final stack = tester.widget<Stack>(
      find.descendant(of: find.byType(VideoPlayerArea), matching: find.byType(Stack)).first,
    );
    final order = stack.children.map((child) => child.key).toList();
    expect(
      order.indexOf(const ValueKey('video-gestures')),
      lessThan(order.indexOf(const ValueKey('chrome-vertical'))),
    );
    expect(order.indexOf(const ValueKey('chrome-vertical')), lessThan(order.indexOf(const ValueKey('video-hud'))));
  });

  testWidgets('the end screen takes the chrome\'s place: the small one inline and in 竖屏, the full one in landscape',
      (tester) async {
    session.ended = true;
    await show(tester, Presentation.inline);
    expect(find.byType(EndScreenPortrait), findsOneWidget);
    expect(find.byType(PortraitControls), findsNothing);
    expect(find.byType(PlayerHud), findsNothing);
    expect(find.byType(PlayerGestureLayer), findsNothing);

    await show(tester, Presentation.landscape, size: const Size(956, 440));
    expect(find.byType(EndScreenLandscape), findsOneWidget);
    expect(find.byType(EndScreenPortrait), findsNothing);
    expect(find.byType(LandscapeChrome), findsNothing);

    await show(tester, Presentation.vertical);
    expect(find.byType(EndScreenPortrait), findsOneWidget);
    final band = tester.getRect(find.byType(EndScreenPortrait));
    expect(band.width, 440);
    expect(band.height, closeTo(440 / BiliMetrics.videoAspect, 0.01));
    expect(band.center.dy, closeTo(956 * BiliMetrics.verticalVideoCentre, 0.01));
  });

  testWidgets('the end screens show no danmaku, and the danmaku switch reaches the layer', (tester) async {
    await show(tester, Presentation.inline);
    bool enabled() => tester.widget<DanmakuLayer>(find.byType(DanmakuLayer)).enabled;
    expect(enabled(), isTrue);
    session
      ..danmakuOn = false
      ..changed();
    await tester.pump();
    expect(enabled(), isFalse);
    session
      ..danmakuOn = true
      ..ended = true
      ..changed();
    await tester.pump();
    expect(enabled(), isFalse);
  });

  testWidgets('显示统计 puts the stats overlay over the video', (tester) async {
    await show(tester, Presentation.inline);
    expect(find.byType(StatsOverlay), findsNothing);
    session
      ..showStats = true
      ..changed();
    await tester.pump();
    expect(find.byType(StatsOverlay), findsOneWidget);
  });

  testWidgets('竖屏 sets a landscape video above the middle and lets a vertical one fill the screen', (tester) async {
    await show(tester, Presentation.vertical);
    expect(videoRect(tester), const Rect.fromLTWH(0, 0, 440, 956 * BiliMetrics.verticalVideoCentre * 2));
    session
      ..isVertical = true
      ..changed();
    await tester.pump();
    expect(videoRect(tester), const Rect.fromLTWH(0, 0, 440, 956));
  });

  testWidgets('the video keeps its element through every presentation, the end and a failure', (tester) async {
    await show(tester, Presentation.inline);
    final first = tester.element(find.byKey(const ValueKey('fake-video')));
    Future<void> same() async {
      expect(identical(tester.element(find.byKey(const ValueKey('fake-video'))), first), isTrue);
    }

    await show(tester, Presentation.landscape, size: const Size(956, 440));
    await same();
    await show(tester, Presentation.vertical);
    await same();
    session
      ..ended = true
      ..changed();
    await tester.pump();
    await same();
    await show(tester, Presentation.inline, failure: '播放失败');
    await same();
    await show(tester, Presentation.inline, loading: true);
    await same();
  });

  testWidgets('without a session or after a failure the area has its own back arrow; with chrome it has none',
      (tester) async {
    await show(tester, Presentation.inline, withUi: false, loading: true);
    expect(find.byKey(const ValueKey('video-loading')), findsOneWidget);
    expect(find.byType(PortraitControls), findsNothing);
    await tester.tap(find.byKey(const ValueKey('video-back')));
    expect(backs, 1);

    await show(tester, Presentation.inline);
    expect(find.byKey(const ValueKey('video-back')), findsNothing);

    await show(tester, Presentation.inline, failure: '播放失败');
    expect(find.byKey(const ValueKey('video-retry')), findsOneWidget);
    expect(find.byType(PortraitControls), findsNothing, reason: 'the failure covers the player');
    await tester.tap(find.byKey(const ValueKey('video-back')));
    expect(backs, 2);
  });

  testWidgets('the cover keeps its element as the session, the chrome and the spinner come', (tester) async {
    const cover = SizedBox.expand(key: ValueKey('video-cover'));
    await show(tester, Presentation.inline, withUi: false, loading: true, cover: cover);
    final first = tester.element(find.byKey(const ValueKey('video-cover')));
    await show(tester, Presentation.inline, loading: true, cover: cover);
    await show(tester, Presentation.inline, cover: cover);
    expect(identical(tester.element(find.byKey(const ValueKey('video-cover'))), first), isTrue);
  });
}
