import 'package:bili_core/api.dart';
import 'package:bili_core/danmaku.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/danmaku/block_rule_store.dart';
import 'package:bilifast/danmaku/danmaku_layer.dart';
import 'package:bilifast/danmaku/danmaku_scene.dart';
import 'package:bilifast/danmaku/danmaku_session.dart';
import 'package:bilifast/danmaku/danmaku_settings.dart';
import 'package:bilifast/danmaku/danmaku_settings_store.dart';
import 'package:bilifast/danmaku/danmaku_sprites.dart';
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/playback/danmaku_feed.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player/playback_clock.dart';
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/video_player_area.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';
import '../support/fake_player_session.dart';

DisplayDanmaku item(String text, int ms, {int mode = 1}) => DisplayDanmaku(
  elem: DanmakuElem(progressMs: ms, mode: mode, content: text),
  text: text,
  isOwn: false,
);

/// The layer in full screen, fed by a 弹幕设置 store, with a clock the test drives at 120 Hz.
final class Rig {
  final time = ManualClock(10000);
  late final clock = PlaybackClock(clock: time.clock);
  final wake = ValueNotifier(0);
  final sprites = DanmakuSprites();
  final timeline = DanmakuTimeline();
  final store = DanmakuSettingsStore.memory();

  static const size = Size(956, 440);

  Future<void> mount(WidgetTester tester) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      Center(
        child: SizedBox.fromSize(
          size: size,
          child: DanmakuLayer(
            clock: clock,
            timeline: timeline,
            wake: wake,
            sprites: sprites,
            settings: store,
            fullScreen: true,
          ),
        ),
      ),
    );
  }

  DanmakuLayerState state(WidgetTester tester) => tester.state<DanmakuLayerState>(find.byType(DanmakuLayer));

  List<DanmakuOnScreen> visible(WidgetTester tester) => state(tester).scene.visible;

  DanmakuOnScreen shown(WidgetTester tester, String text) => visible(tester).firstWhere((shown) => shown.text == text);

  Map<String, Rect> rects(WidgetTester tester) => {for (final shown in visible(tester)) shown.text: shown.rect};

  void play(double at) {
    clock.handle(const StatusChanged(PlayerStatus.playing));
    clock.handle(PositionChanged(seconds: at, hostMs: time.clock.nowMs(), rate: 1));
    wake.value++;
  }

  void pause() {
    clock.handle(const StatusChanged(PlayerStatus.paused));
    wake.value++;
  }

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

  /// A busy stretch: two a second for 10 s, a top one every 2 s.
  void fill() => timeline.add([
    for (var i = 0; i < 20; i++) item('滚动弹幕第$i条', 500 + i * 500),
    for (var i = 0; i < 5; i++) item('顶部$i', 700 + i * 2000, mode: 5),
  ]);
}

void main() {
  test('display() hands the store\'s values to the layer, sized for the presentation', () {
    const settings = DanmakuSettings(area: 0.25, opacity: 0.6, scale: 1.5, speed: 4);
    expect(
      settings.display(fullScreen: true),
      const DanmakuOptions(area: 0.25, opacity: 0.6, scale: 1.5, scrollDuration: 4, fullScreen: true),
    );
    expect(settings.display(fullScreen: false).fullScreen, isFalse);
  });

  testWidgets('the layer follows the store, and nothing rebuilds per frame or for a change but 不透明度', (
    tester,
  ) async {
    final rig = Rig()..fill();
    await rig.mount(tester);
    rig.play(0);
    await rig.run(tester, 0.1);
    Finder inLayer(Type type) => find.descendant(of: find.byType(DanmakuLayer), matching: find.byType(type));
    Widget painter() => tester.widget(inLayer(CustomPaint));
    final first = painter();
    await rig.run(tester, 2);
    expect(rig.visible(tester), isNotEmpty);
    expect(painter(), same(first), reason: 'frames only repaint');

    rig.store.update(rig.store.value.copyWith(speed: 4, area: 1, scale: 1.2));
    await rig.run(tester, 0.5);
    expect(rig.state(tester).options, rig.store.value.display(fullScreen: true));
    expect(painter(), same(first), reason: 'the scene takes these on its next step');

    rig.store.update(rig.store.value.copyWith(opacity: 0.4));
    await tester.pump();
    expect(painter(), same(first), reason: 'only the Opacity above it rebuilds');
    expect(tester.widget<Opacity>(inLayer(Opacity)).opacity, 0.4);
  });

  testWidgets('不透明度 fades what is flying without laying anything out again', (tester) async {
    final rig = Rig()..fill();
    await rig.mount(tester);
    rig.play(0);
    await rig.run(tester, 3);
    rig.pause();
    await rig.run(tester, 0.05);
    final before = rig.rects(tester);
    final layouts = rig.sprites.layouts;
    final opacity = tester.renderObject<RenderOpacity>(
      find.descendant(of: find.byType(DanmakuLayer), matching: find.byType(Opacity)),
    );
    final picture = opacity.debugLayer!.firstChild;
    expect(picture, isA<PictureLayer>());

    rig.store.update(rig.store.value.copyWith(opacity: 0.3));
    await rig.run(tester, 0.1);
    expect(rig.rects(tester), before);
    expect(rig.sprites.layouts, layouts);
    expect(opacity.opacity, 0.3);
    expect((opacity.debugLayer! as OpacityLayer).alpha, (0.3 * 255).round());
    expect(opacity.debugLayer!.firstChild, same(picture), reason: 'not repainted');
  });

  testWidgets('弹幕速度 changes the pace of what is flying from where it is, without a jump', (tester) async {
    final rig = Rig()..timeline.add([item('飞行中', 1000), item('后来的', 3500)]);
    await rig.mount(tester);
    rig.play(0);
    await rig.run(tester, 2.5);
    final before = rig.shown(tester, '飞行中').rect;
    final width = before.width;
    // 适中: 7 s to cross 956 + w.
    expect(Rig.size.width - before.left, closeTo(1.5 * (Rig.size.width + width) / 7, 2));

    rig.store.update(rig.store.value.copyWith(speed: 4));
    // The frame that reads the change still ends at the old pace; from it on, 极快's 4 s. Re-placing it at the new
    // pace would jump it about 160 pt.
    await rig.run(tester, 2 / 120);
    final next = rig.shown(tester, '飞行中').rect;
    expect(before.left - next.left, closeTo((Rig.size.width + width) * (1 / 7 + 1 / 4) / 120, 0.5));
    expect(next.top, before.top);

    await rig.run(tester, 0.5);
    expect(next.left - rig.shown(tester, '飞行中').rect.left, closeTo(0.5 * (Rig.size.width + width) / 4, 3));
    // Its crossing ends 1.5 / 7 + x / 4 = 1, x ≈ 3.14 s after the change, rather than the 5.5 left at 适中.
    await rig.run(tester, 2.5);
    expect(rig.visible(tester).map((shown) => shown.text), contains('飞行中'));
    await rig.run(tester, 0.8);
    expect(rig.visible(tester).map((shown) => shown.text), isNot(contains('飞行中')));
    final later = rig.shown(tester, '后来的').rect;
    expect(Rig.size.width - later.left, closeTo(2.8167 * (Rig.size.width + later.width) / 4, 3));
  });

  testWidgets('显示区域 re-lays at once into the top share, keeping what stays in its lane', (tester) async {
    final rig = Rig()..fill();
    await rig.mount(tester);
    rig.play(0);
    await rig.run(tester, 6);
    rig.pause();
    await rig.run(tester, 0.05);
    final laneHeight = rig.state(tester).scene.laneHeight;
    final before = rig.rects(tester);
    expect(before.values.any((rect) => rect.top >= laneHeight), isTrue);

    // 10% of 440 is one lane of 22 pt text.
    rig.store.update(rig.store.value.copyWith(area: 0.1));
    await tester.pump();
    await tester.pump();
    final narrow = rig.rects(tester);
    expect(narrow, isNotEmpty);
    expect(narrow.values.every((rect) => rect.bottom <= Rig.size.height * 0.1), isTrue);
    for (final entry in narrow.entries) {
      expect(entry.value, before[entry.key], reason: '${entry.key} stays where it was');
    }
    expect(rig.state(tester).ticking, isFalse, reason: 'paused, the ticker sleeps again once re-laid');

    rig.store.update(rig.store.value.copyWith(area: 0.5));
    await tester.pump();
    await tester.pump();
    expect(rig.rects(tester), before, reason: 'back to the same lanes: everything where it was');
  });

  testWidgets('字体大小 re-lays what is flying at the new size at once, mid-flight', (tester) async {
    final rig = Rig()..fill();
    await rig.mount(tester);
    rig.play(0);
    await rig.run(tester, 4);
    final before = rig.rects(tester);

    rig.store.update(rig.store.value.copyWith(scale: 1.5));
    await rig.run(tester, 1 / 120);
    final bigger = rig.rects(tester);
    expect(bigger, isNotEmpty, reason: 'not cleared');
    final common = before.keys.where(bigger.containsKey).toList();
    expect(common, isNotEmpty);
    for (final text in common) {
      expect(bigger[text]!.height, greaterThan(before[text]!.height * 1.3));
      if (text.startsWith('滚动')) {
        // Still as far through its crossing, now with the wider text.
        final progressBefore = (Rig.size.width - before[text]!.left) / (Rig.size.width + before[text]!.width);
        final progressAfter = (Rig.size.width - bigger[text]!.left) / (Rig.size.width + bigger[text]!.width);
        expect(progressAfter, closeTo(progressBefore, 0.01));
      }
    }
    expect(rig.state(tester).scene.laneHeight, closeTo(22 * 1.5 * BiliMetrics.danmakuLaneHeight, 2));
  });

  group('a bigger 字体大小 keeps everything that was showing', () {
    /// Every lane busy: mixed lengths every [every] ms, with top and bottom ones among them.
    void crowd(Rig rig, int every) => rig.timeline.add([
      for (var i = 0; i < 10000 ~/ every; i++)
        item('${'密集' * (1 + i % 5)}$i', 250 + i * every, mode: i % 9 == 4 ? 5 : (i % 9 == 7 ? 4 : 1)),
    ]);

    Future<void> grow(WidgetTester tester, Rig rig, {
      required double area,
      required double scale,
      required int every,
    }) async {
      rig.store.update(rig.store.value.copyWith(area: area));
      crowd(rig, every);
      await rig.mount(tester);
      rig.play(0);
      await rig.run(tester, 6);
      rig.pause();
      await rig.run(tester, 0.05);
      final before = rig.visible(tester).map((shown) => shown.text).toSet();
      expect(before.length, greaterThan(15));

      rig.store.update(rig.store.value.copyWith(scale: scale));
      await rig.run(tester, 0.5);
      final after = rig.visible(tester);
      expect(after.map((shown) => shown.text).toSet(), before);
      expect(after, hasLength(before.length));
      for (final shown in after) {
        expect(shown.rect.top >= 0 && shown.rect.bottom <= Rig.size.height, isTrue, reason: '$shown is on screen');
      }
      expect(rig.state(tester).ticking, isFalse, reason: 'paused, the ticker sleeps again once re-laid');
    }

    testWidgets('paused, at 1.25 the ones without a lane fly past the area', (tester) async {
      final rig = Rig();
      await grow(tester, rig, area: 0.5, scale: 1.25, every: 200);
      final area = Rig.size.height * 0.5;
      final lanes = (area / rig.state(tester).scene.laneHeight).floor();
      final past = rig.visible(tester).where((shown) => shown.kind == LaneKind.scroll && shown.rect.bottom > area);
      expect(past, isNotEmpty, reason: 'more were showing than $lanes lanes hold');
      for (final a in past) {
        for (final b in past) {
          if (!identical(a, b)) expect(a.rect.overlaps(b.rect), isFalse, reason: '$a and $b');
        }
      }

      // Once the old ones have left, new ones keep to the area again.
      rig.timeline.add([for (var i = 0; i < 20; i++) item('之后$i', 12000 + i * 400)]);
      rig.play(6.05);
      await rig.run(tester, 9);
      expect(rig.visible(tester), isNotEmpty);
      expect(rig.visible(tester).every((shown) => shown.rect.bottom <= area + 0.01), isTrue);
    });

    testWidgets('a screen too full for rows of their own still keeps them all', (tester) async {
      await grow(tester, Rig(), area: 1, scale: 2, every: 125);
    });
  });

  testWidgets('the page\'s player feeds its danmaku the 弹幕设置 store, for the presentation it is in', (tester) async {
    final session = FakePlayerSession();
    final chrome = ChromeState();
    final panels = PanelController();
    final orientation = OrientationController();
    final store = DanmakuSettingsStore.memory(const DanmakuSettings(area: 0.25, opacity: 0.5, speed: 0));
    final logger = Logger(session: 'test');
    final feed = DanmakuFeed(
      client: BiliClient(transport: Canned.http(), cookies: CookieJar(Canned.cookies), logger: logger),
      logger: logger,
    );
    final api = FakePageApi();
    final danmaku = DanmakuSession(
      feed: feed,
      settings: store,
      rules: BlockRuleStore(api: api, isLoggedIn: () => false),
      api: api,
      target: () => null,
      position: () => 0,
      isLoggedIn: () => false,
      isVip: () => false,
      accountMid: () => 0,
      toast: (_) {},
      requestLogin: () {},
    );
    addTearDown(() {
      danmaku.dispose();
      feed.dispose();
      session.dispose();
      chrome.dispose();
      panels.dispose();
      orientation.dispose();
    });
    final ui = PlayerUi(
      session: session,
      chrome: chrome,
      panels: panels,
      orientation: orientation,
      device: NoDeviceControls(),
      onBack: () {},
      danmaku: danmaku,
    );
    final video = session.player.buildView();
    Future<void> show(Presentation presentation) => tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerArea(presentation: presentation, onBack: () {}, ui: ui, video: video),
      ),
    );
    DanmakuOptions options() => tester.state<DanmakuLayerState>(find.byType(DanmakuLayer)).options;

    await show(Presentation.inline);
    expect(options(), store.value.display(fullScreen: false));
    await show(Presentation.landscape);
    expect(options(), store.value.display(fullScreen: true));

    store.update(store.value.copyWith(scale: 1.3));
    await tester.pump();
    expect(options().scale, 1.3);
  });
}
