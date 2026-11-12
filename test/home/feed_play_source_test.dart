import 'package:bili_core/api.dart' hide VideoPage;
import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/feed_big_card.dart';
import 'package:bilifast/home/feed_inline_player.dart';
import 'package:bilifast/home/feed_model.dart';
import 'package:bilifast/home/home_page.dart';
import 'package:bilifast/home/main_shell.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:bilifast/video/video_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/fake_player.dart';
import 'autoplay_rules.dart';
import 'fake_login_gate.dart';
import 'feed_fakes.dart';

const _bv = 'BV1GJ411x7h7';
const _flow = '{"flow_card_type":"big"}';

/// The big card's page is told where it came from, as a small card's is (home_page_test.dart), whether it takes the
/// card's playback over or opens the video itself.
void main() {
  late List<FakePlayer> players;

  setUp(() {
    players = [];
    FeedInlineChoices.reset();
    HomePage.feedMinimumRefresh = Duration.zero;
    HomePage.precacheCover = (context, url, size) async => true;
    HomePage.precacheBigCover = (context, url, size) async => true;
    HomePage.feedPages = (index) async => index == 1
        ? [bigCard(_bv, idx: 30, trackId: 'track-big', flowData: _flow), ...smalls('a', 12)]
        : const [];
    addTearDown(() {
      HomePage.feedMinimumRefresh = FeedModel.minimumRefresh;
      HomePage.precacheCover = (context, url, size) async => false;
      HomePage.precacheBigCover = FeedBigCardView.precacheCover;
      HomePage.feedPages = null;
      FeedInlineChoices.reset();
    });
  });

  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final logger = Logger(session: 'test');
    final http = FeedHttp();
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: http,
      logger: logger,
    );
    await environment.refreshAccount();
    final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
    final playback = AppPlayback(() async {
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
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      loginGate: FakeLoginGate(),
      pageApi: FakePageApi(),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppScope(services: services, child: child!),
        home: const MainShell(),
      ),
    );
  }

  Future<void> frames(WidgetTester tester, [int count = 10]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<VideoPage> opened(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('feed-card-$_bv')),
        matching: find.byKey(const ValueKey('big-card-open')),
      ),
    );
    await frames(tester, 30);
    return tester.widget<VideoPage>(find.byType(VideoPage));
  }

  void fromRecommend(PlaySource source) {
    expect(source.fromSpmid, 'tm.recommend.0.0');
    expect(source.from, '7');
    expect(source.trackId, 'track-big');
    expect(source.flowData, _flow);
  }

  testWidgets("a playing big card's page takes its playback and the card's track data", (tester) async {
    await show(tester);
    await frames(tester, 20);
    expect(players, isNotEmpty, reason: 'the big card asked for a player');
    players.last.emit(const StatusChanged(PlayerStatus.playing));
    await frames(tester, 2);
    final page = await opened(tester);
    expect(page.route.playback, isNotNull);
    fromRecommend(page.route.source);
  });

  testWidgets("a big card that doesn't play inline opens its page with the card's track data too", (tester) async {
    autoplayRules().homeAutoplay = AutoplayChoice.off;
    await show(tester);
    await frames(tester, 30);
    expect(players, isEmpty);
    final page = await opened(tester);
    expect(page.route.playback, isNull);
    fromRecommend(page.route.source);
  });
}
