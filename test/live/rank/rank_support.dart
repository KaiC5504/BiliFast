import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/live/fake_live_api.dart';
import 'package:bilifast/live/live_entry.dart';
import 'package:bilifast/live/rank/live_rank_sheet.dart';
import 'package:bilifast/live/room/live_overlays.dart';
import 'package:bilifast/live/room/live_room_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/fake_keychain.dart';
import '../../home/fake_login_gate.dart';
import '../../playback/fakes.dart';

const roomId = 100;
const anchorUid = 7;

/// A made-up viewer: no real names or ids.
LiveUser viewer(int uid, {String? name, int wealth = 0, LiveMedal? medal, int guard = 0}) =>
    LiveUser(uid: uid, name: name ?? '测试观众$uid', wealthLevel: wealth, medal: medal, guardLevel: guard);

const testMedal = LiveMedal(name: '测试', level: 21, guardLevel: 3);

List<LiveRankEntry> rankEntries(int count, {int from = 1, int score = 9000}) => [
  for (var rank = from; rank < from + count; rank++)
    LiveRankEntry(
      rank: rank,
      user: viewer(rank, wealth: 20, medal: testMedal),
      score: score - rank,
    ),
];

/// [FakeLiveApi] with 在线榜 and 大航海 pages past the first, and the anchor each call named.
class PagedLiveApi extends FakeLiveApi {
  PagedLiveApi({super.rankPage, super.guardPages, this.moreRank = const [], this.moreGuards = const {}});

  /// 在线榜's pages from 2.
  final List<LiveRankPage> moreRank;

  /// Each 大航海 tab's pages from 2.
  final Map<LiveGuardTab, List<LiveGuardPage>> moreGuards;

  final anchors = <int>[];

  @override
  Future<LiveRankPage> rank(int roomId, {required int anchorUid, required int page}) async {
    anchors.add(anchorUid);
    final first = await super.rank(roomId, anchorUid: anchorUid, page: page);
    if (page == 1) return first;
    return page - 2 < moreRank.length ? moreRank[page - 2] : const LiveRankPage(entries: []);
  }

  @override
  Future<LiveGuardPage> guards(
    int roomId, {
    required int anchorUid,
    required LiveGuardTab tab,
    required int page,
  }) async {
    anchors.add(anchorUid);
    final first = await super.guards(roomId, anchorUid: anchorUid, tab: tab, page: page);
    if (page == 1) return first;
    final more = moreGuards[tab] ?? const [];
    return page - 2 < more.length ? more[page - 2] : const LiveGuardPage(entries: []);
  }

  int count(String prefix) => calls.where((call) => call.startsWith(prefix)).length;
}

/// A room whose info a test sets, as the room's own calls would.
class TestRoom extends LiveRoomModel {
  TestRoom({required super.api, required super.entry, required super.loggedIn});

  LiveRoomInfo? _info;

  @override
  LiveRoomInfo? get info => _info;

  set info(LiveRoomInfo? info) {
    _info = info;
    notifyListeners();
  }
}

/// The app's services, the account logged in (Canned's, with a face) or out.
Future<AppServices> rankServices({bool loggedIn = true}) async {
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
  );
}

/// A room page stand-in: a black room with the sheet over it while [LiveOverlays] says 高能榜.
class RankHarness {
  RankHarness({required this.api, this.loggedIn = true, int uid = anchorUid, LiveRoomModel? room})
    : room =
          room ??
          LiveRoomModel(
            api: api,
            entry: LiveRoomEntry(roomId: roomId, uid: uid),
            loggedIn: () => loggedIn,
          );

  final PagedLiveApi api;
  final bool loggedIn;
  final LiveRoomModel room;
  final overlays = LiveOverlays()..open(LiveOverlay.rank);

  Widget page({bool landscape = false}) => Stack(
    children: [
      const Positioned.fill(
        child: ColoredBox(key: ValueKey('room'), color: Color(0xFF000000)),
      ),
      Positioned.fill(
        child: ValueListenableBuilder(
          valueListenable: overlays,
          builder: (context, overlay, _) => overlay == LiveOverlay.rank
              ? LiveRankSheet(room: room, overlays: overlays, landscape: landscape)
              : const SizedBox.shrink(),
        ),
      ),
    ],
  );
}

/// The phone's screen at 1×, upright (440×956, the home indicator's 34) or turned (956×440, 21).
Future<void> pumpRank(WidgetTester tester, AppServices services, RankHarness harness, {bool landscape = false}) async {
  tester.view
    ..physicalSize = landscape ? const Size(956, 440) : const Size(440, 956)
    ..devicePixelRatio = 1
    ..padding = FakeViewPadding(bottom: landscape ? 21 : 34);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, page) => AppScope(services: services, child: page!),
      home: Scaffold(body: harness.page(landscape: landscape)),
    ),
  );
  await settle(tester);
}

Future<void> settle(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lets a toast run out, so its timer is not left pending.
Future<void> toastGone(WidgetTester tester) => settle(tester, 60);

Finder byKey(String key) => find.byKey(ValueKey(key));
