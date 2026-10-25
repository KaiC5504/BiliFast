import 'package:bili_core/api.dart'
    show BiliClient, CookieJar, HTTPRequest, HTTPResponse, HTTPTransport, UploaderCard, VideoDetail;
import 'package:bili_core/devlog.dart' show Logger;
import 'package:bilifast/danmaku/block_rule_store.dart';
import 'package:bilifast/danmaku/danmaku_session.dart';
import 'package:bilifast/danmaku/danmaku_settings_store.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/playback/danmaku_feed.dart';
import 'package:bilifast/player/bili_player.dart' show PlayerStatus, StatusChanged;
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/player_ui/seek_bar.dart';
import 'package:bilifast/player_ui/seek_preview.dart';
import 'package:bilifast/player_ui/vertical_chrome.dart';
import 'package:bilifast/shared/action_glyphs.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/player_session.dart' show Episode;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
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

  /// Set before [mount]: 评论's count as the page's tab row has it.
  ValueNotifier<int?>? replyCount;

  /// Set before [mount]: the page's action overlay.
  ValueNotifier<Object?>? overlay;

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
    replyCount: replyCount,
    overlay: overlay,
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
      replyCount?.dispose();
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
    requestLogin: () => logins += 1,
  );

  void dispose() {
    session.dispose();
    feed.dispose();
  }
}

Offset centre(WidgetTester tester, String key) => tester.getCenter(find.byKey(ValueKey(key)));

/// What the control keyed [key] draws at: every fade over it multiplied.
double opacityOf(WidgetTester tester, String key) => tester
    .widgetList<AnimatedOpacity>(find.ancestor(of: find.byKey(ValueKey(key)), matching: find.byType(AnimatedOpacity)))
    .fold(1.0, (opacity, fade) => opacity * fade.opacity);

void main() {
  testWidgets("under the system font the title and the uploader's name fall back to PingFang SC; MiSans "
      'names none', (tester) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    List<String>? fallbackOf(String key) =>
        tester.renderObject<RenderParagraph>(find.byKey(ValueKey(key))).text.style?.fontFamilyFallback;

    BiliFonts.family = BiliFonts.system;
    await rig09().mount(tester);
    expect(fallbackOf('vertical-title'), ['PingFang SC']);
    expect(fallbackOf('vertical-name'), ['PingFang SC']);

    BiliFonts.family = BiliFonts.miSans;
    await rig09().mount(tester);
    // The name's style animates, so it settles on the new font's first.
    await tester.pumpAndSettle();
    expect(fallbackOf('vertical-title'), isNull);
    expect(fallbackOf('vertical-name'), isNull);
  });

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
    expect(rig.session.calls.first, 'wantSeekFrames', reason: 'the hold asks for the preview\'s frames');
    expect(rig.session.calls[1], startsWith('scrub'));
    expect(rig.session.calls.last, startsWith('commitSeek'));
    expect(rig.chrome.shows, 1);
  });

  testWidgets('the controls stay up whatever the chrome says; a panel or an action overlay fades them out and takes '
      'their touches', (tester) async {
    final overlay = ValueNotifier<Object?>(null);
    addTearDown(overlay.dispose);
    final rig = Rig()..overlay = overlay;
    await rig.mount(tester);
    final root = find.byKey(const ValueKey('vertical-chrome'));
    List<double> fades() => [
      for (final key in [
        'vertical-back',
        'vertical-more',
        'vertical-title',
        'vertical-bar',
        'vertical-danmaku-field',
        'vertical-danmaku',
        'vertical-detail',
        'vertical-landscape',
      ])
        opacityOf(tester, key),
    ];

    rig.chrome.hide();
    await tester.pumpAndSettle();
    expect(tester.widget<IgnorePointer>(root).ignoring, isFalse);
    expect(fades(), everyElement(1));

    rig.panels.open(PlayerPanel.more);
    await tester.pumpAndSettle();
    expect(tester.widget<IgnorePointer>(root).ignoring, isTrue);
    expect(fades(), everyElement(0));
    await tester.tap(find.byKey(const ValueKey('vertical-detail')), warnIfMissed: false);
    expect(rig.orientation.presentation, Presentation.vertical);

    rig.panels.close();
    await tester.pumpAndSettle();
    expect(tester.widget<IgnorePointer>(root).ignoring, isFalse);

    overlay.value = Object();
    await tester.pumpAndSettle();
    expect(tester.widget<IgnorePointer>(root).ignoring, isTrue);
    overlay.value = null;
    await tester.pumpAndSettle();
    expect(tester.widget<IgnorePointer>(root).ignoring, isFalse);
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

    testWidgets("评论's count is the tab row's once the list has one, following a post or a delete; the detail's "
        'until then', (tester) async {
      final rig = rig09()..replyCount = ValueNotifier(null);
      await rig.mount(tester);
      await tester.pumpAndSettle();
      final comment = find.byKey(const ValueKey('vertical-comment'));
      expect(find.descendant(of: comment, matching: find.text('239')), findsOneWidget);

      rig.replyCount!.value = 240;
      await tester.pumpAndSettle();
      expect(find.descendant(of: comment, matching: find.text('240')), findsOneWidget);
      expect(find.descendant(of: comment, matching: find.text('239')), findsNothing);

      rig.replyCount!.value = 239;
      await tester.pumpAndSettle();
      expect(find.descendant(of: comment, matching: find.text('239')), findsOneWidget);

      rig.replyCount!.value = null;
      rig.session
        ..detail = detail(reply: 5)
        ..changed();
      await tester.pumpAndSettle();
      expect(find.descendant(of: comment, matching: find.text('5')), findsOneWidget);
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

    testWidgets('a panel takes the column and 关注 with the rest', (tester) async {
      final rig = rig09();
      await rig.mount(tester);
      await tester.pumpAndSettle();

      rig.panels.open(PlayerPanel.more);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('vertical-like')), warnIfMissed: false);
      await tester.tap(find.byKey(const ValueKey('vertical-follow')), warnIfMissed: false);
      expect(actionsOf(rig).calls, isEmpty);
    });
  });

  group('paused (118)', () {
    void status(Rig rig, PlayerStatus status) => rig.session.player.emit(StatusChanged(status));

    SeekBarStyle barStyle(WidgetTester tester) => tester
        .widget<SeekBar>(find.descendant(of: find.byKey(const ValueKey('vertical-bar')), matching: find.byType(SeekBar)))
        .style;

    testWidgets('the bar carries the TV only while paused; playing, it is 09\'s dot', (tester) async {
      final rig = Rig();
      await rig.mount(tester);
      status(rig, PlayerStatus.playing);
      await tester.pump();
      expect(barStyle(tester), SeekBarStyle.dot);

      status(rig, PlayerStatus.paused);
      await tester.pump();
      expect(barStyle(tester), SeekBarStyle.pausedDot);
      expect(SeekBarStyle.pausedDot.face, isTrue);
      expect(SeekBarStyle.pausedDot.thumbWidth, SeekBarStyle.dot.thumbWidth, reason: 'the played end stays put');

      status(rig, PlayerStatus.buffering);
      await tester.pump();
      expect(barStyle(tester), SeekBarStyle.dot);
    });

    testWidgets('paused while another part opens: the loading TV shows alone, no ▶, time or TV thumb', (tester) async {
      final rig = Rig();
      await rig.mount(tester);
      status(rig, PlayerStatus.paused);
      rig.session
        ..opening = true
        ..notifyListeners();
      await tester.pump();
      expect(barStyle(tester), SeekBarStyle.dot);
      expect(find.byKey(const ValueKey('vertical-paused-play')), findsNothing);
      expect(find.byKey(const ValueKey('vertical-paused-time')), findsNothing);

      rig.session
        ..opening = false
        ..notifyListeners();
      await tester.pump();
      expect(find.byKey(const ValueKey('vertical-paused-play')), findsOneWidget);
    });

    testWidgets('the ▶ and the time show only while paused, the ▶ hanging from 竖屏\'s line whatever the video', (
      tester,
    ) async {
      final rig = Rig()..session.videoShape = (width: 1920, height: 1080);
      rig.session.duration.value = 62;
      rig.session.clock.jump(5.4);
      await rig.mount(tester);
      final play = find.byKey(const ValueKey('vertical-paused-play'));
      final time = find.byKey(const ValueKey('vertical-paused-time'));
      status(rig, PlayerStatus.playing);
      await tester.pump();
      expect(play, findsNothing);
      expect(time, findsNothing);

      status(rig, PlayerStatus.paused);
      await tester.pump();
      expect(play, findsOneWidget);
      expect(find.text('00:05 / 01:02'), findsOneWidget);
      final glyph = tester.getRect(find.descendant(of: play, matching: find.byType(Image)));
      expect(glyph.size, const Size(80, 77));
      expect(glyph.center.dx, 220);
      expect(glyph.top, closeTo(956 * BiliMetrics.verticalVideoCentre, 0.01));
      final timeTop = tester.getTopLeft(time).dy;
      expect(timeTop, closeTo(956 * BiliMetrics.verticalVideoCentre + VerticalActionTheme.pausedTimeTop, 0.01));
      final image = tester.widget<Image>(find.descendant(of: play, matching: find.byType(Image)));
      expect((image.image as AssetImage).assetName, VerticalActionTheme.pausedPlayAsset);
      expect(image.opacity!.value, VerticalActionTheme.pausedPlayOpacity);

      // 16's 3:4 video: the official ▶ and time stay where 118's 16:9 one has them.
      rig.session
        ..isVertical = true
        ..videoShape = (width: 1080, height: 1440)
        ..changed();
      await tester.pump();
      expect(tester.getRect(find.descendant(of: play, matching: find.byType(Image))), glyph);
      expect(tester.getTopLeft(time).dy, timeTop);

      status(rig, PlayerStatus.ended);
      await tester.pump();
      expect(play, findsNothing);
    });

    testWidgets('a tap on the ▶ plays; it answers an accessibility press too', (tester) async {
      final rig = Rig();
      await rig.mount(tester);
      status(rig, PlayerStatus.paused);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('vertical-paused-play')));
      expect(rig.session.calls, ['togglePlay']);
      tester.semantics.tap(find.semantics.byLabel('播放'));
      expect(rig.session.calls, ['togglePlay', 'togglePlay']);
    });

    testWidgets('a panel takes the time with the controls; the ▶ stays', (tester) async {
      final rig = Rig();
      await rig.mount(tester);
      status(rig, PlayerStatus.paused);
      await tester.pump();
      rig.panels.open(PlayerPanel.more);
      await tester.pumpAndSettle();
      final fade = tester.widget<AnimatedOpacity>(
        find.ancestor(of: find.byKey(const ValueKey('vertical-paused-time')), matching: find.byType(AnimatedOpacity)),
      );
      expect(fade.opacity, 0);
      expect(find.byKey(const ValueKey('vertical-paused-play')), findsOneWidget);
    });
  });

  group('holding the bar (19, 20)', () {
    const aside = [
      'vertical-back',
      'vertical-more',
      'vertical-online',
      'vertical-like',
      'vertical-share',
      'vertical-uploader',
      'vertical-follow',
      'vertical-title',
      'vertical-danmaku-field',
      'vertical-danmaku',
      'vertical-detail',
      'vertical-landscape',
      'vertical-paused-play',
      'vertical-paused-time',
    ];

    SeekPreview preview(WidgetTester tester) => tester.widget<SeekPreview>(find.byType(SeekPreview));

    testWidgets('every control but the bar fades and takes no touches for the upright seek preview; letting go '
        'brings them back', (tester) async {
      final rig = rig09();
      rig.session.duration.value = 100;
      await rig.mount(tester);
      rig.session.player.emit(const StatusChanged(PlayerStatus.paused));
      await tester.pumpAndSettle();
      for (final key in [...aside, 'vertical-bar']) {
        expect(opacityOf(tester, key), 1, reason: key);
      }
      expect(preview(tester).upright, isTrue);
      expect(preview(tester).shown, isFalse);
      expect(tester.getRect(find.byType(SeekPreview)), Offset.zero & const Size(440, 956));

      final finger = await tester.startGesture(centre(tester, 'vertical-bar'));
      await finger.moveBy(const Offset(-40, 0));
      await tester.pump();
      await finger.moveBy(const Offset(-40, 0));
      await tester.pump(const Duration(milliseconds: 400));
      expect(rig.chrome.barHeld, isTrue);
      expect(rig.session.calls, contains('wantSeekFrames'));
      for (final key in aside) {
        expect(opacityOf(tester, key), 0, reason: key);
      }
      expect(opacityOf(tester, 'vertical-bar'), 1);
      expect(preview(tester).shown, isTrue);

      await tester.tap(find.byKey(const ValueKey('vertical-like')), warnIfMissed: false);
      await tester.tap(find.byKey(const ValueKey('vertical-detail')), warnIfMissed: false);
      expect(actionsOf(rig).calls, isEmpty);
      expect(rig.orientation.presentation, Presentation.vertical);

      await finger.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(rig.chrome.barHeld, isFalse);
      expect(rig.session.calls.last, startsWith('commitSeek'));
      for (final key in aside) {
        expect(opacityOf(tester, key), 1, reason: key);
      }
      expect(preview(tester).shown, isFalse);
    });

    testWidgets('a panel keeps the preview down even if the bar is held', (tester) async {
      final rig = Rig();
      await rig.mount(tester);
      rig.chrome.holdBar(true);
      await tester.pump();
      expect(preview(tester).shown, isTrue);
      rig.panels.open(PlayerPanel.more);
      await tester.pump();
      expect(preview(tester).shown, isFalse);
      rig.chrome.holdBar(false);
    });
  });

  group('合集 (118)', () {
    Episode episode(int i, {bool current = false}) => Episode(bvid: 'BV$i', cid: i, title: '第$i集', current: current);

    VideoDetail inCollection() => VideoDetail.fromJson({
      'bvid': 'BV18',
      'title': '“没错，你触发保底了”',
      'owner': {'mid': 1, 'name': '小小小小小小小流萤', 'face': ''},
      'stat': {'view': 34000},
      'ugc_season': {'id': 1, 'title': '合集', 'sections': <Object>[]},
    });

    testWidgets('a video in a 合集 reads 合集 · 第N集 and a bar before its title', (tester) async {
      final rig = Rig()
        ..session.title = '“没错，你触发保底了”'
        ..session.detail = inCollection()
        ..session.episodesAreParts = false
        ..session.episodes = [for (var i = 1; i <= 20; i++) episode(i, current: i == 18)];
      await rig.mount(tester);
      final title = find.byKey(const ValueKey('vertical-title'));
      final text = tester.renderObject<RenderParagraph>(title).text.toPlainText();
      expect(text.indexOf('合集'), lessThan(text.indexOf('第18集')));
      expect(text.indexOf('第18集'), lessThan(text.indexOf('“没错，你触发保底了”')));
      expect(text, contains('3.4万播放'));
    });

    testWidgets('parts, or a video on its own, keep the plain title', (tester) async {
      final rig = Rig()
        ..session.title = '【VIT赛后】我们接受了LOUD的回溯！！'
        ..session.detail = detail()
        ..session.episodes = [episode(1, current: true), episode(2)];
      await rig.mount(tester);
      final title = find.byKey(const ValueKey('vertical-title'));
      final text = tester.renderObject<RenderParagraph>(title).text.toPlainText();
      expect(text, isNot(contains('合集')));
    });
  });
}
