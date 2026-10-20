import 'dart:convert';

import 'package:bili_core/api.dart';
import 'package:bili_core/logic.dart' show CountFormat;
import 'package:bilifast/home/feed_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/system_font.dart';
import 'feed_fakes.dart';

void main() {
  final card = FeedCard.fromJson(jsonDecode(jsonEncode(feedItem('BV1long', title: '很长很长的标题' * 6, reason: '关注的人赞过'))));

  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets('at text scale $scale the card is as tall as FeedCardSize says and nothing overflows', (tester) async {
      const width = 160.0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: FeedCardView(card: card, onOpen: (_) {}, onWatchLater: () {}),
              ),
            ),
          ),
        ),
      );
      final drawn = tester.getSize(find.byType(FeedCardView)).height;
      expect(drawn, closeTo(FeedCardSize.height(width, TextScaler.linear(scale)), 0.01));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('under the system font, the counts over the cover fall back to emoji, then PingFang SC', (tester) async {
    Future<void> show() => tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 200,
            child: FeedCardView(card: card, onOpen: (_) {}, onWatchLater: () {}),
          ),
        ),
      ),
    );
    await expectSystemFallback(tester, show, find.text(CountFormat.short(card.views)));
    await expectSystemFallback(tester, show, find.text(FeedCardView.duration(card.duration)));
  });
}
