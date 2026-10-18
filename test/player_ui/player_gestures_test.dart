import 'dart:async';

import 'package:bilifast/app/swipe_back_route.dart';
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/player_gestures.dart';
import 'package:bilifast/player_ui/player_hud.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player_session.dart';

/// Brightness and volume kept in memory, with every level the gestures set.
final class RecordingDevice implements DeviceControls {
  double brightnessLevel = 0.5;
  double volumeLevel = 0.5;
  final sets = <String>[];
  final hardware = StreamController<double>.broadcast(sync: true);

  @override
  Future<double> brightness() async => brightnessLevel;

  @override
  Future<void> setBrightness(double value) async {
    sets.add('brightness $value');
    brightnessLevel = value;
  }

  @override
  Future<double> volume() async => volumeLevel;

  @override
  Future<void> setVolume(double value) async {
    sets.add('volume $value');
    volumeLevel = value;
  }

  @override
  Stream<double> get hardwareVolume => hardware.stream;

  @override
  Future<void> enterFullScreen() async {}

  @override
  Future<void> leaveFullScreen() async {}
}

final class Rig {
  Rig() {
    session.duration.value = 600;
  }

  final session = FakePlayerSession();
  final chrome = ChromeState();
  final panels = PanelController();
  final orientation = OrientationController();
  final device = RecordingDevice();
  late final ui = PlayerUi(
    session: session,
    chrome: chrome,
    panels: panels,
    orientation: orientation,
    device: device,
    onBack: () {},
  );

  List<String> get calls => session.calls;

  Iterable<String> callsStarting(String prefix) => calls.where((call) => call.startsWith(prefix));

  Widget player({double? height}) => SizedBox(
    height: height,
    child: Stack(
      fit: StackFit.expand,
      children: [
        PlayerGestureLayer(ui: ui),
        PlayerHud(ui: ui),
      ],
    ),
  );

  /// The player across the top of the 800 × 600 test screen, 450 high, as on the page.
  Future<void> mountInline(WidgetTester tester) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(alignment: Alignment.topCenter, child: player(height: 450)),
    ),
  );

  /// The player filling the screen.
  Future<void> mountFullScreen(WidgetTester tester) {
    orientation.enterLandscape();
    return tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: player()));
  }

  Future<void> startAt(WidgetTester tester, double seconds) async {
    session.clock.jump(seconds);
    session.readout.refresh();
    await tester.pump();
  }

  void playing() => session.player.emit(const StatusChanged(PlayerStatus.playing));

  void dispose() {
    chrome.dispose();
    panels.dispose();
    orientation.dispose();
    unawaited(device.hardware.close());
    session.dispose();
  }
}

/// A thumb's speed: 1500 pt/s, as swipe back is tested.
Duration thumb(double distance) => Duration(milliseconds: (distance / 1.5).round());

/// Lets the single tap's window run out.
const _tapSettles = Duration(milliseconds: 300);

void main() {
  late Rig rig;

  setUp(() => rig = Rig());
  tearDown(() => rig.dispose());

  group('taps', () {
    testWidgets('a tap toggles the controls once the double-tap window has passed', (tester) async {
      await rig.mountInline(tester);
      await tester.tapAt(const Offset(400, 200));
      await tester.pump(const Duration(milliseconds: 200));
      expect(rig.chrome.visible, isTrue, reason: 'still inside the double-tap window');
      await tester.pump(const Duration(milliseconds: 60));
      expect(rig.chrome.visible, isFalse);

      await tester.tapAt(const Offset(400, 200));
      await tester.pump(_tapSettles);
      expect(rig.chrome.visible, isTrue);
      expect(rig.calls, isEmpty);
    });

    testWidgets('a double tap plays or pauses and shows the controls, without toggling them', (tester) async {
      rig.chrome.hide();
      await rig.mountInline(tester);
      await tester.tapAt(const Offset(400, 200));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.tapAt(const Offset(410, 205));
      expect(rig.calls, ['togglePlay']);
      expect(rig.chrome.visible, isTrue);
      await tester.pump(_tapSettles);
      expect(rig.chrome.visible, isTrue);
      expect(rig.calls, ['togglePlay']);
    });

    testWidgets('two taps far apart are two single taps', (tester) async {
      await rig.mountInline(tester);
      await tester.tapAt(const Offset(100, 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(const Offset(700, 400));
      expect(rig.chrome.visible, isFalse, reason: 'the first tap fired as the second landed');
      await tester.pump(_tapSettles);
      expect(rig.chrome.visible, isTrue);
      expect(rig.calls, isEmpty);
    });

    testWidgets('a second touch that drags leaves the first tap a single tap', (tester) async {
      await rig.mountInline(tester);
      await tester.tapAt(const Offset(400, 200));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.timedDragFrom(const Offset(400, 200), const Offset(150, 0), thumb(150));
      expect(rig.chrome.visible, isFalse);
      expect(rig.callsStarting('commitSeek'), hasLength(1));
      expect(rig.calls, isNot(contains('togglePlay')));
    });
  });

  group('hold', () {
    testWidgets('holding 0.35 s plays at 2× with 倍速中 until the finger lifts', (tester) async {
      rig.playing();
      await rig.mountInline(tester);
      final gesture = await tester.startGesture(const Offset(400, 200));
      await tester.pump(const Duration(milliseconds: 330));
      expect(rig.calls, isEmpty);
      await tester.pump(const Duration(milliseconds: 30));
      expect(rig.calls, ['speedUp true']);
      expect(rig.chrome.hud.value, isA<SpeedUpHud>());
      expect(rig.chrome.visible, isFalse);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('倍速中'), findsOneWidget);

      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(rig.callsStarting('scrub'), isEmpty, reason: 'a hold that wanders does not seek');

      await gesture.up();
      expect(rig.calls, ['speedUp true', 'speedUp false']);
      expect(rig.chrome.hud.value, isNull);
      await tester.pump();
      await tester.pump(_tapSettles);
      expect(rig.chrome.visible, isFalse, reason: 'the hold was not also a tap');
      expect(find.text('倍速中'), findsNothing);
    });

    testWidgets('a cancelled hold goes back to the chosen speed', (tester) async {
      rig.playing();
      await rig.mountInline(tester);
      final gesture = await tester.startGesture(const Offset(400, 200));
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.cancel();
      expect(rig.calls, ['speedUp true', 'speedUp false']);
      expect(rig.chrome.hud.value, isNull);
      await tester.pump(_tapSettles);
    });

    testWidgets('holding a paused video does nothing', (tester) async {
      await rig.mountInline(tester);
      final gesture = await tester.startGesture(const Offset(400, 200));
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.up();
      await tester.pump(_tapSettles);
      expect(rig.calls, isEmpty);
      expect(rig.chrome.hud.value, isNull);
      expect(rig.chrome.visible, isTrue);
    });
  });

  group('seek', () {
    testWidgets('a sideways drag at 1500 pt/s seeks 90 s per player width from where it started', (tester) async {
      await rig.mountInline(tester);
      await rig.startAt(tester, 100);
      await tester.timedDragFrom(const Offset(600, 200), const Offset(-400, 0), thumb(400));
      expect(rig.callsStarting('scrub'), isNotEmpty);
      expect(rig.calls.last, 'commitSeek 55.0');
      expect(rig.calls, isNot(contains('cancelScrub')));
      expect(rig.chrome.hud.value, isNull);
      expect(rig.chrome.visible, isTrue, reason: 'a seek is not a tap');
      await tester.pump(_tapSettles);
    });

    testWidgets('the HUD shows the target while dragging, and seeks clamp to the video', (tester) async {
      rig.session.duration.value = 30;
      await rig.mountInline(tester);
      final gesture = await tester.startGesture(const Offset(200, 200));
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump();
      expect(rig.calls.last, 'scrub 9.0');
      expect(rig.chrome.hud.value, const SeekHud(target: 9, duration: 30));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('00:09/00:30'), findsOneWidget);

      await gesture.moveBy(const Offset(500, 0));
      await tester.pump();
      expect(rig.calls.last, 'scrub 30.0');
      await gesture.up();
      expect(rig.calls.last, 'commitSeek 30.0');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('00:30/00:30'), findsNothing);
    });

    testWidgets('the drag is claimed past 10 pt, inside the 18 pt slop of taps and scrollers', (tester) async {
      await rig.mountInline(tester);
      final gesture = await tester.startGesture(const Offset(400, 200));
      await gesture.moveBy(const Offset(9, 0));
      await tester.pump();
      expect(rig.calls, isEmpty);
      await gesture.moveBy(const Offset(3, 0));
      await tester.pump();
      expect(rig.calls, hasLength(1));
      expect(double.parse(rig.calls.single.split(' ').last), closeTo(12 / 800 * 90, 1e-9));
      await gesture.up();
      await tester.pump(_tapSettles);
      expect(rig.chrome.visible, isTrue);
    });

    testWidgets('a short wobble is still a tap', (tester) async {
      await rig.mountInline(tester);
      final gesture = await tester.startGesture(const Offset(400, 200));
      await gesture.moveBy(const Offset(6, 5));
      await gesture.up();
      await tester.pump(_tapSettles);
      expect(rig.calls, isEmpty);
      expect(rig.chrome.visible, isFalse);
    });

    testWidgets('a finger resting mid-drag hints the target; a moving one does not', (tester) async {
      await rig.mountInline(tester);
      final gesture = await tester.startGesture(const Offset(200, 200));
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(20, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(rig.callsStarting('hint'), isEmpty);
      await gesture.moveBy(const Offset(1, 0));
      await tester.pump(const Duration(milliseconds: 160));
      expect(rig.callsStarting('hint'), ['hint 11.3625']);
      await gesture.up();
      expect(rig.calls.last, 'commitSeek 11.3625');
    });

    testWidgets('a cancelled drag cancels the scrub', (tester) async {
      await rig.mountInline(tester);
      final gesture = await tester.startGesture(const Offset(200, 200));
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump();
      await gesture.cancel();
      expect(rig.calls.last, 'cancelScrub');
      expect(rig.callsStarting('commitSeek'), isEmpty);
      expect(rig.chrome.hud.value, isNull);
    });

    testWidgets('the layer going away mid-drag cancels the scrub', (tester) async {
      await rig.mountInline(tester);
      final gesture = await tester.startGesture(const Offset(200, 200));
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      expect(rig.calls.last, 'cancelScrub');
      expect(rig.chrome.hud.value, isNull);
      await gesture.up();
    });

    testWidgets('nothing seeks before the duration is known', (tester) async {
      rig.session.duration.value = 0;
      await rig.mountInline(tester);
      await tester.timedDragFrom(const Offset(200, 200), const Offset(300, 0), thumb(300));
      expect(rig.calls, isEmpty);
      expect(rig.chrome.hud.value, isNull);
    });
  });

  group('inline', () {
    testWidgets('a vertical drag is left to the scroller under the player, with no levels', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ListView(
            controller: scroll,
            children: [rig.player(height: 450), const SizedBox(height: 1200)],
          ),
        ),
      );
      // Mostly down, with a small sideways wobble.
      await tester.timedDragFrom(const Offset(600, 300), const Offset(30, -300), thumb(300));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(200));
      expect(rig.calls, isEmpty);
      expect(rig.device.sets, isEmpty);
      expect(rig.chrome.hud.value, isNull);

      scroll.jumpTo(0);
      await tester.pump();
      await tester.timedDragFrom(const Offset(200, 300), const Offset(300, 0), thumb(300));
      expect(scroll.offset, 0);
      expect(rig.calls.last, 'commitSeek 33.75');
    });

    testWidgets('without a back swipe to leave room for, a drag from the left edge seeks', (tester) async {
      await rig.mountInline(tester);
      await tester.timedDragFrom(const Offset(5, 200), const Offset(300, 0), thumb(300));
      expect(rig.calls.last, 'commitSeek 33.75');
    });
  });

  group('over a real route', () {
    Future<void> pushVideoPage(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    SwipeBackPageRoute<void>(
                      builder: (_) => Scaffold(
                        body: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            rig.player(height: 450),
                            const Expanded(child: Text('简介')),
                          ],
                        ),
                      ),
                    ),
                  ),
                  child: const Text('首页'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('首页'));
      await tester.pumpAndSettle();
      expect(find.text('简介'), findsOneWidget);
    }

    testWidgets('an edge swipe on the player goes back', (tester) async {
      await pushVideoPage(tester);
      await tester.timedDragFrom(const Offset(5, 200), const Offset(300, 0), thumb(300));
      await tester.pumpAndSettle();
      expect(find.text('简介'), findsNothing);
      expect(find.text('首页'), findsOneWidget);
      expect(rig.callsStarting('scrub'), isEmpty);
    });

    testWidgets('a sideways drag in the middle of the player seeks and the page stays', (tester) async {
      await pushVideoPage(tester);
      await tester.timedDragFrom(const Offset(200, 200), const Offset(300, 0), thumb(300));
      await tester.pumpAndSettle();
      expect(find.text('简介'), findsOneWidget);
      expect(rig.calls.last, 'commitSeek 33.75');
    });

    testWidgets('just past the back swipe strip, the player seeks', (tester) async {
      await pushVideoPage(tester);
      await tester.timedDragFrom(const Offset(24, 200), const Offset(300, 0), thumb(300));
      await tester.pumpAndSettle();
      expect(find.text('简介'), findsOneWidget);
      expect(rig.calls.last, 'commitSeek 33.75');
    });
  });

  group('full screen', () {
    testWidgets('up on the left half raises the brightness, with its level in the HUD', (tester) async {
      await rig.mountFullScreen(tester);
      final gesture = await tester.startGesture(const Offset(200, 400));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0, -25), timeStamp: Duration(milliseconds: 16 * (i + 1)));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(rig.device.sets.last, 'brightness 0.75');
      expect(rig.chrome.hud.value, const LevelHud(LevelKind.brightness, 0.75));
      expect(rig.device.sets.where((set) => set.startsWith('volume')), isEmpty);
      await gesture.up();
      expect(rig.chrome.hud.value, isNull);
      expect(rig.calls, isEmpty);
      await tester.pump(_tapSettles);
    });

    testWidgets('down on the right half lowers the volume', (tester) async {
      await rig.mountFullScreen(tester);
      await tester.timedDragFrom(const Offset(600, 200), const Offset(0, 300), thumb(300));
      expect(rig.device.sets.last, 'volume 0.0');
      expect(rig.device.sets.where((set) => set.startsWith('brightness')), isEmpty);
      expect(rig.chrome.hud.value, isNull);
      await tester.pump(_tapSettles);
    });

    testWidgets('sideways still seeks in full screen', (tester) async {
      await rig.mountFullScreen(tester);
      await tester.timedDragFrom(const Offset(200, 300), const Offset(400, 0), thumb(400));
      expect(rig.calls.last, 'commitSeek 45.0');
      expect(rig.device.sets, isEmpty);
    });

    testWidgets('touches within 25 pt of the screen edges are left to the system', (tester) async {
      rig.playing();
      await rig.mountFullScreen(tester);
      for (final (start, offset) in [
        (const Offset(10, 300), const Offset(300, 0)),
        (const Offset(790, 300), const Offset(-300, 0)),
        (const Offset(400, 10), const Offset(0, 300)),
        (const Offset(400, 590), const Offset(0, -300)),
      ]) {
        await tester.timedDragFrom(start, offset, thumb(300));
        await tester.tapAt(start);
        final hold = await tester.startGesture(start);
        await tester.pump(const Duration(milliseconds: 400));
        await hold.up();
        await tester.pump(_tapSettles);
        expect(rig.calls, isEmpty, reason: 'from $start');
        expect(rig.device.sets, isEmpty, reason: 'from $start');
        expect(rig.chrome.visible, isTrue, reason: 'from $start');
      }

      await tester.timedDragFrom(const Offset(30, 300), const Offset(300, 0), thumb(300));
      expect(rig.calls.last, 'commitSeek 33.75');
    });

    testWidgets('the hardware volume buttons show the level for a second', (tester) async {
      await rig.mountFullScreen(tester);
      rig.device.hardware.add(0.3);
      expect(rig.chrome.hud.value, const LevelHud(LevelKind.volume, 0.3));
      await tester.pump(const Duration(milliseconds: 600));
      rig.device.hardware.add(0.4);
      await tester.pump(const Duration(milliseconds: 600));
      expect(rig.chrome.hud.value, const LevelHud(LevelKind.volume, 0.4), reason: 'each press restarts the second');
      await tester.pump(const Duration(milliseconds: 500));
      expect(rig.chrome.hud.value, isNull);
    });

    testWidgets('inline, the hardware volume buttons show nothing', (tester) async {
      await rig.mountInline(tester);
      rig.device.hardware.add(0.3);
      expect(rig.chrome.hud.value, isNull);
    });
  });
}
