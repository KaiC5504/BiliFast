import 'dart:async';
import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bili_core/live.dart';

import 'demo_live_stream.dart';
import 'live_api.dart';

/// Made-up answers for tests and `--fake-account` on the PC: no call leaves the machine. [calls] lists what was asked,
/// in order (`feed page=1`, `send 123`); [failures] makes a call throw and [holds] keeps it waiting, keyed by the call
/// or by its name alone (`feed`). A play info asked at a `qn` the room offers answers at that quality.
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

  /// The `--fake-account` demo: 205's tab (three big cards, one followed room, eight areas, two pages of 推荐), and
  /// every room answering as one demo room, dated from [now] at each call, its chat fed by [FakeLiveChannel.demo].
  /// Names are 演示…, every text made up, covers, faces and emotes empty so nothing is fetched. On Windows its stream
  /// is the repo's HLS test clip looped as a live stream ([DemoLiveServer], on loopback); elsewhere, and in tests, it
  /// has none.
  factory FakeLiveApi.demo({DateTime Function()? now}) {
    final clock = now ?? DateTime.now;
    return FakeLiveApi(
      feedPages: [_Demo.feedPage(1), _Demo.feedPage(2)],
      areaPages: {
        for (final area in _Demo.areas)
          if (!area.isRecommend) area.id: [_Demo.areaPage(area)],
      },
      followingPages: [
        LiveCardPage(page: 1, cards: [_Demo.followed], total: 1),
      ],
      rankPage: _Demo.rank,
      guardPages: _Demo.guards,
      emotePackages: _Demo.emotes,
      channels: (_) => FakeLiveChannel.demo(now: clock),
    ).._demoRoom = _DemoRoom(clock, _demoStream);
  }

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

  /// What a room missing from the maps answers in the demo.
  _DemoRoom? _demoRoom;

  final calls = <String>[];
  final failures = <String, Object>{};
  final holds = <String, Completer<void>>{};

  Future<T> _answer<T>(String call, FutureOr<T> Function() value) async {
    calls.add(call);
    final name = call.split(' ').first;
    final hold = holds[call] ?? holds[name];
    if (hold != null) await hold.future;
    final failure = failures[call] ?? failures[name];
    if (failure != null) throw failure;
    return await value();
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
  Future<LivePlayInfo> playInfo(int roomId, {int? qn}) => _answer('playInfo $roomId qn=${qn ?? '-'}', () async {
    final play =
        plays[roomId] ?? await _demoRoom?.play() ?? LivePlayInfo(roomId: roomId, uid: 0, status: LiveStatus.offline);
    if (qn == null || qn == play.currentQn || !play.qualities.any((quality) => quality.qn == qn)) return play;
    return LivePlayInfo(
      roomId: play.roomId,
      shortId: play.shortId,
      uid: play.uid,
      status: play.status,
      portrait: play.portrait,
      liveTime: play.liveTime,
      url: play.url,
      qualities: play.qualities,
      currentQn: qn,
    );
  });

  @override
  Map<String, String> get streamHeaders => const {};

  @override
  Future<LiveRoomInfo> roomInfo(int roomId) => _answer(
    'roomInfo $roomId',
    () => rooms[roomId] ?? _demoRoom?.info() ?? LiveRoomInfo(roomId: roomId, uid: 0, title: ''),
  );

  @override
  Future<List<LiveChatMessage>> history(int roomId) =>
      _answer('history $roomId', () => histories[roomId] ?? _demoRoom?.history() ?? const []);

  @override
  Future<List<LiveSuperChat>> superChats(int roomId) =>
      _answer('superChats $roomId', () => superChatLists[roomId] ?? _demoRoom?.superChats() ?? const []);

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

  static Future<Uri?> _demoStream() async =>
      Platform.isWindows && !Platform.environment.containsKey('FLUTTER_TEST') ? DemoLiveServer.address() : null;
}

/// A danmaku feed tests drive by hand: [emit] and [setState]; [starts] and [closes] count the calls.
class FakeLiveChannel implements LiveChannel {
  FakeLiveChannel() : _demo = null;

  /// The `--fake-account` room's feed: once started, a danmaku every 1.5 s, a 醒目留言 every 40 s and a new online
  /// count every 10 s, until closed.
  FakeLiveChannel.demo({DateTime Function()? now}) : _demo = _DemoFeed(now ?? DateTime.now);

  final _events = StreamController<LiveEvent>.broadcast();
  final _states = StreamController<LiveSocketState>.broadcast();
  final _DemoFeed? _demo;
  final _timers = <Timer>[];
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
    final demo = _demo;
    if (demo == null || _timers.isNotEmpty) return;
    _timers.addAll([
      Timer.periodic(const Duration(milliseconds: 1500), (_) => emit(demo.danmaku())),
      Timer.periodic(const Duration(seconds: 40), (_) => emit(demo.superChat())),
      Timer.periodic(const Duration(seconds: 10), (_) => emit(demo.onlineCount())),
    ]);
  }

  @override
  Future<void> close() async {
    closes++;
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    _states.add(LiveSocketState.closed);
  }
}

/// The demo room's own answers, dated from [now] when asked.
final class _DemoRoom {
  _DemoRoom(this.now, this.clip);

  final DateTime Function() now;
  final Future<Uri?> Function() clip;

  Future<LivePlayInfo> play() async => LivePlayInfo(
    roomId: _Demo.roomId,
    uid: _Demo.anchorUid,
    status: LiveStatus.live,
    liveTime: now().subtract(const Duration(hours: 5, minutes: 12, seconds: 37)),
    url: await clip(),
    qualities: const [
      LiveQuality(qn: 10000, name: '1080P 原画 (高帧率)'),
      LiveQuality(qn: 400, name: '1080P 蓝光'),
      LiveQuality(qn: 250, name: '720P 超清'),
    ],
    currentQn: 10000,
  );

  LiveRoomInfo info() => const LiveRoomInfo(
    roomId: _Demo.roomId,
    uid: _Demo.anchorUid,
    title: '演示直播间：周末排位一起上分',
    anchorName: '演示主播',
    verify: LiveVerify.personal,
    description: '欢迎来到演示直播间！这里的弹幕、醒目留言和榜单都是编的，只用来看界面。',
    areaName: '英雄联盟',
    likeCount: 124000,
    watchedText: '9.1万人看过',
    onlineCount: 9349,
    topFaces: ['', '', ''],
    rankChips: ['热门榜', '网游人气第 28'],
  );

  List<LiveChatMessage> history() {
    final at = now();
    return [
      for (final (index, line) in _Demo.historyLines.indexed)
        LiveChatMessage(
          id: 'demo-history-$index',
          user: _Demo.viewers[index % _Demo.viewers.length],
          text: line,
          time: at.subtract(Duration(seconds: (_Demo.historyLines.length - index) * 8)),
        ),
    ];
  }

  List<LiveSuperChat> superChats() {
    final at = now();
    return [
      _Demo.superChat(
        id: 1,
        user: _Demo.viewers[3],
        message: '主播今天状态好好，这把一定能赢！',
        price: 50,
        start: at.subtract(const Duration(seconds: 30)),
        length: const Duration(minutes: 2),
      ),
      _Demo.superChat(
        id: 2,
        user: _Demo.viewers[5],
        message: '第一次发醒目留言，支持一下～',
        price: 30,
        start: at.subtract(const Duration(seconds: 10)),
        length: const Duration(minutes: 1),
      ),
    ];
  }
}

/// The demo feed's next danmaku, 醒目留言 and online count.
final class _DemoFeed {
  _DemoFeed(this.now);

  final DateTime Function() now;
  int _danmaku = 0;
  int _superChats = 0;
  int _counts = 0;
  int _online = 9349;

  LiveDanmakuEvent danmaku() {
    final index = _danmaku++;
    return LiveDanmakuEvent(
      LiveChatMessage(
        id: 'demo-live-$index',
        user: _Demo.viewers[(index * 5 + 1) % _Demo.viewers.length],
        text: _Demo.liveLines[index % _Demo.liveLines.length],
        time: now(),
      ),
    );
  }

  LiveSuperChatEvent superChat() {
    final index = _superChats++;
    const messages = ['主播辛苦了，早点休息', '刚下班就赶上开播，太好了', '这波操作太帅了'];
    const prices = [30, 50, 100];
    return LiveSuperChatEvent(
      _Demo.superChat(
        id: 100 + index,
        user: _Demo.viewers[(index * 2 + 1) % _Demo.viewers.length],
        message: messages[index % messages.length],
        price: prices[index % prices.length],
        start: now(),
        length: const Duration(minutes: 1),
      ),
    );
  }

  LiveOnlineCountEvent onlineCount() {
    const steps = [12, -7, 23, -15, 5, -9];
    _online += steps[_counts++ % steps.length];
    return LiveOnlineCountEvent(_online);
  }
}

/// The demo's made-up tab, people and lists.
abstract final class _Demo {
  static const roomId = 1000001;
  static const anchorUid = 2000001;

  static const areas = [
    LiveArea.recommend,
    LiveArea(id: 101, parentId: 14, name: '聊天室'),
    LiveArea(id: 102, parentId: 1, name: '颜值'),
    LiveArea(id: 103, parentId: 9, name: '虚拟主播'),
    LiveArea(id: 104, parentId: 1, name: '娱乐'),
    LiveArea(id: 105, parentId: 2, name: '英雄联盟'),
    LiveArea(id: 106, parentId: 2, name: '网游'),
    LiveArea(id: 107, parentId: 3, name: '手游'),
  ];

  static const _titles = [
    '演示直播间：周末排位一起上分',
    '深夜电台，陪你聊聊天',
    '新版本开荒，边玩边讲',
    '今天唱点老歌',
    '虚拟主播杂谈时间',
    '手游新活动一起肝',
    '画画直播，慢慢来',
    '下班后的放松局',
    '单排上分，弹幕随便聊',
    '做饭直播：今晚吃面',
  ];

  static const _areaNames = [
    '英雄联盟',
    '聊天室',
    '网游',
    '唱见电台',
    '虚拟主播',
    '手游',
    '绘画',
    '聊天室',
    '英雄联盟',
    '美食',
  ];
  static const _watched = ['9.1万', '883', '1.2万', '5634', '2.7万', '467', '3.3万', '1508', '7.8万', '921'];
  static const _likes = ['12.4万', '2.1万', '6532', '8.8万', '1.6万', '973', '4.2万', '3105', '9.9万', '1.1万'];

  static LiveCard card(int index, {String area = ''}) {
    final slot = index % _titles.length;
    return LiveCard(
      roomId: roomId + index,
      uid: anchorUid + index,
      title: _titles[slot],
      cover: '',
      uname: index == 0 ? '演示主播' : '演示主播$index',
      areaName: area.isEmpty ? _areaNames[slot] : area,
      watchedText: _watched[slot],
      likeText: _likes[slot],
      badge: switch (index % 7) {
        0 => const LiveBadge(text: 'TopStar', colors: [0xFFFF6699, 0xFFFF9DBA]),
        3 => const LiveBadge(text: 'SS主播', colors: [0xFF7A6CFF, 0xFFB3A9FF]),
        5 => const LiveBadge(text: '全站第5', colors: [0xFFFF8A3D, 0xFFFFB37A]),
        _ => null,
      },
      verify: index % 4 == 1 ? LiveVerify.personal : LiveVerify.none,
    );
  }

  static final followed = card(100);

  static LiveFeedPage feedPage(int page) => page == 1
      ? LiveFeedPage(
          page: 1,
          bigCards: [
            LiveBigCard(card: card(0), rankText: '人气榜TOP·2', rankValue: '2009助力值'),
            LiveBigCard(card: card(1), rankText: '人气榜TOP·5', rankValue: '1376助力值'),
            LiveBigCard(card: card(2), rankText: '新星榜TOP·1', rankValue: '864助力值'),
          ],
          following: [followed],
          followingTotal: 1,
          areas: areas,
          cards: [for (var index = 3; index < 23; index++) card(index)],
          hasMore: true,
        )
      : LiveFeedPage(page: page, cards: [for (var index = 23; index < 33; index++) card(index)]);

  static LiveCardPage areaPage(LiveArea area) => LiveCardPage(
    page: 1,
    cards: [for (var index = 0; index < 6; index++) card(area.id * 10 + index, area: area.name)],
  );

  static const viewers = [
    LiveUser(
      uid: 3000001,
      name: '演示小鱼干',
      medal: LiveMedal(
        name: '演示',
        level: 21,
        colorStart: 0xFF1A544B,
        colorEnd: 0xFF529D92,
        border: 0xFF6154E6,
        guardLevel: 3,
      ),
      wealthLevel: 28,
      guardLevel: 3,
    ),
    LiveUser(
      uid: 3000002,
      name: '演示晚风',
      medal: LiveMedal(name: '演示', level: 7, colorStart: 0xFF5D7B9E, colorEnd: 0xFF5D7B9E, border: 0xFF5D7B9E),
      wealthLevel: 12,
    ),
    LiveUser(uid: 3000003, name: '演示柠檬', wealthLevel: 3),
    LiveUser(
      uid: 3000004,
      name: '演示星河',
      medal: LiveMedal(name: '演示', level: 15, colorStart: 0xFFBE6686, colorEnd: 0xFFBE6686, border: 0xFFBE6686),
      wealthLevel: 21,
    ),
    LiveUser(
      uid: 3000005,
      name: '演示猫猫',
      medal: LiveMedal(
        name: '演示',
        level: 3,
        colorStart: 0xFF5C968E,
        colorEnd: 0xFF5C968E,
        border: 0xFF5C968E,
        lit: false,
      ),
      wealthLevel: 8,
    ),
    LiveUser(
      uid: 3000006,
      name: '演示早睡',
      medal: LiveMedal(name: '演示', level: 11, colorStart: 0xFF8D7CA6, colorEnd: 0xFF8D7CA6, border: 0xFF8D7CA6),
      wealthLevel: 35,
    ),
    LiveUser(uid: 3000007, name: '演示路人', wealthLevel: 1),
  ];

  static const historyLines = [
    '晚上好',
    '来了来了',
    '主播今天状态不错',
    '这波可以',
    '打卡',
    '刚下班，来看看',
    '这把稳了',
    '666',
    '前排',
    '主播几点下播',
  ];

  static const liveLines = [
    '哈哈哈哈哈',
    '好帅',
    '冲冲冲',
    '学到了',
    '这个画质好清楚',
    '下次一定',
    '主播加油',
    '爱了爱了',
    '稳住，能赢',
    '打得好',
    '刚来，现在几比几',
    '晚安各位',
  ];

  static const _bands = {
    30: (background: 0xFFEDF5FF, bottom: 0xFF2A60B2, price: 0xFF7497CD),
    50: (background: 0xFFDBFFFD, bottom: 0xFF427D9E, price: 0xFF7DA4BD),
    100: (background: 0xFFFFF1C5, bottom: 0xFFE2B52B, price: 0xFFECCF75),
  };

  static LiveSuperChat superChat({
    required int id,
    required LiveUser user,
    required String message,
    required int price,
    required DateTime start,
    required Duration length,
  }) {
    final band = _bands[price] ?? _bands[30]!;
    return LiveSuperChat(
      id: id,
      user: user,
      message: message,
      price: price,
      start: start,
      end: start.add(length),
      background: band.background,
      backgroundBottom: band.bottom,
      headerColor: band.background,
      priceColor: band.price,
    );
  }

  static final rank = LiveRankPage(
    entries: [
      for (var index = 0; index < 10; index++)
        LiveRankEntry(
          rank: index + 1,
          user: index < viewers.length
              ? viewers[index]
              : LiveUser(uid: 3000100 + index, name: '演示观众$index', wealthLevel: 10 - index),
          score: 52000 ~/ (index + 1),
        ),
    ],
    own: const LiveRankEntry(rank: 0, user: LiveUser(uid: 1, name: '测试账号')),
    count: 9349,
  );

  static final guards = {
    for (final tab in LiveGuardTab.values)
      tab: LiveGuardPage(
        entries: [
          for (var index = 0; index < 5; index++)
            LiveRankEntry(rank: index + 1, user: viewers[(index + tab.index) % viewers.length]),
        ],
        total: 5,
        topText: tab == LiveGuardTab.weekly ? '上周TOP1' : '',
        topUser: tab == LiveGuardTab.weekly ? viewers[0] : null,
      ),
  };

  static const emotes = [
    LiveEmotePackage(
      id: 1,
      name: '通用表情',
      icon: '',
      emotes: [
        LiveEmote(text: '打call', url: '', unique: 'demo_official_1'),
        LiveEmote(text: '妙啊', url: '', unique: 'demo_official_2'),
        LiveEmote(text: '好耶', url: '', unique: 'demo_official_3'),
        LiveEmote(text: '哭了', url: '', unique: 'demo_official_4'),
        LiveEmote(text: '赞', url: '', unique: 'demo_official_5'),
        LiveEmote(text: '晚安', url: '', unique: 'demo_official_6'),
        LiveEmote(text: '来了', url: '', unique: 'demo_official_7'),
        LiveEmote(text: '666', url: '', unique: 'demo_official_8'),
      ],
    ),
    LiveEmotePackage(
      id: 2,
      name: '房间专属',
      icon: '',
      emotes: [
        LiveEmote(text: '演示比心', url: '', unique: 'demo_room_1'),
        LiveEmote(text: '演示加油', url: '', unique: 'demo_room_2'),
        LiveEmote(text: '演示鼓掌', url: '', unique: 'demo_room_3'),
        LiveEmote(text: '演示晚安', url: '', unique: 'demo_room_4'),
      ],
    ),
  ];
}
