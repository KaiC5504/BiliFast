import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/live.dart';

import 'live_api.dart';

/// Made-up answers for tests and `--fake-account` on the PC: no call leaves the machine. [calls] lists what was asked,
/// in order (`feed page=1`, `send 123`); [failures] makes a call throw and [holds] keeps it waiting, keyed by the call
/// or by its name alone (`feed`).
class FakeLiveApi implements LiveApi {
  FakeLiveApi({
    this.feedPages = const [],
    this.areaPages = const {},
    this.followingPages = const [],
    this.plays = const {},
    this.rooms = const {},
    this.histories = const {},
    this.superChatLists = const {},
    this.rankPage = const LiveRankPage(entries: []),
    this.guardPages = const {},
    this.emotePackages = const [],
    LiveChannel Function(int roomId)? channels,
  }) : _channels = channels ?? ((_) => FakeLiveChannel());

  /// The `--fake-account` demo: a tab, a room and a chat fed by a timer. Filled in by the room model's builder.
  factory FakeLiveApi.demo() => FakeLiveApi();

  final List<LiveFeedPage> feedPages;
  final Map<int, List<LiveCardPage>> areaPages;
  final List<LiveCardPage> followingPages;
  final Map<int, LivePlayInfo> plays;
  final Map<int, LiveRoomInfo> rooms;
  final Map<int, List<LiveChatMessage>> histories;
  final Map<int, List<LiveSuperChat>> superChatLists;
  final LiveRankPage rankPage;
  final Map<LiveGuardTab, LiveGuardPage> guardPages;
  final List<LiveEmotePackage> emotePackages;
  final LiveChannel Function(int roomId) _channels;

  final calls = <String>[];
  final failures = <String, Object>{};
  final holds = <String, Completer<void>>{};

  Future<T> _answer<T>(String call, T Function() value) async {
    calls.add(call);
    final name = call.split(' ').first;
    final hold = holds[call] ?? holds[name];
    if (hold != null) await hold.future;
    final failure = failures[call] ?? failures[name];
    if (failure != null) throw failure;
    return value();
  }

  static T _page<T>(List<T> pages, int page, T empty) => page - 1 < pages.length ? pages[page - 1] : empty;

  @override
  Future<LiveFeedPage> feed({required int page}) =>
      _answer('feed page=$page', () => _page(feedPages, page, LiveFeedPage(page: page)));

  @override
  Future<LiveCardPage> area(LiveArea area, {required int page}) => _answer(
    'area ${area.id} page=$page',
    () => _page(areaPages[area.id] ?? const [], page, LiveCardPage(page: page, cards: const [])),
  );

  @override
  Future<LiveCardPage> following({required int page}) =>
      _answer('following page=$page', () => _page(followingPages, page, LiveCardPage(page: page, cards: const [])));

  @override
  Future<LivePlayInfo> playInfo(int roomId, {int? qn}) => _answer(
    'playInfo $roomId qn=${qn ?? '-'}',
    () => plays[roomId] ?? LivePlayInfo(roomId: roomId, uid: 0, status: LiveStatus.offline),
  );

  @override
  Map<String, String> get streamHeaders => const {};

  @override
  Future<LiveRoomInfo> roomInfo(int roomId) =>
      _answer('roomInfo $roomId', () => rooms[roomId] ?? LiveRoomInfo(roomId: roomId, uid: 0, title: ''));

  @override
  Future<List<LiveChatMessage>> history(int roomId) => _answer('history $roomId', () => histories[roomId] ?? const []);

  @override
  Future<List<LiveSuperChat>> superChats(int roomId) =>
      _answer('superChats $roomId', () => superChatLists[roomId] ?? const []);

  @override
  Future<LiveRankPage> rank(int roomId, {required int anchorUid, required int page}) =>
      _answer('rank $roomId page=$page', () => page == 1 ? rankPage : const LiveRankPage(entries: []));

  @override
  Future<LiveGuardPage> guards(int roomId, {required int anchorUid, required LiveGuardTab tab, required int page}) =>
      _answer(
        'guards $roomId ${tab.name} page=$page',
        () => page == 1 ? guardPages[tab] ?? const LiveGuardPage(entries: []) : const LiveGuardPage(entries: []),
      );

  @override
  Future<List<LiveEmotePackage>> emotes(int roomId) => _answer('emotes $roomId', () => emotePackages);

  @override
  Future<LiveChannel> channel(int roomId) => _answer('channel $roomId', () => _channels(roomId));

  @override
  Future<void> send(int roomId, String text) => _answer('send $roomId', () {});

  @override
  Future<void> sendEmote(int roomId, LiveEmote emote) => _answer('sendEmote $roomId ${emote.unique}', () {});

  @override
  Future<void> like(int roomId, {required int anchorUid, required int clicks}) =>
      _answer('like $roomId clicks=$clicks', () {});

  @override
  Future<void> enter(int roomId) => _answer('enter $roomId', () {});

  @override
  Future<void> follow(int mid, {required bool on}) => _answer('follow $mid on=$on', () {});
}

/// A danmaku feed tests drive by hand: [emit] and [setState]; [starts] and [closes] count the calls.
class FakeLiveChannel implements LiveChannel {
  final _events = StreamController<LiveEvent>.broadcast();
  final _states = StreamController<LiveSocketState>.broadcast();
  int starts = 0;
  int closes = 0;

  @override
  Stream<LiveEvent> get events => _events.stream;

  @override
  Stream<LiveSocketState> get states => _states.stream;

  void emit(LiveEvent event) => _events.add(event);

  void setState(LiveSocketState state) => _states.add(state);

  @override
  Future<void> start() async {
    starts++;
    _states.add(LiveSocketState.open);
  }

  @override
  Future<void> close() async {
    closes++;
    _states.add(LiveSocketState.closed);
  }
}
