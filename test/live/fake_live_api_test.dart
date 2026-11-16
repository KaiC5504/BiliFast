import 'dart:async';
import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/live.dart';
import 'package:bilifast/live/fake_live_api.dart';
import 'package:bilifast/live/live_entry.dart';
import 'package:bilifast/live/room/live_chat_item.dart';
import 'package:bilifast/live/room/live_room_model.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime(2026, 11, 17, 20);

void main() {
  test('the demo tab: three big cards, one followed room, eight areas and two pages of 推荐', () async {
    final api = FakeLiveApi.demo(now: () => _t0);
    final first = await api.feed(page: 1);
    expect(first.bigCards, hasLength(3));
    expect(first.bigCards.first.rankText, isNotEmpty);
    expect(first.following, hasLength(1));
    expect(first.followingTotal, 1);
    expect(first.areas.map((area) => area.name), ['推荐', '聊天室', '颜值', '虚拟主播', '娱乐', '英雄联盟', '网游', '手游']);
    expect(first.areas.first.isRecommend, isTrue);
    expect(first.cards, hasLength(20));
    expect(first.hasMore, isTrue);

    final second = await api.feed(page: 2);
    expect(second.cards, isNotEmpty);
    expect(second.hasMore, isFalse);
    expect((await api.feed(page: 3)).cards, isEmpty);

    final cards = [...first.cards, ...second.cards, for (final big in first.bigCards) big.card];
    for (final area in first.areas.where((area) => !area.isRecommend)) {
      final page = await api.area(area, page: 1);
      expect(page.cards, isNotEmpty, reason: area.name);
      expect(page.cards.map((card) => card.areaName).toSet(), {area.name});
      cards.addAll(page.cards);
    }
    final following = await api.following(page: 1);
    expect(following.total, 1);
    expect(following.cards.single.roomId, first.following.single.roomId);

    expect(cards.map((card) => card.roomId).toSet(), hasLength(cards.length));
    for (final card in cards) {
      expect(card.cover, isEmpty);
      expect(card.face, isEmpty);
      expect(card.title, isNotEmpty);
      expect(card.uname, startsWith('演示'));
    }
  });

  test('every demo card opens the demo room, dated from now', () async {
    final api = FakeLiveApi.demo(now: () => _t0);
    final card = (await api.feed(page: 2)).cards.last;

    final play = await api.playInfo(card.roomId);
    expect(play.roomId, 1000001);
    expect(play.status, LiveStatus.live);
    expect(play.liveTime, _t0.subtract(const Duration(hours: 5, minutes: 12, seconds: 37)));
    expect(play.qualities.map((quality) => quality.name), ['1080P 原画 (高帧率)', '1080P 蓝光', '720P 超清']);
    expect(play.currentQn, 10000);
    expect((await api.playInfo(play.roomId, qn: 400)).currentQn, 400);
    expect((await api.playInfo(play.roomId, qn: 1)).currentQn, 10000);
    if (Platform.isWindows) {
      expect(File(play.url!.toFilePath()).existsSync(), isTrue);
    } else {
      expect(play.url, isNull);
    }

    final info = await api.roomInfo(card.roomId);
    expect(info.anchorName, '演示主播');
    expect(info.onlineCount, 9349);
    expect(info.rankChips, ['热门榜', '网游人气第 28']);
    expect(info.likeCount, greaterThan(0));
    expect(info.title, isNotEmpty);
    expect(info.description, isNotEmpty);
    expect(info.anchorFace, isEmpty);
    expect(info.topFaces, hasLength(3));

    final history = await api.history(card.roomId);
    expect(history, hasLength(10));
    expect(history.where((message) => message.user.medal != null), isNotEmpty);
    expect(history.where((message) => message.user.wealthLevel > 0), hasLength(10));
    expect(history.every((message) => message.time.isBefore(_t0)), isTrue);

    final superChats = await api.superChats(card.roomId);
    expect(superChats, hasLength(2));
    expect(superChats.every((item) => item.end.isAfter(_t0) && !item.start.isAfter(_t0)), isTrue);

    final rank = await api.rank(play.roomId, anchorUid: play.uid, page: 1);
    expect(rank.entries.map((entry) => entry.rank), [for (var rank = 1; rank <= 10; rank++) rank]);
    expect(rank.own?.rank, 0);
    for (final tab in LiveGuardTab.values) {
      expect((await api.guards(play.roomId, anchorUid: play.uid, tab: tab, page: 1)).entries, isNotEmpty);
    }

    final emotes = await api.emotes(play.roomId);
    expect(emotes, hasLength(2));
    for (final package in emotes) {
      expect(package.icon, isEmpty);
      expect(package.emotes, isNotEmpty);
      expect(package.emotes.every((emote) => emote.url.isEmpty && emote.unique.isNotEmpty), isTrue);
    }
  });

  test('the demo channel feeds danmaku, 醒目留言 and online counts only while started', () {
    fakeAsync((async) {
      final channel = FakeLiveChannel.demo(now: () => _t0.add(async.elapsed));
      final events = <LiveEvent>[];
      channel.events.listen(events.add);
      async.elapse(const Duration(seconds: 10));
      expect(events, isEmpty);

      unawaited(channel.start());
      async.elapse(const Duration(seconds: 40));
      expect(events.whereType<LiveDanmakuEvent>(), hasLength(26));
      expect(events.whereType<LiveOnlineCountEvent>(), hasLength(4));
      final superChat = events.whereType<LiveSuperChatEvent>().single.superChat;
      expect(superChat.start, _t0.add(const Duration(seconds: 50)));
      expect(superChat.end.isAfter(superChat.start), isTrue);
      final danmaku = events.whereType<LiveDanmakuEvent>().map((event) => event.message);
      expect(danmaku.map((message) => message.id).toSet(), hasLength(26));
      expect(danmaku.every((message) => message.user.face.isEmpty), isTrue);

      unawaited(channel.close());
      final count = events.length;
      async.elapse(const Duration(minutes: 2));
      expect(events, hasLength(count));
      expect(async.pendingTimers, isEmpty);

      unawaited(channel.start());
      async.elapse(const Duration(seconds: 3));
      expect(events.length, count + 2);
      unawaited(channel.close());
      expect(channel.starts, 2);
      expect(channel.closes, 2);
    });
  });

  test('the demo room through the room model: live, its chat filled and fed', () {
    fakeAsync((async) {
      final api = FakeLiveApi.demo(now: () => _t0.add(async.elapsed));
      final model = LiveRoomModel(
        api: api,
        entry: const LiveRoomEntry(roomId: 1000005),
        loggedIn: () => true,
        now: () => _t0.add(async.elapsed),
        logger: Logger(session: 'test')..add(MemorySink()),
      );
      unawaited(model.start());
      async.flushMicrotasks();
      expect(model.state, LiveRoomState.live);
      expect(model.roomId, 1000001);
      expect(model.superChats.value, hasLength(2));
      expect(model.chat.value.whereType<LiveChatDanmaku>(), hasLength(10));
      expect(model.chat.value.last, isA<LiveChatRoomCard>());

      async.elapse(const Duration(seconds: 3));
      expect(model.chat.value.whereType<LiveChatDanmaku>(), hasLength(12));
      model.dispose();
      expect(async.pendingTimers, isEmpty);
    });
  });
}
