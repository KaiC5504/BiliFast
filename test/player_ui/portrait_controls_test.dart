import 'package:bili_core/api.dart' show Chapter;
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/player_ui/portrait_controls.dart';
import 'package:bilifast/player_ui/seek_bar.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/player_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player_session.dart';
import '../support/stand_in_fonts.dart';
import '../video/mixed_lines.dart' show appTheme;

final class Rig {
  final session = FakePlayerSession();
  final chrome = ChromeState();
  final panels = PanelController();
  final orientation = OrientationController();
  int backs = 0;

  late final ui = PlayerUi(
    session: session,
    chrome: chrome,
    panels: panels,
    orientation: orientation,
    device: NoDeviceControls(),
    onBack: () => backs++,
  );

  void _disposeAfter() => addTearDown(() {
    chrome.dispose();
    panels.dispose();
    orientation.dispose();
    session.dispose();
  });

  Future<void> mount(WidgetTester tester, {TextScaler textScaler = TextScaler.noScaling}) async {
    _disposeAfter();
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(width: 440, height: 247.5, child: PortraitControls(ui: ui)),
          ),
        ),
      ),
    );
  }

  /// On KaiC's phone under the system font's stand-ins, in the box the page gives the video's shape (17's 3:4 is
  /// 586.67 pt tall), under the island.
  Future<void> mountAsPhone(WidgetTester tester) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    BiliFonts.family = BiliFonts.system;
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    _disposeAfter();
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: Material(
          color: BiliColors.videoBackground,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 62,
                width: 440,
                height: inlinePlayerHeight(440, video: session.videoShape),
                child: PortraitControls(ui: ui),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double opacity(WidgetTester tester, String key) => tester.widget<AnimatedOpacity>(find.byKey(ValueKey(key))).opacity;

  String time(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('portrait-time'))).data!;

  Rect bar(WidgetTester tester) => tester.getRect(find.byKey(const ValueKey('portrait-bar')));
}

void main() {
  testWidgets('back calls the page and ⋮ opens the more panel', (tester) async {
    final rig = Rig();
    await rig.mount(tester);

    await tester.tap(find.byKey(const ValueKey('video-back')));
    expect(rig.backs, 1);

    await tester.tap(find.byKey(const ValueKey('portrait-more')));
    expect(rig.panels.value, PlayerPanel.more);
  });

  testWidgets('the controls press through accessibility too, as VoiceOver and the Windows test driver do',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final rig = Rig();
    await rig.mount(tester);

    tester.semantics.tap(find.semantics.byLabel('返回'));
    expect(rig.backs, 1);
    tester.semantics.tap(find.semantics.byLabel('更多'));
    expect(rig.panels.value, PlayerPanel.more);
    semantics.dispose();
  });

  testWidgets('a tap on a control starts the hide timer again', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    rig.chrome.autoHide = true;

    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byKey(const ValueKey('portrait-more')));
    await tester.pump(const Duration(seconds: 2));
    expect(rig.chrome.visible, isTrue);

    await tester.pump(const Duration(milliseconds: 1100));
    expect(rig.chrome.visible, isFalse);
  });

  testWidgets('play toggles through the session and its label follows the player', (tester) async {
    final semantics = tester.ensureSemantics();
    final rig = Rig();
    await rig.mount(tester);
    expect(find.bySemanticsLabel('播放'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('portrait-play')));
    expect(rig.session.calls, ['togglePlay']);

    rig.session.player.emit(const StatusChanged(PlayerStatus.playing));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('暂停'), findsOneWidget);
    expect(find.bySemanticsLabel('播放'), findsNothing);

    rig.session
      ..ended = true
      ..changed();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('播放'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('every button carries a label', (tester) async {
    final semantics = tester.ensureSemantics();
    final rig = Rig();
    await rig.mount(tester);
    for (final label in ['返回', '更多', '播放', '进度', '竖屏', '全屏']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
    semantics.dispose();
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('the 竖屏 badge keeps 15\'s size at text scale $scale', (tester) async {
      final rig = Rig();
      await rig.mount(tester, textScaler: TextScaler.linear(scale));
      final badge = tester.getSize(find.ancestor(of: find.text('竖屏'), matching: find.byType(Container)).first);
      expect(badge.height, BiliMetrics.badgeHeight);
      expect(badge.width, closeTo(21.7, 0.2));
    });
  }

  testWidgets('full screen turns a horizontal video sideways', (tester) async {
    final rig = Rig();
    await rig.mount(tester);

    await tester.tap(find.byKey(const ValueKey('portrait-fullscreen')));
    expect(rig.orientation.presentation, Presentation.landscape);
  });

  testWidgets('an upright video has no 全屏, only 竖屏, which goes to 竖屏; the row follows the shape once known', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final rig = Rig();
    await rig.mount(tester);
    expect(find.byKey(const ValueKey('portrait-fullscreen')), findsOneWidget);

    rig.session
      ..isVertical = true
      ..changed();
    await tester.pump();
    expect(find.byKey(const ValueKey('portrait-fullscreen')), findsNothing);
    expect(find.bySemanticsLabel('全屏'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('portrait-vertical')));
    expect(rig.orientation.presentation, Presentation.vertical);
    semantics.dispose();
  });

  testWidgets("an in-page open keeps an upright video's row until the next video's shape is in", (tester) async {
    final rig = Rig()..session.isVertical = true;
    await rig.mount(tester);
    Rect pill() => tester.getRect(find.ancestor(of: find.text('竖屏'), matching: find.byType(Container)).first);
    final upright = pill();
    expect(find.byKey(const ValueKey('portrait-fullscreen')), findsNothing);

    rig.session
      ..isVertical = false
      ..heldVertical = true
      ..changed();
    await tester.pump();
    expect(find.byKey(const ValueKey('portrait-fullscreen')), findsNothing);
    expect(pill(), upright, reason: 'the pill keeps its place by the corners');

    rig.session
      ..heldVertical = null
      ..changed();
    await tester.pump();
    expect(find.byKey(const ValueKey('portrait-fullscreen')), findsOneWidget, reason: 'the next one is wide');
    expect(pill(), isNot(upright));
  });

  testWidgets('竖屏 goes to 竖屏 whatever the video', (tester) async {
    final rig = Rig();
    await rig.mount(tester);

    await tester.tap(find.byKey(const ValueKey('portrait-vertical')));
    expect(rig.orientation.presentation, Presentation.vertical);
  });

  group('the bottom row on the phone (440 × 956, the system font)', () {
    Rect rectOf(WidgetTester tester, Finder finder) => tester.getRect(finder);
    Rect pill(WidgetTester tester) =>
        rectOf(tester, find.ancestor(of: find.text('竖屏'), matching: find.byType(Container)).first);
    Rect corners(WidgetTester tester) => rectOf(
      tester,
      find.descendant(
        of: find.byKey(const ValueKey('portrait-vertical')),
        matching: find.byWidgetPredicate((widget) => widget is CustomPaint && widget.painter is CornersPainter),
      ),
    );

    testWidgets('17: an upright video ends at 竖屏, where a wide one has 全屏, and the bar takes the room', (
      tester,
    ) async {
      final rig = Rig()
        ..session.isVertical = true
        ..session.videoShape = (width: 1080, height: 1440)
        ..session.duration.value = 31;
      await rig.mountAsPhone(tester);

      expect(find.byKey(const ValueKey('portrait-fullscreen')), findsNothing);
      // 17: the corners' ink 409.67-424.33 × 618-635.33 pt, the pill 412-434 × 604.67-616.67.
      expect(corners(tester).center.dx, closeTo(417, 0.01));
      expect(corners(tester).center.dy, closeTo(626.67, 0.01));
      expect(pill(tester).center.dx, closeTo(423, 0.01));
      expect(pill(tester).center.dy, closeTo(610.67, 0.01));
      expect(pill(tester).right, lessThanOrEqualTo(434.5));
      // 17: 00:00/00:31's ink ends at 384.33 pt, the bar at 306.33. The stand-in's time starts 1.3 pt further left
      // than 17's SF (its colons are narrower), and the bar ends 2.3 pt short with it.
      final time = rectOf(tester, find.byKey(const ValueKey('portrait-time')));
      expect(time.right, 385);
      expect(rig.bar(tester).right, time.left - BiliMetrics.chromeTimeLeading);
      expect(rig.bar(tester).right, closeTo(306.33, 2.5));
    });

    testWidgets('the bar an upright video gets is longer by 全屏 and its gap', (tester) async {
      final wide = Rig()..session.duration.value = 31;
      await wide.mountAsPhone(tester);
      final wideBar = wide.bar(tester);

      final upright = Rig()
        ..session.isVertical = true
        ..session.videoShape = (width: 1080, height: 1440)
        ..session.duration.value = 31;
      await upright.mountAsPhone(tester);
      expect(upright.bar(tester).left, wideBar.left);
      expect(
        upright.bar(tester).right - wideBar.right,
        closeTo(BiliMetrics.chromeButton + BiliMetrics.fullScreenGap, 0.01),
      );
    });

    testWidgets('03: a wide video keeps 竖屏 and 全屏 side by side', (tester) async {
      final rig = Rig()
        ..session.videoShape = (width: 1920, height: 1080)
        ..session.duration.value = 31;
      await rig.mountAsPhone(tester);

      final fullScreen = rectOf(tester, find.byKey(const ValueKey('portrait-fullscreen')));
      expect(fullScreen, Rect.fromLTRB(395, 265.5, 439, 309.5));
      expect(corners(tester).center, within(distance: 0.01, from: const Offset(371, 287.5)));
      expect(pill(tester).center.dx, closeTo(383, 0.01));
      expect(rectOf(tester, find.byKey(const ValueKey('portrait-time'))).right, 339);
      expect(rig.bar(tester).right, lessThan(270));
    });
  });

  testWidgets('hidden controls fade out, let touches through and leave the thin line', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    expect(rig.opacity(tester, 'portrait-controls'), 1);
    expect(rig.opacity(tester, 'portrait-hidden-line'), 0);

    rig.chrome.hide();
    await tester.pump();
    expect(rig.opacity(tester, 'portrait-controls'), 0);
    expect(rig.opacity(tester, 'portrait-hidden-line'), 1);
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.widget<AnimatedSlide>(find.byType(AnimatedSlide).first).offset,
      const Offset(0, -0.3),
      reason: 'the top row slides up as it goes',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('video-back')), warnIfMissed: false);
    expect(rig.backs, 0);

    rig.chrome.show();
    await tester.pumpAndSettle();
    expect(rig.opacity(tester, 'portrait-controls'), 1);
  });

  testWidgets('once the video ended only the thin line stays', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    rig.session
      ..ended = true
      ..changed();
    await tester.pumpAndSettle();
    expect(rig.opacity(tester, 'portrait-controls'), 0);
    expect(rig.opacity(tester, 'portrait-hidden-line'), 1);
  });

  testWidgets('dragging the bar scrubs through the session and commits where it lifts', (tester) async {
    final rig = Rig();
    rig.session.duration.value = 200;
    await rig.mount(tester);
    final bar = rig.bar(tester);

    final gesture = await tester.startGesture(bar.centerLeft + const Offset(20, 0));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    final scrubs = rig.session.calls.where((call) => call.startsWith('scrub')).toList();
    expect(scrubs, isNotEmpty);
    final aimed = rig.session.scrubbing.value!;
    expect(rig.time(tester), endsWith('/03:20'));
    expect(rig.time(tester), startsWith(_clock(aimed)));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(rig.session.calls.last, startsWith('commitSeek'));
    expect(rig.session.scrubbing.value, isNull);
  });

  testWidgets('before the duration is known the bar does nothing', (tester) async {
    final rig = Rig();
    await rig.mount(tester);

    await tester.drag(find.byKey(const ValueKey('portrait-bar')), const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(rig.session.calls.where((call) => call.startsWith('scrub') || call.startsWith('commitSeek')), isEmpty);
  });

  testWidgets('the bar carries the video\'s chapters', (tester) async {
    final rig = Rig();
    rig.session
      ..duration.value = 100
      ..chapters = const [Chapter(from: 0, to: 50, title: '开头'), Chapter(from: 50, to: 100, title: '后半')];
    await rig.mount(tester);
    expect(tester.widget<SeekBar>(find.byType(SeekBar)).chapters, rig.session.chapters);

    final bar = rig.bar(tester);
    final gesture = await tester.startGesture(bar.centerLeft + const Offset(20, 0));
    await gesture.moveBy(Offset(bar.width * 0.7, 0));
    await tester.pumpAndSettle();
    expect(find.text('后半'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('后半'), findsNothing);
  });
}

String _clock(double seconds) {
  final whole = seconds.toInt();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(whole ~/ 60)}:${two(whole % 60)}';
}
