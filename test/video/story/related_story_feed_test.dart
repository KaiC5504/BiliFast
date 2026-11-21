import 'dart:async';
import 'dart:convert';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart' show ManualClock;
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/route_observer.dart';
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/device/player_device.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player/playback_clock.dart';
import 'package:bilifast/settings/autoplay_policy.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/page_playback.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:bilifast/video/story/page_story_feed.dart';
import 'package:bilifast/video/story/story_drag.dart';
import 'package:bilifast/video/story/story_feed.dart';
import 'package:bilifast/video/story/story_list.dart';
import 'package:bilifast/video/story/story_pager.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/fake_keychain.dart';
import '../../playback/fakes.dart';
import '../../support/fake_player.dart';
import 'story_list_test.dart' show FakeHost;

const tapped = 2;
const fromRoute = PlaySource(fromSpmid: 'from.the.route', trackId: 'TRACK.R', flowData: '{"r":1}');

String bvOf(int place) => 'BV1rel${'$place'.padLeft(5, '0')}';

/// Upright and wide by turns, each with its own part and first frame.
VideoCard listed(int place) => VideoCard(
  aid: 500 + place,
  bvid: bvOf(place),
  cid: 900 + place,
  title: '相关$place',
  cover: 'cover$place',
  duration: 60,
  ownerMid: 3,
  ownerName: 'UP',
  views: 10,
  danmaku: 1,
  likes: 2,
  width: place.isEven ? 1080 : 1920,
  height: place.isEven ? 1920 : 1080,
  firstFrame: 'ff$place',
);

List<VideoCard> cards([int count = 5]) => [for (var place = 0; place < count; place++) listed(place)];

/// The tapped card's details as the page's playback has them: no first frame.
StoryEntry details({int? cid = 902}) => StoryEntry(
  bvid: bvOf(tapped),
  aid: 502,
  cid: cid,
  title: '详情',
  cover: 'cover',
  ownerMid: 3,
  ownerName: 'UP',
  width: 1080,
  height: 1920,
  source: fromRoute,
);

/// 竖屏's feed on a page opened from the sheet's 相关视频: that list alone, from the card tapped, with its counter.
void main() {
  late FakeHost host;
  late MemorySink logs;
  late Logger logger;
  late List<int> officialAsks;
  late List<String> relatedAsks;
  late List<String> detailAsks;
  late List<Completer<VideoDetail>> detailAnswers;
  late int notified;

  setUp(() {
    host = FakeHost()..bvid = bvOf(tapped);
    logs = MemorySink();
    logger = Logger(session: 'test')..add(logs);
    officialAsks = [];
    relatedAsks = [];
    detailAsks = [];
    detailAnswers = [];
    notified = 0;
  });

  Future<List<StoryItem>> official({
    required int aid,
    required int cid,
    required int page,
    required PlaySource entry,
    String? trackId,
  }) {
    officialAsks.add(aid);
    return Completer<List<StoryItem>>().future;
  }

  Future<List<VideoCard>> related(String bvid) {
    relatedAsks.add(bvid);
    return Completer<List<VideoCard>>().future;
  }

  Future<VideoDetail> detail(String bvid) {
    detailAsks.add(bvid);
    final answer = Completer<VideoDetail>();
    detailAnswers.add(answer);
    return answer.future;
  }

  /// Under an iPhone token by default: the official feed is there to ask, and must not be.
  StoryList make({List<VideoCard>? list, int index = tapped, bool ahead = false, bool warms = false}) {
    final on = host;
    final feed = StoryList(
      host: on,
      official: official,
      related: related,
      detail: ahead ? detail : null,
      warmsNext: warms,
      list: (cards: list ?? cards(), index: index),
      logger: logger,
    )..addListener(() => notified++);
    addTearDown(() {
      if (!on.disposed) feed.dispose();
    });
    return feed;
  }

  List<String> bvids(StoryFeed feed) => [for (final entry in feed.entries) entry.bvid];

  List<Map<String, Object>> feedLines() => [
    for (final event in logs.events)
      if (event.msg == 'story feed') {for (final MapEntry(:key, :value) in event.f.entries) key: value.toJson()},
  ];

  void detailsIn({int? cid = 902}) => host
    ..playing = details(cid: cid)
    ..changed();

  void expectNothingAsked() {
    expect(officialAsks, isEmpty);
    expect(relatedAsks, isEmpty);
  }

  test('the cards from the one the page has open, each with its part, shape and first frame; nothing asked', () {
    final feed = make();
    expect(bvids(feed), [for (var place = 0; place < 5; place++) bvOf(place)]);
    expect(feed.index, tapped);
    expect(feed.current!.bvid, bvOf(tapped));
    expect(feed.previous!.bvid, bvOf(1));
    final next = feed.next!;
    expect((next.aid, next.cid, next.width, next.height, next.still), (503, 903, 1920, 1080, 'ff3'));
    expect(next.upright, isFalse);
    expect(feed.current!.upright, isTrue);
    expect(feed.loading, isFalse);
    expect(feed.listGiven, isTrue);
    expect(feed.official, isFalse);
    expect(host.opened, isEmpty, reason: 'the page opened the card itself');
    expectNothingAsked();
    expect(feedLines(), [
      {'source': 'list', 'kept': 5, 'dropped': 0},
    ]);
  });

  test('20 at most', () {
    final feed = make(list: cards(25));
    expect(feed.entries, hasLength(20));
    expect(feed.counter, (at: 3, of: 20));
    expect(feedLines().single, {'source': 'list', 'kept': 20, 'dropped': 5});
  });

  test('the counter is the place from 1 and the list\'s length, following every move with a notification', () {
    final feed = make();
    expect(feed.counter, (at: 3, of: 5));
    final places = <({int at, int of})?>[];
    feed.addListener(() {
      if (places.lastOrNull != feed.counter) places.add(feed.counter);
    });
    feed
      ..moveNext()
      ..moveNext()
      ..movePrevious()
      ..movePrevious()
      ..movePrevious()
      ..movePrevious();
    expect(places, [for (final at in [4, 5, 4, 3, 2, 1]) (at: at, of: 5)]);
    expect(feed.counter, (at: 1, of: 5));
  });

  test('its ends are the feed\'s: no move past them, nothing opened, nothing asked, wantMore or not', () {
    host.bvid = bvOf(0);
    final first = make(index: 0);
    expect(first.previous, isNull);
    final before = notified;
    expect(first.movePrevious(), isFalse);
    expect((first.index, first.counter, notified), (0, (at: 1, of: 5), before));

    for (var move = 0; move < 4; move++) {
      expect(first.moveNext(), isTrue);
    }
    expect(first.next, isNull);
    expect(first.moveNext(), isFalse);
    first
      ..wantMore()
      ..wantMore();
    expect((first.index, first.counter), (4, (at: 5, of: 5)));
    expect(host.opened, hasLength(4));
    expect(first.loading, isFalse);
    expectNothingAsked();
  });

  testWidgets('in the pager, both ends resist and spring back', (tester) async {
    const frame = Duration(microseconds: 16667);
    final drag = StoryDrag();
    final pager = StoryPager(drag: drag, vsync: const TestVSync())..extent = 956;
    addTearDown(drag.dispose);
    host.bvid = bvOf(0);
    final feed = make(index: 0);
    pager.feed = feed;

    Future<void> settle() async {
      for (var i = 0; i < 100 && drag.moving; i++) {
        await tester.pump(frame);
      }
      expect(drag.moving, isFalse);
      expect(drag.offset, 0);
    }

    drag
      ..start()
      ..update(200);
    expect(drag.offset, closeTo(200 * StoryPagerTheme.resistance, 0.001));
    drag.end(1500);
    await settle();
    expect(host.opened, isEmpty);

    for (var move = 0; move < 4; move++) {
      expect(pager.moveNext(), isTrue);
      await settle();
    }
    expect(feed.counter, (at: 5, of: 5));
    drag
      ..start()
      ..update(-300);
    expect(drag.offset, closeTo(-300 * StoryPagerTheme.resistance, 0.001));
    drag.end(-1500);
    await settle();
    expect(pager.moveNext(), isFalse);
    expect(host.opened, hasLength(4));
    expect(feed.index, 4);
    expectNothingAsked();
    pager.dispose();
  });

  group('its plays', () {
    test('the card the page has open reports as the entered video, the rest as videos swiped to, from where the page '
        'was opened once its details are in', () {
      final feed = make();
      expect(feed.next!.source.historySource, 'story-series');
      expect(feed.current!.source.historySource, 'story-single');
      final before = notified;
      detailsIn();
      expect(notified, greaterThan(before));

      final entered = feed.current!.source;
      expect(entered.spmid, PlaySource.verticalPage);
      expect(entered.from, 'default-value');
      expect(entered.fromSpmid, 'from.the.route');
      expect((entered.trackId, entered.flowData), ('TRACK.R', '{"r":1}'));
      expect(entered.historySource, 'story-single');
      for (final (place, entry) in feed.entries.indexed) {
        if (place == tapped) continue;
        final source = entry.source;
        expect(source.spmid, PlaySource.verticalPage);
        expect(source.from, 'default-value');
        expect(source.fromSpmid, 'from.the.route');
        expect((source.trackId, source.flowData), (null, null), reason: 'the related cards carry no track data');
        expect(source.historySource, 'story-series');
        expect(entry.still, 'ff$place');
      }

      feed
        ..moveNext()
        ..movePrevious()
        ..movePrevious()
        ..moveNext();
      expect(host.opened.map((entry) => entry.bvid), [bvOf(3), bvOf(2), bvOf(1), bvOf(2)]);
      expect(host.openedEntered, [false, true, false, true], reason: 'the card tapped opens as the user\'s own');
      expect(host.opened[1].source.historySource, 'story-single');
      expect(host.opened[2].source.historySource, 'story-series');
    });

    test('the page\'s details stand in for the card tapped, keeping its first frame, and its part where they have '
        'none', () {
      final feed = make();
      detailsIn(cid: null);
      expect((feed.current!.title, feed.current!.cid, feed.current!.still), ('详情', 902, 'ff2'));
      detailsIn(cid: 950);
      expect((feed.current!.cid, feed.current!.still), (950, 'ff2'));
      expect(feed.current!.source.historySource, 'story-single');
      expect(bvids(feed), hasLength(5));
      expectNothingAsked();
    });

    test('a move before the details are in opens with what the cards had', () {
      final feed = make();
      feed.moveNext();
      expect(host.opened.single.source.historySource, 'story-series');
      expect(host.opened.single.source.fromSpmid, '');
    });
  });

  group('ahead, as StoryList does', () {
    VideoDetail detailOf(String bvid) => VideoDetail.fromJson({'bvid': bvid, 'aid': 1});

    Future<void> answerDetail(int at, VideoDetail answer) async {
      detailAnswers[at].complete(answer);
      await pumpEventQueue();
    }

    void plays(String bvid) => host
      ..framed = bvid
      ..comfortable = true
      ..changed();

    List<String> warmed() => [for (final (entry, _) in host.warms) entry.bvid];

    test('the next video\'s details at once and on each move, the next loaded ahead after the first frame, nothing '
        'past the last', () async {
      final feed = make(ahead: true, warms: true);
      expect(detailAsks, [bvOf(3)], reason: 'the next one only, as for the entered video today');
      final third = detailOf(bvOf(3));
      await answerDetail(0, third);
      expect(host.warms, isEmpty, reason: 'no first frame yet');
      plays(bvOf(tapped));
      expect(warmed(), [bvOf(3)]);
      expect(identical(host.warms.single.$2, third), isTrue);

      expect(feed.moveNext(), isTrue);
      expect(identical(host.openedWith.single, third), isTrue);
      expect(detailAsks, [bvOf(3), bvOf(4)]);
      await answerDetail(1, detailOf(bvOf(4)));
      plays(bvOf(3));
      expect(warmed(), [bvOf(3), bvOf(4)]);

      expect(feed.moveNext(), isTrue);
      plays(bvOf(4));
      expect(detailAsks, hasLength(2), reason: 'none after the last');
      expect(warmed(), hasLength(2));
      feed.settling(feed.previous);
      expect(warmed().last, bvOf(3), reason: 'let go towards the one before, its details kept as a neighbour');
      expectNothingAsked();
    });

    test('none while halted', () async {
      host.halted = true;
      final feed = make(ahead: true, warms: true);
      plays(bvOf(tapped));
      feed.moveNext();
      expect(detailAsks, isEmpty);
      expect(host.warms, isEmpty);
    });
  });

  group('given up', () {
    test('when the page opens a video the feed didn\'t: the feed starts over from it as today\'s', () {
      final feed = make();
      detailsIn();
      host.plays('BV1autonext0');
      expect(feed.entries, isEmpty);
      expect(feed.counter, isNull);
      expect(feed.listGiven, isFalse);
      expect(feed.official, isTrue, reason: 'under a token, the official feed');
      host
        ..playing = const StoryEntry(
          bvid: 'BV1autonext0',
          aid: 200,
          cid: 21,
          title: '',
          cover: '',
          ownerMid: 4,
          ownerName: '',
          source: PlaySource.unknown,
        )
        ..changed();
      expect(bvids(feed), ['BV1autonext0']);
      expect(officialAsks, [200]);
      expect(feed.current!.source.fromSpmid, 'from.the.route', reason: 'where 竖屏 was entered from is kept');
    });

    test('one of the list\'s too: it no longer holds what plays', () {
      final feed = make();
      host.plays(bvOf(4));
      expect(feed.counter, isNull);
      expect(feed.entries, isEmpty);
    });

    test('placed on the page\'s video when the card given isn\'t it; a list without it is today\'s feed', () {
      host.bvid = bvOf(4);
      final placed = make(index: 0);
      expect((placed.index, placed.counter), (4, (at: 5, of: 5)));

      host = FakeHost()..bvid = 'BV1elsewhere';
      final other = make();
      expect(other.listGiven, isFalse);
      expect(other.counter, isNull);
      expect(other.entries, isEmpty);
      expect(feedLines().last, {'source': 'list', 'kept': 0, 'dropped': 5});
    });
  });

  group('through the page\'s playback', () {
    const bv = 'BV1GJ411x7h7';
    const other = 'BV1xx411c7mD';
    const mobilePath = '/x/report/heartbeat/mobile';
    const historyPath = '/x/v2/history/report';
    const ok = '{"code":0,"message":"0","ttl":1}';

    testWidgets('the route\'s list from the card tapped asks no feed, and a swipe reports as the related lists\' do',
        (tester) async {
      final http = Canned.http()
        ..routes[mobilePath] = (200, ok)
        ..routes[historyPath] = (200, ok);
      final savedPrefs = PlayerPrefs.shared;
      final savedPolicy = AutoplayPolicy.shared;
      PlayerPrefs.shared = PlayerPrefs.memory();
      AutoplayPolicy.shared = AutoplayPolicy.fixed();
      addTearDown(() {
        PlayerPrefs.shared = savedPrefs;
        AutoplayPolicy.shared = savedPolicy;
      });
      final logger = Logger(session: 'test');
      final environment = await AppEnvironment.load(
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
      final time = ManualClock(10000);
      final players = <FakePlayer>[];
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
      final services = AppServices(
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

      Future<void> frames([int n = 10]) async {
        for (var i = 0; i < n; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      Future<void> plays(FakePlayer player) async {
        player.emit(const StatusChanged(PlayerStatus.playing));
        time.advance(PlaybackClock.jumpSettleMs);
        player.emit(PositionChanged(seconds: 3, hostMs: time.clock.nowMs(), rate: 1));
        await frames(2);
      }

      Map<String, String> form(HTTPRequest request) => Uri.splitQueryString(utf8.decode(request.body!));
      List<Map<String, String>> starts() => [
        for (final request in http.to(mobilePath))
          if (form(request)['start_ts'] == '0') form(request),
      ];
      List<String?> places() => [for (final request in http.to(historyPath)) form(request)['source']];

      final story = RelatedStory(cards: [listed(0), listed(tapped).copyAs(bv), listed(1).copyAs(other)], index: 1);
      final page = PagePlayback(
        services: services,
        route: VideoRoute(bvid: bv, source: fromRoute, relatedStory: story),
        createSession: pageSession,
        restorePage: (route) => const SizedBox(),
        storyFeed: (playback) => relatedStoryFeed(playback, story),
      )..start();
      final feed = page.beginStory();
      expect([for (final entry in feed.entries) entry.bvid], [bvOf(0), bv, other]);
      expect((feed.index, feed.counter), (1, (at: 2, of: 3)));

      await frames();
      final player = players.single;
      await plays(player);
      expect(starts().single['spmid'], PlaySource.verticalPage);
      expect(starts().single['auto_play'], '0');

      http
        ..routes[Canned.viewPath] = (200, otherView)
        ..routes[Canned.signedViewPath] = (200, otherView);
      expect(feed.moveNext(), isTrue);
      await frames();
      await plays(player);
      expect(page.bvid, other);
      final swiped = starts().last;
      expect(swiped['aid'], '80433023');
      expect(swiped['spmid'], PlaySource.verticalPage);
      expect(swiped['from'], 'default-value');
      expect(swiped['from_spmid'], 'from.the.route');
      expect(swiped['track_id'], '');
      expect(swiped['auto_play'], '99');
      expect(feed.counter, (at: 3, of: 3));
      expect(http.to('/x/v2/feed/index/story'), isEmpty, reason: 'the official feed is never asked');
      expect([for (final entry in feed.entries) entry.bvid], [bvOf(0), bv, other], reason: 'nothing added');

      page.close();
      await frames(4);
      expect(places(), ['story-single', 'story-series']);
    });
  });
}

/// The other video, as the signed view answers for it.
final otherView = Canned.view.replaceAll('BV1GJ411x7h7', 'BV1xx411c7mD').replaceAll('80433022', '80433023');

class _NoLogin implements LoginGate {
  @override
  Future<bool> request(BuildContext context) async => false;
}

extension on VideoCard {
  VideoCard copyAs(String bvid) => VideoCard(
    aid: aid,
    bvid: bvid,
    cid: 0,
    title: title,
    cover: cover,
    duration: duration,
    ownerMid: ownerMid,
    ownerName: ownerName,
    views: views,
    danmaku: danmaku,
    likes: likes,
    width: width,
    height: height,
    firstFrame: firstFrame,
  );
}
