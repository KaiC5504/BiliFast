import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bili_core/danmaku.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart' show ManualClock;
import 'package:bilifast/app/form_factor.dart';
import 'package:bilifast/danmaku/block_rule_store.dart';
import 'package:bilifast/danmaku/danmaku_layer.dart';
import 'package:bilifast/danmaku/danmaku_overlays.dart';
import 'package:bilifast/danmaku/danmaku_scene.dart';
import 'package:bilifast/danmaku/danmaku_session.dart';
import 'package:bilifast/danmaku/danmaku_settings.dart';
import 'package:bilifast/danmaku/danmaku_settings_store.dart';
import 'package:bilifast/danmaku/send/danmaku_send_model.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player/playback_clock.dart';
import 'package:bilifast/playback/danmaku_feed.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';
import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';

DisplayDanmaku item(String text, int ms, {int mode = 1}) => DisplayDanmaku(
  elem: DanmakuElem(progressMs: ms, mode: mode, content: text),
  text: text,
  isOwn: false,
);

final _ruler = '弹' * 100;
final _top = [_ruler, '今夕是何年', '快带上耳机', '首页通知书', '一二三四', '五六七八', '多余的一条'];

DanmakuScene laidOut(Size size, DanmakuOptions options) {
  final timeline = DanmakuTimeline()..add([for (final text in _top) item(text, 4500, mode: 5)]);
  final scene = DanmakuScene()..size = size;
  addTearDown(scene.dispose);
  scene.step(5, timeline: timeline, options: options);
  return scene;
}

Map<String, Rect> shown(DanmakuScene scene) => {for (final danmaku in scene.visible) danmaku.text: danmaku.rect};

/// Under the test's square font a character is as wide as the font is big; a sprite's width is rounded up to a point,
/// so a hundred of them measure it.
double fontOf(DanmakuScene scene) => (shown(scene)[_ruler]!.width - BiliMetrics.danmakuPad * 2) / 100;

/// A session whose post never goes out.
class _Session extends DanmakuSession {
  _Session({required super.feed, required super.rules, required super.api})
    : super(
        settings: DanmakuSettingsStore.memory(),
        target: () => (bvid: 'BV1xx411c7mD', cid: 42),
        position: () => 12.5,
        isLoggedIn: () => true,
        isVip: () => false,
        accountMid: () => 7,
        requestLogin: () {},
      );

  @override
  Future<String?> send(String text, DanmakuStyle style) async => null;
}

void main() {
  group('the scene', () {
    test('iPad full screen: 21.75 pt, lanes 1.44 of it from the top edge, 25% of 834 holding six', () {
      final scene = laidOut(
        const Size(1194, 834),
        const DanmakuOptions(area: 0.25, presentation: Presentation.landscape, formFactor: FormFactor.pad),
      );
      expect(fontOf(scene), closeTo(PadDanmakuTheme.fontFullScreen, 0.011));
      expect(scene.laneHeight, closeTo(21.75 * BiliMetrics.danmakuLaneHeight, 0.01));
      final centres = [for (final rect in shown(scene).values) rect.center.dy]..sort();
      expect(centres, hasLength(6), reason: '25 shows six lanes in 25% of the screen');
      for (final (lane, centre) in centres.indexed) {
        expect(centre, closeTo(scene.laneHeight * (lane + 0.5), 0.01));
      }
    });

    test("the iPad page's player scales full screen's size by its width: 756 and 834 pt boxes", () {
      for (final width in [756.0, 834.0]) {
        final scene = laidOut(Size(width, width * 9 / 16), const DanmakuOptions(formFactor: FormFactor.pad));
        final font = PadDanmakuTheme.fontFullScreen * width / PadDanmakuTheme.fullScreenWidth;
        expect(fontOf(scene), closeTo(font, 0.011));
        expect(scene.laneHeight, greaterThanOrEqualTo(font * BiliMetrics.danmakuLaneHeight - 0.01));
      }
    });

    test('字体大小 scales the iPad sizes as it does the phone\'s', () {
      final scene = laidOut(
        const Size(1194, 834),
        const DanmakuOptions(scale: 1.5, presentation: Presentation.landscape, formFactor: FormFactor.pad),
      );
      expect(fontOf(scene), closeTo(PadDanmakuTheme.fontFullScreen * 1.5, 0.011));
    });

    test('the phone keeps 22 pt in landscape and 12.5 on the small player, whatever its width', () {
      expect(const DanmakuOptions().formFactor, FormFactor.phone);
      expect(const DanmakuSettings().display(presentation: Presentation.inline).formFactor, FormFactor.phone);
      final landscape = laidOut(const Size(956, 440), const DanmakuOptions(presentation: Presentation.landscape));
      expect(fontOf(landscape), closeTo(BiliMetrics.danmakuFontFullScreen, 0.011));
      expect(landscape.laneHeight, closeTo(22 * BiliMetrics.danmakuLaneHeight, 0.01));
      for (final width in [440.0, 834.0]) {
        expect(fontOf(laidOut(Size(width, 247.5), const DanmakuOptions())), closeTo(BiliMetrics.danmakuFont, 0.011));
      }
    });
  });

  group('the layer', () {
    Future<DanmakuLayerState> mount(WidgetTester tester, Presentation presentation) async {
      final store = DanmakuSettingsStore.memory();
      addTearDown(store.dispose);
      final clock = PlaybackClock(clock: ManualClock(10000).clock);
      await tester.pumpWidget(
        DanmakuLayer(clock: clock, timeline: DanmakuTimeline(), settings: store, presentation: presentation),
      );
      return tester.state<DanmakuLayerState>(find.byType(DanmakuLayer));
    }

    testWidgets('on the iPad it sizes for the iPad', (tester) async {
      showAsPad(tester, landscape: true);
      final state = await mount(tester, Presentation.landscape);
      expect(state.options.formFactor, FormFactor.pad);
      expect(state.options.presentation, Presentation.landscape);
    });

    testWidgets('on the phone it sizes for the phone, as before', (tester) async {
      showAsPhone(tester, landscape: true);
      final state = await mount(tester, Presentation.landscape);
      expect(state.options, const DanmakuSettings().display(presentation: Presentation.landscape));
    });
  });

  group('the send bar on the iPad', () {
    late _Session session;
    late ValueNotifier<double> keyboard;

    setUp(() {
      PlayerPrefs.shared = PlayerPrefs.memory();
      DanmakuOverlays.debugForgetKeyboard();
      final logger = Logger(session: 'test');
      final api = FakePageApi();
      keyboard = ValueNotifier(0);
      session = _Session(
        feed: DanmakuFeed(
          client: BiliClient(transport: Canned.http(), cookies: CookieJar(Canned.cookies), logger: logger),
          logger: logger,
        ),
        rules: BlockRuleStore(api: api, isLoggedIn: () => true),
        api: api,
      );
    });

    tearDown(() {
      session.dispose();
      keyboard.dispose();
    });

    Future<void> pumpLayer(WidgetTester tester, {required bool landscape, required Presentation presentation}) async {
      showAsPad(tester, landscape: landscape);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder(
            valueListenable: keyboard,
            builder: (context, inset, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(viewInsets: EdgeInsets.only(bottom: inset)),
              child: child!,
            ),
            child: DanmakuOverlays(session: session, presentation: presentation, playerBottom: 493, toast: (_) {}),
          ),
        ),
      );
    }

    final bar = find.byKey(const ValueKey('danmaku-send-bar'));
    final field = find.byKey(const ValueKey('danmaku-send-field'));
    final style = find.byKey(const ValueKey('danmaku-send-style'));
    final send = find.byKey(const ValueKey('danmaku-send-button'));
    final panel = find.byKey(const ValueKey('danmaku-style-panel'));

    for (final (landscape, presentation) in [
      (true, Presentation.landscape),
      (true, Presentation.inline),
      (false, Presentation.inline),
    ]) {
      final width = landscape ? 1194.0 : 834.0;
      final height = landscape ? 834.0 : 1194.0;
      testWidgets('${presentation.name} at $width wide: the phone\'s row heights and cells, the field taking the rest, '
          'on the keyboard', (tester) async {
        await pumpLayer(tester, landscape: landscape, presentation: presentation);
        session.openSend();
        await tester.pump();
        await tester.pump();
        keyboard.value = 400;
        await tester.pump();
        expect(tester.takeException(), isNull);

        final barRect = tester.getRect(bar);
        expect(barRect.width, width);
        expect(barRect.height, DanmakuSendTheme.barHeight);
        expect(barRect.bottom, moreOrLessEquals(height - 400));
        expect(tester.getSize(style).width, DanmakuSendTheme.aCell);
        expect(tester.getSize(send).width, DanmakuSendTheme.sendCell);
        expect(tester.getSize(field).width, width - DanmakuSendTheme.aCell - DanmakuSendTheme.sendCell);
        expect(tester.getSize(field).height, DanmakuSendTheme.fieldHeight);
      });

      testWidgets('${presentation.name} at $width wide: before any keyboard the style panel takes the iPad\'s height, '
          'its rows left-aligned at the phone\'s sizes', (tester) async {
        await pumpLayer(tester, landscape: landscape, presentation: presentation);
        session.openSend();
        await tester.pump();
        await tester.pump();
        await tester.tap(style);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(panel).height,
          landscape ? PadDanmakuTheme.landscapePanelHeight : PadDanmakuTheme.portraitPanelHeight,
        );
        expect(tester.getRect(panel).bottom, height);
        final small = tester.getRect(find.byKey(const ValueKey('danmaku-style-size-small')));
        final normal = tester.getRect(find.byKey(const ValueKey('danmaku-style-size-normal')));
        expect(normal.width, small.width, reason: 'options keep their width, not spread across the screen');
        expect(normal.left, lessThan(width / 2));
      });
    }
  });

  testWidgets('look-alike: full screen danmaku over 09 and 25 (BILIFAST_SHOTS)', (tester) async {
    await tester.runAsync(loadSystemFontStandIns);
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    BiliFonts.family = BiliFonts.system;
    showAsPad(tester, landscape: true);
    final time = ManualClock(10000);
    final clock = PlaybackClock(clock: time.clock);
    final store = DanmakuSettingsStore.memory()
      ..update(const DanmakuSettings(area: 0.25, opacity: 0.7));
    addTearDown(store.dispose);
    final timeline = DanmakuTimeline()
      ..add([
        for (final (index, text) in const [
          '养好的话，这段子刚好20个字，可能用吧，养好号的话，这个字刚好20个字。',
          '还打得开你康神主页吗',
          '啊～是心肌梗塞的感觉。',
          '这种一定要留言，而且一定要超过 15 个字，这是来自老一辈的忠告',
          '看着更有意思的时候你们那边的人都是这样的吗',
          '零秒猜到奶康藏在哪里',
        ].indexed)
          item(text, 900 + index * 10, mode: 5),
      ]);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('shot'),
        child: ColoredBox(
          color: const Color(0xFF000000),
          child: Stack(
            textDirection: TextDirection.ltr,
            fit: StackFit.expand,
            children: [
              // 25's pillarboxed picture, about its grey, for the outline.
              const Positioned(left: 304, width: 393, top: 0, bottom: 0, child: ColoredBox(color: Color(0xFF3E3E3E))),
              DanmakuLayer(clock: clock, timeline: timeline, settings: store, presentation: Presentation.landscape),
            ],
          ),
        ),
      ),
    );
    clock.handle(const StatusChanged(PlayerStatus.playing));
    clock.handle(PositionChanged(seconds: 1, hostMs: time.clock.nowMs(), rate: 1));
    for (var i = 0; i < 12; i++) {
      time.advance(1000 / 60);
      await tester.pump(const Duration(milliseconds: 16));
    }
    final state = tester.state<DanmakuLayerState>(find.byType(DanmakuLayer));
    expect(state.scene.visible, hasLength(6));
    expect(
      state.scene.laneHeight,
      closeTo(PadDanmakuTheme.fontFullScreen * BiliMetrics.danmakuLaneHeight, 0.01),
      reason: "25's 62.6 px pitch, under PingFang's taller line",
    );
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) {
      await saveShot(tester, find.byKey(const ValueKey('shot')), '$shots/pad-danmaku.png', pixelRatio: 2);
    }
  });
}
