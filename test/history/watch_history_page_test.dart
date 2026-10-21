import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/history/history_model.dart';
import 'package:bilifast/history/watch_history_page.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/shared/loading_tv.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/system_font.dart';
import '../video/mixed_lines.dart';
import 'history_fakes.dart';

void main() {
  late FakePageApi api;
  late bool loggedIn;
  late List<VideoRoute> opened;
  late List<Uri> shared;
  late FakeLoginGate gate;
  final navigator = GlobalKey<NavigatorState>();

  setUp(() {
    api = FakePageApi();
    loggedIn = true;
    opened = [];
    shared = [];
    gate = FakeLoginGate(onRequest: () => loggedIn = true);
  });

  final today = [
    historyItem(1, viewAt: wall(19, 3, 2), progress: 2, duration: 447, title: '今天看的一'),
    historyItem(2, viewAt: wall(19, 3, 1), progress: -1, duration: 193, device: 1, title: '今天看完的'),
  ];
  final yesterday = [historyItem(3, viewAt: wall(18, 22, 33), progress: 158, duration: 212, title: '昨天看的')];
  final older = [historyItem(4, viewAt: wall(17, 23, 10), progress: 6, duration: 13230, device: 1, title: '更早看的')];

  /// The page pushed over a home screen, at the iPhone's size.
  Future<HistoryModel> show(WidgetTester tester, {List<HistoryItem>? items, bool settle = true}) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    api.historyItems = items ?? [...today, ...yesterday, ...older];
    final model = HistoryModel(
      api: api,
      isLoggedIn: () => loggedIn,
      now: () => wallTime(19, 9, 8),
      utcOffset: testOffset,
      logger: Logger(session: 'test'),
    );
    addTearDown(model.dispose);
    await tester.pumpWidget(MaterialApp(navigatorKey: navigator, home: const Text('home')));
    unawaited(
      navigator.currentState!.push(
        CupertinoPageRoute<void>(
          builder: (_) => WatchHistoryPage(
            model: model,
            loginGate: gate,
            share: (link) async {
              shared.add(link);
              return true;
            },
            open: (context, route) => opened.add(route),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // The loading TV never settles; this outlasts the push.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
    return model;
  }

  Finder row(int aid) =>
      find.byKey(ValueKey('history-BV1test$aid@${api.historyItems.firstWhere((item) => item.aid == aid).viewAt}'));

  Future<void> openMenu(WidgetTester tester, HistoryItem item) async {
    await tester.tap(find.byKey(ValueKey('history-more-${item.id}')));
    await tester.pumpAndSettle();
  }

  testWidgets('draws 今天, 昨天 and 更早 under the bar, without the search, menu or tab row', (tester) async {
    await show(tester);
    expect(find.text('历史记录'), findsOneWidget);
    for (final title in ['今天', '昨天', '更早']) {
      expect(find.text(title), findsOneWidget);
    }
    for (final tab in ['全部', '视频', '直播', '专栏', '商品', '展演']) {
      expect(find.text(tab), findsNothing);
    }
    expect(find.text('00:02/07:27'), findsOneWidget);
    expect(find.text('已看完'), findsOneWidget);
    expect(find.text('00:06/03:40:30'), findsOneWidget);
    expect(find.text('2026年10月19日 03:02'), findsOneWidget);
    expect(find.byKey(const ValueKey('history-device-phone')), findsNWidgets(2));
    expect(find.byKey(const ValueKey('history-device-pc')), findsNWidgets(2));
    expect(find.text('没有更多了'), findsOneWidget);
  });

  testWidgets('under the system font a row\'s mixed title, uploader and time sit on the Chinese line', (tester) async {
    await useSystemFont(tester);
    await show(tester, items: [historyItem(1, viewAt: wall(19, 3, 2), title: mixedLines)]);
    expectOnChineseLine(tester, find.text(mixedLines));
    expectOnChineseLine(tester, find.text('UP1'));
    expectOnChineseLine(tester, find.text('2026年10月19日 03:02'));
  });

  testWidgets('a section header stays pinned while its rows scroll under it', (tester) async {
    await show(tester, items: historyRows(8, from: wall(19, 9, 0)));
    final top = tester.getTopLeft(find.text('今天')).dy;
    await tester.drag(find.byKey(const ValueKey('history-list')), const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('今天')).dy, top);
    expect(tester.getTopLeft(row(1)).dy, lessThan(top), reason: 'the first row went up under the header');
  });

  testWidgets('a tap opens the video where it was left, a finished one from the start', (tester) async {
    await show(tester);
    await tester.tap(row(3));
    expect(opened.single.bvid, 'BV1test3');
    expect(opened.single.cid, 1003);
    expect(opened.single.start, 158);
    await tester.tap(row(2));
    expect(opened.last.start, 0);
  });

  testWidgets('⋮ opens the sheet; back closes it before leaving the page', (tester) async {
    await show(tester);
    await openMenu(tester, today[0]);
    expect(find.byKey(const ValueKey('history-sheet')), findsOneWidget);
    expect(find.text('分享'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-sheet')), findsNothing);
    expect(find.text('历史记录'), findsOneWidget, reason: 'the page is still there');

    await openMenu(tester, today[0]);
    await tester.tap(find.byKey(const ValueKey('history-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-sheet')), findsNothing);

    await openMenu(tester, today[0]);
    await tester.tapAt(const Offset(220, 300));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-sheet')), findsNothing, reason: 'a tap on the dim closes it');
    expect(opened, isEmpty, reason: 'and reaches no row');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('删除 takes the row off and deletes it on the server', (tester) async {
    await show(tester);
    await openMenu(tester, yesterday[0]);
    await tester.tap(find.byKey(const ValueKey('history-delete')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-sheet')), findsNothing);
    expect(find.text('昨天看的'), findsNothing);
    expect(find.text('昨天'), findsNothing, reason: 'its section had no other row');
    expect(api.calls.last, 'deleteHistory aid=3');
  });

  testWidgets('a failed 删除 brings the row back with a toast', (tester) async {
    await show(tester);
    api.failures['deleteHistory'] = const BiliError.http(500);
    final hold = Completer<void>();
    api.holds['deleteHistory'] = hold;
    await openMenu(tester, today[0]);
    await tester.tap(find.byKey(const ValueKey('history-delete')));
    await tester.pumpAndSettle();
    expect(find.text('今天看的一'), findsNothing);

    hold.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('今天看的一'), findsOneWidget);
    expect(find.text(HistoryModel.deleteFailed), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('分享 hands the video link to the system share sheet', (tester) async {
    await show(tester);
    await openMenu(tester, older[0]);
    await tester.tap(find.byKey(const ValueKey('history-share')));
    await tester.pumpAndSettle();
    expect(shared, [Uri.parse('https://www.bilibili.com/video/BV1test4')]);
    expect(find.byKey(const ValueKey('history-sheet')), findsNothing);
  });

  testWidgets('logged out asks for a login, then loads the list', (tester) async {
    loggedIn = false;
    await show(tester);
    expect(find.text('登录后查看历史记录'), findsOneWidget);
    expect(api.calls, isEmpty);

    await tester.tap(find.byKey(const ValueKey('history-login')));
    await tester.pumpAndSettle();
    expect(gate.requests, 1);
    expect(find.text('今天看的一'), findsOneWidget);
  });

  testWidgets('a login that is given up keeps the login state', (tester) async {
    loggedIn = false;
    gate
      ..answer = false
      ..onRequest = null;
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('history-login')));
    await tester.pumpAndSettle();
    expect(find.text('登录后查看历史记录'), findsOneWidget);
    expect(api.calls, isEmpty);
  });

  testWidgets('-101 from Bilibili shows the login state', (tester) async {
    api.failures['history'] = const BiliError.api(code: -101, message: '账号未登录');
    await show(tester);
    expect(find.byKey(const ValueKey('history-logged-out')), findsOneWidget);
  });

  testWidgets('an empty history says so', (tester) async {
    await show(tester, items: const []);
    expect(find.text('还没有看过视频'), findsOneWidget);
  });

  testWidgets('a failed first page offers 重试', (tester) async {
    api.failures['history'] = const BiliError.http(502);
    await show(tester);
    expect(find.byKey(const ValueKey('history-failed')), findsOneWidget);
    api.failures.remove('history');
    await tester.tap(find.byKey(const ValueKey('history-retry')));
    await tester.pumpAndSettle();
    expect(find.text('今天看的一'), findsOneWidget);
  });

  testWidgets('the first page loads under the TV, 297.33 below the bar as in 搜索', (tester) async {
    final hold = Completer<void>();
    api.holds['history'] = hold;
    await show(tester, settle: false);
    final state = find.byKey(const ValueKey('history-loading'));
    expect(tester.widget(state), isA<LoadingTvState>());
    expect(find.text(LoadingTvState.message), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    final barBottom = 62 + HistoryTheme.barHeight + HistoryTheme.barHairline;
    final tv = find.byType(LoadingTv);
    expect(tester.getTopLeft(tv).dy - barBottom, closeTo(892 / 3, 0.01));
    expect(tester.getCenter(tv).dx, closeTo(220, 0.01));

    hold.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LoadingTv), findsNothing);
    expect(find.text('今天看的一'), findsOneWidget);
  });

  testWidgets('a pull shows the TV held on its first face, cycling once it refreshes', (tester) async {
    await show(tester);
    final hold = Completer<void>();
    api.holds['history'] = hold;
    final list = find.byKey(const ValueKey('history-list'));
    final gesture = await tester.startGesture(tester.getCenter(list));
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    expect(tester.widget<LoadingTv>(find.byType(LoadingTv)).playing, isFalse, reason: 'short of the trigger');
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.calls.last, 'history after=0');
    expect(tester.widget<LoadingTv>(find.byType(LoadingTv)).playing, isTrue);

    hold.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LoadingTv), findsNothing);
  });

  testWidgets('pull to refresh keeps the rows while it reloads', (tester) async {
    await show(tester);
    final hold = Completer<void>();
    api.holds['history'] = hold;
    api.historyItems = [historyItem(9, viewAt: wall(19, 9, 0), title: '刚看的'), ...api.historyItems];
    await tester.fling(find.byKey(const ValueKey('history-list')), const Offset(0, 300), 1500);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.calls.last, 'history after=0');
    expect(find.text('今天看的一'), findsOneWidget, reason: 'the rows stay while it reloads');
    expect(find.text('刚看的'), findsNothing);

    hold.complete();
    await tester.pumpAndSettle();
    expect(find.text('刚看的'), findsOneWidget);
  });

  testWidgets('scrolling near the end loads the next page', (tester) async {
    final rows = historyRows(30, from: wall(19, 9, 0));
    await show(tester, items: rows);
    expect(api.calls, ['history after=0']);
    for (var i = 0; i < 4; i++) {
      await tester.drag(find.byKey(const ValueKey('history-list')), const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    expect(api.calls, contains('history after=20'));
    await tester.dragUntilVisible(find.text('视频30'), find.byKey(const ValueKey('history-list')), const Offset(0, -300));
    expect(find.text('视频30'), findsOneWidget);
  });

  testWidgets('the page and its sheet draw regular words, the title alone bold', (tester) async {
    await show(tester);
    FontWeight? weight(Finder text) => tester.renderObject<RenderParagraph>(text).text.style?.fontWeight;
    expect(weight(find.text('今天')), FontWeight.w400);
    expect(weight(find.text('今天看的一')), FontWeight.w400);
    expect(weight(find.text('UP1')), FontWeight.w400);
    expect(weight(find.text('历史记录')), FontWeight.w600);
    await openMenu(tester, today[0]);
    expect(weight(find.text('删除')), FontWeight.w400);
    expect(weight(find.text('分享链接')), FontWeight.w400);
  });

  testWidgets('the row, ⋮, back and the sheet answer a VoiceOver press', (tester) async {
    final semantics = tester.ensureSemantics();
    await show(tester);
    const rowLabel = '今天看的一，UP1，00:02/07:27';
    for (final label in ['返回', rowLabel]) {
      final node = find.semantics.byLabel(label).evaluate().single;
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue, reason: label);
    }
    tester.semantics.tap(find.semantics.byLabel(rowLabel));
    await tester.pump();
    expect(opened.single.bvid, 'BV1test1');

    final more = find.semantics.byLabel('更多操作');
    expect(more.evaluate(), hasLength(4));
    expect(more.evaluate().first.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    tester.semantics.tap(find.semantics.byLabel('更多操作').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-sheet')), findsOneWidget);
    expect(find.semantics.byLabel(rowLabel).evaluate(), isEmpty, reason: 'the sheet hides the rows from VoiceOver');
    for (final label in ['分享链接', '删除', '取消']) {
      final node = find.semantics.byLabel(label).evaluate().single;
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue, reason: label);
    }
    tester.semantics.tap(find.semantics.byLabel('取消'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-sheet')), findsNothing);
    expect(find.semantics.byLabel(rowLabel).evaluate(), hasLength(1));

    tester.semantics.tap(find.semantics.byLabel('更多操作').first);
    await tester.pumpAndSettle();
    tester.semantics.tap(find.semantics.byLabel('分享链接'));
    await tester.pumpAndSettle();
    expect(shared, [Uri.parse('https://www.bilibili.com/video/BV1test1')]);

    tester.semantics.tap(find.semantics.byLabel('更多操作').first);
    await tester.pumpAndSettle();
    tester.semantics.tap(find.semantics.byLabel('删除'));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'deleteHistory aid=1');
    semantics.dispose();
  });

  testWidgets('登录 answers a VoiceOver press', (tester) async {
    final semantics = tester.ensureSemantics();
    loggedIn = false;
    await show(tester);
    tester.semantics.tap(find.semantics.byLabel('登录'));
    await tester.pumpAndSettle();
    expect(gate.requests, 1);
    expect(find.text('今天看的一'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a failed first page retries on a VoiceOver press', (tester) async {
    final semantics = tester.ensureSemantics();
    api.failures['history'] = const BiliError.http(502);
    await show(tester);
    api.failures.remove('history');
    tester.semantics.tap(find.semantics.byLabel('重试'));
    await tester.pumpAndSettle();
    expect(find.text('今天看的一'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a failed next page retries from the footer on a VoiceOver press', (tester) async {
    final semantics = tester.ensureSemantics();
    api.historyPageSize = 2;
    final model = await show(tester);
    api.failures['history'] = const BiliError.http(502);
    await model.loadMore();
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('history-footer-retry')),
      find.byKey(const ValueKey('history-list')),
      const Offset(0, -300),
    );
    api.failures.remove('history');
    final footer = find.semantics.byLabel('加载失败，点击重试');
    expect(footer.evaluate().single.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    tester.semantics.tap(footer);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-footer-retry')), findsNothing);
    expect(model.items, hasLength(4));
    semantics.dispose();
  });

  testWidgets('the 登录 pill hugs its words, centred', (tester) async {
    loggedIn = false;
    await show(tester);
    final pill = tester.getRect(find.byKey(const ValueKey('history-login')));
    final words = tester.getSize(find.text('登录')).width;
    expect(pill.width, closeTo(words + 2 * 36, 0.5));
    expect(pill.center.dx, closeTo(220, 0.5));
  });

  testWidgets('logging in from the page loads the first page once', (tester) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final logger = Logger(session: 'test');
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies({'buvid3': 'b3', 'buvid4': 'b4'})),
      http: Canned.http(loggedIn: false),
      logger: logger,
    );
    await environment.refreshAccount();
    expect(environment.account, isA<LoggedOut>());
    api.historyItems = [...today];
    final playback = AppPlayback(() => Completer<PlaybackController>().future);
    addTearDown(playback.dispose);
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      pageApi: api,
      loginGate: gate..onRequest = environment.useFakeAccount,
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => AppScope(services: services, child: child!),
        home: const Text('home'),
      ),
    );
    unawaited(navigator.currentState!.push(CupertinoPageRoute<void>(builder: (_) => const WatchHistoryPage())));
    await tester.pumpAndSettle();
    expect(find.text('登录后查看历史记录'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('history-login')));
    await tester.pumpAndSettle();
    expect(find.text('今天看的一'), findsOneWidget);
    expect(api.calls.where((call) => call == 'history after=0'), hasLength(1));
  });

  testWidgets('with no Material above it, the page names the system font fallback itself', (tester) async {
    await expectSystemFallback(tester, () => show(tester), find.text('今天看的一'));
  });
}
