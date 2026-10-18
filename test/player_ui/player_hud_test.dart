import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/player_hud.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player_session.dart';

/// Past the HUD's entrance (and the arrows' slide).
const _settled = Duration(milliseconds: 500);

void main() {
  late FakePlayerSession session;
  late ChromeState chrome;
  late PanelController panels;
  late OrientationController orientation;
  late PlayerUi ui;

  setUp(() {
    session = FakePlayerSession();
    chrome = ChromeState();
    panels = PanelController();
    orientation = OrientationController();
    ui = PlayerUi(
      session: session,
      chrome: chrome,
      panels: panels,
      orientation: orientation,
      device: NoDeviceControls(),
      onBack: () {},
    );
  });

  tearDown(() {
    chrome.dispose();
    panels.dispose();
    orientation.dispose();
    session.dispose();
  });

  /// The full-screen player of the official app's 25: 956 × 440.
  Future<void> mount(WidgetTester tester, {VoidCallback? onTapUnder}) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 956,
          height: 440,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(onTap: onTapUnder, child: const ColoredBox(color: BiliColors.videoBackground)),
              PlayerHud(ui: ui),
            ],
          ),
        ),
      ),
    ),
  );

  Rect player(WidgetTester tester) => tester.getRect(find.byType(PlayerHud));

  Finder pill(Finder content) =>
      find.ancestor(of: content, matching: find.byWidgetPredicate((widget) => widget is Container)).first;

  testWidgets('shows nothing without a gesture', (tester) async {
    await mount(tester);
    expect(find.byType(Container), findsNothing);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('倍速中 sits as in 25: a 92 × 44 pill 10 pt below the top, centred', (tester) async {
    tester.view.physicalSize = const Size(956, 440);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await mount(tester);
    chrome.showHud(const SpeedUpHud());
    await tester.pump();
    await tester.pump(_settled);
    final rect = tester.getRect(pill(find.text('倍速中')));
    expect(rect.height, BiliMetrics.hudHeight);
    expect(rect.width, greaterThanOrEqualTo(BiliMetrics.hudMinWidth));
    expect(rect.top - player(tester).top, BiliMetrics.hudTop);
    expect(rect.center.dx, closeTo(player(tester).center.dx, 0.01));
    final decoration = tester.widget<Container>(pill(find.text('倍速中'))).decoration! as BoxDecoration;
    expect(decoration.color, BiliColors.hudFill);
    final label = tester.widget<Text>(find.text('倍速中'));
    expect(label.style?.fontSize, BiliMetrics.hudFont);
    expect(label.style?.color, BiliColors.onVideo);
  });

  testWidgets('the seek label is target / duration in the middle, and follows the drag', (tester) async {
    await mount(tester);
    chrome.showHud(const SeekHud(target: 83, duration: 600));
    await tester.pump();
    await tester.pump(_settled);
    expect(find.text('01:23/10:00'), findsOneWidget);
    expect(tester.getCenter(pill(find.text('01:23/10:00'))), player(tester).center);

    chrome.showHud(const SeekHud(target: 3725, duration: 7200));
    await tester.pump();
    expect(find.text('1:02:05/2:00:00'), findsOneWidget, reason: 'updated in place, no second entrance');
    expect(find.text('01:23/10:00'), findsNothing);
  });

  testWidgets('brightness and volume show their icon, level and value', (tester) async {
    final semantics = tester.ensureSemantics();
    await mount(tester);
    chrome.showHud(const LevelHud(LevelKind.brightness, 0.8));
    await tester.pump();
    await tester.pump(_settled);
    expect(find.byIcon(Icons.brightness_high_rounded), findsOneWidget);
    expect(find.bySemanticsLabel('亮度'), findsOneWidget);
    expect(tester.getSemantics(find.bySemanticsLabel('亮度')).value, '80%');
    expect(tester.getCenter(pill(find.byIcon(Icons.brightness_high_rounded))), player(tester).center);

    chrome.showHud(const LevelHud(LevelKind.volume, 0));
    await tester.pump();
    await tester.pump(_settled);
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
    expect(find.byIcon(Icons.brightness_high_rounded), findsNothing);

    chrome.showHud(const LevelHud(LevelKind.volume, 0.7));
    await tester.pump();
    await tester.pump(_settled);
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    expect(tester.getSemantics(find.bySemanticsLabel('音量')).value, '70%');
    semantics.dispose();
  });

  testWidgets('fades in and out rather than popping', (tester) async {
    await mount(tester);
    chrome.showHud(const SpeedUpHud());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final entering = tester.widget<FadeTransition>(
      find.ancestor(of: find.text('倍速中'), matching: find.byType(FadeTransition)).first,
    );
    expect(entering.opacity.value, inExclusiveRange(0, 1));

    await tester.pump(_settled);
    chrome.showHud(null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('倍速中'), findsOneWidget, reason: 'still fading out');
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('倍速中'), findsNothing);
  });

  testWidgets('takes no touches', (tester) async {
    var taps = 0;
    await mount(tester, onTapUnder: () => taps++);
    chrome.showHud(const SeekHud(target: 10, duration: 60));
    await tester.pump(_settled);
    await tester.tapAt(player(tester).center);
    expect(taps, 1);
  });
}
