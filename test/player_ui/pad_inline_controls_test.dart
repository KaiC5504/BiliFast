import 'package:bili_core/api.dart' show Chapter;
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/pad/pad_inline_controls.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/player_session.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player_session.dart';

/// 03's player: the left column, 16:9.
const _box = Size(756.5, 425.5);

const _chapters = [
  Chapter(from: 0, to: 30, title: '开场'),
  Chapter(from: 30, to: 140, title: '寻找好位置'),
  Chapter(from: 140, to: 254, title: '队长出发'),
];

final class PadRig {
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

  Future<void> mount(WidgetTester tester, {Size box = _box}) async {
    tester.view
      ..physicalSize = const Size(1194, 834)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() {
      chrome.dispose();
      panels.dispose();
      orientation.dispose();
      session.dispose();
    });
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1194, 834)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Overlay(
            key: ObjectKey(this),
            initialEntries: [
              OverlayEntry(
                builder: (_) => Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox.fromSize(size: box, child: PadInlineControls(ui: ui)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Rect rect(WidgetTester tester, String key) => tester.getRect(find.byKey(ValueKey(key)));

  double opacity(WidgetTester tester, String key) => tester.widget<AnimatedOpacity>(find.byKey(ValueKey(key))).opacity;
}

void main() {
  testWidgets('back leaves the page, ⋮ opens 更多, 倍速 opens the speeds, 全屏 enters full screen', (tester) async {
    final rig = PadRig();
    await rig.mount(tester);

    await tester.tap(find.byKey(const ValueKey('video-back')));
    expect(rig.backs, 1);
    await tester.tap(find.byKey(const ValueKey('pad-inline-more')));
    expect(rig.panels.value, PlayerPanel.more);
    await tester.tap(find.byKey(const ValueKey('pad-inline-speed')));
    expect(rig.panels.value, PlayerPanel.speed);
    await tester.tap(find.byKey(const ValueKey('pad-inline-fullscreen')));
    expect(rig.orientation.presentation, Presentation.landscape);
    await tester.tap(find.byKey(const ValueKey('pad-inline-play')));
    expect(rig.session.calls, ['togglePlay']);
  });

  testWidgets('every control presses through accessibility, as VoiceOver and the Windows driver do', (tester) async {
    final semantics = tester.ensureSemantics();
    final rig = PadRig();
    rig.session.episodes = const [
      Episode(bvid: 'BV1', cid: 1, title: 'P1', current: false),
      Episode(bvid: 'BV1', cid: 2, title: 'P2', current: true),
    ];
    await rig.mount(tester);

    for (final label in ['返回', '小窗播放', '投屏', '更多', '上一集', '播放', '进度', '倍速', '全屏']) {
      expect(find.semantics.byLabel(label), findsOne, reason: label);
    }
    tester.semantics.tap(find.semantics.byLabel('返回'));
    tester.semantics.tap(find.semantics.byLabel('小窗播放'));
    tester.semantics.tap(find.semantics.byLabel('上一集'));
    tester.semantics.tap(find.semantics.byLabel('倍速'));
    await tester.pump();
    expect(rig.backs, 1);
    expect(rig.session.calls, ['startPictureInPicture', 'playEpisode BV1 1']);
    expect(rig.panels.value, PlayerPanel.speed);
    semantics.dispose();
  });

  testWidgets('小窗 starts picture in picture and toasts a failure; without it, it is half white and only keeps the '
      'controls up', (tester) async {
    final rig = PadRig()..session.failure = '小窗播放启动失败';
    await rig.mount(tester);
    await tester.tap(find.byKey(const ValueKey('pad-inline-float')));
    await tester.pump();
    expect(rig.session.calls, ['startPictureInPicture']);
    expect(find.text('小窗播放启动失败'), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    final off = PadRig()..session.pictureInPictureSupported = false;
    await off.mount(tester);
    off.chrome.autoHide = true;
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byKey(const ValueKey('pad-inline-float')));
    await tester.pump(const Duration(seconds: 2));
    expect(off.session.calls, isEmpty);
    expect(off.chrome.visible, isTrue, reason: 'the tap started the hide timer again');
    expect(
      tester.widget<Opacity>(find.descendant(of: find.byKey(const ValueKey('pad-inline-float')), matching: find.byType(Opacity))).opacity,
      PadInlineControlsTheme.previousOffOpacity,
    );
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('投屏 says it isn\'t open yet', (tester) async {
    final rig = PadRig();
    await rig.mount(tester);
    await tester.tap(find.byKey(const ValueKey('pad-inline-cast')));
    await tester.pump();
    expect(find.text('暂未开放'), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('⏮ plays the part before; with none before it is half white and plays nothing', (tester) async {
    final rig = PadRig();
    await rig.mount(tester);
    Finder dimmed() => find.descendant(of: find.byKey(const ValueKey('pad-inline-previous')), matching: find.byType(Opacity));
    expect(dimmed(), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pad-inline-previous')));
    expect(rig.session.calls, isEmpty);

    rig.session
      ..episodes = const [
        Episode(bvid: 'BV1', cid: 1, title: 'P1', current: true),
        Episode(bvid: 'BV1', cid: 2, title: 'P2', current: false),
      ]
      ..changed();
    await tester.pump();
    expect(dimmed(), findsOneWidget, reason: 'the first part has nothing before it');

    rig.session
      ..episodes = const [
        Episode(bvid: 'BV1', cid: 1, title: 'P1', current: false),
        Episode(bvid: 'BV1', cid: 2, title: 'P2', current: true),
      ]
      ..changed();
    await tester.pump();
    expect(dimmed(), findsNothing);
    await tester.tap(find.byKey(const ValueKey('pad-inline-previous')));
    expect(rig.session.calls, ['playEpisode BV1 1']);
  });

  testWidgets('the iPad has no 竖屏: an upright video keeps 全屏, which enters the ordinary full screen', (tester) async {
    final semantics = tester.ensureSemantics();
    final rig = PadRig()
      ..session.isVertical = true
      ..session.videoShape = (width: 1080, height: 1920);
    await rig.mount(tester);
    expect(find.text('竖屏'), findsNothing);
    expect(find.semantics.byLabel('竖屏'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('pad-inline-fullscreen')));
    expect(rig.orientation.presentation, Presentation.landscape);
    semantics.dispose();
  });

  testWidgets('倍速 shows the chosen rate', (tester) async {
    final rig = PadRig()..session.rate = 1.5;
    await rig.mount(tester);
    expect(find.text('1.5X'), findsOneWidget);
  });

  testWidgets('03: the rows sit where 03 has them, right-aligned controls following the player\'s width', (
    tester,
  ) async {
    for (final width in [_box.width, 834.0]) {
      final rig = PadRig()..session.duration.value = 254;
      final box = Size(width, width * 9 / 16);
      await rig.mount(tester, box: box);

      expect(rig.rect(tester, 'video-back').center, within(distance: 0.01, from: const Offset(29, 29)));
      expect(rig.rect(tester, 'pad-inline-more').center, within(distance: 0.01, from: Offset(width - 29, 29)));
      expect(rig.rect(tester, 'pad-inline-cast').center.dx, closeTo(width - 87, 0.01));
      expect(rig.rect(tester, 'pad-inline-float').center.dx, closeTo(width - 144.25, 0.01));
      final row = box.height - 29;
      expect(rig.rect(tester, 'pad-inline-previous').center, within(distance: 0.01, from: Offset(29, row)));
      expect(rig.rect(tester, 'pad-inline-play').center, within(distance: 0.01, from: Offset(86.5, row)));
      expect(rig.rect(tester, 'pad-inline-speed').center, within(distance: 0.01, from: Offset(width - 87, row)));
      expect(rig.rect(tester, 'pad-inline-fullscreen').center, within(distance: 0.01, from: Offset(width - 29, row)));
      final bar = rig.rect(tester, 'pad-inline-bar');
      expect(bar.left, 107);
      expect(bar.center.dy, row);
      final time = rig.rect(tester, 'pad-inline-time');
      expect(time.right, width - 142);
      expect(time.left - bar.right, closeTo(17, 0.01));
    }
  });

  testWidgets('章节 · <chapter> › names the chapter playing, and gives way while the bar is held', (tester) async {
    final rig = PadRig()
      ..session.duration.value = 254
      ..session.chapters = _chapters;
    await rig.mount(tester);
    expect(find.text('章节 · 开场'), findsOneWidget);

    const at = PositionChanged(seconds: 60, hostMs: 0, rate: 1);
    rig.session.clock.handle(at);
    rig.session.player.emit(at);
    await tester.pump();
    expect(find.text('章节 · 寻找好位置'), findsOneWidget);
    final line = tester.getRect(find.byKey(const ValueKey('pad-inline-chapter')));
    expect(line.left, 21);
    expect(line.center.dy, closeTo(_box.height - 65.75, 0.5));

    rig.session.scrub(200);
    await tester.pump();
    expect(find.byKey(const ValueKey('pad-inline-chapter')), findsNothing);
  });

  testWidgets('without chapters there is no chapter line and no strip', (tester) async {
    final rig = PadRig()..session.duration.value = 254;
    await rig.mount(tester);
    expect(find.byKey(const ValueKey('pad-inline-chapter')), findsNothing);
    rig.chrome.hide();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pad-chapter-strip')), findsNothing);
  });

  testWidgets('06: hidden, the chapters run along the bottom, each centred on its stretch', (tester) async {
    final rig = PadRig()
      ..session.duration.value = 254
      ..session.chapters = _chapters;
    await rig.mount(tester, box: const Size(834, 834 * 9 / 16));
    expect(rig.opacity(tester, 'pad-inline-hidden'), 0);

    rig.chrome.hide();
    await tester.pumpAndSettle();
    expect(rig.opacity(tester, 'pad-inline-controls'), 0);
    expect(rig.opacity(tester, 'pad-inline-hidden'), 1);
    final strip = find.byKey(const ValueKey('pad-chapter-strip'));
    final second = tester.getRect(find.descendant(of: strip, matching: find.text('寻找好位置')));
    expect(second.center.dx, closeTo(834 * (30 + 140) / 2 / 254, 0.5));
    expect(second.center.dy, closeTo(834 * 9 / 16 - 10.67, 0.5));

    await tester.tap(find.byKey(const ValueKey('video-back')), warnIfMissed: false);
    expect(rig.backs, 0, reason: 'hidden controls take no touches');
  });

  testWidgets('a tap on a control starts the hide timer again', (tester) async {
    final rig = PadRig();
    await rig.mount(tester);
    rig.chrome.autoHide = true;

    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byKey(const ValueKey('pad-inline-more')));
    await tester.pump(const Duration(seconds: 2));
    expect(rig.chrome.visible, isTrue);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(rig.chrome.visible, isFalse);
  });

  testWidgets('dragging the bar scrubs and commits where it lifts', (tester) async {
    final rig = PadRig()..session.duration.value = 254;
    await rig.mount(tester);
    final bar = rig.rect(tester, 'pad-inline-bar');

    final gesture = await tester.startGesture(bar.centerLeft + const Offset(20, 0));
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    expect(rig.session.calls.where((call) => call.startsWith('scrub')), isNotEmpty);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(rig.session.calls.last, startsWith('commitSeek'));
  });

  testWidgets('once the video ended the controls are gone', (tester) async {
    final rig = PadRig();
    await rig.mount(tester);
    rig.session
      ..ended = true
      ..changed();
    await tester.pumpAndSettle();
    expect(rig.opacity(tester, 'pad-inline-controls'), 0);
  });
}
