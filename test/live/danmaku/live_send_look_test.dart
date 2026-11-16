import 'dart:io';

import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/live/danmaku/live_recent_emotes.dart';
import 'package:bilifast/live/danmaku/live_send_input.dart';
import 'package:bilifast/live/room/live_overlays.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/look_alike.dart';
import '../../support/stand_in_fonts.dart';
import '../../video/mixed_lines.dart' show appTheme;
import 'live_send_support.dart';

// Its own file: the stand-ins replace Roboto and the Cupertino families for every later test in the isolate.

/// The inputs as KaiC's iPhone draws them, under the system font, against 226, 227 and 223 (px / 3). With
/// BILIFAST_SHOTS naming a folder outside the repo, the 3× shots are saved there for tools/screen_diff.py.
void main() {
  late FakeRoom room;
  late LiveOverlays overlays;

  setUp(() {
    room = FakeRoom(api: demoApi());
    overlays = LiveOverlays()..open(LiveOverlay.send);
    LiveRecentEmotes.use(LiveRecentEmotes.memory());
  });

  tearDown(() {
    room.dispose();
    overlays.dispose();
  });

  Future<void> show(WidgetTester tester, {bool landscape = false}) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    final harness = await liveHarness();
    BiliFonts.family = BiliFonts.system;
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester, landscape: landscape);
    tester.view.viewInsets = FakeViewPadding(bottom: (landscape ? 224 : 348) * 3);
    addTearDown(tester.view.resetViewInsets);
    EditableText.debugDeterministicCursor = true;
    addTearDown(() => EditableText.debugDeterministicCursor = false);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => RepaintBoundary(
          key: const ValueKey('shot'),
          child: AppScope(services: harness.services, child: child!),
        ),
        home: Scaffold(
          backgroundColor: const Color(0xFF0C0E1B),
          resizeToAvoidBottomInset: false,
          body: LiveSendInput(room: room, overlays: overlays, landscape: landscape),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('shot')), '$shots/$name.png');
  }

  Rect inkOf(WidgetTester tester, String text) => tester.getRect(find.text(text));

  testWidgets('226: the panel on the keyboard, 弹幕支持下～ 10.67 in, 发送 centred in its pill', (tester) async {
    await show(tester);
    await shoot(tester, '226-live-input-ours');
    expect(inkOf(tester, '弹幕支持下～').left, closeTo(22.67, 0.5));
    expect(inkOf(tester, '弹幕支持下～').center.dy, closeTo(546, 0.5));
    expect(inkOf(tester, '发送').center, const Offset(399, 546));
    // 醒目留言's words start 48.33 in on 226.
    expect(inkOf(tester, '醒目留言').left, closeTo(48.33, 0.5));
    expect(inkOf(tester, '醒目留言').center.dy, closeTo(504, 0.5));
  });

  testWidgets('227: the emote panel in the keyboard\'s place', (tester) async {
    await show(tester);
    await tester.tap(byKey('live-send-face'));
    await tester.pump();
    await tester.pump();
    await shoot(tester, '227-live-emote-panel-ours');
    expect(inkOf(tester, '全部表情').left, closeTo(16.33, 0.5));
    expect(inkOf(tester, '全部表情').center.dy, closeTo(612.5, 1));
  });

  testWidgets('223: the bar across the top of the keyboard', (tester) async {
    await show(tester, landscape: true);
    await shoot(tester, '223-live-input-ours');
    expect(inkOf(tester, '弹幕支持下～').left, closeTo(117, 0.5));
    expect(inkOf(tester, '发送').center, offsetMoreOrLessEquals(const Offset(821, 154)));
  });
}
