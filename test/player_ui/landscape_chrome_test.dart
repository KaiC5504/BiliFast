import 'package:bili_core/api.dart'
    show
        BiliClient,
        CookieJar,
        HTTPRequest,
        HTTPResponse,
        HTTPTransport,
        QualityOption,
        UploaderCard,
        VideoDetail,
        VideoShot,
        VideoTag,
        VideoTagKind;
import 'package:bili_core/devlog.dart' show Logger;
import 'package:bilifast/danmaku/block_rule_store.dart';
import 'package:bilifast/danmaku/danmaku_session.dart';
import 'package:bilifast/danmaku/danmaku_settings_store.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/device/status_bar.dart';
import 'package:bilifast/playback/danmaku_feed.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/landscape_chrome.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/player_ui/status_bar_view.dart';
import 'package:bilifast/shared/action_glyphs.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/player_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player_session.dart';
import '../support/fake_video_actions.dart';
import 'seek_preview_test.dart' show testSheets;

class CountingChrome extends ChromeState {
  int shows = 0;

  @override
  void show() {
    shows += 1;
    super.show();
  }
}

/// The landscape chrome on an iPhone 17 Pro Max turned sideways (956 × 440 pt, the island's 62 pt each side, the
/// home indicator's 21 below), the size 04 was taken at.
final class Rig {
  Rig({this.details, this.danmaku, this.statusBar, this.replyCount});

  final session = FakePlayerSession();
  final chrome = CountingChrome();
  final panels = PanelController();
  final orientation = OrientationController()..enterLandscape();
  final FakePageDetails? details;
  final DanmakuRig? danmaku;
  final StatusBarFeed? statusBar;
  final ValueNotifier<int?>? replyCount;
  int backs = 0;
  int comments = 0;

  late final ui = PlayerUi(
    session: session,
    chrome: chrome,
    panels: panels,
    orientation: orientation,
    device: orientation.controls,
    onBack: () => backs += 1,
    details: details,
    onComments: () => comments += 1,
    danmaku: danmaku?.session,
    statusBar: statusBar,
    replyCount: replyCount,
  );

  Future<void> mount(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(956, 440)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(left: 62, right: 62, bottom: 21);
    addTearDown(tester.view.reset);
    addTearDown(() {
      chrome.dispose();
      panels.dispose();
      orientation.dispose();
      session.dispose();
      details?.dispose();
      danmaku?.dispose();
      replyCount?.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ColoredBox(
          color: Colors.black,
          child: LandscapeChrome(ui: ui),
        ),
      ),
    );
  }
}

/// A fixed status that records every watch.
final class CountingStatusFeed implements StatusBarFeed {
  CountingStatusFeed([DeviceStatus status = DeviceStatus.full]) : status = ValueNotifier(status);

  @override
  final ValueNotifier<DeviceStatus> status;

  final calls = <bool>[];

  @override
  void watch(bool on) => calls.add(on);
}

final class _NoNetwork implements HTTPTransport {
  @override
  Future<HTTPResponse> send(HTTPRequest request) => throw StateError('tests never reach the network');
}

final class _Feed extends DanmakuFeed {
  _Feed() : super(client: BiliClient(transport: _NoNetwork(), cookies: CookieJar(), logger: _logger), logger: _logger);

  static final _logger = Logger(session: 'test');

  bool uploaderClosed = false;

  @override
  bool get closed => uploaderClosed;
}

/// The page's danmaku as the video page makes it, over the fake page API and memory stores.
final class DanmakuRig {
  DanmakuRig({bool closed = false, this.loggedIn = true}) {
    feed.uploaderClosed = closed;
  }

  final feed = _Feed();
  final api = FakePageApi();
  bool loggedIn;
  int logins = 0;

  late final session = DanmakuSession(
    feed: feed,
    settings: DanmakuSettingsStore.memory(),
    rules: BlockRuleStore(api: api, isLoggedIn: () => loggedIn),
    api: api,
    target: () => (bvid: 'BV1', cid: 1),
    position: () => 0,
    isLoggedIn: () => loggedIn,
    isVip: () => false,
    accountMid: () => 1,
    requestLogin: () => logins += 1,
  );

  void dispose() {
    session.dispose();
    feed.dispose();
  }
}

Offset centre(WidgetTester tester, String key) => tester.getCenter(find.byKey(ValueKey(key)));

const twoParts = [
  Episode(bvid: 'BV1', cid: 1, title: 'P1', current: true),
  Episode(bvid: 'BV1', cid: 2, title: 'P2', current: false),
];

final detail = VideoDetail.fromJson({
  'bvid': 'BV1',
  'owner': {'mid': 1, 'name': 'PRORES 8K', 'face': ''},
});

/// How far down the screen [text]'s alphabetic baseline is, laid out again as the paragraph is.
double baselineOf(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final painter = TextPainter(
    text: paragraph.text,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
    maxLines: paragraph.maxLines,
    strutStyle: paragraph.strutStyle,
    textHeightBehavior: paragraph.textHeightBehavior,
  )..layout(maxWidth: paragraph.size.width);
  final baseline = painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  painter.dispose();
  return paragraph.localToGlobal(Offset.zero).dy + baseline;
}

ActionIcon iconOf(WidgetTester tester, String key) =>
    tester.widget<ActionIcon>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(ActionIcon)));

/// The glyph's own swell, inside the press shrink every chrome button has.
double scaleOf(WidgetTester tester, String key) => tester
    .widget<ScaleTransition>(
      find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(ScaleTransition)).last,
    )
    .scale
    .value;

void main() {
  testWidgets('lays out as 04: back and ⋮ level at the top, 截图 and the lock on the right, the bottom row', (
    tester,
  ) async {
    final rig = Rig()..session.title = 'Dolby Vision 8K HDR 120FPS';
    await rig.mount(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Dolby Vision 8K HDR 120FPS'), findsOneWidget);
    expect(centre(tester, 'landscape-back').dx, closeTo(89, 1));
    expect(centre(tester, 'landscape-back').dy, closeTo(42, 1));
    expect(centre(tester, 'landscape-more'), within(distance: 1, from: const Offset(867, 42)));
    expect(centre(tester, 'landscape-capture'), within(distance: 0.5, from: const Offset(872, 178.5)));
    expect(centre(tester, 'landscape-lock'), within(distance: 0.5, from: const Offset(872, 231.5)));
    expect(centre(tester, 'landscape-play'), within(distance: 1, from: const Offset(84, 397)));
    expect(centre(tester, 'landscape-danmaku'), within(distance: 1, from: const Offset(134, 396)));
    expect(centre(tester, 'landscape-bar').dy, closeTo(359, 1));
    expect(tester.getTopLeft(find.byKey(const ValueKey('landscape-bar'))).dx, 62);
    expect(tester.getTopRight(find.byKey(const ValueKey('landscape-bar'))).dx, 894);
    expect(tester.getTopLeft(find.byKey(const ValueKey('landscape-time'))).dx, 63);
    // The title stops short of where 点赞…分享 go.
    expect(tester.getTopRight(find.byKey(const ValueKey('landscape-title'))).dx, lessThanOrEqualTo(509));
  });

  group('the system font (字体 系统)', () {
    late String? saved;
    setUp(() => saved = BiliFonts.family);
    tearDown(() => BiliFonts.family = saved);

    List<String>? fallbackOf(WidgetTester tester, String key) =>
        tester.renderObject<RenderParagraph>(find.byKey(ValueKey(key))).text.style?.fontFamilyFallback;

    testWidgets("the chrome's text falls back to PingFang SC, as the app's own text does", (tester) async {
      BiliFonts.family = BiliFonts.system;
      final rig = Rig(statusBar: FixedStatusBarFeed())..session.title = '⚠别眨眼！前方高燃！！';
      await rig.mount(tester);
      for (final key in ['landscape-title', 'landscape-time', 'status-time', 'status-battery-level']) {
        expect(fallbackOf(tester, key), ['PingFang SC'], reason: key);
      }
    });

    testWidgets('MiSans names no fallback', (tester) async {
      BiliFonts.family = BiliFonts.miSans;
      final rig = Rig(statusBar: FixedStatusBarFeed())..session.title = '⚠别眨眼！前方高燃！！';
      await rig.mount(tester);
      for (final key in ['landscape-title', 'landscape-time', 'status-time', 'status-battery-level']) {
        expect(fallbackOf(tester, key), isNull, reason: key);
      }
    });
  });

  testWidgets('back, ⋮, play and the bar do what they say and keep the controls up', (tester) async {
    final rig = Rig();
    rig.session.duration.value = 100;
    await rig.mount(tester);

    await tester.tap(find.byKey(const ValueKey('landscape-back')));
    expect(rig.backs, 1);

    await tester.tap(find.byKey(const ValueKey('landscape-play')));
    expect(rig.session.calls, ['togglePlay']);
    expect(rig.chrome.shows, 1);

    await tester.tap(find.byKey(const ValueKey('landscape-more')));
    expect(rig.panels.value, PlayerPanel.more);
    expect(rig.chrome.shows, 2);

    rig.panels.close();
    await tester.pumpAndSettle();
    final bar = find.byKey(const ValueKey('landscape-bar'));
    await tester.dragFrom(tester.getCenter(bar), const Offset(100, 0));
    await tester.pumpAndSettle();
    expect(rig.session.calls.where((call) => call.startsWith('scrub')), isNotEmpty);
    expect(rig.session.calls.last, startsWith('commitSeek'));
    expect(rig.chrome.shows, 3);
  });

  testWidgets('the play glyph follows the player and turns to play once the video has ended', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    expect(find.bySemanticsLabel('播放'), findsOneWidget);

    rig.session.player.emit(const StatusChanged(PlayerStatus.playing));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('暂停'), findsOneWidget);

    rig.session
      ..ended = true
      ..changed();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('播放'), findsOneWidget);
  });

  testWidgets('截图 saves the frame and toasts what came of it; it is gone where frames cannot be captured', (
    tester,
  ) async {
    final rig = Rig()..session.captureResult = const ActionResult('已保存到相册', ok: true);
    await rig.mount(tester);

    await tester.tap(find.byKey(const ValueKey('landscape-capture')));
    await tester.pump();
    expect(rig.session.calls, ['captureFrame']);
    expect(find.text('已保存到相册'), findsOneWidget);
    expect(rig.chrome.shows, 1);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('已保存到相册'), findsNothing);

    rig.session
      ..canCaptureFrame = false
      ..changed();
    await tester.pump();
    expect(find.byKey(const ValueKey('landscape-capture')), findsNothing);
    expect(find.byKey(const ValueKey('landscape-lock')), findsOneWidget);
  });

  testWidgets('the lock toggles the rotation lock and says which way it will go; the other controls stay', (
    tester,
  ) async {
    final rig = Rig();
    await rig.mount(tester);
    expect(find.bySemanticsLabel('锁定屏幕方向'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('landscape-lock')));
    await tester.pumpAndSettle();
    expect(rig.orientation.locked, isTrue);
    expect(find.bySemanticsLabel('解锁屏幕方向'), findsOneWidget);
    expect(rig.chrome.shows, 1);
    for (final key in ['landscape-back', 'landscape-play', 'landscape-bar', 'landscape-speed']) {
      expect(find.byKey(ValueKey(key)).hitTestable(), findsOneWidget, reason: key);
    }

    await tester.tap(find.byKey(const ValueKey('landscape-lock')));
    await tester.pumpAndSettle();
    expect(rig.orientation.locked, isFalse);
    expect(find.bySemanticsLabel('锁定屏幕方向'), findsOneWidget);
  });

  testWidgets('弹 turns danmaku off and on', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    expect(find.bySemanticsLabel('关闭弹幕'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('landscape-danmaku')));
    await tester.pumpAndSettle();
    expect(rig.session.calls, ['setDanmakuOn false']);
    expect(find.bySemanticsLabel('开启弹幕'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('landscape-danmaku')));
    expect(rig.session.calls.last, 'setDanmakuOn true');
  });

  testWidgets('倍速 reads 倍速 at 1× and the rate otherwise, and opens the speed panel', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    final speed = find.byKey(const ValueKey('landscape-speed'));
    expect(find.descendant(of: speed, matching: find.text('倍速')), findsOneWidget);

    for (final (rate, label) in [(1.5, '1.5X'), (1.25, '1.25X'), (2.0, '2.0X'), (0.75, '0.75X')]) {
      await rig.session.setRate(rate);
      await tester.pump();
      expect(
        find.descendant(of: speed, matching: find.text(label)),
        findsOneWidget,
        reason: '$rate',
      );
    }

    await tester.tap(speed);
    expect(rig.panels.value, PlayerPanel.speed);
  });

  testWidgets('the quality button names the quality playing as 04 does, and opens the quality panel', (tester) async {
    final rig = Rig();
    rig.session
      ..qualities = const [QualityOption(id: 120, name: '4K 超清'), QualityOption(id: 80, name: '1080P 高清')]
      ..quality = 120;
    await rig.mount(tester);
    final quality = find.byKey(const ValueKey('landscape-quality'));

    expect(find.descendant(of: quality, matching: find.text('4K')), findsOne);
    // The video tops out below the quality asked for.
    rig.session
      ..playing = 80
      ..changed();
    await tester.pump();
    expect(find.descendant(of: quality, matching: find.text('1080P')), findsOne);

    await tester.tap(quality);
    expect(rig.panels.value, PlayerPanel.quality);
  });

  testWidgets("60 fps reads 1080P under KaiC's screenshot's outlined 60帧 tag, the name kept 2.67 pt each side", (
    tester,
  ) async {
    final rig = Rig();
    rig.session
      ..qualities = const [QualityOption(id: 116, name: '1080P 60帧'), QualityOption(id: 80, name: '1080P 高清')]
      ..quality = 116;
    await rig.mount(tester);
    final quality = find.byKey(const ValueKey('landscape-quality'));
    final name = find.descendant(of: quality, matching: find.text('1080P'));
    final tag = find.byKey(const ValueKey('landscape-quality-tag'));
    expect(name, findsOne);
    expect(find.descendant(of: tag, matching: find.text('60帧')), findsOne);

    final cell = tester.getRect(quality);
    final text = tester.getRect(name);
    final pill = tester.getRect(tag);
    expect(text.left - cell.left, closeTo(BiliMetrics.chromeTaggedPad, 0.01));
    expect(cell.right - text.right, closeTo(BiliMetrics.chromeTaggedPad, 0.01));
    expect(pill.right - text.right, closeTo(8.8, 0.01));
    expect(text.center.dy - pill.center.dy, closeTo(15.2, 0.01));
    expect(pill.height, BiliMetrics.chromeTagHeight);

    rig.session
      ..playing = 80
      ..changed();
    await tester.pump();
    expect(tag, findsNothing);
    expect(find.descendant(of: quality, matching: find.text('1080P')), findsOne);

    rig.session
      ..playing = 112
      ..changed();
    await tester.pump();
    expect(find.descendant(of: tag, matching: find.text('高码率')), findsOne);
    expect(find.descendant(of: quality, matching: find.text('1080P')), findsOne);
  });

  testWidgets('sizes as 04: the title at 16, 倍速 and the quality at 14, back a full 44 pt target', (tester) async {
    final rig = Rig()..session.title = 'Dolby Vision 8K HDR 120FPS';
    await rig.mount(tester);

    TextStyle styleOf(Finder text) => tester.widget<Text>(text).style!;
    expect(styleOf(find.byKey(const ValueKey('landscape-title'))).fontSize, 16);
    // MiSans ships one weight, and only w600 and up get the synthetic bold 04's semibold title needs.
    expect(styleOf(find.byKey(const ValueKey('landscape-title'))).fontWeight, FontWeight.w600);
    final speed = find.descendant(of: find.byKey(const ValueKey('landscape-speed')), matching: find.byType(Text));
    expect(styleOf(speed).fontSize, 14);
    final quality = find.descendant(of: find.byKey(const ValueKey('landscape-quality')), matching: find.byType(Text));
    expect(styleOf(quality).fontSize, 14);
    expect(tester.getSize(find.byKey(const ValueKey('landscape-back'))), const Size(44, 44));
    // The triangle sits 2.2 pt right of its button's centre, where 04 has it.
    final glyph = find.descendant(of: find.byKey(const ValueKey('landscape-play')), matching: find.byType(CustomPaint));
    expect(tester.getCenter(glyph.last).dx - centre(tester, 'landscape-play').dx, closeTo(2.2, 0.01));
  });

  testWidgets('选集 shows only with episodes, before 倍速 and 4K as on 05, and opens the episodes panel', (tester) async {
    final rig = Rig(danmaku: DanmakuRig());
    rig.session
      ..qualities = const [QualityOption(id: 120, name: '4K 超清')]
      ..quality = 120;
    await rig.mount(tester);
    expect(find.byKey(const ValueKey('landscape-episodes')), findsNothing);
    final speed = tester.getRect(find.byKey(const ValueKey('landscape-speed')));
    final quality = tester.getRect(find.byKey(const ValueKey('landscape-quality')));

    rig.session
      ..episodes = twoParts
      ..changed();
    await tester.pump();
    final episodes = tester.getRect(find.byKey(const ValueKey('landscape-episodes')));
    expect(
      tester.getRect(find.byKey(const ValueKey('landscape-speed'))),
      rectMoreOrLessEquals(speed, epsilon: 0.01),
      reason: '倍速 stays where 04 has it',
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('landscape-quality'))),
      rectMoreOrLessEquals(quality, epsilon: 0.01),
    );
    expect(speed.left - episodes.right, closeTo(LandscapeActionTheme.episodesGap, 0.01));
    final field = tester.getRect(
      find.descendant(of: find.byKey(const ValueKey('landscape-danmaku-field')), matching: find.byType(Container)),
    );
    expect(episodes.left - field.right, closeTo(BiliMetrics.chromeSpeedGap, 0.5), reason: 'the field gives way');
    // 05's labels are 62 pt apart, centre to centre.
    expect(speed.center.dx - episodes.center.dx, closeTo(62, 0.5));

    await tester.tap(find.byKey(const ValueKey('landscape-episodes')));
    expect(rig.panels.value, PlayerPanel.episodes);
  });

  testWidgets('⏭ follows ▶ when something plays next, as on 05, and plays it; 弹 and the rest move 50 pt on', (
    tester,
  ) async {
    final rig = Rig(danmaku: DanmakuRig());
    await rig.mount(tester);
    expect(find.byKey(const ValueKey('landscape-next')), findsNothing);
    expect(centre(tester, 'landscape-danmaku'), within(distance: 1, from: const Offset(134, 396)));

    rig.session
      ..episodes = twoParts
      ..next = twoParts.last
      ..changed();
    await tester.pump();
    expect(centre(tester, 'landscape-next'), within(distance: 0.01, from: const Offset(134, 396)));
    final glyph = find.descendant(of: find.byKey(const ValueKey('landscape-next')), matching: find.byType(CustomPaint));
    expect(tester.getCenter(glyph).dx, closeTo(135, 0.01), reason: "05's ⏭ is centred 135 pt in");
    expect(tester.getSize(glyph), const Size(LandscapeActionTheme.nextWidth, LandscapeActionTheme.nextHeight));
    expect(centre(tester, 'landscape-danmaku'), within(distance: 1, from: const Offset(184, 396)));
    expect(centre(tester, 'landscape-danmaku-settings'), within(distance: 1, from: const Offset(232, 396)));

    await tester.tap(find.byKey(const ValueKey('landscape-next')));
    expect(rig.session.calls, ['playEpisode BV1 2']);
    expect(rig.chrome.shows, 1);
    tester.semantics.tap(find.semantics.byLabel('下一集'));
    expect(rig.session.calls, ['playEpisode BV1 2', 'playEpisode BV1 2']);
  });

  testWidgets('with episodes but nothing next ⏭ stays greyed, as on 34, and a tap only keeps the controls up', (
    tester,
  ) async {
    final rig = Rig();
    rig.session.episodes = twoParts;
    await rig.mount(tester);

    final next = find.byKey(const ValueKey('landscape-next'));
    expect(centre(tester, 'landscape-next'), within(distance: 0.01, from: const Offset(134, 396)));
    expect(
      tester.widget<Opacity>(find.descendant(of: next, matching: find.byType(Opacity))).opacity,
      LandscapeActionTheme.nextOffOpacity,
    );
    await tester.tap(next);
    expect(rig.session.calls, isEmpty);
    expect(
      find.semantics.byLabel('下一集').evaluate().single,
      matchesSemantics(label: '下一集', isButton: true, hasEnabledState: true),
    );
    expect(rig.chrome.shows, 1);
  });

  testWidgets('the time shows the position against the duration', (tester) async {
    final rig = Rig();
    rig.session.duration.value = 794;
    await rig.mount(tester);
    rig.session.scrub(7);
    await tester.pump();
    expect(find.text('00:07/13:14'), findsOneWidget);
  });

  testWidgets('hidden controls fade out and take no touches; a panel hides them too', (tester) async {
    final rig = Rig();
    await rig.mount(tester);

    rig.chrome.hide();
    await tester.pumpAndSettle();
    final root = find.byKey(const ValueKey('landscape-chrome'));
    expect(tester.widget<IgnorePointer>(root).ignoring, isTrue);
    // Each fade is out, or sits inside one that is (the bottom bar's own fades for the seek preview).
    final fades = find.descendant(of: root, matching: find.byType(AnimatedOpacity));
    for (final element in fades.evaluate()) {
      final hidden = [
        element.widget as AnimatedOpacity,
        ...tester.widgetList<AnimatedOpacity>(
          find.ancestor(of: find.byWidget(element.widget), matching: find.byType(AnimatedOpacity)),
        ),
      ].any((fade) => fade.opacity == 0);
      expect(hidden, isTrue);
    }
    await tester.tap(find.byKey(const ValueKey('landscape-play')), warnIfMissed: false);
    expect(rig.session.calls, isEmpty);

    rig.chrome.show();
    await tester.pumpAndSettle();
    expect(tester.widget<IgnorePointer>(root).ignoring, isFalse);

    rig.panels.open(PlayerPanel.quality);
    await tester.pumpAndSettle();
    expect(tester.widget<IgnorePointer>(root).ignoring, isTrue);
  });

  testWidgets('点赞 评论 收藏 投币 充电 分享 line up before ⋮ as on 04, 52 pt apart, and nothing else moves', (tester) async {
    final rig = Rig(details: FakePageDetails(actions: FakeVideoActions()))..session.title = 'Dolby Vision 8K HDR 120FPS';
    await rig.mount(tester);

    expect(tester.takeException(), isNull);
    for (final (key, x) in [
      ('landscape-like', 555.0),
      ('landscape-comments', 607.0),
      ('landscape-favourite', 659.0),
      ('landscape-coin', 711.0),
      ('landscape-charge', 763.0),
      ('landscape-share', 815.0),
    ]) {
      expect(centre(tester, key), within(distance: 0.5, from: Offset(x, 42)), reason: key);
      expect(tester.getSize(find.byKey(ValueKey(key))), const Size(44, 44), reason: key);
    }
    expect(centre(tester, 'landscape-more'), within(distance: 1, from: const Offset(867, 42)));
    expect(centre(tester, 'landscape-back'), within(distance: 1, from: const Offset(89, 42)));
    expect(tester.getTopRight(find.byKey(const ValueKey('landscape-title'))).dx, lessThanOrEqualTo(509));
    final icons = tester.widgetList<ActionIcon>(find.byType(ActionIcon));
    expect(icons.map((icon) => icon.glyph), [
      ActionGlyph.like,
      ActionGlyph.comment,
      ActionGlyph.favourite,
      ActionGlyph.coin,
      ActionGlyph.charge,
      ActionGlyph.share,
    ]);
    for (final icon in icons) {
      expect(icon.solid, isFalse);
      expect(icon.color, BiliColors.onVideo);
      expect(icon.size, LandscapeActionTheme.iconSize);
      expect(icon.stroke, LandscapeActionTheme.outline, reason: "04 and 05's 1.5 pt lines");
    }
  });

  testWidgets("the title starts over N人正在看's icon, as 05's does, and still ends before the actions", (tester) async {
    final rig = Rig(details: FakePageDetails(actions: FakeVideoActions(), online: '1'))..session.title = '别眨眼！前方高燃！！';
    await rig.mount(tester);
    final title = tester.getRect(find.byKey(const ValueKey('landscape-title')));
    expect(title.left, closeTo(115.7, 0.01));
    expect(title.left, closeTo(tester.getTopLeft(find.byKey(const ValueKey('landscape-online'))).dx, 0.01));
    expect(title.right, closeTo(509, 0.01));
  });

  testWidgets("👍, 💬 and ⭐ are fitted to 05's shorter ink; the rest keep the shared glyph's box", (tester) async {
    final rig = Rig(details: FakePageDetails(actions: FakeVideoActions()));
    await rig.mount(tester);
    Rect iconBox(String key) =>
        tester.getRect(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(ActionIcon)));

    const size = LandscapeActionTheme.iconSize;
    for (final (key, x, squash, lift) in [
      ('landscape-like', 555.0, LandscapeActionTheme.likeSquash, LandscapeActionTheme.likeLift),
      ('landscape-favourite', 659.0, LandscapeActionTheme.favouriteSquash, LandscapeActionTheme.favouriteLift),
      ('landscape-comments', 607.0, LandscapeActionTheme.commentSquash, 0.0),
      ('landscape-coin', 711.0, 1.0, 0.0),
    ]) {
      final box = iconBox(key);
      expect(box.width, closeTo(size, 0.01), reason: key);
      expect(box.height, closeTo(size * squash, 0.01), reason: key);
      expect(box.center, within(distance: 0.01, from: Offset(x, 42 - lift)), reason: key);
    }
  });

  testWidgets('点赞 and 收藏 carry their counts as superscripts at their top right; none at 0', (tester) async {
    final actions = FakeVideoActions(likeCount: 30, favCount: 38);
    final rig = Rig(details: FakePageDetails(actions: actions));
    await rig.mount(tester);

    Finder countOf(String key, String text) =>
        find.descendant(of: find.byKey(ValueKey(key)), matching: find.text(text));
    Finder textsOf(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text));
    expect(countOf('landscape-like', '30'), findsOneWidget);
    expect(countOf('landscape-favourite', '38'), findsOneWidget);
    expect(tester.getTopLeft(countOf('landscape-like', '30')).dx, closeTo(561.7, 0.5));
    expect(tester.getTopLeft(countOf('landscape-favourite', '38')).dx, closeTo(665.7, 0.5));
    // 04's and 05's digits stand 32 pt down, in either font.
    expect(baselineOf(tester, countOf('landscape-like', '30')), closeTo(32, 0.01));
    expect(baselineOf(tester, countOf('landscape-favourite', '38')), closeTo(32, 0.01));
    expect(tester.widget<Text>(countOf('landscape-like', '30')).style!.fontSize, LandscapeActionTheme.countText);
    for (final key in ['landscape-comments', 'landscape-coin', 'landscape-charge', 'landscape-share']) {
      expect(textsOf(key), findsNothing, reason: key);
    }

    actions
      ..likeCount = 12345
      ..favCount = 0
      ..changed();
    await tester.pump();
    expect(countOf('landscape-like', '1.2万'), findsOneWidget);
    expect(textsOf('landscape-favourite'), findsNothing);
    expect(centre(tester, 'landscape-like'), within(distance: 0.5, from: const Offset(555, 42)));
  });

  testWidgets("评论 carries the video's reply count as 05 does; none while unknown or at 0", (tester) async {
    final rig = Rig(details: FakePageDetails(actions: FakeVideoActions()));
    await rig.mount(tester);
    final comments = find.byKey(const ValueKey('landscape-comments'));
    expect(find.descendant(of: comments, matching: find.byType(Text)), findsNothing);

    rig.session
      ..detail = VideoDetail.fromJson({
        'bvid': 'BV1',
        'stat': {'reply': 18},
      })
      ..changed();
    await tester.pump();
    final count = find.descendant(of: comments, matching: find.text('18'));
    expect(count, findsOneWidget);
    expect(tester.getTopLeft(count).dx, closeTo(607 + LandscapeActionTheme.countLead, 0.01));
    expect(baselineOf(tester, count), closeTo(32, 0.01));
    expect(tester.widget<Text>(count).style!.fontSize, LandscapeActionTheme.countText);
    expect(centre(tester, 'landscape-comments'), within(distance: 0.5, from: const Offset(607, 42)));

    rig.session
      ..detail = VideoDetail.fromJson({
        'bvid': 'BV1',
        'stat': {'reply': 0},
      })
      ..changed();
    await tester.pump();
    expect(find.descendant(of: comments, matching: find.byType(Text)), findsNothing);
  });

  testWidgets("评论's count is the tab row's once the list has one, following a post or a delete; the detail's until "
      'then', (tester) async {
    final rig = Rig(details: FakePageDetails(actions: FakeVideoActions()), replyCount: ValueNotifier(null))
      ..session.detail = VideoDetail.fromJson({
        'bvid': 'BV1',
        'stat': {'reply': 18},
      });
    await rig.mount(tester);
    final comments = find.byKey(const ValueKey('landscape-comments'));
    expect(find.descendant(of: comments, matching: find.text('18')), findsOneWidget);

    rig.replyCount!.value = 19;
    await tester.pump();
    expect(find.descendant(of: comments, matching: find.text('19')), findsOneWidget);
    expect(find.descendant(of: comments, matching: find.text('18')), findsNothing);

    rig.replyCount!.value = 0;
    await tester.pump();
    expect(find.descendant(of: comments, matching: find.byType(Text)), findsNothing, reason: 'the last one deleted');

    rig.replyCount!.value = null;
    await tester.pump();
    expect(find.descendant(of: comments, matching: find.text('18')), findsOneWidget);
  });

  testWidgets('each action does what it says and keeps the controls up; 充电 toasts that it is not supported', (
    tester,
  ) async {
    final actions = FakeVideoActions();
    final rig = Rig(details: FakePageDetails(actions: actions));
    await rig.mount(tester);

    await tester.tap(find.byKey(const ValueKey('landscape-like')));
    await tester.tap(find.byKey(const ValueKey('landscape-favourite')));
    await tester.tap(find.byKey(const ValueKey('landscape-coin')));
    await tester.tap(find.byKey(const ValueKey('landscape-share')));
    expect(actions.calls, ['toggleLike', 'ask favourites', 'ask coin', 'ask share']);

    await tester.tap(find.byKey(const ValueKey('landscape-comments')));
    expect(rig.comments, 1);

    await tester.tap(find.byKey(const ValueKey('landscape-charge')));
    await tester.pump();
    expect(find.text('暂不支持充电'), findsOneWidget);
    expect(actions.calls, hasLength(4));
    expect(rig.chrome.shows, 6);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('暂不支持充电'), findsNothing);
  });

  testWidgets('liked, favourited and coined turn their glyphs solid pink, swelling as they turn on', (tester) async {
    final actions = FakeVideoActions();
    final rig = Rig(details: FakePageDetails(actions: actions));
    await rig.mount(tester);

    actions
      ..liked = true
      ..favorited = true
      ..coins = 1
      ..changed();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    for (final key in ['landscape-like', 'landscape-favourite', 'landscape-coin']) {
      expect(iconOf(tester, key).color, BiliColors.pink, reason: key);
      expect(iconOf(tester, key).solid, isTrue, reason: key);
      expect(scaleOf(tester, key), greaterThan(1), reason: key);
    }
    for (final key in ['landscape-comments', 'landscape-charge', 'landscape-share']) {
      expect(iconOf(tester, key).color, BiliColors.onVideo, reason: key);
    }
    expect(find.bySemanticsLabel('取消点赞'), findsOneWidget);
    expect(find.bySemanticsLabel('已收藏'), findsOneWidget);
    expect(find.bySemanticsLabel('已投币'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(scaleOf(tester, 'landscape-like'), 1);

    actions
      ..liked = false
      ..changed();
    await tester.pump();
    expect(iconOf(tester, 'landscape-like').color, BiliColors.onVideo);
    expect(iconOf(tester, 'landscape-like').solid, isFalse);
    expect(scaleOf(tester, 'landscape-like'), 1);
  });

  testWidgets('with animations off the glyphs turn on without swelling', (tester) async {
    final actions = FakeVideoActions();
    final rig = Rig(details: FakePageDetails(actions: actions));
    await rig.mount(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: LandscapeChrome(ui: rig.ui),
          ),
        ),
      ),
    );

    actions
      ..liked = true
      ..changed();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(iconOf(tester, 'landscape-like').color, BiliColors.pink);
    expect(scaleOf(tester, 'landscape-like'), 1);
  });

  testWidgets('with animations off 弹 swaps its mark without the fade', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    Duration fade() => tester
        .widget<AnimatedSwitcher>(
          find.descendant(of: find.byType(DanmakuGlyph), matching: find.byType(AnimatedSwitcher)),
        )
        .duration;
    expect(fade(), greaterThan(Duration.zero));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: LandscapeChrome(ui: rig.ui),
          ),
        ),
      ),
    );
    expect(fade(), Duration.zero);
  });

  testWidgets('N人正在看 sits under the title as on 04, follows the count, and is gone while unknown', (tester) async {
    final details = FakePageDetails(actions: FakeVideoActions());
    final rig = Rig(details: details);
    await rig.mount(tester);
    expect(find.byKey(const ValueKey('landscape-online')), findsNothing);
    final title = tester.getRect(find.byKey(const ValueKey('landscape-title')));

    details.online.value = '1';
    await tester.pumpAndSettle();
    expect(find.text('1人正在看'), findsOneWidget);
    final online = find.byKey(const ValueKey('landscape-online'));
    expect(tester.getTopLeft(online).dx, closeTo(115.7, 0.5));
    expect(tester.getCenter(online).dy, closeTo(64.8, 0.5));
    final style = tester.widget<Text>(find.text('1人正在看')).style!;
    expect(style.color, LandscapeActionTheme.online);
    expect(style.fontSize, 12);
    expect(tester.getRect(find.byKey(const ValueKey('landscape-title'))), title);

    details.online.value = '1000+';
    await tester.pumpAndSettle();
    expect(find.text('1000+人正在看'), findsOneWidget);

    details.online.value = null;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('landscape-online')), findsNothing);
  });

  testWidgets('while the controls are hidden a faint N人正在看 stays at the bottom left, as on 25', (tester) async {
    final details = FakePageDetails(online: '1');
    final rig = Rig(details: details);
    await rig.mount(tester);
    final corner = find.byKey(const ValueKey('landscape-corner-online'));
    expect(corner, findsNothing, reason: 'not while the controls show');

    rig.chrome.hide();
    await tester.pumpAndSettle();
    expect(corner, findsOneWidget);
    // 33 pt past the island's inset, centred 9.7 pt above the screen's edge, within the home indicator's band.
    expect(tester.getTopLeft(corner).dx, closeTo(95.3, 0.5));
    expect(tester.getCenter(corner).dy, closeTo(430.3, 0.5));
    final text = find.descendant(of: corner, matching: find.text('1人正在看'));
    expect(tester.widget<Text>(text).style!.color, LandscapeActionTheme.corner);
    expect(tester.widget<Text>(text).style!.fontSize, 9);
    final glyph = find.descendant(of: corner, matching: find.byType(CustomPaint));
    expect(
      tester.getSize(glyph),
      const Size(LandscapeActionTheme.cornerIconWidth, LandscapeActionTheme.cornerIconHeight),
    );
    expect(tester.getTopLeft(text).dx - tester.getTopRight(glyph).dx, closeTo(LandscapeActionTheme.cornerGap, 0.01));
    expect(corner.hitTestable(), findsNothing, reason: 'touches go through it to the video');
    expect(find.semantics.byLabel(RegExp('人正在看')), findsNothing);

    details.online.value = '1000+';
    await tester.pumpAndSettle();
    expect(find.descendant(of: corner, matching: find.text('1000+人正在看')), findsOneWidget);

    rig.panels.open(PlayerPanel.quality);
    await tester.pumpAndSettle();
    expect(corner, findsNothing, reason: 'not with a panel open');
    rig.panels.close();
    await tester.pumpAndSettle();
    expect(corner, findsOneWidget);

    details.online.value = null;
    await tester.pumpAndSettle();
    expect(corner, findsNothing, reason: 'nothing while the count is unknown');
    details.online.value = '3';
    await tester.pumpAndSettle();
    expect(corner, findsOneWidget);

    rig.chrome.show();
    await tester.pumpAndSettle();
    expect(corner, findsNothing);
    expect(find.text('3人正在看'), findsOneWidget, reason: 'the controls show it under the title instead');
  });

  testWidgets('without page details there is no corner count', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    rig.chrome.hide();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('landscape-corner-online')), findsNothing);
    expect(find.textContaining('人正在看'), findsNothing);
  });

  testWidgets('the uploader under it in 05\'s chip: avatar, name, divider and a white + 关注 that follows; 已关注 is '
      'grey with no plus', (tester) async {
    final actions = FakeVideoActions();
    final rig = Rig(
      details: FakePageDetails(
        actions: actions,
        online: '1',
        uploader: const UploaderCard(
          mid: 7,
          name: 'PRORES 8K',
          face: '',
          fans: 0,
          videos: 0,
          isVip: false,
          following: false,
        ),
      ),
    );
    await rig.mount(tester);

    final avatar = find.byKey(const ValueKey('landscape-avatar'));
    expect(tester.getCenter(avatar), within(distance: 0.5, from: const Offset(91, 93)));
    expect(tester.getSize(avatar), const Size(24, 24));
    final chip = tester.getRect(find.byKey(const ValueKey('landscape-uploader')));
    expect(chip.left, closeTo(78, 0.01), reason: "the capsule's end 1 pt outside the avatar");
    expect(chip.center.dy, closeTo(93, 0.01));

    final name = find.text('PRORES 8K');
    expect(tester.getTopLeft(name).dx, closeTo(103 + LandscapeActionTheme.nameGap, 0.01));
    expect(tester.widget<Text>(name).style!.fontSize, LandscapeActionTheme.followText);
    expect(tester.widget<Text>(name).style!.color, BiliColors.onVideo);
    final divider = tester.getRect(find.byKey(const ValueKey('landscape-uploader-divider')));
    expect(divider.left - tester.getTopRight(name).dx, closeTo(LandscapeActionTheme.dividerGap, 0.01));
    expect(divider.width, closeTo(LandscapeActionTheme.dividerWidth, 0.01));
    expect(divider.height, closeTo(LandscapeActionTheme.dividerHeight, 0.01));
    expect(divider.center.dy, closeTo(93, 0.01));

    final follow = find.byKey(const ValueKey('landscape-follow'));
    final plus = find.descendant(of: follow, matching: find.byType(CustomPaint));
    expect(plus, findsOneWidget);
    expect(tester.getTopLeft(plus).dx - divider.right, closeTo(LandscapeActionTheme.dividerGap, 0.01));
    expect(tester.getCenter(plus).dy, closeTo(93, 0.01));
    expect(tester.widget<Text>(find.text('关注')).style!.color, BiliColors.onVideo);
    expect(chip.right - tester.getTopRight(find.text('关注')).dx, closeTo(LandscapeActionTheme.followTrailing, 0.01));
    // 05's name and 关注 stand on one baseline 97.67 pt down.
    expect(baselineOf(tester, name), closeTo(97.67, 0.01));
    expect(baselineOf(tester, find.text('关注')), closeTo(97.67, 0.01));

    await tester.tap(follow);
    expect(actions.calls, ['tapFollow']);
    expect(rig.chrome.shows, 1);

    actions
      ..following = true
      ..changed();
    await tester.pumpAndSettle();
    expect(find.text('已关注'), findsOneWidget);
    expect(find.text('关注'), findsNothing);
    expect(tester.widget<Text>(find.text('已关注')).style!.color, LandscapeActionTheme.followed);
    expect(find.descendant(of: follow, matching: find.byType(CustomPaint)), findsNothing);
    expect(tester.getTopLeft(find.text('已关注')).dx - divider.right, closeTo(LandscapeActionTheme.dividerGap, 0.01));
    expect(
      tester.getRect(find.byKey(const ValueKey('landscape-uploader'))).right - tester.getTopRight(find.text('已关注')).dx,
      closeTo(LandscapeActionTheme.followTrailing, 0.01),
    );
    expect(tester.getCenter(avatar), within(distance: 0.5, from: const Offset(91, 93)));
    expect(find.bySemanticsLabel('已关注'), findsOneWidget);
  });

  testWidgets("a card that came back empty gives way to the view's owner: 05's chip keeps the name and the face", (
    tester,
  ) async {
    const empty = UploaderCard(mid: 1, name: '', face: '', fans: 0, videos: 0, isVip: false, following: false);
    final rig = Rig(details: FakePageDetails(actions: FakeVideoActions(), uploader: empty))
      ..session.detail = VideoDetail.fromJson({
        'bvid': 'BV1',
        'owner': {'mid': 1, 'name': '老鹿der', 'face': 'https://i0.hdslb.com/bfs/face/up.jpg'},
      });
    await rig.mount(tester);

    expect(
      find.descendant(of: find.byKey(const ValueKey('landscape-uploader-name')), matching: find.text('老鹿der')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('landscape-uploader-divider')), findsOneWidget);
    final avatar = find.descendant(
      of: find.byKey(const ValueKey('landscape-avatar')),
      matching: find.byType(RemoteImage),
    );
    expect(tester.widget<RemoteImage>(avatar).url, 'https://i0.hdslb.com/bfs/face/up.jpg');
  });

  testWidgets("the chip's capsule is 05's: 26 pt tall, round-ended, 15% black, centred on the uploader's line", (
    tester,
  ) async {
    final rig = Rig(details: FakePageDetails(actions: FakeVideoActions()))..session.detail = detail;
    await rig.mount(tester);

    final chip = find.byKey(const ValueKey('landscape-uploader'));
    final rect = tester.getRect(chip);
    expect(rect.height, closeTo(LandscapeActionTheme.uploaderHeight, 0.01), reason: '关注 keeps a taller target');
    expect(
      tester.renderObject(find.descendant(of: chip, matching: find.byType(CustomPaint)).first),
      paints..rrect(
        rrect: RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(rect.width / 2, rect.height / 2),
            width: rect.width,
            height: LandscapeActionTheme.chipHeight,
          ),
          const Radius.circular(LandscapeActionTheme.chipHeight / 2),
        ),
        color: LandscapeActionTheme.chipFill,
      ),
    );
    expect(find.text('PRORES 8K'), findsOneWidget, reason: "the detail's owner names it before the card arrives");
  });

  testWidgets('the bgm sits in its own chip under the uploader as on 05, reads as 简介 words it, and leads nowhere', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final details = FakePageDetails(
      actions: FakeVideoActions(),
      tags: const [
        VideoTag(id: 1, name: '生活', kind: VideoTagKind.normal),
        VideoTag(id: 2, name: '发现《Whatever It Takes》', kind: VideoTagKind.bgm),
      ],
    );
    final rig = Rig(details: details)..session.detail = detail;
    await rig.mount(tester);

    final bgm = find.byKey(const ValueKey('landscape-bgm'));
    expect(bgm, findsOneWidget);
    final rect = tester.getRect(bgm);
    expect(rect.left, closeTo(78, 0.01), reason: "lined up with the uploader's chip");
    expect(rect.top, closeTo(114, 0.01));
    expect(rect.height, closeTo(LandscapeActionTheme.chipHeight, 0.01));
    final text = find.text('发现《Whatever It Takes》');
    expect(tester.widget<Text>(text).style!.fontSize, LandscapeActionTheme.followText);
    expect(baselineOf(tester, text), closeTo(131.67, 0.01));
    final glyph = find.descendant(of: bgm, matching: find.byType(CustomPaint)).last;
    expect(
      tester.getRect(glyph),
      rectMoreOrLessEquals(
        Rect.fromLTWH(
          78 + LandscapeActionTheme.musicLead,
          127 - LandscapeActionTheme.musicGlyphHeight / 2,
          LandscapeActionTheme.musicGlyphWidth,
          LandscapeActionTheme.musicGlyphHeight,
        ),
        epsilon: 0.01,
      ),
    );
    expect(tester.getTopLeft(text).dx - tester.getTopRight(glyph).dx, closeTo(LandscapeActionTheme.musicGap, 0.01));
    expect(rect.right - tester.getTopRight(text).dx, closeTo(LandscapeActionTheme.musicTrailing, 0.01));
    expect(find.semantics.byLabel('发现《Whatever It Takes》'), findsOne);
    expect(find.descendant(of: bgm, matching: find.byType(GestureDetector)), findsNothing);

    details
      ..tags = const [VideoTag(id: 1, name: '生活', kind: VideoTagKind.normal)]
      ..changed();
    await tester.pump();
    expect(bgm, findsNothing);
    semantics.dispose();
  });

  testWidgets('without page details none of their parts show, and the rest is where it was', (tester) async {
    final rig = Rig();
    await rig.mount(tester);

    for (final key in ['landscape-like', 'landscape-online', 'landscape-avatar', 'landscape-follow']) {
      expect(find.byKey(ValueKey(key)), findsNothing, reason: key);
    }
    expect(centre(tester, 'landscape-more'), within(distance: 1, from: const Offset(867, 42)));
    expect(centre(tester, 'landscape-back'), within(distance: 1, from: const Offset(89, 42)));
  });

  testWidgets("before the actions: the detail's avatar and no actions; they come in place, follow a new video's", (
    tester,
  ) async {
    final details = FakePageDetails();
    final rig = Rig(details: details)
      ..session.title = 'Dolby Vision 8K HDR 120FPS'
      ..session.detail = detail;
    await rig.mount(tester);

    expect(find.byKey(const ValueKey('landscape-like')), findsNothing);
    expect(find.byKey(const ValueKey('landscape-follow')), findsNothing);
    expect(find.byKey(const ValueKey('landscape-online')), findsNothing);
    final avatar = find.byKey(const ValueKey('landscape-avatar'));
    expect(tester.getCenter(avatar), within(distance: 0.5, from: const Offset(91, 93)));
    final title = tester.getRect(find.byKey(const ValueKey('landscape-title')));
    final more = centre(tester, 'landscape-more');

    details
      ..actions = FakeVideoActions()
      ..changed();
    await tester.pumpAndSettle();
    expect(centre(tester, 'landscape-like'), within(distance: 0.5, from: const Offset(555, 42)));
    expect(find.byKey(const ValueKey('landscape-follow')), findsOneWidget);
    expect(tester.getRect(find.byKey(const ValueKey('landscape-title'))), title);
    expect(centre(tester, 'landscape-more'), more);
    expect(tester.getCenter(avatar), within(distance: 0.5, from: const Offset(91, 93)));

    final next = FakeVideoActions(liked: true);
    details
      ..actions = next
      ..changed();
    await tester.pumpAndSettle();
    expect(iconOf(tester, 'landscape-like').color, BiliColors.pink);
    await tester.tap(find.byKey(const ValueKey('landscape-like')));
    expect(next.calls, ['toggleLike']);

    details
      ..actions = null
      ..changed();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('landscape-like')), findsNothing);
    expect(centre(tester, 'landscape-more'), more);
  });

  testWidgets('the actions and 关注 press through accessibility too, as VoiceOver and the Windows test driver do', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final actions = FakeVideoActions();
    final rig = Rig(details: FakePageDetails(actions: actions, online: '3'))..session.detail = detail;
    await rig.mount(tester);

    for (final label in ['点赞', '收藏', '投币', '分享', '关注']) {
      tester.semantics.tap(find.semantics.byLabel(label));
    }
    expect(actions.calls, ['toggleLike', 'ask favourites', 'ask coin', 'ask share', 'tapFollow']);
    tester.semantics.tap(find.semantics.byLabel('评论'));
    expect(rig.comments, 1);
    tester.semantics.tap(find.semantics.byLabel('充电'));
    await tester.pump();
    expect(find.text('暂不支持充电'), findsOneWidget);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    semantics.dispose();
  });

  testWidgets('hidden controls take the actions and the uploader with them', (tester) async {
    final actions = FakeVideoActions();
    final rig = Rig(details: FakePageDetails(actions: actions, online: '3'))..session.detail = detail;
    await rig.mount(tester);

    rig.chrome.hide();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('landscape-like')), warnIfMissed: false);
    await tester.tap(find.byKey(const ValueKey('landscape-follow')), warnIfMissed: false);
    expect(actions.calls, isEmpty);
    for (final key in ['landscape-like', 'landscape-online']) {
      final fade = tester.widget<AnimatedOpacity>(
        find.ancestor(of: find.byKey(ValueKey(key)), matching: find.byType(AnimatedOpacity)).first,
      );
      expect(fade.opacity, 0, reason: key);
    }
  });

  group('the drawn status bar (04, 05)', () {
    const charging = DeviceStatus(battery: 0.85, charging: true, network: StatusNetwork.wifi);

    testWidgets('the time centred at the top; WIFI, the level and the battery at the right, as on 05', (tester) async {
      final rig = Rig(statusBar: FixedStatusBarFeed(charging));
      await rig.mount(tester);

      expect(tester.takeException(), isNull);
      final time = find.byKey(const ValueKey('status-time'));
      expect(tester.getCenter(time).dx, closeTo(478, 0.01));
      expect(baselineOf(tester, time), closeTo(LandscapeStatusTheme.timeBaseline, 0.01));
      expect(tester.widget<Text>(time).style!.fontSize, LandscapeStatusTheme.timeText);

      // The cap ends 11 pt inside the island's 62.
      final battery = tester.getRect(find.byType(BatteryGlyph));
      expect(battery, rectMoreOrLessEquals(const Rect.fromLTWH(863, 5, 20, 10), epsilon: 0.01));
      final level = find.text('85%');
      expect(baselineOf(tester, level), closeTo(LandscapeStatusTheme.smallBaseline, 0.01));
      expect(battery.left - tester.getTopRight(level).dx, closeTo(LandscapeStatusTheme.batteryGap, 0.01));
      final wifi = tester.getRect(find.byKey(const ValueKey('status-wifi')));
      expect(wifi.size, const Size(LandscapeStatusTheme.capsuleWidth, LandscapeStatusTheme.capsuleHeight));
      expect(wifi.center.dy, closeTo(LandscapeStatusTheme.centre, 0.01));
      expect(tester.getTopLeft(level).dx - wifi.right, closeTo(LandscapeStatusTheme.capsuleGap, 0.01));
      expect(baselineOf(tester, find.text('WIFI')), closeTo(LandscapeStatusTheme.smallBaseline, 0.01));
      expect(tester.getCenter(find.text('WIFI')).dx, closeTo(wifi.center.dx, 0.01));

      expect(centre(tester, 'landscape-back'), within(distance: 1, from: const Offset(89, 42)), reason: 'unmoved');
      expect(centre(tester, 'landscape-more'), within(distance: 1, from: const Offset(867, 42)));
    });

    testWidgets('it goes with the top bar: away with the controls and under a panel, as 25 and 05 show none', (
      tester,
    ) async {
      final rig = Rig(statusBar: FixedStatusBarFeed(charging));
      await rig.mount(tester);
      Finder slideOf(String key) =>
          find.ancestor(of: find.byKey(ValueKey(key)), matching: find.byType(AnimatedSlide)).first;
      double fade() => tester
          .widget<AnimatedOpacity>(
            find.ancestor(of: find.byKey(const ValueKey('status-time')), matching: find.byType(AnimatedOpacity)).first,
          )
          .opacity;
      expect(slideOf('status-time').evaluate().single, same(slideOf('landscape-back').evaluate().single));
      expect(fade(), 1);

      rig.chrome.hide();
      await tester.pumpAndSettle();
      expect(fade(), 0);
      expect(tester.widget<AnimatedSlide>(slideOf('status-time')).offset, const Offset(0, -BiliMetrics.chromeSlide));

      rig.chrome.show();
      await tester.pumpAndSettle();
      expect(fade(), 1);

      rig.panels.open(PlayerPanel.speed);
      await tester.pumpAndSettle();
      expect(fade(), 0);
    });

    testWidgets('outside a video page there is none', (tester) async {
      await Rig().mount(tester);
      expect(find.byKey(const ValueKey('status-time')), findsNothing);
      expect(find.byType(BatteryGlyph), findsNothing);
    });

    testWidgets('the chrome watches the feed while it is up and lets go when it leaves', (tester) async {
      final feed = CountingStatusFeed(charging);
      final rig = Rig(statusBar: feed);
      await rig.mount(tester);
      expect(feed.calls, [true]);

      rig.chrome.hide();
      await tester.pumpAndSettle();
      expect(feed.calls, [true], reason: 'the level stays current for when the controls come back');

      await tester.pumpWidget(const SizedBox());
      expect(feed.calls, [true, false]);
    });
  });

  test('speedLabel', () {
    expect(speedLabel(1), '倍速');
    expect(speedLabel(3), '3.0X');
    expect(speedLabel(0.5), '0.5X');
  });

  group('danmaku (04, 34)', () {
    Rect fieldRect(WidgetTester tester) => tester.getRect(
      find.descendant(of: find.byKey(const ValueKey('landscape-danmaku-field')), matching: find.byType(Container)),
    );

    testWidgets('弹幕设置 and the field follow the toggle as on 04, the field running to 倍速', (tester) async {
      final rig = Rig(danmaku: DanmakuRig());
      await rig.mount(tester);

      expect(tester.takeException(), isNull);
      expect(centre(tester, 'landscape-danmaku-settings'), within(distance: 1, from: const Offset(182, 396)));
      expect(find.byType(DanmakuSettingsGlyph), findsOneWidget);
      final field = fieldRect(tester);
      expect(field.left, closeTo(208, 0.5));
      expect(field.height, BiliMetrics.chromeFieldHeight);
      expect(field.center.dy, closeTo(396, 1));
      final speed = tester.getTopLeft(find.byKey(const ValueKey('landscape-speed'))).dx;
      expect(field.right, closeTo(speed - BiliMetrics.chromeSpeedGap, 0.5));
      expect(find.text('发个友善的弹幕见证当下'), findsOneWidget);
    });

    testWidgets('弹幕设置 opens its panel and the field the send bar, each keeping the controls up', (tester) async {
      final danmaku = DanmakuRig();
      final rig = Rig(danmaku: danmaku);
      await rig.mount(tester);

      await tester.tap(find.byKey(const ValueKey('landscape-danmaku-settings')));
      expect(rig.panels.value, PlayerPanel.danmakuSettings);
      expect(rig.chrome.shows, 1);

      rig.panels.close();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('landscape-danmaku-field')));
      expect(danmaku.session.sendOpen.value, isTrue);
      expect(rig.chrome.shows, 2);
    });

    testWidgets('both answer accessibility presses by name', (tester) async {
      final danmaku = DanmakuRig();
      final rig = Rig(danmaku: danmaku);
      await rig.mount(tester);

      tester.semantics.tap(find.semantics.byLabel('弹幕设置'));
      expect(rig.panels.value, PlayerPanel.danmakuSettings);
      rig.panels.close();
      await tester.pumpAndSettle();
      tester.semantics.tap(find.semantics.byLabel('发个友善的弹幕见证当下'));
      expect(danmaku.session.sendOpen.value, isTrue);
    });

    testWidgets('logged out, the field asks for the login instead', (tester) async {
      final danmaku = DanmakuRig(loggedIn: false);
      await Rig(danmaku: danmaku).mount(tester);

      await tester.tap(find.byKey(const ValueKey('landscape-danmaku-field')));
      expect(danmaku.logins, 1);
      expect(danmaku.session.sendOpen.value, isFalse);
    });

    testWidgets('with danmaku off both are gone and the row closes up behind the toggle, as on 34', (tester) async {
      final rig = Rig(danmaku: DanmakuRig());
      await rig.mount(tester);
      final speed = centre(tester, 'landscape-speed');

      await tester.tap(find.byKey(const ValueKey('landscape-danmaku')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('landscape-danmaku-settings')), findsNothing);
      expect(find.byKey(const ValueKey('landscape-danmaku-field')), findsNothing);
      expect(centre(tester, 'landscape-danmaku'), within(distance: 1, from: const Offset(134, 396)));
      expect(centre(tester, 'landscape-speed'), speed);

      await tester.tap(find.byKey(const ValueKey('landscape-danmaku')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('landscape-danmaku-field')), findsOneWidget);
    });

    testWidgets('with the uploader\'s danmaku closed the field reads UP主已关闭弹幕 and opens nothing', (tester) async {
      final danmaku = DanmakuRig(closed: true);
      final rig = Rig(danmaku: danmaku);
      await rig.mount(tester);

      expect(find.text('UP主已关闭弹幕'), findsOneWidget);
      expect(find.text('发个友善的弹幕见证当下'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('landscape-danmaku-field')));
      expect(danmaku.session.sendOpen.value, isFalse);
      expect(rig.chrome.shows, 1, reason: 'a tap still keeps the controls up');
      expect(find.byKey(const ValueKey('landscape-danmaku-settings')), findsOneWidget);
    });

    testWidgets('outside a video page neither shows', (tester) async {
      await Rig().mount(tester);
      expect(find.byKey(const ValueKey('landscape-danmaku-settings')), findsNothing);
      expect(find.byKey(const ValueKey('landscape-danmaku-field')), findsNothing);
    });
  });

  group('the seek preview (102)', () {
    double fade(WidgetTester tester, String key) => tester
        .widget<AnimatedOpacity>(find.ancestor(of: find.byKey(ValueKey(key)), matching: find.byType(AnimatedOpacity)).first)
        .opacity;

    double previewOpacity(WidgetTester tester) =>
        tester.widget<AnimatedOpacity>(find.byKey(const ValueKey('seek-preview'))).opacity;

    testWidgets('holding the bar fades everything but the bar for the time, asks for the frames, and lifting brings them back', (
      tester,
    ) async {
      final rig = Rig();
      rig.session.duration.value = 251;
      await rig.mount(tester);
      await tester.pumpAndSettle();
      expect(previewOpacity(tester), 0);

      final bar = tester.getCenter(find.byKey(const ValueKey('landscape-bar')));
      final finger = await tester.startGesture(bar);
      await finger.moveBy(const Offset(30, 0));
      await tester.pumpAndSettle();
      expect(rig.session.calls, contains('wantSeekFrames'));
      expect(previewOpacity(tester), 1);
      for (final key in ['landscape-back', 'landscape-play', 'landscape-time', 'landscape-speed']) {
        expect(fade(tester, key), 0, reason: key);
      }
      expect(fade(tester, 'landscape-bar'), 1, reason: 'the bar stays under the finger');
      expect(find.byKey(const ValueKey('seek-preview-frame')), findsNothing, reason: 'no frames yet: the time alone');
      final time = tester.getRect(find.byKey(const ValueKey('seek-preview-time')));
      expect(time.center.dy, closeTo(220 - 36 + 95 + 15 + 7.5, 1));

      await finger.up();
      await tester.pumpAndSettle();
      expect(previewOpacity(tester), 0);
      expect(fade(tester, 'landscape-back'), 1);
      expect(rig.chrome.barHeld, isFalse);
    });

    testSheets("the frame for the dragged time, 170 × 95 with the measured border, from its sheet's cell", (
      tester,
    ) async {
      final rig = Rig();
      rig.session
        ..duration.value = 100
        ..seekFrames.value = const VideoShot(
          sheets: ['https://i0.hdslb.com/bfs/videoshot/a.jpg', 'https://i0.hdslb.com/bfs/videoshot/b.jpg'],
          columns: 2,
          rows: 2,
          times: [0, 0, 5, 10, 15, 20, 25],
        );
      await rig.mount(tester);
      final finger = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('landscape-bar'))));
      await finger.moveBy(const Offset(20, 0));
      rig.session.scrubbing.value = 12;
      await tester.pumpAndSettle();

      final box = tester.getRect(find.byKey(const ValueKey('seek-preview-frame')));
      expect(box.size, const Size(170, 95));
      expect(box.center.dx, 478);
      expect(box.top, 184);
      final cell = tester.widget<Transform>(
        find.descendant(of: find.byKey(const ValueKey('seek-preview-frame')), matching: find.byType(Transform)),
      );
      final shift = cell.transform.getTranslation();
      expect((shift.x, shift.y), (0.0, -93.0), reason: '12 s is the third frame: column 0, row 1 of the first sheet');
      expect(
        tester.widget<Image>(find.byType(Image).last).image,
        isA<NetworkImage>().having((image) => image.url, 'url', 'https://i0.hdslb.com/bfs/videoshot/a.jpg'),
      );
      final text = tester.widget<Text>(find.byKey(const ValueKey('seek-preview-time'))).textSpan!.toPlainText();
      expect(text, '00:12/01:40');

      rig.session.scrubbing.value = 22;
      await tester.pump();
      expect(
        tester.widget<Image>(find.byType(Image).last).image,
        isA<NetworkImage>().having((image) => image.url, 'url', 'https://i0.hdslb.com/bfs/videoshot/b.jpg'),
      );
      await finger.up();
      await tester.pumpAndSettle();
    });
  });
}
