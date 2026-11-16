import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/live/fake_live_api.dart';
import 'package:bilifast/live/live_entry.dart';
import 'package:bilifast/live/player/live_player_controller.dart';
import 'package:bilifast/live/player/live_player_prefs.dart';
import 'package:bilifast/live/room/live_room_model.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/fake_keychain.dart';
import '../../home/fake_login_gate.dart';
import '../../playback/fakes.dart';
import '../../support/fake_player.dart';

/// 207's box on KaiC's 440 pt screen, under its 62 pt safe area, as the room page places it.
const liveBoxTop = 62 + LiveRoomTheme.boxTop;
const liveBoxBottom = liveBoxTop + 440 * 9 / 16;

const qualities = [
  LiveQuality(qn: 10000, name: '1080P 原画 (高帧率)'),
  LiveQuality(qn: 400, name: '1080P 蓝光'),
  LiveQuality(qn: 250, name: '720P 超清'),
];

/// A play info at [qn]; each call makes a new one, as each answer from the room is.
LivePlayInfo playAt(int qn, {int ask = 0}) => LivePlayInfo(
  roomId: 1000002,
  uid: 2000002,
  status: LiveStatus.live,
  url: Uri.parse('https://example.invalid/live/$qn/$ask/index.m3u8'),
  qualities: qualities,
  currentQn: qn,
);

/// A room driven by hand: [go] moves it, and its calls land in [asked].
class FakeRoom extends LiveRoomModel {
  FakeRoom({bool Function()? loggedIn})
    : super(
        api: FakeLiveApi(),
        entry: const LiveRoomEntry(roomId: 1000002, title: '演示比赛 AA vs BB', anchorName: '演示 Streamer'),
        loggedIn: loggedIn ?? () => true,
      );

  LiveRoomState stateValue = LiveRoomState.loading;
  LivePlayInfo? playValue;
  LiveRoomInfo? infoValue;
  bool followingValue = false;
  int asks = 0;
  final asked = <String>[];

  /// Makes [refreshStream] throw.
  Object? refreshError;

  /// Makes [setQuality] throw.
  Object? qualityError;

  /// Makes [setFollowing] throw.
  Object? followError;

  void go(LiveRoomState state, {LivePlayInfo? play}) {
    stateValue = state;
    if (play != null) playValue = play;
    notifyListeners();
  }

  @override
  LiveRoomState get state => stateValue;

  @override
  LivePlayInfo? get play => playValue;

  @override
  LiveRoomInfo? get info => infoValue;

  @override
  int get likeCount => 124000;

  @override
  int get onlineCount => 9382;

  @override
  List<String> get topFaces => const ['', '', ''];

  @override
  bool get following => followingValue;

  @override
  Future<void> setQuality(int qn) async {
    asked.add('quality $qn');
    if (qualityError case final error?) throw error;
    playValue = playAt(qn == 0 ? 10000 : qn, ask: ++asks);
    notifyListeners();
  }

  @override
  Future<void> refreshStream() async {
    asked.add('refresh');
    if (refreshError case final error?) throw error;
    playValue = playAt(playValue?.currentQn ?? 10000, ask: ++asks);
    notifyListeners();
  }

  @override
  Future<void> retry() async {
    asked.add('retry');
    go(LiveRoomState.live, play: playAt(10000, ask: ++asks));
  }

  @override
  void like() => asked.add('like');

  @override
  Future<void> setFollowing(bool on) async {
    asked.add('follow $on');
    if (followError case final error?) throw error;
    followingValue = on;
    notifyListeners();
  }
}

/// What a test drives: the services, the room, the player the controller makes and the controller itself.
final class LiveRig {
  LiveRig(this.services, this.room, this.player, this.controller, this.gate, this.shared);

  final AppServices services;
  final FakeRoom room;
  final FakePlayer player;
  final LivePlayerController controller;
  final FakeLoginGate gate;
  final List<Uri> shared;
}

Future<LiveRig> liveRig({
  bool loggedIn = true,
  LivePlayerPrefs? prefs,
  PlayerPrefs? playerPrefs,
  bool muted = false,
  FakePlayer? player,
}) async {
  final environment = await AppEnvironment.load(
    keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
    http: Canned.http(),
    logger: Logger(session: 'test'),
  );
  final playback = AppPlayback(() => Completer<PlaybackController>().future, muted: muted);
  addTearDown(playback.dispose);
  final gate = FakeLoginGate();
  final services = AppServices(
    environment: environment,
    playback: playback,
    recents: await RecentStore.load(null, logger: Logger(session: 'test')),
    loginGate: gate,
  );
  final room = FakeRoom(loggedIn: () => loggedIn);
  final made = player ?? FakePlayer();
  final shared = <Uri>[];
  final controller = LivePlayerController(
    room: room,
    services: services,
    createPlayer: () async => made,
    prefs: prefs ?? LivePlayerPrefs.memory(),
    playerPrefs: playerPrefs ?? PlayerPrefs.memory(),
    share: (link) async {
      shared.add(link);
      return true;
    },
    coverFile: (url) async => '/covers/room.jpg',
    stallLimit: const Duration(seconds: 2),
  );
  // Torn down last in, first out: the controller lets go of the room before it goes.
  addTearDown(room.dispose);
  addTearDown(controller.dispose);
  return LiveRig(services, room, made, controller, gate, shared);
}
