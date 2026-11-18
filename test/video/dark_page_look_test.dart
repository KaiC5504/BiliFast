import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bili_core/api.dart'
    show
        DescPart,
        OfficialKind,
        UgcSeason,
        UploaderCard,
        VideoCard,
        VideoDetail,
        VideoOwner,
        VideoStat,
        VideoTag,
        VideoTagKind;
import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart' show ManualClock;
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/appearance.dart' show redrawAll;
import 'package:bilifast/app/route_observer.dart';
import 'package:bilifast/app/swipe_back_route.dart';
import 'package:bilifast/comments/comments_tab.dart';
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/device/player_device.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/intro/desc_text.dart';
import 'package:bilifast/video/page_session.dart' show SessionOpen;
import 'package:bilifast/video/page_tabs.dart';
import 'package:bilifast/video/player_session.dart';
import 'package:bilifast/video/video_page.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../device/fake_orientation_host.dart' show FakeOrientationHost;
import '../playback/fakes.dart';
import '../support/fake_player.dart';
import '../support/fake_player_session.dart';
import '../support/fake_video_actions.dart';
import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import 'mixed_lines.dart' show appTheme;

class _NoLogin implements LoginGate {
  @override
  Future<bool> request(BuildContext context) async => false;
}

const _bv = 'BV1b5xt6oEzu';

/// 240's video: expanded, with an @ in its description, nine tags, a 合集 and a topic.
final _detail = VideoDetail(
  bvid: _bv,
  aid: 115497316,
  title: '奶爸爆料：EDG没有主动权，很多俱乐部不计代价的追逐康康。对康康来说，对世界赛对冠军有竞争力才能吸引他。',
  cover: '',
  pubdate: 1793588400,
  duration: 182,
  desc: '@解说奶爸',
  descParts: const [DescPart(text: '@解说奶爸', mentionMid: 7)],
  copyright: 1,
  owner: const VideoOwner(mid: 1, name: '学院派野路子', face: ''),
  stat: const VideoStat(
    view: 463000,
    danmaku: 157,
    reply: 1419,
    favorite: 443,
    coin: 61,
    share: 613,
    like: 4533,
  ),
  pages: const [],
  season: const UgcSeason(id: 1, title: '奶爸短评晋升赛', intro: '', sections: []),
  staff: const [],
  width: 1920,
  height: 1080,
  honor: null,
  redirectURL: null,
);

const _episodes = [
  Episode(bvid: 'BV1a', cid: 11, title: '第一话', current: false),
  Episode(bvid: _bv, cid: 12, title: '第二话', current: true),
];

VideoCard _card(int i, String title) => VideoCard(
  aid: 100 + i,
  bvid: 'BV1related$i',
  cid: 200 + i,
  title: title,
  cover: '',
  duration: 92,
  ownerMid: 300 + i,
  ownerName: '为爱而聚',
  views: 1015000,
  danmaku: 2561,
  likes: 2561,
);

/// The video page in 深色模式 against 240 (简介) and 241 (评论), and its composer against 257. With BILIFAST_SHOTS
/// naming a folder outside the repo, the 3× shots are saved there for tools/screen_diff.py.
void main() {
  late GlobalKey<NavigatorState> nav;
  late FakePageApi api;
  late FakePlayerSession session;
  const screen = ValueKey('screen');

  Future<void> frames(WidgetTester tester, [int count = 10]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> open(WidgetTester tester, {bool dark = true}) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    await tester.runAsync(loadIconFonts);
    showAsPhone(tester, dark: dark);

    final logger = Logger(session: 'test');
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: Canned.http(),
      logger: logger,
    );
    await environment.refreshAccount();
    final player = FakePlayer();
    final now = DateTime.fromMillisecondsSinceEpoch(
      (Canned.deadline - 1000) * 1000,
    );
    final controller = PlaybackController(
      client: environment.client,
      engine: FakeEngine(),
      player: player,
      clock: ManualClock(10000).clock,
      now: () => now,
      startTimer: FakeTimers().start,
      logger: logger,
    );
    final playback = AppPlayback(() async => controller);
    addTearDown(playback.dispose);
    api = FakePageApi.demo(now: DateTime(2026, 11, 18));
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      device: PlayerDevice(
        orientation: OrientationController(host: FakeOrientationHost()),
        controls: NoDeviceControls(),
      ),
      loginGate: _NoLogin(),
      pageApi: api,
    );
    BiliFonts.family = BiliFonts.system;

    PlayerSession makeSession({
      required PlaybackController controller,
      required AppServices services,
      required SessionOpen open,
      required void Function(double seconds) onSeeked,
      required VoidCallback requestLogin,
      required VoidCallback willPlay,
    }) => session = FakePlayerSession(player: player);

    nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      RepaintBoundary(
        key: screen,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(),
          navigatorKey: nav,
          navigatorObservers: [pageRoutes],
          builder: (context, child) =>
              AppScope(services: services, child: child!),
          home: const SizedBox(),
        ),
      ),
    );
    unawaited(
      nav.currentState!.push(
        SwipeBackPageRoute<void>(
          builder: (_) => VideoPage(
            route: const VideoRoute(bvid: _bv, cid: 12, start: 0),
            createSession: makeSession,
            createDetails:
                ({
                  required session,
                  required services,
                  required toast,
                  required requestLogin,
                  required logins,
                }) => FakePageDetails(
                  actions: FakeVideoActions(
                    likeCount: 4533,
                    coinCount: 61,
                    favCount: 443,
                    shareCount: 613,
                  ),
                  uploader: const UploaderCard(
                    mid: 1,
                    name: '学院派野路子',
                    face: '',
                    fans: 171,
                    videos: 93,
                    isVip: false,
                    following: false,
                    official: OfficialKind.none,
                  ),
                  tags: [
                    const VideoTag(
                      id: 1,
                      name: '2026VCTCN晋升赛',
                      kind: VideoTagKind.topic,
                    ),
                    for (final (i, name) in [
                      '康康',
                      'EDG',
                      '电子竞技',
                      'FPS',
                      '无畏契约',
                      'zmjjkk',
                      '解说奶爸',
                      '冠军',
                      '瓦',
                    ].indexed)
                      VideoTag(
                        id: 10 + i,
                        name: name,
                        kind: VideoTagKind.normal,
                      ),
                  ],
                  online: '6',
                ),
          ),
        ),
      ),
    );
    await frames(tester, 20);
    session
      ..video = controller.video
      ..detail = _detail
      ..episodes = _episodes
      ..episodesAreParts = false
      ..related = [
        _card(1, '为爱而聚：EDG《为爱而聚》十周年纪录片'),
        _card(2, '【XLG ZMJJKK】最终还是来了！'),
      ]
      ..changed();
    await frames(tester, 20);
  }

  /// The page as drawn, one pixel a point, for reading colours.
  Future<Color Function(Offset at)> pixels(WidgetTester tester) async {
    final render = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(screen),
    );
    late ByteData bytes;
    late int width;
    await tester.runAsync(() async {
      final image = await render.toImage();
      width = image.width;
      bytes = (await image.toByteData())!;
      image.dispose();
    });
    return (Offset at) {
      final i = (at.dy.floor() * width + at.dx.floor()) * 4;
      return Color.fromARGB(
        bytes.getUint8(i + 3),
        bytes.getUint8(i),
        bytes.getUint8(i + 1),
        bytes.getUint8(i + 2),
      );
    };
  }

  Future<void> shot(WidgetTester tester, String name) async {
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(screen), '$shots/$name');
  }

  Future<void> close(WidgetTester tester) async {
    nav.currentState!.pop();
    await frames(tester, 20);
  }

  testWidgets(
    '简介 at night (240): the card surface, chips in Ga0_s, the @ in Lb6 and the text in the night greys',
    (tester) async {
      await open(tester);
      await tester.tap(find.textContaining('奶爸爆料').first);
      await frames(tester, 10);
      await shot(tester, '240-ours.png');

      final at = await pixels(tester);
      final tabs = tester.getRect(find.byType(PageTabRow));
      expect(
        at(tabs.topLeft + const Offset(4, 4)),
        const Color(0xFF17181A),
        reason: 'the tab row on the card',
      );
      final capsule = tester.getRect(
        find.byKey(const ValueKey('danmaku-send')),
      );
      expect(
        at(Offset(capsule.left + 10, capsule.center.dy)),
        const Color(0xFF1E2022),
        reason: '点我发弹幕 in Ga0_s',
      );

      final tag = tester.getRect(find.text('康康'));
      expect(
        at(Offset(tag.left - 4, tag.center.dy)),
        const Color(0xFF1E2022),
        reason: 'a tag chip in Ga0_s, as 240',
      );
      expect(
        tester.widget<Text>(find.text('康康')).style?.color,
        IntroTheme.tagInk,
      );
      expect(IntroTheme.tagInk, const Color(0xFFA2A7AE));

      final collection = tester.getRect(find.textContaining('奶爸短评晋升赛'));
      expect(
        at(Offset(collection.left - 6, collection.center.dy)),
        const Color(0xFF1E2022),
        reason: '合集 in Ga0_s',
      );

      final mention = tester.widget<RichText>(
        find.descendant(
          of: find.byType(DescriptionText),
          matching: find.byType(RichText),
        ),
      );
      final spans = <TextSpan>[];
      mention.text.visitChildren((span) {
        if (span is TextSpan && span.text == '@解说奶爸') spans.add(span);
        return true;
      });
      expect(spans.single.style?.color, const Color(0xFF2C9CC8));

      final below = tester.getRect(find.textContaining('最终还是来了'));
      expect(
        at(Offset(4, below.bottom + 4)),
        const Color(0xFF17181A),
        reason: 'the body under the related rows',
      );
      await close(tester);
    },
  );

  testWidgets(
    '评论 at night (241): replies box in Ga0, the write bar\'s pill in Ga1_s, the 大 keeping its day pink',
    (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('tab-comments')));
      await frames(tester, 20);
      expect(find.byType(CommentsTab), findsOneWidget);
      await shot(tester, '241-ours.png');

      final at = await pixels(tester);
      final bar = tester.getRect(find.byKey(const ValueKey('comment-bar')));
      expect(
        at(Offset(bar.left + 4, bar.top + 3)),
        const Color(0xFF17181A),
        reason: 'the bar on the card',
      );
      final field = tester.getRect(find.byKey(const ValueKey('comment-field')));
      expect(
        at(Offset(field.left + 20, field.top + 3)),
        const Color(0xFF232527),
      );
      expect(
        CommentRowTheme.box,
        const Color(0xFF101011),
        reason: "241's replies box is 101010",
      );
      expect(CommentRowTheme.vipMarkFill, const Color(0xFFFF6699));
      expect(CommentRowTheme.vipName, const Color(0xFFFB7299));
      expect(CommentRowTheme.levelInk, const Color(0xFFFFFFFF));
      await close(tester);
    },
  );

  testWidgets(
    'the composer at night (257): Ga11 sheet over the same dim as by day, the dark keyboard, the faded 发布',
    (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('tab-comments')));
      await frames(tester, 20);
      await tester.tap(find.byKey(const ValueKey('comment-field')));
      await frames(tester, 10);
      await shot(tester, '257-ours.png');

      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('composer-field')),
      );
      expect(field.keyboardAppearance, Brightness.dark);
      final at = await pixels(tester);
      final sheet = tester.getRect(
        find.byKey(const ValueKey('composer-sheet')),
      );
      expect(at(sheet.topLeft + const Offset(4, 40)), const Color(0xFF242628));
      final dimmed = at(const Offset(4, 400));
      expect(
        dimmed.r,
        lessThan(BiliColors.card.r),
        reason: 'the page under the dim',
      );
      expect(
        tester.widget<Text>(find.text('发布')).style?.color,
        const Color(0xFF686868),
      );
      await close(tester);
    },
  );

  testWidgets(
    'back to day mode, every colour on the page is the light one again, the cached link spans included',
    (tester) async {
      await open(tester);
      await tester.tap(find.textContaining('奶爸爆料').first);
      await frames(tester, 10);
      BiliTheme.dark = false;
      redrawAll(tester.element(find.byType(VideoPage)));
      await frames(tester, 2);

      final at = await pixels(tester);
      final tabs = tester.getRect(find.byType(PageTabRow));
      expect(at(tabs.topLeft + const Offset(4, 4)), const Color(0xFFFFFFFF));
      final tag = tester.getRect(find.text('康康'));
      expect(at(Offset(tag.left - 4, tag.center.dy)), const Color(0xFFF6F7F8));
      final mention = tester.widget<RichText>(
        find.descendant(
          of: find.byType(DescriptionText),
          matching: find.byType(RichText),
        ),
      );
      final colours = <Color?>[];
      mention.text.visitChildren((span) {
        if (span is TextSpan && span.text == '@解说奶爸') colours.add(span.style?.color);
        return true;
      });
      expect(colours, [const Color(0xFF00699D)]);
      await close(tester);
    },
  );

  test('day values are those the page had before 深色模式', () {
    BiliTheme.dark = false;
    expect(PageTheme.chipFill, BiliColors.softGrey);
    expect(IntroTheme.descLink, BiliColors.link);
    expect(CommentListTheme.fieldFill, BiliColors.pageGrey);
    expect(ComposerTheme.sheet, BiliColors.card);
    expect(ComposerTheme.dim, BiliColors.scrim);
    expect(ComposerTheme.panel, BiliColors.pageGrey);
    expect(FavouriteTheme.sheetFill, BiliColors.card);
    expect(FavouriteTheme.pressed, BiliColors.pressedFill);
    expect(ComposerTheme.publishTextFaded, ComposerTheme.publishText);
    expect(PadBodyTheme.tagFill, BiliColors.pageGrey);
    expect(IntroListTheme.chipTextColor, const Color(0xFF61666D));
  });
}
