import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/route_observer.dart';
import 'package:bilifast/home/main_shell.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/settings/settings_confirm.dart';
import 'package:bilifast/settings/settings_page.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/sideload/sideload_links.dart';
import 'package:bilifast/sideload/sideload_model.dart';
import 'package:bilifast/sideload/sideload_prompts.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../home/fake_login_gate.dart' as home;
import '../home/feed_fakes.dart';
import '../playback/fakes.dart';
import '../settings/settings_fakes.dart';

/// The model's surface as 设置 and the alerts read it, set by the test; the calls the UI makes are recorded.
class TestSideload extends SideloadModel {
  TestSideload({
    this.expires,
    this.days,
    this.release,
    this.isChecking = false,
    this.reminder = false,
    this.askReminder = false,
    this.warnExpiry = false,
    this.announceRelease = false,
  }) : super.none();

  DateTime? expires;
  int? days;
  ReleaseInfo? release;
  bool isChecking;
  bool reminder;
  bool askReminder;
  bool warnExpiry;
  bool announceRelease;
  final calls = <String>[];

  @override
  SignatureInfo? get signature => switch (expires) {
    final expires? => SignatureInfo(expires: expires),
    null => null,
  };

  @override
  int? get daysLeft => days;

  @override
  ReleaseInfo? get newer => release;

  @override
  bool get checking => isChecking;

  @override
  bool get reminderOn => reminder;

  @override
  bool get shouldAskReminder => askReminder;

  @override
  bool get shouldWarnExpiry => warnExpiry;

  @override
  bool get shouldAnnounceRelease => announceRelease;

  @override
  Future<void> checkNow() async => calls.add('checkNow');

  @override
  Future<void> setReminder(bool on) async {
    calls.add('setReminder($on)');
    reminder = on;
    notifyListeners();
  }

  @override
  Future<void> answerReminder(bool yes) async {
    calls.add('answerReminder($yes)');
    askReminder = false;
  }

  @override
  void expiryWarned() {
    calls.add('expiryWarned');
    warnExpiry = false;
  }

  @override
  void releaseAnnounced() {
    calls.add('releaseAnnounced');
    announceRelease = false;
  }

  void changed() => notifyListeners();
}

final _release = ReleaseInfo(
  version: '1.3.0',
  build: 9,
  page: Uri.parse('https://github.com/KaiC5504/BiliFast/releases/tag/v1.3.0-9'),
);

/// A sideloaded install signed until 10 November, 3 days left, nothing due.
TestSideload _signed({
  int days = 3,
  bool checking = false,
  ReleaseInfo? release,
  bool reminder = false,
  bool askReminder = false,
  bool warnExpiry = false,
  bool announceRelease = false,
}) => TestSideload(
  expires: DateTime(2026, 11, 10, 9),
  days: days,
  isChecking: checking,
  release: release,
  reminder: reminder,
  askReminder: askReminder,
  warnExpiry: warnExpiry,
  announceRelease: announceRelease,
);

/// Links opened and asked about, answering [installed] to the signers' links.
class _Links {
  _Links({this.installed = const {}});

  final Set<Uri> installed;
  final opened = <Uri>[];
  final asked = <Uri>[];

  Future<bool> open(Uri link) async {
    opened.add(link);
    return true;
  }

  Future<bool> canOpen(Uri link) async {
    asked.add(link);
    return installed.contains(link);
  }
}

Future<AppServices> _services(WidgetTester tester, SideloadModel sideload) async {
  final playback = AppPlayback(() => Completer<PlaybackController>().future);
  addTearDown(playback.dispose);
  return AppServices(
    environment: FakeEnvironment(const LoggedOut()),
    playback: playback,
    recents: await RecentStore.load(null),
    pageApi: FakePageApi(),
    loginGate: FakeLoginGate(),
    sideload: sideload,
  );
}

Finder _row(String key) => find.byKey(ValueKey(key));
Finder _in(String key, String text) => find.descendant(of: _row(key), matching: find.text(text));
Finder _confirmButton(String label) => find.byKey(ValueKey('settings-confirm-$label'));
Finder _choice(String label) => find.byKey(ValueKey('source-choice-$label'));

void main() {
  group('设置\'s 签名 section', () {
    late _Links links;

    Future<void> show(WidgetTester tester, SideloadModel sideload) async {
      tester.view
        ..physicalSize = const Size(440, 956) * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final services = await _services(tester, sideload);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => AppScope(services: services, child: child!),
          home: Builder(
            builder: (context) => Center(
              child: GestureDetector(
                key: const ValueKey('open-settings'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SettingsPage(
                      prefs: PlayerPrefs.memory(),
                      version: '1.3.0 (8)',
                      openLink: links.open,
                      canOpenLink: links.canOpen,
                    ),
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

    Future<void> tapRow(WidgetTester tester, String key) async {
      await tester.ensureVisible(_row(key));
      await tester.pumpAndSettle();
      await tester.tap(_row(key));
      await tester.pumpAndSettle();
    }

    setUp(() => links = _Links());

    testWidgets('hidden while the install isn\'t sideloaded, shown above 版本 once it is', (tester) async {
      final sideload = TestSideload();
      await show(tester, sideload);
      expect(_row('settings-signature'), findsNothing);
      expect(_row('settings-add-source'), findsNothing);
      expect(find.text('免费 Apple ID 签名 7 天后过期，到期前在 SideStore 或电脑上重新签名。'), findsNothing);
      expect(_row('settings-version'), findsOneWidget);

      sideload
        ..expires = DateTime(2026, 11, 10)
        ..days = 6;
      sideload.changed();
      await tester.pumpAndSettle();
      for (final key in ['settings-signature', 'settings-reminder', 'settings-update', 'settings-add-source']) {
        expect(_row(key), findsOneWidget, reason: key);
      }
      await tester.ensureVisible(_row('settings-version'));
      await tester.pumpAndSettle();
      expect(find.text('免费 Apple ID 签名 7 天后过期，到期前在 SideStore 或电脑上重新签名。'), findsOneWidget);
      expect(
        tester.getTopLeft(_row('settings-add-source')).dy,
        lessThan(tester.getTopLeft(_row('settings-version')).dy),
      );
    });

    testWidgets('the stock model shows nothing', (tester) async {
      await show(tester, SideloadModel.none());
      expect(_row('settings-signature'), findsNothing);
      expect(_row('settings-version'), findsOneWidget);
    });

    testWidgets('签名到期 shows the date and the days left, red from 2 days, 今天到期 on the day', (tester) async {
      final sideload = _signed();
      await show(tester, sideload);
      Text value(String text) => tester.widget<Text>(_in('settings-signature', text));
      expect(value('11月10日 · 还剩 3 天').style!.color, SettingsTheme.value);

      sideload.days = 2;
      sideload.changed();
      await tester.pumpAndSettle();
      expect(value('11月10日 · 还剩 2 天').style!.color, BiliColors.failure);

      sideload.days = 0;
      sideload.changed();
      await tester.pumpAndSettle();
      expect(value('11月10日 · 今天到期').style!.color, BiliColors.failure);

      await tapRow(tester, 'settings-signature');
      expect(sideload.calls, isEmpty);
    });

    testWidgets('到期提醒 is the model\'s reminder, and flipping it sets it', (tester) async {
      final sideload = _signed();
      await show(tester, sideload);
      expect(tester.getSemantics(_row('settings-reminder')), isSemantics(isToggled: false, hasToggledState: true));
      await tapRow(tester, 'settings-reminder');
      expect(sideload.calls, ['setReminder(true)']);
      expect(tester.getSemantics(_row('settings-reminder')), isSemantics(isToggled: true, hasToggledState: true));
      await tapRow(tester, 'settings-reminder');
      expect(sideload.calls, ['setReminder(true)', 'setReminder(false)']);
    });

    testWidgets('检查更新: 检查中… while checking, 已是最新 checks again, a newer release opens its page', (tester) async {
      final sideload = _signed(checking: true);
      await show(tester, sideload);
      expect(_in('settings-update', '检查中…'), findsOneWidget);

      sideload.isChecking = false;
      sideload.changed();
      await tester.pumpAndSettle();
      expect(_in('settings-update', '已是最新'), findsOneWidget);
      await tapRow(tester, 'settings-update');
      expect(sideload.calls, ['checkNow']);
      expect(links.opened, isEmpty);

      sideload.release = _release;
      sideload.changed();
      await tester.pumpAndSettle();
      expect(_in('settings-update', '有新版本 1.3.0 (9)'), findsOneWidget);
      await tapRow(tester, 'settings-update');
      expect(sideload.calls, ['checkNow']);
      expect(links.opened, [Uri.parse(releasesPage)]);
    });

    testWidgets('添加更新源 lists only the installed signers, and each opens its add-source link', (tester) async {
      links = _Links(installed: {sideStoreAddSource, featherAddSource});
      await show(tester, _signed());
      await tapRow(tester, 'settings-add-source');
      expect(links.asked.toSet(), {sideStoreAddSource, altStoreAddSource, featherAddSource});
      expect(find.byKey(const ValueKey('source-choice')), findsOneWidget);
      expect(_choice('SideStore'), findsOneWidget);
      expect(_choice('AltStore'), findsNothing);
      expect(_choice('Feather'), findsOneWidget);
      expect(_choice('复制源地址'), findsOneWidget);
      expect(_choice('取消'), findsOneWidget);
      expect(tester.getTopLeft(_choice('SideStore')).dy, lessThan(tester.getTopLeft(_choice('Feather')).dy));

      await tester.tap(_choice('SideStore'));
      await tester.pumpAndSettle();
      expect(links.opened, [sideStoreAddSource]);
      expect(find.byKey(const ValueKey('source-choice')), findsNothing);

      await tapRow(tester, 'settings-add-source');
      await tester.tap(_choice('Feather'));
      await tester.pumpAndSettle();
      expect(links.opened, [sideStoreAddSource, featherAddSource]);
    });

    testWidgets('添加更新源\'s choice answers accessibility presses', (tester) async {
      links = _Links(installed: {altStoreAddSource});
      final semantics = tester.ensureSemantics();
      await show(tester, _signed());
      await tapRow(tester, 'settings-add-source');
      expect(
        tester.getSemantics(_choice('AltStore')),
        isSemantics(label: 'AltStore', isButton: true, hasTapAction: true),
      );
      tester.semantics.tap(find.semantics.byLabel('AltStore'));
      await tester.pumpAndSettle();
      expect(links.opened, [altStoreAddSource]);
      semantics.dispose();
    });

    testWidgets('复制源地址 copies the source and toasts; 取消, the dim and back close the choice', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await show(tester, _signed());

      await tapRow(tester, 'settings-add-source');
      expect(_choice('SideStore'), findsNothing);
      await tester.tap(_choice('复制源地址'));
      await tester.pump();
      expect(copied, sourceUrl);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('toast')), findsOneWidget);
      expect(find.text('已复制'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('source-choice')), findsNothing);

      await tapRow(tester, 'settings-add-source');
      await tester.tap(_choice('取消'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('source-choice')), findsNothing);

      await tapRow(tester, 'settings-add-source');
      await tester.tapAt(const Offset(20, 100));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('source-choice')), findsNothing);

      await tapRow(tester, 'settings-add-source');
      await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('source-choice')), findsNothing);
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(links.opened, isEmpty);
    });
  });

  group('the launch alerts', () {
    late _Links links;

    setUp(() => links = _Links(installed: {sideStoreOpen}));

    /// A page holding the alerts in its Stack, as the shell does.
    Future<void> show(WidgetTester tester, SideloadModel sideload) async {
      tester.view
        ..physicalSize = const Size(440, 956)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [pageRoutes],
          home: Stack(
            children: [
              const Center(child: Text('shell')),
              Positioned.fill(
                child: SideloadPrompts(model: sideload, openLink: links.open, canOpenLink: links.canOpen),
              ),
            ],
          ),
        ),
      );
    }

    /// Past the quiet wait, the alert's own questions and its fade.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump(SideloadPrompts.settle);
      await tester.pump();
      await tester.pumpAndSettle();
    }

    final alert = find.byKey(const ValueKey('settings-confirm'));

    testWidgets('expiry: 打开 SideStore opens it, either button marks it warned', (tester) async {
      final sideload = _signed(days: 1, warnExpiry: true);
      await show(tester, sideload);
      await settle(tester);
      expect(find.byKey(const ValueKey('sideload-prompt-expiry')), findsOneWidget);
      expect(find.text('签名快过期了'), findsOneWidget);
      expect(find.text('还剩 1 天，过期后 BiliFast 会打不开，记得在 SideStore 或电脑上重新签名。'), findsOneWidget);
      expect(_confirmButton('知道了'), findsOneWidget);
      await tester.tap(_confirmButton('打开 SideStore'));
      await tester.pumpAndSettle();
      expect(sideload.calls, ['expiryWarned']);
      expect(links.opened, [sideStoreOpen]);
      expect(alert, findsNothing);
    });

    testWidgets('expiry on the day: 今天到期, and 知道了 only marks it warned', (tester) async {
      final sideload = _signed(days: 0, warnExpiry: true);
      await show(tester, sideload);
      await settle(tester);
      expect(find.text('今天到期，过期后 BiliFast 会打不开，记得在 SideStore 或电脑上重新签名。'), findsOneWidget);
      await tester.tap(_confirmButton('知道了'));
      await tester.pumpAndSettle();
      expect(sideload.calls, ['expiryWarned']);
      expect(links.opened, isEmpty);
      expect(alert, findsNothing);
    });

    testWidgets('expiry without SideStore: 知道了 alone', (tester) async {
      links = _Links();
      final sideload = _signed(days: 2, warnExpiry: true);
      await show(tester, sideload);
      await settle(tester);
      expect(links.asked, [sideStoreOpen]);
      expect(_confirmButton('打开 SideStore'), findsNothing);
      expect(_confirmButton('取消'), findsNothing);
      final button = tester.widget<Text>(find.descendant(of: _confirmButton('知道了'), matching: find.text('知道了')));
      expect(button.style!.color, SettingsTheme.confirmAction);
      await tester.tap(_confirmButton('知道了'));
      await tester.pumpAndSettle();
      expect(sideload.calls, ['expiryWarned']);
    });

    testWidgets('release: 下载 opens the release page, either button marks it announced', (tester) async {
      final sideload = _signed(release: _release, announceRelease: true);
      await show(tester, sideload);
      await settle(tester);
      expect(find.text('有新版本 1.3.0 (9)'), findsOneWidget);
      expect(find.text('在 SideStore、AltStore 或 Feather 里更新，或者下载新的 IPA 覆盖安装。'), findsOneWidget);
      expect(_confirmButton('稍后'), findsOneWidget);
      await tester.tap(_confirmButton('下载'));
      await tester.pumpAndSettle();
      expect(sideload.calls, ['releaseAnnounced']);
      expect(links.opened, [Uri.parse(releasesPage)]);
      expect(alert, findsNothing);
    });

    testWidgets('release: 稍后 only marks it announced', (tester) async {
      final sideload = _signed(release: _release, announceRelease: true);
      await show(tester, sideload);
      await settle(tester);
      await tester.tap(_confirmButton('稍后'));
      await tester.pumpAndSettle();
      expect(sideload.calls, ['releaseAnnounced']);
      expect(links.opened, isEmpty);
    });

    testWidgets('reminder: 好 and 不用 answer it', (tester) async {
      for (final (label, yes) in [('好', true), ('不用', false)]) {
        final sideload = _signed(askReminder: true);
        await show(tester, sideload);
        await settle(tester);
        expect(find.text('签名到期前提醒你？'), findsOneWidget);
        expect(find.text('免费 Apple ID 签名 7 天后过期，到期前一天发通知提醒你重新签名。'), findsOneWidget);
        await tester.tap(_confirmButton(label));
        await tester.pumpAndSettle();
        expect(sideload.calls, ['answerReminder($yes)']);
        expect(alert, findsNothing);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('the buttons answer accessibility presses', (tester) async {
      final semantics = tester.ensureSemantics();
      final sideload = _signed(askReminder: true);
      await show(tester, sideload);
      await settle(tester);
      expect(tester.getSemantics(_confirmButton('好')), isSemantics(label: '好', isButton: true, hasTapAction: true));
      tester.semantics.tap(find.semantics.byLabel('好'));
      await tester.pumpAndSettle();
      expect(sideload.calls, ['answerReminder(true)']);
      semantics.dispose();
    });

    testWidgets('back answers as the other button', (tester) async {
      final sideload = _signed(askReminder: true);
      await show(tester, sideload);
      await settle(tester);
      expect(alert, findsOneWidget);
      await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
      await tester.pumpAndSettle();
      expect(sideload.calls, ['answerReminder(false)']);
      expect(alert, findsNothing);
      expect(find.text('shell'), findsOneWidget);
    });

    testWidgets('expiry goes before a release, and a launch has one alert at most', (tester) async {
      final sideload = _signed(days: 1, warnExpiry: true, release: _release, announceRelease: true, askReminder: true);
      await show(tester, sideload);
      await settle(tester);
      expect(find.text('签名快过期了'), findsOneWidget);
      await tester.tap(_confirmButton('知道了'));
      await tester.pumpAndSettle();
      sideload.changed();
      await settle(tester);
      expect(alert, findsNothing);

      // The shell built again on the same launch asks nothing either.
      await tester.pumpWidget(const SizedBox());
      await show(tester, sideload);
      await settle(tester);
      expect(alert, findsNothing);
      expect(sideload.calls, ['expiryWarned']);
    });

    testWidgets('a release goes before the reminder question', (tester) async {
      final sideload = _signed(release: _release, announceRelease: true, askReminder: true);
      await show(tester, sideload);
      await settle(tester);
      expect(find.text('有新版本 1.3.0 (9)'), findsOneWidget);
      expect(find.text('签名到期前提醒你？'), findsNothing);
    });

    testWidgets('nothing before start settles: the quiet wait, then the release check\'s end', (tester) async {
      final sideload = TestSideload();
      await show(tester, sideload);
      await tester.pump(const Duration(seconds: 5));
      expect(alert, findsNothing);

      sideload
        ..expires = DateTime(2026, 11, 10)
        ..days = 6
        ..askReminder = true
        ..isChecking = true;
      sideload.changed();
      await tester.pump(SideloadPrompts.settle - const Duration(milliseconds: 100));
      expect(alert, findsNothing);
      await settle(tester);
      expect(alert, findsNothing);

      sideload
        ..isChecking = false
        ..release = _release
        ..announceRelease = true;
      sideload.changed();
      await settle(tester);
      expect(find.text('有新版本 1.3.0 (9)'), findsOneWidget);
    });

    testWidgets('an expiry doesn\'t wait for the release check', (tester) async {
      final sideload = _signed(days: 1, warnExpiry: true, checking: true);
      await show(tester, sideload);
      await settle(tester);
      expect(find.text('签名快过期了'), findsOneWidget);
    });

    testWidgets('settled with nothing due, a later change asks nothing', (tester) async {
      final sideload = _signed();
      await show(tester, sideload);
      await settle(tester);
      sideload
        ..release = _release
        ..announceRelease = true;
      sideload.changed();
      await settle(tester);
      expect(alert, findsNothing);
    });

    testWidgets('a page over the shell holds the alert until it leaves', (tester) async {
      final sideload = _signed(askReminder: true);
      await show(tester, sideload);
      unawaited(
        tester
            .state<NavigatorState>(find.byType(Navigator))
            .push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('video')))),
      );
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.byKey(const ValueKey('sideload-prompt-reminder'), skipOffstage: false), findsNothing);

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.text('签名到期前提醒你？'), findsOneWidget);
    });

    testWidgets('an install that isn\'t sideloaded is never asked', (tester) async {
      final sideload = TestSideload(askReminder: true, announceRelease: true, release: _release);
      await show(tester, sideload);
      sideload.changed();
      await settle(tester);
      expect(alert, findsNothing);
    });
  });

  testWidgets('the shell holds the launch alert over its pages and bar', (tester) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(bottom: 34)
      ..viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);
    final http = FeedHttp()..pages[1] = [for (var i = 0; i < 6; i++) feedItem('BV1s$i')];
    final logger = Logger(session: 'test');
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(StoredCookies(Canned.cookies)),
      http: http,
      logger: logger,
    );
    final playback = AppPlayback(() => throw StateError('no playback here'));
    addTearDown(playback.dispose);
    final sideload = _signed(release: _release, announceRelease: true);
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      loginGate: home.FakeLoginGate(),
      sideload: sideload,
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [pageRoutes],
        builder: (context, child) => AppScope(services: services, child: child!),
        home: const MainShell(),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const ValueKey('sideload-prompt-release')), findsOneWidget);
    final bar = tester.getRect(find.byKey(const ValueKey('home-tab-home')));
    expect(tester.getRect(find.byKey(const ValueKey('settings-confirm-dim'))).contains(bar.center), isTrue);
    await tester.tap(_confirmButton('稍后'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(sideload.calls, ['releaseAnnounced']);
    expect(find.byKey(const ValueKey('settings-confirm')), findsNothing);
  });

  group('SettingsConfirm\'s cancel label', () {
    Future<void> show(WidgetTester tester, Widget confirm) =>
        tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: confirm));

    testWidgets('is 取消 unless given, on the button and the dim', (tester) async {
      final semantics = tester.ensureSemantics();
      var cancels = 0;
      await show(tester, SettingsConfirm(title: '清除日志？', action: '清除', onConfirm: () {}, onCancel: () => cancels++));
      expect(_confirmButton('取消'), findsOneWidget);
      expect(_confirmButton('清除'), findsOneWidget);
      expect(find.semantics.byLabel('取消'), findsExactly(2));
      await tester.tap(_confirmButton('取消'));
      expect(cancels, 1);
      final cancel = tester.widget<Text>(find.descendant(of: _confirmButton('取消'), matching: find.text('取消')));
      expect(cancel.style!.color, SettingsTheme.confirmCancel);
      semantics.dispose();
    });

    testWidgets('a given label takes 取消\'s place', (tester) async {
      var cancels = 0;
      await show(
        tester,
        SettingsConfirm(title: '有新版本', action: '下载', onConfirm: () {}, cancel: '稍后', onCancel: () => cancels++),
      );
      expect(_confirmButton('取消'), findsNothing);
      await tester.tap(_confirmButton('稍后'));
      await tester.tapAt(const Offset(5, 5));
      expect(cancels, 2);
    });
  });
}
