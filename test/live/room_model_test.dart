import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/live.dart';
import 'package:bilifast/live/fake_live_api.dart';
import 'package:bilifast/live/live_entry.dart';
import 'package:bilifast/live/room/live_chat_item.dart';
import 'package:bilifast/live/room/live_room_model.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// The card's short id; the play info answers [_realId].
const _shortId = 7;
const _realId = 7007;
const _anchor = 42;
const _viewerUid = 99;
final _t0 = DateTime(2026, 11, 17, 20);

const _viewer = LiveUser(uid: _viewerUid, name: '我自己');


LivePlayInfo _playInfo({LiveStatus status = LiveStatus.live, int qn = 10000}) => LivePlayInfo(
  roomId: _realId,
  shortId: _shortId,
  uid: _anchor,
  status: status,
  liveTime: DateTime(2026, 11, 17, 15),
  url: status == LiveStatus.live ? Uri.parse('https://example.invalid/live.m3u8') : null,
  qualities: const [
    LiveQuality(qn: 10000, name: '原画'),
    LiveQuality(qn: 400, name: '蓝光'),
    LiveQuality(qn: 250, name: '超清'),
  ],
  currentQn: qn,
);

const _info = LiveRoomInfo(
  roomId: _realId,
  uid: _anchor,
  title: '测试房间',
  description: '房间公告',
  likeCount: 100,
  watchedText: '1万人看过',
  onlineCount: 50,
  topFaces: ['a', 'b', 'c'],
);

LiveUser _user(int uid) => LiveUser(uid: uid, name: '观众$uid');

LiveChatMessage _message(String id, {int uid = 5, String? text, DateTime? time, LiveEmote? bigEmote}) =>
    LiveChatMessage(id: id, user: _user(uid), text: text ?? id, time: time ?? _t0, bigEmote: bigEmote);

LiveSuperChat _superChat(int id, {required Duration start, required Duration end}) => LiveSuperChat(
  id: id,
  user: _user(id),
  message: '留言$id',
  price: 30,
  start: _t0.add(start),
  end: _t0.add(end),
);

final class _Room {
  _Room(
    this.async, {
    this.loggedIn = true,
    LivePlayInfo? play,
    List<LiveChatMessage> history = const [],
    List<LiveSuperChat> superChats = const [],
    LiveUser? viewer = _viewer,
  }) {
    plays = {_shortId: play ?? _playInfo(), _realId: play ?? _playInfo()};
    api = FakeLiveApi(
      plays: plays,
      rooms: const {_shortId: _info},
      histories: {_shortId: history},
      superChatLists: {_shortId: superChats},
      channels: (_) => channel,
    );
    model = LiveRoomModel(
      api: api,
      entry: const LiveRoomEntry(roomId: _shortId, title: '卡片标题'),
      loggedIn: () => loggedIn,
      now: () => _t0.add(async.elapsed),
      viewer: viewer == null ? null : () => viewer,
      logger: Logger(session: 'test')..add(MemorySink()),
    );
    model.flying.listen(flown.add);
  }

  final FakeAsync async;
  bool loggedIn;
  late final Map<int, LivePlayInfo> plays;
  late final FakeLiveApi api;
  late final LiveRoomModel model;
  final channel = FakeLiveChannel();
  final flown = <LiveChatMessage>[];

  List<LiveChatItem> get chat => model.chat.value;

  void start() {
    unawaited(model.start());
    async.flushMicrotasks();
  }

  void emit(LiveEvent event) {
    channel.emit(event);
    async.flushMicrotasks();
  }

  List<String> callsNamed(String name) => [
    for (final call in api.calls)
      if (call.split(' ').first == name) call,
  ];
}

String _describe(LiveChatItem item) => switch (item) {
  LiveChatNotice() => 'notice',
  LiveChatRoomCard(:final title) => 'card $title',
  LiveChatDanmaku(:final message, :final own) => '${own ? 'own' : 'dm'} ${message.text}',
  LiveChatInteraction(:final kind, :final user) => '${kind.name} ${user.uid}',
  LiveChatSuperChat(:final superChat) => 'sc ${superChat.id}',
  LiveChatTip(:final text) => 'tip $text',
};

void main() {
  test('start asks the four calls together, once, and takes the real room id', () {
    fakeAsync((async) {
      final room = _Room(async);
      unawaited(room.model.start());
      unawaited(room.model.start());
      expect(room.api.calls, ['roomInfo 7', 'playInfo 7 qn=-', 'history 7', 'superChats 7']);
      expect(room.model.state, LiveRoomState.loading);

      async.flushMicrotasks();
      expect(room.model.state, LiveRoomState.live);
      expect(room.model.roomId, _realId);
      expect(room.model.play?.currentQn, 10000);
      expect(room.model.info?.title, '测试房间');
      expect(room.model.title, '测试房间');
      expect(room.model.anchorUid, _anchor);
      expect(room.model.likeCount, 100);
      expect(room.model.onlineCount, 50);
      expect(room.model.topFaces, ['a', 'b', 'c']);
      expect(room.model.watchedText, '1万人看过');
      expect(room.api.calls.skip(4), ['enter 7007', 'channel 7007']);
      expect(room.channel.starts, 1);

      unawaited(room.model.start());
      async.flushMicrotasks();
      expect(room.api.calls, hasLength(6));
      room.model.dispose();
    });
  });

  test('a failed history or 醒目留言 list costs only itself', () {
    fakeAsync((async) {
      final room = _Room(async, history: [_message('h0')]);
      room.api.failures['history'] = StateError('down');
      room.api.failures['superChats'] = StateError('down');
      room.start();
      expect(room.model.state, LiveRoomState.live);
      expect(room.chat.map(_describe), ['notice', 'card 测试房间']);
      expect(room.model.superChats.value, isEmpty);
      room.model.dispose();
    });
  });

  test('a failed play info leaves the room failed until retry answers', () {
    fakeAsync((async) {
      final room = _Room(async, history: [_message('h0')]);
      room.api.failures['playInfo'] = StateError('down');
      var notified = 0;
      room.model.addListener(() => notified++);
      room.start();

      expect(room.model.state, LiveRoomState.failed);
      expect(room.model.play, isNull);
      expect(room.chat.map(_describe), ['notice', 'dm h0']);
      expect(room.callsNamed('channel'), isEmpty);
      expect(room.callsNamed('enter'), isEmpty);
      expect(notified, greaterThan(0));

      room.api.failures.clear();
      unawaited(room.model.retry());
      expect(room.model.state, LiveRoomState.loading);
      async.flushMicrotasks();

      expect(room.model.state, LiveRoomState.live);
      expect(room.callsNamed('playInfo'), ['playInfo 7 qn=-', 'playInfo 7 qn=-']);
      // The info answered the first time, so only the play info is asked again.
      expect(room.callsNamed('roomInfo'), hasLength(1));
      expect(room.chat.map(_describe), ['notice', 'dm h0', 'card 测试房间']);
      expect(room.callsNamed('enter'), ['enter 7007']);
      expect(room.channel.starts, 1);

      unawaited(room.model.retry());
      async.flushMicrotasks();
      expect(room.callsNamed('playInfo'), hasLength(2));
      room.model.dispose();
    });
  });

  test('a room not live when opened is ended, opens no socket and gets no tip', () {
    fakeAsync((async) {
      final room = _Room(async, play: _playInfo(status: LiveStatus.offline));
      room.start();
      expect(room.model.state, LiveRoomState.ended);
      expect(room.chat.map(_describe), ['notice', 'card 测试房间']);
      async.elapse(const Duration(seconds: 31));
      expect(room.callsNamed('channel'), isEmpty);
      expect(room.chat.map(_describe), ['notice', 'card 测试房间']);
      room.model.dispose();
    });
  });

  test('the chat: 系统提示, history, the room card, live rows, then the tip once at 30 s', () {
    fakeAsync((async) {
      final room = _Room(async, history: [_message('h0'), _message('h1')]);
      room.start();
      final notice = room.chat.first as LiveChatNotice;
      expect(
        notice.text,
        '系统提示：哔哩哔哩直播内容及互动评论须严格遵守直播规范，严禁传播违法违规、低俗血暴、吸烟酗酒、造谣诈骗等不良有害信息。如有违规，平台将对'
        '违规直播间或账号进行相应的处罚！注意理性打赏，严禁未成年人直播或打赏。请勿轻信各类招聘征婚、代练代抽、刷钻、购买礼包码、游戏币等广告信息，'
        '且如主播在推广商品中诱导私下交易，请谨慎判断，以免上当受骗。',
      );
      final card = room.chat[3] as LiveChatRoomCard;
      expect(card.description, '房间公告');
      expect(card.liveTime, DateTime(2026, 11, 17, 15));

      room.emit(LiveDanmakuEvent(_message('d0')));
      async.elapse(const Duration(seconds: 29));
      expect(room.chat.whereType<LiveChatTip>(), isEmpty);
      async.elapse(const Duration(seconds: 1));
      room.emit(LiveDanmakuEvent(_message('d1')));
      async.elapse(const Duration(minutes: 2));

      expect(room.chat.map(_describe), [
        'notice',
        'dm h0',
        'dm h1',
        'card 测试房间',
        'dm d0',
        'tip 试试双击点赞，让主播被更多人看到吧～',
        'dm d1',
      ]);
      expect(room.flown.map((message) => message.id), ['d0', 'd1']);
      room.model.dispose();
    });
  });

  test('the chat keeps at most 500 rows, trimmed 100 at a time from the top', () {
    fakeAsync((async) {
      final room = _Room(async, history: [_message('h0'), _message('h1')]);
      room.start();
      expect(room.chat, hasLength(4));

      for (var index = 0; index < 497; index++) {
        room.channel.emit(LiveDanmakuEvent(_message('d$index')));
      }
      async.flushMicrotasks();
      expect(room.chat, hasLength(501 - 100));
      expect(_describe(room.chat.first), 'dm d96');

      for (var index = 497; index < 600; index++) {
        room.channel.emit(LiveDanmakuEvent(_message('d$index')));
      }
      async.flushMicrotasks();
      // 604 rows in all: two trims of 100.
      expect(room.chat, hasLength(404));
      expect(_describe(room.chat.first), 'dm d196');
      expect(_describe(room.chat.last), 'dm d599');
      expect(room.flown, hasLength(600));
      room.model.dispose();
    });
  });

  test('a send shows at once, flies, and its echo from the viewer within 10 s is dropped', () {
    fakeAsync((async) {
      final room = _Room(async);
      room.start();
      final before = room.chat.length;

      unawaited(room.model.send('  你好  '));
      expect(_describe(room.chat.last), 'own 你好');
      expect((room.chat.last as LiveChatDanmaku).message.user.uid, _viewerUid);
      async.flushMicrotasks();
      expect(room.flown.single.text, '你好');
      expect(room.callsNamed('send'), ['send 7007']);

      async.elapse(const Duration(seconds: 3));
      room.emit(LiveDanmakuEvent(_message('echo', uid: _viewerUid, text: '你好')));
      expect(room.chat, hasLength(before + 1));
      expect(room.flown, hasLength(1));

      // Someone else saying the same, and the viewer saying it again, are rows.
      room.emit(LiveDanmakuEvent(_message('other', uid: 5, text: '你好')));
      room.emit(LiveDanmakuEvent(_message('again', uid: _viewerUid, text: '你好')));
      expect(room.chat.skip(before).map(_describe), ['own 你好', 'dm 你好', 'dm 你好']);
      room.model.dispose();
    });
  });

  test('an echo after 10 s is a row; an emote send drops its emote echo', () {
    fakeAsync((async) {
      final room = _Room(async);
      room.start();
      final before = room.chat.length;

      unawaited(room.model.send('晚上好'));
      async.elapse(const Duration(seconds: 11));
      room.emit(LiveDanmakuEvent(_message('late', uid: _viewerUid, text: '晚上好')));
      expect(room.chat.skip(before).map(_describe), ['own 晚上好', 'dm 晚上好']);

      const emote = LiveEmote(text: '妙啊', url: '', unique: 'official_1');
      unawaited(room.model.sendEmote(emote));
      async.flushMicrotasks();
      expect(room.callsNamed('sendEmote'), ['sendEmote 7007 official_1']);
      final own = (room.chat.last as LiveChatDanmaku).message;
      expect(own.bigEmote?.unique, 'official_1');
      room.emit(LiveDanmakuEvent(_message('echo', uid: _viewerUid, text: '妙啊', bigEmote: emote)));
      expect(room.chat.skip(before).map(_describe), ['own 晚上好', 'dm 晚上好', 'own 妙啊']);
      room.model.dispose();
    });
  });

  test('an empty send asks nothing; a failed send takes its row back and throws', () {
    fakeAsync((async) {
      final room = _Room(async);
      room.start();
      final before = room.chat.length;

      unawaited(room.model.send('   '));
      async.flushMicrotasks();
      expect(room.callsNamed('send'), isEmpty);
      expect(room.chat, hasLength(before));

      room.api.failures['send'] = StateError('refused');
      Object? error;
      room.model.send('不行').catchError((Object caught) => error = caught);
      expect(_describe(room.chat.last), 'own 不行');
      async.flushMicrotasks();
      expect(error, isA<StateError>());
      expect(room.chat, hasLength(before));

      // No echo is expected any more: the same text from the viewer is a row.
      room.emit(LiveDanmakuEvent(_message('x', uid: _viewerUid, text: '不行')));
      expect(_describe(room.chat.last), 'dm 不行');
      room.model.dispose();
    });
  });

  test('logged out, send, emotes, 点赞 and 关注 throw LiveNotLoggedIn and nothing is entered', () {
    fakeAsync((async) {
      final room = _Room(async, loggedIn: false, viewer: null);
      room.start();
      expect(room.callsNamed('enter'), isEmpty);
      final before = room.chat.length;

      expect(room.model.like, throwsA(isA<LiveNotLoggedIn>()));
      final errors = <Object>[];
      room.model.send('hi').catchError((Object error) => errors.add(error));
      room.model
          .sendEmote(const LiveEmote(text: 'a', url: ''))
          .catchError((Object error) => errors.add(error));
      room.model.setFollowing(true).catchError((Object error) => errors.add(error));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));

      expect(errors, [isA<LiveNotLoggedIn>(), isA<LiveNotLoggedIn>(), isA<LiveNotLoggedIn>()]);
      expect(room.chat, hasLength(before));
      expect(room.model.likeCount, 100);
      for (final write in ['send', 'sendEmote', 'like', 'follow', 'enter']) {
        expect(room.callsNamed(write), isEmpty);
      }
      room.model.dispose();
    });
  });

  test('点赞: taps gather into one call 800 ms after the last, the count rises at once', () {
    fakeAsync((async) {
      final room = _Room(async);
      room.start();
      var notified = 0;
      room.model.addListener(() => notified++);

      room.model.like();
      async.elapse(const Duration(milliseconds: 500));
      room.model.like();
      room.model.like();
      expect(room.model.likeCount, 103);
      expect(notified, 3);
      async.elapse(const Duration(milliseconds: 799));
      expect(room.callsNamed('like'), isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(room.callsNamed('like'), ['like 7007 clicks=3']);

      // The socket's total only ever raises the count.
      room.emit(const LiveLikeCountEvent(101));
      expect(room.model.likeCount, 103);
      room.emit(const LiveLikeCountEvent(250));
      expect(room.model.likeCount, 250);

      room.api.failures['like'] = StateError('down');
      room.model.like();
      async.elapse(const Duration(seconds: 1));
      expect(room.callsNamed('like'), ['like 7007 clicks=3', 'like 7007 clicks=1']);
      expect(room.model.likeCount, 250);
      room.model.dispose();
    });
  });

  test('the socket closes 1 s after the page hides, survives a quick cover, and reopens on show', () {
    fakeAsync((async) {
      final room = _Room(async);
      room.start();
      expect(room.channel.starts, 1);

      room.model.setShown(false);
      async.elapse(const Duration(milliseconds: 500));
      room.model.setShown(true);
      async.elapse(const Duration(seconds: 2));
      expect(room.channel.closes, 0);
      expect(room.channel.starts, 1);

      room.model.setShown(false);
      async.elapse(const Duration(milliseconds: 999));
      expect(room.channel.closes, 0);
      async.elapse(const Duration(milliseconds: 1));
      expect(room.channel.closes, 1);

      room.model.setShown(true);
      async.flushMicrotasks();
      expect(room.channel.starts, 2);
      // The channel (and its token) is asked once and kept.
      expect(room.callsNamed('channel'), ['channel 7007']);
      room.model.dispose();
    });
  });

  test('after a hide past 30 min, show asks a fresh channel (its token likely expired)', () {
    fakeAsync((async) {
      final room = _Room(async);
      room.start();
      room.model.setShown(false);
      async.elapse(const Duration(minutes: 31));
      expect(room.channel.closes, 1);

      room.model.setShown(true);
      async.flushMicrotasks();
      expect(room.callsNamed('channel'), ['channel 7007', 'channel 7007']);
      expect(room.channel.starts, 2);
      expect(room.channel.closes, 1, reason: 'the old one was already closed');
      room.model.dispose();
    });
  });

  test('a refused socket asks a fresh channel once; refused again, the chat says so and nothing more is asked', () {
    fakeAsync((async) {
      final room = _Room(async);
      room.start();
      expect(room.callsNamed('channel'), hasLength(1));

      room.channel.setState(LiveSocketState.refused);
      async.flushMicrotasks();
      expect(room.callsNamed('channel'), hasLength(2));
      expect(room.channel.closes, 1);
      expect(room.channel.starts, 2);

      // The fresh channel's events still reach the chat.
      room.emit(LiveDanmakuEvent(_message('d0')));
      expect(_describe(room.chat.last), 'dm d0');

      room.channel.setState(LiveSocketState.refused);
      async.flushMicrotasks();
      expect(room.callsNamed('channel'), hasLength(2));
      expect(room.channel.closes, 2);
      expect((room.chat.last as LiveChatNotice).text, '弹幕连接失败，请稍后重试');

      unawaited(room.model.setQuality(400));
      async.elapse(const Duration(minutes: 1));
      room.channel.setState(LiveSocketState.refused);
      async.flushMicrotasks();
      expect(room.callsNamed('channel'), hasLength(2));
      expect(room.chat.whereType<LiveChatNotice>(), hasLength(2), reason: '系统提示 and the one notice');

      // Shown again, it may try once more.
      room.model.setShown(false);
      async.elapse(const Duration(seconds: 2));
      room.model.setShown(true);
      async.flushMicrotasks();
      expect(room.callsNamed('channel'), hasLength(3));
      expect(room.channel.starts, 3);
      room.model.dispose();
    });
  });

  test('a socket that gave up says so in the chat and starts the same channel once more on the next show', () {
    fakeAsync((async) {
      final room = _Room(async);
      room.start();
      expect(room.channel.starts, 1);

      room.channel.setState(LiveSocketState.failed);
      async.flushMicrotasks();
      expect(room.chat.whereType<LiveChatNotice>(), hasLength(1), reason: 'a retryable loss says nothing');

      room.channel.setState(LiveSocketState.gaveUp);
      async.flushMicrotasks();
      expect((room.chat.last as LiveChatNotice).text, '弹幕连接失败，请稍后重试');

      unawaited(room.model.setQuality(400));
      async.elapse(const Duration(minutes: 1));
      expect(room.channel.starts, 1, reason: 'held until the next show');
      expect(room.callsNamed('channel'), hasLength(1));

      room.model.setShown(false);
      async.elapse(const Duration(seconds: 2));
      expect(room.channel.closes, 0, reason: 'it had already stopped');
      room.model.setShown(true);
      async.flushMicrotasks();
      expect(room.channel.starts, 2);
      expect(room.callsNamed('channel'), hasLength(1), reason: 'its token was never refused');
      room.model.dispose();
    });
  });

  test('a failed channel ask waits for the next show: a quality switch asks nothing', () {
    fakeAsync((async) {
      final room = _Room(async);
      room.api.failures['channel'] = StateError('down');
      room.start();
      expect(room.callsNamed('channel'), hasLength(1));

      unawaited(room.model.setQuality(400));
      unawaited(room.model.refreshStream());
      async.elapse(const Duration(minutes: 1));
      expect(room.callsNamed('channel'), hasLength(1));
      expect(room.channel.starts, 0);

      room.api.failures.clear();
      room.model.setShown(false);
      async.elapse(const Duration(seconds: 2));
      room.model.setShown(true);
      async.flushMicrotasks();
      expect(room.callsNamed('channel'), hasLength(2));
      expect(room.channel.starts, 1);
      room.model.dispose();
    });
  });

  test('a failed 点赞 takes its taps back and reports the error for the page', () {
    fakeAsync((async) {
      final room = _Room(async);
      room.start();
      final failures = <Object>[];
      room.model.writeFailures.listen(failures.add);
      const notLoggedIn = BiliAPIError(code: -101, message: '账号未登录');
      room.api.failures['like'] = notLoggedIn;

      room.model
        ..like()
        ..like();
      expect(room.model.likeCount, 102);
      async.elapse(const Duration(seconds: 1));
      expect(room.model.likeCount, 100);
      expect(failures, [notLoggedIn]);
      room.model.dispose();
    });
  });

  test('endedNotices stays at 0 for a room offline at open, and rises once for each PREPARING', () {
    fakeAsync((async) {
      final offline = _Room(async, play: _playInfo(status: LiveStatus.offline));
      offline.start();
      expect(offline.model.state, LiveRoomState.ended);
      expect(offline.model.endedNotices.value, 0, reason: 'its cover says so; no toast');
      unawaited(offline.model.refreshStream());
      async.flushMicrotasks();
      expect(offline.model.endedNotices.value, 0);
      offline.model.dispose();

      final room = _Room(async);
      room.start();
      expect(room.model.endedNotices.value, 0);
      room.emit(const LiveStatusEvent(live: false));
      room.emit(const LiveStatusEvent(live: false));
      expect(room.model.endedNotices.value, 1);
      room.emit(const LiveStatusEvent(live: true));
      room.emit(const LiveStatusEvent(live: false));
      expect(room.model.endedNotices.value, 2);
      expect(room.chat.whereType<LiveChatRoomCard>(), hasLength(1), reason: 'the chat stays');
      room.model.dispose();
    });
  });

  test('a page hidden before the room answers opens no socket until shown', () {
    fakeAsync((async) {
      final room = _Room(async);
      room.model.setShown(false);
      room.start();
      async.elapse(const Duration(seconds: 5));
      expect(room.callsNamed('channel'), isEmpty);

      room.model.setShown(true);
      async.flushMicrotasks();
      expect(room.channel.starts, 1);
      room.model.dispose();
    });
  });

  test('a channel that answers after the page hid is not started', () {
    fakeAsync((async) {
      final room = _Room(async);
      final hold = room.api.holds['channel'] = Completer<void>();
      room.start();
      room.model.setShown(false);
      async.elapse(const Duration(seconds: 2));
      hold.complete();
      async.flushMicrotasks();
      expect(room.channel.starts, 0);

      room.model.setShown(true);
      async.flushMicrotasks();
      expect(room.channel.starts, 1);
      expect(room.callsNamed('channel'), hasLength(1));
      room.model.dispose();
    });
  });

  test('PREPARING ends the room and keeps the chat; LIVE asks the play info once', () {
    fakeAsync((async) {
      final room = _Room(async);
      room.start();
      room.emit(LiveDanmakuEvent(_message('d0')));
      final chat = room.chat;

      room.emit(const LiveStatusEvent(live: false));
      expect(room.model.state, LiveRoomState.ended);
      expect(room.chat, chat);
      expect(room.channel.closes, 0);

      // The stream isn't up yet: the room stays ended, and nothing asks again on its own.
      room.plays[_realId] = _playInfo(status: LiveStatus.offline);
      room.emit(const LiveStatusEvent(live: true));
      async.elapse(const Duration(minutes: 5));
      expect(room.callsNamed('playInfo'), ['playInfo 7 qn=-', 'playInfo 7007 qn=10000']);
      expect(room.model.state, LiveRoomState.ended);

      room.plays[_realId] = _playInfo();
      room.emit(const LiveStatusEvent(live: true));
      expect(room.callsNamed('playInfo'), hasLength(3));
      expect(room.model.state, LiveRoomState.live);
      expect(room.model.play?.url, isNotNull);
      room.model.dispose();
    });
  });

  test('醒目留言 leave the strip when they end, on one timer, or when deleted', () {
    fakeAsync((async) {
      final room = _Room(
        async,
        superChats: [
          _superChat(1, start: const Duration(seconds: -40), end: const Duration(seconds: 20)),
          _superChat(2, start: const Duration(seconds: -10), end: const Duration(seconds: 50)),
          _superChat(3, start: const Duration(seconds: -90), end: const Duration(seconds: -1)),
        ],
      );
      room.start();
      List<int> ids() => [for (final item in room.model.superChats.value) item.id];
      expect(ids(), [2, 1]);

      room.emit(LiveSuperChatEvent(_superChat(4, start: Duration.zero, end: const Duration(seconds: 30))));
      room.emit(LiveSuperChatEvent(_superChat(4, start: Duration.zero, end: const Duration(seconds: 30))));
      room.emit(LiveSuperChatEvent(_superChat(5, start: Duration.zero, end: const Duration(seconds: 70))));
      expect(ids(), [5, 4, 2, 1]);
      expect(room.chat.whereType<LiveChatSuperChat>().map((row) => row.superChat.id), [4, 5]);
      expect(async.periodicTimerCount, 0);

      async.elapse(const Duration(seconds: 19));
      expect(ids(), [5, 4, 2, 1]);
      async.elapse(const Duration(seconds: 1));
      expect(ids(), [5, 4, 2]);
      async.elapse(const Duration(seconds: 10));
      expect(ids(), [5, 2]);

      room.emit(const LiveSuperChatDeletedEvent([2]));
      expect(ids(), [5]);
      async.elapse(const Duration(seconds: 40));
      expect(ids(), isEmpty);
      // The chat's rows stay.
      expect(room.chat.whereType<LiveChatSuperChat>(), hasLength(2));
      room.model.dispose();
    });
  });

  test('quality: one call at a time, the play info follows, the same quality asks nothing', () {
    fakeAsync((async) {
      final room = _Room(async);
      room.start();
      var notified = 0;
      room.model.addListener(() => notified++);

      unawaited(room.model.setQuality(10000));
      async.flushMicrotasks();
      expect(room.callsNamed('playInfo'), hasLength(1));

      final hold = room.api.holds['playInfo'] = Completer<void>();
      final first = room.model.setQuality(400);
      final second = room.model.setQuality(400);
      expect(identical(first, second), isTrue);
      expect(identical(room.model.refreshStream(), first), isTrue);
      async.flushMicrotasks();
      expect(room.callsNamed('playInfo'), ['playInfo 7 qn=-', 'playInfo 7007 qn=400']);

      hold.complete();
      room.api.holds.clear();
      async.flushMicrotasks();
      expect(room.model.play?.currentQn, 400);
      expect(notified, greaterThan(0));

      unawaited(room.model.refreshStream());
      async.flushMicrotasks();
      expect(room.callsNamed('playInfo').last, 'playInfo 7007 qn=400');

      room.api.failures['playInfo'] = StateError('down');
      Object? error;
      room.model.setQuality(250).catchError((Object caught) => error = caught);
      async.flushMicrotasks();
      expect(error, isA<StateError>());
      expect(room.model.play?.currentQn, 400);
      expect(room.model.state, LiveRoomState.live);
      expect(room.callsNamed('enter'), hasLength(1));
      room.model.dispose();
    });
  });

  test("210's 自动 (qn 0) asks with no qn, even when the room is on its default", () {
    fakeAsync((async) {
      final room = _Room(async);
      room.start();
      unawaited(room.model.setQuality(0));
      async.flushMicrotasks();
      expect(room.callsNamed('playInfo'), ['playInfo 7 qn=-', 'playInfo 7007 qn=-']);
      room.model.dispose();
    });
  });

  test('a second quality waits for the first', () {
    fakeAsync((async) {
      final room = _Room(async);
      room.start();
      final hold = room.api.holds['playInfo'] = Completer<void>();
      unawaited(room.model.setQuality(400));
      unawaited(room.model.setQuality(250));
      async.flushMicrotasks();
      expect(room.callsNamed('playInfo'), ['playInfo 7 qn=-', 'playInfo 7007 qn=400']);

      room.api.holds.clear();
      hold.complete();
      async.flushMicrotasks();
      expect(room.callsNamed('playInfo').skip(1), ['playInfo 7007 qn=400', 'playInfo 7007 qn=250']);
      expect(room.model.play?.currentQn, 250);
      room.model.dispose();
    });
  });

  test('the socket moves the counts, faces, title and interactions', () {
    fakeAsync((async) {
      final room = _Room(async);
      room.start();
      final before = room.chat.length;

      room.emit(const LiveOnlineCountEvent(9349));
      room.emit(const LiveTopFacesEvent(['x', 'y', 'z']));
      room.emit(const LiveWatchedEvent('2万人看过'));
      room.emit(const LiveRoomChangedEvent(title: '新标题', areaName: '聊天室'));
      expect(room.model.onlineCount, 9349);
      expect(room.model.topFaces, ['x', 'y', 'z']);
      expect(room.model.watchedText, '2万人看过');
      expect(room.model.title, '新标题');
      expect(room.model.info?.title, '新标题');
      expect(room.model.info?.areaName, '聊天室');
      expect(room.model.info?.uid, _anchor);

      room.emit(LiveInteractEvent(LiveInteraction.entered, _user(5)));
      room.emit(const LiveInteractEvent(LiveInteraction.entered, _viewer));
      room.emit(LiveInteractEvent(LiveInteraction.liked, _user(6)));
      room.emit(LiveInteractEvent(LiveInteraction.followed, _user(7)));
      room.emit(LiveInteractEvent(LiveInteraction.shared, _user(8)));
      expect(room.chat.skip(before).map(_describe), ['entered 99', 'liked 6', 'followed 7', 'shared 8']);
      room.model.dispose();
    });
  });

  test('关注 is shown at once and goes back when the call fails', () {
    fakeAsync((async) {
      final room = _Room(async);
      room.start();
      expect(room.model.following, isFalse);

      unawaited(room.model.setFollowing(true));
      expect(room.model.following, isTrue);
      async.flushMicrotasks();
      expect(room.callsNamed('follow'), ['follow 42 on=true']);

      room.api.failures['follow'] = StateError('down');
      Object? error;
      room.model.setFollowing(false).catchError((Object caught) => error = caught);
      expect(room.model.following, isFalse);
      async.flushMicrotasks();
      expect(error, isA<StateError>());
      expect(room.model.following, isTrue);
      room.model.dispose();
    });
  });

  test('entered once per start, after the real id is known', () {
    fakeAsync((async) {
      final room = _Room(async);
      room.start();
      unawaited(room.model.setQuality(400));
      unawaited(room.model.refreshStream());
      room.emit(const LiveStatusEvent(live: false));
      room.emit(const LiveStatusEvent(live: true));
      async.elapse(const Duration(minutes: 1));
      expect(room.callsNamed('enter'), ['enter 7007']);
      room.model.dispose();
    });
  });

  test('dispose sends gathered taps, closes the socket and stops every timer', () {
    fakeAsync((async) {
      final room = _Room(async, superChats: [_superChat(1, start: Duration.zero, end: const Duration(minutes: 1))]);
      room.start();
      room.model.like();
      room.model.setShown(false);
      expect(async.pendingTimers, isNotEmpty);

      room.model.dispose();
      async.flushMicrotasks();
      expect(async.pendingTimers, isEmpty);
      expect(room.callsNamed('like'), ['like 7007 clicks=1']);
      expect(room.channel.closes, 1);

      final calls = room.api.calls.length;
      room.channel.emit(LiveDanmakuEvent(_message('late')));
      async.elapse(const Duration(minutes: 5));
      expect(room.api.calls, hasLength(calls));
    });
  });

  test('a room disposed before its calls answer stays quiet', () {
    fakeAsync((async) {
      final room = _Room(async);
      final hold = room.api.holds['playInfo'] = Completer<void>();
      room.start();
      room.model.dispose();
      hold.complete();
      async.elapse(const Duration(minutes: 1));
      expect(room.callsNamed('channel'), isEmpty);
      expect(room.callsNamed('enter'), isEmpty);
      expect(async.pendingTimers, isEmpty);
    });
  });
}
