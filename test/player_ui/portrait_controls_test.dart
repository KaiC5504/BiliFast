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
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player_session.dart';

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

  Future<void> mount(WidgetTester tester, {TextScaler textScaler = TextScaler.noScaling}) async {
    addTearDown(() {
      chrome.dispose();
      panels.dispose();
      orientation.dispose();
      session.dispose();
    });
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

  testWidgets('full screen on a vertical video goes to 竖屏', (tester) async {
    final rig = Rig();
    rig.session.isVertical = true;
    await rig.mount(tester);

    await tester.tap(find.byKey(const ValueKey('portrait-fullscreen')));
    expect(rig.orientation.presentation, Presentation.vertical);
  });

  testWidgets('竖屏 goes to 竖屏 whatever the video', (tester) async {
    final rig = Rig();
    await rig.mount(tester);

    await tester.tap(find.byKey(const ValueKey('portrait-vertical')));
    expect(rig.orientation.presentation, Presentation.vertical);
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
    final gesture = await tester.startGesture(bar.centerRight - const Offset(20, 0));
    await gesture.moveBy(const Offset(-5, 0));
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
