import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/danmaku.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/danmaku/block_rule_store.dart';
import 'package:bilifast/danmaku/danmaku_settings_store.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/live/fake_live_api.dart';
import 'package:bilifast/live/live_entry.dart';
import 'package:bilifast/live/room/live_room_model.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/fake_keychain.dart';
import '../../home/fake_login_gate.dart';
import '../../playback/fakes.dart';
import '../../video/mixed_lines.dart' show appTheme;

/// The account the harness is logged in as (Canned's).
const selfUid = 12345;

/// A room whose feed the test drives and whose sends it records; [failure] makes the next send throw.
class FakeRoom extends LiveRoomModel {
  FakeRoom({required super.api}) : super(entry: const LiveRoomEntry(roomId: 7734200), loggedIn: () => true);

  bool signedIn = true;

  final _flying = StreamController<LiveChatMessage>.broadcast(sync: true);
  final sent = <String>[];
  final sentEmotes = <LiveEmote>[];
  Object? failure;
  Completer<void>? hold;

  @override
  bool Function() get loggedIn =>
      () => signedIn;

  @override
  Stream<LiveChatMessage> get flying => _flying.stream;

  void fly(LiveChatMessage message) => _flying.add(message);

  @override
  Future<void> send(String text) async {
    await hold?.future;
    final error = failure;
    if (error != null) {
      failure = null;
      throw error;
    }
    sent.add(text);
  }

  @override
  Future<void> sendEmote(LiveEmote emote) async {
    final error = failure;
    if (error != null) {
      failure = null;
      throw error;
    }
    sentEmotes.add(emote);
  }

  @override
  void dispose() {
    unawaited(_flying.close());
    super.dispose();
  }
}

final class LiveHarness {
  LiveHarness(this.services, this.loginGate, this.pageApi, this.settings);

  final AppServices services;
  final FakeLoginGate loginGate;
  final FakePageApi pageApi;
  final DanmakuSettingsStore settings;
}

Future<LiveHarness> liveHarness({List<BlockRule> rules = const []}) async {
  final logger = Logger(session: 'test');
  final http = Canned.http(loggedIn: true)..routes[Canned.navPath] = (200, Canned.navLoggedIn);
  final environment = await AppEnvironment.load(
    keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
    http: http,
    logger: logger,
  );
  await environment.refreshAccount();
  final playback = AppPlayback(() async => throw UnimplementedError());
  addTearDown(playback.dispose);
  final loginGate = FakeLoginGate();
  final pageApi = FakePageApi()..blockRules = List.of(rules);
  final settings = DanmakuSettingsStore.memory();
  final blockRules = BlockRuleStore(api: pageApi, isLoggedIn: () => true);
  await blockRules.refresh(force: true);
  final services = AppServices(
    environment: environment,
    playback: playback,
    recents: await RecentStore.load(null, logger: logger),
    loginGate: loginGate,
    pageApi: pageApi,
    danmakuSettings: settings,
    blockRules: blockRules,
  );
  return LiveHarness(services, loginGate, pageApi, settings);
}

/// [child] in the app's theme over the harness, the view sized as the phone ([size], 1 px per pt).
Future<void> pumpLive(
  WidgetTester tester,
  LiveHarness harness,
  Widget child, {
  Size size = const Size(440, 956),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      builder: (context, child) => AppScope(services: harness.services, child: child!),
      // The room page gives the input the whole screen, the keyboard's inset left in its MediaQuery.
      home: Scaffold(backgroundColor: Colors.black, resizeToAvoidBottomInset: false, body: child),
    ),
  );
}

LiveChatMessage danmaku(
  String text, {
  String id = '',
  int uid = 99,
  int mode = 1,
  int color = 0xFFFFFFFF,
  LiveEmote? bigEmote,
}) => LiveChatMessage(
  id: id.isEmpty ? text : id,
  user: LiveUser(uid: uid, name: '观众$uid'),
  text: text,
  time: DateTime(2026, 11, 17, 20),
  mode: mode,
  color: color,
  bigEmote: bigEmote,
);

/// The room's packages: 全部表情's inline emotes (bracketed) and a package of whole-message ones.
final demoPackages = [
  LiveEmotePackage(
    id: 1,
    name: '通用表情',
    icon: '',
    emotes: [for (var i = 0; i < 12; i++) LiveEmote(text: '[表情$i]', url: '', unique: 'emoji_$i')],
  ),
  const LiveEmotePackage(
    id: 2,
    name: '房间专属',
    icon: '',
    emotes: [
      LiveEmote(text: '赞', url: '', unique: 'room_zan'),
      LiveEmote(text: '冲', url: '', unique: 'room_chong'),
    ],
  ),
];

FakeLiveApi demoApi() => FakeLiveApi(emotePackages: demoPackages);

/// Lets a toast run out, so no timer is left when the test ends.
Future<void> toastGone(WidgetTester tester) async {
  for (final wait in const [Duration(milliseconds: 500), Duration(seconds: 3), Duration(seconds: 1)]) {
    await tester.pump(wait);
  }
}

Finder byKey(String key) => find.byKey(ValueKey(key));
