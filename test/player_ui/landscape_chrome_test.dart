import 'package:bili_core/api.dart' show QualityOption, UploaderCard, VideoDetail;
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/landscape_chrome.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/shared/action_glyphs.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/player_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player_session.dart';
import '../support/fake_video_actions.dart';

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
  Rig({this.details});

  final session = FakePlayerSession();
  final chrome = CountingChrome();
  final panels = PanelController();
  final orientation = OrientationController()..enterLandscape();
  final FakePageDetails? details;
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

Offset centre(WidgetTester tester, String key) => tester.getCenter(find.byKey(ValueKey(key)));

final detail = VideoDetail.fromJson({
  'bvid': 'BV1',
  'owner': {'mid': 1, 'name': 'PRORES 8K', 'face': ''},
});

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
    expect(centre(tester, 'landscape-capture'), within(distance: 1.5, from: const Offset(873, 178.5)));
    expect(centre(tester, 'landscape-lock'), within(distance: 1.5, from: const Offset(873, 231.5)));
    expect(centre(tester, 'landscape-play'), within(distance: 1, from: const Offset(84, 397)));
    expect(centre(tester, 'landscape-danmaku'), within(distance: 1, from: const Offset(134, 396)));
    expect(centre(tester, 'landscape-bar').dy, closeTo(359, 1));
    expect(tester.getTopLeft(find.byKey(const ValueKey('landscape-bar'))).dx, 62);
    expect(tester.getTopRight(find.byKey(const ValueKey('landscape-bar'))).dx, 894);
    expect(tester.getTopLeft(find.byKey(const ValueKey('landscape-time'))).dx, 63);
    // The title stops short of where 点赞…分享 go.
    expect(tester.getTopRight(find.byKey(const ValueKey('landscape-title'))).dx, lessThanOrEqualTo(509));
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

  testWidgets('选集 shows only with episodes, and opens the episodes panel', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    expect(find.byKey(const ValueKey('landscape-episodes')), findsNothing);

    rig.session
      ..episodes = const [
        Episode(bvid: 'BV1', cid: 1, title: 'P1', current: true),
        Episode(bvid: 'BV1', cid: 2, title: 'P2', current: false),
      ]
      ..changed();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('landscape-episodes')));
    expect(rig.panels.value, PlayerPanel.episodes);
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
    final fades = tester.widgetList<AnimatedOpacity>(find.descendant(of: root, matching: find.byType(AnimatedOpacity)));
    expect(fades.map((fade) => fade.opacity), everyElement(0));
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
    expect(tester.getTopLeft(countOf('landscape-like', '30')), within(distance: 0.5, from: const Offset(561.7, 25.5)));
    expect(tester.getTopLeft(countOf('landscape-favourite', '38')).dx, closeTo(665.7, 0.5));
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

  testWidgets('the uploader under it: avatar and a white + 关注 that follows; 已关注 is grey with no plus', (
    tester,
  ) async {
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
    expect(tester.getTopLeft(find.text('关注')).dx, closeTo(126.4, 1));
    expect(tester.getCenter(find.text('关注')).dy, closeTo(93, 1));
    expect(tester.widget<Text>(find.text('关注')).style!.color, BiliColors.onVideo);
    final follow = find.byKey(const ValueKey('landscape-follow'));
    expect(find.descendant(of: follow, matching: find.byType(CustomPaint)), findsOneWidget);

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
    expect(tester.getCenter(avatar), within(distance: 0.5, from: const Offset(91, 93)));
    expect(find.bySemanticsLabel('已关注'), findsOneWidget);
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

  test('speedLabel', () {
    expect(speedLabel(1), '倍速');
    expect(speedLabel(3), '3.0X');
    expect(speedLabel(0.5), '0.5X');
  });
}
