import 'dart:async';
import 'dart:convert';

import 'package:bili_core/api.dart' show AppToken, HTTPRequest, OfficialIdentity, PlaySource;
import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart' show ManualClock;
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/route_observer.dart';
import 'package:bilifast/app/swipe_back_route.dart';
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/device/player_device.dart';
import 'package:bilifast/home/feed_inline_player.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player/playback_clock.dart';
import 'package:bilifast/settings/autoplay_policy.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/page_details.dart';
import 'package:bilifast/video/page_playback.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:bilifast/video/player_session.dart';
import 'package:bilifast/video/story/story_list.dart';
import 'package:bilifast/video/video_page.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/fake_player.dart';
import '../support/fake_video_actions.dart';

const mobilePath = '/x/report/heartbeat/mobile';
const historyPath = '/x/v2/history/report';
const webPath = '/x/click-interface/web/heartbeat';
const ok = '{"code":0,"message":"0","ttl":1}';
const bv = 'BV1GJ411x7h7';
const other = 'BV1xx411c7mD';
const p1 = 137649199;
const p2 = 137649200;

const recommended = PlaySource(
  fromSpmid: 'tm.recommend.0.0',
  from: '7',
  trackId: 'TRACK.1.2.3',
  flowData: '{"flow_card_type":"av"}',
);

/// The other video, as the signed view answers for it.
final otherView = Canned.view.replaceAll(bv, other).replaceAll('80433022', '80433023');

class _NoLogin implements LoginGate {
  @override
  Future<bool> request(BuildContext context) async => false;
}

/// Where a page was opened from reaches the official watch reports of its video: from the route to the playback, and
/// from the page that takes 推荐's card over.
void main() {
  late CannedHttp http;
  late AppEnvironment environment;
  late AppServices services;
  late ManualClock time;
  late List<FakePlayer> players;

  setUp(() {
    http = Canned.http()
      ..routes[mobilePath] = (200, ok)
      ..routes[historyPath] = (200, ok)
      ..routes[webPath] = (200, ok);
    players = [];
    final savedPrefs = PlayerPrefs.shared;
    final savedPolicy = AutoplayPolicy.shared;
    PlayerPrefs.shared = PlayerPrefs.memory();
    AutoplayPolicy.shared = AutoplayPolicy.fixed();
    addTearDown(() {
      PlayerPrefs.shared = savedPrefs;
      AutoplayPolicy.shared = savedPolicy;
    });
  });

  PageDetails fakeDetails({
    required PlayerSession session,
    required AppServices services,
    required void Function(String message) toast,
    required VoidCallback requestLogin,
    required Listenable logins,
  }) => FakePageDetails();

  Widget page(VideoRoute route) => VideoPage(
    route: route,
    createSession: pageSession,
    createDetails: fakeDetails,
    openPage: (context, route) async {},
  );

  Future<void> host(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: 62, bottom: 34)
      ..viewPadding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    final logger = Logger(session: 'test');
    environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: http,
      logger: logger,
    );
    await environment.refreshAccount();
    environment.client.appToken = AppToken(
      accessToken: 'ACCESS',
      refreshToken: 'REFRESH',
      mid: 7,
      expiresAt: DateTime.utc(2027, 4, 1),
      identity: OfficialIdentity.iphone,
    );
    final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
    time = ManualClock(10000);
    final playback = AppPlayback(() async {
      final player = FakePlayer();
      players.add(player);
      return PlaybackController(
        client: environment.client,
        engine: FakeEngine(),
        player: player,
        clock: time.clock,
        now: () => now,
        startTimer: FakeTimers().start,
        logger: logger,
      );
    });
    addTearDown(playback.dispose);
    services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      device: PlayerDevice(orientation: OrientationController(), controls: NoDeviceControls()),
      loginGate: _NoLogin(),
      pageApi: FakePageApi(),
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: services.navigator,
        navigatorObservers: [pageRoutes],
        builder: (context, child) => AppScope(services: services, child: child!),
        home: const SizedBox(),
      ),
    );
  }

  Future<void> frames(WidgetTester tester, [int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> plays(WidgetTester tester, FakePlayer player, double seconds) async {
    player.emit(const StatusChanged(PlayerStatus.playing));
    time.advance(PlaybackClock.jumpSettleMs);
    player.emit(PositionChanged(seconds: seconds, hostMs: time.clock.nowMs(), rate: 1));
    await frames(tester, 2);
  }

  Map<String, String> form(HTTPRequest request) => Uri.splitQueryString(utf8.decode(request.body!));

  /// The start reports sent so far.
  List<Map<String, String>> starts() => [
    for (final request in http.to(mobilePath))
      if (form(request)['start_ts'] == '0') form(request),
  ];
  List<Map<String, String>> ends() => [
    for (final request in http.to(mobilePath))
      if (form(request)['start_ts'] != '0') form(request),
  ];

  void expectRecommended(Map<String, String> beat) {
    expect(beat['from'], '7');
    expect(beat['from_spmid'], 'tm.recommend.0.0');
    expect(beat['track_id'], 'TRACK.1.2.3');
    expect(beat['report_flow_data'], '{"flow_card_type":"av"}');
  }

  void expectUnknown(Map<String, String> beat) {
    expect(beat['from'], '');
    expect(beat['from_spmid'], '');
    expect(beat['track_id'], '');
    expect(beat.containsKey('report_flow_data'), isFalse);
  }

  testWidgets('a page\'s reports name where its route says it was opened from; a route that says nothing, nothing', (
    tester,
  ) async {
    await host(tester);
    final navigator = services.navigator.currentState!;
    unawaited(
      navigator.push(
        SwipeBackPageRoute<void>(
          builder: (_) => page(const VideoRoute(bvid: bv, cid: p1, start: 0, source: recommended)),
        ),
      ),
    );
    await frames(tester, 20);
    await plays(tester, players.single, 8);
    expectRecommended(starts().single);
    unawaited(navigator.maybePop());
    await frames(tester, 20);
    expectRecommended(ends().single);
    expect(ends().single['session'], starts().single['session']);
    expect(http.to(historyPath), hasLength(1));
    expect(http.to(webPath), isEmpty);

    unawaited(
      navigator.push(SwipeBackPageRoute<void>(builder: (_) => page(const VideoRoute(bvid: bv, cid: p1, start: 0)))),
    );
    await frames(tester, 20);
    await plays(tester, players.last, 8);
    expectUnknown(starts().last);
    unawaited(navigator.maybePop());
    await frames(tester, 20);
  });

  testWidgets('推荐\'s card reports nothing while it plays inline; the page that takes it over names the card', (
    tester,
  ) async {
    await host(tester);
    final card = FeedInlinePlayback(
      services: services,
      video: const InlineVideo(bvid: bv, cid: p1),
      startAt: () => 0,
      released: (_) {},
    );
    addTearDown(card.dispose);
    card.play();
    await frames(tester, 10);
    final player = players.single;
    await plays(tester, player, 5);
    expect(http.to(mobilePath), isEmpty);
    expect(http.to(webPath), isEmpty);

    final navigator = services.navigator.currentState!;
    final inline = card.handOver()!;
    unawaited(
      navigator.push(
        SwipeBackPageRoute<void>(builder: (_) => page(VideoRoute(bvid: bv, playback: inline, source: recommended))),
      ),
    );
    await frames(tester, 20);
    await plays(tester, player, 6);
    expectRecommended(starts().single);
    unawaited(navigator.maybePop());
    await frames(tester, 20);
    expectRecommended(ends().single);
    expect(http.to(webPath), isEmpty);
  });

  testWidgets('another part of the video keeps the source, another video opened on the page has none; an open that '
      'followed on its own says auto_play 99', (tester) async {
    await host(tester);
    final playback = PagePlayback(
      services: services,
      route: const VideoRoute(bvid: bv, cid: p1, start: 0, source: recommended),
      createSession: pageSession,
      restorePage: page,
    )..start();
    await frames(tester, 10);
    final player = players.single;
    await plays(tester, player, 3);
    expect(playback.restartRoute.source, same(recommended));

    playback.openOnPage(bv, cid: p2);
    await frames(tester, 10);
    await plays(tester, player, 3);
    expect(starts().map((beat) => beat['cid']), ['$p1', '$p2']);
    expect(ends().single['cid'], '$p1', reason: 'the open before it ended there');
    starts().forEach(expectRecommended);
    expect(starts().map((beat) => beat['auto_play']), ['0', '0']);

    http
      ..routes[Canned.viewPath] = (200, otherView)
      ..routes[Canned.signedViewPath] = (200, otherView);
    playback.openOnPage(other, followed: true);
    await frames(tester, 10);
    await plays(tester, player, 3);
    final last = starts().last;
    expect(last['aid'], '80433023');
    expectUnknown(last);
    expect(last['auto_play'], '99');
    expect(identical(playback.restartRoute.source, PlaySource.unknown), isTrue);

    playback.close();
    await frames(tester, 4);
    expect(ends(), hasLength(3));
    expectUnknown(ends().last);
    expect(ends().last['auto_play'], '99');
  });

  group('竖屏', () {
    const relatedPath = '/x/web-interface/archive/related';
    const related =
        '{"code":0,"message":"0","ttl":1,"data":[{"bvid":"$other","aid":80433023,"cid":0,"title":"另一个视频",'
        '"pic":"","duration":100,"owner":{"mid":2,"name":"B"},"stat":{"view":1,"danmaku":0,"like":0}}]}';

    PagePlayback started() => PagePlayback(
      services: services,
      route: const VideoRoute(bvid: bv, cid: p1, start: 0, source: recommended),
      createSession: pageSession,
      restorePage: page,
    )..start();

    testWidgets('the feed\'s first entry is the video playing, at the part playing', (tester) async {
      await host(tester);
      final playback = started();
      await frames(tester, 10);
      expect(playback.storyEntry!.cid, p1);
      playback.openOnPage(bv, cid: p2);
      await frames(tester, 10);
      expect(playback.storyEntry!.cid, p2);
      final story = playback.beginStory();
      expect(identical(playback.beginStory(), story), isTrue);
      expect(story.current!.bvid, bv);
      expect(story.current!.cid, p2);
      playback.close();
      await frames(tester, 4);
      expect(playback.story, isNull);
    });

    testWidgets('the official feed only under an iPhone token with reports allowed', (tester) async {
      await host(tester);
      final playback = started();
      await frames(tester, 10);
      expect((playback.beginStory() as StoryList).official, isTrue);
      playback.endStory();

      environment.client.appToken = AppToken(
        accessToken: 'ACCESS',
        refreshToken: 'REFRESH',
        mid: 7,
        expiresAt: DateTime.utc(2027, 4, 1),
        identity: OfficialIdentity.android,
      );
      expect((playback.beginStory() as StoryList).official, isFalse);
      playback.endStory();

      environment.client.appToken = null;
      expect((playback.beginStory() as StoryList).official, isFalse);
      playback
        ..endStory()
        ..close();
      await frames(tester, 4);
    });

    testWidgets('the official feed failing hands over to the related list; the video swiped to reports as 竖屏\'s, and '
        'ending 竖屏 leaves it on the page', (tester) async {
      await host(tester);
      http.routes[relatedPath] = (200, related);
      final playback = started();
      await frames(tester, 10);
      final player = players.single;
      await plays(tester, player, 3);
      final story = playback.beginStory();
      await frames(tester, 4);
      expect([for (final entry in story.entries) entry.bvid], [bv, other]);

      http
        ..routes[Canned.viewPath] = (200, otherView)
        ..routes[Canned.signedViewPath] = (200, otherView);
      expect(story.moveNext(), isTrue);
      await frames(tester, 10);
      await plays(tester, player, 3);
      expect(playback.bvid, other);
      final start = starts().last;
      expect(start['aid'], '80433023');
      expect(start['spmid'], 'main.ugc-video-detail-vertical.0.0');
      expect(start['from'], 'default-value');
      expect(start['from_spmid'], 'tm.recommend.0.0');
      expect(start['track_id'], '');
      expect(start['auto_play'], '99');

      final enteredEnd = ends().single;
      expectRecommended(enteredEnd);
      expect(enteredEnd['spmid'], 'united.player-video-detail.0.0', reason: 'its first play keeps how it began');
      expect(enteredEnd['auto_play'], '0');
      expect(form(http.to(historyPath).single).containsKey('source'), isFalse);

      playback.endStory();
      expect(playback.story, isNull);
      expect(playback.bvid, other);
      await frames(tester, 4);
      expect(playback.bvid, other);

      playback.close();
      await frames(tester, 4);
      expect(ends().last['spmid'], 'main.ugc-video-detail-vertical.0.0');
      expect(form(http.to(historyPath).last)['source'], 'story-series');
    });
  });
}
