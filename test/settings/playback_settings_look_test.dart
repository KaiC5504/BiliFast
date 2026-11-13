import 'dart:io';

import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/settings/playback/autoplay_settings_page.dart';
import 'package:bilifast/settings/playback/home_feed_settings_page.dart';
import 'package:bilifast/settings/playback/playback_settings_page.dart';
import 'package:bilifast/settings/settings_page.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import '../video/mixed_lines.dart' show appTheme;
import 'settings_fakes.dart';

// Its own file: the stand-ins replace Roboto and the Cupertino families for every later test in the isolate.

/// The playback pages as KaiC's iPhone draws them, under the system font, in the states of his screenshots (170-174,
/// 178, 179). Each must fit at 440 pt; with BILIFAST_SHOTS naming a folder outside the repo, the 3× shots are saved
/// there for tools/screen_diff.py (the official bar is 10 pt taller: `--anchor 106:116`).
void main() {
  Future<void> shoot(WidgetTester tester, String name, Widget page) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    BiliFonts.family = BiliFonts.system;
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(key: const ValueKey('shot'), child: page),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'nothing overflows');
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) await saveShot(tester, find.byKey(const ValueKey('shot')), '$shots/$name.png');
  }

  testWidgets('设置 with 首页推荐设置 and 播放设置 (50)', (tester) async {
    final world = await SettingsWorld.create();
    addTearDown(world.dispose);
    await shoot(
      tester,
      '50-settings',
      AppScope(
        services: world.services,
        child: SettingsPage(prefs: PlayerPrefs.memory(), version: '1.3.0 (9)'),
      ),
    );
    final value = find.text('双列/Wi-Fi/免流/移动网络下自动播放');
    expect(tester.getSize(value).width, lessThan(240), reason: 'the whole value shows');
  });

  testWidgets('首页推荐设置 (170)', (tester) async {
    await shoot(tester, '170-home-feed', HomeFeedSettingsPage(prefs: PlayerPrefs.memory()));
  });

  testWidgets('播放设置 (171)', (tester) async {
    await shoot(tester, '171-playback', PlaybackSettingsPage(prefs: PlayerPrefs.memory()));
  });

  testWidgets('自动播放设置 (172)', (tester) async {
    await shoot(tester, '172-autoplay', AutoplaySettingsPage(prefs: PlayerPrefs.memory()));
  });

  testWidgets('竖屏模式设置 (173)', (tester) async {
    await shoot(tester, '173-vertical', VerticalModeSettingsPage(prefs: PlayerPrefs.memory()));
  });

  testWidgets('小窗播放/后台听视频设置 (174)', (tester) async {
    await shoot(tester, '174-pip', PipSettingsPage(prefs: PlayerPrefs.memory()));
  });

  testWidgets('动态视频是否自动播放 (178)', (tester) async {
    await shoot(tester, '178-list-picker', AutoplayChoicePage.list(choice: AutoplayChoice.always, onChanged: (_) {}));
  });

  testWidgets('首页自动播放 (179)', (tester) async {
    await shoot(tester, '179-home-picker', AutoplayChoicePage.home(choice: AutoplayChoice.always, onChanged: (_) {}));
  });
}
