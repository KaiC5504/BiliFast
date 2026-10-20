import 'package:bili_core/api.dart';
import 'package:bilifast/comments/comment_callbacks.dart';
import 'package:bilifast/comments/comment_row.dart';
import 'package:bilifast/comments/comments_model.dart';
import 'package:bilifast/comments/comments_tab.dart';
import 'package:bilifast/comments/thread_view.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/collapsing_player.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Comment comment(int rpid, {int root = 0, int replies = 0, bool upLiked = false}) => Comment(
  rpid: rpid,
  root: root,
  replyCount: replies,
  member: CommentMember(mid: rpid * 10, name: '用户$rpid'),
  message: '评论 $rpid',
  upLiked: upLiked,
);

final root = comment(100, replies: 12);

/// The open thread set by hand, and every call the view makes recorded.
class FakeThread extends CommentsModel {
  FakeThread(this.threadValue)
    : super(
        aid: 1,
        upMid: 2,
        api: FakePageApi(),
        drafts: CommentDrafts(),
        isLoggedIn: () => true,
        accountMid: () => 3,
        requestLogin: () {},
        toast: (_) {},
      );

  ThreadState? threadValue;
  String? childPromptValue;
  final calls = <String>[];

  /// What a page does once asked for, such as failing.
  void Function()? onLoadMore;

  void change(ThreadState? Function(ThreadState? thread) update) {
    threadValue = update(threadValue);
    notifyListeners();
  }

  @override
  ThreadState? get thread => threadValue;

  @override
  String? get childPrompt => childPromptValue;

  @override
  void closeThread() => calls.add('closeThread');

  @override
  Future<void> setThreadSort(CommentSort sort) async => calls.add('setThreadSort ${sort.name}');

  @override
  Future<void> loadMoreThread() async {
    calls.add('loadMoreThread');
    onLoadMore?.call();
  }

  int get pages => calls.where((call) => call == 'loadMoreThread').length;
}

class Replies {
  final calls = <(ReplyTarget, bool)>[];

  late final callbacks = CommentCallbacks(
    reply: (target, emotes) => calls.add((target, emotes)),
    openThread: (_) {},
    viewPictures: (_, _) {},
    confirmDelete: (_) {},
    seek: (_) {},
    openVideo: (_) {},
  );
}

ThreadState loaded({
  List<Comment>? replies,
  CommentSort sort = CommentSort.time,
  bool isEnd = false,
  bool loading = false,
  String? error,
  int page = 1,
}) => ThreadState(
  root: root,
  replies: replies ?? [comment(1, root: 100), comment(2, root: 100)],
  sort: sort,
  page: page,
  isEnd: isEnd,
  total: 12,
  loading: loading,
  error: error,
);

const phone = Size(440, 956);
const homeIndicator = 34.0;

/// Where the overlay puts the thread: under the small player.
const threadTop = 247.5;

late ScrollController primary;

Future<void> show(WidgetTester tester, FakeThread model, {ThreadState? shown, Replies? replies}) async {
  tester.view.physicalSize = phone;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: phone,
          padding: EdgeInsets.only(bottom: homeIndicator),
        ),
        child: PrimaryScrollController(
          controller: primary,
          child: PlayerReserve(
            height: 300,
            child: Stack(
              children: [
                Positioned.fill(
                  top: threadTop,
                  child: ThreadView(
                    model: model,
                    thread: shown ?? model.thread!,
                    callbacks: (replies ?? Replies()).callbacks,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder get rows => find.byType(CommentRow, skipOffstage: false);

ScrollPosition position(WidgetTester tester) => tester.state<ScrollableState>(find.byType(Scrollable).first).position;

Future<void> jumpToEnd(WidgetTester tester) async {
  final scroll = position(tester);
  scroll.jumpTo(scroll.maxScrollExtent);
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() => primary = ScrollController());
  tearDown(() => primary.dispose());

  group('the header (13)', () {
    testWidgets('评论详情 where the tab row was, over a 1 pt hairline at 40', (tester) async {
      await show(tester, FakeThread(loaded(isEnd: true)));
      final header = tester.getRect(find.byKey(const ValueKey('thread-header')));
      expect(header.top, threadTop);
      expect(header.height, 41);
      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find.descendant(of: find.byKey(const ValueKey('thread-header')), matching: find.byType(DecoratedBox)),
                  )
                  .decoration
              as BoxDecoration;
      expect((decoration.border! as Border).bottom.width, 1);
      final title = tester.getRect(find.text('评论详情'));
      expect(title.left, CommentListTheme.gutter);
      expect(title.center.dy, closeTo(header.center.dy, 0.01));
      final close = tester.getRect(find.byKey(const ValueKey('thread-close')));
      expect(close.center.dx, phone.width - CommentListTheme.closeTrailing - CommentListTheme.closeBox / 2);
      expect(close.center.dy, header.center.dy);
    });

    testWidgets('✕ closes the thread, by touch and through accessibility', (tester) async {
      final semantics = tester.ensureSemantics();
      final model = FakeThread(loaded(isEnd: true));
      await show(tester, model);
      await tester.tap(find.byKey(const ValueKey('thread-close')));
      tester.semantics.tap(find.semantics.byLabel('关闭'));
      expect(model.calls, ['closeThread', 'closeThread']);
      semantics.dispose();
    });
  });

  group('the thread (13)', () {
    testWidgets('the root in full, the band, 相关回复共N条, then the replies answering in the thread', (tester) async {
      final model = FakeThread(loaded(isEnd: true));
      final replies = Replies();
      await show(tester, model, replies: replies);

      final shown = tester.widgetList<CommentRow>(rows).toList();
      expect(shown.map((row) => row.comment.rpid), [100, 1, 2]);
      final first = shown.first;
      expect(first.key, const ValueKey('thread-root'));
      expect(first.showsReplies, isFalse);
      expect(first.showsDivider, isFalse);
      expect(first.thread, isNull);
      for (final reply in shown.skip(1)) {
        expect(reply.key, ValueKey(reply.comment.rpid));
        expect(reply.thread, same(root));
        expect(reply.showsReplies, isFalse);
        expect(reply.showsDivider, isTrue);
        expect(reply.model, same(model));
        expect(reply.callbacks, same(replies.callbacks));
      }
      expect(find.text('相关回复共12条'), findsOneWidget);
      expect(find.text('按时间'), findsOneWidget);
    });

    testWidgets('no player reserve, and its own scroll view rather than the page\'s', (tester) async {
      await show(tester, FakeThread(loaded(isEnd: true)));
      final header = tester.getRect(find.byKey(const ValueKey('thread-header')));
      expect(tester.getTopLeft(find.byKey(const ValueKey('thread-root'), skipOffstage: false)).dy, header.bottom);
      expect(primary.hasClients, isFalse);
    });

    testWidgets('the band is 10 tall under the root; the sort header 35 under the band', (tester) async {
      await show(tester, FakeThread(loaded(isEnd: true)));
      final band = tester.getRect(find.byKey(const ValueKey('thread-band')));
      expect(band.height, CommentListTheme.bandHeight);
      expect(band.top, tester.getBottomLeft(find.byKey(const ValueKey('thread-root'), skipOffstage: false)).dy);
      final sort = tester.getRect(find.byType(CommentSortHeader));
      expect(sort.top, band.bottom);
      expect(sort.height, CommentListTheme.threadSortHeight);
      expect(
        tester.getRect(find.text('相关回复共12条')).center.dy - sort.top,
        closeTo(CommentListTheme.threadSortCentre, 0.01),
      );
    });

    testWidgets('UP主觉得很赞 in its box under a liked root and a liked reply; the band and the replies 26 lower, the '
        'hairline 8 under the box (font-check 04)', (tester) async {
      final saved = BiliFonts.family;
      addTearDown(() => BiliFonts.family = saved);
      BiliFonts.family = BiliFonts.system;
      final chips = find.byKey(const ValueKey('comment-up-liked'), skipOffstage: false);
      final rootRow = find.byKey(const ValueKey('thread-root'), skipOffstage: false);
      final band = find.byKey(const ValueKey('thread-band'));

      await show(tester, FakeThread(loaded(isEnd: true)));
      expect(chips, findsNothing);
      final bandWithout = tester.getRect(band).top;
      final replyWithout = tester.getRect(find.byKey(const ValueKey(1))).top;

      final liked = comment(100, replies: 12, upLiked: true);
      await show(
        tester,
        FakeThread(
          ThreadState(
            root: liked,
            replies: [comment(1, root: 100, upLiked: true), comment(2, root: 100)],
            sort: CommentSort.time,
            page: 1,
            isEnd: true,
            total: 12,
          ),
        ),
      );
      expect(chips, findsNWidgets(2));
      final rootChip = tester.getRect(find.descendant(of: rootRow, matching: chips));
      expect(rootChip.left, CommentRowTheme.textLeading);
      expect(rootChip.height, CommentRowTheme.upChipHeight);
      expect(tester.getRect(band).top - rootChip.bottom, closeTo(8, 0.01));
      expect(tester.getRect(band).top - bandWithout, closeTo(26, 0.01));
      expect(tester.getRect(find.byKey(const ValueKey(1))).top - replyWithout, closeTo(26, 0.01));

      final reply = find.byKey(const ValueKey(1));
      final replyChip = tester.getRect(find.descendant(of: reply, matching: chips));
      final hairline = tester.getRect(
        find.descendant(of: reply, matching: find.byKey(const ValueKey('comment-divider'))),
      );
      expect(hairline.top - replyChip.bottom, closeTo(8, 0.01));
      expect(
        find.descendant(of: find.byKey(const ValueKey(2)), matching: chips),
        findsNothing,
        reason: 'a reply the uploader didn\'t like',
      );
    });

    testWidgets('按时间 switches to the hot sort, 按热度 back', (tester) async {
      final model = FakeThread(loaded(isEnd: true));
      await show(tester, model);
      await tester.tap(find.text('按时间'));
      expect(model.calls.last, 'setThreadSort hot');

      model.change((thread) => thread!.copyWith(sort: CommentSort.hot));
      await tester.pump();
      await tester.tap(find.text('按热度'));
      expect(model.calls.last, 'setThreadSort time');
    });

    testWidgets('shows the model\'s thread while it has the same root, the last one as it closes', (tester) async {
      final model = FakeThread(loaded());
      final first = model.thread!;
      await show(tester, model);
      model.change((thread) => thread!.copyWith(total: 13, replies: [...thread.replies, comment(3, root: 100)]));
      await tester.pump();
      expect(find.text('相关回复共13条'), findsOneWidget);
      expect(tester.widgetList<CommentRow>(rows).map((row) => row.comment.rpid), [100, 1, 2, 3]);

      model.change((_) => null);
      await tester.pump();
      expect(find.text('相关回复共12条'), findsOneWidget);
      expect(tester.widgetList<CommentRow>(rows).map((row) => row.comment.rpid), [100, 1, 2]);
      expect(first.total, 12);
    });

    testWidgets('a thread for another root shows the one it was given', (tester) async {
      final model = FakeThread(loaded());
      final given = model.thread!;
      model.threadValue = ThreadState(root: comment(200, replies: 3), total: 3, page: 1);
      await show(tester, model, shown: given);
      expect(find.text('相关回复共12条'), findsOneWidget);
    });
  });

  group('the footer and paging', () {
    testWidgets('没有更多了 at the end; 还没有评论，快来抢沙发吧 with no replies', (tester) async {
      final model = FakeThread(loaded(isEnd: true));
      await show(tester, model);
      expect(find.text('没有更多了'), findsOneWidget);

      model.change((thread) => thread!.copyWith(replies: const []));
      await tester.pump();
      expect(find.text('还没有评论，快来抢沙发吧'), findsOneWidget);
    });

    testWidgets('a spinner while the first page loads, and no ask of its own', (tester) async {
      final model = FakeThread(loaded(replies: const [], page: 0, loading: true));
      await show(tester, model);
      expect(find.byKey(const ValueKey('comments-loading')), findsOneWidget);
      expect(model.pages, 0);
    });

    testWidgets('asks for the next page once the end is on screen, once', (tester) async {
      final model = FakeThread(loaded());
      model.onLoadMore = () => model.change((thread) => thread!.copyWith(loading: true));
      await show(tester, model);
      expect(model.pages, 1);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -100));
      await settle(tester);
      expect(model.pages, 1);
    });

    testWidgets('never before the first page, while loading or at the end', (tester) async {
      for (final thread in [loaded(page: 0), loaded(loading: true), loaded(isEnd: true)]) {
        final model = FakeThread(thread);
        await show(tester, model);
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -100));
        await settle(tester);
        expect(model.pages, 0);
      }
    });

    testWidgets('a failed page asks once and waits for the tap', (tester) async {
      final model = FakeThread(loaded());
      model.onLoadMore = () => model.change((thread) => thread!.copyWith(error: () => '网络连接失败，请稍后再试'));
      await show(tester, model);
      expect(model.pages, 1);
      await tester.pump();
      expect(find.text('加载失败，点击重试', findRichText: true), findsOneWidget);
      expect(find.text('网络连接失败，请稍后再试'), findsOneWidget, reason: 'the reason over it');

      for (var i = 0; i < 3; i++) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
        await settle(tester);
        await jumpToEnd(tester);
      }
      expect(model.pages, 1);

      await tester.tap(find.byKey(const ValueKey('comments-retry')));
      await settle(tester);
      expect(model.pages, 2);
    });
  });

  group('the 发条评论 bar (13)', () {
    testWidgets('replies to the root, the face on the emotes, over the home indicator', (tester) async {
      final replies = Replies();
      await show(tester, FakeThread(loaded(isEnd: true)), replies: replies);
      final bar = tester.getRect(find.byKey(const ValueKey('comment-bar')));
      expect(bar.bottom, phone.height);
      expect(
        phone.height - homeIndicator - tester.getRect(find.byKey(const ValueKey('comment-field'))).bottom,
        CommentListTheme.barBottom,
      );

      await tester.tap(find.text(CommentWriteBar.placeholder));
      await tester.tap(find.byKey(const ValueKey('comment-emotes')));
      expect(replies.calls, [(ReplyToComment(root), false), (ReplyToComment(root), true)]);
    });

    testWidgets('the thread\'s own prompt, else the list\'s for threads, else the fixed one (font-check 04)', (
      tester,
    ) async {
      final replies = Replies();
      final model = FakeThread(loaded(isEnd: true))..childPromptValue = '列表给的提示';
      await show(tester, model, replies: replies);
      expect(find.text('列表给的提示'), findsOneWidget);
      expect(find.text(CommentWriteBar.placeholder), findsNothing);

      model.change((thread) => thread!.copyWith(prompt: () => '楼里的提示'));
      await tester.pump();
      expect(find.text('楼里的提示'), findsOneWidget);
      expect(find.text('列表给的提示'), findsNothing);
      await tester.tap(find.text('楼里的提示'));
      expect(replies.calls, [(ReplyToComment(root), false)]);

      model.childPromptValue = null;
      model.change((thread) => thread!.copyWith(prompt: () => null));
      await tester.pump();
      expect(find.text(CommentWriteBar.placeholder), findsOneWidget);
    });
  });
}
