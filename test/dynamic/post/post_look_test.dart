import 'dart:async';
import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/swipe_back_route.dart';
import 'package:bilifast/dynamic/fake_dynamic_api.dart';
import 'package:bilifast/dynamic/post/post_page.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/fake_keychain.dart';
import '../../home/fake_login_gate.dart';
import '../../playback/fakes.dart';
import '../../support/look_alike.dart';
import '../../support/stand_in_fonts.dart';
import '../../video/mixed_lines.dart' show appTheme;

const _icons = [
  'assets/images/noface.jpeg',
  'assets/images/dynamic/dy_ic_arrow_share_line_24.png',
  'assets/images/dynamic/dy_ic_bubble_comment_line_24.png',
  'assets/images/dynamic/dy_ic_star_favorite_line_24.png',
  'assets/images/dynamic/dy_ic_hand_thumbsup_line_24.png',
];

const _org = DynamicAuthor(
  mid: 2001,
  name: '演示星河列车',
  face: '',
  pubTime: '2026年10月26日 15:00',
  location: '上海',
  vipPink: true,
  verify: DynamicVerify.organisation,
);

/// The post page as KaiC's iPhone draws it, under the system font, for 131, 132 and 140. The text, pictures and the
/// repost's block draw here too but are judged in dynamic_card_look_alike_test.dart, so the bar, the author block, the
/// tabs, the comments and the bottom bar are what these measure. With BILIFAST_SHOTS naming a folder outside the repo,
/// the 3× shots are saved there for tools/screen_diff.py.
void main() {
  Future<void> shoot(
    WidgetTester tester, {
    required DynamicItem post,
    List<Comment> comments = const [],
    int? total,
    required String name,
    required void Function(WidgetTester tester) check,
    Future<void> Function(WidgetTester tester, Future<void> Function(String name) save)? then,
  }) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    final logger = Logger(session: 'test');
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: Canned.http(),
      logger: logger,
    );
    environment.useFakeAccount();
    final playback = AppPlayback(() => Completer<PlaybackController>().future);
    addTearDown(playback.dispose);
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      pageApi: FakePageApi()..commentPage = CommentPage(comments: comments, total: total ?? comments.length),
      dynamicApi: FakeDynamicApi(posts: [post]),
      loginGate: FakeLoginGate(),
    );
    BiliFonts.family = BiliFonts.system;
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester);
    final navigator = GlobalKey<NavigatorState>();
    const screen = ValueKey('screen');
    await tester.pumpWidget(
      RepaintBoundary(
        key: screen,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(),
          navigatorKey: navigator,
          builder: (context, child) => AppScope(services: services, child: child!),
          home: const SizedBox(),
        ),
      ),
    );
    unawaited(navigator.currentState!.push(SwipeBackPageRoute<void>(builder: (_) => DynamicPostPage(id: post.id))));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final context = tester.element(find.byType(DynamicPostPage));
    await tester.runAsync(() => Future.wait([for (final icon in _icons) precacheImage(AssetImage(icon), context)]));
    await tester.pump();
    check(tester);
    final shots = Platform.environment['BILIFAST_SHOTS'];
    Future<void> save(String name) async {
      if (shots != null) await saveShot(tester, find.byKey(screen), '$shots/$name-ours.png');
    }

    await save(name);
    await then?.call(tester, save);
    navigator.currentState!.pop();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Rect rect(WidgetTester tester, String key) => tester.getRect(find.byKey(ValueKey(key)));

  /// 131's and 132's bottom bar: its rules from 877.33, the pill 12 in from 884 to 916, the counts 54 apart.
  void bottomBar(WidgetTester tester, {required double pillRight, required List<String> actions}) {
    final bar = rect(tester, 'post-bottom-bar');
    expect(bar.top, closeTo(877.33, 0.01));
    final pill = rect(tester, 'post-write');
    expect(pill, rectMoreOrLessEquals(Rect.fromLTRB(12, 884, pillRight, 916), epsilon: 0.01));
    final centres = [for (final action in actions) rect(tester, action).center.dx];
    expect(centres.last, closeTo(403, 0.01));
    for (var i = 1; i < centres.length; i++) {
      expect(centres[i] - centres[i - 1], closeTo(DynamicPostTheme.actionPitch, 0.01));
    }
  }

  testWidgets('131: a long text post', (tester) async {
    await shoot(
      tester,
      name: '131-post',
      post: const DynamicItem(
        id: '1',
        kind: DynamicKind.draw,
        author: _org,
        nodes: [DynamicTextNode('文')],
        stat: DynamicStat(forward: 24000, comment: 809, like: 10000, favourite: 82),
        comments: CommentArea(oid: 1, type: 11),
      ),
      check: (tester) {
        expect(rect(tester, 'post-back').center.dy, 86);
        expect(rect(tester, 'post-share').center, const Offset(372, 86));
        expect(rect(tester, 'post-more').center, const Offset(416, 86));
        // 131: the face 19.67-55.67 × 122-157.67.
        expect(rect(tester, 'post-author-face'), rectMoreOrLessEquals(const Rect.fromLTWH(20, 110 + 35 / 3, 36, 36)));
        // The first page counted none, but the post says 809.
        expect(find.text('评论 809'), findsOneWidget);
        bottomBar(tester, pillRight: 258, actions: ['post-comments', 'post-favourite', 'post-like']);
      },
      // 134: scrolled, the poster's face and name in the bar, the tabs under it, the hairline over their top.
      then: (tester, save) async {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(rect(tester, 'post-tab-comments').top, 62 + DynamicPostTheme.barRow);
        expect(tester.widget<AnimatedOpacity>(find.byKey(const ValueKey('post-bar-title'))).opacity, 1);
        expect(rect(tester, 'post-bar-rule'), rectMoreOrLessEquals(const Rect.fromLTRB(0, 110, 440, 110 + 2 / 3)));
        expect(tester.widget<AnimatedOpacity>(find.byKey(const ValueKey('post-bar-rule'))).opacity, 1);
        await save('134-pinned');
      },
    );
  });

  testWidgets('132: a repost, with its comments', (tester) async {
    await shoot(
      tester,
      name: '132-post',
      post: const DynamicItem(
        id: '2',
        kind: DynamicKind.forward,
        author: DynamicAuthor(
          mid: 2,
          name: '阿木又来了_PingRacing',
          face: '',
          pubTime: '2026年10月25日 20:38',
          location: '中国香港',
          vipPink: true,
          verify: DynamicVerify.personal,
        ),
        nodes: [DynamicTextNode('文')],
        original: DynamicItem(
          id: '3',
          kind: DynamicKind.video,
          author: DynamicAuthor(mid: 2, name: '阿木又来了_PingRacing', face: ''),
        ),
        stat: DynamicStat(comment: 64, like: 128),
        comments: CommentArea(oid: 2, type: 17),
      ),
      total: 64,
      comments: [
        Comment(
          rpid: 100,
          oid: 2,
          mid: 3,
          ctime: 1,
          likes: 3,
          replyCount: 27,
          location: 'IP属地：浙江',
          member: const CommentMember(mid: 3, name: '888只剩鹿角', level: 6, isVip: true),
          message: '阿哥说说新游戏策划怎么平衡三个职业呢不平衡感觉会被吐槽啊，小号玩家已经开始闹了',
        ),
      ],
      check: (tester) {
        // 132: the face 19.67-55.67 × 128-164, centred on three lines.
        expect(rect(tester, 'post-author-face').top, closeTo(128, 1));
        expect(find.text('IP属地：中国香港'), findsOneWidget);
        expect(rect(tester, 'post-tab-comments').height, DynamicPostTheme.tabsHeight);
        expect(find.byKey(const ValueKey('post-favourite')), findsNothing);
        bottomBar(tester, pillRight: 312, actions: ['post-comments', 'post-like']);
      },
    );
  });

  testWidgets('140: nine pictures', (tester) async {
    await shoot(
      tester,
      name: '140-post',
      post: const DynamicItem(
        id: '4',
        kind: DynamicKind.draw,
        author: DynamicAuthor(
          mid: 2001,
          name: '演示星河列车',
          face: '',
          pubTime: '2026年10月25日 15:00',
          location: '上海',
          vipPink: true,
          verify: DynamicVerify.organisation,
        ),
        nodes: [DynamicTextNode('文')],
        major: DynamicPictures(pictures: [DynamicPicture(url: '', width: 1000, height: 1000)]),
        stat: DynamicStat(forward: 120, comment: 4515, like: 17000, favourite: 414),
        comments: CommentArea(oid: 4, type: 11),
      ),
      total: 4515,
      check: (tester) {
        expect(find.text('IP属地：上海'), findsOneWidget);
        expect(find.text('评论 4515'), findsOneWidget);
        bottomBar(tester, pillRight: 258, actions: ['post-comments', 'post-favourite', 'post-like']);
      },
    );
  });
}
