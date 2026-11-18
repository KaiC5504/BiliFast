import 'dart:async';
import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/dynamic/fake_dynamic_api.dart';
import 'package:bilifast/home/feed_card.dart';
import 'package:bilifast/home/home_page.dart';
import 'package:bilifast/home/home_tab_bar.dart';
import 'package:bilifast/home/main_shell.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/home/tab_bar_icons.dart';
import 'package:bilifast/me/fake_me_api.dart';
import 'package:bilifast/me/me_page.dart';
import 'package:bilifast/message/fake_message_api.dart';
import 'package:bilifast/message/message_model.dart';
import 'package:bilifast/message/message_page.dart';
import 'package:bilifast/search/fake_search_api.dart';
import 'package:bilifast/shared/loading_tv.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../dynamic/follow_tab/follow_fixtures.dart' show BadgeServices, RecordingFollowBadge, faces, posts;
import '../playback/fakes.dart';
import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import '../video/mixed_lines.dart';
import 'fake_login_gate.dart';
import 'feed_fakes.dart';

const _screen = ValueKey('screen');

void main() {
  late FeedHttp http;
  late FakeDynamicApi dynamicApi;

  /// 关注's count in the shell [show] last built.
  late RecordingFollowBadge badge;

  setUp(() {
    http = FeedHttp()..pages[1] = [for (var i = 0; i < 20; i++) feedItem('BV1c$i')];
    dynamicApi = FakeDynamicApi(posts: posts(30), upList: faces);
  });

  /// The shell at [size] (440×956 unless given) over a 34 pt home indicator; [phone] makes it KaiC's iPhone at 3×
  /// under the system font. [messages] builds 消息's model in place of the app's; 关注's count is [badge].
  Future<void> show(
    WidgetTester tester, {
    bool phone = false,
    Size size = const Size(440, 956),
    MessageModel Function(AppEnvironment environment)? messages,
  }) async {
    if (phone) {
      final saved = BiliFonts.family;
      addTearDown(() => BiliFonts.family = saved);
      await tester.runAsync(loadSystemFontStandIns);
      showAsPhone(tester);
    } else {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1
        ..padding = const FakeViewPadding(bottom: 34)
        ..viewPadding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.reset);
    }
    final logger = Logger(session: 'test');
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: http,
      logger: logger,
    );
    await environment.refreshAccount();
    final playback = AppPlayback(() => throw StateError('no playback here'));
    addTearDown(playback.dispose);
    badge = RecordingFollowBadge(environment);
    addTearDown(badge.dispose);
    final services = BadgeServices(
      badge: badge,
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      searchApi: FakeSearchApi(defaultWord: '崩铁新版本即将上线'),
      meApi: FakeMeApi.demo(),
      dynamicApi: dynamicApi,
      loginGate: FakeLoginGate(),
      messageApi: FakeMessageApi(),
      messages: messages?.call(environment),
    );
    if (phone) BiliFonts.family = BiliFonts.system;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => RepaintBoundary(
          key: _screen,
          child: AppScope(services: services, child: child!),
        ),
        home: MainShell(developerPage: (context) => const Text('开发者页面')),
      ),
    );
  }

  /// Lets requests answer and frames run without waiting on the loading cards' endless sweep.
  Future<void> settle(WidgetTester tester, [int frames = 10]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Finder slot(HomeTab tab) => find.byKey(ValueKey('home-tab-${tab.name}'));

  Future<void> tapTab(WidgetTester tester, HomeTab tab) async {
    await tester.tap(slot(tab));
    await tester.pump();
  }

  ScrollPosition feedScroll(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(of: find.byKey(const ValueKey('feed')), matching: find.byType(Scrollable)).first,
      )
      .position;

  bool meActive(WidgetTester tester) => tester.widget<MePage>(find.byType(MePage, skipOffstage: false)).active;

  void expectSelected(WidgetTester tester, HomeTab selected) {
    for (final tab in HomeTab.values) {
      final on = tab == selected;
      expect(
        tester.getSemantics(slot(tab)),
        isSemantics(label: tab.label, isButton: true, hasTapAction: true, hasSelectedState: true, isSelected: on),
      );
      final icon = find.descendant(of: slot(tab), matching: find.byType(HomeTabIcon));
      expect(tester.widget<HomeTabIcon>(icon).selected, on, reason: tab.label);
      if (tab == HomeTab.post) continue;
      final glyph = tester.widget<CustomPaint>(find.descendant(of: icon, matching: find.byType(CustomPaint)));
      final painter = glyph.painter! as HomeTabGlyphPainter;
      expect(painter.selected, on, reason: tab.label);
      expect(painter.color, on ? TabIconTheme.selectedInk : TabIconTheme.ink, reason: tab.label);
      final label = tester.widget<Text>(find.descendant(of: slot(tab), matching: find.text(tab.label)));
      expect(label.style?.color, on ? HomeTabBarTheme.selected : HomeTabBarTheme.label, reason: tab.label);
    }
  }

  testWidgets('five slots across the bottom over the home indicator, 首页 selected, the pages ending at the bar', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await show(tester);
    await settle(tester);
    final bar = tester.getRect(find.byType(HomeTabBar));
    expect(bar.bottom, 956);
    expect(bar.height, HomeTabBarTheme.height + 34);
    expect(tester.getRect(find.byKey(const ValueKey('feed'))).bottom, bar.top);
    for (final (i, tab) in HomeTab.values.indexed) {
      expect(tester.getRect(slot(tab)), Rect.fromLTWH(88.0 * i, bar.top, 88, HomeTabBarTheme.height));
      if (tab == HomeTab.post) {
        expect(find.text(tab.label), findsNothing, reason: 'the + has no label');
        continue;
      }
      final label = find.text(tab.label);
      expect(tester.getCenter(label).dx, 44 + 88.0 * i);
      expect(tester.getTopLeft(label).dy, greaterThan(bar.top + 30));
    }
    expectSelected(tester, HomeTab.home);

    await tapTab(tester, HomeTab.mine);
    await settle(tester);
    expectSelected(tester, HomeTab.mine);
    expect(tester.getRect(find.byType(MePage)), Rect.fromLTRB(0, 0, 440, bar.top));
    expect(
      MediaQuery.paddingOf(tester.element(find.byType(MePage))).bottom,
      0,
      reason: 'the bar takes the home indicator',
    );
    semantics.dispose();
  });

  testWidgets('switching keeps both pages alive: 推荐 comes back where it was, with its cards, unrefreshed', (
    tester,
  ) async {
    await show(tester);
    await settle(tester);
    final home = tester.state(find.byType(HomePage));
    final me = tester.state(find.byType(MePage, skipOffstage: false));
    await tester.drag(find.byKey(const ValueKey('feed')), const Offset(0, -1500));
    await settle(tester, 20);
    final at = feedScroll(tester).pixels;
    expect(at, greaterThan(1000));
    final asked = List.of(http.asked);
    Set<String> cards() => {
      for (final card in find.byWidgetPredicate((widget) => widget.key is ValueKey<String>).evaluate())
        if ((card.widget.key! as ValueKey<String>).value case final key when key.startsWith('feed-card-BV')) key,
    };
    final shown = cards();
    expect(shown, isNotEmpty);

    await tapTab(tester, HomeTab.mine);
    await settle(tester);
    expect(find.byType(HomePage), findsNothing, reason: 'offstage');
    expect(find.byType(MePage), findsOneWidget);
    await tapTab(tester, HomeTab.home);
    await settle(tester, 20);

    expect(tester.state(find.byType(HomePage)), same(home));
    expect(tester.state(find.byType(MePage, skipOffstage: false)), same(me));
    expect(feedScroll(tester).pixels, at);
    expect(cards(), shown);
    expect(find.byKey(const ValueKey('feed-reload')), findsNothing);
    expect(http.asked, asked, reason: 'no refresh');
  });

  testWidgets('首页 on 首页 refreshes 推荐; 首页 from 我的 only shows it again', (tester) async {
    await show(tester);
    await settle(tester, 40);
    final asked = List.of(http.asked);

    await tapTab(tester, HomeTab.mine);
    await settle(tester);
    await tapTab(tester, HomeTab.home);
    await settle(tester, 20);
    expect(http.asked, asked);

    await tapTab(tester, HomeTab.home);
    await settle(tester, 20);
    expect(http.asked, [...asked, 1]);
    await settle(tester, 40);
  });

  testWidgets("MePage is active only while 我的 is the tab; 我的 again changes nothing; the status bar stays dark", (
    tester,
  ) async {
    await show(tester);
    await settle(tester);
    expect(meActive(tester), isFalse);
    expect(tester.widget<MePage>(find.byType(MePage, skipOffstage: false)).developerPage, isNotNull);

    await tapTab(tester, HomeTab.mine);
    await settle(tester);
    expect(meActive(tester), isTrue);
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.dark);
    final me = tester.state(find.byType(MePage));

    await tapTab(tester, HomeTab.mine);
    await settle(tester);
    expect(meActive(tester), isTrue);
    expect(tester.state(find.byType(MePage)), same(me));
    expect(find.byType(HomePage), findsNothing);
    expectSelected(tester, HomeTab.mine);

    await tapTab(tester, HomeTab.home);
    await settle(tester);
    expect(meActive(tester), isFalse);
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.dark);
  });

  testWidgets('消息 shows its page, active only while shown; 消息 again asks it to reload', (tester) async {
    late _Messages model;
    await show(tester, messages: (environment) => model = _Messages(environment));
    await settle(tester);
    expect(model.starts, 1, reason: 'the shell starts the counts once');
    bool messagesActive() => tester.widget<MessagePage>(find.byType(MessagePage, skipOffstage: false)).active;
    expect(messagesActive(), isFalse);

    await tapTab(tester, HomeTab.messages);
    await settle(tester);
    expectSelected(tester, HomeTab.messages);
    expect(messagesActive(), isTrue);
    expect(find.byType(MessagePage), findsOneWidget);
    expect(find.byType(HomePage), findsNothing, reason: 'offstage');
    expect(model.refreshes, 1);

    await tapTab(tester, HomeTab.messages);
    await settle(tester);
    expect(model.refreshes, 2, reason: 'reloaded');

    await tapTab(tester, HomeTab.home);
    await settle(tester);
    expect(messagesActive(), isFalse);
    expect(model.starts, 1);
  });

  testWidgets("the bar's 消息 count follows the model's badge: none at 0", (tester) async {
    late _Messages model;
    await show(tester, messages: (environment) => model = _Messages(environment));
    await settle(tester);
    final count = find.byKey(const ValueKey('home-tab-messages-count'));
    expect(count, findsNothing);

    model.setBadge(7);
    await tester.pump();
    expect(find.descendant(of: count, matching: find.text('7')), findsOneWidget);

    model.setBadge(120);
    await tester.pump();
    expect(find.descendant(of: count, matching: find.text('99+')), findsOneWidget);

    model.setBadge(0);
    await tester.pump();
    expect(count, findsNothing);
  });

  testWidgets('a show request (a tapped 私信 notification) switches to 消息 from any place, and again changes nothing', (
    tester,
  ) async {
    late _Messages model;
    await show(tester, messages: (environment) => model = _Messages(environment));
    await settle(tester);
    for (final from in [HomeTab.home, HomeTab.follow, HomeTab.mine]) {
      if (from != HomeTab.home) {
        await tapTab(tester, from);
        await settle(tester);
      }
      model.requestShow();
      await settle(tester);
      expectSelected(tester, HomeTab.messages);
      expect(tester.widget<MessagePage>(find.byType(MessagePage)).active, isTrue);
    }
    model.requestShow();
    await settle(tester);
    expectSelected(tester, HomeTab.messages);
  });

  testWidgets('the iPad has no 消息: the shell starts no counts, and a show request changes nothing', (tester) async {
    late _Messages model;
    await show(tester, size: const Size(834, 1194), messages: (environment) => model = _Messages(environment));
    await settle(tester);
    expect(model.starts, 0);
    model.requestShow();
    await settle(tester);
    expect(tester.widget<MessagePage>(find.byType(MessagePage, skipOffstage: false)).active, isFalse);
    expect(find.byType(HomePage), findsOneWidget);
    expect(model.refreshes, 0);
  });

  testWidgets("the bar's 关注 count follows the badge: none at 0, and none while 关注 shows", (tester) async {
    await show(tester);
    await settle(tester);
    expect(badge.starts, 1, reason: 'the shell starts the count once');
    final count = find.byKey(const ValueKey('home-tab-follow-count'));
    expect(count, findsNothing);

    badge.show(3);
    await tester.pump();
    expect(find.descendant(of: count, matching: find.text('3')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-tab-messages-count')), findsNothing);

    badge.show(0);
    await tester.pump();
    expect(count, findsNothing);

    await tapTab(tester, HomeTab.follow);
    await settle(tester);
    badge.show(5);
    await tester.pump();
    expect(count, findsNothing, reason: '关注 shows');

    await tapTab(tester, HomeTab.home);
    await settle(tester);
    expect(find.descendant(of: count, matching: find.text('5')), findsOneWidget);
    expect((badge.starts, badge.clears), (1, 0));
  });

  testWidgets('关注 opened over its count clears it and asks the list again; opened at 0 it only shows it', (
    tester,
  ) async {
    await show(tester);
    await settle(tester);
    badge.show(4);
    await tester.pump();
    await tapTab(tester, HomeTab.follow);
    expect((badge.clears, badge.count), (1, 0));
    await settle(tester);
    expect(dynamicApi.calls, ['ups offset=', 'feed all offset='], reason: 'its first show loads once');

    await tapTab(tester, HomeTab.home);
    await settle(tester);
    await tapTab(tester, HomeTab.follow);
    await settle(tester);
    expect(dynamicApi.calls, hasLength(2), reason: 'shown as it was');
    expect(badge.clears, 1);

    await tapTab(tester, HomeTab.home);
    await settle(tester);
    badge.show(2);
    await tester.pump();
    await tapTab(tester, HomeTab.follow);
    expect(badge.clears, 2);
    await settle(tester);
    expect(dynamicApi.calls.sublist(2), ['ups offset=', 'feed all offset=']);
    expect(find.byKey(const ValueKey('home-tab-follow-count')), findsNothing);
    expect(badge.baselines, ['p0', 'p0']);
  });

  testWidgets("the iPad's bar draws no 关注 count: the shell starts none, and 动态 hands no baseline on", (tester) async {
    await show(tester, size: const Size(834, 1194));
    await settle(tester);
    expect(badge.starts, 0);
    badge.show(5);
    await tester.pump();
    expect(find.byType(TabCount), findsNothing);

    await tapTab(tester, HomeTab.follow);
    await settle(tester);
    expect(dynamicApi.calls, contains('feed all offset='));
    expect(badge.baselines, isEmpty);
    expect(badge.clears, 0);
  });

  testWidgets('+ says 暂未开放 and changes nothing, from either tab', (tester) async {
    await show(tester);
    await settle(tester, 40);
    final asked = List.of(http.asked);
    for (final from in [HomeTab.home, HomeTab.mine]) {
      if (from == HomeTab.mine) {
        await tapTab(tester, from);
        await settle(tester, 20);
      }
      await tapTab(tester, HomeTab.post);
      expect(find.text('暂未开放'), findsOneWidget);
      await settle(tester, 60);
      expectSelected(tester, from);
      expect(meActive(tester), from == HomeTab.mine);
    }
    expect(http.asked, asked, reason: 'no refresh');
  });

  testWidgets('hidden 首页 ticks nothing: the loading cards stop sweeping, the refresh TV holds its face', (
    tester,
  ) async {
    http.gates[1] = Completer<void>();
    await show(tester);
    await settle(tester, 2);
    String? sweep() => tester
        .state(find.byType(Shimmer, skipOffstage: false).first)
        .toDiagnosticsNode()
        .getProperties()
        .firstWhere((property) => property.name == 'ticker')
        .toDescription();
    bool homeTicks() => TickerMode.valuesOf(tester.element(find.byType(Shimmer, skipOffstage: false).first)).enabled;
    expect(sweep(), 'active');
    expect(homeTicks(), isTrue);

    await tapTab(tester, HomeTab.mine);
    await settle(tester);
    expect(homeTicks(), isFalse);
    expect(sweep(), 'active but muted');
    expect(TickerMode.valuesOf(tester.element(find.byType(MePage))).enabled, isTrue);
    expect(tester.binding.transientCallbackCount, 0, reason: '首页 asks for no frames while hidden');

    await tapTab(tester, HomeTab.home);
    await tester.pump();
    expect(homeTicks(), isTrue);
    expect(sweep(), 'active');
    http.gates[1]!.complete();
    await settle(tester, 40);

    int face() {
      for (var face = 0; face < LoadingTv.frames.length; face++) {
        if (find.byKey(ValueKey('loading-tv-$face'), skipOffstage: false).evaluate().isNotEmpty) return face;
      }
      fail('no loading TV');
    }

    http.gates[1] = Completer<void>();
    await tapTab(tester, HomeTab.home);
    await settle(tester, 10);
    final cycling = face();
    await tester.pump(LoadingTvTheme.frame);
    expect(face(), isNot(cycling), reason: 'cycling while shown');

    await tapTab(tester, HomeTab.mine);
    final held = face();
    for (var i = 0; i < 4; i++) {
      await tester.pump(LoadingTvTheme.frame);
      expect(face(), held, reason: 'held while hidden');
    }
    await tapTab(tester, HomeTab.home);
    await tester.pump(LoadingTvTheme.frame);
    await tester.pump(LoadingTvTheme.frame);
    expect(face(), isNot(held), reason: 'cycling again once shown');
    http.gates[1]!.complete();
    await settle(tester, 40);
  });

  /// The bar as KaiC's iPhone draws it under the system font, against 01 (首页 selected) and 02 (我的 selected). With
  /// BILIFAST_SHOTS naming a folder outside the repo, the 3× shots are saved there for tools/screen_diff.py.
  for (final (selected, shot) in [(HomeTab.home, '01'), (HomeTab.mine, '02')]) {
    testWidgets('under the system font, the bar with ${selected.label} selected where $shot has it', (tester) async {
      await show(tester, phone: true);
      await settle(tester, 40);
      if (selected == HomeTab.mine) {
        await tapTab(tester, HomeTab.mine);
        await settle(tester, 20);
      }
      expectSelected(tester, selected);
      final bar = tester.getRect(find.byType(HomeTabBar));
      expect(bar.top, 873);
      expect(bar.bottom, 956);
      for (final (i, tab) in HomeTab.values.indexed) {
        final icon = tester.getCenter(find.descendant(of: slot(tab), matching: find.byType(HomeTabIcon)));
        expect(icon.dx, 44 + 88.0 * i, reason: tab.label);
        expect(icon.dy, moreOrLessEquals(tab == HomeTab.post ? 897.67 : 891, epsilon: 0.01), reason: tab.label);
      }

      final shots = Platform.environment['BILIFAST_SHOTS'];
      if (shots != null) await saveShot(tester, find.byKey(_screen), '$shots/$shot-bar-ours.png');
    });
  }
}

/// 消息's model counting the shell's and the page's asks, its badge set by the test; it asks Bilibili nothing.
class _Messages extends MessageModel {
  _Messages(AppEnvironment environment) : super(api: FakeMessageApi(), environment: environment);

  int starts = 0;
  int refreshes = 0;
  int _badge = 0;

  void setBadge(int badge) {
    _badge = badge;
    notifyListeners();
  }

  @override
  int get badge => _badge;

  @override
  void start() => starts++;

  @override
  Future<bool> refresh() async {
    refreshes++;
    return true;
  }
}
