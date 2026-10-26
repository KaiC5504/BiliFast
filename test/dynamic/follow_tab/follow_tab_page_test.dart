import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:bilifast/dynamic/fake_dynamic_api.dart';
import 'package:bilifast/dynamic/follow_tab/follow_parts.dart';
import 'package:bilifast/dynamic/follow_tab/follow_tab_page.dart';
import 'package:bilifast/dynamic/follow_tab/follow_top.dart';
import 'package:bilifast/home/feed_inline_player.dart';
import 'package:bilifast/home/home_page.dart';
import 'package:bilifast/home/home_tab_bar.dart';
import 'package:bilifast/shared/loading_tv.dart';
import 'package:bilifast/space/own/own_space_page.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/skin/skin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../home/skin_fixtures.dart';
import '../../playback/fakes.dart' show Canned;
import 'follow_fixtures.dart';

late SkinPictures _pictures;

/// A video card as the inline host sees it, its box wherever the test puts it.
final class _FakeInlineCard implements FeedInlineCard {
  _FakeInlineCard(this.box);

  Rect box;
  int plays = 0;
  int pauses = 0;

  @override
  Rect? videoRect() => box;

  @override
  void inlinePlay() => plays++;

  @override
  void inlinePause() => pauses++;
}

/// A login page that logs in through [login] before answering.
final class _LoggingInGate implements LoginGate {
  late Future<bool> Function() login;
  int requests = 0;

  @override
  Future<bool> request(BuildContext context) async {
    requests++;
    return login();
  }
}

void main() {
  setUpAll(() async => _pictures = await SkinPictures.draw());
  tearDownAll(() => _pictures.dispose());

  /// The host the cards were last given.
  FeedInlineHost? host;

  setUp(() {
    host = null;
    FollowPosts.cardOverride = (item, inline) {
      host = inline;
      return SizedBox(height: 300, child: Text('post ${item.id}'));
    };
  });

  tearDown(() => FollowPosts.cardOverride = null);

  Finder tab(HomeTab tab) => find.byKey(ValueKey('home-tab-${tab.name}'));

  Future<void> tapTab(WidgetTester tester, HomeTab which) async {
    await tester.tap(tab(which));
    await tester.pump();
  }

  ScrollPosition listScroll(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(of: find.byKey(const ValueKey('follow-list')), matching: find.byType(Scrollable)).first,
      )
      .position;

  Finder sheetFaces() => find.byKey(const ValueKey('face-sheet-faces'));

  testWidgets('关注 is a place of its own, kept alive: it asks nothing until first shown, then keeps its list', (
    tester,
  ) async {
    final rig = await showShell(tester);
    await settle(tester, 20);
    expect(rig.api.calls, isEmpty, reason: 'nothing at launch');
    expect(find.byType(FollowTabPage, skipOffstage: false), findsOneWidget);

    await tapTab(tester, HomeTab.follow);
    await settle(tester);
    expect(rig.api.calls, ['ups offset=', 'feed all offset=']);
    expect(find.text('关注'), findsWidgets);
    expect(find.text('post p0'), findsOneWidget);
    expect(find.byType(HomePage), findsNothing, reason: '首页 offstage');
    final page = tester.state(find.byType(FollowTabPage));

    await tester.drag(find.byKey(const ValueKey('follow-list')), const Offset(0, -500));
    await settle(tester);
    final at = listScroll(tester).pixels;
    expect(at, greaterThan(300));
    final asked = List.of(rig.api.calls);

    await tapTab(tester, HomeTab.home);
    await settle(tester);
    expect(find.byType(FollowTabPage), findsNothing, reason: 'offstage');
    expect(find.byType(HomePage), findsOneWidget);
    await tapTab(tester, HomeTab.follow);
    await settle(tester);
    expect(tester.state(find.byType(FollowTabPage)), same(page));
    expect(listScroll(tester).pixels, at);
    expect(rig.api.calls, asked, reason: 'no reload');
  });

  testWidgets('关注 tapped while shown goes back to the top and refreshes, its TV held open until the answer', (
    tester,
  ) async {
    final rig = await showShell(tester);
    await tapTab(tester, HomeTab.follow);
    await settle(tester);
    await tester.drag(find.byKey(const ValueKey('follow-list')), const Offset(0, -600));
    await settle(tester);
    expect(listScroll(tester).pixels, greaterThan(300));

    rig.api.holds['feed'] = Completer<void>();
    final before = rig.api.calls.length;
    await tapTab(tester, HomeTab.follow);
    await settle(tester, 12);
    expect(listScroll(tester).pixels, 0);
    expect(find.byKey(const ValueKey('follow-reload')), findsOneWidget);
    expect(rig.api.calls.sublist(before), ['ups offset=', 'feed all offset=']);

    await tapTab(tester, HomeTab.follow);
    await settle(tester);
    expect(rig.api.calls.length, before + 2, reason: 'one refresh at a time');

    rig.api.holds.remove('feed')!.complete();
    await settle(tester);
    expect(find.byKey(const ValueKey('follow-reload')), findsNothing);
    expect(find.text('post p0'), findsOneWidget);
  });

  testWidgets('全部 / 视频: 视频 asks its own list and 我的追番 · 追剧 once, drops 更多; 全部 comes back as it was', (tester) async {
    final api = FakeDynamicApi(
      posts: posts(12),
      videoPosts: posts(4, from: 100),
      upList: faces,
      bangumiList: const [
        FollowedBangumi(seasonId: 1, title: '星之丘 第三季', cover: '', progress: '全13话'),
        FollowedBangumi(seasonId: 2, title: '星之丘', cover: '', progress: '全4话'),
      ],
    );
    final rig = await showShell(tester, api: api);
    await tapTab(tester, HomeTab.follow);
    await settle(tester);
    expect(find.byKey(const ValueKey('follow-faces-more')), findsOneWidget);
    expect(find.byKey(const ValueKey('follow-bangumi')), findsNothing);
    expect(tester.getSemantics(find.byKey(const ValueKey('follow-switch-all'))), isSemantics(isSelected: true));

    await tester.tap(find.byKey(const ValueKey('follow-switch-video')));
    await settle(tester);
    expect(rig.api.calls, ['ups offset=', 'feed all offset=', 'feed video offset=', 'bangumi page=1']);
    expect(find.text('post p100'), findsOneWidget);
    expect(find.text('post p0'), findsNothing);
    expect(find.byKey(const ValueKey('follow-faces-more')), findsNothing, reason: '128 has no 更多');
    expect(find.byKey(const ValueKey('follow-bangumi')), findsOneWidget);
    expect(find.text('全13话'), findsOneWidget);
    expect(find.text('星之丘 第三季'), findsOneWidget);
    expect(tester.getSemantics(find.byKey(const ValueKey('follow-switch-video'))), isSemantics(isSelected: true));

    await tester.tap(find.byKey(const ValueKey('follow-poster-1')));
    await tester.pump();
    expect(find.text('暂未开放'), findsOneWidget);
    await settle(tester, 60);
    await tester.tap(find.byKey(const ValueKey('follow-bangumi-all')));
    await settle(tester);
    final own = tester.widget<OwnSpacePage>(find.byType(OwnSpacePage));
    expect((own.uploader.mid, own.initialTab), (rig.services.environment.mid, SpaceTabKind.bangumi));
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('follow-switch-all')));
    await settle(tester);
    expect(find.text('post p0'), findsOneWidget);
    expect(find.byKey(const ValueKey('follow-bangumi')), findsNothing);
    expect(find.byKey(const ValueKey('follow-faces-more')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('follow-switch-video')));
    await settle(tester);
    expect(rig.api.calls.length, 4, reason: 'both lists kept, the posters asked once');
  });

  testWidgets('我的追番 · 追剧 stays hidden when the account follows none', (tester) async {
    final rig = await showShell(
      tester,
      api: FakeDynamicApi(posts: posts(3), upList: faces),
    );
    await tapTab(tester, HomeTab.follow);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('follow-switch-video')));
    await settle(tester);
    expect(rig.api.calls, contains('bangumi page=1'));
    expect(find.byKey(const ValueKey('follow-bangumi')), findsNothing);
  });

  testWidgets('posts page near the end, one call at a time, and stop at the last page', (tester) async {
    final rig = await showShell(
      tester,
      api: FakeDynamicApi(posts: posts(25), upList: faces),
    );
    await tapTab(tester, HomeTab.follow);
    await settle(tester);
    expect(rig.api.calls.where((call) => call.startsWith('feed')), ['feed all offset=']);

    rig.api.holds['feed'] = Completer<void>();
    await tester.drag(find.byKey(const ValueKey('follow-list')), const Offset(0, -2400));
    await settle(tester);
    expect(rig.api.calls.where((call) => call.startsWith('feed')), ['feed all offset=', 'feed all offset=p1']);
    expect(find.byKey(const ValueKey('follow-faces-more')), findsNothing, reason: 'scrolled away');
    expect(find.byKey(const ValueKey('follow-faces-more'), skipOffstage: false), findsOneWidget);
    await tester.drag(find.byKey(const ValueKey('follow-list')), const Offset(0, -400));
    await settle(tester);
    expect(rig.api.calls.where((call) => call.startsWith('feed')).length, 2, reason: 'one call at a time');
    rig.api.holds.remove('feed')!.complete();
    await settle(tester);

    for (var i = 0; i < 6; i++) {
      await tester.drag(find.byKey(const ValueKey('follow-list')), const Offset(0, -2400));
      await settle(tester);
    }
    expect(rig.api.calls.where((call) => call.startsWith('feed')), [
      'feed all offset=',
      'feed all offset=p1',
      'feed all offset=p2',
    ]);
    expect(find.byKey(const ValueKey('follow-end')), findsOneWidget);
    expect(find.text('post p24'), findsOneWidget);
  });

  testWidgets('a pull refreshes on release; a failure over shown posts keeps them and says why', (tester) async {
    final rig = await showShell(tester);
    await tapTab(tester, HomeTab.follow);
    await settle(tester);
    final before = rig.api.calls.length;

    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('follow-list'))));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(0, 15));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(rig.api.calls.length, before, reason: 'nothing while held');
    await gesture.up();
    await settle(tester, 30);
    expect(rig.api.calls.sublist(before), ['ups offset=', 'feed all offset=']);

    rig.api.failures['feed'] = const BiliError.api(code: -500, message: '服务器错误');
    final pull = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('follow-list'))));
    for (var i = 0; i < 20; i++) {
      await pull.moveBy(const Offset(0, 15));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await pull.up();
    await settle(tester, 4);
    expect(find.text('B 站返回错误 -500：服务器错误'), findsOneWidget, reason: 'a toast');
    expect(find.text('post p0'), findsOneWidget, reason: 'kept');
    expect(find.byKey(const ValueKey('follow-failed')), findsNothing);
    await settle(tester, 60);
  });

  testWidgets('the first load shows the TV; a failure offers 重试, which loads it', (tester) async {
    final api = FakeDynamicApi(posts: posts(3), upList: faces)..holds['feed'] = Completer<void>();
    await showShell(tester, api: api);
    await tapTab(tester, HomeTab.follow);
    await settle(tester);
    expect(find.byType(LoadingTvState), findsOneWidget);
    expect(find.text('最常访问'), findsOneWidget, reason: 'the faces come on their own');

    api.failures['feed'] = const BiliError.api(code: -500, message: '服务器错误');
    api.holds.remove('feed')!.complete();
    await settle(tester);
    expect(find.byKey(const ValueKey('follow-failed')), findsOneWidget);

    api.failures.remove('feed');
    await tester.tap(find.byKey(const ValueKey('follow-retry')));
    await settle(tester);
    expect(find.byKey(const ValueKey('follow-failed')), findsNothing);
    expect(find.text('post p0'), findsOneWidget);
  });

  testWidgets('the face sheet: a face opens its posts and loses its dot, another face switches it, ✕ and back close', (
    tester,
  ) async {
    final api = FakeDynamicApi(posts: [...posts(3, mid: 101), ...posts(2, mid: 102, from: 10)], upList: faces);
    final rig = await showShell(tester, api: api);
    await tapTab(tester, HomeTab.follow);
    await settle(tester);
    expect(find.byKey(const ValueKey('follow-dot-101')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('follow-face-101')));
    await settle(tester, 12);
    expect(find.text('晚风的星星的动态'), findsOneWidget);
    expect(rig.api.calls.last, 'spacePosts 101 offset=');
    expect(find.byKey(const ValueKey('follow-dot-101'), skipOffstage: false), findsNothing);
    expect(find.descendant(of: sheetFaces(), matching: find.byKey(const ValueKey('follow-dot-102'))), findsOneWidget);
    expect(find.byKey(const ValueKey('face-sheet-pointer')), findsOneWidget);
    final sheet = tester.getRect(find.byKey(const ValueKey('face-sheet')));
    expect(sheet.top, 62 + 127);
    expect(sheet.bottom, 956, reason: 'over the bar');
    final pointer = tester.getRect(find.byKey(const ValueKey('face-sheet-pointer')));
    final face = tester.getRect(
      find.descendant(of: sheetFaces(), matching: find.byKey(const ValueKey('follow-face-101'))),
    );
    expect(pointer.center.dx, moreOrLessEquals(face.center.dx, epsilon: 0.01));
    expect(
      find.descendant(of: find.byKey(const ValueKey('face-sheet')), matching: find.text('post p0')),
      findsOneWidget,
    );

    await tester.tap(find.descendant(of: sheetFaces(), matching: find.byKey(const ValueKey('follow-face-102'))));
    await settle(tester, 12);
    expect(find.text('云舟mimi的动态'), findsOneWidget);
    expect(rig.api.calls.last, 'spacePosts 102 offset=');
    expect(
      find.descendant(of: find.byKey(const ValueKey('face-sheet')), matching: find.text('post p10')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('follow-dot-102'), skipOffstage: false), findsNothing);
    final moved = tester.getRect(find.byKey(const ValueKey('face-sheet-pointer')));
    expect(moved.center.dx, moreOrLessEquals(pointer.center.dx + 74, epsilon: 0.01));

    await tester.tap(find.byKey(const ValueKey('face-sheet-close')));
    await settle(tester, 12);
    expect(find.byKey(const ValueKey('face-sheet')), findsNothing);
    expect(find.byKey(const ValueKey('follow-dot-103')), findsOneWidget, reason: 'unopened faces keep theirs');

    await tester.tap(find.byKey(const ValueKey('follow-face-103')));
    await settle(tester, 12);
    expect(find.text('星海远航计划的动态'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settle(tester, 12);
    expect(find.byKey(const ValueKey('face-sheet')), findsNothing, reason: 'back closes it first');
    expect(find.byType(FollowTabPage), findsOneWidget);
  });

  testWidgets('cards play while 关注 shows with nothing over it: not under 首页, the face sheet or a page', (tester) async {
    await showShell(tester, routes: {'/other': (_) => const Scaffold(body: Text('other page'))});
    await tapTab(tester, HomeTab.follow);
    await settle(tester);
    final inline = host!;
    final card = _FakeInlineCard(const Rect.fromLTWH(0, 400, 440, 200));
    inline.register(card);
    await settle(tester, 2);
    expect(inline.playing, same(card));

    await tapTab(tester, HomeTab.home);
    await settle(tester, 2);
    expect(inline.playing, isNull);
    await tapTab(tester, HomeTab.follow);
    await settle(tester, 2);
    expect(inline.playing, same(card));

    await tester.tap(find.byKey(const ValueKey('follow-face-101')));
    await settle(tester, 12);
    expect(inline.playing, isNull, reason: 'the face sheet is over it');
    await tester.tap(find.byKey(const ValueKey('face-sheet-close')));
    await settle(tester, 12);
    expect(inline.playing, same(card));

    unawaited(tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/other'));
    await settle(tester, 12);
    expect(inline.playing, isNull, reason: 'a page over it');
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await settle(tester, 12);
    expect(inline.playing, same(card));
    inline.unregister(card);
  });

  testWidgets('logged out: the prompt and its 登录, through the login gate, and no call to Bilibili', (tester) async {
    final rig = await showShell(tester, loggedIn: false);
    await tapTab(tester, HomeTab.follow);
    await settle(tester);
    expect(find.text('登录后查看关注动态'), findsOneWidget);
    expect(find.byKey(const ValueKey('follow-list')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('follow-login')));
    await settle(tester);
    expect(rig.gate.requests, 1);
    expect(rig.api.calls, isEmpty);
  });

  testWidgets('a -101 with nothing shown asks for the login; logging in loads the list', (tester) async {
    final api = FakeDynamicApi(posts: posts(3), upList: faces)
      ..failures['feed'] = const BiliError.api(code: -101, message: '账号未登录');
    final rig = await showShell(tester, api: api);
    await tapTab(tester, HomeTab.follow);
    await settle(tester);
    expect(find.text('登录后查看关注动态'), findsOneWidget);
    api.failures.remove('feed');
    rig.gate.answer = true;
    await tester.tap(find.byKey(const ValueKey('follow-login')));
    await settle(tester);
    expect(rig.gate.requests, 1);
    expect(find.text('post p0'), findsOneWidget);
  });

  testWidgets('the header: 关注 centred on its row, 88 pt down; ✏️ says 暂未开放', (tester) async {
    await showShell(tester);
    await tapTab(tester, HomeTab.follow);
    await settle(tester);
    final header = tester.getRect(find.byKey(const ValueKey('follow-header')));
    expect(header, const Rect.fromLTWH(0, 0, 440, 88));
    expect(tester.getCenter(find.byKey(const ValueKey('follow-title'))), const Offset(220, 66));
    await tester.tap(find.byKey(const ValueKey('follow-write')));
    await tester.pump();
    expect(find.text('暂未开放'), findsOneWidget);
    await settle(tester, 60);
  });

  testWidgets("dressed by the 装扮: head_bg behind the header, 关注 and ✏️ in the skin's colour, the status bar by the "
      'picture', (tester) async {
    await showShell(tester, skin: _pictures.skin());
    await tapTab(tester, HomeTab.follow);
    await settle(tester);
    final art = find.byKey(const ValueKey('follow-head-art'));
    expect(tester.getRect(art), const Rect.fromLTWH(0, 0, 440, 88));
    final image = tester.widget<Image>(art);
    expect((image.image as FileImage).file.path, _pictures['head_bg.png'].path);
    expect(image.fit, BoxFit.cover);
    expect(tester.widget<Text>(find.byKey(const ValueKey('follow-title'))).style?.color, const Color(0xFFFFFFFF));
    final pen = tester.widget<Image>(
      find.descendant(of: find.byKey(const ValueKey('follow-write')), matching: find.byType(Image)),
    );
    expect(pen.color, const Color(0xFFFFFFFF).withValues(alpha: 0.88));
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.light);

    await showShell(tester, skin: _pictures.skin(head: false));
    await tapTab(tester, HomeTab.follow);
    await settle(tester);
    expect(art, findsNothing);
    expect(tester.widget<Text>(find.byKey(const ValueKey('follow-title'))).style?.color, BiliColors.text);
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.dark);
  });

  testWidgets('关注 tapped twice on its first show asks one set: the second waits on the first load', (tester) async {
    final api = FakeDynamicApi(posts: posts(3), upList: faces)
      ..holds['ups'] = Completer<void>()
      ..holds['feed'] = Completer<void>();
    final rig = await showShell(tester, api: api);
    await tapTab(tester, HomeTab.follow);
    await tapTab(tester, HomeTab.follow);
    await settle(tester);
    expect(rig.api.calls, ['ups offset=', 'feed all offset=']);
    expect(find.byType(LoadingTvState), findsOneWidget);
    expect(find.byKey(const ValueKey('follow-reload')), findsNothing, reason: "the list's own TV stands for it");

    api.holds.remove('ups')!.complete();
    api.holds.remove('feed')!.complete();
    await settle(tester);
    expect(find.text('post p0'), findsOneWidget);
    expect(rig.api.calls, hasLength(2));
  });

  testWidgets('a pull while a refresh is out waits on it', (tester) async {
    final rig = await showShell(tester);
    await tapTab(tester, HomeTab.follow);
    await settle(tester);
    rig.api.holds['feed'] = Completer<void>();
    final before = rig.api.calls.length;
    await tapTab(tester, HomeTab.follow);
    await settle(tester, 12);
    expect(rig.api.calls.sublist(before), ['ups offset=', 'feed all offset=']);

    final pull = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('follow-list'))));
    for (var i = 0; i < 20; i++) {
      await pull.moveBy(const Offset(0, 15));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await pull.up();
    await settle(tester, 12);
    expect(rig.api.calls, hasLength(before + 2));
    rig.api.holds.remove('feed')!.complete();
    await settle(tester, 30);
    expect(rig.api.calls, hasLength(before + 2));
  });

  testWidgets("logged out, 登录 that logs in loads the tab once: the login's own first load, no refresh after it", (
    tester,
  ) async {
    final gate = _LoggingInGate();
    final rig = await showShell(tester, loggedIn: false, loginGate: gate);
    gate.login = () async {
      rig.http.canned.routes[Canned.navPath] = (200, Canned.navLoggedIn);
      return rig.services.environment.didLogin(Canned.cookies);
    };
    await tapTab(tester, HomeTab.follow);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('follow-login')));
    await settle(tester, 20);
    expect(gate.requests, 1);
    expect(find.text('post p0'), findsOneWidget);
    expect(rig.api.calls, ['ups offset=', 'feed all offset=']);
  });

  testWidgets('an empty list, then a failed refresh: 重试 asks again and the posts come', (tester) async {
    final shown = <DynamicItem>[];
    final api = FakeDynamicApi(posts: shown, upList: faces);
    await showShell(tester, api: api);
    await tapTab(tester, HomeTab.follow);
    await settle(tester);
    expect(find.byKey(const ValueKey('follow-empty')), findsOneWidget);

    api.failures['feed'] = const BiliError.api(code: -500, message: '服务器错误');
    await tapTab(tester, HomeTab.follow);
    await settle(tester);
    expect(find.byKey(const ValueKey('follow-failed')), findsOneWidget);
    expect(find.text('B 站返回错误 -500：服务器错误'), findsOneWidget);

    api.failures.remove('feed');
    shown.addAll(posts(3));
    await tester.tap(find.byKey(const ValueKey('follow-retry')));
    await settle(tester);
    expect(find.text('post p0'), findsOneWidget);
  });

  testWidgets("risk control says so: the first load's failure and the footer's carry the error's own words", (
    tester,
  ) async {
    const busy = BiliError.api(code: -352, message: '风控校验失败');
    final api = FakeDynamicApi(posts: posts(25), upList: faces)..failures['feed'] = busy;
    final rig = await showShell(tester, api: api);
    await tapTab(tester, HomeTab.follow);
    await settle(tester);
    expect(find.text('请求过于频繁，请稍后再试'), findsOneWidget);
    api.failures.remove('feed');
    await tester.tap(find.byKey(const ValueKey('follow-retry')));
    await settle(tester);
    expect(find.text('post p0'), findsOneWidget);

    api.failures['feed'] = busy;
    for (var i = 0; i < 3; i++) {
      await tester.drag(find.byKey(const ValueKey('follow-list')), const Offset(0, -2400));
      await settle(tester);
    }
    expect(rig.api.calls.where((call) => call.startsWith('feed')), [
      'feed all offset=',
      'feed all offset=',
      'feed all offset=p1',
    ]);
    expect(find.text('请求过于频繁，请稍后再试，点击重试', findRichText: true), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('follow-footer-retry'))),
      isSemantics(label: '请求过于频繁，请稍后再试，点击重试'),
    );

    api.failures.remove('feed');
    await tester.tap(find.byKey(const ValueKey('follow-footer-retry')));
    await settle(tester);
    expect(rig.api.calls.where((call) => call.startsWith('feed')).last, 'feed all offset=p1');
    expect(find.text('请求过于频繁，请稍后再试，点击重试', findRichText: true), findsNothing);
  });

  testWidgets("最常访问's next page failing is asked once: scrolling the row's end again asks nothing", (tester) async {
    final many = [for (var i = 0; i < 8; i++) DynamicUp(mid: 200 + i, name: '演示$i', face: '')];
    final api = PagedUpsApi(posts: posts(3), first: many, rest: faces)
      ..failMore = const BiliError.api(code: -352, message: '风控校验失败');
    final rig = await showShell(tester, api: api);
    await tapTab(tester, HomeTab.follow);
    await settle(tester);
    final row = find.descendant(of: find.byType(FollowFacesRow), matching: find.byType(Scrollable)).first;
    for (var i = 0; i < 3; i++) {
      await tester.drag(row, const Offset(-300, 0));
      await settle(tester);
      await tester.drag(row, const Offset(100, 0));
      await settle(tester);
    }
    expect(rig.api.calls.where((call) => call == 'ups offset=u1'), hasLength(1));
    expect(find.byKey(const ValueKey('follow-face-101'), skipOffstage: false), findsNothing);

    api.failMore = null;
    await tapTab(tester, HomeTab.follow);
    await settle(tester, 30);
    await tester.drag(row, const Offset(-300, 0));
    await settle(tester);
    expect(rig.api.calls.where((call) => call == 'ups offset=u1'), hasLength(2), reason: 'a refresh lifts it');
    expect(find.byKey(const ValueKey('follow-face-101'), skipOffstage: false), findsOneWidget);
  });

  testWidgets('关注 pressed while the face sheet is open closes it, then refreshes as ever', (tester) async {
    final semantics = tester.ensureSemantics();
    final rig = await showShell(tester);
    await tapTab(tester, HomeTab.follow);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('follow-face-101')));
    await settle(tester, 12);
    expect(find.byKey(const ValueKey('face-sheet')), findsOneWidget);
    final before = rig.api.calls.length;

    // The sheet's frost lies over the bar, so the press comes as VoiceOver's.
    tester.semantics.tap(
      find.semantics.byPredicate(
        (node) => node.label == HomeTab.follow.label && node.getSemanticsData().hasAction(SemanticsAction.tap),
      ),
    );
    await settle(tester, 20);
    expect(find.byKey(const ValueKey('face-sheet')), findsNothing);
    expect(rig.api.calls.sublist(before), ['ups offset=', 'feed all offset=']);
    semantics.dispose();
  });

  testWidgets('logging out while 关注 shows with the face sheet open closes it, empties the tab for the login prompt '
      'and asks nothing', (tester) async {
    final rig = await showShell(tester);
    await tapTab(tester, HomeTab.follow);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('follow-face-101')));
    await settle(tester, 12);
    expect(find.byKey(const ValueKey('face-sheet')), findsOneWidget);
    final asked = List.of(rig.api.calls);

    await rig.services.environment.logout();
    await settle(tester, 20);
    expect(find.byKey(const ValueKey('face-sheet')), findsNothing);
    expect(find.text('登录后查看关注动态'), findsOneWidget);
    expect(find.text('post p0', skipOffstage: false), findsNothing);
    expect(find.byKey(const ValueKey('follow-face-101'), skipOffstage: false), findsNothing);
    expect(rig.api.calls, asked);
    await settle(tester, 60);
    expect(rig.api.calls, asked);
  });

  for (final (home, follow) in [(0.9, 0.01), (0.01, 0.9)]) {
    final white = follow < SkinStatusBar.crossover;
    testWidgets("the status bar over 关注's dressed header goes by its own cut of head_bg, not 首页's: "
        "${white ? 'white' : 'black'} icons", (tester) async {
      await showShell(
        tester,
        skin: _pictures.skin().withStatusBar(SkinStatusBar(home: home, follow: follow)),
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('home-head-art')), findsOneWidget);
      expect(SystemChrome.latestStyle?.statusBarIconBrightness, white ? Brightness.dark : Brightness.light);
      await tapTab(tester, HomeTab.follow);
      await settle(tester);
      expect(find.byKey(const ValueKey('follow-head-art')), findsOneWidget);
      expect(SystemChrome.latestStyle?.statusBarIconBrightness, white ? Brightness.light : Brightness.dark);
    });
  }
}
