import 'package:bili_core/api.dart'
    show BiliClient, CookieJar, HTTPRequest, HTTPResponse, HTTPTransport, UploaderCard, VideoDetail;
import 'package:bili_core/devlog.dart' show Logger;
import 'package:bilifast/danmaku/block_rule_store.dart';
import 'package:bilifast/danmaku/danmaku_session.dart';
import 'package:bilifast/danmaku/danmaku_settings_store.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/playback/danmaku_feed.dart';
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/player_ui/vertical_chrome.dart';
import 'package:bilifast/shared/action_glyphs.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
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

/// 竖屏 on an upright iPhone 17 Pro Max (440 × 956 pt, 62 above for the island, 34 below), the size 09 was taken at.
final class Rig {
  final session = FakePlayerSession();
  final chrome = CountingChrome();
  final panels = PanelController();
  final orientation = OrientationController()..enterVertical();
  int backs = 0;
  int comments = 0;

  /// Set before [mount]; null is a player outside a video page.
  FakePageDetails? details;

  /// Set before [mount]; null is a player outside a video page.
  DanmakuRig? danmaku;

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
  );

  Future<void> mount(WidgetTester tester, {bool still = false}) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    addTearDown(() {
      chrome.dispose();
      panels.dispose();
      orientation.dispose();
      session.dispose();
      details?.dispose();
      danmaku?.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: still),
            child: ColoredBox(
              color: Colors.black,
              child: VerticalChrome(ui: ui),
            ),
          ),
        ),
      ),
    );
  }
}

VideoDetail detail({int reply = 239}) => VideoDetail.fromJson({
  'bvid': 'BV1',
  'title': '【VIT赛后】我们接受了LOUD的回溯！！',
  'owner': {'mid': 1, 'name': '我们一起去养猪', 'face': ''},
  'stat': {'view': 56000, 'reply': reply, 'like': 352, 'coin': 12, 'favorite': 59, 'share': 136},
});

UploaderCard uploader({int fans = 6129, bool vip = true}) => UploaderCard(
  mid: 1,
  name: '我们一起去养猪',
  face: '',
  fans: fans,
  videos: 10,
  isVip: vip,
  following: false,
);

FakeVideoActions actions09() => FakeVideoActions(likeCount: 352, coinCount: 12, favCount: 59, shareCount: 136);

/// 09's video with everything the page details bring.
Rig rig09() => Rig()
  ..session.title = '【VIT赛后】我们接受了LOUD的回溯！！'
  ..session.detail = detail()
  ..details = FakePageDetails(actions: actions09(), uploader: uploader(), online: '479');

FakeVideoActions actionsOf(Rig rig) => rig.details!.actions! as FakeVideoActions;

Color iconColour(WidgetTester tester, String key) =>
    tester.widget<ActionIcon>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(ActionIcon))).color;

Color? textColour(WidgetTester tester, Finder text) =>
    tester.widget<RichText>(find.descendant(of: text, matching: find.byType(RichText)).first).text.style?.color;

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
    toast: (_) {},
    requestLogin: () => logins += 1,
  );

  void dispose() {
    session.dispose();
    feed.dispose();
  }
}

Offset centre(WidgetTester tester, String key) => tester.getCenter(find.byKey(ValueKey(key)));

void main() {
  testWidgets('lays out as 09: back and ⋮ under the island, the title over the bar, the bottom row', (tester) async {
    final rig = Rig()..session.title = '【VIT赛后】我们接受了LOUD的回溯！！';
    await rig.mount(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('【VIT赛后】我们接受了LOUD的回溯！！'), findsOneWidget);
    expect(centre(tester, 'vertical-back'), within(distance: 1, from: const Offset(22, 76)));
    expect(centre(tester, 'vertical-more'), within(distance: 1, from: const Offset(418, 76)));
    expect(centre(tester, 'vertical-detail'), within(distance: 1, from: const Offset(368, 900)));
    expect(centre(tester, 'vertical-landscape'), within(distance: 1, from: const Offset(413, 900)));
    expect(centre(tester, 'vertical-danmaku'), within(distance: 1, from: const Offset(318, 900)));
    expect(centre(tester, 'vertical-bar').dy, closeTo(871, 1));
    expect(tester.getTopLeft(find.byKey(const ValueKey('vertical-bar'))).dx, 12);
    expect(tester.getTopRight(find.byKey(const ValueKey('vertical-bar'))).dx, 428);
    expect(tester.getTopLeft(find.byKey(const ValueKey('vertical-title'))).dx, 12);
    // The title stops short of where the action column goes.
    expect(tester.getTopRight(find.byKey(const ValueKey('vertical-title'))).dx, lessThanOrEqualTo(378));
    expect(find.text('详情页'), findsOneWidget);
  });

  testWidgets('the uploader and the plays come with the detail, where 09 has them', (tester) async {
    final rig = Rig()..session.title = '【VIT赛后】我们接受了LOUD的回溯！！';
    await rig.mount(tester);
    expect(find.byKey(const ValueKey('vertical-uploader')), findsNothing);
    expect(find.textContaining('播放', findRichText: true), findsNothing);

    rig.session
      ..detail = VideoDetail.fromJson({
        'bvid': 'BV1',
        'owner': {'mid': 1, 'name': '我们一起去养猪', 'face': ''},
        'stat': {'view': 56000},
      })
      ..changed();
    await tester.pump();

    expect(find.text('我们一起去养猪'), findsOneWidget);
    expect(find.textContaining('【VIT赛后】我们接受了LOUD的回溯！！', findRichText: true), findsOneWidget);
    expect(find.textContaining('5.6万播放', findRichText: true), findsOneWidget);
    final avatar = find.descendant(
      of: find.byKey(const ValueKey('vertical-uploader')),
      matching: find.byType(ClipOval),
    );
    expect(tester.getSize(avatar), const Size.square(36));
    expect(tester.getTopLeft(avatar).dx, 13);
    // 09 rings the avatar in 1 pt of white, inside its 36 pt.
    final ring = tester.widget<Container>(find.byKey(const ValueKey('vertical-avatar'))).foregroundDecoration!;
    expect(ring, isA<BoxDecoration>().having((d) => d.shape, 'shape', BoxShape.circle));
    final border = (ring as BoxDecoration).border! as Border;
    expect(border.top.color, BiliColors.onVideo);
    expect(border.top.width, 1);
    expect(border.top.strokeAlign, BorderSide.strokeAlignInside);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('vertical-title'))).dy - tester.getBottomLeft(avatar).dy,
      closeTo(9.7, 0.01),
    );
    expect(tester.getTopLeft(find.text('我们一起去养猪')).dx, closeTo(59, 1));
  });

  testWidgets('the 详情页 pill hugs its text, as on 09', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    final pill = find.ancestor(of: find.text('详情页'), matching: find.byType(Container)).first;
    expect(tester.getSize(pill).width, closeTo(31, 2));
    expect(tester.getCenter(pill), within(distance: 1, from: const Offset(377, 882.5)));
  });

  testWidgets('back and ⋮', (tester) async {
    final rig = Rig();
    await rig.mount(tester);

    await tester.tap(find.byKey(const ValueKey('vertical-back')));
    expect(rig.backs, 1);
    await tester.tap(find.byKey(const ValueKey('vertical-more')));
    expect(rig.panels.value, PlayerPanel.more);
    expect(rig.chrome.shows, 1);
  });

  testWidgets('详情页 goes back to the page and 横屏全屏 to landscape', (tester) async {
    final rig = Rig();
    await rig.mount(tester);

    await tester.tap(find.byKey(const ValueKey('vertical-detail')));
    expect(rig.orientation.presentation, Presentation.inline);
    expect(rig.chrome.shows, 1);

    rig.orientation.enterVertical();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('vertical-landscape')));
    expect(rig.orientation.presentation, Presentation.landscape);
    expect(rig.chrome.shows, 2);
  });

  testWidgets('弹 turns danmaku off and on and says which way it will go', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    expect(find.bySemanticsLabel('关闭弹幕'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('vertical-danmaku')));
    await tester.pumpAndSettle();
    expect(rig.session.calls, ['setDanmakuOn false']);
    expect(find.bySemanticsLabel('开启弹幕'), findsOneWidget);
  });

  group('发弹幕 (09, 35)', () {
    Finder field() => find.byKey(const ValueKey('vertical-danmaku-field'));

    testWidgets('reads 发弹幕 at the field\'s left, as on 09, and opens the send bar', (tester) async {
      final rig = Rig()..danmaku = DanmakuRig();
      await rig.mount(tester);

      final text = find.text('发弹幕');
      expect(text, findsOneWidget);
      expect(tester.getTopLeft(text).dx, closeTo(27, 1));
      // Centred on the field, then dropped to put MiSans's ink where 09's is.
      expect(tester.getCenter(text).dy, closeTo(901 + VerticalActionTheme.fieldDrop, 0.5));
      await tester.tap(field());
      expect(rig.danmaku!.session.sendOpen.value, isTrue);
      expect(rig.chrome.shows, 1);
    });

    testWidgets('answers an accessibility press by its name', (tester) async {
      final rig = Rig()..danmaku = DanmakuRig();
      await rig.mount(tester);
      tester.semantics.tap(find.semantics.byLabel('发弹幕'));
      expect(rig.danmaku!.session.sendOpen.value, isTrue);
    });

    testWidgets('logged out it asks for the login instead', (tester) async {
      final rig = Rig()..danmaku = DanmakuRig(loggedIn: false);
      await rig.mount(tester);
      await tester.tap(field());
      expect(rig.danmaku!.logins, 1);
      expect(rig.danmaku!.session.sendOpen.value, isFalse);
    });

    testWidgets('with danmaku off it reads 已关闭弹幕 and opens nothing, as on 35', (tester) async {
      final rig = Rig()..danmaku = DanmakuRig();
      await rig.mount(tester);
      await tester.tap(find.byKey(const ValueKey('vertical-danmaku')));
      await tester.pumpAndSettle();

      expect(find.text('已关闭弹幕'), findsOneWidget);
      expect(find.text('发弹幕'), findsNothing);
      await tester.tap(field());
      expect(rig.danmaku!.session.sendOpen.value, isFalse);
      expect(centre(tester, 'vertical-danmaku'), within(distance: 1, from: const Offset(318, 900)));
    });

    testWidgets('with the uploader\'s danmaku closed it reads UP主已关闭弹幕 and opens nothing', (tester) async {
      final rig = Rig()..danmaku = DanmakuRig(closed: true);
      await rig.mount(tester);

      expect(find.text('UP主已关闭弹幕'), findsOneWidget);
      await tester.tap(field());
      expect(rig.danmaku!.session.sendOpen.value, isFalse);
      expect(rig.chrome.shows, 1, reason: 'a tap still keeps the controls up');
    });
  });

  testWidgets('the bar scrubs and seeks', (tester) async {
    final rig = Rig();
    rig.session.duration.value = 100;
    await rig.mount(tester);

    await tester.dragFrom(centre(tester, 'vertical-bar'), const Offset(-80, 0));
    await tester.pumpAndSettle();
    expect(rig.session.calls.first, startsWith('scrub'));
    expect(rig.session.calls.last, startsWith('commitSeek'));
    expect(rig.chrome.shows, 1);
  });

  testWidgets('hidden controls fade out and take no touches; a panel hides them too', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    final root = find.byKey(const ValueKey('vertical-chrome'));

    rig.chrome.hide();
    await tester.pumpAndSettle();
    expect(tester.widget<IgnorePointer>(root).ignoring, isTrue);
    final fades = tester.widgetList<AnimatedOpacity>(find.descendant(of: root, matching: find.byType(AnimatedOpacity)));
    expect(fades.map((fade) => fade.opacity), everyElement(0));
    await tester.tap(find.byKey(const ValueKey('vertical-detail')), warnIfMissed: false);
    expect(rig.orientation.presentation, Presentation.vertical);

    rig.chrome.show();
    await tester.pumpAndSettle();
    expect(tester.widget<IgnorePointer>(root).ignoring, isFalse);

    rig.panels.open(PlayerPanel.more);
    await tester.pumpAndSettle();
    expect(tester.widget<IgnorePointer>(root).ignoring, isTrue);
  });

  group('the page details (09)', () {
    testWidgets('the action column runs down the right with its counts, 69 apart, clear of the bar', (tester) async {
      final rig = rig09();
      await rig.mount(tester);
      await tester.pumpAndSettle();

      for (final count in ['352', '239', '12', '59', '136']) {
        expect(find.text(count), findsOneWidget, reason: count);
      }
      const keys = ['vertical-like', 'vertical-comment', 'vertical-coin', 'vertical-favourite', 'vertical-share'];
      for (final key in keys) {
        expect(centre(tester, key).dx, closeTo(413, 0.5), reason: key);
      }
      final tops = [for (final key in keys) tester.getTopLeft(find.byKey(ValueKey(key))).dy];
      for (var i = 1; i < tops.length; i++) {
        expect(tops[i] - tops[i - 1], closeTo(69, 0.01));
      }
      // 956 less the 33 the bottom block sits up, less the column's lift.
      expect(tester.getBottomLeft(find.byKey(const ValueKey('vertical-share'))).dy, closeTo(860.5, 0.01));
      expect(tester.getCenter(find.text('352')).dy - tester.getTopLeft(find.byKey(ValueKey(keys[0]))).dy, 43.5);
      // The title still stops short of the column.
      expect(
        tester.getTopRight(find.byKey(const ValueKey('vertical-title'))).dx,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('vertical-like'))).dx),
      );
    });

    testWidgets('each action does its thing and keeps the controls up', (tester) async {
      final rig = rig09();
      await rig.mount(tester);
      await tester.pumpAndSettle();
      final actions = actionsOf(rig);

      await tester.tap(find.byKey(const ValueKey('vertical-like')));
      expect(actions.calls, ['toggleLike']);
      await tester.tap(find.byKey(const ValueKey('vertical-comment')));
      expect(rig.comments, 1);
      await tester.tap(find.byKey(const ValueKey('vertical-coin')));
      await tester.tap(find.byKey(const ValueKey('vertical-favourite')));
      await tester.tap(find.byKey(const ValueKey('vertical-share')));
      expect(actions.calls, ['toggleLike', 'ask coin', 'ask favourites', 'ask share']);
      expect(rig.chrome.shows, 5);
      await tester.pumpAndSettle();
    });

    testWidgets('every action answers an accessibility press by its name', (tester) async {
      final rig = rig09();
      await rig.mount(tester);
      await tester.pumpAndSettle();
      for (final label in ['点赞', '评论', '投币', '收藏', '分享', '关注']) {
        tester.semantics.tap(find.semantics.byLabel(label));
      }
      await tester.pumpAndSettle();
      expect(actionsOf(rig).calls, ['toggleLike', 'ask coin', 'ask favourites', 'ask share', 'tapFollow']);
      expect(rig.comments, 1);
    });

    testWidgets('white at rest; 点赞, 投币 and 收藏 turn pink once given, and back', (tester) async {
      final rig = rig09();
      await rig.mount(tester);
      await tester.pumpAndSettle();
      const keys = ['vertical-like', 'vertical-comment', 'vertical-coin', 'vertical-favourite', 'vertical-share'];
      for (final key in keys) {
        expect(iconColour(tester, key), VerticalActionTheme.icon, reason: key);
      }
      expect(tester.widget<ActionIcon>(find.byType(ActionIcon).first).solid, isTrue);

      actionsOf(rig)
        ..liked = true
        ..coins = 1
        ..favorited = true
        ..changed();
      await tester.pumpAndSettle();
      expect(iconColour(tester, 'vertical-like'), BiliColors.pink);
      expect(iconColour(tester, 'vertical-coin'), BiliColors.pink);
      expect(iconColour(tester, 'vertical-favourite'), BiliColors.pink);
      expect(iconColour(tester, 'vertical-comment'), VerticalActionTheme.icon);
      expect(iconColour(tester, 'vertical-share'), VerticalActionTheme.icon);

      actionsOf(rig)
        ..liked = false
        ..coins = 0
        ..favorited = false
        ..changed();
      await tester.pumpAndSettle();
      for (final key in keys) {
        expect(iconColour(tester, key), VerticalActionTheme.icon, reason: key);
      }
    });

    testWidgets('a liked icon swells and settles; with reduced motion it just turns pink', (tester) async {
      final rig = rig09();
      await rig.mount(tester);
      await tester.pumpAndSettle();
      final like = find.descendant(of: find.byKey(const ValueKey('vertical-like')), matching: find.byType(ActionIcon));
      final width = tester.getSize(like).width;

      actionsOf(rig)
        ..liked = true
        ..changed();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      expect(tester.getRect(like).width, greaterThan(width * 1.1));
      await tester.pumpAndSettle();
      expect(tester.getRect(like).width, closeTo(width, 0.01));

      final still = rig09();
      await still.mount(tester, still: true);
      await tester.pumpAndSettle();
      actionsOf(still)
        ..liked = true
        ..changed();
      await tester.pump();
      expect(iconColour(tester, 'vertical-like'), BiliColors.pink);
      expect(tester.getRect(like).width, closeTo(width, 0.01));
    });

    testWidgets('counts follow the actions, the comments the detail', (tester) async {
      final rig = rig09();
      await rig.mount(tester);
      await tester.pumpAndSettle();

      actionsOf(rig)
        ..likeCount = 353
        ..favCount = 12345
        ..changed();
      await tester.pumpAndSettle();
      expect(find.text('353'), findsOneWidget);
      expect(find.text('352'), findsNothing);
      expect(find.text('1.2万'), findsOneWidget);

      rig.session
        ..detail = detail(reply: 240)
        ..changed();
      rig.details!.changed();
      await tester.pumpAndSettle();
      expect(find.text('240'), findsOneWidget);
    });

    testWidgets('a new video brings new actions; the old ones no longer show', (tester) async {
      final rig = rig09();
      await rig.mount(tester);
      await tester.pumpAndSettle();
      final old = actionsOf(rig);

      rig.details!
        ..actions = FakeVideoActions(likeCount: 7, coinCount: 8, favCount: 9, shareCount: 10, liked: true)
        ..changed();
      await tester.pumpAndSettle();
      expect(find.text('7'), findsOneWidget);
      expect(find.text('352'), findsNothing);
      expect(iconColour(tester, 'vertical-like'), BiliColors.pink);

      old
        ..likeCount = 999
        ..changed();
      await tester.pumpAndSettle();
      expect(find.text('999'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('vertical-like')));
      expect(old.calls, isEmpty);
      expect(actionsOf(rig).calls, ['toggleLike']);
    });

    testWidgets('the uploader as 09: pink name for 大会员, 粉丝 under it, + 关注 beside it on the avatar\'s line',
        (tester) async {
      final rig = rig09();
      await rig.mount(tester);
      await tester.pumpAndSettle();

      final name = find.byKey(const ValueKey('vertical-name'));
      expect(textColour(tester, name), BiliColors.pink);
      expect(find.text('6129粉丝'), findsOneWidget);
      expect(find.text('关注'), findsOneWidget);
      final avatar = find.byKey(const ValueKey('vertical-avatar'));
      final pill = find.byKey(const ValueKey('vertical-follow'));
      expect(tester.getSize(pill).height, VerticalActionTheme.followHeight);
      expect(tester.getCenter(pill).dy, closeTo(tester.getCenter(avatar).dy, 0.01));
      expect(tester.getTopLeft(pill).dx - tester.getTopRight(name).dx, closeTo(VerticalActionTheme.followGap, 0.01));
      expect(tester.getTopLeft(name).dx, closeTo(59, 1));
      expect(tester.getTopLeft(find.text('6129粉丝')).dx, closeTo(59, 1));
      expect(tester.getCenter(find.text('6129粉丝')).dy, greaterThan(tester.getCenter(name).dy + 12));
      final pillColour = tester.widget<AnimatedContainer>(
        find.descendant(of: pill, matching: find.byType(AnimatedContainer)),
      ).decoration! as ShapeDecoration;
      expect(pillColour.color, BiliColors.pink);
    });

    testWidgets('a plain uploader\'s name is white, and 粉丝 counts in 万', (tester) async {
      final rig = rig09()..details!.uploader = uploader(fans: 1234567, vip: false);
      await rig.mount(tester);
      await tester.pumpAndSettle();
      expect(textColour(tester, find.byKey(const ValueKey('vertical-name'))), BiliColors.onVideo);
      expect(find.text('123.4万粉丝'), findsOneWidget);
    });

    testWidgets('关注 follows through the actions; 已关注 shows once following', (tester) async {
      final rig = rig09();
      await rig.mount(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('vertical-follow')));
      expect(actionsOf(rig).calls, ['tapFollow']);
      expect(rig.chrome.shows, 1);

      actionsOf(rig)
        ..following = true
        ..changed();
      await tester.pumpAndSettle();
      expect(find.text('已关注'), findsOneWidget);
      expect(find.text('关注'), findsNothing);
      expect(find.bySemanticsLabel('已关注'), findsOneWidget);
      final decoration = tester.widget<AnimatedContainer>(
        find.descendant(of: find.byKey(const ValueKey('vertical-follow')), matching: find.byType(AnimatedContainer)),
      ).decoration! as ShapeDecoration;
      expect(decoration.color, VerticalActionTheme.followingFill);

      await tester.tap(find.byKey(const ValueKey('vertical-follow')));
      expect(actionsOf(rig).calls, ['tapFollow', 'tapFollow']);
    });

    testWidgets('N人正在看 after the back arrow once the poll answers, gone while it hasn\'t', (tester) async {
      final rig = rig09()..details!.online.value = null;
      await rig.mount(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('人正在看'), findsNothing);

      rig.details!.online.value = '479';
      await tester.pumpAndSettle();
      expect(find.text('479人正在看'), findsOneWidget);
      // 09: the icon 52.3 in, the text from 69.3, both on the back arrow's line.
      final label = find.byKey(const ValueKey('vertical-online'));
      expect(tester.getTopLeft(find.text('479人正在看')).dx, closeTo(69.3, 0.5));
      expect(tester.getCenter(label).dy, closeTo(centre(tester, 'vertical-back').dy, 0.5));

      rig.details!.online.value = '1000+';
      await tester.pumpAndSettle();
      expect(find.text('1000+人正在看'), findsOneWidget);

      rig.details!.online.value = null;
      await tester.pumpAndSettle();
      expect(find.textContaining('人正在看'), findsNothing);
      expect(centre(tester, 'vertical-more'), within(distance: 1, from: const Offset(418, 76)));
    });

    testWidgets('before the details arrive nothing of theirs shows, and nothing moves when they do', (tester) async {
      final rig = Rig()
        ..session.title = '【VIT赛后】我们接受了LOUD的回溯！！'
        ..session.detail = detail()
        ..details = FakePageDetails();
      await rig.mount(tester);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('vertical-actions')), findsNothing);
      expect(find.byKey(const ValueKey('vertical-follow')), findsNothing);
      expect(find.byKey(const ValueKey('vertical-fans')), findsNothing);
      expect(find.textContaining('人正在看'), findsNothing);
      expect(find.text('我们一起去养猪'), findsOneWidget);

      Map<String, Rect> places() => {
        for (final key in [
          'vertical-back',
          'vertical-more',
          'vertical-name',
          'vertical-avatar',
          'vertical-title',
          'vertical-bar',
          'vertical-detail',
          'vertical-landscape',
        ])
          key: tester.getRect(find.byKey(ValueKey(key))),
      };
      final before = places();

      rig.details!
        ..uploader = uploader()
        ..changed();
      await tester.pumpAndSettle();
      expect(find.text('6129粉丝'), findsOneWidget);
      expect(find.byKey(const ValueKey('vertical-follow')), findsNothing);

      rig.details!
        ..actions = actions09()
        ..changed();
      rig.details!.online.value = '479';
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vertical-actions')), findsOneWidget);
      expect(find.byKey(const ValueKey('vertical-follow')), findsOneWidget);
      expect(find.text('479人正在看'), findsOneWidget);
      expect(places(), before);

      rig.details!
        ..actions = null
        ..uploader = null
        ..changed();
      rig.details!.online.value = null;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vertical-actions')), findsNothing);
      expect(find.byKey(const ValueKey('vertical-follow')), findsNothing);
      expect(places(), before);
    });

    testWidgets('the column waits for the video\'s detail too', (tester) async {
      final rig = Rig()..details = FakePageDetails(actions: actions09());
      await rig.mount(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vertical-actions')), findsNothing);

      rig.session
        ..detail = detail()
        ..changed();
      rig.details!.changed();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vertical-actions')), findsOneWidget);
      expect(find.text('239'), findsOneWidget);
    });

    testWidgets('outside a video page there is no column, 关注 or N人正在看', (tester) async {
      final rig = Rig()
        ..session.detail = detail()
        ..session.title = 'x';
      await rig.mount(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vertical-actions')), findsNothing);
      expect(find.byKey(const ValueKey('vertical-follow')), findsNothing);
      expect(find.byKey(const ValueKey('vertical-fans')), findsNothing);
      expect(find.byKey(const ValueKey('vertical-online')), findsNothing);
      expect(textColour(tester, find.byKey(const ValueKey('vertical-name'))), BiliColors.onVideo);
    });

    testWidgets('hidden controls take the column and 关注 with them', (tester) async {
      final rig = rig09();
      await rig.mount(tester);
      await tester.pumpAndSettle();

      rig.chrome.hide();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('vertical-like')), warnIfMissed: false);
      await tester.tap(find.byKey(const ValueKey('vertical-follow')), warnIfMissed: false);
      expect(actionsOf(rig).calls, isEmpty);
    });
  });
}
