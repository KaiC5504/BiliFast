import 'package:bili_core/api.dart';
import 'package:bilifast/comments/comment_callbacks.dart';
import 'package:bilifast/comments/comment_row.dart';
import 'package:bilifast/comments/comments_model.dart';
import 'package:bilifast/comments/comments_tab.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/collapsing_player.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Comment comment(int rpid, {bool pinned = false}) => Comment(
  rpid: rpid,
  member: CommentMember(mid: rpid * 10, name: '用户$rpid'),
  message: '评论 $rpid',
  isPinned: pinned,
);

/// The list's state set by hand, and every call the tab makes recorded.
class FakeComments extends CommentsModel {
  FakeComments({
    List<Comment> comments = const [],
    this.pinnedValue,
    this.isEndValue = false,
    this.loadingValue = false,
    this.errorValue,
    this.closedValue,
    this.sortValue = CommentSort.hot,
    this.loaded = true,
  }) : commentsValue = comments,
       super(
         aid: 1,
         upMid: 2,
         api: FakePageApi(),
         drafts: CommentDrafts(),
         isLoggedIn: () => true,
         accountMid: () => 3,
         requestLogin: () {},
         toast: (_) {},
       );

  List<Comment> commentsValue;
  Comment? pinnedValue;
  bool isEndValue;
  bool loadingValue;
  String? errorValue;
  String? closedValue;
  CommentSort sortValue;
  bool loaded;
  String? rootPromptValue;

  final calls = <String>[];

  /// What a page does once asked for, such as failing.
  void Function()? onLoadMore;

  void change(void Function() update) {
    update();
    notifyListeners();
  }

  @override
  List<Comment> get comments => commentsValue;
  @override
  Comment? get pinned => pinnedValue;
  @override
  bool get isEnd => isEndValue;
  @override
  bool get loading => loadingValue;
  @override
  String? get error => errorValue;
  @override
  String? get closedMessage => closedValue;
  @override
  CommentSort get sort => sortValue;
  @override
  bool get hasLoaded => loaded;
  @override
  String? get rootPrompt => rootPromptValue;

  @override
  Future<void> ensureLoaded() async => calls.add('ensureLoaded');

  @override
  Future<void> loadMore() async {
    calls.add('loadMore');
    onLoadMore?.call();
  }

  @override
  Future<void> setSort(CommentSort sort) async => calls.add('setSort ${sort.name}');

  int get pages => calls.where((call) => call == 'loadMore').length;
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

const phone = Size(440, 956);
const homeIndicator = 34.0;

late ScrollController primary;

Future<void> host(WidgetTester tester, Widget child, {double reserve = 0}) async {
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
          child: PlayerReserve(height: reserve, child: child),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> show(WidgetTester tester, FakeComments model, {Replies? replies, double reserve = 0}) => host(
  tester,
  CommentsTab(model: model, callbacks: (replies ?? Replies()).callbacks),
  reserve: reserve,
);

ScrollPosition position(WidgetTester tester) => tester.state<ScrollableState>(find.byType(Scrollable).first).position;

/// Pumps through a fling without waiting on the spinner, which never settles.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder rowKey(int rpid) => find.byKey(ValueKey(rpid), skipOffstage: false);

Finder get rows => find.byType(CommentRow, skipOffstage: false);

Future<void> jumpToEnd(WidgetTester tester) async {
  final scroll = position(tester);
  scroll.jumpTo(scroll.maxScrollExtent);
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() => primary = ScrollController());
  tearDown(() => primary.dispose());

  group('loading', () {
    testWidgets('asks for the first page once, when it first shows', (tester) async {
      final model = FakeComments(loaded: false, loadingValue: true);
      await show(tester, model);
      expect(model.calls, ['ensureLoaded']);

      await tester.pump();
      expect(model.calls, ['ensureLoaded']);
    });

    testWidgets('a new model is asked for its first page too', (tester) async {
      final first = FakeComments(loaded: false, loadingValue: true);
      final second = FakeComments(loaded: false, loadingValue: true);
      final replies = Replies();
      await host(tester, CommentsTab(model: first, callbacks: replies.callbacks));
      await host(tester, CommentsTab(model: second, callbacks: replies.callbacks));
      expect(first.calls, ['ensureLoaded']);
      expect(second.calls, ['ensureLoaded']);

      first.change(() => first.closedValue = '评论区已关闭');
      await tester.pump();
      expect(find.text('评论区已关闭'), findsNothing);
      second.change(() => second.closedValue = '评论区已关闭');
      await tester.pump();
      expect(find.text('评论区已关闭'), findsOneWidget);
    });

    testWidgets('kept alive behind 简介, a new video waits until 评论 shows to load', (tester) async {
      final first = FakeComments(loaded: false, loadingValue: true);
      final second = FakeComments(loaded: false, loadingValue: true);
      final replies = Replies();
      Widget tab(FakeComments model, {required bool shown}) =>
          TickerMode(enabled: shown, child: CommentsTab(model: model, callbacks: replies.callbacks));

      await host(tester, tab(first, shown: false));
      expect(first.calls, isEmpty);
      await host(tester, tab(first, shown: true));
      expect(first.calls, ['ensureLoaded']);

      await host(tester, tab(first, shown: false));
      await host(tester, tab(second, shown: false));
      expect(second.calls, isEmpty, reason: '自动连播 while 简介 shows');
      await host(tester, tab(second, shown: true));
      expect(second.calls, ['ensureLoaded']);
    });

    testWidgets('shows what the model has as it changes', (tester) async {
      final model = FakeComments(loaded: false, loadingValue: true);
      await show(tester, model);
      expect(find.byKey(const ValueKey('comments-loading')), findsOneWidget);

      model.change(() {
        model.loaded = true;
        model.loadingValue = false;
        model.isEndValue = true;
        model.commentsValue = [comment(1)];
      });
      await tester.pump();
      expect(rowKey(1), findsOneWidget);
      expect(find.text('没有更多了'), findsOneWidget);
      expect(find.byKey(const ValueKey('comments-loading')), findsNothing);
    });
  });

  group('the list (10, 11)', () {
    testWidgets('starts with the player reserve and scrolls with the primary controller', (tester) async {
      await show(tester, FakeComments(isEndValue: true), reserve: 300);
      expect(tester.getSize(find.byKey(const ValueKey('comments-reserve'))).height, 300);
      expect(tester.getTopLeft(find.byType(CommentSortHeader)).dy, 300);
      expect(primary.hasClients, isTrue);

      await show(tester, FakeComments(isEndValue: true), reserve: 3000);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await settle(tester);
      expect(primary.offset, greaterThan(0));
    });

    testWidgets('the pinned comment first, then the rows, each with the model and the callbacks', (tester) async {
      final model = FakeComments(
        pinnedValue: comment(9, pinned: true),
        comments: [comment(1), comment(2)],
        isEndValue: true,
      );
      final replies = Replies();
      await show(tester, model, replies: replies);

      final shown = tester.widgetList<CommentRow>(rows).toList();
      expect(shown.map((row) => row.comment.rpid), [9, 1, 2]);
      expect(shown.first.key, const ValueKey('pinned-9'));
      expect(shown[1].key, const ValueKey(1));
      for (final row in shown) {
        expect(row.model, same(model));
        expect(row.callbacks, same(replies.callbacks));
        expect(row.showsReplies, isTrue);
        expect(row.showsDivider, isTrue);
        expect(row.thread, isNull);
      }
    });

    testWidgets('a comment posted at the top keeps the other rows', (tester) async {
      final model = FakeComments(comments: [comment(1), comment(2)], isEndValue: true);
      await show(tester, model);
      final before = tester.element(rowKey(1));

      model.change(() => model.commentsValue = [comment(3), ...model.commentsValue]);
      await tester.pump();
      expect(tester.element(rowKey(1)), same(before));
      expect(tester.widgetList<CommentRow>(rows).map((row) => row.comment.rpid), [3, 1, 2]);
    });
  });

  group('the sort header (10)', () {
    testWidgets('热门评论 with ≡ 按热度, 28 tall, centred 16.5 down, the button at the gutter', (tester) async {
      await show(tester, FakeComments(isEndValue: true));
      final header = tester.getRect(find.byType(CommentSortHeader));
      expect(header.height, CommentListTheme.sortHeight);
      final title = tester.getRect(find.text('热门评论'));
      expect(title.left, CommentListTheme.gutter);
      expect(title.center.dy - header.top, closeTo(CommentListTheme.sortCentre, 0.01));
      final sort = tester.getRect(find.text('按热度'));
      expect(sort.right, closeTo(phone.width - CommentListTheme.gutter, 0.01));
      expect(sort.center.dy - header.top, closeTo(CommentListTheme.sortCentre, 0.01));
    });

    testWidgets('a tap switches 按热度 to the time sort and 按时间 back', (tester) async {
      final model = FakeComments(isEndValue: true);
      await show(tester, model);
      await tester.tap(find.text('按热度'));
      expect(model.calls.last, 'setSort time');

      model.change(() => model.sortValue = CommentSort.time);
      await tester.pump();
      expect(find.text('最新评论'), findsOneWidget);
      await tester.tap(find.text('按时间'));
      expect(model.calls.last, 'setSort hot');
    });

    testWidgets('the whole right end of the header switches, including left of ≡', (tester) async {
      final model = FakeComments(isEndValue: true);
      await show(tester, model);
      final sort = tester.getRect(find.text('按热度'));
      final header = tester.getRect(find.byType(CommentSortHeader));
      await tester.tapAt(Offset(sort.left - CommentListTheme.sortIconWidth - 8, header.top + 2));
      expect(model.calls.last, 'setSort time');
    });

    testWidgets('pressed through accessibility', (tester) async {
      final semantics = tester.ensureSemantics();
      final model = FakeComments(isEndValue: true);
      await show(tester, model);
      tester.semantics.tap(find.semantics.byLabel('按热度'));
      expect(model.calls.last, 'setSort time');
      semantics.dispose();
    });
  });

  group('the footer', () {
    testWidgets('a spinner while a page loads, an empty space while more waits', (tester) async {
      final model = FakeComments(comments: [comment(1)], loadingValue: true);
      await show(tester, model);
      expect(find.byKey(const ValueKey('comments-loading')), findsOneWidget);

      model.change(() => model.loadingValue = false);
      await tester.pump();
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    });

    testWidgets('没有更多了 at the end', (tester) async {
      await show(tester, FakeComments(comments: [comment(1)], isEndValue: true));
      expect(find.text('没有更多了'), findsOneWidget);
      expect(find.text('还没有评论，快来抢沙发吧'), findsNothing);
    });

    testWidgets('还没有评论，快来抢沙发吧 for a video without comments', (tester) async {
      await show(tester, FakeComments(isEndValue: true));
      expect(find.text('还没有评论，快来抢沙发吧'), findsOneWidget);
      expect(find.text('没有更多了'), findsNothing);
    });

    testWidgets('a pinned comment alone is not an empty list', (tester) async {
      await show(tester, FakeComments(pinnedValue: comment(9, pinned: true), isEndValue: true));
      expect(find.text('没有更多了'), findsOneWidget);
    });

    testWidgets('a failed page is 加载失败，点击重试, and the tap asks again', (tester) async {
      final model = FakeComments(comments: [comment(1)], errorValue: '网络连接失败，请稍后再试');
      await show(tester, model);
      expect(find.text('加载失败，点击重试', findRichText: true), findsOneWidget);
      expect(model.pages, 0);

      await tester.tap(find.byKey(const ValueKey('comments-retry')));
      expect(model.pages, 1);
    });

    testWidgets('the server\'s reason shows over 加载失败，点击重试, and is read with it', (tester) async {
      final semantics = tester.ensureSemantics();
      await show(tester, FakeComments(comments: [comment(1)], errorValue: '请求过于频繁，请稍后再试'));
      final reason = tester.getRect(find.byKey(const ValueKey('comments-error')));
      expect(find.text('请求过于频繁，请稍后再试'), findsOneWidget);
      expect(reason.bottom, lessThan(tester.getRect(find.text('加载失败，点击重试', findRichText: true)).top));
      expect(find.semantics.byLabel('请求过于频繁，请稍后再试，加载失败，点击重试'), findsOne);
      semantics.dispose();
    });

    testWidgets('a closed section shows its words in place of the list', (tester) async {
      final model = FakeComments(comments: [comment(1)], closedValue: 'UP主已关闭评论区');
      await show(tester, model, reserve: 200);
      expect(find.text('UP主已关闭评论区'), findsOneWidget);
      expect(find.byType(CommentSortHeader), findsNothing);
      expect(rows, findsNothing);
      expect(find.byType(CommentListFooter), findsNothing);
      expect(tester.getTopLeft(find.byKey(const ValueKey('comments-closed'))).dy, 200);
      expect(model.pages, 0);
      expect(find.byKey(const ValueKey('comment-bar')), findsNothing, reason: 'a post there can only fail');
    });
  });

  group('paging', () {
    testWidgets('asks for the next page once while the end is on screen', (tester) async {
      final model = FakeComments(comments: [comment(1)]);
      model.onLoadMore = () => model.change(() => model.loadingValue = true);
      await show(tester, model);
      expect(model.pages, 1);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -100));
      await settle(tester);
      expect(model.pages, 1);
    });

    testWidgets('not while the end is more than a screen away, then once it nears', (tester) async {
      final model = FakeComments(comments: [comment(1)]);
      model.onLoadMore = () => model.change(() => model.loadingValue = true);
      await show(tester, model, reserve: 4000);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await settle(tester);
      expect(model.pages, 0);

      await jumpToEnd(tester);
      expect(model.pages, 1);
    });

    testWidgets('never while a page loads, at the end, or before the first page', (tester) async {
      for (final model in [
        FakeComments(comments: [comment(1)], loadingValue: true),
        FakeComments(comments: [comment(1)], isEndValue: true),
        FakeComments(loaded: false),
      ]) {
        await show(tester, model, reserve: 2000);
        await jumpToEnd(tester);
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 200));
        await settle(tester);
        expect(model.pages, 0);
      }
    });

    testWidgets('a failed page asks once and waits for the tap', (tester) async {
      final model = FakeComments(comments: [comment(1)]);
      model.onLoadMore = () => model.change(() => model.errorValue = '网络连接失败，请稍后再试');
      await show(tester, model, reserve: 2000);
      expect(model.pages, 0);
      await jumpToEnd(tester);
      await settle(tester);
      expect(model.pages, 1);
      expect(find.text('加载失败，点击重试', findRichText: true), findsOneWidget);

      for (var i = 0; i < 3; i++) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 600));
        await settle(tester);
        expect(position(tester).extentAfter, greaterThan(0));
        await jumpToEnd(tester);
      }
      await tester.pump(const Duration(seconds: 5));
      expect(model.pages, 1);

      await tester.tap(find.byKey(const ValueKey('comments-retry')));
      await settle(tester);
      expect(model.pages, 2);
      await jumpToEnd(tester);
      expect(model.pages, 2);
    });

    testWidgets('a page that arrives asks for the next only once the end nears again', (tester) async {
      final model = FakeComments(comments: [comment(1)]);
      model.onLoadMore = () => model.change(() => model.loadingValue = true);
      await show(tester, model, reserve: 2000);
      await jumpToEnd(tester);
      expect(model.pages, 1);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, 1500));
      await settle(tester);
      model.change(() {
        model.loadingValue = false;
        model.commentsValue = [comment(1), comment(2)];
      });
      await settle(tester);
      expect(model.pages, 1);

      await jumpToEnd(tester);
      expect(model.pages, 2);
    });
  });

  group('the 发条评论 bar (10)', () {
    testWidgets('a 34 pt pill from the gutter to 44 short of the edge, over the home indicator', (tester) async {
      await show(tester, FakeComments(isEndValue: true));
      final bar = tester.getRect(find.byKey(const ValueKey('comment-bar')));
      final field = tester.getRect(find.byKey(const ValueKey('comment-field')));
      expect(field.left, CommentListTheme.gutter);
      expect(field.right, phone.width - CommentListTheme.faceBox);
      expect(field.height, CommentListTheme.fieldHeight);
      expect(field.top - bar.top, closeTo(CommentListTheme.barTop, 0.01));
      expect(phone.height - homeIndicator - field.bottom, CommentListTheme.barBottom);
      expect(bar.bottom, phone.height);
      final face = tester.getRect(find.byKey(const ValueKey('comment-emotes')));
      expect(face.center.dx, phone.width - CommentListTheme.faceBox / 2);
      expect(face.center.dy, field.center.dy);
      expect(find.text(CommentWriteBar.placeholder), findsOneWidget);
    });

    testWidgets('the section\'s own prompt replaces the fixed one once the list sends it', (tester) async {
      final semantics = tester.ensureSemantics();
      final replies = Replies();
      final model = FakeComments(isEndValue: true);
      await show(tester, model, replies: replies);
      expect(find.text(CommentWriteBar.placeholder), findsOneWidget);

      model.change(() => model.rootPromptValue = '随便聊聊吧～');
      await tester.pump();
      expect(find.text(CommentWriteBar.placeholder), findsNothing);
      expect(find.text('随便聊聊吧～'), findsOneWidget);
      tester.semantics.tap(find.semantics.byLabel('随便聊聊吧～'));
      expect(replies.calls, [(const ReplyToVideo(), false)]);
      semantics.dispose();
    });

    testWidgets('the list ends above the bar', (tester) async {
      await show(tester, FakeComments(isEndValue: true));
      final list = tester.getRect(find.byType(CustomScrollView));
      final bar = tester.getRect(find.byKey(const ValueKey('comment-bar')));
      expect(list.bottom, bar.top);
    });

    testWidgets('the pill writes to the video, the face opens on the emotes', (tester) async {
      final replies = Replies();
      await show(tester, FakeComments(isEndValue: true), replies: replies);
      await tester.tap(find.text(CommentWriteBar.placeholder));
      await tester.tap(find.byKey(const ValueKey('comment-emotes')));
      expect(replies.calls, [(const ReplyToVideo(), false), (const ReplyToVideo(), true)]);
    });

    testWidgets('both pressed through accessibility', (tester) async {
      final semantics = tester.ensureSemantics();
      final replies = Replies();
      final model = FakeComments(comments: [comment(1)], errorValue: '失败');
      await show(tester, model, replies: replies);
      tester.semantics.tap(find.semantics.byLabel(CommentWriteBar.placeholder));
      tester.semantics.tap(find.semantics.byLabel('表情'));
      tester.semantics.tap(find.semantics.byLabel('失败，加载失败，点击重试'));
      expect(replies.calls, [(const ReplyToVideo(), false), (const ReplyToVideo(), true)]);
      expect(model.pages, 1);
      semantics.dispose();
    });
  });

  group('before the aid is known', () {
    testWidgets('a spinner under the reserve, in a list on the primary controller', (tester) async {
      await host(tester, const CommentsSlot(), reserve: 300);
      final spinner = tester.getRect(find.byKey(const ValueKey('comments-slot-loading')));
      expect(spinner.top, 300 + CommentListTheme.emptyPadding);
      expect(spinner.center.dx, phone.width / 2);
      expect(primary.hasClients, isTrue);
    });
  });
}
