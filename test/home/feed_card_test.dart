import 'dart:convert';

import 'package:bili_core/api.dart';
import 'package:bilifast/home/feed_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
                child: FeedCardView(card: card, onOpen: () {}, onWatchLater: () {}),
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
}
