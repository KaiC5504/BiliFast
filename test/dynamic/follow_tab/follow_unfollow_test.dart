import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/api.dart';
import 'package:bilifast/dynamic/fake_dynamic_api.dart';
import 'package:bilifast/dynamic/follow_tab/follow_feed_model.dart';
import 'package:bilifast/dynamic/follow_tab/follow_parts.dart';
import 'package:bilifast/home/home_tab_bar.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'follow_fixtures.dart';

/// Posts by mids 1, 2, 1, 3, 2, 3, … : every other one by 2's neighbours, so each author's posts are spread out.
List<DynamicItem> _mixed(int count) => [for (var i = 0; i < count; i++) post(i, mid: const [1, 2, 1, 3][i % 4])];

DynamicItem _withMenu(DynamicItem item) => DynamicItem(
  id: item.id,
  kind: item.kind,
  typeName: item.typeName,
  author: item.author,
  nodes: item.nodes,
  menu: const [DynamicMenuItem.unfollow, DynamicMenuItem.report],
);

void main() {
  setUp(() => FollowPosts.cardOverride = (item, inline) => SizedBox(height: 300, child: Text('post ${item.id}')));
  tearDown(() => FollowPosts.cardOverride = null);

  Finder shown(String id) => find.text('post $id', skipOffstage: false);

  Future<ShellRig> open(WidgetTester tester, {FakeDynamicApi? api}) async {
    final rig = await showShell(tester, api: api ?? FakeDynamicApi(posts: _mixed(12), upList: faces));
    await tester.tap(find.byKey(ValueKey('home-tab-${HomeTab.follow.name}')));
    await settle(tester);
    return rig;
  }

  ScrollPosition listScroll(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(of: find.byKey(const ValueKey('follow-list')), matching: find.byType(Scrollable)).first,
      )
      .position;

  double opacityOf(WidgetTester tester, String id) => tester
      .widget<FadeTransition>(find.ancestor(of: shown(id), matching: find.byType(FadeTransition)).first)
      .opacity
      .value;

  testWidgets('an unfollow made anywhere: the post on screen fades where it lay as the ones under it rise, on 263\'s '
      'curve; one further down just goes', (tester) async {
    final rig = await open(tester);
    final leaving = tester.getRect(shown('p1'));
    final under = tester.getRect(shown('p2'));
    expect(under.top - leaving.top, 300);
    expect(find.text('post p5', skipOffstage: false), findsNothing, reason: 'p5 is not built yet');

    rig.services.follows.changed(2, following: false);
    await tester.pump();
    expect(shown('p1'), findsOneWidget, reason: 'still drawn, over the list');
    expect(tester.getRect(shown('p1')), leaving);
    expect(opacityOf(tester, 'p1'), 1);
    expect(tester.getRect(shown('p2')).top, under.top);

    await tester.pump(const Duration(milliseconds: 95));
    final early = under.top - tester.getRect(shown('p2')).top;
    expect(early / 300, closeTo(DynamicFeedTheme.leaveCurve.transform(0.25), 0.01));
    expect(opacityOf(tester, 'p1'), closeTo(1 - early / 300, 0.01), reason: 'the fade on the same curve');
    expect(tester.getRect(shown('p1')).top, leaving.top, reason: 'it fades in place');

    await tester.pump(const Duration(milliseconds: 95));
    expect((under.top - tester.getRect(shown('p2')).top) / 300, greaterThan(0.85), reason: 'most of the way by 190 ms');

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(shown('p1'), findsNothing);
    expect(tester.getRect(shown('p2')).top, leaving.top);
    await tester.pump();
    expect(tester.getRect(shown('p2')).top, leaving.top, reason: 'its gap goes without a step');

    await tester.drag(find.byKey(const ValueKey('follow-list')), const Offset(0, -1500));
    await settle(tester);
    expect(find.text('post p5', skipOffstage: false), findsNothing);
    expect(find.text('post p9', skipOffstage: false), findsNothing);
    expect(find.text('post p6', skipOffstage: false), findsOneWidget);
  });

  testWidgets('the first post leaving hands its band over: the next takes its place without a step', (tester) async {
    final rig = await open(tester);
    final first = tester.getRect(shown('p0'));
    rig.services.follows.changed(1, following: false);
    final tops = <double>[];
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      tops.add(tester.getRect(shown('p1')).top);
    }
    expect(tops.last, first.top);
    for (var i = 1; i < tops.length; i++) {
      expect(tops[i], lessThanOrEqualTo(tops[i - 1]), reason: 'only ever rising');
    }
  });

  testWidgets('a refresh starts the list over: what was taken out no longer holds a place', (tester) async {
    final rig = await open(tester);
    final first = tester.getRect(shown('p0'));
    rig.services.follows.changed(2, following: false);
    await settle(tester);
    expect(tester.getRect(shown('p2')).top, first.bottom);

    // The fake still lists 2's posts, so a refresh brings p1 back in its old place.
    await tester.tap(find.byKey(ValueKey('home-tab-${HomeTab.follow.name}')));
    await settle(tester, 20);
    expect(tester.getRect(shown('p1')).top, first.bottom);
    expect(tester.getRect(shown('p2')).top, first.bottom + 300);
  });

  testWidgets('when every post was theirs, the list says it is empty once the last has faded', (tester) async {
    final rig = await open(tester, api: FakeDynamicApi(posts: posts(2, mid: 5), upList: faces));
    rig.services.follows.changed(5, following: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(shown('p0'), findsOneWidget);
    expect(find.byKey(const ValueKey('follow-empty')), findsNothing);
    await settle(tester);
    expect(shown('p0'), findsNothing);
    expect(find.byKey(const ValueKey('follow-empty')), findsOneWidget);
  });

  testWidgets("both lists lose the account's posts without asking Bilibili again", (tester) async {
    final api = FakeDynamicApi(
      posts: _mixed(8),
      videoPosts: [post(100, mid: 2), post(101, mid: 3), post(102, mid: 2)],
      upList: faces,
    );
    final rig = await open(tester, api: api);
    await tester.tap(find.byKey(const ValueKey('follow-switch-video')));
    await settle(tester);
    expect(shown('p100'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('follow-switch-all')));
    await settle(tester);
    final asked = List.of(api.calls);

    rig.services.follows.changed(2, following: false);
    await settle(tester);
    expect(shown('p1'), findsNothing);
    expect(shown('p0'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('follow-switch-video')));
    await settle(tester);
    expect(shown('p100'), findsNothing);
    expect(find.text('post p102', skipOffstage: false), findsNothing);
    expect(shown('p101'), findsOneWidget);
    expect(api.calls, asked);
  });

  testWidgets('a 关注 made, not taken back, removes nothing', (tester) async {
    final rig = await open(tester);
    rig.services.follows.changed(2, following: true);
    await settle(tester);
    expect(shown('p1'), findsOneWidget);
  });

  testWidgets('under Reduce Motion the post goes at once, the next in its place', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final rig = await open(tester);
    final leaving = tester.getRect(shown('p1'));

    rig.services.follows.changed(2, following: false);
    await tester.pump();
    expect(shown('p1'), findsNothing);
    expect(tester.getRect(shown('p2')).top, leaving.top);
    await tester.pump();
    expect(tester.getRect(shown('p2')).top, leaving.top);
  });

  testWidgets('posts above the screen go at once and what shows stays put, drawn or not', (tester) async {
    FollowPosts.cardOverride = (item, inline) => SizedBox(height: 120, child: Text('post ${item.id}'));
    final rig = await open(tester, api: FakeDynamicApi(posts: _mixed(24), upList: faces, pageSize: 30));
    final list = tester.getRect(find.byKey(const ValueKey('follow-list')));
    final scroll = listScroll(tester);
    scroll.jumpTo(scroll.pixels + tester.getRect(shown('p6')).top - list.top + 10);
    await tester.pump();
    // p5 (by 2) just above the screen, drawn in the list's cache under p4; p1 (by 2 too) no longer drawn.
    expect(shown('p1'), findsNothing);
    expect(tester.getRect(shown('p4')).bottom, lessThan(list.top));
    expect(tester.getRect(shown('p5')).bottom, lessThan(list.top));
    final at = {for (final id in ['p6', 'p7', 'p8']) id: tester.getRect(shown(id))};

    rig.services.follows.changed(2, following: false);
    for (var frame = 0; frame < 3; frame++) {
      await tester.pump();
      for (final MapEntry(key: id, value: rect) in at.entries) {
        expect(tester.getRect(shown(id)), rect, reason: '$id in frame $frame');
      }
    }
    expect(shown('p5'), findsNothing);

    await settle(tester);
    scroll.jumpTo(0);
    await settle(tester);
    expect(tester.getRect(shown('p0')).top, 284, reason: 'the list still starts under the top');
    expect(tester.getRect(shown('p2')).top, 284 + 120);
  });

  testWidgets('posts far above the screen, never built since, close too: scrolled back up the list moves only as far '
      'as it is scrolled, and starts under the top', (tester) async {
    FollowPosts.cardOverride = (item, inline) => SizedBox(height: 120, child: Text('post ${item.id}'));
    // Long enough that the list's end stays far below the screen.
    final rig = await open(tester, api: FakeDynamicApi(posts: _mixed(40), upList: faces, pageSize: 40));
    final list = tester.getRect(find.byKey(const ValueKey('follow-list')));
    final scroll = listScroll(tester);
    scroll.jumpTo(284 + 120 * 16 - list.top);
    await tester.pump();
    expect(tester.getRect(shown('p16')).top, list.top);
    // p13 (by 2) lies in the cache above the screen; 2's p1, p5 and p9 are far above it, not built.
    expect(shown('p13'), findsOneWidget);
    for (final id in ['p1', 'p5', 'p9']) {
      expect(shown(id), findsNothing);
    }

    rig.services.follows.changed(2, following: false);
    for (var frame = 0; frame < 3; frame++) {
      await tester.pump();
      expect(tester.getRect(shown('p16')).top, list.top, reason: 'frame $frame');
    }
    await settle(tester);
    expect(tester.getRect(shown('p16')).top, list.top);

    Map<String, double> tops() => {
      for (var n = 0; n < 40; n++)
        if (find.text('post p$n').evaluate().isNotEmpty) 'p$n': tester.getRect(find.text('post p$n')).top,
    };
    var at = scroll.pixels;
    while (at > 0) {
      final before = tops();
      final step = math.min(45.0, at);
      at -= step;
      scroll.jumpTo(at);
      await tester.pump();
      expect(scroll.pixels, at, reason: 'no correction at $at');
      final after = tops();
      for (final MapEntry(key: id, value: top) in before.entries) {
        if (after[id] case final moved?) expect(moved - top, step, reason: '$id at $at');
      }
    }
    expect(tester.getRect(shown('p0')).top, 284);
    expect(tester.getRect(shown('p2')).top, 284 + 120);
    expect(tester.getRect(shown('p3')).top, 284 + 240);
  });

  testWidgets('posts leave at once while 关注 is out of sight', (tester) async {
    final rig = await open(tester);
    await tester.tap(find.byKey(ValueKey('home-tab-${HomeTab.home.name}')));
    await settle(tester);
    rig.services.follows.changed(2, following: false);
    await tester.pump();
    await tester.tap(find.byKey(ValueKey('home-tab-${HomeTab.follow.name}')));
    await tester.pump();
    expect(shown('p1'), findsNothing);
    expect(shown('p2'), findsOneWidget);
  });

  test("a list's generation moves when it starts over, not when posts leave or a page is added", () async {
    final api = FakeDynamicApi(posts: _mixed(30));
    final feed = FollowFeed(name: 'all', load: (offset) => api.feed(DynamicFeedType.all, offset: offset));
    addTearDown(feed.dispose);
    await feed.start();
    final first = feed.generation;
    feed.removeAuthor(2);
    await feed.loadMore();
    expect(feed.generation, first);
    await feed.reload();
    expect(feed.generation, greaterThan(first));
    final reloaded = feed.generation;
    feed.clear();
    expect(feed.generation, greaterThan(reloaded));
  });

  group('a page out when the unfollow lands', () {
    late FakeDynamicApi api;
    late FollowFeed feed;

    void make(List<DynamicItem> list) {
      api = FakeDynamicApi(posts: list);
      feed = FollowFeed(name: 'all', load: (offset) => api.feed(DynamicFeedType.all, offset: offset));
      addTearDown(feed.dispose);
    }

    List<int> mids() => [for (final item in feed.items) item.author.mid];
    List<String> ids() => [for (final item in feed.items) item.id];

    /// Runs [call] with the feed's answer held until [mid] is unfollowed.
    Future<void> heldOver(Future<void> Function() call, int mid) async {
      final hold = api.holds['feed'] = Completer<void>();
      final out = call();
      feed.removeAuthor(mid);
      api.holds.remove('feed');
      hold.complete();
      await out;
    }

    test("a next page doesn't bring the account's posts back", () async {
      make(_mixed(30));
      await feed.start();
      await heldOver(feed.loadMore, 2);
      expect(ids(), containsAll(['p10', 'p11', 'p12']), reason: 'the page landed');
      expect(mids(), isNot(contains(2)));
      await feed.loadMore();
      expect(ids(), contains('p20'));
      expect(mids(), isNot(contains(2)), reason: 'kept out for the rest of this list');
    });

    test("a refresh's first page doesn't either, nor the pages after it", () async {
      make(_mixed(30));
      await feed.start();
      await heldOver(feed.reload, 2);
      expect(ids(), contains('p0'));
      expect(mids(), isNot(contains(2)));
      await feed.loadMore();
      expect(ids(), contains('p10'));
      expect(mids(), isNot(contains(2)));
    });

    test('a page of nothing but their posts adds nothing and the list pages on', () async {
      make([...posts(10), ...posts(10, mid: 2, from: 10), ...posts(10, from: 20)]);
      await feed.start();
      await heldOver(feed.loadMore, 2);
      expect(ids(), posts(10).map((item) => item.id));
      expect(feed.isEnd, isFalse);
      await feed.loadMore();
      expect(ids(), contains('p20'));
    });

    test('followed again, a refresh shows their posts, and so do the pages after it', () async {
      make(_mixed(30));
      await feed.start();
      feed.removeAuthor(2);
      expect(mids(), isNot(contains(2)));
      // Asked after the unfollow, so whatever Bilibili answers is shown: here 2's posts, as after a 关注 again.
      await feed.reload();
      expect(ids(), contains('p1'));
      await feed.loadMore();
      expect(ids(), contains('p13'));
    });

    test('signing out forgets them too', () async {
      make(_mixed(30));
      await feed.start();
      feed.removeAuthor(2);
      feed.clear();
      await feed.start();
      expect(ids(), contains('p1'));
    });
  });

  group('⋮ → 取消关注 on a post', () {
    setUp(() => FollowPosts.cardOverride = null);

    Future<void> unfollowFirstBy(WidgetTester tester, String id, {required String answer}) async {
      final card = find.byKey(ValueKey('follow-post-$id'));
      await tester.tap(find.descendant(of: card, matching: find.byKey(const ValueKey('dynamic-more'))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dynamic-more-unfollow')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('dynamic-unfollow-$answer')));
    }

    testWidgets("confirmed, every post by the author leaves and 已取消关注 says so", (tester) async {
      final api = FakeDynamicApi(posts: [for (final item in _mixed(6)) _withMenu(item)], upList: faces);
      await open(tester, api: api);
      await unfollowFirstBy(tester, 'p1', answer: '取消关注');
      await tester.pump();
      await tester.pump();
      expect(api.unfollowed, [2]);
      expect(find.descendant(of: find.byKey(const ValueKey('toast')), matching: find.text('已取消关注')), findsOneWidget);
      await settle(tester, 50);
      expect(find.byKey(const ValueKey('follow-post-p1'), skipOffstage: false), findsNothing);
      expect(find.byKey(const ValueKey('follow-post-p5'), skipOffstage: false), findsNothing);
      expect(find.byKey(const ValueKey('follow-post-p0')), findsOneWidget);
    });

    testWidgets('refused, or 再想想, nothing leaves', (tester) async {
      final api = FakeDynamicApi(posts: [for (final item in _mixed(6)) _withMenu(item)], upList: faces)
        ..failures['unfollow'] = const BiliError.api(code: 22001, message: '不能对自己进行此操作');
      await open(tester, api: api);
      await unfollowFirstBy(tester, 'p1', answer: '取消关注');
      await settle(tester, 50);
      expect(find.byKey(const ValueKey('follow-post-p1')), findsOneWidget);

      await unfollowFirstBy(tester, 'p1', answer: '再想想');
      await settle(tester, 50);
      expect(find.byKey(const ValueKey('follow-post-p1')), findsOneWidget);
      expect(api.unfollowed, isEmpty);
    });
  });
}
