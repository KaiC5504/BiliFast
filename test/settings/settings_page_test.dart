import 'dart:async';
import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/settings/btr_page.dart';
import 'package:bilifast/settings/playback/home_feed_settings_page.dart';
import 'package:bilifast/settings/settings_page.dart';
import 'package:bilifast/shared/image_disk_cache.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../video/mixed_lines.dart';
import 'settings_fakes.dart';

void main() {
  late SettingsWorld world;
  late PlayerPrefs prefs;

  setUp(() => prefs = PlayerPrefs.memory());

  Future<void> show(
    WidgetTester tester, {
    Account account = const LoggedOut(),
    WidgetBuilder? developerPage,
    Completer<void>? startGate,
    bool reduceMotion = false,
    ThemeData? theme,
    ImageDiskCache? imageCache,
  }) async {
    tester.view
      ..physicalSize = const Size(440, 956) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    world = await SettingsWorld.create(account: account, startGate: startGate, imageCache: imageCache);
    addTearDown(world.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        builder: (context, child) => AppScope(
          services: world.services,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) => Center(
            child: GestureDetector(
              key: const ValueKey('open-settings'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsPage(developerPage: developerPage, prefs: prefs, version: '1.0.0 (10)'),
                ),
              ),
              child: const Text('home'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-settings')));
    await tester.pumpAndSettle();
  }

  Finder row(String key) => find.byKey(ValueKey(key));
  Finder confirmButton(String label) => find.byKey(ValueKey('settings-confirm-$label'));
  final confirm = find.byKey(const ValueKey('settings-confirm'));
  Finder text(String key, String value) => find.descendant(of: row(key), matching: find.text(value));
  Finder checked(String key) => find.descendant(of: row(key), matching: find.byKey(const ValueKey('settings-check')));
  const licence = '下载加速移植自 Bilibili 线程撕裂者（BTR），MIT 许可。';

  Future<void> tapRow(WidgetTester tester, String key) async {
    await tester.ensureVisible(row(key));
    await tester.pumpAndSettle();
    await tester.tap(row(key));
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('settings-back')).last);
    await tester.pumpAndSettle();
  }

  List<String> rowTitles(WidgetTester tester) => [
    for (final row in tester.widgetList<SettingsRow>(find.byType(SettingsRow, skipOffstage: false))) row.title,
  ];

  testWidgets('under the system font the rows, the version and BTR\'s page sit on the Chinese line', (tester) async {
    await useSystemFont(tester);
    await show(tester, theme: appTheme());
    expectOnChineseLine(tester, find.text('BTR'));
    await tester.ensureVisible(row('settings-version'));
    await tester.pumpAndSettle();
    expectOnChineseLine(tester, find.text('版本 1.0.0 (10)'));

    await tapRow(tester, 'settings-btr');
    expectOnChineseLine(tester, find.text('BTR 加速'));
    expectOnChineseLine(tester, find.text('CDN 节点'));
    expectOnChineseLine(tester, find.text(licence));
  });

  testWidgets('the order: 首页推荐设置, 播放设置, BTR, the clearing rows, 开发者, 退出登录, then the version', (tester) async {
    await show(
      tester,
      account: const LoggedIn(name: '小明', vip: true),
      developerPage: (_) => const Scaffold(body: Text('开发者页面')),
      imageCache: FakeImageDiskCache(1024),
    );
    expect(rowTitles(tester), ['首页推荐设置', '播放设置', 'BTR', '清除最近观看', '清除图片缓存', '开发者', '退出登录']);
    await tester.ensureVisible(row('settings-version'));
    await tester.pumpAndSettle();
    final version = tester.getRect(row('settings-version'));
    expect(version.top, greaterThan(tester.getRect(row('settings-logout')).bottom));
    expect(version.center.dx, closeTo(220, 0.5));
    expect(tester.widget<Text>(row('settings-version')).style?.color, SettingsTheme.footer);
  });

  testWidgets('重置编码记忆 and 清除日志 are not on 设置 (开发者 has them)', (tester) async {
    await show(tester, imageCache: FakeImageDiskCache(1024));
    expect(find.text('重置编码记忆', skipOffstage: false), findsNothing);
    expect(find.text('清除日志', skipOffstage: false), findsNothing);
    expect(row('settings-codec-memory'), findsNothing);
    expect(row('settings-logs'), findsNothing);
  });

  group('the account', () {
    testWidgets('logged out: 登录 comes first and opens the login page, and there is no 退出登录', (tester) async {
      await show(tester);
      expect(text('settings-login', '登录'), findsOneWidget);
      expect(rowTitles(tester).first, '登录');
      expect(row('settings-relogin'), findsNothing);
      await tapRow(tester, 'settings-login');
      expect(world.gate.requests, 1);
      expect(row('settings-logout'), findsNothing);
    });

    testWidgets('login expired: 重新登录 comes first and opens the login page', (tester) async {
      await show(tester, account: const LoginExpired());
      expect(row('settings-login'), findsNothing);
      expect(rowTitles(tester).first, '重新登录');
      await tapRow(tester, 'settings-relogin');
      expect(world.gate.requests, 1);
      expect(row('settings-logout'), findsNothing);
    });

    testWidgets('logged in: no account rows at all, and 退出登录 is the last row', (tester) async {
      await show(tester, account: const LoggedIn(name: '小明', vip: true));
      expect(find.text('小明', skipOffstage: false), findsNothing);
      expect(find.text('账号', skipOffstage: false), findsNothing);
      expect(find.text('大会员', skipOffstage: false), findsNothing);
      expect(row('settings-login'), findsNothing);
      expect(row('settings-relogin'), findsNothing);
      expect(rowTitles(tester).first, '首页推荐设置');
      expect(rowTitles(tester).last, '退出登录');
    });

    testWidgets('an account still being checked, or whose check failed, shows no row either', (tester) async {
      await show(tester, account: const AccountUnknown());
      expect(rowTitles(tester).first, '首页推荐设置');
      world.environment
        ..accountCheckFailed = true
        ..account = const AccountUnknown();
      await tester.pump();
      expect(rowTitles(tester).first, '首页推荐设置');
      expect(find.text('无法获取账号信息，点按重试', skipOffstage: false), findsNothing);
      expect(row('settings-logout'), findsNothing);
    });

    testWidgets('a login while 设置 is open takes 登录 away and brings 退出登录', (tester) async {
      await show(tester);
      world.environment.account = const LoggedIn(name: '小明', vip: false);
      await tester.pump();
      expect(row('settings-login'), findsNothing);
      expect(rowTitles(tester).first, '首页推荐设置');
      expect(row('settings-logout'), findsOneWidget);
    });
  });

  group('BTR', () {
    testWidgets('the row reads 开启 or 关闭 and opens BTR\'s page; its switch saves btr and the row follows', (
      tester,
    ) async {
      await show(tester);
      expect(prefs.btr, isTrue);
      expect(text('settings-btr', '开启'), findsOneWidget);
      await tapRow(tester, 'settings-btr');
      expect(find.byType(BtrPage), findsOneWidget);
      expect(find.text('BTR'), findsOneWidget, reason: 'the bar\'s title');
      expect(tester.getSemantics(row('btr-switch')), isSemantics(isToggled: true, hasToggledState: true));

      await tapRow(tester, 'btr-switch');
      expect(prefs.btr, isFalse);
      expect(tester.getSemantics(row('btr-switch')), isSemantics(isToggled: false, hasToggledState: true));
      await back(tester);
      expect(text('settings-btr', '关闭'), findsOneWidget);

      await tapRow(tester, 'settings-btr');
      await tapRow(tester, 'btr-switch');
      expect(prefs.btr, isTrue);
      await back(tester);
      expect(text('settings-btr', '开启'), findsOneWidget);
    });

    testWidgets('BTR\'s page: the switch, CDN 节点\'s picks with their note, and the licence last', (tester) async {
      await show(tester);
      await tapRow(tester, 'settings-btr');
      expect(find.text('CDN 节点'), findsOneWidget);
      expect(text('node-overseas', '海外节点'), findsOneWidget);
      expect(text('node-mainland', '大陆节点'), findsOneWidget);
      final note = tester.getRect(find.text('从下一个视频开始使用。'));
      expect(note.top, greaterThan(tester.getRect(row('node-mainland')).bottom));
      expect(tester.getRect(find.text(licence)).top, greaterThan(note.bottom));
      expect(tester.getRect(row('btr-switch')).bottom, lessThan(tester.getRect(find.text('CDN 节点')).top));
      expect(tester.widget<Text>(find.text(licence)).style?.color, SettingsTheme.footer);
      await back(tester);
      expect(find.text(licence), findsNothing, reason: '设置 itself no longer carries it');
    });

    testWidgets('CDN 节点 starts on 海外节点; 大陆节点 is saved and goes to the engine for the next video', (tester) async {
      final logs = MemorySink();
      Logger.shared.add(logs);
      addTearDown(() => Logger.shared.remove(logs));
      await show(tester);
      await tapRow(tester, 'settings-btr');
      expect(checked('node-overseas'), findsOneWidget);
      expect(checked('node-mainland'), findsNothing);
      await tapRow(tester, 'node-mainland');
      expect(prefs.node, NodeChoice.mainland);
      expect(world.engine.nodeModes.last, isA<MainlandNodes>());
      expect(checked('node-mainland'), findsOneWidget);
      expect(checked('node-overseas'), findsNothing);
      expect(logs.events.where((event) => event.msg == 'settings node').single.f['node']?.toJson(), 'mainland');

      await back(tester);
      await tapRow(tester, 'settings-btr');
      expect(checked('node-mainland'), findsOneWidget);
      await tapRow(tester, 'node-overseas');
      expect(prefs.node, NodeChoice.overseas);
      expect(world.engine.nodeModes.last, isA<OverseasNodes>());
    });

    testWidgets('a change while the engine is still starting reaches it once it has started, with no player made', (
      tester,
    ) async {
      final gate = Completer<void>();
      await show(tester, startGate: gate);
      expect(world.shared.running, isNull);
      await tapRow(tester, 'settings-btr');
      await tapRow(tester, 'node-mainland');
      expect(prefs.node, NodeChoice.mainland);
      expect(world.engine.nodeModes, isEmpty);
      gate.complete();
      await tester.pumpAndSettle();
      expect(world.shared.running, same(world.engine));
      expect(world.engine.nodeModes.single, isA<MainlandNodes>());
      expect(world.services.playback.live, 0);
    });

    testWidgets('picking the node already in use changes nothing', (tester) async {
      await show(tester);
      await tapRow(tester, 'settings-btr');
      await tapRow(tester, 'node-overseas');
      expect(world.engine.nodeModes, isEmpty);
    });
  });

  group('数据', () {
    testWidgets('清除最近观看 is off while 最近打开 is empty', (tester) async {
      await show(tester);
      expect(tester.widget<SettingsRow>(row('settings-recents')).enabled, isFalse);
      await tapRow(tester, 'settings-recents');
      expect(confirm, findsNothing);
    });

    testWidgets('清除最近观看 asks first, then empties 最近打开 and turns itself off', (tester) async {
      await show(tester);
      world.services.recents.add(sampleRecent);
      await tester.pump();
      await tapRow(tester, 'settings-recents');
      expect(find.descendant(of: confirm, matching: find.text('清除最近观看？')), findsOneWidget);
      expect(find.descendant(of: confirm, matching: find.text('「最近在看的视频」列表会被清空。')), findsOneWidget);
      await tester.tap(confirmButton('清除'));
      await tester.pumpAndSettle();
      expect(world.services.recents.items, isEmpty);
      expect(tester.widget<SettingsRow>(row('settings-recents')).enabled, isFalse);
    });

    testWidgets('清除图片缓存 follows 清除最近观看 and shows what the stored pictures take', (tester) async {
      final pictures = FakeImageDiskCache(12345678);
      await show(tester, imageCache: pictures);
      final titles = rowTitles(tester);
      expect(titles.indexOf('清除图片缓存'), titles.indexOf('清除最近观看') + 1);
      expect(text('settings-images', '11.8 MB'), findsOneWidget);
    });

    testWidgets('清除图片缓存 asks first, then clears the pictures and shows the new size', (tester) async {
      final pictures = FakeImageDiskCache(3 * 1024 * 1024);
      await show(tester, imageCache: pictures);
      expect(text('settings-images', '3.0 MB'), findsOneWidget);
      await tapRow(tester, 'settings-images');
      expect(find.descendant(of: confirm, matching: find.text('清除图片缓存？')), findsOneWidget);
      expect(find.descendant(of: confirm, matching: find.text('保存在手机上的图片会被删除，再看到时会重新下载。')), findsOneWidget);
      expect(pictures.clears, 0);
      await tester.tap(confirmButton('清除'));
      await tester.pumpAndSettle();
      expect(pictures.clears, 1);
      expect(confirm, findsNothing);
      expect(text('settings-images', '0.0 MB'), findsOneWidget);
    });

    testWidgets('清除图片缓存 that fails is logged, not thrown', (tester) async {
      final logs = MemorySink();
      Logger.shared.add(logs);
      addTearDown(() => Logger.shared.remove(logs));
      final pictures = FakeImageDiskCache(1024)..clearError = const FileSystemException('Deletion failed');
      await show(tester, imageCache: pictures);
      await tapRow(tester, 'settings-images');
      await tester.tap(confirmButton('清除'));
      await tester.pumpAndSettle();
      expect(pictures.clears, 1);
      expect(confirm, findsNothing);
      final warning = logs.events.where((event) => event.msg == 'image cache not cleared').single;
      expect(warning.f['error']?.toJson(), 'FileSystemException');
    });

    testWidgets('取消 on 清除图片缓存 keeps the pictures', (tester) async {
      final pictures = FakeImageDiskCache(1024);
      await show(tester, imageCache: pictures);
      await tapRow(tester, 'settings-images');
      await tester.tap(confirmButton('取消'));
      await tester.pumpAndSettle();
      expect(pictures.clears, 0);
      expect(text('settings-images', '0.0 MB'), findsOneWidget);
    });

    testWidgets('without pictures kept on the phone there is no 清除图片缓存', (tester) async {
      await show(tester);
      expect(row('settings-images'), findsNothing);
    });

    test('a size reads in MB with one decimal', () {
      expect(megabytesLabel(0), '0.0 MB');
      expect(megabytesLabel(12900000), '12.3 MB');
      expect(megabytesLabel(500 * 1024 * 1024), '500.0 MB');
    });

    testWidgets('取消, the dim and back each close a confirm with nothing done', (tester) async {
      final pictures = FakeImageDiskCache(1024);
      await show(tester, account: const LoggedIn(name: '小明', vip: false), imageCache: pictures);
      world.services.recents.add(sampleRecent);
      await tester.pump();

      await tapRow(tester, 'settings-images');
      await tester.tap(confirmButton('取消'));
      await tester.pumpAndSettle();
      expect(confirm, findsNothing);

      await tapRow(tester, 'settings-recents');
      await tester.tapAt(const Offset(20, 900));
      await tester.pumpAndSettle();
      expect(confirm, findsNothing);

      await tapRow(tester, 'settings-images');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(confirm, findsNothing);
      expect(find.byType(SettingsPage), findsOneWidget, reason: 'back closed the confirm, not the page');

      await tapRow(tester, 'settings-logout');
      await tester.tap(confirmButton('取消'));
      await tester.pumpAndSettle();

      expect(pictures.clears, 0);
      expect(world.services.recents.items, hasLength(1));
      expect(world.environment.logouts, 0);
      expect(world.environment.account, isA<LoggedIn>());
    });
  });

  group('开发者', () {
    testWidgets('has no row without a page', (tester) async {
      await show(tester);
      expect(row('settings-developer'), findsNothing);
    });

    testWidgets('pushes the page it is given', (tester) async {
      await show(tester, developerPage: (_) => const Scaffold(body: Text('开发者页面')));
      await tapRow(tester, 'settings-developer');
      expect(find.text('开发者页面'), findsOneWidget);
    });
  });

  testWidgets('the version is the last thing on the page, as 版本 and the build', (tester) async {
    await show(tester);
    expect(find.text('版本'), findsNothing);
    expect(tester.widget<Text>(row('settings-version')).data, '版本 1.0.0 (10)');
    final list = find.descendant(of: find.byType(SettingsScaffold), matching: find.byType(ListView));
    final texts = tester.widgetList<Text>(
      find.descendant(of: list, matching: find.byType(Text), skipOffstage: false),
    );
    expect(texts.last.key, const ValueKey('settings-version'));
  });

  test('the build version reads as name (number)', () {
    expect(buildVersionLabel(), isNotEmpty);
  });

  group('退出登录', () {
    testWidgets('asks with 51\'s alert, then logs out and goes back home', (tester) async {
      await show(tester, account: const LoggedIn(name: '小明', vip: false));
      await tapRow(tester, 'settings-logout');
      expect(find.descendant(of: confirm, matching: find.text('退出登录')), findsOneWidget);
      expect(find.descendant(of: confirm, matching: find.byType(Checkbox)), findsNothing);
      expect(confirmButton('取消'), findsOneWidget);
      await tester.tap(confirmButton('确定'));
      await tester.pumpAndSettle();
      expect(world.environment.logouts, 1);
      expect(world.environment.account, isA<LoggedOut>());
      expect(find.byType(SettingsPage), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('a logout that left the login in the keychain stays on 设置, says so and offers 退出登录 again',
        (tester) async {
      await show(tester, account: const LoggedIn(name: '小明', vip: false));
      world.environment.logoutError = const LogoutIncomplete();
      await tapRow(tester, 'settings-logout');
      await tester.tap(confirmButton('确定'));
      await tester.pump();
      expect(find.text('退出登录失败，请重试'), findsOneWidget);
      // The toast runs out.
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(world.environment.account, isA<LoggedOut>());
      expect(find.byKey(const ValueKey('settings-logout')), findsOneWidget);

      await tapRow(tester, 'settings-logout');
      await tester.tap(confirmButton('确定'));
      await tester.pumpAndSettle();
      expect(world.environment.logouts, 2);
      expect(find.byType(SettingsPage), findsNothing);
    });
  });

  testWidgets('an open confirm hides the rows behind it from accessibility', (tester) async {
    final semantics = tester.ensureSemantics();
    await show(tester, imageCache: FakeImageDiskCache(1024));
    expect(find.semantics.byLabel('播放设置'), findsOne);
    await tapRow(tester, 'settings-images');
    expect(find.semantics.byLabel('播放设置'), findsNothing);
    expect(find.semantics.byLabel('清除'), findsOne);
    await tester.tap(confirmButton('取消'));
    await tester.pumpAndSettle();
    expect(find.semantics.byLabel('播放设置'), findsOne);
    semantics.dispose();
  });

  testWidgets('Reduce Motion: the confirm and BTR\'s switch change at once', (tester) async {
    await show(tester, reduceMotion: true, imageCache: FakeImageDiskCache(1024));
    await tester.tap(row('settings-images'));
    await tester.pump();
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    final opacity = tester.widget<Opacity>(find.ancestor(of: confirm, matching: find.byType(Opacity)).first);
    expect(opacity.opacity, 1);
    await tester.tap(confirmButton('取消'));
    await tester.pump();
    await tester.pump();
    expect(confirm, findsNothing);

    await tapRow(tester, 'settings-btr');
    await tester.tap(row('btr-switch'));
    await tester.pump();
    expect(tester.widget<AnimatedContainer>(find.byKey(const ValueKey('settings-switch'))).duration, Duration.zero);
    expect(tester.hasRunningAnimations, isFalse);
  });

  group('every row presses through accessibility, as the Windows test driver does', () {
    testWidgets('logged out: 登录, the playback pages, BTR and its page, the clearing rows, 开发者', (tester) async {
      final semantics = tester.ensureSemantics();
      final pictures = FakeImageDiskCache(1024);
      await show(tester, developerPage: (_) => const Scaffold(body: Text('开发者页面')), imageCache: pictures);
      world.services.recents.add(sampleRecent);
      await tester.pump();

      tester.semantics.tap(find.semantics.byLabel('登录'));
      await tester.pumpAndSettle();
      expect(world.gate.requests, 1);

      tester.semantics.tap(find.semantics.byLabel(RegExp(r'^首页推荐设置')));
      await tester.pumpAndSettle();
      expect(find.byType(HomeFeedSettingsPage), findsOneWidget);
      tester.semantics.tap(find.semantics.byLabel('返回'));
      await tester.pumpAndSettle();
      tester.semantics.tap(find.semantics.byLabel('播放设置'));
      await tester.pumpAndSettle();
      expect(find.text('自动播放设置'), findsOneWidget);
      tester.semantics.tap(find.semantics.byLabel('返回'));
      await tester.pumpAndSettle();

      tester.semantics.tap(find.semantics.byLabel(RegExp(r'^BTR\s+开启$')));
      await tester.pumpAndSettle();
      expect(find.byType(BtrPage), findsOneWidget);
      tester.semantics.tap(find.semantics.byLabel('BTR 加速'));
      await tester.pumpAndSettle();
      expect(prefs.btr, isFalse);
      tester.semantics.tap(find.semantics.byLabel('大陆节点'));
      await tester.pumpAndSettle();
      expect(prefs.node, NodeChoice.mainland);
      expect(world.engine.nodeModes.last, isA<MainlandNodes>());
      tester.semantics.tap(find.semantics.byLabel('海外节点'));
      await tester.pumpAndSettle();
      expect(prefs.node, NodeChoice.overseas);
      tester.semantics.tap(find.semantics.byLabel('返回'));
      await tester.pumpAndSettle();
      expect(find.semantics.byLabel(RegExp(r'^BTR\s+关闭$')), findsOne);

      tester.semantics.tap(find.semantics.byLabel('清除最近观看'));
      await tester.pumpAndSettle();
      tester.semantics.tap(find.semantics.byLabel('清除'));
      await tester.pumpAndSettle();
      expect(world.services.recents.items, isEmpty);

      await tester.ensureVisible(row('settings-images'));
      await tester.pumpAndSettle();
      tester.semantics.tap(find.semantics.byLabel(RegExp('^清除图片缓存')));
      await tester.pumpAndSettle();
      tester.semantics.tap(find.semantics.byLabel('清除'));
      await tester.pumpAndSettle();
      expect(pictures.clears, 1);

      await tester.ensureVisible(row('settings-developer'));
      await tester.pumpAndSettle();
      tester.semantics.tap(find.semantics.byLabel('开发者'));
      await tester.pumpAndSettle();
      expect(find.text('开发者页面'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('login expired: 重新登录; logged in: 退出登录', (tester) async {
      final semantics = tester.ensureSemantics();
      await show(tester, account: const LoginExpired());
      tester.semantics.tap(find.semantics.byLabel('重新登录'));
      await tester.pumpAndSettle();
      expect(world.gate.requests, 1);

      world.environment.account = const LoggedIn(name: '小明', vip: false);
      await tester.pump();
      await tester.ensureVisible(row('settings-logout'));
      await tester.pumpAndSettle();
      tester.semantics.tap(find.semantics.byLabel('退出登录'));
      await tester.pumpAndSettle();
      tester.semantics.tap(find.semantics.byLabel('确定'));
      await tester.pumpAndSettle();
      expect(world.environment.logouts, 1);
      semantics.dispose();
    });
  });

  test('the node choice is saved to player_prefs.json and read back', () async {
    final folder = await Directory.systemTemp.createTemp('settings_prefs');
    addTearDown(() => folder.delete(recursive: true));
    final path = '${folder.path}${Platform.pathSeparator}player_prefs.json';
    final saved = await PlayerPrefs.load(path);
    expect(saved.node, NodeChoice.overseas);
    saved.node = NodeChoice.mainland;
    await saved.settle();
    expect(await File(path).readAsString(), contains('"node":"mainland"'));
    final read = await PlayerPrefs.load(path);
    expect(read.node, NodeChoice.mainland);
    expect(read.node.mode, isA<MainlandNodes>());
  });
}
