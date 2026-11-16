import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/home/feed_inline_player.dart';
import 'package:bilifast/home/live/live_inline_player.dart';
import 'package:bilifast/live/fake_live_api.dart';
import 'package:bilifast/live/live_entry.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../home/live/live_support.dart';

final class _Card {
  _Card(this.api, this.inline, this.players, this.channel);

  final FakeLiveApi api;
  final LiveInlinePlayback inline;
  final LivePlayers players;
  final FakeLiveChannel channel;

  List<String> named(String name) => [
    for (final call in api.calls)
      if (call.split(' ').first == name) call,
  ];

  List<String> loads() => [
    for (final call in players.last.calls)
      if (call.startsWith('load ')) call,
  ];
}

Future<_Card> _card() async {
  final players = LivePlayers();
  final channel = FakeLiveChannel();
  final api = FakeLiveApi(plays: livePlays(), channels: (_) => channel);
  final services = await liveServices(api: api);
  final inline = LiveInlinePlayback(
    services: services,
    api: api,
    entry: const LiveRoomEntry(roomId: 9100),
    loggedIn: () => true,
    logger: Logger(session: 'test')..add(MemorySink()),
  );
  addTearDown(inline.dispose);
  return _Card(api, inline, players, channel);
}

Future<void> _lifecycle(WidgetTester tester, List<AppLifecycleState> states) async {
  for (final state in states) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pump();
}

void main() {
  testWidgets('the socket is open only while the card plays with 弹 on', (tester) async {
    final card = await _card();
    FeedInlineChoices.danmaku.value = false;
    card.inline.play();
    await tester.pump();
    expect(card.api.calls, ['playInfo 9100 qn=-']);

    FeedInlineChoices.danmaku.value = true;
    await tester.pump();
    expect(card.api.calls, ['playInfo 9100 qn=-', 'channel 9100']);
    expect(card.channel.starts, 1);

    FeedInlineChoices.danmaku.value = false;
    await tester.pump(const Duration(seconds: 2));
    expect(card.channel.closes, 1);

    // Paused with 弹 on, it closes too; 弹 again while paused opens nothing.
    FeedInlineChoices.danmaku.value = true;
    await tester.pump();
    expect(card.channel.starts, 2);
    card.inline.pause();
    await tester.pump(const Duration(seconds: 2));
    expect(card.channel.closes, 2);
    FeedInlineChoices.danmaku.value = false;
    FeedInlineChoices.danmaku.value = true;
    await tester.pump();
    expect(card.channel.starts, 2);
    expect(card.named('channel'), hasLength(1));
    card.inline.release();
  });

  testWidgets('a player failure asks a fresh stream once; a second shows the cover until released', (tester) async {
    final card = await _card();
    card.inline.play();
    await tester.pump();
    final player = card.players.last;
    expect(card.loads(), ['load https://live.invalid/9100.m3u8']);

    player.emit(const PlayerFailed('broken'));
    expect(card.inline.loading, isTrue);
    await tester.pump();
    expect(card.named('playInfo'), ['playInfo 9100 qn=-', 'playInfo 9100 qn=-']);
    expect(card.loads(), hasLength(2), reason: 'the same address loaded again');
    expect(card.inline.failed, isFalse);

    player.emit(const PlayerFailed('broken again'));
    await tester.pump(const Duration(seconds: 20));
    expect(card.inline.failed, isTrue);
    expect(card.named('playInfo'), hasLength(2));

    card.inline
      ..release()
      ..play();
    await tester.pump();
    expect(card.inline.failed, isFalse);
    expect(card.named('playInfo'), hasLength(3));
    card.inline.release();
  });

  testWidgets('a live room offering no stream it can play shows the cover at once', (tester) async {
    final players = LivePlayers();
    final api = FakeLiveApi(
      plays: {9100: const LivePlayInfo(roomId: 9100, uid: 600, status: LiveStatus.live)},
      channels: (_) => FakeLiveChannel(),
    );
    final inline = LiveInlinePlayback(
      services: await liveServices(api: api),
      api: api,
      entry: const LiveRoomEntry(roomId: 9100),
      loggedIn: () => true,
      logger: Logger(session: 'test')..add(MemorySink()),
    );
    addTearDown(inline.dispose);
    inline.play();
    await tester.pump();
    expect(inline.failed, isTrue);
    expect(inline.loading, isFalse);
    expect([for (final call in players.last.calls) if (call.startsWith('load ')) call], isEmpty);
    await tester.pump(const Duration(seconds: 20));
    expect(api.calls.where((call) => call.startsWith('playInfo')), hasLength(1), reason: 'no fresh stream asked');
    inline.release();
  });

  testWidgets('15 s without a picture asks a fresh stream once; a later stall leaves the cover', (tester) async {
    final card = await _card();
    card.inline.play();
    await tester.pump();
    final player = card.players.last;

    await tester.pump(const Duration(seconds: 14));
    expect(card.named('playInfo'), hasLength(1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(card.named('playInfo'), hasLength(2));
    expect(card.loads(), hasLength(2));

    player.emit(const StatusChanged(PlayerStatus.playing));
    await tester.pump(const Duration(seconds: 30));
    expect(card.inline.shown, isTrue);
    expect(card.named('playInfo'), hasLength(2));

    player.emit(const StatusChanged(PlayerStatus.buffering));
    await tester.pump(const Duration(seconds: 15));
    expect(card.inline.failed, isTrue);
    expect(card.named('playInfo'), hasLength(2));
    card.inline.release();
  });

  testWidgets('the app leaving pauses the card and closes its socket after the grace; back, it plays on', (
    tester,
  ) async {
    final card = await _card();
    card.inline.play();
    await tester.pump();
    final player = card.players.last..emit(const StatusChanged(PlayerStatus.playing));
    expect(card.channel.starts, 1);

    await _lifecycle(tester, [AppLifecycleState.inactive, AppLifecycleState.hidden]);
    expect(player.calls.last, 'pause');
    expect(card.channel.closes, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(card.channel.closes, 1);
    await tester.pump(const Duration(seconds: 5));

    await _lifecycle(tester, [AppLifecycleState.inactive, AppLifecycleState.resumed]);
    expect(player.calls.last, 'play');
    expect(card.channel.starts, 2);
    expect(card.loads(), hasLength(1), reason: 'back within 10 s, no new stream');
    expect(card.named('playInfo'), hasLength(1));
    card.inline.release();
  });
}
