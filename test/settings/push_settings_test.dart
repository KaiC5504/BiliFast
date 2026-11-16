import 'dart:ui' show Tristate;

import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/notify/notify_host.dart';
import 'package:bilifast/settings/push_settings_page.dart';
import 'package:bilifast/settings/settings_page.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'settings_fakes.dart';

const _kept = {
  'push-likes': '点赞',
  'push-replies': '评论',
  'push-mentions': '@',
  'push-messages': '聊天消息',
  'push-uploads': '关注up主的更新提醒',
};

const _drawn = {
  'push-recommend': '推荐可能感兴趣的内容',
  'push-hot': '热点',
  'push-events': '活动',
  'push-bangumi': '追番追剧更新提醒',
  'push-live': '直播提醒',
  'push-collection': '订阅合集更新提醒',
  'push-search': '搜索内容更新提醒',
  'push-reserve': '其他订阅/预约提醒',
  'push-creator': '投稿服务通知',
  'push-orders': '物流与订单通知',
  'push-vip': '增值服务通知',
  'push-security': '账号安全通知',
  'push-other': '其他通知',
  'push-banner': '应用内顶部横幅提醒',
};

const _denied = '请在系统设置中允许通知';
const _refreshOff = '请在系统设置中开启后台App刷新';

void main() {
  late FakeNotifyHost host;
  late int settingsOpened;

  setUp(() {
    host = FakeNotifyHost();
    settingsOpened = 0;
  });

  void phone(WidgetTester tester, {double height = 956}) {
    tester.view
      ..physicalSize = Size(440, height) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  /// The page on a phone tall enough to build every row at once; the look-alike test has it at the real height.
  Future<void> showPage(WidgetTester tester, {NotifyHost? notify}) async {
    phone(tester, height: 1800);
    await tester.pumpWidget(
      MaterialApp(
        home: PushSettingsPage(
          host: notify ?? host,
          openSettings: () async {
            settingsOpened += 1;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder row(String key) => find.byKey(ValueKey(key));
  final toast = find.text('暂未开放');

  bool isOn(WidgetTester tester, String key) =>
      tester.getSemantics(row(key)).getSemanticsData().flagsCollection.isToggled == Tristate.isTrue;

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.ensureVisible(row(key));
    await tester.pumpAndSettle();
    await tester.tap(row(key));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Lets a toast run out, so no timer is left when the test ends.
  Future<void> runOut(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  }

  /// The app leaves the screen, [meanwhile] runs (the user in iOS's Settings), and the app comes back.
  Future<void> awayAndBack(WidgetTester tester, void Function() meanwhile) async {
    for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    meanwhile();
    for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
  }

  group('设置', () {
    Future<SettingsWorld> show(WidgetTester tester, Account account) async {
      phone(tester);
      final world = await SettingsWorld.create(account: account, notify: host);
      addTearDown(world.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => AppScope(services: world.services, child: child!),
          home: SettingsPage(prefs: PlayerPrefs.memory(), version: '1.4.0 (2)'),
        ),
      );
      await tester.pumpAndSettle();
      return world;
    }

    for (final account in [const LoggedOut(), const LoggedIn(name: '小明', vip: true)]) {
      testWidgets('推送设置 sits alone after 播放设置 and before BTR, ${account.runtimeType}, and opens the page', (
        tester,
      ) async {
        await show(tester, account);
        final playback = tester.getRect(row('settings-playback'));
        final push = tester.getRect(row('settings-push'));
        final btr = tester.getRect(row('settings-btr'));
        expect(push.top, greaterThan(playback.bottom + 10), reason: 'its own section');
        expect(btr.top, greaterThan(push.bottom + 10), reason: 'BTR in the next one');
        expect(find.descendant(of: row('settings-push'), matching: find.text('推送设置')), findsOneWidget);

        await tap(tester, 'settings-push');
        await tester.pumpAndSettle();
        expect(find.byType(PushSettingsPage), findsOneWidget);
        expect(host.permissionReads, greaterThan(0), reason: 'the page reads AppScope\'s host');
        await tester.tap(find.byKey(const ValueKey('settings-back')).last);
        await tester.pumpAndSettle();
        expect(find.byType(PushSettingsPage), findsNothing);
      });
    }
  });

  testWidgets('the five switches start as kinds() has them and each change is saved with setKinds()', (tester) async {
    host
      ..allowed = NotifyPermission.allowed
      ..stored = const NotifyKinds(likes: true, uploads: true);
    await showPage(tester);
    expect(isOn(tester, 'push-likes'), isTrue);
    expect(isOn(tester, 'push-uploads'), isTrue);
    for (final key in ['push-replies', 'push-mentions', 'push-messages']) {
      expect(isOn(tester, key), isFalse, reason: key);
    }

    await tap(tester, 'push-replies');
    expect(host.saved.last, const NotifyKinds(likes: true, replies: true, uploads: true));
    await tap(tester, 'push-mentions');
    expect(host.saved.last, const NotifyKinds(likes: true, replies: true, mentions: true, uploads: true));
    await tap(tester, 'push-messages');
    expect(
      host.saved.last,
      const NotifyKinds(likes: true, replies: true, mentions: true, messages: true, uploads: true),
    );
    await tap(tester, 'push-likes');
    expect(host.saved.last, const NotifyKinds(replies: true, mentions: true, messages: true, uploads: true));
    await tap(tester, 'push-uploads');
    expect(host.saved.last, const NotifyKinds(replies: true, mentions: true, messages: true));
    expect(host.saved, hasLength(5));
    expect(isOn(tester, 'push-likes'), isFalse);
    expect(isOn(tester, 'push-replies'), isTrue);
    expect(host.requests, 0, reason: 'already allowed');
    expect(find.text(_denied), findsNothing);
  });

  testWidgets('every switch defaults off', (tester) async {
    await showPage(tester);
    for (final key in [..._kept.keys, ..._drawn.keys]) {
      expect(isOn(tester, key), isFalse, reason: key);
    }
  });

  group('turning one on', () {
    testWidgets('asks iOS first when it never has; allowed turns it on and saves it', (tester) async {
      await showPage(tester);
      await tap(tester, 'push-likes');
      expect(host.requests, 1);
      expect(isOn(tester, 'push-likes'), isTrue);
      expect(host.saved, [const NotifyKinds(likes: true)]);
      expect(find.text('[已开启]'), findsOneWidget, reason: '总开关 follows the answer');

      await tap(tester, 'push-replies');
      expect(host.requests, 1, reason: 'asked once');
      expect(host.saved.last, const NotifyKinds(likes: true, replies: true));
    });

    testWidgets('refused in the prompt: stays off, nothing saved, and the toast says where to allow it', (
      tester,
    ) async {
      host.answer = false;
      await showPage(tester);
      await tap(tester, 'push-messages');
      expect(host.requests, 1);
      expect(isOn(tester, 'push-messages'), isFalse);
      expect(host.saved, isEmpty);
      expect(find.text(_denied), findsOneWidget);
      expect(find.text('[已关闭]'), findsOneWidget);
      await runOut(tester);
    });

    testWidgets('already denied: no prompt, stays off, the toast', (tester) async {
      host.allowed = NotifyPermission.denied;
      await showPage(tester);
      await tap(tester, 'push-uploads');
      expect(host.requests, 0);
      expect(isOn(tester, 'push-uploads'), isFalse);
      expect(host.saved, isEmpty);
      expect(find.text(_denied), findsOneWidget);
      await runOut(tester);
    });

    testWidgets('turning one off never asks, even when denied', (tester) async {
      host
        ..allowed = NotifyPermission.denied
        ..stored = const NotifyKinds(mentions: true);
      await showPage(tester);
      await tap(tester, 'push-mentions');
      expect(host.requests, 0);
      expect(host.saved, [NotifyKinds.none]);
      expect(find.text(_denied), findsNothing);
    });

    testWidgets('where notifications don\'t exist (Windows) the switches still work, asking nothing', (tester) async {
      final none = NoNotifyHost();
      await showPage(tester, notify: none);
      for (final key in _kept.keys) {
        await tap(tester, key);
        expect(isOn(tester, key), isTrue, reason: key);
      }
      expect(
        await none.kinds(),
        const NotifyKinds(likes: true, replies: true, mentions: true, messages: true, uploads: true),
      );
      expect(find.text(_denied), findsNothing);
      expect(find.text('[已关闭]'), findsOneWidget);
    });
  });

  group('reading the switches', () {
    testWidgets('a read that fails is tried again, and its answer shows', (tester) async {
      host
        ..allowed = NotifyPermission.allowed
        ..stored = const NotifyKinds(likes: true)
        ..kindsFailures = 1;
      await showPage(tester);
      expect(host.kindsReads, 2);
      expect(isOn(tester, 'push-likes'), isTrue);
      await tap(tester, 'push-replies');
      expect(host.saved, [const NotifyKinds(likes: true, replies: true)]);
    });

    testWidgets('unreadable twice: no switch moves, so nothing overwrites what the phone keeps', (tester) async {
      host
        ..stored = const NotifyKinds(likes: true, uploads: true)
        ..kindsFailures = 2;
      await showPage(tester);
      expect(host.kindsReads, 2);
      for (final key in _kept.keys) {
        await tap(tester, key);
        expect(isOn(tester, key), isFalse, reason: key);
      }
      expect(host.saved, isEmpty);
      expect(host.stored, const NotifyKinds(likes: true, uploads: true));
      expect(host.requests, 0, reason: 'nothing asked for a switch that can\'t move');
    });
  });

  testWidgets('a save that fails puts the switch back, and a later one saves', (tester) async {
    host
      ..allowed = NotifyPermission.allowed
      ..stored = const NotifyKinds(uploads: true)
      ..saveError = StateError('not saved');
    await showPage(tester);
    await tap(tester, 'push-likes');
    expect(isOn(tester, 'push-likes'), isFalse);
    await tap(tester, 'push-uploads');
    expect(isOn(tester, 'push-uploads'), isTrue);
    expect(host.stored, const NotifyKinds(uploads: true));

    host.saveError = null;
    await tap(tester, 'push-likes');
    expect(isOn(tester, 'push-likes'), isTrue);
    expect(host.saved, [const NotifyKinds(likes: true, uploads: true)]);
  });

  group('后台App刷新 off', () {
    testWidgets('turning one on still saves it, and the toast says where to turn it on', (tester) async {
      host
        ..allowed = NotifyPermission.allowed
        ..backgroundRefresh = false;
      await showPage(tester);
      await tap(tester, 'push-likes');
      expect(isOn(tester, 'push-likes'), isTrue);
      expect(host.saved, [const NotifyKinds(likes: true)]);
      expect(find.text(_refreshOff), findsOneWidget);
      await runOut(tester);
    });

    testWidgets('turning one off says nothing', (tester) async {
      host
        ..allowed = NotifyPermission.allowed
        ..stored = const NotifyKinds(likes: true)
        ..backgroundRefresh = false;
      await showPage(tester);
      await tap(tester, 'push-likes');
      expect(host.saved, [NotifyKinds.none]);
      expect(find.text(_refreshOff), findsNothing);
    });

    testWidgets('read again when the app comes back to the screen', (tester) async {
      host.allowed = NotifyPermission.allowed;
      await showPage(tester);
      await tap(tester, 'push-likes');
      expect(find.text(_refreshOff), findsNothing, reason: 'on');
      await awayAndBack(tester, () => host.backgroundRefresh = false);
      await tap(tester, 'push-replies');
      expect(host.saved.last, const NotifyKinds(likes: true, replies: true));
      expect(find.text(_refreshOff), findsOneWidget);
      await runOut(tester);
    });
  });

  testWidgets('every switch tells accessibility whether it is on, as a switch rather than a button', (tester) async {
    host
      ..allowed = NotifyPermission.allowed
      ..stored = const NotifyKinds(likes: true);
    await showPage(tester);
    for (final key in [..._kept.keys, ..._drawn.keys]) {
      expect(
        tester.getSemantics(row(key)),
        isSemantics(hasToggledState: true, isToggled: key == 'push-likes', isButton: false, hasTapAction: true),
        reason: key,
      );
    }
    await tap(tester, 'push-replies');
    expect(tester.getSemantics(row('push-replies')), isSemantics(hasToggledState: true, isToggled: true));
  });

  testWidgets('each group starts where 189 and 190 have it, the rows inside it as they were', (tester) async {
    await showPage(tester);
    // The official's px from 点赞's top; 190's lined up with 189 by 订阅/预约通知's rows.
    const official = {
      'push-replies': 130,
      'push-mentions': 260,
      'push-messages': 484,
      'push-uploads': 708,
      'push-recommend': 931,
      'push-hot': 1061,
      'push-bangumi': 1415,
      'push-live': 1545,
      'push-creator': 2160,
      'push-orders': 2384,
      'push-vip': 2514,
      'push-security': 2738,
      'push-banner': 3091,
    };
    final likes = tester.getRect(row('push-likes')).top;
    for (final MapEntry(:key, :value) in official.entries) {
      expect((tester.getRect(row(key)).top - likes) * 3, closeTo(value, 0.01), reason: key);
    }
  });

  group('接收通知总开关', () {
    for (final (permission, state) in [
      (NotifyPermission.allowed, '[已开启]'),
      (NotifyPermission.denied, '[已关闭]'),
      (NotifyPermission.notDetermined, '[已关闭]'),
    ]) {
      testWidgets('shows $state when iOS answers ${permission.name}', (tester) async {
        host.allowed = permission;
        await showPage(tester);
        expect(find.descendant(of: row('push-master'), matching: find.text(state)), findsOneWidget);
        expect(find.text('接收通知总开关'), findsOneWidget);
        expect(find.text('请在您设备的“设置-通知”中，选择“BiliFast”进行修改'), findsOneWidget);
      });
    }

    testWidgets('reads iOS again when the app comes back to the screen', (tester) async {
      host.allowed = NotifyPermission.denied;
      await showPage(tester);
      expect(find.text('[已关闭]'), findsOneWidget);
      await awayAndBack(tester, () => host.allowed = NotifyPermission.allowed);
      expect(find.text('[已开启]'), findsOneWidget);
    });

    testWidgets('a tap opens the app\'s page in iOS\'s Settings', (tester) async {
      await showPage(tester);
      await tap(tester, 'push-master');
      expect(settingsOpened, 1);
      expect(toast, findsNothing);
    });
  });

  testWidgets('消息免打扰 and every drawn switch toast 暂未开放 and stay off', (tester) async {
    host.allowed = NotifyPermission.allowed;
    await showPage(tester);
    for (final key in ['push-quiet', ..._drawn.keys]) {
      await tap(tester, key);
      expect(toast, findsOneWidget, reason: key);
      if (key != 'push-quiet') expect(isOn(tester, key), isFalse, reason: key);
      await runOut(tester);
    }
    expect(host.saved, isEmpty);
    expect(settingsOpened, 0);
  });

  testWidgets('every label, row and second line is drawn, in 189 and 190\'s order', (tester) async {
    await showPage(tester);
    final texts = find.descendant(of: find.byType(ListView), matching: find.byType(Text));
    final lines = [
      for (final element in texts.evaluate())
        (top: (element.renderObject! as RenderBox).localToGlobal(Offset.zero).dy, text: (element.widget as Text).data!),
    ]..sort((a, b) => a.top.compareTo(b.top));
    expect(lines.map((line) => line.text), [
      '接收通知总开关',
      '[已关闭]',
      '请在您设备的“设置-通知”中，选择“BiliFast”进行修改',
      '消息免打扰',
      '开启后，免打扰时间内将不会收到推送消息',
      '互动通知',
      '点赞',
      '评论',
      '@',
      '私信通知',
      '聊天消息',
      '关注通知',
      '关注up主的更新提醒',
      '内容推荐',
      '推荐可能感兴趣的内容',
      '热点',
      '活动',
      '订阅/预约通知',
      '追番追剧更新提醒',
      '直播提醒',
      '订阅合集更新提醒',
      '搜索内容更新提醒',
      '其他订阅/预约提醒',
      'UP主小助手',
      '投稿服务通知',
      '服务通知',
      '物流与订单通知',
      '增值服务通知',
      '其他通知',
      '账号安全通知',
      '其他通知',
      'APP内通知横幅',
      '应用内顶部横幅提醒',
      '开启后，应用使用期间会收到推送通知',
    ]);
    for (final (key, title) in [..._kept.entries, ..._drawn.entries].map((entry) => (entry.key, entry.value))) {
      expect(
        find.descendant(of: row(key), matching: find.text(title)),
        findsOneWidget,
        reason: key,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('every row and switch takes an accessibility press, which does what a tap does', (tester) async {
    final handle = tester.ensureSemantics();
    host.allowed = NotifyPermission.allowed;
    await showPage(tester);
    for (final key in ['push-master', 'push-quiet', ..._kept.keys, ..._drawn.keys]) {
      await tester.ensureVisible(row(key));
      await tester.pumpAndSettle();
      final node = tester.getSemantics(row(key));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue, reason: key);
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      if (_kept.containsKey(key)) expect(isOn(tester, key), isTrue, reason: key);
      await runOut(tester);
    }
    expect(settingsOpened, 1);
    expect(
      host.saved.last,
      const NotifyKinds(likes: true, replies: true, mentions: true, messages: true, uploads: true),
    );
    handle.dispose();
  });
}
