import 'package:bili_core/danmaku.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/danmaku/danmaku_layer.dart';
import 'package:bilifast/danmaku/danmaku_scene.dart';
import 'package:bilifast/danmaku/danmaku_sprites.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player/playback_clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

DisplayDanmaku item(String text, int ms, {int mode = 1, int color = 0xFFFFFF, bool own = false}) => DisplayDanmaku(
  elem: DanmakuElem(progressMs: ms, mode: mode, color: color, content: text),
  text: text,
  isOwn: own,
);

/// Stands in for the player and the controller that feeds the clock.
final class Rig {
  final time = ManualClock(10000);
  late final clock = PlaybackClock(clock: time.clock);
  final wake = ValueNotifier(0);
  final sprites = DanmakuSprites();
  final timeline = DanmakuTimeline();

  static const size = Size(400, 225);

  Future<void> mount(WidgetTester tester, {bool enabled = true, DanmakuTimeline? timeline}) => tester.pumpWidget(
    Center(
      child: SizedBox.fromSize(
        size: size,
        child: DanmakuLayer(
          clock: clock,
          timeline: timeline ?? this.timeline,
          wake: wake,
          enabled: enabled,
          sprites: sprites,
        ),
      ),
    ),
  );

  DanmakuLayerState state(WidgetTester tester) => tester.state<DanmakuLayerState>(find.byType(DanmakuLayer));

  List<DanmakuOnScreen> visible(WidgetTester tester) => state(tester).scene.visible;

  DanmakuOnScreen? shown(WidgetTester tester, String text) {
    for (final shown in visible(tester)) {
      if (shown.text == text) return shown;
    }
    return null;
  }

  void play(double at) {
    clock.handle(const StatusChanged(PlayerStatus.playing));
    clock.handle(PositionChanged(seconds: at, hostMs: time.clock.nowMs(), rate: 1));
    wake.value++;
  }

  void pause() {
    clock.handle(const StatusChanged(PlayerStatus.paused));
    wake.value++;
  }

  /// [seconds] of 120 Hz frames, with a position reading every frame as a player would send about every 100 ms.
  Future<void> run(WidgetTester tester, double seconds) async {
    const frameMs = 1000 / 120;
    final frames = (seconds * 120).round();
    for (var i = 0; i < frames; i++) {
      time.advance(frameMs);
      if (clock.running) {
        clock.handle(PositionChanged(seconds: clock.seconds, hostMs: time.clock.nowMs(), rate: 1));
      }
      await tester.pump(const Duration(microseconds: 8333));
    }
  }
}

void main() {
  testWidgets('shows each danmaku as the playhead reaches it and scrolls it right to left', (tester) async {
    final rig = Rig();
    rig.timeline.add([item('第一条', 1000), item('第二条', 2000)]);
    await rig.mount(tester);
    rig.play(0);
    await rig.run(tester, 0.9);
    expect(rig.visible(tester), isEmpty);

    await rig.run(tester, 0.2);
    final entered = rig.shown(tester, '第一条')!;
    expect(entered.kind, LaneKind.scroll);
    expect(entered.rect.left, lessThan(Rig.size.width));
    expect(entered.rect.left, greaterThan(Rig.size.width - 40));

    await rig.run(tester, 1);
    final later = rig.shown(tester, '第一条')!;
    // 7 s to cross the width plus its own: about (400 + w) / 7 points a second.
    final speed = (Rig.size.width + later.rect.width) / 7;
    expect(entered.rect.left - later.rect.left, closeTo(speed, 3));
    expect(rig.shown(tester, '第二条'), isNotNull);

    await rig.run(tester, 6);
    expect(rig.shown(tester, '第一条'), isNull, reason: 'gone once it has left on the left');
    expect(rig.shown(tester, '第二条'), isNotNull);
  });

  testWidgets('top and bottom danmaku sit centred at the top and the bottom for 4 s', (tester) async {
    final rig = Rig();
    rig.timeline.add([item('顶部', 500, mode: 5), item('底部', 500, mode: 4)]);
    await rig.mount(tester);
    rig.play(0);
    await rig.run(tester, 1);

    final top = rig.shown(tester, '顶部')!;
    final bottom = rig.shown(tester, '底部')!;
    expect(top.kind, LaneKind.top);
    expect(top.rect.center.dx, closeTo(Rig.size.width / 2, 0.01));
    expect(top.rect.top, lessThan(10));
    expect(bottom.kind, LaneKind.bottom);
    expect(bottom.rect.center.dx, closeTo(Rig.size.width / 2, 0.01));
    expect(bottom.rect.bottom, greaterThan(Rig.size.height - 10));

    await rig.run(tester, 2);
    expect(rig.shown(tester, '顶部')!.rect, top.rect, reason: 'static danmaku do not move');

    await rig.run(tester, 1.6);
    expect(rig.visible(tester), isEmpty);
  });

  testWidgets('a jump clears the screen and lays out what the new position would show', (tester) async {
    final rig = Rig();
    rig.timeline.add([item('开头', 1000), item('后面', 30000)]);
    await rig.mount(tester);
    rig.play(0);
    await rig.run(tester, 1.5);
    expect(rig.shown(tester, '开头'), isNotNull);

    rig.clock.jump(31);
    rig.wake.value++;
    await rig.run(tester, 0.05);
    expect(rig.shown(tester, '开头'), isNull);
    final caught = rig.shown(tester, '后面')!;
    // Placed mid-flight: a second into its 7 s crossing, not entering at the right edge.
    expect(caught.rect.left, lessThan(Rig.size.width - 40));

    rig.clock.jump(0.5);
    rig.wake.value++;
    await rig.run(tester, 0.05);
    expect(rig.visible(tester), isEmpty);
  });

  testWidgets('a jump while paused clears the screen at once', (tester) async {
    final rig = Rig();
    rig.timeline.add([item('开头', 1000)]);
    await rig.mount(tester);
    rig.play(0);
    await rig.run(tester, 1.5);
    rig.pause();
    await rig.run(tester, 0.1);
    expect(rig.shown(tester, '开头'), isNotNull);

    rig.clock.jump(60);
    rig.wake.value++;
    await tester.pump();
    expect(rig.visible(tester), isEmpty);
  });

  testWidgets('pausing freezes the danmaku and stops the ticker; playing moves them on', (tester) async {
    final rig = Rig();
    rig.timeline.add([item('暂停', 1000)]);
    await rig.mount(tester);
    rig.play(0);
    await rig.run(tester, 1.5);
    rig.pause();
    await rig.run(tester, 0.05);
    final frozen = rig.shown(tester, '暂停')!.rect;
    expect(rig.state(tester).ticking, isFalse);

    await rig.run(tester, 2);
    expect(rig.shown(tester, '暂停')!.rect, frozen);
    expect(tester.binding.hasScheduledFrame, isFalse);

    rig.play(rig.clock.seconds);
    await rig.run(tester, 0.5);
    expect(rig.state(tester).ticking, isTrue);
    expect(rig.shown(tester, '暂停')!.rect.left, lessThan(frozen.left - 20));
  });

  testWidgets('lays out each danmaku once however many frames it is drawn in', (tester) async {
    final rig = Rig();
    rig.timeline.add([for (var i = 0; i < 12; i++) item('弹幕 $i', 1000 + i * 400)]);
    await rig.mount(tester);
    rig.play(0);
    await rig.run(tester, 5.5);
    expect(rig.visible(tester), hasLength(12));
    await rig.run(tester, 2);
    expect(rig.sprites.layouts, 12);
  });

  testWidgets('repeated text is laid out once', (tester) async {
    final rig = Rig();
    rig.timeline.add([for (var i = 0; i < 6; i++) item('哈哈哈', 1000 + i * 300)]);
    await rig.mount(tester);
    rig.play(0);
    await rig.run(tester, 3);
    expect(rig.visible(tester), hasLength(6));
    expect(rig.sprites.layouts, 1);
  });

  testWidgets('switched off, it shows nothing and stops ticking', (tester) async {
    final rig = Rig();
    rig.timeline.add([item('开关', 1000)]);
    await rig.mount(tester);
    rig.play(0);
    await rig.run(tester, 1.5);
    expect(rig.shown(tester, '开关'), isNotNull);

    await rig.mount(tester, enabled: false);
    expect(rig.visible(tester), isEmpty);
    expect(rig.state(tester).ticking, isFalse);
    await rig.run(tester, 0.1);
    expect(tester.binding.hasScheduledFrame, isFalse);

    await rig.mount(tester);
    await rig.run(tester, 0.05);
    expect(rig.state(tester).ticking, isTrue);
    expect(rig.shown(tester, '开关'), isNotNull, reason: 'laid out again where it would be');
  });

  testWidgets('without a timeline nothing ticks', (tester) async {
    final rig = Rig();
    await tester.pumpWidget(
      Center(
        child: SizedBox.fromSize(
          size: Rig.size,
          child: DanmakuLayer(clock: rig.clock, timeline: null, wake: rig.wake),
        ),
      ),
    );
    rig.play(0);
    await tester.pump();
    expect(rig.state(tester).ticking, isFalse);
  });

  test('sprites: own danmaku get a wider box, and dark text still gets a sprite', () {
    final sprites = DanmakuSprites();
    final plain = sprites.of(item('同样', 0), pointSize: 17);
    final own = sprites.of(item('同样', 0, own: true), pointSize: 17);
    final dark = sprites.of(item('同样', 0, color: 0x000000), pointSize: 17);
    expect(own.size.width, plain.size.width + 8);
    expect(dark.size, plain.size);
    expect(sprites.layouts, 3);
    expect(sprites.of(item('同样', 0), pointSize: 17), same(plain));
    expect(sprites.layouts, 3);
  });
}
