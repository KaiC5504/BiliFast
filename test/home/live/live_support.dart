import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/feed_inline_player.dart';
import 'package:bilifast/home/live/live_inline_player.dart';
import 'package:bilifast/home/live/live_tab.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/live/fake_live_api.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player/player_factory.dart' as players;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/fake_keychain.dart';
import '../../playback/fakes.dart';
import '../../support/fake_player.dart';
import '../fake_login_gate.dart';

/// A made-up room: no real titles, names or ids.
LiveCard liveCard(
  int i, {
  String? title,
  String? name,
  String area = '测试分区',
  LiveBadge? badge,
  String corner = '',
  LiveVerify verify = LiveVerify.none,
}) => LiveCard(
  roomId: 9000 + i,
  uid: 500 + i,
  title: title ?? '测试直播间 $i',
  cover: '',
  uname: name ?? '测试主播$i',
  areaName: area,
  watchedText: '${i + 1}.2万',
  likeText: '${i + 3}',
  badge: badge,
  cornerIcon: corner,
  verify: verify,
);

List<LiveCard> liveCards(int count, {int from = 0}) => [for (var i = from; i < from + count; i++) liveCard(i)];

const liveAreas = [
  LiveArea(id: 11, parentId: 1, name: '聊天室'),
  LiveArea(id: 12, parentId: 1, name: '颜值'),
  LiveArea(id: 13, parentId: 9, name: '虚拟主播'),
];

/// The feed's first page: two big rooms, one followed room live, the areas and [count] rooms.
LiveFeedPage liveFeedPage({
  int count = 20,
  bool following = true,
  bool hasMore = true,
  List<LiveBigCard>? big,
  int followingTotal = 1,
}) => LiveFeedPage(
  page: 1,
  bigCards:
      big ??
      [
        LiveBigCard(card: liveCard(100, title: '大卡直播间 甲')),
        LiveBigCard(
          card: liveCard(101, title: '大卡直播间 乙'),
          rankText: '人气榜TOP·2',
          rankValue: '2009助力值',
        ),
      ],
  following: following ? [liveCard(200, name: '关注的主播', title: '关注的直播间', verify: LiveVerify.personal)] : const [],
  followingTotal: following ? followingTotal : 0,
  areas: liveAreas,
  cards: liveCards(count),
  hasMore: hasMore,
);

/// The app's services as 直播 reaches them, the account logged in or out, the live calls on [api].
Future<AppServices> liveServices({required FakeLiveApi api, bool loggedIn = true}) async {
  final logger = Logger(session: 'test');
  final environment = await AppEnvironment.load(
    keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
    http: Canned.http(loggedIn: loggedIn),
    logger: logger,
  );
  await environment.refreshAccount();
  final playback = AppPlayback(() async => throw UnimplementedError());
  addTearDown(playback.dispose);
  return AppServices(
    environment: environment,
    playback: playback,
    recents: await RecentStore.load(null, logger: logger),
    loginGate: FakeLoginGate(),
    liveApi: api,
  );
}

/// The players the carousel makes, newest last, in place of real ones; put back after the test.
class LivePlayers {
  LivePlayers() {
    LiveInlinePlayback.createPlayer = () async {
      final player = FakePlayer();
      made.add(player);
      return player;
    };
    addTearDown(() {
      LiveInlinePlayback.createPlayer = players.createPlayer;
      FeedInlineChoices.reset();
    });
  }

  final made = <BiliPlayer>[];

  FakePlayer get last => made.last as FakePlayer;
}

/// Drives a [LiveTab] on its own: on screen or not, 首页's taps.
class LiveHarness {
  LiveHarness({FakeLiveApi? api}) : api = api ?? FakeLiveApi(feedPages: [liveFeedPage()]);

  final FakeLiveApi api;
  final offset = ValueNotifier<double>(0);
  final reloads = ValueNotifier(0);
  final active = ValueNotifier(true);

  void tapHome() => reloads.value++;

  Widget tab() => ValueListenableBuilder(
    valueListenable: active,
    builder: (context, active, _) => LiveTab(active: active, scrollOffset: offset, reloads: reloads, api: api),
  );
}

/// [child] filling the phone's 440 × 956 view at 1× with the home indicator's inset, inside the app's scope.
Future<void> pumpLive(WidgetTester tester, AppServices services, Widget child) async {
  tester.view
    ..physicalSize = const Size(440, 956)
    ..devicePixelRatio = 1
    ..padding = const FakeViewPadding(bottom: 34);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, page) => AppScope(services: services, child: page!),
      home: Scaffold(body: child),
    ),
  );
}

Future<void> settle(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lets a toast run out, so its timer is not left pending.
Future<void> toastGone(WidgetTester tester) => settle(tester, 60);
