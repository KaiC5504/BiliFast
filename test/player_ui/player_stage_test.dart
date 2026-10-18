import 'package:bili_core/danmaku.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/danmaku/danmaku_layer.dart';
import 'package:bilifast/playback/overlay_stats.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player/playback_clock.dart';
import 'package:bilifast/player_ui/player_stage.dart';
import 'package:bilifast/player_ui/stats_overlay.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player.dart';

/// The stage with a fake player, and the controller's one job here: feeding the clock the player's events.
final class Rig {
  Rig() {
    player.events.listen(clock.handle);
  }

  final player = FakePlayer();
  final time = ManualClock(10000);
  late final clock = PlaybackClock(clock: time.clock);
  final stats = ValueNotifier(const OverlayStats(mode: PlaybackMode.btr));
  final duration = ValueNotifier<double>(120);
  final seeks = <double>[];
  final precise = <bool>[];
  final hints = <double?>[];

  void seek(double seconds, {required bool precise}) {
    seeks.add(seconds);
    this.precise.add(precise);
  }

  Future<void> mount(WidgetTester tester, {bool showStats = false, DanmakuTimeline? danmaku}) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 400,
          height: 225,
          child: PlayerStage(
            player: player,
            clock: clock,
            stats: stats,
            showStats: showStats,
            duration: duration,
            danmaku: danmaku,
            onSeek: seek,
            onHint: hints.add,
          ),
        ),
      ),
    ),
  );

  void status(PlayerStatus status) => player.emit(StatusChanged(status));

  void position(double seconds) =>
      player.emit(PositionChanged(seconds: seconds, hostMs: time.clock.nowMs(), rate: 1));

  Rect stage(WidgetTester tester) => tester.getRect(find.byType(PlayerStage));

  /// A spot on the video away from the controls.
  Offset video(WidgetTester tester) => stage(tester).topLeft + const Offset(200, 60);

  double controlsOpacity(WidgetTester tester) =>
      tester.widget<AnimatedOpacity>(find.byKey(const ValueKey('player-controls'))).opacity;

  String timeLabel(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('player-time'))).data!;

  Iterable<String> seekCalls() => player.calls.where((call) => call.startsWith('seek'));
}

/// A single tap fires once the double tap's 300 ms have passed.
const _tapSettles = Duration(milliseconds: 350);

void main() {
  testWidgets('the play button plays, and pauses once the player says it plays', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    final button = find.byKey(const ValueKey('player-play'));
    expect(find.bySemanticsLabel('播放'), findsOneWidget);

    await tester.tap(button);
    expect(rig.player.calls, ['play']);

    rig.status(PlayerStatus.playing);
    await tester.pump();
    expect(find.bySemanticsLabel('暂停'), findsOneWidget);
    await tester.tap(button);
    expect(rig.player.calls, ['play', 'pause']);
  });

  testWidgets('the play button replays from the start once the video ended', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    rig.status(PlayerStatus.ended);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('player-play')));
    expect(rig.player.calls, ['seek 0.0 precise', 'play']);
  });

  testWidgets('a drag on the bar follows the finger and seeks once, to a keyframe, on release', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    rig.status(PlayerStatus.playing);
    rig.position(5);
    await tester.pump();
    expect(rig.timeLabel(tester), '00:05/02:00');

    final bar = tester.getRect(find.byKey(const ValueKey('player-bar')));
    final travel = bar.width - BiliMetrics.thumbWidth;
    Offset at(double seconds) => Offset(bar.left + BiliMetrics.thumbWidth / 2 + travel * seconds / 120, bar.center.dy);

    final finger = await tester.startGesture(at(10));
    await tester.pump();
    await finger.moveTo(at(30));
    await tester.pump();
    expect(rig.timeLabel(tester), '00:30/02:00');
    await finger.moveTo(at(60));
    await tester.pump();
    expect(rig.timeLabel(tester), '01:00/02:00');
    expect(rig.seekCalls(), isEmpty, reason: 'nothing seeks until the finger lifts');

    await finger.up();
    await tester.pump();
    final seek = rig.seekCalls().single.split(' ');
    expect(double.parse(seek[1]), closeTo(60, 0.01));
    expect(seek, hasLength(2), reason: 'not precise: the player starts at a keyframe');
    expect(rig.seeks.single, closeTo(60, 0.01));
    expect(rig.precise.single, isFalse);
    expect(rig.clock.seconds, closeTo(60, 0.01));
    expect(rig.timeLabel(tester), '01:00/02:00');
    expect(rig.hints, isEmpty, reason: 'the finger never rested');
  });

  testWidgets('after a keyframe seek the clock takes the spot the player landed on', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    rig.status(PlayerStatus.playing);
    rig.position(5);
    await tester.pump();
    final bar = tester.getRect(find.byKey(const ValueKey('player-bar')));
    final travel = bar.width - BiliMetrics.thumbWidth;
    await tester.tapAt(Offset(bar.left + BiliMetrics.thumbWidth / 2 + travel / 2, bar.center.dy));
    await tester.pump();
    expect(rig.clock.seconds, closeTo(60, 0.01));
    // The keyframe before 60 s is at 56.5 s, further than a precise seek's 1.5 s.
    rig.position(56.5);
    await tester.pump();
    expect(rig.clock.seconds, closeTo(56.5, 0.01));
    expect(rig.timeLabel(tester), '00:56/02:00');
  });

  testWidgets('a finger resting on the bar for 150 ms hints where it rests, once per spot', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    final bar = tester.getRect(find.byKey(const ValueKey('player-bar')));
    final travel = bar.width - BiliMetrics.thumbWidth;
    Offset at(double seconds) => Offset(bar.left + BiliMetrics.thumbWidth / 2 + travel * seconds / 120, bar.center.dy);

    final finger = await tester.startGesture(at(10));
    await finger.moveTo(at(30));
    await tester.pump(const Duration(milliseconds: 100));
    await finger.moveTo(at(90));
    await tester.pump(const Duration(milliseconds: 100));
    expect(rig.hints, isEmpty, reason: 'the finger has not stayed anywhere for 150 ms');
    await tester.pump(const Duration(milliseconds: 60));
    expect(rig.hints.single, closeTo(90, 0.01));

    // A twitch smaller than the slop is still resting there.
    await finger.moveBy(const Offset(1, 0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(rig.hints, hasLength(1));

    await finger.moveTo(at(45));
    await tester.pump(const Duration(milliseconds: 200));
    expect(rig.hints.last, closeTo(45, 0.01));
    await finger.up();
    await tester.pump();
    expect(rig.hints, hasLength(2), reason: 'the seek takes the hint over; nothing cancels it');
    expect(rig.seeks.single, closeTo(45, 0.01));
  });

  testWidgets('a drag that turns into a scroll after a hint cancels the hint', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    final bar = tester.getRect(find.byKey(const ValueKey('player-bar')));
    final finger = await tester.startGesture(bar.center);
    await tester.pump(const Duration(milliseconds: 200));
    expect(rig.hints, hasLength(1), reason: 'a finger held still on the bar is resting too');
    await finger.cancel();
    await tester.pump();
    expect(rig.hints.last, isNull);
    expect(rig.seekCalls(), isEmpty);
  });

  testWidgets('a tap on the bar seeks there', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    final bar = tester.getRect(find.byKey(const ValueKey('player-bar')));
    final travel = bar.width - BiliMetrics.thumbWidth;
    await tester.tapAt(Offset(bar.left + BiliMetrics.thumbWidth / 2 + travel / 4, bar.center.dy));
    await tester.pump();
    expect(double.parse(rig.seekCalls().single.split(' ')[1]), closeTo(30, 0.01));
    expect(rig.seeks.single, closeTo(30, 0.01));
    expect(rig.precise.single, isFalse, reason: 'any seek on the bar starts at a keyframe');
  });

  testWidgets('a page scroll that starts on the bar scrolls, seeks nothing and lets go of the target', (tester) async {
    final rig = Rig();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ListView(
          children: [
            SizedBox(
              height: 225,
              child: PlayerStage(
                player: rig.player,
                clock: rig.clock,
                stats: rig.stats,
                showStats: false,
                duration: rig.duration,
                onSeek: rig.seek,
                onHint: rig.hints.add,
              ),
            ),
            const SizedBox(height: 2000),
          ],
        ),
      ),
    );
    final bar = tester.getRect(find.byKey(const ValueKey('player-bar')));
    await tester.timedDragFrom(bar.center, const Offset(0, -150), const Duration(milliseconds: 100));
    await tester.pump();
    expect(rig.seekCalls(), isEmpty);
    expect(tester.getRect(find.byType(PlayerStage)).top, lessThan(-100));
    expect(rig.timeLabel(tester), '00:00/02:00');
  });

  testWidgets('before the duration is known the bar does not seek', (tester) async {
    final rig = Rig()..duration.value = 0;
    await rig.mount(tester);
    final bar = tester.getRect(find.byKey(const ValueKey('player-bar')));
    await tester.timedDragFrom(
      bar.centerLeft + const Offset(20, 0),
      const Offset(150, 0),
      const Duration(milliseconds: 200),
    );
    await tester.pump();
    expect(rig.seekCalls(), isEmpty);
  });

  testWidgets('a tap on the video hides the controls, and the next one shows them', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    expect(rig.controlsOpacity(tester), 1);

    await tester.tapAt(rig.video(tester));
    await tester.pump(_tapSettles);
    expect(rig.controlsOpacity(tester), 0);
    expect(rig.player.calls, isEmpty);

    await tester.tapAt(rig.video(tester));
    await tester.pump(_tapSettles);
    expect(rig.controlsOpacity(tester), 1);
  });

  testWidgets('hidden controls let a tap through to the video', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    await tester.tapAt(rig.video(tester));
    await tester.pump(_tapSettles);
    expect(rig.controlsOpacity(tester), 0);

    await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('player-play'))));
    await tester.pump(_tapSettles);
    expect(rig.player.calls, isEmpty);
    expect(rig.controlsOpacity(tester), 1);
  });

  testWidgets('a double tap toggles play and leaves the controls showing', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    await tester.tapAt(rig.video(tester));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(rig.video(tester));
    await tester.pump(_tapSettles);
    expect(rig.player.calls, ['play']);
    expect(rig.controlsOpacity(tester), 1);

    rig.status(PlayerStatus.playing);
    await tester.pump();
    await tester.tapAt(rig.video(tester));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(rig.video(tester));
    await tester.pump(_tapSettles);
    expect(rig.player.calls, ['play', 'pause']);
  });

  testWidgets('while playing the controls hide after 3 s without a touch', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    rig.status(PlayerStatus.playing);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2900));
    expect(rig.controlsOpacity(tester), 1);
    await tester.pump(const Duration(milliseconds: 200));
    expect(rig.controlsOpacity(tester), 0);

    await tester.tapAt(rig.video(tester));
    await tester.pump(_tapSettles);
    expect(rig.controlsOpacity(tester), 1);
    await tester.pump(const Duration(seconds: 3));
    expect(rig.controlsOpacity(tester), 0);
  });

  testWidgets('while paused the controls stay', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    rig.status(PlayerStatus.playing);
    await tester.pump(const Duration(seconds: 1));
    rig.status(PlayerStatus.paused);
    await tester.pump(const Duration(seconds: 5));
    expect(rig.controlsOpacity(tester), 1);
  });

  testWidgets('the controls stay while the bar is held', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    rig.status(PlayerStatus.playing);
    await tester.pump();
    final bar = tester.getRect(find.byKey(const ValueKey('player-bar')));
    final finger = await tester.startGesture(bar.center);
    await finger.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(seconds: 4));
    expect(rig.controlsOpacity(tester), 1);
    await finger.up();
    await tester.pump(const Duration(seconds: 3, milliseconds: 100));
    expect(rig.controlsOpacity(tester), 0);
  });

  testWidgets('the time follows the playhead between position readings', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    rig.status(PlayerStatus.playing);
    rig.position(64.2);
    await tester.pump();
    expect(rig.timeLabel(tester), '01:04/02:00');
    rig.time.advance(1000);
    rig.position(65.2);
    await tester.pump();
    expect(rig.timeLabel(tester), '01:05/02:00');
    rig.duration.value = 3725;
    await tester.pump();
    expect(rig.timeLabel(tester), '01:05/1:02:05');
  });

  testWidgets('a stage kept for the next video reads 0 once the clock and the duration are reset', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    rig.status(PlayerStatus.playing);
    rig.position(45);
    await tester.pump();
    expect(rig.timeLabel(tester), '00:45/02:00');
    rig.clock.clear();
    rig.duration.value = 0;
    await tester.pump();
    expect(rig.timeLabel(tester), '00:00/00:00');
  });

  testWidgets('the stats overlay shows only when asked', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    expect(find.byType(StatsOverlay), findsNothing);
    await rig.mount(tester, showStats: true);
    expect(find.text('模式 BTR'), findsOneWidget);
    rig.stats.value = const OverlayStats(mode: PlaybackMode.btr, stalls: 3);
    await tester.pump();
    expect(find.text('卡顿 3 次'), findsOneWidget);
  });

  testWidgets('danmaku start with playback and clear when the bar seeks while paused', (tester) async {
    final rig = Rig();
    final timeline = DanmakuTimeline()
      ..add([
        DisplayDanmaku(elem: const DanmakuElem(progressMs: 500, content: '前面'), text: '前面', isOwn: false),
      ]);
    await rig.mount(tester, danmaku: timeline);
    final layer = tester.state<DanmakuLayerState>(find.byType(DanmakuLayer));
    rig.status(PlayerStatus.playing);
    rig.position(0);
    for (var i = 0; i < 12; i++) {
      rig.time.advance(100);
      rig.position(rig.clock.seconds);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(layer.scene.visible.map((shown) => shown.text), ['前面']);

    rig.status(PlayerStatus.paused);
    await tester.pump();
    await tester.pump();
    expect(layer.ticking, isFalse);

    final bar = tester.getRect(find.byKey(const ValueKey('player-bar')));
    await tester.timedDragFrom(bar.center, const Offset(60, 0), const Duration(milliseconds: 200));
    await tester.pump();
    await tester.pump();
    expect(layer.scene.visible, isEmpty);
  });

  testWidgets('the video sits under everything and is built once', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    final video = tester.widget(find.byKey(const ValueKey('fake-video')));
    await tester.tapAt(rig.video(tester));
    await tester.pump(_tapSettles);
    expect(tester.widget(find.byKey(const ValueKey('fake-video'))), same(video));
  });
}
