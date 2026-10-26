import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/swipe_back_route.dart';
import 'package:bilifast/comments/comment_overlays.dart';
import 'package:bilifast/comments/comment_row.dart';
import 'package:bilifast/comments/composer.dart';
import 'package:bilifast/comments/picture_viewer.dart';
import 'package:bilifast/comments/thread_view.dart';
import 'package:bilifast/dynamic/card/dynamic_repost.dart';
import 'package:bilifast/dynamic/card/dynamic_rich_text.dart';
import 'package:bilifast/dynamic/fake_dynamic_api.dart';
import 'package:bilifast/dynamic/post/post_bottom_bar.dart';
import 'package:bilifast/dynamic/post/post_page.dart';
import 'package:bilifast/dynamic/post/post_route.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/shared/loading_tv.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/fake_keychain.dart';
import '../../home/fake_login_gate.dart';
import '../../playback/fakes.dart';

/// [FakePageApi] that also notes the comment area each comment call names.
class _AreaApi extends FakePageApi {
  final areas = <String>[];

  @override
  Future<CommentPage> comments({required int aid, required CommentSort sort, String? offset, int type = 1}) {
    areas.add('comments $aid $type');
    return super.comments(aid: aid, sort: sort, offset: offset, type: type);
  }

  @override
  Future<Comment> postComment({
    required int aid,
    required String message,
    int root = 0,
    int parent = 0,
    bool syncToDynamic = false,
    Map<String, int> mentions = const {},
    List<UploadedPicture> pictures = const [],
    int type = 1,
  }) {
    areas.add('postComment $aid $type');
    return super.postComment(
      aid: aid,
      message: message,
      root: root,
      parent: parent,
      syncToDynamic: syncToDynamic,
      mentions: mentions,
      pictures: pictures,
      type: type,
    );
  }

  @override
  Future<ThreadPage> thread({
    required int aid,
    required int root,
    required int page,
    required CommentSort sort,
    int type = 1,
  }) {
    areas.add('thread $aid $type');
    return super.thread(aid: aid, root: root, page: page, sort: sort, type: type);
  }

  @override
  Future<void> likeComment({required int aid, required int rpid, required bool on, int type = 1}) {
    areas.add('likeComment $aid $type');
    return super.likeComment(aid: aid, rpid: rpid, on: on, type: type);
  }

  @override
  Future<void> hateComment({required int aid, required int rpid, required bool on, int type = 1}) {
    areas.add('hateComment $aid $type');
    return super.hateComment(aid: aid, rpid: rpid, on: on, type: type);
  }

  @override
  Future<void> deleteComment({required int aid, required int rpid, int type = 1}) {
    areas.add('deleteComment $aid $type');
    return super.deleteComment(aid: aid, rpid: rpid, type: type);
  }
}

Comment _comment(int rpid, {int replyCount = 0, int mid = 2001, List<Comment> preview = const []}) => Comment(
  rpid: rpid,
  oid: 9004,
  mid: mid,
  ctime: rpid,
  likes: 10,
  replyCount: replyCount,
  member: CommentMember(mid: mid, name: '测试用户$rpid', level: 5),
  message: '第$rpid条评论',
  runs: [TextRun('第$rpid条评论')],
  previewReplies: preview,
);

const _drawId = '9004';
const _forwardId = '9003';

class _Harness {
  _Harness(this.dynamicApi, this.pageApi, this.gate, this.navigator, this.shared, this.opened);

  final FakeDynamicApi dynamicApi;
  final _AreaApi pageApi;
  final FakeLoginGate gate;
  final GlobalKey<NavigatorState> navigator;
  final List<Uri> shared;
  final List<VideoRoute> opened;
}

void main() {
  final logs = MemorySink();
  setUp(() => Logger.shared.add(logs));
  tearDown(() => Logger.shared.remove(logs));

  Finder key(String value) => find.byKey(ValueKey(value));
  Finder row(int rpid) => find.byKey(ValueKey(rpid));
  Finder inRow(int rpid, String value) => find.descendant(of: row(rpid), matching: key(value));

  /// The 9-picture post runs past the first screen: scrolls a comment row to the middle before a tap.
  Future<void> reveal(WidgetTester tester, int rpid) async {
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(row(rpid)), alignment: 0.5);
    await tester.pump();
  }

  Future<void> frames(WidgetTester tester, [int count = 12]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// The post page pushed over a blank home at the iPhone's size. [hold] keeps the detail waiting; [failure] makes it
  /// throw; [posts] replaces the demo's. [firstPage] is the comments' first answer as given, [commentsFailure] what
  /// the comment call throws instead; [shareFails] makes the share sheet throw.
  Future<_Harness> show(
    WidgetTester tester, {
    String id = _drawId,
    DynamicItem? item,
    bool toComments = false,
    bool loggedIn = true,
    bool hold = false,
    Object? failure,
    List<DynamicItem>? posts,
    List<Comment>? comments,
    CommentPage? firstPage,
    Object? commentsFailure,
    bool shareFails = false,
  }) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: 62, bottom: 34)
      ..viewPadding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    final logger = Logger(session: 'test');
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: Canned.http(loggedIn: loggedIn),
      logger: logger,
    );
    if (loggedIn) {
      environment.useFakeAccount();
    } else {
      await environment.refreshAccount();
    }
    final playback = AppPlayback(() => Completer<PlaybackController>().future);
    addTearDown(playback.dispose);
    final dynamicApi = FakeDynamicApi(posts: posts ?? FakeDynamicApi.demoPosts);
    if (hold) dynamicApi.holds['detail'] = Completer<void>();
    if (failure != null) dynamicApi.failures['detail'] = failure;
    final reply1 = _comment(201);
    final reply2 = _comment(202);
    final pageApi = _AreaApi()
      ..commentList =
          comments ??
          [
            _comment(100, replyCount: 2, preview: [reply1, reply2]),
            for (var i = 1; i <= 25; i++) _comment(300 + i),
          ]
      ..threadReplies = {
        100: [reply1, reply2],
      };
    if (firstPage != null) pageApi.commentPage = firstPage;
    if (commentsFailure != null) pageApi.failures['comments'] = commentsFailure;
    final gate = FakeLoginGate();
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      pageApi: pageApi,
      dynamicApi: dynamicApi,
      loginGate: gate,
    );
    final navigator = GlobalKey<NavigatorState>();
    final shared = <Uri>[];
    final opened = <VideoRoute>[];
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => AppScope(services: services, child: child!),
        home: const SizedBox(),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        SwipeBackPageRoute<void>(
          builder: (_) => DynamicPostPage(
            id: id,
            item: item,
            toComments: toComments,
            share: (link) async {
              if (shareFails) throw StateError('no share sheet');
              shared.add(link);
              return true;
            },
            openPage: (context, route) async => opened.add(route),
          ),
        ),
      ),
    );
    await frames(tester);
    return _Harness(dynamicApi, pageApi, gate, navigator, shared, opened);
  }

  Future<void> back(WidgetTester tester, _Harness harness) async {
    unawaited(harness.navigator.currentState!.maybePop());
    await frames(tester);
  }

  /// Lets the toast go, so no timer outlives the test.
  Future<void> settleToast(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
  }

  double tabsTop(WidgetTester tester) => tester.getTopLeft(key('post-tab-comments')).dy;

  double opacity(WidgetTester tester, String value) => tester.widget<AnimatedOpacity>(key(value)).opacity;

  testWidgets('openDynamicPost pushes the page on the plain swipe-back route', (tester) async {
    final harness = await show(tester);
    unawaited(harness.navigator.currentState!.maybePop());
    await frames(tester);
    expect(find.byType(DynamicPostPage), findsNothing);
    unawaited(openDynamicPost(harness.navigator.currentContext!, id: _drawId));
    await frames(tester);
    expect(find.byType(DynamicPostPage), findsOneWidget);
    expect(ModalRoute.of(tester.element(find.byType(DynamicPostPage))), isA<SwipeBackPageRoute<void>>());
    await tester.tap(key('post-back'));
    await frames(tester);
    expect(find.byType(DynamicPostPage), findsNothing);
  });

  testWidgets('‹ and 正在努力加载... alone until the detail answers, then the post, its tabs and its bar', (tester) async {
    final harness = await show(tester, hold: true);
    expect(key('post-loading'), findsOneWidget);
    expect(find.text(LoadingTvState.message), findsOneWidget);
    expect(key('post-back'), findsOneWidget);
    expect(key('post-share'), findsNothing);
    expect(key('post-more'), findsNothing);
    expect(key('post-bottom-bar'), findsNothing);
    expect(harness.dynamicApi.calls, ['detail $_drawId']);
    // Centred on the screen, as 133's TV.
    expect(tester.getCenter(key('post-loading')).dy, closeTo(478, 1));

    harness.dynamicApi.holds['detail']!.complete();
    await frames(tester);
    expect(key('post-loading'), findsNothing);
    expect(key('post-share'), findsOneWidget);
    expect(key('post-more'), findsOneWidget);
    expect(find.text('演示星河列车'), findsWidgets);
    expect(find.text('4小时前'), findsOneWidget);
    expect(key('post-verify'), findsOneWidget);
    final text = tester.widget<DynamicRichText>(find.byType(DynamicRichText));
    expect(text.nodes, FakeDynamicApi.demoPosts[3].nodes);
    expect(text.maxLines, isNull);
    expect(text.style.fontSize, DynamicPostTheme.text);
    // 评论 N follows the list's own count once its first page is in.
    expect(find.text('评论 ${harness.pageApi.commentTotal}'), findsOneWidget);
    expect(find.descendant(of: key('post-comments'), matching: find.text('${harness.pageApi.commentTotal}')), findsOne);
    expect(find.text('赞和转发 1.7万'), findsOneWidget);
    expect(key('post-bottom-bar'), findsOneWidget);
    expect(find.text(PostBottomBar.prompt), findsOneWidget);

    final event = logs.events.lastWhere((event) => event.msg == 'dynamic post');
    expect(event.f.keys.toSet(), {'kind', 'type', 'commentType', 'ms'});
    expect(event.f['kind']!.toJson(), 'draw');
    expect(event.f['commentType']!.toJson(), 11);
    await back(tester, harness);
  });

  testWidgets('a failed detail shows why with 重试, which asks again', (tester) async {
    final harness = await show(tester, failure: const BiliError.http(500));
    expect(key('post-failed'), findsOneWidget);
    expect(find.text('网络请求失败（HTTP 500）'), findsOneWidget);
    expect(key('post-bottom-bar'), findsNothing);
    harness.dynamicApi.failures.remove('detail');
    await tester.tap(key('post-retry'));
    await frames(tester);
    expect(harness.dynamicApi.calls, ['detail $_drawId', 'detail $_drawId']);
    expect(key('post-failed'), findsNothing);
    expect(key('post-bottom-bar'), findsOneWidget);
    await back(tester, harness);
  });

  testWidgets('a deleted post says so with no 重试', (tester) async {
    final harness = await show(tester, id: '404');
    expect(find.text('动态不存在或已被删除'), findsOneWidget);
    expect(key('post-retry'), findsNothing);
    await back(tester, harness);
  });

  testWidgets('scrolled, the poster comes into the bar and the tabs pin under it', (tester) async {
    final harness = await show(tester);
    const barBottom = 62 + DynamicPostTheme.barRow;
    expect(opacity(tester, 'post-bar-title'), 0);
    expect(opacity(tester, 'post-bar-rule'), 0);
    expect(tabsTop(tester), greaterThan(barBottom));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1200));
    await frames(tester);
    expect(opacity(tester, 'post-bar-title'), 1);
    expect(opacity(tester, 'post-bar-rule'), 1);
    expect(tabsTop(tester), closeTo(barBottom, 0.01));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 2000));
    await frames(tester, 20);
    expect(opacity(tester, 'post-bar-title'), 0);
    expect(tabsTop(tester), greaterThan(barBottom));
    await back(tester, harness);
  });

  testWidgets('toComments puts the tabs under the bar once the post shows', (tester) async {
    final harness = await show(tester, toComments: true);
    expect(tabsTop(tester), closeTo(62 + DynamicPostTheme.barRow, 0.01));
    expect(find.text('第100条评论'), findsOneWidget);
    await back(tester, harness);
  });

  testWidgets('💬 scrolls to 评论', (tester) async {
    final harness = await show(tester);
    await tester.tap(key('post-comments'));
    await frames(tester);
    expect(tabsTop(tester), closeTo(62 + DynamicPostTheme.barRow, 0.01));
    await back(tester, harness);
  });

  testWidgets("comments load for the list item's area, else the detail's", (tester) async {
    final item = FakeDynamicApi.demoPosts[3];
    var harness = await show(
      tester,
      item: DynamicItem(
        id: item.id,
        kind: item.kind,
        author: item.author,
        comments: const CommentArea(oid: 777, type: 17),
      ),
    );
    expect(harness.pageApi.areas, ['comments 777 17']);
    expect(find.byType(CommentRow), findsWidgets);
    await back(tester, harness);

    harness = await show(tester);
    expect(harness.pageApi.areas, ['comments 9004 11']);
    await back(tester, harness);
  });

  testWidgets('点我发评论 opens the composer and posts to the post', (tester) async {
    final harness = await show(tester);
    await tester.tap(key('post-write'));
    await frames(tester);
    expect(find.byType(Composer), findsOneWidget);
    await tester.enterText(key('composer-field'), '第一');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('发布'));
    await frames(tester, 20);
    expect(harness.pageApi.posts.single.root, 0);
    expect(harness.pageApi.areas.last, 'postComment 9004 11');
    expect(find.byType(Composer), findsNothing);
    expect(tester.widgetList<CommentRow>(find.byType(CommentRow)).first.comment.message, '第一');
    await back(tester, harness);
  });

  testWidgets('logged out, 点我发评论 and 👍 go to the login gate', (tester) async {
    final harness = await show(tester, loggedIn: false);
    await tester.tap(key('post-write'));
    await frames(tester);
    expect(find.byType(Composer), findsNothing);
    expect(harness.gate.requests, 1);
    await tester.tap(key('post-like'));
    await frames(tester);
    expect(harness.gate.requests, 2);
    expect(harness.dynamicApi.likes, isEmpty);
    await back(tester, harness);
  });

  testWidgets('回复 on a row replies to it; 共N条回复 opens 评论详情, which back closes first', (tester) async {
    final harness = await show(tester);
    await reveal(tester, 100);
    await tester.tap(inRow(100, 'comment-reply').first);
    await frames(tester);
    expect(find.text('回复 测试用户100 :'), findsOneWidget);
    await tester.enterText(key('composer-field'), '你好');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('发布'));
    await frames(tester, 20);
    expect((harness.pageApi.posts.single.root, harness.pageApi.posts.single.parent), (100, 100));
    expect(harness.pageApi.areas.last, 'postComment 9004 11');

    await reveal(tester, 100);
    await tester.tap(inRow(100, 'comment-replies'));
    await frames(tester, 20);
    expect(find.byType(ThreadView), findsOneWidget);
    expect(harness.pageApi.calls.where((call) => call.startsWith('thread root=100')), isNotEmpty);
    expect(harness.pageApi.areas.last, 'thread 9004 11');
    await back(tester, harness);
    expect(find.byType(ThreadView), findsNothing);
    expect(find.byType(DynamicPostPage), findsOneWidget, reason: 'back closed the thread, not the page');
    await back(tester, harness);
    expect(find.byType(DynamicPostPage), findsNothing);
  });

  testWidgets('a comment liked, 踩 and the own comment deleted name the post\'s area', (tester) async {
    final harness = await show(tester, comments: [_comment(100), _comment(101, mid: 1)]);
    await reveal(tester, 100);
    await tester.tap(inRow(100, 'comment-like'));
    await frames(tester);
    expect(harness.pageApi.areas.last, 'likeComment 9004 11');
    await tester.tap(inRow(100, 'comment-dislike'));
    await frames(tester);
    expect(harness.pageApi.areas.last, 'hateComment 9004 11');

    await reveal(tester, 101);
    await tester.tap(inRow(101, 'comment-more'));
    await frames(tester);
    await tester.tap(key('comment-delete'));
    await frames(tester);
    expect(find.text('确定删除这条评论吗？'), findsOneWidget);
    await tester.tap(key('comment-delete-删除'));
    await frames(tester);
    expect(harness.pageApi.areas.last, 'deleteComment 9004 11');
    expect(row(101), findsNothing);
    await back(tester, harness);
  });

  testWidgets('a time link does nothing; a video link opens the video', (tester) async {
    final harness = await show(tester);
    final callbacks = tester.widget<CommentOverlays>(find.byType(CommentOverlays)).callbacks;
    callbacks.seek(30);
    callbacks.openVideo('BV1GJ411x7h7');
    await frames(tester);
    expect(harness.opened.single.bvid, 'BV1GJ411x7h7');
    await back(tester, harness);
  });

  testWidgets('👍 turns pink with its count at once, and back if Bilibili refuses', (tester) async {
    final harness = await show(tester, id: _forwardId);
    Color? likeInk() => tester.widget<Image>(find.descendant(of: key('post-like'), matching: find.byType(Image))).color;
    final hold = harness.dynamicApi.holds['like'] = Completer<void>();
    expect(find.text('赞和转发 2'), findsOneWidget);
    expect(likeInk(), DynamicPostTheme.actionInk);
    await tester.tap(key('post-like'));
    await tester.pump();
    expect(likeInk(), DynamicPostTheme.actionLiked);
    expect(find.descendant(of: key('post-like'), matching: find.text('3')), findsOneWidget);
    expect(find.text('赞和转发 3'), findsOneWidget);
    hold.complete();
    await frames(tester);
    expect(harness.dynamicApi.likes.single, (id: _forwardId, on: true));

    harness.dynamicApi
      ..holds.remove('like')
      ..failures['like'] = const BiliError.api(code: 65006, message: '已赞过');
    await tester.tap(key('post-like'));
    await frames(tester);
    expect(likeInk(), DynamicPostTheme.actionLiked, reason: 'the refused unlike is rolled back');
    expect(find.text('赞和转发 3'), findsOneWidget);
    expect(find.text('B 站返回错误 65006：已赞过'), findsOneWidget);
    await settleToast(tester);
    await back(tester, harness);
  });

  testWidgets('⭐ shows only with a 收藏 count and toasts; 赞和转发 toasts', (tester) async {
    var harness = await show(tester);
    expect(key('post-favourite'), findsOneWidget);
    expect(find.text('414'), findsOneWidget);
    await tester.tap(key('post-favourite'));
    await tester.pump();
    expect(find.text('暂未开放'), findsOneWidget);
    await settleToast(tester);
    await tester.tap(key('post-tab-reactions'));
    await tester.pump();
    expect(find.text('暂未开放'), findsOneWidget);
    await settleToast(tester);
    await back(tester, harness);

    harness = await show(tester, id: _forwardId);
    expect(key('post-favourite'), findsNothing);
    expect(find.byType(DynamicRepostBlock), findsOneWidget);
    final block = tester.widget<DynamicRepostBlock>(find.byType(DynamicRepostBlock));
    expect(block.detail, isTrue);
    expect(block.inline, isNotNull, reason: 'its video plays muted');
    await back(tester, harness);
  });

  testWidgets('↗ and ⋮ hand the post\'s link to the share sheet', (tester) async {
    final harness = await show(tester);
    await tester.tap(key('post-share'));
    await tester.pump();
    await tester.tap(key('post-more'));
    await tester.pump();
    expect(harness.shared, [
      Uri.parse('https://www.bilibili.com/opus/$_drawId'),
      Uri.parse('https://www.bilibili.com/opus/$_drawId'),
    ]);
    await back(tester, harness);
  });

  testWidgets('IP属地 is under the time for a repost and under the body for a picture post', (tester) async {
    const author = DynamicAuthor(mid: 5, name: '演示', face: '', pubTime: '2026年10月25日 20:38', location: '上海');
    final posts = [
      const DynamicItem(id: '1', kind: DynamicKind.forward, author: author, comments: CommentArea(oid: 1, type: 17)),
      const DynamicItem(id: '2', kind: DynamicKind.draw, author: author, comments: CommentArea(oid: 2, type: 11)),
      const DynamicItem(
        id: '3',
        kind: DynamicKind.draw,
        author: DynamicAuthor(mid: 5, name: '演示', face: ''),
        comments: CommentArea(oid: 3, type: 11),
      ),
    ];
    var harness = await show(tester, id: '1', posts: posts);
    expect(key('post-location-top'), findsOneWidget);
    expect(key('post-location'), findsNothing);
    expect(find.text('IP属地：上海'), findsOneWidget);
    await back(tester, harness);
    harness = await show(tester, id: '2', posts: posts);
    expect(key('post-location'), findsOneWidget);
    expect(key('post-location-top'), findsNothing);
    await back(tester, harness);
    harness = await show(tester, id: '3', posts: posts);
    expect(find.textContaining('IP属地'), findsNothing);
    await back(tester, harness);
  });

  testWidgets('a post with no comment area asks for no comments, and 点我发评论 toasts', (tester) async {
    const post = DynamicItem(
      id: '1',
      kind: DynamicKind.word,
      author: DynamicAuthor(mid: 5, name: '演示', face: ''),
      nodes: [DynamicTextNode('没有评论区的动态')],
      stat: DynamicStat(like: 1),
    );
    final harness = await show(tester, id: '1', posts: [post]);
    expect(harness.pageApi.areas, isEmpty);
    expect(harness.pageApi.calls.where((call) => call.startsWith('comments')), isEmpty);
    await tester.tap(key('post-write'));
    await tester.pump();
    expect(find.byType(Composer), findsNothing);
    expect(find.text('评论区暂不可用'), findsOneWidget);
    await settleToast(tester);
    await back(tester, harness);
  });

  testWidgets('a closed comment area: 点我发评论 toasts its words instead of opening the composer', (tester) async {
    final harness = await show(tester, commentsFailure: const BiliError.api(code: 12002, message: '评论区已关闭'));
    expect(find.text('评论区已关闭'), findsOneWidget, reason: 'the notice in the list');
    await tester.tap(key('post-write'));
    await tester.pump();
    expect(find.byType(Composer), findsNothing);
    expect(find.text('评论区已关闭'), findsNWidgets(2));
    expect(harness.gate.requests, 0);
    await settleToast(tester);
    await back(tester, harness);
  });

  testWidgets('a share sheet that fails toasts 分享失败', (tester) async {
    final harness = await show(tester, shareFails: true);
    await tester.tap(key('post-share'));
    await tester.pump();
    expect(find.text('分享失败'), findsOneWidget);
    await settleToast(tester);
    await back(tester, harness);
  });

  testWidgets("评论 N keeps the post's own count when the first page counts none", (tester) async {
    final harness = await show(tester, firstPage: CommentPage(comments: [_comment(100)], total: 0));
    expect(find.byType(CommentRow), findsWidgets);
    expect(find.text('评论 4515'), findsOneWidget);
    expect(find.descendant(of: key('post-comments'), matching: find.text('4515')), findsOneWidget);
    await back(tester, harness);
  });

  testWidgets("the post's pictures open in the page's own viewer, which back closes first", (tester) async {
    final harness = await show(tester);
    await tester.tap(key('dynamic-picture-1'));
    await frames(tester);
    expect(find.byType(PictureViewer), findsOneWidget);
    expect(key('dynamic-picture-viewer'), findsNothing, reason: 'not the root overlay\'s viewer');
    final overlay = tester.widget<CommentOverlays>(find.byType(CommentOverlays)).controller.value;
    expect(overlay, isA<PicturesOverlay>().having((shown) => shown.index, 'index', 1));
    expect((overlay as PicturesOverlay?)?.pictures, hasLength(9));
    await back(tester, harness);
    expect(find.byType(PictureViewer), findsNothing);
    expect(find.byType(DynamicPostPage), findsOneWidget, reason: 'back closed the viewer, not the page');
    await back(tester, harness);
  });

  testWidgets("a repost's video pauses under the composer and 评论详情, and plays again once they close", (tester) async {
    final harness = await show(tester, id: _forwardId);
    final host = tester.widget<DynamicRepostBlock>(find.byType(DynamicRepostBlock)).inline!;
    expect(host.playing, isNotNull);

    await tester.tap(key('post-write'));
    await frames(tester);
    expect(find.byType(Composer), findsOneWidget);
    expect(host.playing, isNull);
    await back(tester, harness);
    expect(find.byType(Composer), findsNothing);
    expect(host.playing, isNotNull);

    tester.widget<CommentOverlays>(find.byType(CommentOverlays)).callbacks.openThread(_comment(100, replyCount: 2));
    await frames(tester, 20);
    expect(find.byType(ThreadView), findsOneWidget);
    expect(host.playing, isNull);
    await back(tester, harness);
    expect(find.byType(ThreadView), findsNothing);
    expect(host.playing, isNotNull);
    await back(tester, harness);
  });
}
