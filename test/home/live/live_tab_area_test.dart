import 'package:bili_core/api.dart';
import 'package:bilifast/home/live/live_cards.dart';
import 'package:bilifast/live/fake_live_api.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'live_support.dart';

/// Whether the [LiveBars] under [card] may tick (their gif decodes frames only then).
bool _barsTicking(WidgetTester tester, Finder card) {
  final bars = find.descendant(of: card, matching: find.byType(LiveBars), skipOffstage: false);
  return TickerMode.valuesOf(tester.element(bars)).enabled;
}

void main() {
  setUp(() => LivePlayers());

  testWidgets('a chosen area tab under the fade slides fully clear of it', (tester) async {
    final page = LiveFeedPage(
      page: 1,
      bigCards: const [],
      following: const [],
      areas: [for (var i = 1; i <= 8; i++) LiveArea(id: 20 + i, parentId: 1, name: '测试分区$i')],
      cards: liveCards(4),
    );
    final harness = LiveHarness(api: FakeLiveApi(feedPages: [page]));
    await pumpLive(tester, await liveServices(api: harness.api), harness.tab());
    await settle(tester);

    const fadeFrom = LiveTabTheme.areaFadeFrom;
    final words = find.text('测试分区4');
    expect(tester.getRect(words).right, greaterThan(fadeFrom));
    await tester.tapAt(tester.getTopLeft(find.byKey(const ValueKey('live-area-24-1'))) + const Offset(4, 20));
    await settle(tester);
    expect(tester.getRect(words).right, lessThanOrEqualTo(fadeFrom + 0.01));
    expect(tester.getRect(words).left, greaterThanOrEqualTo(LiveTabTheme.areaLead));

    // The first area, now short of the row's lead: chosen, it comes back to it.
    final first = find.text('测试分区1');
    expect(tester.getRect(first).left, lessThan(LiveTabTheme.areaLead - 1));
    await tester.tapAt(tester.getRect(first).centerRight - const Offset(4, 0));
    await settle(tester);
    expect(tester.getRect(first).left, moreOrLessEquals(LiveTabTheme.areaLead));
  });

  testWidgets('直播中 bars tick only on the middle card, with the tab shown and nothing over it', (tester) async {
    final harness = LiveHarness(
      api: FakeLiveApi(
        feedPages: [
          liveFeedPage(big: [for (var i = 100; i < 103; i++) LiveBigCard(card: liveCard(i))]),
        ],
        plays: livePlays(),
      ),
    );
    await pumpLive(tester, await liveServices(api: harness.api), harness.tab());
    await settle(tester);

    // Three cards, 500 laps each way: the middle one is 1500, its neighbours 1499 and 1501.
    final middle = find.byKey(const ValueKey('live-big-1500'));
    final neighbour = find.byKey(const ValueKey('live-big-1501'));
    final following = find.byKey(const ValueKey('live-following'));
    expect(_barsTicking(tester, middle), isTrue);
    expect(_barsTicking(tester, following), isTrue);
    expect(_barsTicking(tester, neighbour), isFalse);

    // A sheet over 首页 leaves the tab drawn underneath, but its gifs stop.
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(PageRouteBuilder<void>(opaque: false, pageBuilder: (context, _, _) => const SizedBox.shrink()));
    await settle(tester);
    expect(_barsTicking(tester, middle), isFalse);
    expect(_barsTicking(tester, following), isFalse);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await settle(tester);
    expect(_barsTicking(tester, middle), isTrue);

    // Another 首页 tab or place shown.
    harness.active.value = false;
    await settle(tester);
    expect(_barsTicking(tester, middle), isFalse);
    expect(_barsTicking(tester, following), isFalse);
  });
}
