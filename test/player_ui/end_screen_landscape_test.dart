import 'package:bili_core/api.dart' show UploaderCard, VideoCard, VideoDetail;
import 'package:bili_core/devlog.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/end_screen_landscape.dart';
import 'package:bilifast/player_ui/end_screen_portrait.dart' show CountGlyph, CountPainter;
import 'package:bilifast/player_ui/landscape_chrome.dart' show LandscapeCornerOnline;
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/shared/action_glyphs.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player_session.dart';
import '../support/fake_video_actions.dart';

VideoCard card(int n) => VideoCard(
  aid: n,
  bvid: 'BV$n',
  cid: n,
  title: '推荐 $n',
  cover: '',
  duration: 48,
  ownerMid: n,
  ownerName: 'UP $n',
  views: 1357000,
  danmaku: 284,
  likes: 0,
);

/// The end screen at 27's size: 956 × 440 pt, 62 each side, 21 below.
final class Rig {
  Rig({this.details});

  final session = FakePlayerSession()..shareLink = Uri.parse('https://www.bilibili.com/video/BV1xx411c7mD');
  final chrome = ChromeState();
  final panels = PanelController();
  final orientation = OrientationController()..enterLandscape();
  final shared = <Uri>[];
  final FakePageDetails? details;
  int backs = 0;

  late final ui = PlayerUi(
    session: session,
    chrome: chrome,
    panels: panels,
    orientation: orientation,
    device: orientation.controls,
    onBack: () => backs += 1,
    details: details,
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
        home: EndScreenLandscape(ui: ui, share: (link) async {
          shared.add(link);
          return true;
        }),
      ),
    );
    await tester.pumpAndSettle();
  }
}

Offset centre(WidgetTester tester, String key) => tester.getCenter(find.byKey(ValueKey(key)));

void main() {
  testWidgets('lays out as 27: back, 重播 | 分享 at the right, then 推荐视频 in a row', (tester) async {
    final rig = Rig()..session.related = [card(1), card(2), card(3), card(4), card(5)];
    await rig.mount(tester);

    expect(tester.takeException(), isNull);
    expect(centre(tester, 'end-back'), within(distance: 1, from: const Offset(84, 22)));
    expect(tester.getSize(find.byKey(const ValueKey('end-back'))), const Size(44, 44));
    expect(centre(tester, 'end-replay').dx, closeTo(604, 2));
    expect(centre(tester, 'end-share').dx, closeTo(866.5, 1));
    expect(centre(tester, 'end-divider').dx, closeTo(647.3, 0.5));
    expect(find.text('推荐视频'), findsOneWidget);
    expect(tester.getTopLeft(find.text('推荐 1')).dx, closeTo(74, 1));
    expect(find.text('0:48'), findsWidgets);
    expect(find.text('135.7万'), findsWidgets);
  });

  testWidgets("27's rules: 1 pt, the divider 48 tall around y 93", (tester) async {
    final rig = Rig();
    await rig.mount(tester);

    final divider = find.byKey(const ValueKey('end-divider'));
    expect(tester.getSize(divider), const Size(1, 48));
    expect(tester.getCenter(divider).dy, closeTo(93, 0.5));
    expect(BiliMetrics.landscapeEndRule, 1);
  });

  testWidgets("the counts on a cover are white, with the portrait end screen's icons", (tester) async {
    final rig = Rig()..session.related = [card(1)];
    await rig.mount(tester);

    final icons = [
      for (final paint in tester.widgetList<CustomPaint>(find.byType(CustomPaint)))
        if (paint.painter case final CountPainter painter) (painter, paint.size),
    ];
    expect([for (final (painter, _) in icons) painter.glyph], [CountGlyph.views, CountGlyph.danmaku]);
    for (final (painter, size) in icons) {
      expect(painter.color, BiliColors.onVideo);
      expect(size, const Size(BiliMetrics.landscapeEndCountIconWidth, BiliMetrics.landscapeEndCountIconHeight));
    }
    expect(find.byType(Icon), findsNothing);
    for (final count in ['135.7万', '284', '0:48']) {
      expect(tester.widget<Text>(find.text(count)).style?.color, BiliColors.onVideo);
    }
  });

  testWidgets('重播 replays, back goes back', (tester) async {
    final rig = Rig();
    await rig.mount(tester);

    await tester.tap(find.byKey(const ValueKey('end-replay')));
    expect(rig.session.calls, ['replay']);
    await tester.tap(find.byKey(const ValueKey('end-back')));
    expect(rig.backs, 1);
  });

  testWidgets('分享 hands the link to the share seam, and is gone without a link', (tester) async {
    final rig = Rig();
    await rig.mount(tester);

    await tester.tap(find.byKey(const ValueKey('end-share')));
    expect(rig.shared, [Uri.parse('https://www.bilibili.com/video/BV1xx411c7mD')]);

    rig.session
      ..shareLink = null
      ..changed();
    await tester.pump();
    expect(find.byKey(const ValueKey('end-share')), findsNothing);
    expect(centre(tester, 'end-replay').dx, closeTo(604, 2));
  });

  testWidgets('a share that fails is logged with its error and toasts 分享失败', (tester) async {
    final logs = MemorySink();
    Logger.shared.add(logs);
    addTearDown(() => Logger.shared.remove(logs));
    final rig = Rig();
    tester.view
      ..physicalSize = const Size(956, 440)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() {
      rig.chrome.dispose();
      rig.panels.dispose();
      rig.orientation.dispose();
      rig.session.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: EndScreenLandscape(ui: rig.ui, share: (_) async => throw StateError('no share sheet')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('end-share')));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('分享失败'), findsOneWidget);
    final failure = logs.events.singleWhere((event) => event.msg == 'share failed');
    expect(failure.f['error']?.toJson(), 'Bad state: no share sheet');
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('分享失败'), findsNothing);
  });

  testWidgets('the uploader shows with the detail, and the text is sized as on 27', (tester) async {
    final rig = Rig()
      ..session.related = [card(1)]
      ..session.detail = VideoDetail.fromJson({
        'bvid': 'BV1',
        'owner': {'mid': 1, 'name': '不科学の小石头', 'face': ''},
      });
    await rig.mount(tester);

    expect(find.text('不科学の小石头'), findsOneWidget);
    final avatar = find.descendant(of: find.byKey(const ValueKey('end-uploader')), matching: find.byType(ClipOval));
    expect(tester.getCenter(avatar), within(distance: 1, from: const Offset(104, 93)));
    expect(tester.getTopLeft(find.text('不科学の小石头')).dx, closeTo(146, 1));

    double sizeOf(String text) => tester.widget<Text>(find.text(text)).style!.fontSize!;
    expect(sizeOf('推荐视频'), 14);
    expect(sizeOf('推荐 1'), 12);
    expect(sizeOf('UP 1'), 10);
    expect(sizeOf('0:48'), 11);
    expect(sizeOf('重播'), 12);
    expect(sizeOf('分享'), 12);
    final badge = find.ancestor(of: find.text('UP'), matching: find.byType(Container)).first;
    expect(tester.getSize(badge).width, closeTo(13, 0.5));
  });

  testWidgets('the faint N人正在看 stays at the bottom left under the dim, as on 27', (tester) async {
    final details = FakePageDetails(online: '1');
    final rig = Rig(details: details);
    await rig.mount(tester);

    final corner = find.byKey(const ValueKey('landscape-corner-online'));
    expect(corner, findsOneWidget);
    expect(tester.getTopLeft(corner).dx, closeTo(95.3, 0.5));
    expect(tester.getCenter(corner).dy, closeTo(430.3, 0.5));
    expect(corner.hitTestable(), findsNothing);
    final layers = tester.widget<Stack>(find.byKey(const ValueKey('end-landscape-layers')));
    final under = layers.children.first as Opacity;
    expect(under.child, isA<LandscapeCornerOnline>(), reason: 'painted before the dim, so it sits under it');
    expect(under.opacity, LandscapeActionTheme.cornerUnderEndOpacity, reason: '27 dims it further than the dim alone');

    details.online.value = null;
    await tester.pumpAndSettle();
    expect(corner, findsNothing);
  });

  testWidgets('a related video plays on tap; without any, 推荐视频 is not shown', (tester) async {
    final rig = Rig()..session.related = [card(1), card(2)];
    await rig.mount(tester);

    await tester.tap(find.text('推荐 2'));
    expect(rig.session.calls, ['playRelated BV2']);

    rig.session
      ..related = const []
      ..changed();
    await tester.pump();
    expect(find.text('推荐视频'), findsNothing);
  });

  testWidgets('the cards rise in one after another', (tester) async {
    final rig = Rig()..session.related = [card(1), card(2), card(3)];
    tester.view
      ..physicalSize = const Size(956, 440)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() {
      rig.chrome.dispose();
      rig.panels.dispose();
      rig.orientation.dispose();
      rig.session.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: EndScreenLandscape(ui: rig.ui, share: (_) async => true),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    double opacityOf(String title) =>
        tester.widget<Opacity>(find.ancestor(of: find.text(title), matching: find.byType(Opacity)).first).opacity;
    expect(opacityOf('推荐 1'), greaterThan(opacityOf('推荐 3')));
    await tester.pumpAndSettle();
    expect(opacityOf('推荐 3'), 1);
  });

  testWidgets('点赞 投币 收藏 fill the room between the divider and 分享 as on 27, outlined and white', (tester) async {
    final rig = Rig(details: FakePageDetails(actions: FakeVideoActions()))..session.detail = detail;
    await rig.mount(tester);

    expect(tester.takeException(), isNull);
    expect(centre(tester, 'end-like').dx, closeTo(689, 1.5));
    expect(centre(tester, 'end-coin').dx, closeTo(749, 1.5));
    expect(centre(tester, 'end-favourite').dx, closeTo(809, 1.5));
    expect(centre(tester, 'end-replay').dx, closeTo(604, 2));
    expect(centre(tester, 'end-share').dx, closeTo(866.5, 1));
    expect(centre(tester, 'end-divider').dx, closeTo(647.3, 0.5));
    for (final key in ['end-like', 'end-coin', 'end-favourite']) {
      expect(iconOf(tester, key).solid, isFalse, reason: key);
      expect(iconOf(tester, key).color, BiliColors.onVideo, reason: key);
      final icon = find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(ActionIcon));
      expect(tester.getCenter(icon).dy, closeTo(80, 1.5), reason: key);
    }
    for (final label in ['点赞', '投币', '收藏']) {
      expect(tester.widget<Text>(find.text(label)).style!.fontSize, 12, reason: label);
      expect(tester.getCenter(find.text(label)).dy, tester.getCenter(find.text('重播')).dy, reason: label);
    }
  });

  testWidgets('点赞 likes, 投币 and 收藏 ask for their sheets, 分享 goes through the actions so it is counted', (
    tester,
  ) async {
    final actions = FakeVideoActions();
    final rig = Rig(details: FakePageDetails(actions: actions))..session.detail = detail;
    await rig.mount(tester);

    await tester.tap(find.byKey(const ValueKey('end-like')));
    await tester.tap(find.byKey(const ValueKey('end-coin')));
    await tester.tap(find.byKey(const ValueKey('end-favourite')));
    await tester.tap(find.byKey(const ValueKey('end-share')));
    expect(actions.calls, ['toggleLike', 'ask coin', 'ask favourites', 'ask share']);
    expect(rig.shared, isEmpty);
  });

  testWidgets('liked, coined and favourited turn solid pink; the labels stay white', (tester) async {
    final actions = FakeVideoActions();
    final rig = Rig(details: FakePageDetails(actions: actions))..session.detail = detail;
    await rig.mount(tester);

    actions
      ..liked = true
      ..coins = 2
      ..favorited = true
      ..changed();
    await tester.pumpAndSettle();
    for (final key in ['end-like', 'end-coin', 'end-favourite']) {
      expect(iconOf(tester, key).solid, isTrue, reason: key);
      expect(iconOf(tester, key).color, BiliColors.pink, reason: key);
    }
    expect(tester.widget<Text>(find.text('点赞')).style!.color, BiliColors.onVideo);
    expect(find.bySemanticsLabel('取消点赞'), findsOneWidget);
    expect(find.bySemanticsLabel('已投币'), findsOneWidget);
    expect(find.bySemanticsLabel('已收藏'), findsOneWidget);

    actions
      ..coins = 0
      ..changed();
    await tester.pumpAndSettle();
    expect(iconOf(tester, 'end-coin').color, BiliColors.onVideo);
  });

  testWidgets("under the name: 充电's pink outline and 关注's pink pill, as on 27", (tester) async {
    final rig = Rig(details: FakePageDetails(actions: FakeVideoActions()))..session.detail = detail;
    await rig.mount(tester);

    final charge = find.byKey(const ValueKey('end-charge'));
    final follow = find.byKey(const ValueKey('end-follow'));
    expect(tester.getRect(charge), rectMoreOrLessEquals(const Rect.fromLTRB(146, 93, 234, 123), epsilon: 0.5));
    expect(tester.getRect(follow), rectMoreOrLessEquals(const Rect.fromLTRB(242, 93, 330, 123), epsilon: 0.5));
    final outline = tester.widget<Container>(find.descendant(of: charge, matching: find.byType(Container)));
    final border = (outline.decoration! as BoxDecoration).border! as Border;
    expect(border.top.color, BiliColors.pink);
    expect(border.top.width, 1);
    expect(tester.widget<Text>(find.text('充电')).style!.color, BiliColors.pink);
    expect(tester.widget<Text>(find.text('充电')).style!.fontSize, 14);
    final fill = tester.widget<AnimatedContainer>(find.descendant(of: follow, matching: find.byType(AnimatedContainer)));
    expect((fill.decoration! as BoxDecoration).color, BiliColors.pink);
    expect(tester.widget<Text>(find.text('关注')).style!.color, BiliColors.onPink);
    expect(tester.getCenter(find.text('关注')).dx, closeTo(293.3, 1.5));
    // The name stays where it was before the pills came.
    expect(tester.getTopLeft(find.text('不科学の小石头')).dx, closeTo(146, 1));
  });

  testWidgets('充电 toasts that it is not supported; 关注 follows, and 已关注 is a grey pill', (tester) async {
    final actions = FakeVideoActions();
    final rig = Rig(details: FakePageDetails(actions: actions))..session.detail = detail;
    await rig.mount(tester);

    await tester.tap(find.byKey(const ValueKey('end-charge')));
    await tester.pump();
    expect(find.text('暂不支持充电'), findsOneWidget);
    expect(actions.calls, isEmpty);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.byKey(const ValueKey('end-follow')));
    expect(actions.calls, ['tapFollow']);

    actions
      ..following = true
      ..changed();
    await tester.pumpAndSettle();
    final follow = find.byKey(const ValueKey('end-follow'));
    expect(find.descendant(of: follow, matching: find.text('已关注')), findsOneWidget);
    expect(find.text('关注'), findsNothing);
    final fill = tester.widget<AnimatedContainer>(find.descendant(of: follow, matching: find.byType(AnimatedContainer)));
    expect((fill.decoration! as BoxDecoration).color, LandscapeActionTheme.followedPill);
    expect(tester.widget<Text>(find.text('已关注')).style!.color, LandscapeActionTheme.followed);
    expect(tester.getRect(follow), rectMoreOrLessEquals(const Rect.fromLTRB(242, 93, 330, 123), epsilon: 0.5));
  });

  testWidgets('before the actions arrive their room stays empty and 充电 alone shows; then they come in place', (
    tester,
  ) async {
    final details = FakePageDetails();
    final rig = Rig(details: details)..session.detail = detail;
    await rig.mount(tester);

    for (final key in ['end-like', 'end-coin', 'end-favourite', 'end-follow']) {
      expect(find.byKey(ValueKey(key)), findsNothing, reason: key);
    }
    expect(find.byKey(const ValueKey('end-charge')), findsOneWidget);
    final replay = centre(tester, 'end-replay');
    final share = centre(tester, 'end-share');
    final charge = tester.getRect(find.byKey(const ValueKey('end-charge')));

    await tester.tap(find.byKey(const ValueKey('end-share')));
    expect(rig.shared, hasLength(1), reason: 'without actions 分享 shares by itself');

    final actions = FakeVideoActions();
    details
      ..actions = actions
      ..changed();
    await tester.pumpAndSettle();
    expect(centre(tester, 'end-like').dx, closeTo(689, 1.5));
    expect(find.byKey(const ValueKey('end-follow')), findsOneWidget);
    expect(centre(tester, 'end-replay'), replay);
    expect(centre(tester, 'end-share'), share);
    expect(tester.getRect(find.byKey(const ValueKey('end-charge'))), charge);

    actions
      ..liked = true
      ..changed();
    await tester.pumpAndSettle();
    expect(iconOf(tester, 'end-like').color, BiliColors.pink);
  });

  testWidgets("without the session's detail the uploader comes from the page details", (tester) async {
    final rig = Rig(
      details: FakePageDetails(
        actions: FakeVideoActions(),
        uploader: const UploaderCard(
          mid: 9,
          name: '不科学の小石头',
          face: '',
          fans: 0,
          videos: 0,
          isVip: false,
          following: false,
        ),
      ),
    );
    await rig.mount(tester);

    expect(find.text('不科学の小石头'), findsOneWidget);
    expect(find.byKey(const ValueKey('end-follow')), findsOneWidget);
  });

  testWidgets('the actions and the pills press through accessibility too, as VoiceOver and the Windows test driver do',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final actions = FakeVideoActions();
    final rig = Rig(details: FakePageDetails(actions: actions))..session.detail = detail;
    await rig.mount(tester);

    for (final label in ['点赞', '投币', '收藏', '分享', '关注']) {
      tester.semantics.tap(find.semantics.byLabel(label));
    }
    expect(actions.calls, ['toggleLike', 'ask coin', 'ask favourites', 'ask share', 'tapFollow']);
    tester.semantics.tap(find.semantics.byLabel('充电'));
    await tester.pump();
    expect(find.text('暂不支持充电'), findsOneWidget);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    semantics.dispose();
  });
}

final detail = VideoDetail.fromJson({
  'bvid': 'BV1',
  'owner': {'mid': 1, 'name': '不科学の小石头', 'face': ''},
});

ActionIcon iconOf(WidgetTester tester, String key) =>
    tester.widget<ActionIcon>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(ActionIcon)));
