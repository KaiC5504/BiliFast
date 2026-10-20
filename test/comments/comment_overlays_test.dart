import 'package:bili_core/api.dart';
import 'package:bilifast/app/swipe_back_route.dart';
import 'package:bilifast/comments/comment_callbacks.dart';
import 'package:bilifast/comments/comment_overlays.dart';
import 'package:bilifast/comments/comments_model.dart';
import 'package:bilifast/comments/composer.dart';
import 'package:bilifast/comments/picture_viewer.dart';
import 'package:bilifast/comments/thread_view.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/system_font.dart';

/// Where the thread's top is put for these tests.
const threadTop = 280.0;
const screen = Size(440, 956);
const threadHeight = 956 - threadTop;

/// A comments model whose thread a test opens and closes, recording what the overlays ask of it. Nothing it does
/// reaches the API.
class TestComments extends CommentsModel {
  TestComments()
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

  ThreadState? _open;
  final calls = <String>[];
  final deleted = <Comment>[];

  @override
  ThreadState? get thread => _open;

  void show(ThreadState? thread) {
    _open = thread;
    notifyListeners();
  }

  @override
  void closeThread() {
    calls.add('closeThread');
    show(null);
  }

  @override
  Future<bool> delete(Comment comment) async {
    deleted.add(comment);
    return true;
  }

  @override
  Future<void> ensureLoaded() async {}

  @override
  Future<void> loadMore() async {}

  @override
  Future<void> loadMoreThread() async {}

  @override
  Future<void> setThreadSort(CommentSort sort) async {}
}

Comment comment(int rpid, {String message = '拳头的规则'}) => Comment(
  rpid: rpid,
  member: CommentMember(mid: rpid, name: '殇泪'),
  message: message,
);

ThreadState threadOf(int rpid, {int total = 12}) => ThreadState(root: comment(rpid), total: total);

const pictures = [
  CommentPicture(url: '', width: 1080, height: 1920),
  CommentPicture(url: '', width: 1920, height: 1080),
];

final callbacks = CommentCallbacks(
  reply: (_, _) {},
  openThread: (_) {},
  viewPictures: (_, _) {},
  confirmDelete: (_) {},
  seek: (_) {},
  openVideo: (_) {},
);

class Rig {
  Rig(this.controller, this.below, this.scroll);

  final CommentOverlayController controller;

  /// Taps that went through to the page under the overlays.
  final List<Offset> below;

  /// Scrolls the page around the overlays, standing in for the thread's own list: a vertical drag that starts on
  /// the thread reaches every scroller under the finger, the thread's included.
  final ScrollController scroll;
}

Widget host({
  required CommentsModel? model,
  required CommentOverlayController controller,
  required List<Offset> below,
  required ScrollController scroll,
  bool still = false,
  EdgeInsets padding = EdgeInsets.zero,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(size: screen, disableAnimations: still, padding: padding, viewPadding: padding),
    child: Scaffold(
      body: SingleChildScrollView(
        controller: scroll,
        child: SizedBox(
          width: screen.width,
          height: screen.height * 2,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  key: const ValueKey('page'),
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) => below.add(details.globalPosition),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                width: screen.width,
                height: screen.height,
                child: CommentOverlays(
                  model: model,
                  controller: controller,
                  callbacks: callbacks,
                  threadTop: threadTop,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);

Future<Rig> pumpOverlays(
  WidgetTester tester,
  CommentsModel? model, {
  bool still = false,
  EdgeInsets padding = EdgeInsets.zero,
}) async {
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = CommentOverlayController();
  addTearDown(controller.dispose);
  final scroll = ScrollController();
  addTearDown(scroll.dispose);
  final below = <Offset>[];
  await tester.pumpWidget(
    host(model: model, controller: controller, below: below, scroll: scroll, still: still, padding: padding),
  );
  await tester.pumpAndSettle();
  return Rig(controller, below, scroll);
}

TestComments testComments() {
  final model = TestComments();
  addTearDown(model.dispose);
  return model;
}

/// Opens [model]'s thread and lets it rise.
Future<void> openThread(WidgetTester tester, TestComments model, [int rpid = 1]) async {
  model.show(threadOf(rpid));
  await tester.pumpAndSettle();
  expect(threadTopNow(tester), threadTop);
}

double threadTopNow(WidgetTester tester) => tester.getTopLeft(find.byType(ThreadView)).dy;

const frame = Duration(milliseconds: 16);

void main() {
  group('with nothing up', () {
    testWidgets('every touch reaches the page and the overlays add nothing to semantics', (tester) async {
      final rig = await pumpOverlays(tester, testComments());
      await tester.tapAt(const Offset(220, 700));
      await tester.tapAt(const Offset(10, 700));
      expect(rig.below, hasLength(2));
      expect(find.descendant(of: find.byType(CommentOverlays), matching: find.byType(Semantics)), findsNothing);
    });

    testWidgets('without a model it shows nothing, a composer included', (tester) async {
      final rig = await pumpOverlays(tester, null);
      rig.controller.compose(const ReplyToVideo());
      await tester.pumpAndSettle();
      expect(find.byType(Composer), findsNothing);
      await tester.tapAt(const Offset(220, 700));
      expect(rig.below, hasLength(1));
    });
  });

  group('the thread', () {
    testWidgets('rises from the bottom over everything below threadTop in about 300 ms', (tester) async {
      final model = testComments();
      await pumpOverlays(tester, model);
      final thread = threadOf(1);
      model.show(thread);
      await tester.pump();
      expect(threadTopNow(tester), screen.height);
      await tester.pump(const Duration(milliseconds: 150));
      final halfway = threadTopNow(tester);
      expect(halfway, inExclusiveRange(threadTop, screen.height));
      // Easing out: past the middle of the way at half the time.
      expect(halfway, lessThan(threadTop + threadHeight / 2));
      await tester.pump(const Duration(milliseconds: 150));
      expect(threadTopNow(tester), threadTop);
      expect(tester.getSize(find.byType(ThreadView)), const Size(440, threadHeight));
      final view = tester.widget<ThreadView>(find.byType(ThreadView));
      expect(view.model, same(model));
      expect(view.thread, thread);
      expect(view.callbacks, same(callbacks));
    });

    testWidgets('shows the model\'s latest state', (tester) async {
      final model = testComments();
      await pumpOverlays(tester, model);
      await openThread(tester, model);
      final more = threadOf(1).copyWith(replies: [comment(2, message: '没人看的')], page: 1);
      model.show(more);
      await tester.pump();
      expect(tester.widget<ThreadView>(find.byType(ThreadView)).thread, more);
    });

    testWidgets('stops touches over itself; above threadTop they reach the page', (tester) async {
      final model = testComments();
      final rig = await pumpOverlays(tester, model);
      await openThread(tester, model);
      await tester.tapAt(const Offset(220, 600));
      expect(rig.below, isEmpty);
      await tester.tapAt(const Offset(220, 100));
      expect(rig.below, [const Offset(220, 100)]);
    });

    testWidgets('closing in the model slides it down showing its last state, letting touches through, then it goes', (
      tester,
    ) async {
      final model = testComments();
      final rig = await pumpOverlays(tester, model);
      await openThread(tester, model);
      final last = model.thread;
      model.closeThread();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(threadTopNow(tester), inExclusiveRange(threadTop, screen.height));
      expect(tester.widget<ThreadView>(find.byType(ThreadView)).thread, last);
      await tester.tapAt(const Offset(220, 900));
      expect(rig.below, hasLength(1));
      await tester.pumpAndSettle();
      expect(find.byType(ThreadView), findsNothing);
      expect(model.calls, ['closeThread']);
    });

    testWidgets('opened again while it slides away, it turns around', (tester) async {
      final model = testComments();
      await pumpOverlays(tester, model);
      await openThread(tester, model);
      model.closeThread();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final turned = threadTopNow(tester);
      model.show(threadOf(1));
      await tester.pump();
      await tester.pump(frame);
      expect(threadTopNow(tester), lessThan(turned));
      await tester.pumpAndSettle();
      expect(threadTopNow(tester), threadTop);
    });

    testWidgets('a new model drops it at once, closing nothing in the old one', (tester) async {
      final first = testComments();
      final rig = await pumpOverlays(tester, first);
      await openThread(tester, first);
      final second = testComments();
      await tester.pumpWidget(host(model: second, controller: rig.controller, below: rig.below, scroll: rig.scroll));
      expect(find.byType(ThreadView), findsNothing);
      expect(first.calls, isEmpty);
      // The old model's later news no longer reaches the overlays.
      first.show(threadOf(1));
      await tester.pumpAndSettle();
      expect(find.byType(ThreadView), findsNothing);
      await openThread(tester, second, 5);
      expect(tester.widget<ThreadView>(find.byType(ThreadView)).model, same(second));
    });

    testWidgets('with Reduce Motion it appears and goes at once', (tester) async {
      final model = testComments();
      await pumpOverlays(tester, model, still: true);
      model.show(threadOf(1));
      await tester.pump();
      expect(threadTopNow(tester), threadTop);
      model.closeThread();
      await tester.pump();
      expect(find.byType(ThreadView), findsNothing);
    });
  });

  group('the edge swipe', () {
    // Swipes are dragged at about a thumb's speed (1500 px/s), as in swipe_back_test.dart.
    testWidgets('lowers the thread by the finger\'s travel to the right', (tester) async {
      final model = testComments();
      await pumpOverlays(tester, model);
      await openThread(tester, model);
      final gesture = await tester.startGesture(const Offset(5, 600));
      var time = Duration.zero;
      // Past the touch slop: the swipe begins here.
      time += frame;
      await gesture.moveBy(const Offset(24, 0), timeStamp: time);
      await tester.pump();
      final began = threadTopNow(tester);
      for (var step = 1; step <= 5; step++) {
        time += frame;
        await gesture.moveBy(const Offset(24, 2), timeStamp: time);
        await tester.pump();
        expect(threadTopNow(tester), moreOrLessEquals(began + 24 * step), reason: 'step $step');
      }
      // Back to the left raises it with the finger, never above its place.
      time += frame;
      await gesture.moveBy(const Offset(-200, 0), timeStamp: time);
      await tester.pump();
      expect(threadTopNow(tester), threadTop);
      await gesture.up(timeStamp: time + const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(threadTopNow(tester), threadTop);
      expect(model.calls, isEmpty);
    });

    testWidgets('a long swipe from the left edge slides it down and closes it', (tester) async {
      final model = testComments();
      final rig = await pumpOverlays(tester, model);
      await openThread(tester, model);
      await tester.timedDragFrom(const Offset(5, 600), const Offset(300, 0), const Duration(milliseconds: 200));
      // Closed in the model at release, while it is still sliding down.
      expect(model.calls, ['closeThread']);
      await tester.pump(frame);
      expect(find.byType(ThreadView), findsOneWidget);
      await tester.pumpAndSettle();
      expect(model.calls, ['closeThread']);
      expect(find.byType(ThreadView), findsNothing);
      await tester.tapAt(const Offset(220, 600));
      expect(rig.below, hasLength(1));
    });

    testWidgets('a thread opened while a released swipe takes the last one down rises and stays', (tester) async {
      final model = testComments();
      final rig = await pumpOverlays(tester, model);
      await openThread(tester, model);
      await tester.timedDragFrom(const Offset(5, 600), const Offset(300, 0), const Duration(milliseconds: 200));
      await tester.pump(frame);
      // Taps pass through the sliding thread, so one on another comment's replies opens its thread now.
      await tester.tapAt(const Offset(220, 900));
      expect(rig.below, hasLength(1));
      model.show(threadOf(2));
      await tester.pumpAndSettle();
      expect(threadTopNow(tester), threadTop);
      expect(tester.widget<ThreadView>(find.byType(ThreadView)).thread.root.rpid, 2);
      expect(model.calls, ['closeThread']);
    });

    testWidgets('a short slow swipe springs back', (tester) async {
      final model = testComments();
      await pumpOverlays(tester, model);
      await openThread(tester, model);
      final gesture = await tester.startGesture(const Offset(5, 600));
      var time = Duration.zero;
      for (var i = 0; i < 6; i++) {
        time += frame;
        await gesture.moveBy(const Offset(20, 0), timeStamp: time);
        await tester.pump(frame);
      }
      expect(threadTopNow(tester), greaterThan(threadTop + 60));
      // Held still before letting go: no fling.
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up(timeStamp: time + const Duration(milliseconds: 200));
      await tester.pump();
      await tester.pump(frame);
      expect(threadTopNow(tester), inExclusiveRange(threadTop, threadTop + 100));
      await tester.pumpAndSettle();
      expect(threadTopNow(tester), threadTop);
      expect(model.calls, isEmpty);
    });

    testWidgets('let go past a third of its height, slowly, it closes', (tester) async {
      final model = testComments();
      await pumpOverlays(tester, model);
      await openThread(tester, model);
      final gesture = await tester.startGesture(const Offset(5, 600));
      var time = Duration.zero;
      for (var i = 0; i < 12; i++) {
        time += frame;
        await gesture.moveBy(const Offset(22, 0), timeStamp: time);
        await tester.pump(frame);
      }
      expect(threadTopNow(tester), greaterThan(threadTop + threadHeight / 3));
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up(timeStamp: time + const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(model.calls, ['closeThread']);
      expect(find.byType(ThreadView), findsNothing);
    });

    testWidgets('a short quick flick closes it; a quick flick back to the left keeps it', (tester) async {
      final model = testComments();
      await pumpOverlays(tester, model);
      await openThread(tester, model);
      // About 1500 px/s over 90 px: far from a third of the way, fast enough to close.
      await tester.timedDragFrom(const Offset(5, 600), const Offset(90, 0), const Duration(milliseconds: 60));
      await tester.pumpAndSettle();
      expect(model.calls, ['closeThread']);

      await openThread(tester, model);
      final gesture = await tester.startGesture(const Offset(5, 600));
      var time = Duration.zero;
      for (var i = 0; i < 12; i++) {
        time += frame;
        await gesture.moveBy(const Offset(25, 0), timeStamp: time);
        await tester.pump(frame);
      }
      expect(threadTopNow(tester), greaterThan(threadTop + threadHeight / 3));
      for (var i = 0; i < 4; i++) {
        time += frame;
        await gesture.moveBy(const Offset(-25, 0), timeStamp: time);
        await tester.pump(frame);
      }
      await gesture.up(timeStamp: time);
      await tester.pumpAndSettle();
      expect(threadTopNow(tester), threadTop);
      expect(model.calls, ['closeThread']);
    });

    testWidgets('a quick swipe from the edge over the player closes it; taps there still reach the player', (
      tester,
    ) async {
      final model = testComments();
      final rig = await pumpOverlays(tester, model);
      await openThread(tester, model);
      await tester.tapAt(const Offset(10, 150));
      expect(rig.below, [const Offset(10, 150)]);
      // About 1500 px/s, as a thumb swipes.
      await tester.timedDragFrom(const Offset(5, 150), const Offset(300, 0), const Duration(milliseconds: 200));
      expect(model.calls, ['closeThread']);
      await tester.pumpAndSettle();
      expect(find.byType(ThreadView), findsNothing);
      // Closed, it leaves the edge to the page.
      await tester.tapAt(const Offset(10, 150));
      expect(rig.below, hasLength(2));
    });

    testWidgets('a swipe from the middle does nothing', (tester) async {
      final model = testComments();
      final rig = await pumpOverlays(tester, model);
      await openThread(tester, model);
      for (final start in [const Offset(220, 600), const Offset(60, 600), const Offset(220, 150)]) {
        await tester.timedDragFrom(start, const Offset(300, 0), const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        expect(threadTopNow(tester), threadTop, reason: 'from $start');
      }
      expect(model.calls, isEmpty);
      expect(rig.scroll.offset, 0);
    });

    testWidgets('vertical drags still scroll, from the edge and from the middle, and leave the thread in place', (
      tester,
    ) async {
      final model = testComments();
      final rig = await pumpOverlays(tester, model);
      await openThread(tester, model);
      // The thread scrolls with the page here, so it stays in place when it sits threadTop below the page's top.
      for (final start in [const Offset(5, 800), const Offset(220, 800)]) {
        rig.scroll.jumpTo(0);
        await tester.pump();
        await tester.timedDragFrom(start, const Offset(0, -300), const Duration(milliseconds: 200));
        expect(rig.scroll.offset, greaterThan(0), reason: 'from $start');
        expect(threadTopNow(tester), moreOrLessEquals(threadTop - rig.scroll.offset), reason: 'from $start');
        await tester.pumpAndSettle();
      }
      // A mostly vertical drag with a sideways drift from the edge scrolls too.
      rig.scroll.jumpTo(0);
      await tester.pump();
      final gesture = await tester.startGesture(const Offset(5, 800));
      var time = Duration.zero;
      for (var i = 0; i < 12; i++) {
        time += frame;
        await gesture.moveBy(Offset(i.isEven ? 7 : -2, -25), timeStamp: time);
        await tester.pump();
        expect(threadTopNow(tester), moreOrLessEquals(threadTop - rig.scroll.offset), reason: 'move $i');
      }
      await gesture.up(timeStamp: time + frame);
      await tester.pumpAndSettle();
      expect(rig.scroll.offset, greaterThan(0));
      expect(model.calls, isEmpty);
    });

    testWidgets('closes the thread before the page; the next edge swipe goes back', (tester) async {
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final model = testComments();
      final controller = CommentOverlayController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    SwipeBackPageRoute<void>(
                      // As the video page: its PopScope holds while the thread is open.
                      builder: (_) => ListenableBuilder(
                        listenable: model,
                        builder: (context, _) => PopScope<void>(
                          canPop: model.thread == null,
                          child: Scaffold(
                            body: Stack(
                              children: [
                                const Center(child: Text('视频页')),
                                Positioned.fill(
                                  child: CommentOverlays(
                                    model: model,
                                    controller: controller,
                                    callbacks: callbacks,
                                    threadTop: threadTop,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('首页'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('首页'));
      await tester.pumpAndSettle();
      await openThread(tester, model);

      await tester.timedDragFrom(const Offset(5, 600), const Offset(300, 0), const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(model.calls, ['closeThread']);
      expect(find.byType(ThreadView), findsNothing);
      expect(find.text('视频页'), findsOneWidget);

      await tester.timedDragFrom(const Offset(5, 600), const Offset(300, 0), const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('视频页'), findsNothing);
      expect(find.text('首页'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  });

  group('with the home indicator\'s 34 pt inset', () {
    const inset = EdgeInsets.only(top: 62, bottom: 34);

    testWidgets('the thread\'s fill reaches the bottom edge', (tester) async {
      final model = testComments();
      await pumpOverlays(tester, model, padding: inset);
      await openThread(tester, model);
      final fill = find.ancestor(of: find.byType(ThreadView), matching: find.byType(ColoredBox)).first;
      expect(tester.widget<ColoredBox>(fill).color, CommentOverlayTheme.threadFill);
      expect(tester.getRect(fill), const Rect.fromLTRB(0, threadTop, 440, 956));
      // The thread keeps the inset for its own bottom bar.
      expect(MediaQuery.paddingOf(tester.element(find.byType(ThreadView))).bottom, 34);
    });

    testWidgets('the delete confirm\'s dim, the composer and the viewer cover the whole screen', (tester) async {
      final model = testComments();
      final rig = await pumpOverlays(tester, model, padding: inset);
      await openThread(tester, model);
      rig.controller.confirmDelete(comment(7));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(const ValueKey('comment-delete-dim'))), Offset.zero & screen);
      rig.controller.compose(const ReplyToVideo());
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(Composer)), Offset.zero & screen);
      rig.controller.viewPictures(pictures, 0);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(PictureViewer)), Offset.zero & screen);
    });
  });

  group('the composer', () {
    testWidgets('opens over the whole page with a model for its target, on the emote panel when asked', (tester) async {
      final model = testComments();
      final rig = await pumpOverlays(tester, model);
      await openThread(tester, model);
      final target = ReplyInThread(root: comment(1), reply: comment(2));
      rig.controller.compose(target, emotes: true);
      await tester.pump();
      final composer = tester.widget<Composer>(find.byType(Composer));
      expect(composer.model.comments, same(model));
      expect(composer.model.target, target);
      expect(composer.model.showingEmotes, isTrue);
      expect(tester.getRect(find.byType(Composer)), Offset.zero & screen);
      expect(composer.top, threadTop);
      // Over the thread it replies in.
      final stack = tester.widget<Stack>(
        find.descendant(of: find.byType(CommentOverlays), matching: find.byType(Stack)).first,
      );
      expect(stack.children.last.key, const ValueKey('comment-front'));
      expect(stack.children.first.key, const ValueKey('comment-thread'));

      rig.controller.compose(const ReplyToVideo());
      await tester.pump();
      final second = tester.widget<Composer>(find.byType(Composer));
      expect(second.model, isNot(same(composer.model)));
      expect(second.model.target, const ReplyToVideo());
      expect(second.model.showingEmotes, isFalse);
      await tester.pump();
      expect(() => composer.model.addListener(() {}), throwsFlutterError);
    });

    testWidgets('its close takes it away and disposes its model', (tester) async {
      final model = testComments();
      final rig = await pumpOverlays(tester, model);
      rig.controller.compose(ReplyToComment(comment(1)));
      await tester.pump();
      final composer = tester.widget<Composer>(find.byType(Composer));
      composer.onClose();
      expect(rig.controller.value, isNull);
      await tester.pump();
      expect(find.byType(Composer), findsNothing);
      await tester.pump();
      expect(() => composer.model.addListener(() {}), throwsFlutterError);
      await tester.tapAt(const Offset(220, 600));
      expect(rig.below, hasLength(1));
    });

    testWidgets('a new model takes away the old one\'s composer', (tester) async {
      final first = testComments();
      final rig = await pumpOverlays(tester, first);
      rig.controller.compose(const ReplyToVideo());
      await tester.pump();
      final old = tester.widget<Composer>(find.byType(Composer)).model;
      final second = testComments();
      await tester.pumpWidget(host(model: second, controller: rig.controller, below: rig.below, scroll: rig.scroll));
      expect(tester.widget<Composer>(find.byType(Composer)).model.comments, same(second));
      await tester.pump();
      expect(() => old.addListener(() {}), throwsFlutterError);
    });
  });

  group('the picture viewer', () {
    testWidgets('fades in over the whole page at the tapped picture, and fades out on close', (tester) async {
      final model = testComments();
      final rig = await pumpOverlays(tester, model);
      rig.controller.viewPictures(pictures, 1);
      await tester.pump();
      double opacity() => tester
          .widget<FadeTransition>(
            find.ancestor(of: find.byType(PictureViewer), matching: find.byType(FadeTransition)).first,
          )
          .opacity
          .value;
      expect(opacity(), 0);
      await tester.pump(const Duration(milliseconds: 200));
      expect(opacity(), 1);
      final viewer = tester.widget<PictureViewer>(find.byType(PictureViewer));
      expect(viewer.pictures, pictures);
      expect(viewer.initialIndex, 1);
      expect(tester.getRect(find.byType(PictureViewer)), Offset.zero & screen);

      viewer.onClose();
      expect(rig.controller.value, isNull);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(opacity(), inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(find.byType(PictureViewer), findsNothing);
    });

    testWidgets('a stale close leaves a newer overlay up', (tester) async {
      final model = testComments();
      final rig = await pumpOverlays(tester, model);
      rig.controller.viewPictures(pictures, 0);
      await tester.pumpAndSettle();
      final stale = tester.widget<PictureViewer>(find.byType(PictureViewer));
      rig.controller.confirmDelete(comment(9));
      await tester.pumpAndSettle();
      stale.onClose();
      expect(rig.controller.value, isA<DeleteOverlay>());
    });
  });

  group('the delete confirm', () {
    Future<(TestComments, Rig)> confirm(WidgetTester tester, Comment target) async {
      final model = testComments();
      final rig = await pumpOverlays(tester, model);
      rig.controller.confirmDelete(target);
      await tester.pumpAndSettle();
      return (model, rig);
    }

    testWidgets('asks 删除评论 / 确定删除这条评论吗？ with 取消 and 删除, centred', (tester) async {
      await confirm(tester, comment(7));
      expect(find.text('删除评论'), findsOneWidget);
      expect(find.text('确定删除这条评论吗？'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
      expect(tester.getCenter(find.byKey(const ValueKey('comment-delete-alert'))), const Offset(220, 478));
    });

    testWidgets('取消 closes it and deletes nothing', (tester) async {
      final (model, rig) = await confirm(tester, comment(7));
      await tester.tap(find.text('取消'));
      expect(rig.controller.value, isNull);
      await tester.pumpAndSettle();
      expect(find.text('删除评论'), findsNothing);
      expect(model.deleted, isEmpty);
    });

    testWidgets('删除 closes it and deletes the comment', (tester) async {
      final target = comment(7);
      final (model, rig) = await confirm(tester, target);
      await tester.tap(find.text('删除'));
      expect(rig.controller.value, isNull);
      expect(model.deleted, [target]);
      await tester.pumpAndSettle();
      expect(find.text('删除评论'), findsNothing);
      await tester.tapAt(const Offset(220, 600));
      expect(rig.below, hasLength(1));
    });

    testWidgets('a tap on the dim cancels; one on the alert does nothing', (tester) async {
      final (model, rig) = await confirm(tester, comment(7));
      await tester.tap(find.text('确定删除这条评论吗？'));
      expect(rig.controller.value, isA<DeleteOverlay>());
      await tester.tapAt(const Offset(220, 120));
      expect(rig.controller.value, isNull);
      expect(model.deleted, isEmpty);
      expect(rig.below, isEmpty);
    });

    testWidgets('it settles from slightly large as it fades in, and is gone at once with Reduce Motion', (
      tester,
    ) async {
      final model = testComments();
      final rig = await pumpOverlays(tester, model);
      rig.controller.confirmDelete(comment(7));
      await tester.pump();
      double opacity() => tester
          .widget<Opacity>(
            find.ancestor(of: find.byKey(const ValueKey('comment-delete-alert')), matching: find.byType(Opacity)),
          )
          .opacity;
      expect(opacity(), 0);
      await tester.pump(const Duration(milliseconds: 150));
      expect(opacity(), inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(opacity(), 1);

      final still = testComments();
      final stillRig = await pumpOverlays(tester, still, still: true);
      stillRig.controller.confirmDelete(comment(8));
      await tester.pump();
      expect(opacity(), 1);
      stillRig.controller.close();
      await tester.pump();
      expect(find.byKey(const ValueKey('comment-delete-alert')), findsNothing);
    });

    testWidgets('its buttons answer accessibility presses, and it alone is read while up', (tester) async {
      final handle = tester.ensureSemantics();
      final target = comment(7);
      final (model, rig) = await confirm(tester, target);
      expect(
        tester.getSemantics(find.byKey(const ValueKey('comment-delete-删除'))),
        matchesSemantics(label: '删除', isButton: true, hasTapAction: true),
      );
      expect(
        tester.getSemantics(find.byKey(const ValueKey('comment-delete-取消'))),
        matchesSemantics(label: '取消', isButton: true, hasTapAction: true),
      );
      tester.semantics.tap(find.semantics.byLabel('取消').first);
      expect(rig.controller.value, isNull);
      await tester.pumpAndSettle();
      rig.controller.confirmDelete(target);
      await tester.pumpAndSettle();
      tester.semantics.tap(find.semantics.byLabel('删除'));
      expect(model.deleted, [target]);
      handle.dispose();
    });

    testWidgets('under the system font, its words fall back to PingFang SC', (tester) async {
      Future<void> show() => confirm(tester, comment(7));
      await expectSystemFallback(tester, show, find.text('删除评论'));
      await expectSystemFallback(tester, show, find.text('删除'));
    });
  });
}
