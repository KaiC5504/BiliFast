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
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/video_player_area.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';
import '../support/fake_mask_feed.dart';
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
    ValueListenable<bool>? waiting,
    String? failure,
    Widget? cover,
    Size size = const Size(440, 956),
    ValueListenable<bool>? turning,
    ValueListenable<double?>? verticalTurn,
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
          onRetry: () {},
          turning: turning,
          verticalTurn: verticalTurn,
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
}
