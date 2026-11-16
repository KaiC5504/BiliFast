import 'package:bili_core/devlog.dart';
import 'package:bilifast/home/feed_inline_player.dart';
import 'package:bilifast/settings/autoplay_policy.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/pip_keeper.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'autoplay_rules.dart';

final class _Card implements FeedInlineCard {
  _Card({this.list});

  Rect box = const Rect.fromLTWH(0, 200, 440, 248);
  int plays = 0;
  int pauses = 0;
  int releases = 0;
  bool playing = false;
  final ValueNotifier<bool>? list;

  @override
  Rect? videoRect() => box;

  @override
  ValueListenable<bool>? scrolling() => list;

  @override
  void inlinePlay() {
    plays++;
    playing = true;
  }

  @override
  void inlinePause() {
    pauses++;
    playing = false;
  }

  @override
  void inlineRelease() {
    releases++;
    playing = false;
  }
}

const _onScreen = Rect.fromLTWH(0, 200, 440, 248);
const _offScreen = Rect.fromLTWH(0, 1000, 440, 248);

/// 自动播放设置 against the hosts: 推荐's follows 首页自动播放, 动态's 动态视频是否自动播放, each with 流量网络下自动播放.
void main() {
  late MemorySink logs;

  setUp(() => logs = MemorySink());

  Future<(FeedInlineHost, _Card)> host(WidgetTester tester, InlineAutoplay rule, {Rect? box}) async {
    final pip = PipKeeper(logger: Logger(session: 'test'));
    final inline = FeedInlineHost(
      viewport: () => const Rect.fromLTWH(0, 0, 440, 956),
      pip: pip,
      autoplay: rule,
      logger: Logger(session: 'test')..add(logs),
    );
    addTearDown(() {
      inline.dispose();
      pip.dispose();
    });
    final card = _Card();
    if (box != null) card.box = box;
    inline
      ..register(card)
      ..shown = true;
    await tester.pump();
    return (inline, card);
  }

  /// The list shown again, as after a page or another tab over it.
  Future<void> showAgain(WidgetTester tester, FeedInlineHost inline) async {
    inline.shown = false;
    await tester.pump();
    inline.shown = true;
    await tester.pump();
  }

  List<Map<String, Object?>> held() => [
    for (final event in logs.events)
      if (event.msg == 'inline autoplay held') {for (final MapEntry(:key, :value) in event.f.entries) key: value.toJson()},
  ];

  void choose(PlayerPrefs prefs, InlineAutoplay rule, AutoplayChoice choice) {
    // The other list's rule the other way, so a host reading the wrong one fails.
    final other = choice == AutoplayChoice.off ? AutoplayChoice.always : AutoplayChoice.off;
    prefs
      ..homeAutoplay = rule == InlineAutoplay.home ? choice : other
      ..listAutoplay = rule == InlineAutoplay.list ? choice : other;
  }

  for (final rule in InlineAutoplay.values) {
    for (final choice in AutoplayChoice.values) {
      for (final cellular in [false, true]) {
        final plays = choice == AutoplayChoice.always || (choice == AutoplayChoice.wifiOnly && !cellular);
        final network = cellular ? 'mobile data' : 'Wi-Fi';
        testWidgets('${rule.logName}: ${choice.name} on $network ${plays ? 'plays' : 'holds'} the card', (tester) async {
          choose(autoplayRules(cellular: cellular), rule, choice);
          final (inline, card) = await host(tester, rule);
          expect(inline.playing, plays ? same(card) : isNull);
          expect(card.plays, plays ? 1 : 0);
          expect(held(), plays ? isEmpty : [
            {'list': rule.logName, 'reason': choice.name},
          ]);
        });
      }
    }
  }

  testWidgets('流量网络下自动播放 off holds both lists on mobile data only', (tester) async {
    for (final cellular in [false, true]) {
      autoplayRules(cellular: cellular).cellularAutoplay = false;
      for (final rule in InlineAutoplay.values) {
        final (_, card) = await host(tester, rule);
        expect(card.playing, !cellular, reason: '${rule.logName} on ${cellular ? 'mobile data' : 'Wi-Fi'}');
      }
    }
    expect(held(), [
      {'list': 'home', 'reason': 'cellular'},
      {'list': 'dynamic', 'reason': 'cellular'},
    ]);
  });

  testWidgets('a playing card pauses once the rule turns off and the list shows again, and plays when it is back on', (
    tester,
  ) async {
    final prefs = autoplayRules();
    final (inline, card) = await host(tester, InlineAutoplay.home);
    expect(card.playing, isTrue);
    prefs.homeAutoplay = AutoplayChoice.off;
    await showAgain(tester, inline);
    expect(card.playing, isFalse);
    expect(inline.playing, isNull);
    final plays = card.plays;
    inline.settle();
    expect(card.plays, plays, reason: 'every settle holds it');

    prefs.homeAutoplay = AutoplayChoice.wifiOnly;
    await showAgain(tester, inline);
    expect(card.playing, isTrue);
    onCellular(true);
    await showAgain(tester, inline);
    expect(card.playing, isFalse, reason: '仅 Wi-Fi on mobile data');
  });

  testWidgets('a hold is logged once while its reason stands; a new reason, or a hold after a play, logs again', (
    tester,
  ) async {
    final prefs = autoplayRules()..listAutoplay = AutoplayChoice.off;
    final (inline, _) = await host(tester, InlineAutoplay.list);
    inline.settle();
    await showAgain(tester, inline);
    expect(held(), [
      {'list': 'dynamic', 'reason': 'off'},
    ]);

    prefs.listAutoplay = AutoplayChoice.wifiOnly;
    onCellular(true);
    inline.settle();
    inline.settle();
    expect(held().map((fields) => fields['reason']), ['off', 'wifiOnly']);

    onCellular(false);
    inline.settle();
    expect(inline.playing, isNotNull);
    onCellular(true);
    inline.settle();
    expect(held().map((fields) => fields['reason']), ['off', 'wifiOnly', 'wifiOnly']);
  });

  testWidgets('仅 Wi-Fi: a playing card stops as the phone moves to mobile data, and plays again back on Wi-Fi', (
    tester,
  ) async {
    autoplayRules().homeAutoplay = AutoplayChoice.wifiOnly;
    final (inline, card) = await host(tester, InlineAutoplay.home);
    expect(card.playing, isTrue);
    onCellular(true);
    await tester.pump();
    expect(card.playing, isFalse, reason: 'no scroll or return needed');
    expect(inline.playing, isNull);
    onCellular(false);
    await tester.pump();
    expect(card.playing, isTrue);
  });

  testWidgets('a return to the app that settled on the old network corrects itself once the new one is in', (
    tester,
  ) async {
    autoplayRules().homeAutoplay = AutoplayChoice.wifiOnly;
    final (inline, card) = await host(tester, InlineAutoplay.home);
    inline.didChangeAppLifecycleState(AppLifecycleState.hidden);
    expect(card.playing, isFalse);
    inline.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(card.playing, isTrue, reason: 'settled on the Wi-Fi it last knew');
    onCellular(true);
    await tester.pump();
    expect(card.playing, isFalse);
  });

  testWidgets('a disposed host hears the network no more', (tester) async {
    autoplayRules().homeAutoplay = AutoplayChoice.wifiOnly;
    final (inline, card) = await host(tester, InlineAutoplay.home);
    inline.dispose();
    onCellular(true);
    await tester.pump();
    expect(card.playing, isTrue);
  });

  testWidgets('before the network is known 仅 Wi-Fi holds, logged as unknown', (tester) async {
    autoplayRules().homeAutoplay = AutoplayChoice.wifiOnly;
    AutoplayPolicy.shared = AutoplayPolicy(prefs: () => PlayerPrefs.shared, onCellular: () async => false);
    final (inline, card) = await host(tester, InlineAutoplay.home);
    expect(card.playing, isFalse);
    expect(held(), [
      {'list': 'home', 'reason': 'unknown'},
    ]);
    await AutoplayPolicy.shared.refresh();
    await tester.pump();
    expect(inline.playing, same(card));
  });

  testWidgets('only a card that would have played is held and logged, not one off screen', (tester) async {
    autoplayRules().homeAutoplay = AutoplayChoice.off;
    final (inline, card) = await host(tester, InlineAutoplay.home, box: const Rect.fromLTWH(0, 1000, 440, 248));
    expect(held(), isEmpty);
    card.box = const Rect.fromLTWH(0, 200, 440, 248);
    inline.settle();
    expect(held(), hasLength(1));
    expect(card.plays, 0);
  });

  group('letting go and resting', () {
    /// A host over [cards], shown, settled once.
    Future<FeedInlineHost> hostOf(WidgetTester tester, List<_Card> cards) async {
      autoplayRules();
      final pip = PipKeeper(logger: Logger(session: 'test'));
      final inline = FeedInlineHost(
        viewport: () => const Rect.fromLTWH(0, 0, 440, 956),
        pip: pip,
        autoplay: InlineAutoplay.home,
        logger: Logger(session: 'test'),
      );
      addTearDown(() {
        inline.dispose();
        pip.dispose();
      });
      for (final card in cards) {
        inline.register(card);
      }
      inline.shown = true;
      await tester.pump();
      return inline;
    }

    testWidgets('a card another takes over from is let go, not paused', (tester) async {
      final first = _Card(), second = _Card()..box = _offScreen;
      final inline = await hostOf(tester, [first, second]);
      expect(inline.playing, same(first));
      first.box = _offScreen;
      second.box = _onScreen;
      inline.settle();
      expect(inline.playing, same(second));
      expect(first.releases, 1);
      expect(first.pauses, 0);
    });

    testWidgets('with nothing playing in its place (a page over the list), the card is only paused', (tester) async {
      final card = _Card();
      final inline = await hostOf(tester, [card]);
      inline.shown = false;
      await tester.pump();
      expect(card.pauses, 1);
      expect(card.releases, 0);
      card.box = _offScreen;
      inline
        ..shown = true
        ..settle();
      expect(card.releases, 0, reason: 'scrolled off with no other card: still only paused');
    });

    testWidgets('the app leaving lets every card go; back in front the chosen one plays again', (tester) async {
      final first = _Card(), second = _Card()..box = _offScreen;
      final inline = await hostOf(tester, [first, second]);
      final before = second.releases;
      inline.didChangeAppLifecycleState(AppLifecycleState.hidden);
      expect(first.releases, 1);
      expect(second.releases, before + 1);
      expect(first.pauses + second.pauses, 0);
      inline.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(first.playing, isTrue);
    });

    testWidgets('while the list scrolls nothing new starts; the card playing goes on while half of it shows', (
      tester,
    ) async {
      final list = ValueNotifier(false);
      addTearDown(list.dispose);
      final first = _Card(list: list), second = _Card(list: list)..box = _offScreen;
      final inline = await hostOf(tester, [first, second]);
      expect(inline.playing, same(first));

      list.value = true;
      first.box = const Rect.fromLTWH(0, -100, 440, 248);
      second.box = _onScreen;
      inline.settle();
      expect(inline.playing, same(first), reason: 'more than half still shows');
      expect(second.plays, 0);

      first.box = const Rect.fromLTWH(0, -200, 440, 248);
      inline.settle();
      expect(inline.playing, isNull);
      expect(first.pauses, 1, reason: 'below half, nothing in its place yet');
      expect(second.plays, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(second.plays, 0, reason: 'still scrolling');
    });

    testWidgets('a new card starts once the list has rested, if it is still the one to play', (tester) async {
      final list = ValueNotifier(false);
      addTearDown(list.dispose);
      final first = _Card(list: list), second = _Card(list: list)..box = _offScreen;
      final inline = await hostOf(tester, [first, second]);
      list.value = true;
      await tester.pump();
      first.box = _offScreen;
      second.box = _onScreen;
      list.value = false;
      inline.settle();
      expect(second.plays, 0, reason: 'just come to rest');
      await tester.pump(FeedBigCardTheme.startAfterRest - const Duration(milliseconds: 10));
      expect(second.plays, 0);
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();
      expect(inline.playing, same(second));
      expect(first.releases, 1, reason: 'the paused card let go as another takes over');
    });

    testWidgets('a fling caught by a finger and dragged on starts nothing; a card gone by the rest is not started', (
      tester,
    ) async {
      final list = ValueNotifier(true);
      addTearDown(list.dispose);
      final first = _Card(list: list);
      final inline = await hostOf(tester, [first]);
      expect(first.plays, 0, reason: 'registered mid-scroll');

      list.value = false;
      await tester.pump(FeedBigCardTheme.startAfterRest ~/ 2);
      list.value = true;
      await tester.pump(FeedBigCardTheme.startAfterRest);
      inline.settle();
      expect(first.plays, 0, reason: 'the finger dragged on before the rest was up');

      list.value = false;
      await tester.pump(FeedBigCardTheme.startAfterRest ~/ 2);
      first.box = _offScreen;
      await tester.pump(FeedBigCardTheme.startAfterRest);
      await tester.pump();
      expect(first.plays, 0, reason: 'no longer the one to play when the rest was up');
    });
  });
}
