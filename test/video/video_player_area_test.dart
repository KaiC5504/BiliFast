import 'package:bili_core/api.dart' show BiliClient, CookieJar, DanmakuMaskInfo;
import 'package:bili_core/devlog.dart';
import 'package:bilifast/danmaku/block_rule_store.dart';
import 'package:bilifast/danmaku/danmaku_layer.dart';
import 'package:bilifast/danmaku/danmaku_session.dart';
import 'package:bilifast/danmaku/danmaku_settings_store.dart';
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/playback/danmaku_feed.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/end_screen_landscape.dart';
import 'package:bilifast/player_ui/end_screen_portrait.dart';
import 'package:bilifast/player_ui/landscape_chrome.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/player_gestures.dart';
import 'package:bilifast/player_ui/player_hud.dart';
import 'package:bilifast/player_ui/player_loading.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/player_ui/portrait_controls.dart';
import 'package:bilifast/player_ui/stats_overlay.dart';
import 'package:bilifast/player_ui/vertical_chrome.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/story/story_drag.dart';
import 'package:bilifast/video/story/story_pager.dart';
import 'package:bilifast/video/video_player_area.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';
import '../support/fake_mask_feed.dart';
import '../support/fake_player_session.dart';
import 'story/fake_story_feed.dart';

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
    ValueListenable<bool>? waiting,
    String? failure,
    Widget? cover,
    Size size = const Size(440, 956),
    ValueListenable<bool>? turning,
    ValueListenable<double?>? verticalTurn,
    ValueListenable<Rect?>? slide,
    StoryPager? storyPager,
    bool? moveTargets,
    VoidCallback? onRetry,
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
          waiting: waiting,
          failure: failure,
          onRetry: onRetry ?? () {},
          turning: turning,
          verticalTurn: verticalTurn,
          slide: slide,
          storyPager: storyPager,
          moveTargets: moveTargets,
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
      find.descendant(of: find.byKey(const ValueKey('video-pinned')), matching: find.byType(Stack)).first,
    );
    final order = stack.children.map((child) => child.key).toList();
    expect(
      find.descendant(of: find.byKey(const ValueKey('video-chrome')), matching: find.byType(VerticalChrome)),
      findsOneWidget,
    );
    expect(
      order.indexOf(const ValueKey('video-gestures')),
      lessThan(order.indexOf(const ValueKey('video-chrome'))),
    );
    expect(order.indexOf(const ValueKey('video-chrome')), lessThan(order.indexOf(const ValueKey('video-hud'))));
  });

  testWidgets('shrinking to the 继续播放 bar: the controls take no touches, and once it is the bar nothing of them '
      'shows (12); the danmaku keep laying out at the full height, clipped', (tester) async {
    const full = 440 / BiliMetrics.videoAspect;
    Future<void> shrink(double height, {bool shrunk = true, bool barred = false}) async {
      tester.view.physicalSize = const Size(440, 956);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: height,
              child: VideoPlayerArea(
                key: areaKey,
                presentation: Presentation.inline,
                onBack: () {},
                ui: ui,
                video: video,
                shrunk: shrunk,
                barred: barred,
                danmakuHeight: full,
              ),
            ),
          ),
        ),
      );
    }

    IgnorePointer chrome() => tester.widget<IgnorePointer>(find.byKey(const ValueKey('video-chrome')));
    await shrink(full, shrunk: false);
    expect(chrome().ignoring, isFalse);
    expect(tester.getSize(find.byType(DanmakuLayer)), const Size(440, full));
    final first = tester.element(find.byType(DanmakuLayer));

    await shrink(150);
    expect(chrome().ignoring, isTrue);
    expect(find.byType(PortraitControls), findsOneWidget, reason: 'the thin line still runs along the bottom (11)');
    expect(tester.getSize(find.byType(DanmakuLayer)), const Size(440, full), reason: 'not re-laid at 150');
    expect(identical(tester.element(find.byType(DanmakuLayer)), first), isTrue);
    final clip = tester.widget<ClipRect>(
      find.ancestor(of: find.byType(DanmakuLayer), matching: find.byType(ClipRect)).first,
    );
    expect(clip.clipBehavior, Clip.hardEdge);
    expect(tester.getSize(find.byKey(const ValueKey('fake-video'))), const Size(440, 150), reason: 'letterboxed');

    await shrink(CollapseTheme.barHeight, barred: true);
    expect(find.byType(PortraitControls), findsNothing);
    expect(find.byType(PortraitControls, skipOffstage: false), findsOneWidget, reason: 'kept for when it grows');
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

  testWidgets('while the page turns the player, the chrome, the HUD and the end screen are out of sight and take no '
      'touches, kept as they were; the gestures and the danmaku stay', (tester) async {
    final turning = ValueNotifier(false);
    addTearDown(turning.dispose);
    await show(tester, Presentation.inline, turning: turning);
    bool drawn(Type type) =>
        tester.widget<Visibility>(find.ancestor(of: find.byType(type), matching: find.byType(Visibility)).first).visible;
    bool backTouched() => tester
        .hitTestOnBinding(tester.getCenter(find.byKey(const ValueKey('video-back'))))
        .path
        .any((entry) => entry.target == tester.renderObject(find.byKey(const ValueKey('video-back'))));
    expect(drawn(PortraitControls), isTrue);
    expect(drawn(PlayerHud), isTrue);
    expect(backTouched(), isTrue);
    final controls = tester.element(find.byType(PortraitControls));

    turning.value = true;
    await tester.pump();
    expect(drawn(PortraitControls), isFalse);
    expect(drawn(PlayerHud), isFalse);
    expect(backTouched(), isFalse);
    expect(find.byType(PlayerGestureLayer), findsOneWidget);
    expect(find.byType(DanmakuLayer), findsOneWidget);
    expect(identical(tester.element(find.byType(PortraitControls)), controls), isTrue);

    turning.value = false;
    await tester.pump();
    expect(drawn(PortraitControls), isTrue);
    expect(backTouched(), isTrue);

    session.ended = true;
    turning.value = true;
    await show(tester, Presentation.inline, turning: turning);
    expect(drawn(EndScreenPortrait), isFalse);
    turning.value = false;
    await tester.pump();
    expect(drawn(EndScreenPortrait), isTrue);
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

  testWidgets('竖屏 sets a landscape video above the middle and an upright one a little higher, as 16 does', (
    tester,
  ) async {
    // The native view letterboxes the picture into the band it is given.
    Rect picture(Size video) {
      final band = videoRect(tester);
      return Alignment.center.inscribe(applyBoxFit(BoxFit.contain, video, band.size).destination, band);
    }

    await show(tester, Presentation.vertical);
    expect(videoRect(tester), const Rect.fromLTWH(0, 0, 440, 956 * BiliMetrics.verticalVideoCentre * 2));
    expect(picture(const Size(1920, 1080)).center.dy, closeTo(396.74, 0.01));

    session
      ..isVertical = true
      ..changed();
    await tester.pump();
    expect(videoRect(tester), const Rect.fromLTWH(0, 0, 440, 926));
    // 16's 3:4 video spans 169.67-756.33 pt, its bottom on the uploader row's top.
    final upright = picture(const Size(1080, 1440));
    expect(upright.top, closeTo(169.67, 0.01));
    expect(upright.bottom, closeTo(756.33, 0.01));
    expect(upright.width, 440);
  });

  testWidgets("竖屏 gives a square video the upright band, as the chrome's last button takes it as upright", (
    tester,
  ) async {
    session
      ..videoShape = (width: 1080, height: 1080)
      ..changed();
    await show(tester, Presentation.vertical, loading: true);
    expect(VerticalChrome.uprightShape(session), isTrue);
    expect(videoRect(tester), const Rect.fromLTWH(0, 0, 440, 926));
    final loading = find.ancestor(of: find.byType(PlayerLoading), matching: find.byType(FractionallySizedBox)).first;
    expect(tester.getRect(loading).height, closeTo(926, 0.01), reason: 'the loading TV centres on the same band');

    session
      ..videoShape = (width: 1081, height: 1080)
      ..changed();
    await tester.pump();
    expect(VerticalChrome.uprightShape(session), isFalse);
    expect(videoRect(tester).height, closeTo(956 * BiliMetrics.verticalVideoCentre * 2, 0.01));
  });

  testWidgets('holding 竖屏\'s bar leaves the video where it is and the danmaku flying (19, 20)', (tester) async {
    session
      ..isVertical = true
      ..changed();
    await show(tester, Presentation.vertical);
    final before = videoRect(tester);
    final danmaku = tester.getRect(find.byType(DanmakuLayer));
    ui.chrome.holdBar(true);
    await tester.pump(const Duration(milliseconds: 400));
    expect(videoRect(tester), before);
    expect(tester.getRect(find.byType(DanmakuLayer)), danmaku);
    expect(tester.widget<DanmakuLayer>(find.byType(DanmakuLayer)).enabled, isTrue);
    final unseen = find.ancestor(of: find.byType(DanmakuLayer), matching: find.byType(Visibility)).first;
    expect(tester.widget<Visibility>(unseen).visible, isTrue);
    ui.chrome.holdBar(false);
  });

  testWidgets('turning between 竖屏 and landscape, the video goes from 竖屏\'s band to the whole box, and the danmaku '
      'are put away, kept as they were', (tester) async {
    final turn = ValueNotifier<double?>(null);
    addTearDown(turn.dispose);
    await show(tester, Presentation.vertical, verticalTurn: turn);
    bool danmakuDrawn() => tester
        .widget<Visibility>(find.ancestor(of: find.byType(DanmakuLayer), matching: find.byType(Visibility)).first)
        .visible;
    const band = 956 * BiliMetrics.verticalVideoCentre * 2;
    expect(videoRect(tester).height, closeTo(band, 0.01));
    expect(danmakuDrawn(), isTrue);
    final danmaku = tester.element(find.byType(DanmakuLayer));

    turn.value = 0;
    await tester.pump();
    expect(videoRect(tester).height, closeTo(band, 0.01), reason: 'where it was in 竖屏');
    expect(danmakuDrawn(), isFalse);
    turn.value = 0.5;
    await tester.pump();
    expect(videoRect(tester).height, closeTo((band + 956) / 2, 0.01));

    // Laid out for landscape at the end of the turn, at the box it ends at.
    turn.value = 1;
    await show(tester, Presentation.landscape, size: const Size(956, 440), verticalTurn: turn);
    expect(videoRect(tester), const Rect.fromLTWH(0, 0, 956, 440));
    turn.value = null;
    await tester.pump();
    expect(videoRect(tester), const Rect.fromLTWH(0, 0, 956, 440));
    expect(danmakuDrawn(), isTrue);
    expect(identical(tester.element(find.byType(DanmakuLayer)), danmaku), isTrue);

    session
      ..isVertical = true
      ..changed();
    turn.value = 0;
    await show(tester, Presentation.vertical, verticalTurn: turn);
    const upright = 956 * BiliMetrics.verticalUprightCentre * 2;
    expect(videoRect(tester).height, closeTo(upright, 0.01), reason: 'an upright video from its own band');
    turn.value = 0.5;
    await tester.pump();
    expect(videoRect(tester).height, closeTo((upright + 956) / 2, 0.01));
    turn.value = 1;
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

  testWidgets('without a session or after a failure the area has its own back arrow; with chrome it is the controls one',
      (tester) async {
    await show(tester, Presentation.inline, withUi: false, loading: true);
    expect(find.byKey(const ValueKey('video-loading')), findsOneWidget);
    expect(find.byType(PortraitControls), findsNothing);
    await tester.tap(find.byKey(const ValueKey('video-back')));
    expect(backs, 1);

    await show(tester, Presentation.inline);
    expect(
      find.descendant(of: find.byType(PortraitControls), matching: find.byKey(const ValueKey('video-back'))),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('video-back')), findsOneWidget);

    await show(tester, Presentation.inline, failure: '播放失败');
    expect(find.byKey(const ValueKey('video-retry')), findsOneWidget);
    expect(find.byType(PortraitControls), findsNothing, reason: 'the failure covers the player');
    await tester.tap(find.byKey(const ValueKey('video-back')));
    expect(backs, 2);
  });

  testWidgets('the loading TV shows for a load or a wait, over the chrome, centred on the video', (tester) async {
    final waiting = ValueNotifier(false);
    addTearDown(waiting.dispose);
    await show(tester, Presentation.inline, waiting: waiting);
    expect(find.byType(PlayerLoading), findsNothing);
    waiting.value = true;
    await tester.pump();
    expect(find.byKey(const ValueKey('video-loading')), findsOneWidget);
    expect(find.byType(PlayerLoading), findsOneWidget);
    final stack = tester.widget<Stack>(
      find.descendant(of: find.byKey(const ValueKey('video-pinned')), matching: find.byType(Stack)).first,
    );
    final order = stack.children.map((child) => child.key).toList();
    expect(order.indexOf(const ValueKey('video-hud')), lessThan(order.indexOf(const ValueKey('video-loading-layer'))));
    waiting.value = false;
    await tester.pump();
    expect(find.byType(PlayerLoading), findsNothing);

    await show(tester, Presentation.inline, loading: true, waiting: waiting);
    expect(find.byType(PlayerLoading), findsOneWidget);

    // 竖屏 sets a landscape video in its band above the middle; the TV keeps to the video.
    await show(tester, Presentation.vertical, loading: true);
    final band = 956 * BiliMetrics.verticalVideoCentre * 2;
    expect(tester.getRect(find.byType(PlayerLoading)), const Offset(0, 0) & Size(440, band));
    session
      ..isVertical = true
      ..changed();
    await tester.pump();
    expect(tester.getRect(find.byType(PlayerLoading)), const Offset(0, 0) & const Size(440, 926));
    expect(tester.getCenter(find.byType(PlayerLoading)).dy, 463, reason: "on an upright video's centre (16)");

    session
      ..isVertical = false
      ..heldVertical = true
      ..changed();
    await tester.pump();
    expect(tester.getCenter(find.byType(PlayerLoading)).dy, 463, reason: 'an in-page open keeps the last band');
    expect(videoRect(tester).height, 926);
    session
      ..heldVertical = null
      ..changed();
    await tester.pump();
    expect(tester.getRect(find.byType(PlayerLoading)), const Offset(0, 0) & Size(440, band));

    await show(tester, Presentation.inline, loading: true, failure: '播放失败');
    expect(find.byType(PlayerLoading), findsNothing, reason: 'the failure takes its place');
  });

  testWidgets('the loading TV is out of sight through a turn, where the pinned layer would stretch it', (tester) async {
    final turning = ValueNotifier(false);
    addTearDown(turning.dispose);
    await show(tester, Presentation.inline, loading: true, turning: turning);
    bool drawn() => tester
        .widget<Visibility>(find.ancestor(of: find.byType(PlayerLoading), matching: find.byType(Visibility)).first)
        .visible;
    expect(drawn(), isTrue);
    turning.value = true;
    await tester.pump();
    expect(drawn(), isFalse);
    turning.value = false;
    await tester.pump();
    expect(drawn(), isTrue);
  });

  testWidgets('the cover keeps its element as the session, the chrome and the spinner come', (tester) async {
    const cover = SizedBox.expand(key: ValueKey('video-cover'));
    await show(tester, Presentation.inline, withUi: false, loading: true, cover: cover);
    final first = tester.element(find.byKey(const ValueKey('video-cover')));
    await show(tester, Presentation.inline, loading: true, cover: cover);
    await show(tester, Presentation.inline, cover: cover);
    expect(identical(tester.element(find.byKey(const ValueKey('video-cover'))), first), isTrue);
  });
  group("人像防挡's picture", () {
    /// Where the layer is told the picture is, on screen: through every transform between the layer and the screen.
    Rect told(WidgetTester tester) {
      final picture = tester.widget<DanmakuLayer>(find.byType(DanmakuLayer)).picture!;
      final layer = tester.renderObject<RenderBox>(find.byType(DanmakuLayer));
      return Rect.fromPoints(layer.localToGlobal(picture.topLeft), layer.localToGlobal(picture.bottomRight));
    }

    /// Where the player draws it: fitted into the native view's box.
    Rect drawn(WidgetTester tester) {
      final box = videoRect(tester);
      final shape = session.videoShape!;
      final video = Size(shape.width.toDouble(), shape.height.toDouble());
      return videoPicture(box.size, fit: session.fit, video: video)!.shift(box.topLeft);
    }

    Future<void> place(
      WidgetTester tester,
      Presentation presentation, {
      Size screen = const Size(440, 956),
      double topInset = 0,
      double? height,
      double? danmakuHeight,
      ValueListenable<Size?>? pin,
    }) async {
      tester.view
        ..physicalSize = screen
        ..devicePixelRatio = 1
        ..padding = FakeViewPadding(top: topInset);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: height ?? screen.height,
              child: VideoPlayerArea(
                key: areaKey,
                presentation: presentation,
                onBack: () {},
                ui: ui,
                video: video,
                danmakuHeight: danmakuHeight,
                pin: pin,
              ),
            ),
          ),
        ),
      );
    }

    setUp(() => session.videoShape = (width: 1920, height: 1080));

    testWidgets('the small player: the picture as the player fits it, for each fit, and 镜像 passed on', (tester) async {
      await place(tester, Presentation.inline, height: 300);
      final layer = tester.widget<DanmakuLayer>(find.byType(DanmakuLayer));
      expect(layer.picture, rectMoreOrLessEquals(const Rect.fromLTWH(0, 26.25, 440, 247.5)));
      expect(layer.mirrored, isFalse);
      for (final fit in FitMode.values) {
        session
          ..fit = fit
          ..mirrored = fit == FitMode.fill
          ..changed();
        await tester.pump();
        expect(told(tester), rectMoreOrLessEquals(drawn(tester)), reason: fit.label);
        expect(tester.widget<DanmakuLayer>(find.byType(DanmakuLayer)).mirrored, fit == FitMode.fill);
      }
    });

    testWidgets('no shape yet, no picture for 适应; a new shape moves it', (tester) async {
      session.videoShape = null;
      await place(tester, Presentation.inline, height: 300);
      expect(tester.widget<DanmakuLayer>(find.byType(DanmakuLayer)).picture, isNull);
      session
        ..videoShape = (width: 1080, height: 1920)
        ..changed();
      await tester.pump();
      expect(told(tester), rectMoreOrLessEquals(drawn(tester)));
      expect(told(tester).width, closeTo(300 * 9 / 16, 1e-9));
    });

    testWidgets('under the status bar, the danmaku start below it and the picture is told from there', (tester) async {
      await place(tester, Presentation.landscape, screen: const Size(956, 440), topInset: 20);
      expect(tester.getTopLeft(find.byType(DanmakuLayer)), const Offset(0, 20));
      expect(told(tester), rectMoreOrLessEquals(drawn(tester)));
      final picture = tester.widget<DanmakuLayer>(find.byType(DanmakuLayer)).picture!;
      expect(picture.top, closeTo(-20, 1e-9), reason: 'the picture fills the height, from above the danmaku');
    });

    testWidgets("竖屏: the band's insets, a wide video and an upright one", (tester) async {
      await place(tester, Presentation.vertical, topInset: 59);
      expect(tester.getTopLeft(find.byType(DanmakuLayer)).dy, greaterThan(59));
      expect(told(tester), rectMoreOrLessEquals(drawn(tester)));

      session
        ..isVertical = true
        ..videoShape = (width: 1080, height: 1440)
        ..changed();
      await tester.pump();
      expect(told(tester), rectMoreOrLessEquals(drawn(tester)));
    });

    testWidgets('竖屏, worked by hand: a 16:9 video letterboxed in the band, the danmaku under the top row', (
      tester,
    ) async {
      await place(tester, Presentation.vertical, topInset: 59);
      // The band is 0.415 × 2 of 956 = 793.48 pt; the 440 × 247.5 picture centres on 396.74, so its top is 272.99.
      const picture = Rect.fromLTWH(0, 272.99, 440, 247.5);
      expect(told(tester), rectMoreOrLessEquals(picture, epsilon: 1e-9));
      // The danmaku start 59 − 8 + 44 + 1 = 96 pt down, so the layer is told the picture from there.
      expect(tester.getTopLeft(find.byType(DanmakuLayer)), const Offset(0, 96));
      expect(
        tester.widget<DanmakuLayer>(find.byType(DanmakuLayer)).picture,
        rectMoreOrLessEquals(picture.shift(const Offset(0, -96)), epsilon: 1e-9),
      );
    });

    testWidgets("the iPad: no inset, the picture told from the box's own corner", (tester) async {
      for (final presentation in [Presentation.inline, Presentation.landscape]) {
        await place(tester, presentation, screen: const Size(1194, 834), topInset: 24);
        expect(tester.getTopLeft(find.byType(DanmakuLayer)), Offset.zero);
        final picture = tester.widget<DanmakuLayer>(find.byType(DanmakuLayer)).picture!;
        expect(picture, rectMoreOrLessEquals(drawn(tester)));
      }
    });

    testWidgets('growing or shrinking, the danmaku laid out at the pinned size see the picture scaled to it', (
      tester,
    ) async {
      final pin = ValueNotifier<Size?>(const Size(956, 440));
      addTearDown(pin.dispose);
      await place(tester, Presentation.landscape, height: 600, pin: pin);
      expect(
        tester.renderObject<RenderBox>(find.byType(DanmakuLayer)).size,
        const Size(956, 440),
        reason: 'laid out at the pinned size',
      );
      expect(told(tester), rectMoreOrLessEquals(drawn(tester)));
      pin.value = null;
      await tester.pump();
      expect(told(tester), rectMoreOrLessEquals(drawn(tester)));
    });

    testWidgets('the small player shrinking keeps its danmaku tall, and the picture follows the box', (tester) async {
      const full = 440 / BiliMetrics.videoAspect;
      await place(tester, Presentation.inline, height: 150, danmakuHeight: full);
      expect(tester.getSize(find.byType(DanmakuLayer)), const Size(440, full));
      expect(told(tester), rectMoreOrLessEquals(drawn(tester)));
      expect(told(tester).height, closeTo(150, 1e-9));
    });

    testWidgets("the page's 人像防挡 feed reaches the layer and clips it; switched off, the danmaku draw as before", (
      tester,
    ) async {
      final logger = Logger(session: 'test');
      final feed = DanmakuFeed(
        client: BiliClient(transport: Canned.http(), cookies: CookieJar(Canned.cookies), logger: logger),
        logger: logger,
      );
      final store = DanmakuSettingsStore.memory();
      final api = FakePageApi();
      final rules = BlockRuleStore(api: api, isLoggedIn: () => false);
      final mask = ValueNotifier<DanmakuMaskInfo?>(
        DanmakuMaskInfo(cid: 1, plat: 0, fps: 30, time: 1, url: Uri.parse('https://upos.example/1.webmask')),
      );
      final feeds = FakeMaskFeeds();
      final danmaku = DanmakuSession(
        feed: feed,
        settings: store,
        rules: rules,
        api: api,
        target: () => null,
        position: () => 0,
        isLoggedIn: () => false,
        isVip: () => false,
        accountMid: () => 0,
        requestLogin: () {},
        maskInfo: mask,
        maskFetch: (url, {required start, end}) async => Uint8List(0),
        maskFeeds: feeds.call,
      );
      final page = PlayerUi(
        session: session,
        chrome: ui.chrome,
        panels: ui.panels,
        orientation: ui.orientation,
        device: NoDeviceControls(),
        onBack: () {},
        danmaku: danmaku,
      );
      addTearDown(() {
        danmaku.dispose();
        rules.dispose();
        feed.dispose();
        store.dispose();
        mask.dispose();
      });
      feeds.made.single.frames = (_) => maskFrame(const Rect.fromLTWH(0, 0, 80, 90));
      tester.view
        ..physicalSize = const Size(440, 956)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: 247.5,
              child: VideoPlayerArea(presentation: Presentation.inline, onBack: () {}, ui: page, video: video),
            ),
          ),
        ),
      );
      final layer = find.byType(DanmakuLayer);
      expect(tester.widget<DanmakuLayer>(layer).mask, same(danmaku.mask));
      final painter = tester.renderObject(find.descendant(of: layer, matching: find.byType(CustomPaint)));
      // The frame's left half is open to danmaku, the right half is a person.
      final halves = isPathThat(includes: const [Offset(100, 120)], excludes: const [Offset(340, 120)]);
      expect(painter, paints..clipPath(pathMatcher: halves));

      store.update(store.value.copyWith(peopleShield: false));
      await tester.pump();
      expect(feeds.made.single.disposed, isTrue);
      expect(painter, paintsExactlyCountTimes(#clipPath, 0));
    });
  });

  group("竖屏's swipe", () {
    late StoryDrag drag;
    late StoryPager pager;
    late FakeStoryFeed feed;

    setUp(() {
      drag = StoryDrag();
      pager = StoryPager(drag: drag, vsync: const TestVSync());
      feed = FakeStoryFeed([storyEntry('BV1'), storyEntry('BV2'), storyEntry('BV3')]);
      addTearDown(() {
        pager.dispose();
        drag.dispose();
        feed.dispose();
      });
    });

    List<Key?> order(WidgetTester tester) => tester
        .widget<Stack>(
          find.descendant(of: find.byKey(areaKey), matching: find.byType(Stack)).first,
        )
        .children
        .map((child) => child.key)
        .toList();

    testWidgets('the picture and its danmaku follow the finger; the neighbours lie between them and the controls',
        (tester) async {
      pager.feed = feed;
      await show(tester, Presentation.vertical, storyPager: pager);
      final rest = videoRect(tester);
      final danmaku = tester.getRect(find.byType(DanmakuLayer));
      final layers = order(tester);
      expect(layers.indexOf(const ValueKey('video-surface')), lessThan(layers.indexOf(const ValueKey('story-neighbours'))));
      expect(layers.indexOf(const ValueKey('story-neighbours')), lessThan(layers.indexOf(const ValueKey('video-pinned'))));

      drag
        ..start()
        ..update(-240);
      await tester.pump();
      expect(videoRect(tester), rest.shift(const Offset(0, -240)));
      expect(tester.getRect(find.byType(DanmakuLayer)), danmaku.shift(const Offset(0, -240)));
      drag.cancel();
      await tester.pumpAndSettle();
      expect(videoRect(tester), rest);
    });

    testWidgets('outside 竖屏, or with no feed, nothing moves and there are no neighbours', (tester) async {
      await show(tester, Presentation.vertical, storyPager: pager);
      expect(find.byType(StoryNeighbours), findsNothing, reason: 'no feed yet');
      pager.feed = feed;
      await show(tester, Presentation.inline, storyPager: pager);
      expect(find.byType(StoryNeighbours), findsNothing);
      final rest = videoRect(tester);
      drag
        ..start()
        ..update(-240);
      await tester.pump();
      expect(videoRect(tester), rest);
      drag.cancel();
      await tester.pumpAndSettle();
    });

    testWidgets('the native view keeps its element as the swipe comes and goes', (tester) async {
      await show(tester, Presentation.inline, storyPager: pager);
      final first = tester.element(find.byKey(const ValueKey('fake-video')));
      pager.feed = feed;
      await show(tester, Presentation.vertical, storyPager: pager);
      expect(identical(tester.element(find.byKey(const ValueKey('fake-video'))), first), isTrue);
      pager.feed = null;
      await tester.pump();
      expect(identical(tester.element(find.byKey(const ValueKey('fake-video'))), first), isTrue);
    });

    testWidgets('VoiceOver and the test tool move with 下一个视频 and 上一个视频, settling as a swipe does',
        (tester) async {
      final semantics = tester.ensureSemantics();
      pager.feed = feed;
      await show(tester, Presentation.vertical, storyPager: pager);
      const next = CustomSemanticsAction(label: '下一个视频');
      const previous = CustomSemanticsAction(label: '上一个视频');
      final node = find.semantics.byPredicate(
        (node) => node.getSemanticsData().customSemanticsActionIds?.isNotEmpty ?? false,
      );
      SemanticsData data() => node.evaluate().single.getSemanticsData();
      Set<int> actions() => data().customSemanticsActionIds!.toSet();
      expect(actions(), {CustomSemanticsAction.getIdentifier(next)}, reason: 'nothing before the first video');

      void perform(CustomSemanticsAction action) => tester.semantics.customAction(node, action);
      perform(next);
      await tester.pump(const Duration(milliseconds: 17));
      expect(drag.offset, lessThan(0), reason: 'animated, not a jump');
      expect(feed.moves, isEmpty);
      await tester.pump(const Duration(milliseconds: 200));
      expect(feed.moves, [1]);
      expect(drag.moving, isFalse);
      expect(
        actions(),
        {CustomSemanticsAction.getIdentifier(next), CustomSemanticsAction.getIdentifier(previous)},
      );
      perform(previous);
      await tester.pump(const Duration(milliseconds: 17));
      await tester.pump(const Duration(milliseconds: 200));
      expect(feed.moves, [1, 0]);

      await show(tester, Presentation.inline, storyPager: pager);
      expect(node, findsNothing, reason: 'only in 竖屏');
      semantics.dispose();
    });

    testWidgets('下一个视频 is offered with no next video known yet, and asks the feed again as a swipe past the end does',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final alone = _AskingFeed([storyEntry('BV1')]);
      addTearDown(alone.dispose);
      pager.feed = alone;
      await show(tester, Presentation.vertical, storyPager: pager);
      const next = CustomSemanticsAction(label: '下一个视频');
      final node = find.semantics.byPredicate(
        (node) => node.getSemanticsData().customSemanticsActionIds?.isNotEmpty ?? false,
      );
      expect(node, findsOne, reason: 'a stalled feed can still be asked');
      expect(node.evaluate().single.getSemanticsData().customSemanticsActionIds!.toSet(), {
        CustomSemanticsAction.getIdentifier(next),
      });

      tester.semantics.customAction(node, next);
      await tester.pump(const Duration(milliseconds: 200));
      expect(alone.asks, 1);
      expect(alone.moves, isEmpty);
      expect(drag.moving, isFalse, reason: 'nothing to move to');

      alone.add(storyEntry('BV2'));
      await tester.pump();
      tester.semantics.customAction(node, next);
      await tester.pump(const Duration(milliseconds: 17));
      await tester.pump(const Duration(milliseconds: 200));
      expect(alone.moves, [1], reason: 'once one is in, it moves');
      semantics.dispose();
    });

    testWidgets("the still held for the video landed on goes where the page puts the video's box, the neighbours left "
        'out (the uploader sheet over 竖屏, 181)', (tester) async {
      final pictured = FakeStoryFeed([
        storyEntry('BV1', cover: pic('BV1')),
        storyEntry('BV2', cover: pic('BV2')),
        storyEntry('BV3', cover: pic('BV3')),
      ]);
      addTearDown(pictured.dispose);
      pager.feed = pictured;
      final slide = ValueNotifier<Rect?>(null);
      addTearDown(slide.dispose);
      await show(tester, Presentation.vertical, storyPager: pager, slide: slide);
      expect(pager.moveNext(), isTrue);
      await tester.pumpAndSettle();
      Finder still(String bvid) => find.byWidgetPredicate((widget) => widget is RemoteImage && widget.url == pic(bvid));
      expect(still('BV2'), findsOne, reason: 'held until its first frame');

      const room = Rect.fromLTRB(0, VerticalSheetTheme.pictureTop, 440, VerticalSheetTheme.pictureBottom);
      slide.value = room;
      await tester.pump();
      expect(videoRect(tester), room);
      expect(
        tester.getRect(still('BV2')),
        rectMoreOrLessEquals(Rect.fromCenter(center: room.center, width: room.height * 9 / 16, height: room.height)),
        reason: 'over the picture as the player fits it into the room, not over the whole band',
      );
      expect(still('BV1'), findsNothing);
      expect(still('BV3'), findsNothing);
      expect(find.byType(VerticalChromePreview), findsNothing);

      slide.value = null;
      await tester.pump();
      expect(still('BV3'), findsOne, reason: 'the neighbours come back with the band');
    });

    testWidgets('the video landed on holds its still on black over the whole page until its first frame, so nothing of '
        'the video before shows around it: from the frame it lands, and going back too', (tester) async {
      final mixed = FakeStoryFeed([
        storyEntry('BV1', cover: pic('BV1')),
        storyEntry('BV2', cover: pic('BV2'), width: 1920, height: 1080),
      ]);
      addTearDown(mixed.dispose);
      pager.feed = mixed;
      // An upright video playing; the player keeps its band until the next video's shape is in.
      session
        ..isVertical = true
        ..changed();
      await show(tester, Presentation.vertical, storyPager: pager);
      final backdrop = find.byKey(const ValueKey('story-backdrop'));
      final upright = videoRect(tester);
      expect(upright, const Rect.fromLTWH(0, 0, 440, 926));
      expect(backdrop, findsNothing);

      drag
        ..start()
        ..update(-120);
      await tester.pump();
      expect(backdrop, findsNothing, reason: 'nothing is held while the video before plays');
      drag.end(-1500);
      while (drag.moving) {
        await tester.pump(const Duration(microseconds: 16667));
      }
      expect(mixed.moves, [1]);
      expect(find.descendant(of: find.byKey(const ValueKey('story-neighbours')), matching: backdrop), findsOne);
      expect(tester.getRect(backdrop), const Rect.fromLTWH(0, 0, 440, 956), reason: 'in the frame it lands');
      expect(videoRect(tester), upright, reason: 'the last picture of the video before, under it');
      final still = find.byWidgetPredicate((widget) => widget is RemoteImage && widget.url == pic('BV2'));
      expect(tester.getRect(still).height, 247.5, reason: "the wide video's still in its own band, over the black");

      pager.framed('BV2');
      await tester.pump();
      expect(backdrop, findsNothing, reason: 'its own picture shows now');

      expect(pager.movePrevious(), isTrue);
      await tester.pump(const Duration(milliseconds: 17));
      expect(backdrop, findsNothing, reason: 'nothing held while the page moves');
      await tester.pump(const Duration(milliseconds: 200));
      expect(mixed.moves, [1, 0]);
      expect(tester.getRect(backdrop), const Rect.fromLTWH(0, 0, 440, 956));
      pager.framed('BV1');
      await tester.pump();
      expect(backdrop, findsNothing);
    });

    testWidgets('no loading TV over the still held for a video swiped to, until it has waited '
        '${StoryPagerTheme.quietLoading.inSeconds} s; a failure still shows', (tester) async {
      pager.feed = feed;
      await show(tester, Presentation.vertical, storyPager: pager, loading: true);
      expect(find.byType(PlayerLoading), findsOne, reason: 'nothing held: an open shows it at once');
      expect(pager.moveNext(), isTrue);
      await tester.pump(const Duration(milliseconds: 17));
      await tester.pump(const Duration(milliseconds: 200));
      expect(pager.arrived?.bvid, 'BV2');
      expect(find.byType(PlayerLoading), findsNothing, reason: 'the picture alone, as the official app shows it');
      await tester.pump(StoryPagerTheme.quietLoading - const Duration(milliseconds: 100));
      expect(find.byType(PlayerLoading), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(PlayerLoading), findsOne, reason: 'a slow start shows it is under way');

      expect(pager.moveNext(), isTrue);
      await tester.pump(const Duration(milliseconds: 17));
      await tester.pump(const Duration(milliseconds: 200));
      expect(pager.arrived?.bvid, 'BV3');
      expect(find.byType(PlayerLoading), findsNothing, reason: 'the next landing waits from its own start');

      await show(tester, Presentation.vertical, storyPager: pager, failure: '播放失败');
      expect(find.byKey(const ValueKey('video-failure')), findsOne);
      await show(tester, Presentation.vertical, storyPager: pager, loading: true);
      expect(find.byType(PlayerLoading), findsNothing);

      pager.framed('BV3');
      await tester.pump();
      expect(find.byType(PlayerLoading), findsOne, reason: 'held no more, a load shows as ever');
    });

    testWidgets('the danmaku dim with the controls while the page moves, and come back as it lands', (tester) async {
      pager.feed = feed;
      await show(tester, Presentation.vertical, storyPager: pager);
      double dim() => tester
          .widget<Opacity>(find.ancestor(of: find.byType(DanmakuLayer), matching: find.byType(Opacity)).first)
          .opacity;
      final layer = tester.element(find.byType(DanmakuLayer));
      expect(dim(), 1);
      drag
        ..start()
        ..update(-100);
      await tester.pump();
      expect(dim(), VerticalCleanTheme.movingOpacity);
      expect(find.ancestor(of: find.byKey(const ValueKey('fake-video')), matching: find.byType(Opacity)), findsNothing,
          reason: 'the picture stays as it is');
      drag.end(0);
      await tester.pump(const Duration(milliseconds: 17));
      expect(drag.settling, isTrue);
      expect(dim(), VerticalCleanTheme.movingOpacity);
      await tester.pumpAndSettle();
      expect(dim(), 1);
      expect(identical(tester.element(find.byType(DanmakuLayer)), layer), isTrue, reason: 'they keep their state');
    });

    testWidgets("the neighbours' 发弹幕 fields follow the page's 弹", (tester) async {
      pager.feed = feed;
      session
        ..danmakuOn = false
        ..changed();
      await show(tester, Presentation.vertical, storyPager: pager);
      expect(tester.widget<VerticalChromePreview>(find.byType(VerticalChromePreview)).danmakuOn, isFalse);
      session
        ..danmakuOn = true
        ..changed();
      await tester.pump();
      expect(tester.widget<VerticalChromePreview>(find.byType(VerticalChromePreview)).danmakuOn, isTrue);
    });

    testWidgets('on Windows 下一个视频 and 上一个视频 are buttons too, which take no touches', (tester) async {
      final semantics = tester.ensureSemantics();
      pager.feed = feed;
      await show(tester, Presentation.vertical, storyPager: pager, moveTargets: true);
      final next = find.semantics.byLabel('下一个视频');
      final previous = find.semantics.byLabel('上一个视频');
      expect(next, findsOne);
      expect(next.evaluate().single.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(next.evaluate().single.getSemanticsData().flagsCollection.isButton, isTrue);

      tester.semantics.tap(previous);
      await tester.pump(const Duration(milliseconds: 200));
      expect(feed.moves, isEmpty, reason: 'nothing before the first video');
      tester.semantics.tap(next);
      await tester.pump(const Duration(milliseconds: 17));
      expect(drag.offset, lessThan(0), reason: 'the same settle as a swipe');
      await tester.pump(const Duration(milliseconds: 200));
      expect(feed.moves, [1]);
      tester.semantics.tap(previous);
      await tester.pump(const Duration(milliseconds: 17));
      await tester.pump(const Duration(milliseconds: 200));
      expect(feed.moves, [1, 0]);

      final targets = find.byKey(const ValueKey('story-move-targets'));
      final box = tester.getRect(find.descendant(of: targets, matching: find.byType(SizedBox)).first);
      expect(box.size, const Size.square(StoryPagerTheme.moveTarget));
      final hit = tester.hitTestOnBinding(box.center).path.map((entry) => entry.target).toList();
      expect(
        hit,
        isNot(contains(tester.renderObject(find.descendant(of: targets, matching: find.byType(SizedBox)).first))),
      );
      final gestures = find.descendant(of: find.byType(PlayerGestureLayer), matching: find.byType(Listener)).first;
      expect(hit, contains(tester.renderObject(gestures)), reason: 'the touch reaches the gesture layer under them');

      await show(tester, Presentation.vertical, storyPager: pager, moveTargets: false);
      expect(next, findsNothing, reason: "iOS: VoiceOver's custom actions are enough");
      await show(tester, Presentation.inline, storyPager: pager, moveTargets: true);
      expect(next, findsNothing, reason: 'only in 竖屏');
      semantics.dispose();
    });

    testWidgets('a video swiped to that fails to open can be swiped past; 重试 still answers a tap', (tester) async {
      pager.feed = feed;
      var retries = 0;
      await show(tester, Presentation.vertical, storyPager: pager, failure: '播放失败', onRetry: () => retries++);
      expect(find.byType(PlayerGestureLayer), findsNothing);
      final failure = find.byKey(const ValueKey('video-failure'));
      final rest = tester.getRect(failure);

      final gesture = await tester.startGesture(const Offset(220, 800));
      for (var i = 0; i < 20; i++) {
        await gesture.moveBy(const Offset(0, -30));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(drag.dragging, isTrue);
      expect(tester.getRect(failure).top, closeTo(rest.top + drag.offset, 0.01), reason: 'it moves with the page');
      expect(drag.offset, lessThan(-956 / 2));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(feed.moves, [1]);

      final back = await tester.startGesture(const Offset(220, 800));
      for (var i = 0; i < 20; i++) {
        await back.moveBy(const Offset(0, -30));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await back.cancel();
      await tester.pumpAndSettle();
      expect(feed.moves, [1], reason: 'a cancelled touch goes back');
      expect(drag.moving, isFalse);

      await tester.tap(find.byKey(const ValueKey('video-retry')));
      expect(retries, 1);
      expect(feed.moves, [1]);

      await show(tester, Presentation.inline, storyPager: pager, failure: '播放失败');
      expect(find.byKey(const ValueKey('video-failure-swipe')), findsNothing, reason: 'only in 竖屏');
    });
  });
}

/// A feed counting the moves past its end.
class _AskingFeed extends FakeStoryFeed {
  _AskingFeed(super.entries);

  var asks = 0;

  @override
  void wantMore() => asks++;
}
