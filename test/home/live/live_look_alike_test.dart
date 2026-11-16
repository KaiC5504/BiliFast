import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/live/live_cards.dart';
import 'package:bilifast/live/fake_live_api.dart';
import 'package:bilifast/live/following/live_following_page.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/look_alike.dart';
import '../../support/stand_in_fonts.dart';
import '../../video/mixed_lines.dart' show appTheme;
import 'live_support.dart';

const _screen = ValueKey('screen');

/// 205 under 首页's 142 pt header and 206, as KaiC's iPhone draws them, under the system font. With BILIFAST_SHOTS
/// naming a folder outside the repo, the 3× shots are saved there for tools/screen_diff.py.
void main() {
  setUp(() => LivePlayers());

  final page = liveFeedPage(
    big: [
      LiveBigCard(
        card: liveCard(100, title: '【素颜】演示女神赛 杀一个就算赢！', name: '演示主播的名字可'),
      ),
      LiveBigCard(card: liveCard(101), rankText: '人气榜TOP·2', rankValue: '2009助力值'),
    ],
  );

  Future<void> show(WidgetTester tester, Widget body, {double top = 142}) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester);
    BiliFonts.family = BiliFonts.system;
    final api = FakeLiveApi(
      feedPages: [page],
      followingPages: [
        LiveCardPage(
          page: 1,
          cards: [liveCard(200, name: '你的演示月月', title: '演示新服【九天】')],
          total: 1,
        ),
      ],
    );
    final services = await liveServices(api: api);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => RepaintBoundary(
          key: _screen,
          child: AppScope(services: services, child: child!),
        ),
        home: Scaffold(
          backgroundColor: LiveTabTheme.page,
          body: Column(
            children: [
              SizedBox(
                height: top,
                width: double.infinity,
                child: const ColoredBox(color: Color(0xFFD9E8D3)),
              ),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      final context = tester.element(find.byType(Scaffold));
      for (final asset in [LiveArt.watched, LiveArt.liked, LiveArt.coverSwitch, LiveArt.areas]) {
        await precacheImage(AssetImage(asset), context);
      }
    });
    await settle(tester);
  }

  testWidgets('205: the carousel 5.33 under the header, the strip, the area row and the cards at 205\'s places', (
    tester,
  ) async {
    final harness = LiveHarness(api: FakeLiveApi(feedPages: [page]));
    await show(tester, harness.tab());
    final carousel = tester.getRect(find.byKey(const ValueKey('live-carousel')));
    expect(carousel.top, moreOrLessEquals(142 + 16 / 3));
    expect(tester.getRect(find.byKey(const ValueKey('live-following'))).top, moreOrLessEquals(1218 / 3, epsilon: 0.4));
    expect(tester.getRect(find.byKey(const ValueKey('live-areas'))).bottom, moreOrLessEquals(1761 / 3, epsilon: 0.4));
    expect(
      tester.getRect(find.byKey(const ValueKey('live-grid-9000'))).bottom,
      moreOrLessEquals(2388 / 3, epsilon: 0.6),
    );

    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(_screen), '$shots/205-live-ours.png');
  });

  testWidgets('206: the cards straight under the bar', (tester) async {
    await show(tester, const LiveFollowingPage(), top: 0);
    final card = tester.getRect(find.byKey(const ValueKey('live-following-card-9200')));
    expect(card.top, moreOrLessEquals(348 / 3, epsilon: 0.4));
    expect(card.left, moreOrLessEquals(16 / 3));
    expect(card.bottom, moreOrLessEquals(911 / 3, epsilon: 0.6));

    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(_screen), '$shots/206-live-following-ours.png');
  });
}
