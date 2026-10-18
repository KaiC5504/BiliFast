import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/home_page.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/fake_player.dart';
import 'feed_fakes.dart';

void main() {
  late FeedHttp http;
  late FakePlayer player;
  late PlaybackController controller;
  late RecentStore recents;

  setUp(() {
    http = FeedHttp();
    http.pages[1] = [feedItem('BV1aaa', reason: '1万点赞'), feedItem('BV1bbb')];
    player = FakePlayer();
  });

  Future<void> show(WidgetTester tester, {bool developer = false}) async {
    tester.view.physicalSize = const Size(440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final logger = Logger(session: 'test');
    final environment = await AppEnvironment.load(
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
    final services = AppServices(
      environment: environment,
      playback: AppPlayback(() async => controller),
      recents: recents,
    );
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

  testWidgets('loading cards sweep until the feed answers, then two columns of cards', (tester) async {
    http.gates[1] = Completer<void>();
    await show(tester);
    await settle(tester, 2);
    expect(find.text('推荐'), findsOneWidget);
    expect(find.byKey(const ValueKey('feed-card-BV1aaa')), findsNothing);
    http.gates[1]!.complete();
    await settle(tester);
    expect(find.text('视频 BV1aaa'), findsOneWidget);
    expect(find.text('1万点赞'), findsOneWidget, reason: 'the reason tag');
    expect(find.text('UP BV1bbb'), findsOneWidget);
    expect(find.text('1.2万'), findsNWidgets(2));
    expect(find.text('2:05'), findsNWidgets(2));
    final first = tester.getTopLeft(find.byKey(const ValueKey('feed-card-BV1aaa')));
    final second = tester.getTopLeft(find.byKey(const ValueKey('feed-card-BV1bbb')));
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

  testWidgets('a pasted link opens its part on the video page, lands in 最近打开, and back closes it', (tester) async {
    await show(tester);
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('home-link')), 'https://www.bilibili.com/video/BV1GJ411x7h7?p=2');
    await settle(tester, 20);
    expect(find.text('测试视频'), findsOneWidget);
    expect(controller.page?.cid, 137649200);
    expect(find.text('UP主 · P2 第二集'), findsOneWidget);
    expect(recents.items.single.id, 'BV1GJ411x7h7#137649200');

    await tester.tap(find.byKey(const ValueKey('video-back')));
    await settle(tester, 20);
    expect(find.text('推荐'), findsOneWidget);
    expect(controller.video, isNull, reason: 'the page gave the player back');
    expect(tester.widget<TextField>(find.byKey(const ValueKey('home-link'))).controller!.text, isEmpty);
  });

  testWidgets('a link to a video in parts asks which part', (tester) async {
    await show(tester);
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('home-link')), 'BV1GJ411x7h7');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await settle(tester, 20);
    expect(find.text('选择分P'), findsOneWidget);
    await tester.tap(find.text('P1 第一集'));
    await settle(tester, 20);
    expect(controller.page?.cid, 137649199);
  });

  testWidgets('a card opens its video page with the card title first', (tester) async {
    http.canned.gates[Canned.signedViewPath] = Completer<void>();
    await show(tester);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('feed-card-BV1aaa')));
    await settle(tester, 20);
    expect(find.byKey(const ValueKey('video-title')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('video-title'))).data, '视频 BV1aaa');
    http.canned.gates[Canned.signedViewPath]!.complete();
    await settle(tester, 20);
    expect(tester.widget<Text>(find.byKey(const ValueKey('video-title'))).data, '测试视频');
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
    await tester.tap(find.text('最近打开'));
    await settle(tester, 20);
    expect(find.text('最近的视频'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('recents-clear')));
    await settle(tester, 20);
    await tester.tap(find.byKey(const ValueKey('recents-clear-confirm')));
    await settle(tester, 20);
    expect(find.text('还没有打开过视频'), findsOneWidget);
    expect(recents.items, isEmpty);
  });

  testWidgets('a tap outside closes the menu; release builds have no 开发者', (tester) async {
    await show(tester);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('home-avatar')));
    await settle(tester);
    expect(find.text('开发者'), findsNothing);
    await tester.tapAt(const Offset(400, 800));
    await settle(tester);
    expect(
      tester
          .widget<IgnorePointer>(
            find.ancestor(of: find.byKey(const ValueKey('avatar-menu')), matching: find.byType(IgnorePointer)).first,
          )
          .ignoring,
      isTrue,
    );
  });
}
