import 'package:bili_core/api.dart' show VideoPage, VideoView;
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/speed_lock.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'player_gestures_test.dart' show Rig;

/// 竖屏's hold dragged down to lock the 2× (182, 183, 186), on the 800 × 600 test screen with no safe areas: the band is
/// the bottom 51 pt.
void main() {
  late Rig rig;

  setUp(() {
    rig = Rig()..playing();
    rig.session.video = VideoView(
      bvid: 'BV1',
      aid: 1,
      title: '',
      pages: [VideoPage(cid: 1, page: 1, part: '', duration: 60)],
    );
  });
  tearDown(() => rig.dispose());

  const hold = Duration(milliseconds: 400);
  const onBand = Offset(400, 580);

  SpeedLockPhase phase() => rig.speedLock.value;

  Future<TestGesture> holdDown(WidgetTester tester) async {
    await rig.mountVertical(tester);
    final gesture = await tester.startGesture(const Offset(400, 300));
    await tester.pump(hold);
    return gesture;
  }

  Future<void> lock(WidgetTester tester) async {
    final gesture = await holdDown(tester);
    await gesture.moveTo(onBand);
    await tester.pump();
    await gesture.up();
    await tester.pump();
  }

  test('the band reaches from just under the progress line to the bottom', () {
    expect(SpeedLock.bandHeight(const EdgeInsets.only(bottom: 34)), 84, reason: '182 and 183: from 872 pt down');
    expect(SpeedLock.bandHeight(EdgeInsets.zero), BiliMetrics.chromeButton + SpeedLockTheme.bandOverRow);
  });

  testWidgets('holding plays at 2× with 倍速中 and the hint under the progress line', (tester) async {
    final gesture = await holdDown(tester);
    expect(rig.calls, ['speedUp true']);
    expect(phase(), SpeedLockPhase.holding);
    expect(rig.chrome.hud.value, isA<SpeedUpHud>());
    expect(find.text('拖动到此处锁定倍速'), findsOneWidget);
    expect(tester.getRect(find.byKey(const ValueKey('speed-lock-hint'))).top, 600 - SpeedLock.bandHeight(EdgeInsets.zero));
    await gesture.up();
    await tester.pump();
  });

  testWidgets('dragged down onto the band it arms; dragged off it goes back to the hint', (tester) async {
    final gesture = await holdDown(tester);
    await gesture.moveTo(onBand);
    await tester.pump();
    expect(phase(), SpeedLockPhase.armed);
    expect(find.text('松手锁定倍速'), findsOneWidget);
    expect(find.text('拖动到此处锁定倍速'), findsNothing);
    expect(rig.callsStarting('scrub'), isEmpty, reason: 'the hold owns the finger');
    expect(rig.storyDrag.events, isEmpty);

    await gesture.moveTo(const Offset(400, 520));
    await tester.pump();
    expect(phase(), SpeedLockPhase.holding);
    expect(find.text('拖动到此处锁定倍速'), findsOneWidget);
    await gesture.up();
    await tester.pump();
  });

  testWidgets('let go on the band, the 2× stays with the locked pill in 倍速中’s place', (tester) async {
    await lock(tester);
    expect(phase(), SpeedLockPhase.locked);
    expect(rig.calls, ['speedUp true'], reason: 'the speed stays');
    expect(rig.session.speedingUp, isTrue);
    expect(rig.chrome.hud.value, isNull, reason: '倍速中 gives way to the pill');
    expect(find.text('锁定倍速中'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('松手锁定倍速'), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    expect(rig.calls, ['speedUp true'], reason: 'the lift was not also a tap');
  });

  testWidgets('取消 unlocks and goes back to 1×', (tester) async {
    await lock(tester);
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(phase(), SpeedLockPhase.off);
    expect(rig.calls, ['speedUp true', 'speedUp false']);
    expect(find.text('锁定倍速中'), findsNothing);
  });

  testWidgets('取消 answers an accessibility press, so VoiceOver and the test driver can unlock', (tester) async {
    final semantics = tester.ensureSemantics();
    await lock(tester);
    tester.semantics.tap(find.semantics.byLabel('取消锁定倍速'));
    await tester.pump();
    expect(phase(), SpeedLockPhase.off);
    expect(rig.calls.last, 'speedUp false');
    semantics.dispose();
  });

  testWidgets('a tap on the pill outside 取消 neither unlocks nor pauses', (tester) async {
    await lock(tester);
    await tester.tap(find.text('锁定倍速中'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(phase(), SpeedLockPhase.locked);
    expect(rig.calls, ['speedUp true']);
  });

  testWidgets('let go anywhere else, the hold ends as before', (tester) async {
    final gesture = await holdDown(tester);
    await gesture.moveTo(const Offset(400, 500));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(phase(), SpeedLockPhase.off);
    expect(rig.calls, ['speedUp true', 'speedUp false']);
    expect(find.text('拖动到此处锁定倍速'), findsNothing);
  });

  testWidgets('a hold cancelled while armed does not lock', (tester) async {
    final gesture = await holdDown(tester);
    await gesture.moveTo(onBand);
    await tester.pump();
    await gesture.cancel();
    await tester.pump();
    expect(phase(), SpeedLockPhase.off);
    expect(rig.calls, ['speedUp true', 'speedUp false']);
  });

  testWidgets('another video opening ends the lock', (tester) async {
    await lock(tester);
    rig.session
      ..part = VideoPage(cid: 2, page: 1, part: '', duration: 60)
      ..changed();
    await tester.pump();
    expect(phase(), SpeedLockPhase.off);
    expect(rig.calls, ['speedUp true', 'speedUp false']);
    expect(find.text('锁定倍速中'), findsNothing);
  });

  testWidgets('the same video notifying keeps it', (tester) async {
    await lock(tester);
    rig.session.changed();
    await tester.pump();
    expect(phase(), SpeedLockPhase.locked);
  });

  testWidgets('leaving 竖屏 ends the lock', (tester) async {
    await lock(tester);
    rig.orientation.exitToInline();
    await tester.pump();
    expect(phase(), SpeedLockPhase.off);
    expect(rig.calls, ['speedUp true', 'speedUp false']);
    expect(find.text('锁定倍速中'), findsNothing);
  });

  testWidgets('leaving 竖屏 mid-hold drops the hint and the hold ends at the lift', (tester) async {
    final gesture = await holdDown(tester);
    rig.orientation.exitToInline();
    await tester.pump();
    expect(phase(), SpeedLockPhase.off);
    expect(rig.calls, ['speedUp true']);
    await gesture.up();
    await tester.pump();
    expect(rig.calls, ['speedUp true', 'speedUp false']);
  });

  testWidgets('while locked, another hold changes nothing', (tester) async {
    await lock(tester);
    final gesture = await tester.startGesture(const Offset(400, 300));
    await tester.pump(hold);
    await gesture.up();
    await tester.pump();
    expect(phase(), SpeedLockPhase.locked);
    expect(rig.calls, ['speedUp true']);
  });

  testWidgets('landscape and the small player hold as before, with no hint', (tester) async {
    await rig.mountFullScreen(tester);
    final gesture = await tester.startGesture(const Offset(400, 300));
    await tester.pump(hold);
    await gesture.moveTo(onBand);
    await tester.pump();
    expect(phase(), SpeedLockPhase.off);
    expect(find.text('拖动到此处锁定倍速'), findsNothing);
    await gesture.up();
    await tester.pump();
    expect(rig.calls, ['speedUp true', 'speedUp false']);
  });

  testWidgets('竖屏’s 倍速中 is 36 pt high right under the top row', (tester) async {
    final gesture = await holdDown(tester);
    await tester.pump(const Duration(milliseconds: 500));
    final pill = tester.getRect(
      find.ancestor(of: find.byKey(const ValueKey('hud-speed-pill')), matching: find.byType(Container)).first,
    );
    expect(pill.top, BiliMetrics.chromeButton, reason: 'no top inset on the test screen');
    expect(pill.height, SpeedLockTheme.pillHeight);
    await gesture.up();
    await tester.pump();
  });
}
