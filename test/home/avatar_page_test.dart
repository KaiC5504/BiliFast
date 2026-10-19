import 'dart:async';

import 'package:bili_core/api.dart' show HistoryItem, BiliError;
import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/route_observer.dart';
import 'package:bilifast/history/watch_history_page.dart';
import 'package:bilifast/home/avatar_page.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/settings/settings_page.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/video_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/fake_player.dart';
import 'fake_login_gate.dart';

/// 2026-10-19 21:00 local.
final _now = DateTime(2026, 10, 19, 21);

RecentVideo _video(int index, {int duration = 0, String? cover}) => RecentVideo(
  bvid: 'BV1v$index',
  cid: index,
  title: '视频 $index',
  part: '',
  page: 1,
  pageCount: 1,
  duration: duration,
  cover: cover,
);

/// A history row watched [ago] before [_now].
HistoryItem _watched(int aid, Duration ago, {int progress = 30, int duration = 300}) => HistoryItem(
  aid: aid,
  bvid: 'BV1h$aid',
  cid: 2000 + aid,
  title: '看过 $aid',
  cover: 'https://i0.hdslb.com/bfs/archive/cover$aid.jpg',
  ownerName: 'UP$aid',
  progress: progress,
  duration: duration,
  viewAt: _now.subtract(ago).millisecondsSinceEpoch ~/ 1000,
  device: 2,
  part: null,
);

void main() {
  late RecentStore recents;
  late PlaybackController controller;
  late FakeLoginGate gate;
  late FakePageApi api;
  late AppEnvironment environment;
  var clock = _now;

  /// Logged out (cookies Bilibili no longer takes) unless [loggedIn], or still unknown without [checkAccount]; the page's
  /// calls go to [api].
  Future<void> show(
    WidgetTester tester, {
    List<RecentVideo> opened = const [],
    bool loggedIn = false,
    List<HistoryItem> history = const [],
    bool settleFirst = true,
    bool fakeAccount = false,
    bool checkAccount = true,
    LoginGate? loginGate,
  }) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    final logger = Logger(session: 'test');
    final http = Canned.http(loggedIn: loggedIn);
    environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: http,
      logger: logger,
    );
    if (checkAccount) await environment.refreshAccount();
    if (fakeAccount) environment.useFakeAccount();
    recents = await RecentStore.load(null, logger: logger, now: () => clock);
    for (final video in opened.reversed) {
      recents.add(video);
    }
    clock = _now;
    controller = PlaybackController(
      client: environment.client,
      engine: FakeEngine(),
      player: FakePlayer(),
      clock: ManualClock(10000).clock,
      now: () => _now,
      startTimer: FakeTimers().start,
      logger: logger,
    );
    final playback = AppPlayback(() async => controller);
    addTearDown(playback.dispose);
    gate = FakeLoginGate();
    api = fakeAccount ? FakePageApi.demo(now: _now) : (FakePageApi()..historyItems = [...history]);
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: recents,
      loginGate: loginGate ?? gate,
      pageApi: api,
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [pageRoutes],
        builder: (context, child) => AppScope(services: services, child: child!),
        home: const Scaffold(body: Center(child: Text('首页'))),
      ),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    final pushed = navigator.push(MaterialPageRoute<void>(builder: (_) => const AvatarPage()));
    pushed.ignore();
    if (settleFirst) await settle(tester);
  }

  int historyCalls() => api.calls.where((call) => call.startsWith('history')).length;

  setUp(() => clock = _now);

  testWidgets('the bar, 最近 and the four shortcuts sit where 49 has them', (tester) async {
    await show(tester);
    Rect rect(String key) => tester.getRect(find.byKey(ValueKey(key)));
    expect(rect('avatar-back').center.dy, closeTo(84, 0.5));
    expect(rect('avatar-settings').center, offsetMoreOrLessEquals(const Offset(416, 84), epsilon: 0.5));
    expect(tester.getCenter(find.text('最近')).dx, closeTo(132.3, 0.5));
    final shortcuts = ['avatar-offline', 'avatar-history', 'avatar-favourites', 'avatar-later'];
    for (final (index, key) in shortcuts.indexed) {
      expect(rect(key).center.dx, closeTo(55 + 110 * index, 0.5), reason: key);
    }
    for (final label in ['离线缓存', '历史记录', '我的收藏', '稍后再看']) {
      expect(tester.getCenter(find.text(label)).dy, closeTo(168.2, 1), reason: label);
    }
    expect(find.text('看视频'), findsNothing);
    expect(find.text('听视频'), findsNothing);
    expect(find.text('开发者'), findsNothing);
    expect(find.text('登录'), findsNothing);
  });

  testWidgets('up to five recents in 49\'s rows: cover, duration, title, when, and ✕', (tester) async {
    clock = _now.subtract(const Duration(hours: 2));
    await show(tester, opened: [for (var i = 0; i < 7; i++) _video(i, duration: i == 0 ? 81593 : 133)]);
    expect(find.text('最近在看的视频'), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      expect(find.text('视频 $i'), findsOneWidget);
    }
    expect(find.text('视频 5'), findsNothing, reason: 'five at most');
    expect(find.text('22:39:53'), findsOneWidget);
    expect(find.text('2:13'), findsNWidgets(4));
    expect(find.text('2小时前播放'), findsNWidgets(5));
    final first = find.byKey(const ValueKey('avatar-recent-BV1v0#0'));
    final second = find.byKey(const ValueKey('avatar-recent-BV1v1#1'));
    expect(tester.getTopLeft(first).dy + 14, closeTo(252, 0.5), reason: "the first cover's top on 49");
    expect(tester.getTopLeft(second).dy - tester.getTopLeft(first).dy, 104);
    expect(
      tester.getCenter(find.byKey(const ValueKey('avatar-remove-BV1v0#0'))),
      offsetMoreOrLessEquals(const Offset(420, 322), epsilon: 0.5),
    );
  });

  testWidgets('the pink progress line runs along the cover as far as the part was watched', (tester) async {
    await show(tester, opened: [_video(0, duration: 100), _video(1, duration: 100)]);
    recents.recordProgress(bvid: 'BV1v0', cid: 0, seconds: 25);
    await settle(tester);
    final line = find.byKey(const ValueKey('avatar-recent-progress'));
    expect(line, findsOneWidget, reason: 'only the part with progress');
    expect(tester.getSize(line), const Size(34, 2));
  });

  testWidgets('✕ removes that one recent, from the page and the store', (tester) async {
    await show(tester, opened: [_video(0), _video(1), _video(2)]);
    await tester.tap(find.byKey(const ValueKey('avatar-remove-BV1v1#1')));
    await settle(tester);
    expect(find.text('视频 1'), findsNothing);
    expect([for (final item in recents.items) item.bvid], ['BV1v0', 'BV1v2']);
    expect(api.calls, isEmpty, reason: "logged out, the account's history is never asked");
  });

  testWidgets('with nothing opened yet the card says so, in the 字体 chosen', (tester) async {
    await show(tester);
    expect(find.text('还没有打开过视频'), findsOneWidget);
    expect(tester.widget<Text>(find.text('还没有打开过视频')).style?.fontFamily, BiliFonts.miSans);
    BiliFonts.family = null;
    addTearDown(() => BiliFonts.family = BiliFonts.miSans);
    recents.clear();
    await settle(tester);
    expect(tester.widget<Text>(find.text('还没有打开过视频')).style?.fontFamily, isNull);
  });

  testWidgets('a row opened again is stamped now and goes first, its progress kept', (tester) async {
    clock = _now.subtract(const Duration(hours: 3));
    await show(tester, opened: [_video(0), _video(1, duration: 100)]);
    recents.recordProgress(bvid: 'BV1v1', cid: 1, seconds: 40);
    await settle(tester);
    expect(find.text('3小时前播放'), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('avatar-recent-BV1v1#1')));
    await settle(tester, 20);
    expect([for (final item in recents.items) item.bvid], ['BV1v1', 'BV1v0']);
    final reopened = recents.items.first;
    expect(reopened.openedAt, _now.millisecondsSinceEpoch ~/ 1000);
    expect(reopened.progress, 40);
    expect(tester.widget<VideoPage>(find.byType(VideoPage)).route.bvid, 'BV1v1');
  });

  testWidgets('a row opens its video', (tester) async {
    await show(tester, opened: [_video(0)]);
    await tester.tap(find.byKey(const ValueKey('avatar-recent-BV1v0#0')));
    await settle(tester, 20);
    final route = tester.widget<VideoPage>(find.byType(VideoPage)).route;
    expect(route.bvid, 'BV1v0');
    expect(route.cid, 0);
  });

  testWidgets('全部 opens 最近打开', (tester) async {
    await show(tester, opened: [_video(0)]);
    await tester.tap(find.byKey(const ValueKey('avatar-all')));
    await settle(tester, 20);
    expect(find.text('最近打开'), findsOneWidget);
    expect(find.byKey(const ValueKey('recent-BV1v0#0')), findsOneWidget);
  });

  testWidgets('a part opened again from 最近打开 is stamped now and goes first', (tester) async {
    clock = _now.subtract(const Duration(hours: 3));
    await show(tester, opened: [_video(0), _video(1)]);
    await tester.tap(find.byKey(const ValueKey('avatar-all')));
    await settle(tester, 20);
    await tester.tap(find.byKey(const ValueKey('recent-BV1v1#1')));
    await settle(tester, 20);
    expect([for (final item in recents.items) item.bvid], ['BV1v1', 'BV1v0']);
    expect(recents.items.first.openedAt, _now.millisecondsSinceEpoch ~/ 1000);
    expect(tester.widget<VideoPage>(find.byType(VideoPage)).route.bvid, 'BV1v1');
  });

  testWidgets('⚙ opens 设置', (tester) async {
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('avatar-settings')));
    await settle(tester, 20);
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-font')), findsOneWidget);
  });

  testWidgets('历史记录 opens 历史记录; the other shortcuts say 即将推出', (tester) async {
    await show(tester);
    for (final key in ['avatar-offline', 'avatar-favourites', 'avatar-later']) {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pump();
      expect(find.text('即将推出'), findsOneWidget, reason: key);
      await settle(tester, 60);
    }
    expect(find.byType(WatchHistoryPage), findsNothing);
    await tester.tap(find.byKey(const ValueKey('avatar-history')));
    await settle(tester, 20);
    expect(find.byType(WatchHistoryPage), findsOneWidget);
    expect(gate.requests, 0);
  });

  testWidgets('back returns to where the page was opened from', (tester) async {
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('avatar-back')));
    await settle(tester, 20);
    expect(find.byType(AvatarPage), findsNothing);
    expect(find.text('首页'), findsOneWidget);
  });

  group('logged in', () {
    final watched = [
      _watched(1, const Duration(minutes: 5), progress: 25, duration: 100),
      _watched(2, const Duration(hours: 2), progress: -1, duration: 133),
      _watched(3, const Duration(hours: 26)),
      _watched(4, const Duration(days: 3)),
      _watched(5, const Duration(days: 4)),
      _watched(6, const Duration(days: 5)),
      _watched(7, const Duration(days: 6)),
    ];
    Finder row(HistoryItem item) => find.byKey(ValueKey('avatar-recent-${item.id}'));

    testWidgets("the rows are the newest five of the account's history: cover, duration, progress, title, when", (
      tester,
    ) async {
      await show(tester, loggedIn: true, history: watched, opened: [_video(0)]);
      expect(historyCalls(), 1);
      for (var i = 1; i <= 5; i++) {
        expect(find.text('看过 $i'), findsOneWidget);
      }
      expect(find.text('看过 6'), findsNothing, reason: 'five at most');
      expect(find.text('视频 0'), findsNothing, reason: '最近打开 is for logged out');
      expect(find.text('5分钟前播放'), findsOneWidget);
      expect(find.text('2小时前播放'), findsOneWidget);
      expect(find.text('昨天 19:00播放'), findsOneWidget);
      expect(find.text('10-16播放'), findsOneWidget);
      expect(find.text('1:40'), findsOneWidget);
      expect(find.text('2:13'), findsOneWidget);
      final cover = find.descendant(of: row(watched[0]), matching: find.byType(RemoteImage));
      expect(tester.widget<RemoteImage>(cover).url, 'https://i0.hdslb.com/bfs/archive/cover1.jpg');
      final lines = find.byKey(const ValueKey('avatar-recent-progress'));
      Size line(int index) => tester.getSize(find.descendant(of: row(watched[index]), matching: lines));
      expect(line(0), const Size(34, 2));
      expect(line(1), const Size(AvatarPageTheme.coverWidth, 2), reason: 'a finished one is full');
      expect(tester.getTopLeft(row(watched[0])).dy + 14, closeTo(252, 0.5), reason: "the first cover's top on 49");
      expect(tester.getTopLeft(row(watched[1])).dy - tester.getTopLeft(row(watched[0])).dy, 104);
    });

    testWidgets('the first load shows only the header; a failed one says so and a pull asks again', (tester) async {
      final hold = Completer<void>();
      await show(tester, loggedIn: true, history: watched, settleFirst: false);
      api.holds['history'] = hold;
      await settle(tester);
      expect(find.text('最近在看的视频'), findsOneWidget);
      expect(find.text('还没有看过视频'), findsNothing);
      expect(find.text('还没有打开过视频'), findsNothing);
      expect(find.textContaining('看过'), findsNothing);
      api
        ..failures['history'] = const BiliError.http(500)
        ..holds.clear();
      hold.complete();
      await settle(tester);
      expect(find.text('加载失败，下拉重试'), findsOneWidget);
      api.failures.clear();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
      await settle(tester, 30);
      expect(find.text('加载失败，下拉重试'), findsNothing);
      expect(find.text('看过 1'), findsOneWidget);
    });

    testWidgets('with no history the card says so', (tester) async {
      await show(tester, loggedIn: true);
      expect(find.text('还没有看过视频'), findsOneWidget);
    });

    testWidgets('coming back to the page asks again; a failure then keeps the rows', (tester) async {
      await show(tester, loggedIn: true, history: watched.sublist(1));
      expect(find.text('看过 1'), findsNothing);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      Future<void> visitAnotherPage() async {
        navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('别处')))).ignore();
        await settle(tester, 20);
        navigator.pop();
        await settle(tester, 20);
      }

      api.historyItems = [...watched];
      await visitAnotherPage();
      expect(historyCalls(), 2);
      expect(find.text('看过 1'), findsOneWidget);
      expect(find.text('看过 6'), findsNothing);

      api.failures['history'] = const BiliError.http(500);
      await visitAnotherPage();
      expect(historyCalls(), 3);
      expect(find.text('看过 1'), findsOneWidget);
      expect(find.text('加载失败，下拉重试'), findsNothing);
    });

    testWidgets('a row opens the video where it was left, as 历史记录 does', (tester) async {
      await show(tester, loggedIn: true, history: watched);
      await tester.tap(row(watched[0]));
      await settle(tester, 20);
      final route = tester.widget<VideoPage>(find.byType(VideoPage)).route;
      expect(route.bvid, 'BV1h1');
      expect(route.cid, 2001);
      expect(route.start, 25);
      expect(route.title, '看过 1');
    });

    testWidgets("✕ deletes from the account's history at once; a failed delete comes back with a toast", (
      tester,
    ) async {
      await show(tester, loggedIn: true, history: watched);
      final hold = Completer<void>();
      api.holds['deleteHistory'] = hold;
      await tester.tap(find.byKey(ValueKey('avatar-remove-${watched[1].id}')));
      await tester.pump();
      expect(api.calls.last, 'deleteHistory aid=2');
      expect(find.text('看过 2'), findsNothing, reason: 'gone before the server answers');
      expect(find.text('看过 6'), findsOneWidget, reason: 'the next one moves up');
      api.failures['deleteHistory'] = const BiliError.http(500);
      hold.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('删除失败，请稍后重试'), findsOneWidget);
      await settle(tester, 60);
      expect(find.text('看过 2'), findsOneWidget);
      expect(find.text('看过 6'), findsNothing);

      api
        ..failures.clear()
        ..holds.clear();
      await tester.tap(find.byKey(ValueKey('avatar-remove-${watched[1].id}')));
      await settle(tester);
      expect(find.text('看过 2'), findsNothing);
      expect([for (final item in api.historyItems) item.aid], isNot(contains(2)));
    });

    testWidgets('全部 opens 历史记录', (tester) async {
      await show(tester, loggedIn: true, history: watched, opened: [_video(0)]);
      await tester.tap(find.byKey(const ValueKey('avatar-all')));
      await settle(tester, 20);
      expect(find.byType(WatchHistoryPage), findsOneWidget);
      expect(find.text('最近打开'), findsNothing);
    });

    testWidgets("--fake-account shows the fake's history", (tester) async {
      await show(tester, fakeAccount: true, settleFirst: false);
      await settle(tester, 20);
      expect(find.text('一口气看完系列：三分钟带你了解城市夜景延时摄影的全部流程'), findsOneWidget);
      expect(find.text('3小时前播放'), findsOneWidget);
      expect(find.byKey(const ValueKey('avatar-recent-progress')), findsNWidgets(AvatarPageTheme.shown));
    });
  });

  testWidgets('every control is a button VoiceOver can press', (tester) async {
    final semantics = tester.ensureSemantics();
    await show(tester, opened: [_video(0)]);
    for (final label in ['返回', '设置', '离线缓存', '历史记录', '我的收藏', '稍后再看', '全部', '视频 0', '移除']) {
      final nodes = find.semantics.byLabel(label).evaluate();
      expect(nodes, hasLength(1), reason: label);
      expect(nodes.single.getSemanticsData().hasAction(SemanticsAction.tap), isTrue, reason: label);
    }
    semantics.dispose();
  });

  group('account changes while the page is open', () {
    final watched = [_watched(1, const Duration(minutes: 5)), _watched(2, const Duration(hours: 2))];
    const expired = BiliError.api(code: -101, message: '账号未登录');

    testWidgets('logged out at open, a login turns the card into the account history', (tester) async {
      await show(tester, history: watched, opened: [_video(0)]);
      expect(find.text('视频 0'), findsOneWidget);
      expect(historyCalls(), 0);
      environment.useFakeAccount();
      await settle(tester);
      expect(historyCalls(), 1);
      expect(find.text('看过 1'), findsOneWidget);
      expect(find.text('视频 0'), findsNothing);
    });

    testWidgets('a logout turns it back into 最近打开', (tester) async {
      await show(tester, loggedIn: true, history: watched, opened: [_video(0)]);
      expect(find.text('看过 1'), findsOneWidget);
      try {
        await environment.logout();
      } on LogoutIncomplete catch (_) {}
      await settle(tester);
      expect(find.text('看过 1'), findsNothing);
      expect(find.text('视频 0'), findsOneWidget);
    });

    testWidgets("logged out then in again, the previous account's rows are not shown when the new list fails", (
      tester,
    ) async {
      await show(tester, loggedIn: true, history: watched, opened: [_video(0)]);
      expect(find.text('看过 1'), findsOneWidget);
      try {
        await environment.logout();
      } on LogoutIncomplete catch (_) {}
      await settle(tester);
      api.failures['history'] = const BiliError.http(500);
      environment.useFakeAccount();
      await settle(tester);
      expect(find.text('看过 1'), findsNothing, reason: "the last account's history");
      expect(find.text('加载失败，下拉重试'), findsOneWidget);
    });

    testWidgets('a logout and a login under 设置 ask for the history once, as 设置 closes', (tester) async {
      await show(tester, loggedIn: true, history: watched);
      expect(historyCalls(), 1);
      await tester.tap(find.byKey(const ValueKey('avatar-settings')));
      await settle(tester, 20);
      try {
        await environment.logout();
      } on LogoutIncomplete catch (_) {}
      environment.useFakeAccount();
      await settle(tester);
      expect(historyCalls(), 1, reason: 'covered by 设置');
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await settle(tester, 20);
      expect(historyCalls(), 2);
      expect(find.text('看过 1'), findsOneWidget);
    });

    testWidgets('✕ deletes while the account is still being checked', (tester) async {
      await show(tester, checkAccount: false, history: watched);
      expect(environment.account, isA<AccountUnknown>());
      await tester.tap(find.byKey(ValueKey('avatar-remove-${watched[1].id}')));
      await settle(tester);
      expect(api.calls.last, 'deleteHistory aid=2');
      expect(find.text('看过 2'), findsNothing);
    });

    testWidgets('a -101 on the load asks for a login in the card; the login page opens only when pressed', (
      tester,
    ) async {
      await show(tester, loggedIn: true, history: watched, opened: [_video(0)], settleFirst: false);
      api.failures['history'] = expired;
      await settle(tester);
      expect(find.text('登录后查看历史记录'), findsOneWidget);
      expect(find.text('视频 0'), findsNothing, reason: 'not 最近打开 under the history header');
      expect(gate.requests, 0);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('别处')))).ignore();
      await settle(tester, 20);
      navigator.pop();
      await settle(tester, 20);
      expect(historyCalls(), 1, reason: 'no login since, so nothing to ask');

      api.failures.clear();
      gate.answer = true;
      await tester.tap(find.byKey(const ValueKey('avatar-login')));
      await settle(tester);
      expect(gate.requests, 1);
      expect(historyCalls(), 2);
      expect(find.text('看过 1'), findsOneWidget);
    });

    testWidgets('全部 while a login is needed goes through the login gate, then opens 历史记录', (tester) async {
      await show(tester, loggedIn: true, history: watched, settleFirst: false);
      api.failures['history'] = expired;
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('avatar-all')));
      await settle(tester, 20);
      expect(gate.requests, 1);
      expect(find.byType(WatchHistoryPage), findsNothing, reason: 'the login was cancelled');
      api.failures.clear();
      gate.answer = true;
      await tester.tap(find.byKey(const ValueKey('avatar-all')));
      await settle(tester, 20);
      expect(gate.requests, 2);
      expect(find.byType(WatchHistoryPage), findsOneWidget);
    });

    testWidgets('a -101 on ✕ turns the card to its login state, with no toast', (tester) async {
      await show(tester, loggedIn: true, history: watched);
      api.failures['deleteHistory'] = expired;
      await tester.tap(find.byKey(ValueKey('avatar-remove-${watched[1].id}')));
      await settle(tester);
      expect(find.text('登录后查看历史记录'), findsOneWidget);
      expect(find.text('看过 1'), findsNothing);
      expect(find.text('删除失败，请稍后重试'), findsNothing);
      expect(gate.requests, 0);
    });

    testWidgets('after a -101, a login through the login page asks for the history once', (tester) async {
      final login = _PageGate();
      await show(tester, loggedIn: true, history: watched, settleFirst: false, loginGate: login);
      api.failures['history'] = expired;
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('avatar-login')));
      await settle(tester, 20);
      expect(find.text('登录页'), findsOneWidget);
      api.failures.clear();
      expect(await environment.didLogin(Canned.cookies), isTrue);
      await settle(tester);
      expect(historyCalls(), 1, reason: 'covered by the login page');
      login.close(loggedIn: true);
      await settle(tester, 20);
      expect(historyCalls(), 2);
      expect(find.text('看过 1'), findsOneWidget);
    });
  });
}

/// Pushes a stand-in login page and answers when the test closes it.
final class _PageGate implements LoginGate {
  late NavigatorState _navigator;

  @override
  Future<bool> request(BuildContext context) {
    _navigator = Navigator.of(context);
    return _navigator
        .push<bool>(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('登录页'))))
        .then((loggedIn) => loggedIn ?? false);
  }

  void close({required bool loggedIn}) => _navigator.pop(loggedIn);
}
Future<void> settle(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
