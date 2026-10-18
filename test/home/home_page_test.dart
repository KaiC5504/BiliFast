import 'dart:async';
import 'dart:convert';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/feed_model.dart';
import 'package:bilifast/home/home_page.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/shared/menu.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/video/video_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/fake_player.dart';
import 'feed_fakes.dart';

const _watchLaterPath = '/x/v2/history/toview/add';

void main() {
  late FeedHttp http;
  late FakePlayer player;
  late PlaybackController controller;
  late RecentStore recents;
  late AppEnvironment environment;

  setUp(() {
    http = FeedHttp();
    http.pages[1] = [feedItem('BV1aaa', reason: '1万点赞'), feedItem('BV1bbb')];
    player = FakePlayer();
  });

  List<Map<String, Object?>> twenty() => [for (var i = 0; i < 20; i++) feedItem('BV1c$i')];

  Future<void> show(WidgetTester tester, {bool developer = false, double scale = 1, bool still = false}) async {
    tester.view.physicalSize = const Size(440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (scale != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    if (still) {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    }
    final logger = Logger(session: 'test');
    environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: http,
      logger: logger,
    );
    await environment.refreshAccount();
    final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
    controller = PlaybackController(
      client: environment.client,
      engine: FakeEngine(),
      player: player,
      clock: ManualClock(10000).clock,
      now: () => now,
      startTimer: FakeTimers().start,
      logger: logger,
    );
    recents = await RecentStore.load(null, logger: logger);
    final playback = AppPlayback(() async => controller);
    addTearDown(playback.dispose);
    final services = AppServices(environment: environment, playback: playback, recents: recents);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppScope(services: services, child: child!),
        home: HomePage(developerPage: developer ? (context) => const Text('开发者页面') : null),
      ),
    );
  }

  /// Lets requests answer and frames run without waiting on the loading cards' endless sweep.
  Future<void> settle(WidgetTester tester, [int frames = 10]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Lets a toast run out, so its timer is not left pending.
  Future<void> toastGone(WidgetTester tester) => settle(tester, 60);

  Finder card(String bvid) => find.byKey(ValueKey('feed-card-$bvid'));

  Finder entrance(String bvid) => find.descendant(of: card(bvid), matching: find.byType(SlideTransition));

  testWidgets('loading cards sweep until the feed answers, then two columns of cards', (tester) async {
    http.gates[1] = Completer<void>();
    await show(tester);
    await settle(tester, 2);
    expect(find.text('推荐'), findsOneWidget);
    expect(card('BV1aaa'), findsNothing);
    http.gates[1]!.complete();
    await settle(tester);
    expect(find.text('视频 BV1aaa'), findsOneWidget);
    expect(find.text('1万点赞'), findsOneWidget, reason: 'the reason tag');
    expect(find.text('UP BV1bbb'), findsOneWidget);
    expect(find.text('1.2万'), findsNWidgets(2));
    expect(find.text('2:05'), findsNWidgets(2));
    final first = tester.getTopLeft(card('BV1aaa'));
    final second = tester.getTopLeft(card('BV1bbb'));
    expect(first.dy, second.dy, reason: 'side by side');
    expect(http.asked.first, 1);
  });

  testWidgets('a failed feed says why, and 重试 loads it', (tester) async {
    http.failing.add(1);
    await show(tester);
    await settle(tester);
    expect(find.byKey(const ValueKey('feed-error')), findsOneWidget);
    http.failing.clear();
    await tester.tap(find.byKey(const ValueKey('feed-retry')));
    await settle(tester);
    expect(find.text('视频 BV1aaa'), findsOneWidget);
  });

  testWidgets('an empty first page says so with 重试 instead of loading forever', (tester) async {
    http.pages[1] = [];
    await show(tester);
    await settle(tester);
    expect(find.text(FeedModel.emptyMessage), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    http.pages[1] = twenty();
    await tester.tap(find.byKey(const ValueKey('feed-retry')));
    await settle(tester);
    expect(card('BV1c0'), findsOneWidget);
    expect(http.asked, [1, 1]);
  });

  testWidgets('the next page is asked for only near the end of the grid, never by building cards', (tester) async {
    http.pages[1] = twenty();
    http.pages[2] = [for (var i = 20; i < 40; i++) feedItem('BV1c$i')];
    await show(tester);
    await settle(tester, 40);
    expect(http.asked, [1], reason: 'the end is far below the screen');
    await tester.drag(find.byKey(const ValueKey('feed')), const Offset(0, -3000));
    await settle(tester, 20);
    expect(http.asked, [1, 2]);
  });

  testWidgets('a short feed whose next pages add nothing asks three more times, then offers 没有更多了', (tester) async {
    await show(tester);
    await settle(tester, 40);
    expect(http.asked, [1, 2, 3, 4]);
    expect(find.text(FeedModel.endMessage), findsOneWidget);
    expect(find.byKey(const ValueKey('feed-more')), findsNothing, reason: 'no spinner while nothing loads');

    http.pages[5] = [feedItem('BV1ccc')];
    await tester.tap(find.byKey(const ValueKey('feed-retry')));
    await settle(tester, 40);
    expect(http.asked.take(5), [1, 2, 3, 4, 5]);
    expect(card('BV1ccc'), findsOneWidget);
  });

  testWidgets('a failed load more waits for 重试 instead of asking again', (tester) async {
    http.pages[1] = twenty();
    http.failing.add(2);
    await show(tester);
    await settle(tester);
    await tester.drag(find.byKey(const ValueKey('feed')), const Offset(0, -3000));
    await settle(tester, 20);
    expect(find.byKey(const ValueKey('feed-error')), findsOneWidget);
    await tester.drag(find.byKey(const ValueKey('feed')), const Offset(0, -300));
    await settle(tester, 20);
    expect(http.asked, [1, 2]);
    http.failing.clear();
    http.pages[2] = [for (var i = 20; i < 40; i++) feedItem('BV1c$i')];
    await tester.tap(find.byKey(const ValueKey('feed-retry')));
    await settle(tester, 20);
    expect(http.asked, [1, 2, 2]);
    expect(find.byKey(const ValueKey('feed-error')), findsNothing);
  });

  testWidgets('a pull to refresh that fails keeps the cards and says why in a toast', (tester) async {
    http.pages[1] = twenty();
    await show(tester);
    await settle(tester);
    http.failing.add(1);
    await tester.drag(find.byKey(const ValueKey('feed')), const Offset(0, 500));
    await settle(tester, 20);
    expect(http.asked, [1, 1]);
    expect(find.text('网络请求失败（HTTP 500）'), findsOneWidget);
    expect(find.byKey(const ValueKey('feed-error')), findsNothing);
    expect(card('BV1c0'), findsOneWidget);
    await toastGone(tester);
  });

  testWidgets('home goes idle once the feed shows: nothing ticks, no frame waits', (tester) async {
    http.pages[1] = twenty();
    http.gates[1] = Completer<void>();
    await show(tester);
    await settle(tester, 2);
    expect(tester.binding.transientCallbackCount, greaterThan(0), reason: 'the loading cards sweep');
    http.gates[1]!.complete();
    await settle(tester, 40);
    expect(card('BV1c0'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('cards fade in the first time they appear, never again when scrolled back', (tester) async {
    http.pages[1] = twenty();
    await show(tester);
    await settle(tester, 20);
    expect(entrance('BV1c0'), findsOneWidget);
    await tester.drag(find.byKey(const ValueKey('feed')), const Offset(0, -2500));
    await settle(tester, 20);
    expect(card('BV1c0'), findsNothing, reason: 'scrolled out and let go');
    await tester.drag(find.byKey(const ValueKey('feed')), const Offset(0, 2500));
    await tester.pump();
    expect(card('BV1c0'), findsOneWidget);
    expect(entrance('BV1c0'), findsNothing);
    await settle(tester, 20);
  });

  testWidgets('with reduced motion the cards just appear and the loading cards keep still', (tester) async {
    http.pages[1] = twenty();
    http.gates[1] = Completer<void>();
    await show(tester, still: true);
    await settle(tester, 2);
    expect(tester.binding.transientCallbackCount, 0);
    http.gates[1]!.complete();
    await tester.pump();
    await tester.pump();
    expect(card('BV1c0'), findsOneWidget);
    expect(entrance('BV1c0'), findsNothing);
  });

  testWidgets('a pasted link opens its part on the video page, lands in 最近打开, and back closes it', (tester) async {
    await show(tester);
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('home-link')), 'https://www.bilibili.com/video/BV1GJ411x7h7?p=2');
    await settle(tester, 20);
    expect(find.text('测试视频'), findsOneWidget);
    expect(controller.page?.cid, 137649200);
    expect(find.text('UP主 · P2 第二集'), findsOneWidget);
    expect(recents.items.single.id, 'BV1GJ411x7h7#137649200');
    final route = tester.widget<VideoPage>(find.byType(VideoPage)).route;
    expect(route.detail?.bvid, 'BV1GJ411x7h7', reason: 'the signed view that resolved the link, for its 合集');
    expect(http.canned.to(Canned.signedViewPath), hasLength(1));

    await tester.tap(find.byKey(const ValueKey('video-back')));
    await settle(tester, 20);
    expect(find.text('推荐'), findsOneWidget);
    expect(controller.video, isNull, reason: 'the page gave the player back');
    expect(tester.widget<TextField>(find.byKey(const ValueKey('home-link'))).controller!.text, isEmpty);
  });

  testWidgets('a link to a video in parts asks which part, with no spinner left behind the sheet', (tester) async {
    await show(tester);
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('home-link')), 'BV1GJ411x7h7');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await settle(tester, 20);
    expect(find.text('选择分P'), findsOneWidget);
    expect(find.byKey(const ValueKey('opening')), findsNothing);
    await tester.tap(find.text('P1 第一集'));
    await settle(tester, 20);
    expect(controller.page?.cid, 137649199);
  });

  testWidgets('a card opens its video page with the card title first', (tester) async {
    http.canned.gates[Canned.signedViewPath] = Completer<void>();
    await show(tester);
    await settle(tester);
    await tester.tap(card('BV1aaa'));
    await settle(tester, 20);
    expect(find.byKey(const ValueKey('video-title')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('video-title'))).data, '视频 BV1aaa');
    http.canned.gates[Canned.signedViewPath]!.complete();
    await settle(tester, 20);
    expect(tester.widget<Text>(find.byKey(const ValueKey('video-title'))).data, '测试视频');
  });

  testWidgets('⋮ opens a frosted menu beside it whose 稍后再看 adds the video', (tester) async {
    http.canned.routes[_watchLaterPath] = (200, '{"code":0,"message":"0","ttl":1}');
    await show(tester);
    await settle(tester);
    final more = find.descendant(of: card('BV1aaa'), matching: find.byKey(const ValueKey('card-more')));
    expect(tester.getSize(more), const Size.square(24), reason: "Swift's tap target");
    await tester.tap(more);
    await settle(tester);
    expect(find.byType(GlassPanel), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(
      find.descendant(of: find.byType(GlassPanel), matching: find.byType(InkWell)),
      findsNothing,
      reason: 'no Material ripple in the menu',
    );
    await tester.tap(find.byKey(const ValueKey('card-watch-later')));
    await settle(tester);
    expect(find.byType(GlassPanel), findsNothing);
    expect(find.text('已添加至稍后再看'), findsOneWidget);
    final sent = Uri.splitQueryString(utf8.decode(http.canned.to(_watchLaterPath).single.body!));
    expect(sent['aid'], '${'BV1aaa'.hashCode.abs()}');
    await toastGone(tester);

    await tester.tap(more);
    await settle(tester);
    await tester.tapAt(const Offset(220, 850));
    await settle(tester);
    expect(find.byType(GlassPanel), findsNothing, reason: 'a tap elsewhere closes it');
    expect(http.canned.to(_watchLaterPath), hasLength(1));
  });

  testWidgets('the avatar opens the account menu: 最近打开, and 开发者 in dev builds', (tester) async {
    await show(tester, developer: true);
    await settle(tester);
    recents.add(const RecentVideo(bvid: 'BV1x', cid: 3, title: '最近的视频', part: '', page: 1, pageCount: 1));
    await tester.tap(find.byKey(const ValueKey('home-avatar')));
    await settle(tester);
    expect(find.byKey(const ValueKey('menu-account-name')), findsOneWidget);
    expect(find.text('测试用户'), findsOneWidget);
    expect(find.text('大会员'), findsOneWidget);
    expect(find.text('开发者'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.descendant(of: find.byType(GlassPanel), matching: find.byType(BackdropFilter)), findsOneWidget);
    await tester.tap(find.text('最近打开'));
    await settle(tester, 20);
    expect(find.text('最近的视频'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(ListView), matching: find.byType(InkWell)),
      findsNothing,
      reason: 'recents rows highlight instead of rippling',
    );

    await tester.tap(find.byKey(const ValueKey('recents-clear')));
    await settle(tester, 20);
    await tester.tap(find.byKey(const ValueKey('recents-clear-confirm')));
    await settle(tester, 20);
    expect(find.text('还没有打开过视频'), findsOneWidget);
    expect(recents.items, isEmpty);
  });

  testWidgets('设置 in the avatar menu opens 设置 with the font in use', (tester) async {
    await show(tester);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('home-avatar')));
    await settle(tester);
    await tester.tap(find.text('设置'));
    await settle(tester, 20);
    expect(find.byKey(const ValueKey('settings-font')), findsOneWidget);
    expect(find.text('MiSans'), findsOneWidget);
  });

  testWidgets('a tap outside closes the menu, which then leaves the tree; release builds have no 开发者', (tester) async {
    await show(tester);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('home-avatar')));
    await settle(tester);
    expect(find.byKey(const ValueKey('avatar-menu')), findsOneWidget);
    expect(find.text('开发者'), findsNothing);
    await tester.tapAt(const Offset(400, 800));
    await settle(tester);
    expect(find.byKey(const ValueKey('avatar-menu')), findsNothing);
    expect(find.byKey(const ValueKey('menu-scrim')), findsNothing);
  });

  testWidgets('back on home from 最近打开, an account check that failed is tried again', (tester) async {
    http.canned.routes[Canned.navPath] = (500, '');
    await show(tester);
    await settle(tester);
    expect(environment.account, isA<AccountUnknown>());
    expect(environment.accountCheckFailed, isTrue);

    Future<void> visitRecents() async {
      await tester.tap(find.byKey(const ValueKey('home-avatar')));
      await settle(tester);
      await tester.tap(find.text('最近打开'));
      await settle(tester, 20);
      expect(find.text('还没有打开过视频'), findsOneWidget);
      await tester.pageBack();
      await settle(tester, 20);
    }

    http.canned.routes[Canned.navPath] = (200, Canned.navLoggedIn);
    final asked = http.canned.to(Canned.navPath).length;
    await visitRecents();
    expect(environment.account, isA<LoggedIn>());
    expect(http.canned.to(Canned.navPath), hasLength(asked + 1));

    await visitRecents();
    expect(http.canned.to(Canned.navPath), hasLength(asked + 1), reason: 'a known account is not asked again');
  });

  testWidgets('cards are buttons named by their title, with 稍后再看 as their action', (tester) async {
    final semantics = tester.ensureSemantics();
    await show(tester);
    await settle(tester);
    expect(
      tester.getSemantics(card('BV1aaa')),
      isSemantics(
        label: '视频 BV1aaa',
        isButton: true,
        hasTapAction: true,
        customActions: const [CustomSemanticsAction(label: '稍后再看')],
      ),
    );
    semantics.dispose();
  });

  testWidgets('with the menu open VoiceOver reaches the menu and a way out, not the cards behind', (tester) async {
    final semantics = tester.ensureSemantics();
    await show(tester);
    await settle(tester);
    expect(find.semantics.byLabel('视频 BV1aaa'), findsOne);
    await tester.tap(find.byKey(const ValueKey('home-avatar')));
    await settle(tester);
    expect(find.semantics.byLabel('视频 BV1aaa'), findsNothing);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('menu-scrim'))),
      isSemantics(label: '关闭菜单', isButton: true, hasTapAction: true, hasDismissAction: true),
    );
    expect(
      tester.getSemantics(find.text('历史记录')),
      isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
    );
    expect(
      tester.getSemantics(find.text('最近打开')),
      isSemantics(isButton: true, hasEnabledState: true, isEnabled: true, hasTapAction: true),
    );
    semantics.dispose();
  });

  for (final scale in [2.0, 3.0]) {
    testWidgets('nothing overflows at text scale $scale, with the account menu open', (tester) async {
      await show(tester, scale: scale);
      await settle(tester);
      expect(card('BV1aaa'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-avatar')));
      await settle(tester);
      expect(find.byKey(const ValueKey('avatar-menu')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets("on iOS the link field's edit menu is the system's, whose Paste asks nothing", (tester) async {
    tester.platformDispatcher.supportsShowingSystemContextMenu = true;
    addTearDown(tester.platformDispatcher.resetSupportsShowingSystemContextMenu);
    await show(tester);
    await settle(tester);
    expect(await editMenu(tester), isA<SystemContextMenu>());
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets("elsewhere the link field's edit menu is Flutter's own", (tester) async {
    await show(tester);
    await settle(tester);
    expect(await editMenu(tester), isA<AdaptiveTextSelectionToolbar>());
  });
}

/// What the link field shows as its edit menu once focused.
Future<Widget> editMenu(WidgetTester tester) async {
  final field = find.byKey(const ValueKey('home-link'));
  await tester.tap(field);
  await tester.pump();
  final editable = find.descendant(of: field, matching: find.byType(EditableText));
  final state = tester.state<EditableTextState>(editable);
  return tester.widget<TextField>(field).contextMenuBuilder!(tester.element(editable), state);
}
