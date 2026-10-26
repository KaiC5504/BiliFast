import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/dynamic/fake_dynamic_api.dart';
import 'package:bilifast/dynamic/follow_tab/follow_tab_page.dart';
import 'package:bilifast/home/feed_big_card.dart';
import 'package:bilifast/home/feed_inline_player.dart';
import 'package:bilifast/home/feed_model.dart';
import 'package:bilifast/home/home_page.dart';
import 'package:bilifast/home/home_tab_bar.dart';
import 'package:bilifast/home/main_shell.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/fake_player.dart';
import 'fake_login_gate.dart';
import 'feed_fakes.dart';

const _bv = 'BV1GJ411x7h7';

/// 推荐's big card under the bottom bar's places: 关注 lies over 首页 as 我的 does, so the card plays only on 首页.
void main() {
  late List<FakePlayer> players;
  Completer<void>? createGate;

  setUp(() {
    players = [];
    createGate = null;
    FeedInlineChoices.reset();
    HomePage.feedMinimumRefresh = Duration.zero;
    HomePage.precacheCover = (context, url, size) async => true;
    HomePage.precacheBigCover = (context, url, size) async => true;
    final pages = {
      1: [bigCard(_bv), ...smalls('a', 12)],
    };
    HomePage.feedPages = (index) async => pages[index] ?? const [];
    addTearDown(() {
      HomePage.feedMinimumRefresh = FeedModel.minimumRefresh;
      HomePage.precacheCover = (context, url, size) async => false;
      HomePage.precacheBigCover = FeedBigCardView.precacheCover;
      HomePage.feedPages = null;
      FeedInlineChoices.reset();
    });
  });

  Future<FakeDynamicApi> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final logger = Logger(session: 'test');
    final http = FeedHttp();
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(StoredCookies(Canned.cookies)),
      http: http,
      logger: logger,
    );
    await environment.refreshAccount();
    final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
    final playback = AppPlayback(() async {
      await createGate?.future;
      final player = FakePlayer();
      players.add(player);
      return PlaybackController(
        client: environment.client,
        engine: FakeEngine(),
        player: player,
        clock: ManualClock(10000).clock,
        now: () => now,
        startTimer: FakeTimers().start,
        logger: logger,
      );
    });
    addTearDown(playback.dispose);
    final dynamicApi = FakeDynamicApi();
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      loginGate: FakeLoginGate(),
      pageApi: FakePageApi(),
      dynamicApi: dynamicApi,
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppScope(services: services, child: child!),
        home: const MainShell(),
      ),
    );
    return dynamicApi;
  }

  Future<void> frames(WidgetTester tester, [int count = 10]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> tapTab(WidgetTester tester, HomeTab tab) async {
    await tester.tap(find.byKey(ValueKey('home-tab-${tab.name}')));
    await frames(tester);
  }

  /// The last play or pause since the last load, or the load's own autoplay.
  bool playingNow(FakePlayer player) {
    final calls = player.calls;
    final load = calls.lastIndexWhere((call) => call.startsWith('load'));
    final since = calls.skip(load + 1).where((call) => call == 'play' || call == 'pause');
    if (since.isEmpty) return player.loaded?.autoplay ?? false;
    return since.last == 'play';
  }

  testWidgets('playing, it pauses while 关注 shows and plays on back on 首页', (tester) async {
    await show(tester);
    await frames(tester, 20);
    expect(players, hasLength(1), reason: 'the big card asked for a player');
    players.single.emit(const StatusChanged(PlayerStatus.playing));
    await frames(tester, 2);
    expect(playingNow(players.single), isTrue);

    await tapTab(tester, HomeTab.follow);
    expect(find.byType(FollowTabPage), findsOneWidget);
    expect(playingNow(players.single), isFalse, reason: '关注 shown');
    await tapTab(tester, HomeTab.home);
    expect(playingNow(players.single), isTrue);
  });

  testWidgets('a player that comes while 关注 shows waits paused until 首页 shows again', (tester) async {
    createGate = Completer<void>();
    await show(tester);
    await frames(tester, 20);
    await tapTab(tester, HomeTab.follow);
    createGate!.complete();
    await frames(tester, 20);
    expect(players.where(playingNow), isEmpty, reason: '关注 shown');

    await tapTab(tester, HomeTab.home);
    await frames(tester, 10);
    expect(players.where(playingNow), hasLength(1));
  });
}
