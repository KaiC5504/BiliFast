import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/settings/playback/autoplay_settings_page.dart';
import 'package:bilifast/settings/playback/home_feed_settings_page.dart';
import 'package:bilifast/settings/playback/playback_settings_page.dart';
import 'package:bilifast/settings/settings_page.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'settings_fakes.dart';

void main() {
  late SettingsWorld world;
  late PlayerPrefs prefs;

  setUp(() => prefs = PlayerPrefs.memory());

  Future<void> show(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(440, 956) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    world = await SettingsWorld.create();
    addTearDown(world.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppScope(services: world.services, child: child!),
        home: SettingsPage(prefs: prefs, version: '1.3.0 (9)'),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder row(String key) => find.byKey(ValueKey(key));
  Finder checkOf(String key) => find.descendant(of: row(key), matching: find.byKey(const ValueKey('settings-check')));
  final toast = find.text('暂未开放');

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.ensureVisible(row(key));
    await tester.pumpAndSettle();
    await tester.tap(row(key));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> back(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('settings-back')).last);
    await tester.pumpAndSettle();
  }

  /// Lets a toast run out, so no timer is left when the test ends.
  Future<void> runOut(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  }

  Future<void> expectToast(WidgetTester tester) async {
    expect(toast, findsOneWidget);
    await runOut(tester);
  }

  void expectValue(String key, String value) =>
      expect(find.descendant(of: row(key), matching: find.text(value)), findsOneWidget);

  testWidgets('设置 has 首页推荐设置 and 播放设置 in their own section after 字体', (tester) async {
    await show(tester);
    expectValue('settings-home-feed', '双列/Wi-Fi/免流/移动网络下自动播放');
    final font = tester.getRect(row('settings-font'));
    final feed = tester.getRect(row('settings-home-feed'));
    final playback = tester.getRect(row('settings-playback'));
    final node = tester.getRect(row('settings-node'));
    expect(feed.top, greaterThan(font.bottom + 10), reason: 'a section gap after 字体');
    expect(playback.top, closeTo(feed.bottom + 1 / 3, 0.01));
    expect(node.top, greaterThan(playback.bottom + 10));
    expect(tester.takeException(), isNull);
  });

  group('首页推荐设置', () {
    Future<void> open(WidgetTester tester) async {
      await show(tester);
      await tap(tester, 'settings-home-feed');
      await tester.pumpAndSettle();
      expect(find.byType(HomeFeedSettingsPage), findsOneWidget);
    }

    testWidgets('首页自动播放 saves each choice, moves the ✓, and 设置 shows it on return', (tester) async {
      await open(tester);
      expect(checkOf('home-feed-autoplay-always'), findsOneWidget);
      for (final choice in [AutoplayChoice.wifiOnly, AutoplayChoice.off, AutoplayChoice.always]) {
        await tap(tester, 'home-feed-autoplay-${choice.name}');
        expect(prefs.homeAutoplay, choice);
        for (final other in AutoplayChoice.values) {
          expect(checkOf('home-feed-autoplay-${other.name}'), other == choice ? findsOneWidget : findsNothing);
        }
      }
      await tap(tester, 'home-feed-autoplay-wifiOnly');
      await back(tester);
      expectValue('settings-home-feed', '双列/仅Wi-Fi下自动播放');
    });

    testWidgets('大卡默认声音 starts muted and saves both choices', (tester) async {
      await open(tester);
      expect(checkOf('home-feed-sound-muted'), findsOneWidget);
      await tap(tester, 'home-feed-sound-on');
      expect(prefs.bigCardSound, isTrue);
      expect(checkOf('home-feed-sound-on'), findsOneWidget);
      expect(checkOf('home-feed-sound-muted'), findsNothing);
      await tap(tester, 'home-feed-sound-muted');
      expect(prefs.bigCardSound, isFalse);
      expect(checkOf('home-feed-sound-muted'), findsOneWidget);
    });

    testWidgets('自动模式 and 关闭 are what 首页 does; 竖屏模式, 开启 and 首页单双列切换 toast and change nothing', (tester) async {
      await open(tester);
      expect(checkOf('home-feed-mode-auto'), findsOneWidget);
      expect(checkOf('home-feed-refresh-off'), findsOneWidget);
      for (final key in ['home-feed-mode-vertical', 'home-feed-refresh-on', 'home-feed-columns']) {
        await tap(tester, key);
        await expectToast(tester);
      }
      expect(checkOf('home-feed-mode-auto'), findsOneWidget);
      expect(checkOf('home-feed-mode-vertical'), findsNothing);
      expect(checkOf('home-feed-refresh-off'), findsOneWidget);
      expect(checkOf('home-feed-refresh-on'), findsNothing);
      expect(find.byType(HomeFeedSettingsPage), findsOneWidget);
      for (final key in ['home-feed-mode-auto', 'home-feed-refresh-off']) {
        await tap(tester, key);
        expect(toast, findsNothing);
      }
    });
  });

  group('播放设置', () {
    Future<void> open(WidgetTester tester) async {
      await show(tester);
      await tap(tester, 'settings-playback');
      await tester.pumpAndSettle();
      expect(find.byType(PlaybackSettingsPage), findsOneWidget);
    }

    testWidgets('opens 自动播放设置, 竖屏模式设置 and 小窗播放/后台听视频设置; the other three toast', (tester) async {
      await open(tester);
      for (final (key, page) in [
        ('playback-autoplay', AutoplaySettingsPage),
        ('playback-vertical', VerticalModeSettingsPage),
        ('playback-pip', PipSettingsPage),
      ]) {
        await tap(tester, key);
        await tester.pumpAndSettle();
        expect(find.byType(page), findsOneWidget);
        await back(tester);
        expect(find.byType(page), findsNothing);
      }
      for (final key in ['playback-danmaku', 'playback-quality', 'playback-other']) {
        await tap(tester, key);
        await expectToast(tester);
        expect(find.byType(PlaybackSettingsPage), findsOneWidget);
      }
    });

    testWidgets('自动播放设置\'s switches save both ways', (tester) async {
      await open(tester);
      await tap(tester, 'playback-autoplay');
      await tester.pumpAndSettle();
      final switches = <String, bool Function()>{
        'autoplay-cellular': () => prefs.cellularAutoplay,
        'autoplay-detail': () => prefs.detailAutoplay,
        'autoplay-detail-full-screen': () => prefs.detailFullScreen,
      };
      expect([for (final read in switches.values) read()], [true, true, false]);
      for (final MapEntry(key: key, value: read) in switches.entries) {
        final before = read();
        await tap(tester, key);
        expect(read(), !before, reason: key);
        await tap(tester, key);
        expect(read(), before, reason: key);
      }
    });

    testWidgets('自动播放设置\'s 动态 row opens 178, whose picks save and show on return', (tester) async {
      await open(tester);
      await tap(tester, 'playback-autoplay');
      await tester.pumpAndSettle();
      expectValue('autoplay-list', '开启自动播放');
      await tap(tester, 'autoplay-list');
      await tester.pumpAndSettle();
      expect(find.text('动态视频是否自动播放'), findsOneWidget);
      expect(find.text('选择后，将影响所有列表场景下的视频播放'), findsOneWidget);
      expect(checkOf('list-autoplay-always'), findsOneWidget);
      await tap(tester, 'list-autoplay-off');
      expect(prefs.listAutoplay, AutoplayChoice.off);
      await tap(tester, 'list-autoplay-wifiOnly');
      expect(prefs.listAutoplay, AutoplayChoice.wifiOnly);
      expect(checkOf('list-autoplay-wifiOnly'), findsOneWidget);
      expect(checkOf('list-autoplay-always'), findsNothing);
      await back(tester);
      expectValue('autoplay-list', '仅WiFi/免流下自动播放');
      expect(prefs.homeAutoplay, AutoplayChoice.always);
    });

    testWidgets('自动播放设置\'s 首页自动播放 opens 179, whose picks save and show back in 自动播放设置 and 设置', (tester) async {
      await open(tester);
      await tap(tester, 'playback-autoplay');
      await tester.pumpAndSettle();
      expectValue('autoplay-home', 'Wi-Fi/免流/移动网络下自动播放');
      await tap(tester, 'autoplay-home');
      await tester.pumpAndSettle();
      expect(find.byType(AutoplayChoicePage), findsOneWidget);
      await tap(tester, 'home-autoplay-off');
      expect(prefs.homeAutoplay, AutoplayChoice.off);
      expect(checkOf('home-autoplay-off'), findsOneWidget);
      await back(tester);
      expectValue('autoplay-home', '关闭自动播放');
      expect(prefs.listAutoplay, AutoplayChoice.always);
      await back(tester);
      await back(tester);
      expectValue('settings-home-feed', '双列/关闭自动播放');
    });

    testWidgets('竖屏模式设置\'s switch saves both ways', (tester) async {
      await open(tester);
      await tap(tester, 'playback-vertical');
      await tester.pumpAndSettle();
      expect(prefs.verticalFullScreen, isTrue);
      await tap(tester, 'vertical-full-screen');
      expect(prefs.verticalFullScreen, isFalse);
      await tap(tester, 'vertical-full-screen');
      expect(prefs.verticalFullScreen, isTrue);
    });

    testWidgets('小窗播放: 应用外自动小窗播放 saves both ways; the other three are off, toast and stay off', (tester) async {
      await open(tester);
      await tap(tester, 'playback-pip');
      await tester.pumpAndSettle();
      bool shownOn(String key) {
        final drawn = tester.widget<AnimatedContainer>(
          find.descendant(of: row(key), matching: find.byKey(const ValueKey('settings-switch'))),
        );
        return (drawn.decoration! as BoxDecoration).color == SettingsListTheme.switchOn;
      }

      expect(prefs.autoPip, isTrue);
      expect(shownOn('pip-outside'), isTrue);
      await tap(tester, 'pip-outside');
      expect(prefs.autoPip, isFalse);
      expect(shownOn('pip-outside'), isFalse);
      await tap(tester, 'pip-outside');
      expect(prefs.autoPip, isTrue);
      for (final key in ['pip-inside', 'pip-background', 'pip-background-next']) {
        expect(shownOn(key), isFalse, reason: key);
        await tap(tester, key);
        await expectToast(tester);
        expect(shownOn(key), isFalse, reason: key);
      }
    });
  });

  testWidgets('every new row presses through accessibility, as the Windows test driver does', (tester) async {
    final semantics = tester.ensureSemantics();
    await show(tester);
    tester.semantics.tap(find.semantics.byLabel(RegExp('^首页推荐设置\n')));
    await tester.pumpAndSettle();
    tester.semantics.tap(find.semantics.byLabel('仅Wi-Fi下自动播放'));
    await tester.pumpAndSettle();
    expect(prefs.homeAutoplay, AutoplayChoice.wifiOnly);
    tester.semantics.tap(find.semantics.byLabel('默认打开'));
    await tester.pumpAndSettle();
    expect(prefs.bigCardSound, isTrue);
    tester.semantics.tap(find.semantics.byLabel('返回').last);
    await tester.pumpAndSettle();

    tester.semantics.tap(find.semantics.byLabel('播放设置'));
    await tester.pumpAndSettle();
    tester.semantics.tap(find.semantics.byLabel('自动播放设置'));
    await tester.pumpAndSettle();
    tester.semantics.tap(find.semantics.byLabel('详情页直接全屏播放\n进入视频详情页后自动全屏播放视频'));
    await tester.pumpAndSettle();
    expect(prefs.detailFullScreen, isTrue);
    tester.semantics.tap(find.semantics.byLabel(RegExp('^动态/活动页单列视频是否自动播放')));
    await tester.pumpAndSettle();
    tester.semantics.tap(find.semantics.byLabel('关闭自动播放'));
    await tester.pumpAndSettle();
    expect(prefs.listAutoplay, AutoplayChoice.off);
    tester.semantics.tap(find.semantics.byLabel('返回').last);
    await tester.pumpAndSettle();
    tester.semantics.tap(find.semantics.byLabel('返回').last);
    await tester.pumpAndSettle();

    tester.semantics.tap(find.semantics.byLabel('小窗播放/后台听视频设置'));
    await tester.pumpAndSettle();
    tester.semantics.tap(find.semantics.byLabel(RegExp('^应用外自动小窗播放')));
    await tester.pumpAndSettle();
    expect(prefs.autoPip, isFalse);
    tester.semantics.tap(find.semantics.byLabel(RegExp('^后台听视频\n')));
    await tester.pump();
    await expectToast(tester);
    semantics.dispose();
  });
}
