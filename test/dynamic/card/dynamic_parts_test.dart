import 'dart:async';

import 'package:bili_core/api.dart' hide RichText, VideoPage;
import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/dynamic/card/dynamic_card.dart';
import 'package:bilifast/dynamic/card/dynamic_more_sheet.dart';
import 'package:bilifast/dynamic/card/dynamic_open.dart';
import 'package:bilifast/dynamic/card/dynamic_repost.dart';
import 'package:bilifast/dynamic/card/dynamic_video_box.dart';
import 'package:bilifast/dynamic/fake_dynamic_api.dart';
import 'package:bilifast/home/feed_inline_player.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player/playback_clock.dart';
import 'package:bilifast/player_ui/player_loading.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../playback/fakes.dart';
import '../../support/fake_player.dart';
import 'card_host.dart';

const _video = DynamicVideo(
  aid: 1,
  bvid: 'BV1GJ411x7h7',
  title: '投稿的标题',
  cover: '',
  durationText: '11:52',
  duration: 712,
  plays: '47.2万',
  danmaku: '52',
);

Future<void> _toastGone(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
}

Finder _toast(String text) => find.descendant(of: find.byKey(const ValueKey('toast')), matching: find.text(text));

void main() {
  group('⋮', () {
    Future<CardHost> open(WidgetTester tester, DynamicItem item, {FakeDynamicApi? api, bool loggedIn = true}) async {
      final host = await pumpCardHost(
        tester,
        DynamicCard(item: item),
        api: api,
        loggedIn: loggedIn,
      );
      await tester.tap(find.byKey(const ValueKey('dynamic-more')));
      await tester.pumpAndSettle();
      return host;
    }

    testWidgets('137: 分享, 取消关注 and 举报, then 取消, over the dimmed page', (tester) async {
      await open(tester, post('1'));
      expect(find.text('分享'), findsOneWidget);
      expect(find.text('取消关注'), findsOneWidget);
      expect(find.text('举报'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      final rows = [
        'share',
        'unfollow',
        'report',
      ].map((name) => tester.getRect(find.byKey(ValueKey('dynamic-more-$name'))));
      expect(rows.map((row) => row.height).toSet(), {50.0});
      await tester.tap(find.byKey(const ValueKey('dynamic-more-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dynamic-more-sheet')), findsNothing);
    });

    testWidgets('取消关注 shows only when the post offers it', (tester) async {
      await open(tester, post('1', menu: const [DynamicMenuItem.report]));
      expect(find.text('取消关注'), findsNothing);
      expect(find.text('举报'), findsOneWidget);
    });

    testWidgets('分享 hands the post link to the share sheet', (tester) async {
      final host = await open(tester, post('7788'));
      await tester.tap(find.byKey(const ValueKey('dynamic-more-share')));
      await tester.pumpAndSettle();
      expect(host.opened.shares, [Uri.parse('https://www.bilibili.com/opus/7788')]);
    });

    testWidgets('分享 that fails toasts 分享失败', (tester) async {
      await open(tester, post('7788'));
      DynamicOpen.share = (link) async => throw StateError('no share sheet');
      await tester.tap(find.byKey(const ValueKey('dynamic-more-share')));
      await tester.pumpAndSettle();
      expect(_toast('分享失败'), findsOneWidget);
      await _toastGone(tester);
    });

    testWidgets('取消关注 unfollows, tells every page, and toasts', (tester) async {
      final host = await open(tester, post('1'));
      final changes = <({int mid, bool following})>[];
      host.services.follows.addListener(() => changes.add(host.services.follows.last!));
      await tester.tap(find.byKey(const ValueKey('dynamic-more-unfollow')));
      await tester.pumpAndSettle();
      expect(host.api.unfollowed, [7]);
      expect(changes, [(mid: 7, following: false)]);
      expect(_toast('取消关注成功'), findsOneWidget);
      await _toastGone(tester);
    });

    testWidgets('取消关注 refused toasts why and tells no page', (tester) async {
      final api = FakeDynamicApi()..failures['unfollow'] = const BiliError.api(code: 22001, message: '不能对自己进行此操作');
      final host = await open(tester, post('1'), api: api);
      var told = false;
      host.services.follows.addListener(() => told = true);
      await tester.tap(find.byKey(const ValueKey('dynamic-more-unfollow')));
      await tester.pumpAndSettle();
      expect(told, isFalse);
      expect(_toast('不能对自己进行此操作'), findsOneWidget);
      await _toastGone(tester);
    });

    testWidgets('logged out, 取消关注 asks for the login', (tester) async {
      final host = await open(tester, post('1'), loggedIn: false);
      await tester.tap(find.byKey(const ValueKey('dynamic-more-unfollow')));
      await tester.pumpAndSettle();
      expect(host.gate.requests, 1);
      expect(host.api.unfollowed, isEmpty);
    });

    testWidgets('举报 toasts', (tester) async {
      await open(tester, post('1'));
      await tester.tap(find.byKey(const ValueKey('dynamic-more-report')));
      await tester.pumpAndSettle();
      expect(_toast('暂未开放'), findsOneWidget);
      await _toastGone(tester);
    });

    testWidgets('showDynamicMoreSheet opens on its own too', (tester) async {
      await pumpCardHost(
        tester,
        Builder(
          builder: (context) => GestureDetector(
            key: const ValueKey('open'),
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(showDynamicMoreSheet(context, post('1'))),
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dynamic-more-sheet')), findsOneWidget);
    });
  });

  group('a repost', () {
    final original = post(
      'o1',
      kind: DynamicKind.draw,
      author: const DynamicAuthor(mid: 55, name: '原作者', face: '', following: false),
      nodes: const [DynamicTextNode('原动态的文字')],
    );

    testWidgets("its block: @name in blue, + 关注, the original's text; a tap opens the original", (tester) async {
      final host = await pumpCardHost(
        tester,
        DynamicCard(
          item: post('1', kind: DynamicKind.forward, nodes: const [DynamicTextNode('转发说')], original: original),
        ),
      );
      expect(find.text('@原作者'), findsOneWidget);
      expect(find.text('关注'), findsOneWidget);
      expect(find.textContaining('原动态的文字', findRichText: true), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dynamic-repost-text-o1')));
      expect(host.opened.posts.single, (id: 'o1', toComments: false));
      await tester.tap(find.byKey(const ValueKey('dynamic-text-1')));
      expect(host.opened.posts.last, (id: '1', toComments: false), reason: 'outside the block, the repost itself');
      await tester.tap(find.byKey(const ValueKey('dynamic-repost-name')));
      expect(host.opened.spaces, [55]);
    });

    testWidgets('+ 关注 follows with the page call, then goes', (tester) async {
      final host = await pumpCardHost(tester, DynamicRepostBlock(original: original));
      await tester.tap(find.byKey(const ValueKey('dynamic-repost-follow')));
      await tester.pump();
      await tester.pump();
      expect(host.pageApi.calls, contains('follow on=true'));
      expect(find.byKey(const ValueKey('dynamic-repost-follow')), findsNothing);
      expect(host.services.follows.last, (mid: 55, following: true));
      await _toastGone(tester);
    });

    testWidgets('followed already, no + 关注', (tester) async {
      await pumpCardHost(
        tester,
        DynamicRepostBlock(
          original: post(
            'o2',
            author: const DynamicAuthor(mid: 56, name: '已关注的', face: ''),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('dynamic-repost-follow')), findsNothing);
    });

    testWidgets("a video original's box opens its video", (tester) async {
      final host = await pumpCardHost(
        tester,
        DynamicRepostBlock(
          original: post('o3', kind: DynamicKind.video, major: _video),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('dynamic-repost-block')));
      await tester.pump();
      expect(host.opened.videos.single.bvid, _video.bvid);
    });

    testWidgets("136: the original's pictures in one row 202 tall at their shapes, 6 apart, running off the right", (
      tester,
    ) async {
      final host = await pumpCardHost(
        tester,
        DynamicRepostBlock(
          original: post(
            'o5',
            kind: DynamicKind.draw,
            author: const DynamicAuthor(mid: 55, name: '原作者', face: ''),
            nodes: const [DynamicTextNode('原动态的文字')],
            major: const DynamicPictures(pictures: _pictures),
          ),
        ),
      );
      final block = tester.getRect(find.byKey(const ValueKey('dynamic-repost-block')));
      final text = tester.getRect(find.byKey(const ValueKey('dynamic-repost-text-o5')));
      final frames = [for (var i = 0; i < 3; i++) tester.getRect(find.byKey(ValueKey('dynamic-picture-$i')))];
      expect(frames.map((frame) => frame.height).toSet(), {DynamicCardTheme.repostStrip});
      expect(frames.first.top - text.bottom, DynamicCardTheme.repostStripTop);
      expect(block.bottom - frames.first.bottom, DynamicCardTheme.repostBottom);
      expect(frames.first.left - block.left, DynamicCardTheme.gutter);
      expect(frames[0].width, closeTo(202 * 1000 / 1200, 0.01));
      expect(frames[1].width, closeTo(202 * 900 / 1200, 0.01));
      expect(frames[2].width, 202, reason: 'square when its size is unknown');
      expect(frames[1].left - frames[0].right, closeTo(6, 0.01));
      expect(frames[2].right, greaterThan(block.right), reason: 'the row runs off the right edge');
      await tester.drag(find.byKey(const ValueKey('dynamic-picture-strip')), const Offset(-120, 0));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(const ValueKey('dynamic-picture-0'))).left, lessThan(frames.first.left));
      await tester.tap(find.byKey(const ValueKey('dynamic-picture-1')));
      await tester.pump();
      expect(find.byKey(const ValueKey('dynamic-picture-viewer')), findsOneWidget);
      expect(find.text('2/3'), findsOneWidget);
      expect(host.opened.posts, isEmpty, reason: 'the picture opens, not the original');
    });

    testWidgets("the post page opens a repost's picture in its own viewer through onOpen", (tester) async {
      final asked = <int>[];
      await pumpCardHost(
        tester,
        DynamicRepostBlock(
          detail: true,
          onOpen: asked.add,
          original: post('o6', kind: DynamicKind.draw, major: const DynamicPictures(pictures: _pictures)),
        ),
      );
      final block = tester.getRect(find.byKey(const ValueKey('dynamic-repost-block')));
      expect(tester.getRect(find.byKey(const ValueKey('dynamic-picture-0'))).left - block.left, 20);
      await tester.tap(find.byKey(const ValueKey('dynamic-picture-1')));
      await tester.pump();
      expect(asked, [1]);
      expect(find.byKey(const ValueKey('dynamic-picture-viewer')), findsNothing);
    });

    testWidgets('132: on the post page the block sits 20 in, its @name 24, the box 400 × 225 44 down', (tester) async {
      await pumpCardHost(
        tester,
        DynamicRepostBlock(
          detail: true,
          original: post(
            'o7',
            kind: DynamicKind.video,
            author: const DynamicAuthor(mid: 57, name: '原作者', face: ''),
            nodes: const [],
            major: _video,
          ),
        ),
      );
      final block = tester.getRect(find.byKey(const ValueKey('dynamic-repost-block')));
      final box = tester.getRect(
        find.descendant(of: find.byKey(ValueKey('dynamic-video-${_video.bvid}')), matching: find.byType(AspectRatio)),
      );
      expect(box.shift(-block.topLeft), const Rect.fromLTWH(20, 44, 400, 225));
      expect(tester.getTopLeft(find.byKey(const ValueKey('dynamic-repost-name'))).dx - block.left, 24);
      final title = tester.getRect(find.byKey(ValueKey('dynamic-video-title-${_video.bvid}')));
      expect(title.top - box.bottom, closeTo(6, 0.01));
      expect(block.height, closeTo(308, 0.01));
    });

    testWidgets('+ 关注 keeps a 关注 made on another page before it was built, and follows later changes', (tester) async {
      final shown = ValueNotifier(false);
      addTearDown(shown.dispose);
      final host = await pumpCardHost(
        tester,
        ValueListenableBuilder(
          valueListenable: shown,
          builder: (context, value, _) => value ? DynamicRepostBlock(original: original) : const SizedBox.shrink(),
        ),
      );
      host.services.follows.changed(55, following: true);
      shown.value = true;
      await tester.pump();
      expect(find.byKey(const ValueKey('dynamic-repost-follow')), findsNothing, reason: 'followed elsewhere first');
      host.services.follows.changed(55, following: false);
      await tester.pump();
      expect(find.byKey(const ValueKey('dynamic-repost-follow')), findsOneWidget);
    });

    testWidgets("an original that didn't decode draws no block; a deleted one keeps its words", (tester) async {
      await pumpCardHost(
        tester,
        Column(
          children: [
            DynamicCard(
              item: post(
                '1',
                kind: DynamicKind.forward,
                nodes: const [DynamicTextNode('转发说')],
                original: post('o8', author: const DynamicAuthor(mid: 0, name: '', face: ''), nodes: const []),
              ),
            ),
            DynamicCard(
              item: post(
                '2',
                kind: DynamicKind.forward,
                original: post(
                  'o9',
                  kind: DynamicKind.other,
                  author: const DynamicAuthor(mid: 0, name: '', face: ''),
                  nodes: const [],
                  major: const DynamicOtherMajor(typeName: 'MAJOR_TYPE_NONE', title: '源动态已被作者删除'),
                ),
              ),
            ),
            DynamicRepostBlock(
              key: const ValueKey('alone'),
              original: post('o10', author: const DynamicAuthor(mid: 0, name: '', face: ''), nodes: const []),
            ),
          ],
        ),
      );
      expect(find.byKey(const ValueKey('dynamic-repost-o8')), findsNothing);
      expect(find.byKey(const ValueKey('dynamic-repost-o9')), findsOneWidget);
      expect(find.textContaining('源动态已被作者删除', findRichText: true), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('alone'))).height, 0, reason: 'the post page draws none either');
    });

    testWidgets('a deleted original shows its words only and opens nothing', (tester) async {
      final host = await pumpCardHost(
        tester,
        DynamicRepostBlock(
          original: post(
            'o4',
            kind: DynamicKind.other,
            author: const DynamicAuthor(mid: 0, name: '', face: ''),
            nodes: const [],
            major: const DynamicOtherMajor(typeName: 'MAJOR_TYPE_NONE', title: '源动态已被作者删除'),
          ),
        ),
      );
      expect(find.textContaining('源动态已被作者删除', findRichText: true), findsOneWidget);
      expect(find.byKey(const ValueKey('dynamic-repost-name')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('dynamic-repost-block')));
      expect(host.opened.posts, isEmpty);
    });
  });

  group('the video box', () {
    testWidgets('the cover with its length, plays and danmaku, the TV, and the title under it', (tester) async {
      await pumpCardHost(tester, const DynamicVideoBox(video: _video));
      expect(find.text('11:52'), findsOneWidget);
      expect(find.textContaining('47.2万播放', findRichText: true), findsOneWidget);
      expect(find.textContaining('52弹幕', findRichText: true), findsOneWidget);
      expect(find.byKey(const ValueKey('dynamic-video-tv')), findsOneWidget);
      expect(find.byKey(const ValueKey('dynamic-video-badge')), findsNothing);
      expect(find.text('投稿的标题'), findsOneWidget);
    });

    testWidgets('动态视频 in its pink badge, no title when showTitle is off', (tester) async {
      await pumpCardHost(
        tester,
        const DynamicVideoBox(
          video: DynamicVideo(aid: 2, bvid: 'BV1x', title: '标题', cover: '', badge: '动态视频'),
          showTitle: false,
        ),
      );
      expect(find.text('动态视频'), findsOneWidget);
      expect(find.text('标题'), findsNothing);
    });

    testWidgets('a 动态视频 post on a card shows no title; a 投稿视频 one does (128, 139)', (tester) async {
      await pumpCardHost(
        tester,
        Column(
          children: [
            DynamicCard(
              item: post(
                '1',
                kind: DynamicKind.video,
                major: const DynamicVideo(aid: 2, bvid: 'BV1x', title: '动态视频的标题', cover: '', badge: '动态视频'),
              ),
            ),
            DynamicCard(
              item: post('2', kind: DynamicKind.video, nodes: const [], major: _video),
            ),
          ],
        ),
      );
      expect(find.text('动态视频的标题'), findsNothing);
      expect(find.text('投稿的标题'), findsOneWidget);
    });

    testWidgets('inline: the host picks it and it plays muted with 🔇 and the played line; covered, it pauses', (
      tester,
    ) async {
      FeedInlineChoices.reset();
      addTearDown(FeedInlineChoices.reset);
      final players = <FakePlayer>[];
      final logger = Logger(session: 'test');
      final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
      late FeedInlineHost inline;
      final host = await pumpCardHost(
        tester,
        Builder(
          builder: (context) {
            return DynamicCard(
              item: post('1', kind: DynamicKind.video, nodes: const [], major: _video),
              inline: inline,
            );
          },
        ),
        players: (environment) async {
          final player = FakePlayer();
          players.add(player);
          return PlaybackController(
            client: environment.client,
            engine: FakeEngine(),
            player: player,
            clock: ManualClock(10000).clock,
            now: () => now,
            startTimer: FakeTimers().start,
            logger: logger,
          );
        },
        before: (services) {
          inline = FeedInlineHost(viewport: () => const Rect.fromLTWH(0, 0, 440, 956), pip: services.pipKeeper);
          addTearDown(inline.dispose);
        },
      );
      inline.shown = true;
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(inline.playing, isA<DynamicVideoBoxState>(), reason: 'registered and picked');
      expect(players, hasLength(1));
      expect(find.byType(PlayerLoading), findsOneWidget, reason: 'the TV while it loads');
      players.single.emit(const StatusChanged(PlayerStatus.playing));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byKey(const ValueKey('dynamic-video-sound')), findsOneWidget);
      expect(find.byKey(const ValueKey('dynamic-video-progress')), findsOneWidget);
      expect(find.byKey(const ValueKey('dynamic-video-tv')), findsNothing);
      expect(players.single.muted, isTrue);
      await tester.tap(find.byKey(const ValueKey('dynamic-video-sound')));
      await tester.pump();
      expect(FeedInlineChoices.sound.value, isTrue);
      expect(host.opened.videos, isEmpty, reason: 'the speaker opens nothing');
      inline.shown = false;
      await tester.pump();
      await tester.pump();
      expect(players.single.calls.lastWhere((call) => call == 'play' || call == 'pause'), 'pause');
      await tester.tap(find.byKey(const ValueKey('dynamic-video-BV1GJ411x7h7')));
      await tester.pump();
      expect(host.opened.videos.single.playback, isNotNull, reason: 'the page takes the running video over');
      await tester.pumpWidget(const SizedBox.shrink());
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    });

    testWidgets("the picture viewer covers the playing card's page, so its video pauses until the viewer closes", (
      tester,
    ) async {
      final setup = await _inlineHost(
        tester,
        (inline) => _RouteHost(
          inline: inline,
          child: Column(
            children: [
              DynamicCard(
                item: post('1', kind: DynamicKind.video, nodes: const [], major: _video),
                inline: inline,
              ),
              DynamicCard(
                item: post('2', kind: DynamicKind.draw, major: const DynamicPictures(pictures: _pictures)),
              ),
            ],
          ),
        ),
      );
      await _settle(tester);
      final player = setup.players.single;
      player.emit(const StatusChanged(PlayerStatus.playing));
      await _settle(tester, frames: 4);
      expect(setup.inline.playing, isA<DynamicVideoBoxState>());
      final card = tester.element(find.byType(DynamicCard).first);
      final playing = player.calls.length;
      await tester.tap(find.byKey(const ValueKey('dynamic-picture-1')));
      await _settle(tester, frames: 4);
      expect(find.byKey(const ValueKey('dynamic-picture-viewer')), findsOneWidget);
      expect(ModalRoute.isCurrentOf(card), isFalse, reason: 'the viewer is a route over the page');
      expect(setup.inline.playing, isNull);
      expect(player.calls.skip(playing), contains('pause'));
      expect(await tester.state<NavigatorState>(find.byType(Navigator)).maybePop(), isTrue);
      await _settle(tester, frames: 4);
      expect(find.byKey(const ValueKey('dynamic-picture-viewer')), findsNothing);
      expect(ModalRoute.isCurrentOf(card), isTrue);
      expect(setup.inline.playing, isA<DynamicVideoBoxState>());
      expect(_lastPlayOrPause(player), 'play', reason: 'the page shown again, the card plays on');
      await _tearDown(tester);
    });

    testWidgets('back from the page, the card plays on the part the page left it on, and opens there again', (
      tester,
    ) async {
      final setup = await _inlineHost(
        tester,
        (inline) => DynamicCard(
          item: post('1', kind: DynamicKind.video, nodes: const [], major: _video),
          inline: inline,
        ),
      );
      final routes = <VideoRoute>[];
      final pageLeft = Completer<void>();
      DynamicOpen.video = (context, route) {
        routes.add(route);
        return pageLeft.future;
      };
      setup.inline.shown = true;
      await _settle(tester);
      setup.players.single.emit(const StatusChanged(PlayerStatus.playing));
      await _settle(tester, frames: 4);
      await tester.tap(find.byKey(ValueKey('dynamic-video-${_video.bvid}')));
      await tester.pump();
      final playback = routes.single.playback!;
      // The page moves on to the second part (选集), then lets the video go.
      playback.openOnPage(_video.bvid, cid: 137649200);
      await _settle(tester);
      playback.close();
      await tester.pump();
      final asked = setup.host.http.to(Canned.playUrlPath).length;
      pageLeft.complete();
      await _settle(tester);
      final again = setup.host.http.to(Canned.playUrlPath).skip(asked).toList();
      expect(again, isNotEmpty, reason: 'the card plays again');
      expect(again.map((request) => request.url.queryParameters['cid']).toSet(), {'137649200'});
      // Paused long enough to let its player go, a tap opens the page on that part, where the card stopped.
      setup.inline.shown = false;
      await tester.pump();
      await tester.pump(const Duration(seconds: 31));
      await tester.tap(find.byKey(ValueKey('dynamic-video-${_video.bvid}')));
      await tester.pump();
      expect(routes.last.playback, isNull);
      expect(routes.last.cid, 137649200);
      expect(routes.last.start, isNotNull);
      await _tearDown(tester);
    });

    testWidgets("a tap on a card whose video failed opens the page where the card's player stopped", (tester) async {
      final setup = await _inlineHost(
        tester,
        (inline) => DynamicCard(
          item: post('1', kind: DynamicKind.video, nodes: const [], major: _video),
          inline: inline,
        ),
      );
      setup.inline.shown = true;
      await _settle(tester);
      final player = setup.players.single;
      player
        ..emit(const StatusChanged(PlayerStatus.loading))
        ..emit(const StatusChanged(PlayerStatus.playing));
      setup.time.advance(PlaybackClock.jumpSettleMs);
      player.emit(PositionChanged(seconds: 25, hostMs: setup.time.clock.nowMs(), rate: 1));
      await _settle(tester, frames: 4);
      // The connection drops (BTR falls back to direct), drops again, and fresh addresses can't be had: the card's
      // player gives up at 25 s.
      setup.host.http.errors[Canned.playUrlPath] = StateError('offline');
      player.emit(const PlayerFailed('lost', domain: 'NSURLErrorDomain'));
      await _settle(tester);
      player
        ..emit(const StatusChanged(PlayerStatus.loading))
        ..emit(const PlayerFailed('lost', domain: 'NSURLErrorDomain'));
      await _settle(tester);
      expect(setup.controllers.single.phase, PlaybackPhase.failed);
      await tester.tap(find.byKey(ValueKey('dynamic-video-${_video.bvid}')));
      await tester.pump();
      final route = setup.host.opened.videos.single;
      expect(route.playback, isNull, reason: 'a failed video is opened afresh');
      expect(route.start, closeTo(25, 0.5));
      await _tearDown(tester);
    });
  });
}

const _pictures = [
  DynamicPicture(url: '', width: 1000, height: 1200),
  DynamicPicture(url: '', width: 900, height: 1200),
  DynamicPicture(url: ''),
];

String _lastPlayOrPause(FakePlayer player) => player.calls.lastWhere((call) => call == 'play' || call == 'pause');

Future<void> _settle(WidgetTester tester, {int frames = 20}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tearDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _settle(tester, frames: 10);
}

/// A card host whose players are fakes on the canned client, with an inline host over the whole screen.
Future<
  ({
    CardHost host,
    FeedInlineHost inline,
    List<FakePlayer> players,
    List<PlaybackController> controllers,
    ManualClock time,
  })
>
_inlineHost(WidgetTester tester, Widget Function(FeedInlineHost inline) build) async {
  FeedInlineChoices.reset();
  addTearDown(FeedInlineChoices.reset);
  final players = <FakePlayer>[];
  final controllers = <PlaybackController>[];
  final logger = Logger(session: 'test');
  final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
  final time = ManualClock(10000);
  late FeedInlineHost inline;
  final host = await pumpCardHost(
    tester,
    Builder(builder: (context) => build(inline)),
    players: (environment) async {
      final player = FakePlayer();
      players.add(player);
      final controller = PlaybackController(
        client: environment.client,
        engine: FakeEngine(),
        player: player,
        clock: time.clock,
        now: () => now,
        startTimer: FakeTimers().start,
        logger: logger,
      );
      controllers.add(controller);
      return controller;
    },
    before: (services) {
      inline = FeedInlineHost(viewport: () => const Rect.fromLTWH(0, 0, 440, 956), pip: services.pipKeeper);
      addTearDown(inline.dispose);
    },
  );
  return (host: host, inline: inline, players: players, controllers: controllers, time: time);
}

/// Shows [inline]'s cards while their page is the current route, as the 关注 tab and the post page do.
class _RouteHost extends StatelessWidget {
  const _RouteHost({required this.inline, required this.child});

  final FeedInlineHost inline;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    inline.shown = ModalRoute.isCurrentOf(context) ?? true;
    return child;
  }
}
