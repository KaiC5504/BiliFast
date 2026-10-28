import 'dart:ui' show Tristate;

import 'package:bili_core/api.dart' show BiliClient, CookieJar, HTTPRequest, HTTPResponse, HTTPTransport, VideoCard;
import 'package:bili_core/devlog.dart' show Logger;
import 'package:bilifast/danmaku/block_rule_store.dart';
import 'package:bilifast/danmaku/danmaku_session.dart';
import 'package:bilifast/danmaku/danmaku_settings_store.dart';
import 'package:bilifast/playback/danmaku_feed.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/intro/action_row.dart';
import 'package:bilifast/video/intro/intro_tab.dart';
import 'package:bilifast/video/intro/related_list.dart';
import 'package:bilifast/video/intro/title_block.dart';
import 'package:bilifast/video/intro/uploader_row.dart';
import 'package:bilifast/video/pad/pad_body.dart';
import 'package:bilifast/video/player_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_player_session.dart';
import '../../support/fake_video_actions.dart';
import '../../support/look_alike.dart';
import 'pad_body_fixtures.dart';

final class _NoNetwork implements HTTPTransport {
  @override
  Future<HTTPResponse> send(HTTPRequest request) => throw StateError('tests never reach the network');
}

final class _Feed extends DanmakuFeed {
  _Feed()
    : super(
        client: BiliClient(transport: _NoNetwork(), cookies: CookieJar(), logger: _logger),
        logger: _logger,
      );

  static final _logger = Logger(session: 'test');

  bool uploaderClosed = false;

  @override
  bool get closed => uploaderClosed;
}

void main() {
  late FakeVideoActions actions;
  late FakePageDetails details;
  late FakePlayerSession player;
  late _Feed feed;
  late DanmakuSession danmaku;
  late bool loggedIn;
  late int logins;

  setUp(() {
    actions = padActions();
    details = FakePageDetails(actions: actions, uploader: padUploader, tags: padTags, online: '4000+');
    player = FakePlayerSession();
    feed = _Feed();
    loggedIn = true;
    logins = 0;
    final api = FakePageApi();
    danmaku = DanmakuSession(
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
  });

  tearDown(() {
    danmaku.dispose();
    feed.dispose();
    player.dispose();
    actions.dispose();
    details.dispose();
  });

  Widget page(Widget child) => MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: Material(child: child),
      ),
    ),
  );

  Future<void> head(WidgetTester tester, {bool landscape = true}) async {
    showAsPad(tester, landscape: landscape);
    await tester.pumpWidget(
      page(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: landscape ? 756.5 : 834,
            child: PadIntroHead(
              content: IntroContent(detail: padDetail(), related: padRelated),
              details: details,
              onSeek: (_) {},
              onOpenVideo: (_) {},
              onPlayEpisode: (Episode _) {},
              onOpenEpisodes: () {},
              player: player,
              danmaku: danmaku,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('PadIntroHead', () {
    testWidgets('查看简介 opens the description and the plain tags in place, and closes them again (04)', (tester) async {
      await head(tester);
      expect(find.text('qwnrt?'), findsNothing);
      final actionsTop = tester.getTopLeft(find.byKey(const ValueKey('action-like'))).dy;

      await tester.tap(find.byKey(const ValueKey('pad-intro-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('qwnrt?'), findsOneWidget);
      expect(find.text('乐乐'), findsOneWidget);
      expect(find.text('AI游戏全世界'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('action-like'))).dy,
        greaterThan(actionsTop + 50),
        reason: 'the actions move down under the tags',
      );
      expect(
        tester.getSemantics(find.byKey(const ValueKey('pad-intro-toggle'))).flagsCollection.isExpanded,
        Tristate.isTrue,
      );

      await tester.tap(find.byKey(const ValueKey('pad-intro-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('qwnrt?'), findsNothing);
      expect(tester.getTopLeft(find.byKey(const ValueKey('action-like'))).dy, actionsTop);
    });

    testWidgets('the title opens and closes the description too', (tester) async {
      await head(tester);
      await tester.tap(find.text(padDetail().title));
      await tester.pumpAndSettle();
      expect(find.text('qwnrt?'), findsOneWidget);
      await tester.tap(find.text(padDetail().title));
      await tester.pumpAndSettle();
      expect(find.text('qwnrt?'), findsNothing);
    });

    testWidgets('the meta line carries the BV id and N人正在看; the counts have one space', (tester) async {
      await head(tester);
      expect(find.text('BV1Fk4x7NqTz'), findsOneWidget);
      expect(find.text('4000+人正在看'), findsOneWidget);
      expect(find.text('2.1万粉丝 519视频', findRichText: true), findsOneWidget);
    });

    testWidgets('sideways, 点我发弹幕 opens the send bar as the tab row does, and 弹 turns danmaku off', (tester) async {
      await head(tester);
      expect(danmaku.sendOpen.value, isFalse);
      await tester.tap(find.byKey(const ValueKey('danmaku-send')));
      await tester.pump();
      expect(danmaku.sendOpen.value, isTrue);
      expect(find.text('弹幕输入中'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('danmaku-toggle')));
      await tester.pump();
      expect(player.calls, contains('setDanmakuOn false'));
    });

    testWidgets('logged out, 点我发弹幕 asks for the login instead', (tester) async {
      loggedIn = false;
      await head(tester);
      await tester.tap(find.byKey(const ValueKey('danmaku-send')));
      await tester.pump();
      expect(danmaku.sendOpen.value, isFalse);
      expect(logins, 1);
    });

    testWidgets('the uploader closed danmaku: the field reads UP主已关闭弹幕 and opens nothing', (tester) async {
      feed.uploaderClosed = true;
      await head(tester);
      expect(find.text('UP主已关闭弹幕'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('danmaku-send')));
      await tester.pump();
      expect(danmaku.sendOpen.value, isFalse);
    });

    testWidgets("upright the field is the tab row's, not the head's (06)", (tester) async {
      await head(tester, landscape: false);
      expect(find.byType(PadDanmakuCapsule), findsNothing);
      expect(find.text('查看简介'), findsOneWidget);
    });

    testWidgets('the actions are 70 pt cells from the 20 pt gutter, each doing what the iPhone\'s does', (
      tester,
    ) async {
      await head(tester);
      final like = tester.getCenter(find.byKey(const ValueKey('action-like')));
      final dislike = tester.getCenter(find.byKey(const ValueKey('action-dislike')));
      expect(like.dx, 55);
      expect(dislike.dx - like.dx, 70);

      await tester.tap(find.byKey(const ValueKey('action-like')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const ValueKey('action-dislike')));
      await tester.tap(find.byKey(const ValueKey('action-coin')));
      await tester.tap(find.byKey(const ValueKey('action-favourite')));
      await tester.tap(find.byKey(const ValueKey('action-share')));
      await tester.pump();
      expect(actions.calls, ['toggleLike', 'toggleDislike', 'ask coin', 'ask favourites', 'ask share']);
    });

    testWidgets('a like turns the thumb and its count pink at once (optimistic, as the model says)', (tester) async {
      await head(tester);
      actions
        ..liked = true
        ..likeCount = 3960
        ..changed();
      await tester.pumpAndSettle();
      expect(find.text('3960'), findsOneWidget);
      final count = tester.widget<Text>(find.text('3960'));
      expect(count.style?.color, BiliColors.pink);
    });

    testWidgets('+ 关注 sits right after the counts and follows through the actions', (tester) async {
      await head(tester);
      expect(find.text('关注'), findsOneWidget);
      await tester.tap(find.text('关注'));
      await tester.pump();
      expect(actions.calls, ['tapFollow']);
      actions
        ..following = true
        ..changed();
      await tester.pumpAndSettle();
      expect(find.text('已关注'), findsOneWidget);
    });

    testWidgets('nothing shows before the detail arrives', (tester) async {
      showAsPad(tester, landscape: true);
      await tester.pumpWidget(
        page(
          PadIntroHead(
            content: const IntroContent(),
            details: details,
            onSeek: (_) {},
            onOpenVideo: (_) {},
            onPlayEpisode: (Episode _) {},
            onOpenEpisodes: () {},
          ),
        ),
      );
      expect(find.byType(PadUploaderRow), findsNothing);
      expect(find.byType(ActionRow), findsNothing);
    });
  });

  group('the related rows', () {
    Future<List<String>> column(WidgetTester tester, {List<String>? later}) async {
      showAsPad(tester, landscape: true);
      final opened = <String>[];
      await tester.pumpWidget(
        page(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 437,
              height: 800,
              child: PadRelatedColumn(
                cards: padRelated,
                onOpen: (card) => opened.add(card.bvid),
                onWatchLater: (card) => later?.add(card.bvid),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return opened;
    }

    Finder row(String title) => find.ancestor(of: find.text(title), matching: find.byType(Stack)).last;

    testWidgets('sideways: 97 apart, a 138 × 77 cover 10 in, the first 16 under the top, no hairline', (tester) async {
      await column(tester);
      final first = tester.getTopLeft(row(padRelated[0].title));
      final second = tester.getTopLeft(row(padRelated[1].title));
      expect(second.dy - first.dy, 97);
      final cover = find.descendant(of: row(padRelated[0].title), matching: find.byType(ClipRRect)).first;
      expect(tester.getSize(cover), const Size(138, 77));
      expect(tester.getTopLeft(cover), const Offset(10, 16));
      expect(find.byKey(const ValueKey('related-hairline')), findsNothing);
      expect(find.text('04:15'), findsOneWidget, reason: 'the iPad keeps the leading zero');
    });

    testWidgets('a tap opens the video; ⋮ offers 稍后再看, as on the iPhone', (tester) async {
      final later = <String>[];
      final opened = await column(tester, later: later);
      await tester.tap(find.text(padRelated[1].title));
      await tester.pumpAndSettle();
      expect(opened, [padRelated[1].bvid]);

      await tester.tap(
        find.descendant(of: row(padRelated[0].title), matching: find.byKey(const ValueKey('related-more'))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('稍后再看'));
      await tester.pumpAndSettle();
      expect(later, [padRelated[0].bvid]);
      expect(opened, [padRelated[1].bvid]);
    });

    testWidgets('upright (06): the full width at the 20 pt gutter, under a hairline 10 in from each side', (
      tester,
    ) async {
      showAsPad(tester);
      await tester.pumpWidget(
        page(
          CustomScrollView(
            slivers: [RelatedSliver(cards: padRelated, onOpen: (_) {}, onWatchLater: (_) {})],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final hairline = find.byKey(const ValueKey('related-hairline'));
      expect(hairline, findsOneWidget);
      final line = find.descendant(of: hairline, matching: find.byType(ColoredBox));
      expect(tester.getTopLeft(line), const Offset(10, 10));
      expect(tester.getSize(line).width, 834 - 20);
      final cover = find.descendant(of: row(padRelated[0].title), matching: find.byType(ClipRRect)).first;
      expect(tester.getTopLeft(cover).dx, 20);
      expect(tester.getSize(cover), const Size(138, 77));
      final more = tester.getCenter(find.byKey(const ValueKey('related-more')).first);
      expect(more.dx, 834 - 28);
    });
  });

  group('the iPhone stays as it was', () {
    testWidgets('IntroTab at the phone size builds the iPhone sections, at the iPad size the pad head', (tester) async {
      Future<void> tab(Size size) async {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          page(
            IntroTab(
              content: IntroContent(detail: padDetail(), related: padRelated),
              details: details,
              onSeek: (_) {},
              onOpenVideo: (_) {},
              onPlayEpisode: (Episode _) {},
              onOpenEpisodes: () {},
              onOpenRelated: (VideoCard _) {},
              onWatchLater: (VideoCard _) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await tab(const Size(440, 956));
      expect(find.byType(UploaderRow), findsOneWidget);
      expect(find.byType(TitleBlock), findsOneWidget);
      expect(find.byType(PadIntroHead), findsNothing);
      expect(find.text('4:15'), findsOneWidget, reason: "the iPhone's covers drop the leading zero");
      final phoneLike = tester.getSize(find.byKey(const ValueKey('action-like')));
      expect(phoneLike.width, closeTo((440 - 24) / 5, 0.01), reason: 'the five cells share the row');

      await tab(const Size(834, 1194));
      expect(find.byType(PadIntroHead), findsOneWidget);
      expect(find.byType(UploaderRow), findsNothing);
      expect(find.byType(TitleBlock), findsNothing);
      expect(find.byType(PadDanmakuCapsule), findsNothing);
    });

    test("the iPhone's action metrics are the theme's", () {
      const phone = ActionRowMetrics.phone;
      expect(phone.cell, isNull);
      expect(phone.icon, ActionTheme.iconSize);
      expect(phone.coinDrop, IntroTheme.actionCoinDrop);
      expect(phone.countColor, ActionTheme.count);
      expect(phone.gutter, BiliMetrics.gutter);
    });

    test('RelatedSliver.duration: 4:15 on the iPhone, 04:15 on the iPad', () {
      expect(RelatedSliver.duration(255), '4:15');
      expect(RelatedSliver.duration(255, pad: true), '04:15');
    });
  });
}
