import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/route_observer.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/live/fake_live_api.dart';
import 'package:bilifast/live/live_entry.dart';
import 'package:bilifast/live/player/live_player_controller.dart';
import 'package:bilifast/live/room/live_chat_item.dart';
import 'package:bilifast/live/room/live_room_model.dart';
import 'package:bilifast/live/room/live_room_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/fake_keychain.dart';
import '../../home/fake_login_gate.dart';
import '../../playback/fakes.dart';

/// The moment every test's clock reads.
final roomNow = DateTime(2026, 11, 17, 9, 59);

const roomEntry = LiveRoomEntry(roomId: 1001, uid: 2001, title: '测试直播间', anchorName: '入口主播');

/// A made-up room's info: no real names or ids.
LiveRoomInfo roomInfo({bool following = false, List<String> chips = const ['热门榜', '网游人气第 28']}) => LiveRoomInfo(
  roomId: 1001,
  uid: 2001,
  title: '测试比赛 A vs B',
  anchorName: '测试主播',
  verify: LiveVerify.personal,
  description: '测试公告',
  rankChips: chips,
  following: following,
);

LiveUser roomUser(int i, {int wealth = 0, LiveMedal? medal, int guard = 0, int nameColor = 0}) =>
    LiveUser(uid: 3000 + i, name: '观众$i', wealthLevel: wealth, medal: medal, guardLevel: guard, nameColor: nameColor);

LiveChatDanmaku roomDanmaku(
  int i, {
  String? text,
  LiveUser? user,
  Map<String, LiveEmote> emotes = const {},
  LiveEmote? big,
}) => LiveChatDanmaku(
  LiveChatMessage(
    id: 'm$i',
    user: user ?? roomUser(i),
    text: text ?? '弹幕$i',
    time: roomNow,
    emotes: emotes,
    bigEmote: big,
  ),
);

LiveSuperChat roomSuperChat(int id, {int price = 30, Duration left = const Duration(seconds: 30)}) => LiveSuperChat(
  id: id,
  user: roomUser(id, guard: 2, medal: const LiveMedal(name: '测试', level: 8)),
  message: '醒目留言$id',
  price: price,
  start: roomNow.subtract(const Duration(seconds: 30)),
  end: roomNow.add(left),
  background: 0xFFEDF5FF,
  backgroundBottom: 0xFF2A60B2,
);

/// A room model the test drives by hand: its answers are fields, and what the page asks of it is recorded.
class TestRoomModel extends LiveRoomModel {
  TestRoomModel({this._info, this._following = false})
    : super(api: FakeLiveApi(), entry: roomEntry, loggedIn: () => true, now: () => roomNow);

  LiveRoomInfo? _info;
  bool _following;
  int likes = 124000;
  int online = 9349;
  List<String> faces = const ['', '', ''];
  final chatList = ValueNotifier<List<LiveChatItem>>(const []);
  final superChatList = ValueNotifier<List<LiveSuperChat>>(const []);

  /// Danmaku for the flying layer only, with no chat row.
  final flyingFeed = StreamController<LiveChatMessage>.broadcast();

  final shown = <bool>[];
  final follows = <bool>[];
  int starts = 0;
  Object? followError;

  set info(LiveRoomInfo? value) {
    _info = value;
    notifyListeners();
  }

  @override
  LiveRoomInfo? get info => _info;

  @override
  int get likeCount => likes;

  @override
  int get onlineCount => online;

  @override
  List<String> get topFaces => faces;

  @override
  bool get following => _following;

  @override
  ValueListenable<List<LiveChatItem>> get chat => chatList;

  @override
  ValueListenable<List<LiveSuperChat>> get superChats => superChatList;

  @override
  Stream<LiveChatMessage> get flying => flyingFeed.stream;

  @override
  Future<void> start() async => starts++;

  @override
  void setShown(bool shown) => this.shown.add(shown);

  @override
  Future<void> setFollowing(bool on) async {
    follows.add(on);
    if (followError case final error?) throw error;
    _following = on;
    notifyListeners();
  }

  @override
  void dispose() {
    chatList.dispose();
    superChatList.dispose();
    unawaited(flyingFeed.close());
    super.dispose();
  }
}

/// The player as the page reaches it: full screen is a field, and what the page asks is recorded.
class TestPlayerController extends LivePlayerController {
  TestPlayerController({required super.room, required super.services});

  bool full = false;
  final covered = <bool>[];
  final fullScreenAsks = <bool>[];
  int starts = 0;
  int shares = 0;
  int pips = 0;
  bool disposed = false;

  @override
  bool get fullScreen => full;

  @override
  Future<void> start() async => starts++;

  @override
  Future<void> setFullScreen(bool on) async {
    fullScreenAsks.add(on);
    full = on;
    notifyListeners();
  }

  @override
  void setCovered(bool covered) => this.covered.add(covered);

  @override
  Future<void> share(BuildContext context) async => shares++;

  @override
  Future<void> startPictureInPicture() async => pips++;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

Future<AppServices> roomServices({bool loggedIn = true, FakeLoginGate? gate, FakeLiveApi? liveApi}) async {
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
    loginGate: gate ?? FakeLoginGate(),
    liveApi: liveApi ?? FakeLiveApi(),
  );
}

/// What a pumped room hands back: its model and player, and the navigator to push and pop over it.
class RoomHarness {
  RoomHarness({this.model});

  TestRoomModel? model;
  TestPlayerController? controller;
  final navigator = GlobalKey<NavigatorState>();
}

/// The room pushed over a blank home, the view as KaiC's iPhone at 1× (or turned), inside the app's scope.
Future<RoomHarness> pumpRoom(
  WidgetTester tester,
  AppServices services, {
  TestRoomModel? model,
  bool landscape = false,
  bool realModel = false,
}) async {
  tester.view
    ..physicalSize = landscape ? const Size(956, 440) : const Size(440, 956)
    ..devicePixelRatio = 1
    ..padding = landscape
        ? const FakeViewPadding(left: 62, right: 62, bottom: 21)
        : const FakeViewPadding(top: 62, bottom: 34);
  addTearDown(tester.view.reset);
  final harness = RoomHarness(model: model ?? (realModel ? null : TestRoomModel(info: roomInfo())));
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: harness.navigator,
      navigatorObservers: [pageRoutes],
      builder: (context, page) => AppScope(services: services, child: page!),
      home: const Scaffold(body: SizedBox.expand()),
    ),
  );
  unawaited(
    harness.navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => LiveRoomPage(
          entry: roomEntry,
          createModel: realModel ? null : (_, _) => harness.model!,
          createController: (services, room) =>
              harness.controller = TestPlayerController(room: room, services: services),
        ),
      ),
    ),
  );
  await settle(tester);
  return harness;
}

Future<void> settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lets a toast run out, so its timer is not left pending.
Future<void> toastGone(WidgetTester tester) => settle(tester, 60);
