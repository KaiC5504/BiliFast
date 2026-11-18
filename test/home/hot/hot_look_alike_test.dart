import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/hot/hot_api.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/look_alike.dart';
import '../../support/stand_in_fonts.dart';
import '../../video/mixed_lines.dart' show appTheme;
import 'hot_support.dart';

const _screen = ValueKey('screen');

/// The rows under 204's header as KaiC's iPhone draws them, under the system font, the list starting 142 down. With
/// BILIFAST_SHOTS naming a folder outside the repo, the 3× shot is saved there for tools/screen_diff.py.
void main() {
  Future<HotHarness> show(WidgetTester tester, List<PopularVideo> videos, {bool sheet = false}) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester);
    BiliFonts.family = BiliFonts.system;
    final services = await hotServices();
    final harness = HotHarness(api: FakeHotApi(videos: videos));
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => RepaintBoundary(
          key: _screen,
          child: AppScope(services: services, child: child!),
        ),
        home: Scaffold(
          backgroundColor: HotListTheme.page,
          body: Column(
            children: [
              SizedBox(
                height: 142,
                width: double.infinity,
                child: ColoredBox(color: BiliColors.pageGrey),
              ),
              Expanded(child: harness.list()),
            ],
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      final context = tester.element(find.byType(Scaffold));
      for (final asset in [
        'assets/images/card/up_badge.png',
        'assets/images/home/hot_play_counts.png',
        'assets/images/home/hot_share_wechat.png',
        'assets/images/home/hot_share_moments.png',
        'assets/images/home/hot_share_download.png',
        'assets/images/home/hot_share_qq.png',
        'assets/images/home/hot_share_watch_later.png',
      ]) {
        await precacheImage(AssetImage(asset), context);
      }
    });
    await settle(tester);
    return harness;
  }

  final rows = [
    hotVideo(1, title: '“演示数字3，讲讲一条规矩。”', owner: '演示用户名字', views: 1831000),
    hotVideo(
      2,
      title: '演示标题这一行写得长一些丨一口气看完9th演示合集 长到第二行也放得下',
      owner: 'Demo-演示',
      views: 238000,
      duration: 4908,
      age: const Duration(hours: 15, minutes: 12),
    ),
    hotVideo(3, title: '演示一下，我动不了了...', views: 1519000, duration: 70),
    hotVideo(4, title: 'Morning, Demo', views: 1611000, duration: 411, age: const Duration(days: 2, hours: 3)),
    hotVideo(5, views: 1161000, duration: 475, age: const Duration(hours: 23, minutes: 2)),
    hotVideo(6, views: 1380000, duration: 394, age: const Duration(hours: 21, minutes: 15)),
    hotVideo(7, views: 62000, duration: 174, age: const Duration(hours: 2)),
  ];

  testWidgets("204's rows: 114.67 apart, the cover 167 × 94 at 12, 152 and the line under it at 256", (tester) async {
    await show(tester, rows);
    final first = tester.getRect(find.byKey(const ValueKey('hot-row-BV1hot1')));
    expect(first.top, 142);
    expect(first.height, moreOrLessEquals(344 / 3));
    final second = tester.getRect(find.byKey(const ValueKey('hot-row-BV1hot2')));
    expect(second.top - first.top, moreOrLessEquals(344 / 3));
    expect(
      tester.getRect(find.byKey(const ValueKey('hot-cover-placeholder')).first),
      const Rect.fromLTWH(12, 152, 167, 94),
    );
    final up = tester.getRect(find.byKey(const ValueKey('hot-uploader-BV1hot1')));
    expect(up.left, moreOrLessEquals(571 / 3), reason: "the UP icon's ink starts 190.33 in");
    final more = tester.getCenter(find.byKey(const ValueKey('hot-more-BV1hot1')));
    expect(more.dx, moreOrLessEquals(440 - 20.17));
    expect(more.dy, moreOrLessEquals(246 - 8.17), reason: "on the ▷ line, 8.17 above the cover's bottom");

    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(_screen), '$shots/204-hot-ours.png');
  });

  testWidgets("217's sheet: 222 above the home indicator, the targets 66 apart from 12 in, 稍后再看 under the rule", (
    tester,
  ) async {
    await show(tester, rows);
    await tester.tap(find.byKey(const ValueKey('hot-more-BV1hot1')));
    await settle(tester);
    expect(tester.getRect(find.byKey(const ValueKey('hot-share-sheet'))).top, moreOrLessEquals(700));
    final facebook = tester.getRect(find.byKey(const ValueKey('hot-share-facebook')));
    expect(facebook.left, 12);
    expect(facebook.width, 66);
    expect(facebook.top, moreOrLessEquals(747.33));
    expect(tester.getRect(find.byKey(const ValueKey('hot-share-x'))).left, 78);
    final later = tester.getRect(find.byKey(const ValueKey('hot-share-watch-later')));
    expect(later.topLeft, const Offset(12, 854));
    expect(tester.getCenter(find.byKey(const ValueKey('hot-share-close'))).dx, moreOrLessEquals(440 - 26.17));

    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(_screen), '$shots/217-hot-share-ours.png');
  });
}
