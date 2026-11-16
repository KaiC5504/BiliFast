import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:bili_core/api.dart';
import 'package:bilifast/message/fake_message_api.dart';
import 'package:bilifast/message/settings/message_settings_page.dart';
import 'package:bilifast/message/settings/notice_picker_page.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'message_settings_support.dart';

const _drawn = {
  'message-settings-intercept': '私信智能拦截',
  'message-settings-block-words': '消息屏蔽词',
  'message-settings-support': '应援团消息',
  'message-settings-strangers': '未关注人消息',
  'message-settings-blacklist': '黑名单',
};

const _soon = '暂未开放';

void main() {
  Future<MessageSettingsWorld> show(WidgetTester tester, {FakeMessageApi? api, bool badgeOn = true}) async {
    phone(tester);
    final world = await MessageSettingsWorld.create(api: api, badgeOn: badgeOn);
    await world.pump(tester, const MessageSettingsPage());
    return world;
  }

  bool isOn(WidgetTester tester, String key) =>
      tester.getSemantics(byKey(key)).getSemanticsData().flagsCollection.isToggled == Tristate.isTrue;

  String? valueOf(WidgetTester tester, NoticeSettingKind kind) {
    final value = find.descendant(
      of: byKey('message-settings-${kind.name}'),
      matching: byKey('message-settings-value'),
    );
    if (value.evaluate().isEmpty) return null;
    return (tester.widget<Text>(value)).data;
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.ensureVisible(byKey(key));
    await tester.pumpAndSettle();
    await tester.tap(byKey(key));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('消息提醒', () {
    for (final on in [true, false]) {
      testWidgets('starts as the model has it (${on ? 'on' : 'off'}), and a tap saves the other', (tester) async {
        final world = await show(tester, badgeOn: on);
        expect(isOn(tester, 'message-settings-badge'), on);
        await tap(tester, 'message-settings-badge');
        expect(world.messages.saves, [!on]);
        expect(isOn(tester, 'message-settings-badge'), !on);
        await tap(tester, 'message-settings-badge');
        expect(world.messages.saves, [!on, on]);
        expect(isOn(tester, 'message-settings-badge'), on);
      });
    }

    testWidgets('moves at once, before the save lands', (tester) async {
      final world = await show(tester);
      final gate = world.messages.saveGate = Completer<void>();
      await tap(tester, 'message-settings-badge');
      expect(isOn(tester, 'message-settings-badge'), isFalse);
      expect(world.messages.on, isTrue, reason: 'not saved yet');
      gate.complete();
      await tester.pumpAndSettle();
      expect(isOn(tester, 'message-settings-badge'), isFalse);
      expect(world.messages.on, isFalse);
    });

    testWidgets('a save that fails goes back, with a toast', (tester) async {
      final world = await show(tester);
      world.messages.saveError = StateError('not saved');
      await tap(tester, 'message-settings-badge');
      await tester.pumpAndSettle();
      expect(isOn(tester, 'message-settings-badge'), isTrue);
      expect(find.text('设置失败，请稍后重试'), findsOneWidget);
      await runOutToast(tester);
    });
  });

  group('回复与@, 收到喜欢, 新增粉丝', () {
    testWidgets('show the account\'s choices, read once as the page opens', (tester) async {
      final api = FakeMessageApi(
        settings: const {
          NoticeSettingKind.replies: NoticeAudience.following,
          NoticeSettingKind.likes: NoticeAudience.off,
          NoticeSettingKind.fans: NoticeAudience.everyone,
        },
      );
      await show(tester, api: api);
      expect(callCount(api, 'noticeSettings'), 1);
      expect(valueOf(tester, NoticeSettingKind.replies), '关注的人');
      expect(valueOf(tester, NoticeSettingKind.likes), '不接收任何消息提醒');
      expect(valueOf(tester, NoticeSettingKind.fans), '接收提醒');
      expect(api.calls.where((call) => call.startsWith('setNoticeSetting')), isEmpty);
    });

    testWidgets('所有人 and 永不提醒 in 188\'s words', (tester) async {
      await show(tester, api: FakeMessageApi(settings: const {NoticeSettingKind.fans: NoticeAudience.off}));
      expect(valueOf(tester, NoticeSettingKind.replies), '所有人');
      expect(valueOf(tester, NoticeSettingKind.likes), '所有人');
      expect(valueOf(tester, NoticeSettingKind.fans), '永不提醒');
    });

    testWidgets('show nothing until the read answers', (tester) async {
      final api = FakeMessageApi();
      final hold = api.holds['noticeSettings'] = Completer<void>();
      phone(tester);
      final world = await MessageSettingsWorld.create(api: api);
      await world.pump(tester, const MessageSettingsPage());
      for (final kind in NoticeSettingKind.values) {
        expect(valueOf(tester, kind), isNull, reason: kind.name);
      }
      hold.complete();
      await tester.pumpAndSettle();
      expect(valueOf(tester, NoticeSettingKind.replies), '所有人');
    });

    for (final kind in NoticeSettingKind.values) {
      testWidgets('${kind.title} opens its picker, and coming back shows what was picked there', (tester) async {
        final api = FakeMessageApi();
        await show(tester, api: api);
        await tap(tester, 'message-settings-${kind.name}');
        await tester.pumpAndSettle();
        final picker = tester.widget<NoticePickerPage>(find.byType(NoticePickerPage));
        expect(picker.kind, kind);
        expect(find.text(kind.pickerTitle), findsOneWidget);

        await tester.tap(byKey('notice-picker-off'));
        await tester.pumpAndSettle();
        expect(api.settings[kind], NoticeAudience.off);
        await tester.tap(byKey('message-settings-back'));
        await tester.pumpAndSettle();
        expect(find.byType(NoticePickerPage), findsNothing);
        expect(valueOf(tester, kind), kind.wordFor(NoticeAudience.off));
      });
    }

    testWidgets('where no call for them is known: no value, and a tap toasts instead of opening', (tester) async {
      final api = FakeMessageApi();
      api.failures['noticeSettings'] = UnsupportedError('no call');
      await show(tester, api: api);
      for (final kind in NoticeSettingKind.values) {
        expect(valueOf(tester, kind), isNull, reason: kind.name);
        await tap(tester, 'message-settings-${kind.name}');
        await tester.pumpAndSettle();
        expect(find.byType(NoticePickerPage), findsNothing, reason: kind.name);
        expect(find.text(_soon), findsOneWidget, reason: kind.name);
        await runOutToast(tester);
      }
      expect(callCount(api, 'noticeSettings'), 1);
    });

    testWidgets('a read that fails otherwise: no value, and the picker still opens', (tester) async {
      final api = FakeMessageApi();
      api.failures['noticeSettings'] = StateError('offline');
      await show(tester, api: api);
      expect(valueOf(tester, NoticeSettingKind.replies), isNull);
      await tap(tester, 'message-settings-likes');
      await tester.pumpAndSettle();
      expect(find.byType(NoticePickerPage), findsOneWidget);
      expect(find.text(_soon), findsNothing);
      await runOutToast(tester);
    });
  });

  testWidgets('私信智能拦截, 消息屏蔽词, 应援团消息, 未关注人消息 and 黑名单 toast 暂未开放 and change nothing', (tester) async {
    final world = await show(tester);
    expect(isOn(tester, 'message-settings-intercept'), isTrue);
    for (final key in _drawn.keys) {
      await tap(tester, key);
      expect(find.text(_soon), findsOneWidget, reason: key);
      expect(find.byType(NoticePickerPage), findsNothing, reason: key);
      await runOutToast(tester);
    }
    expect(isOn(tester, 'message-settings-intercept'), isTrue);
    expect(world.messages.saves, isEmpty);
    expect(world.api.calls, ['noticeSettings']);
  });

  testWidgets('every label, row and second line, in 188\'s order', (tester) async {
    await show(tester);
    final texts = find.descendant(of: find.byType(ListView), matching: find.byType(Text));
    final lines = [
      for (final element in texts.evaluate())
        (top: (element.renderObject! as RenderBox).localToGlobal(Offset.zero).dy, text: (element.widget as Text).data!),
    ]..sort((a, b) => a.top.compareTo(b.top));
    expect(lines.map((line) => line.text), [
      '消息提醒',
      '关闭后，APP首页将不再进行数字提醒',
      '消息接收设置',
      '私信智能拦截',
      '开启后，将自动拦截疑似骚扰和不良的会话',
      '消息屏蔽词',
      '添加后，将不再接受包含屏蔽词的消息',
      '互动通知',
      '回复与@',
      '所有人',
      '你将收到这些人的评论、弹幕等通知提醒',
      '收到喜欢',
      '所有人',
      '是否接收点赞等通知提醒',
      '新增粉丝',
      '接收提醒',
      '是否接收新增粉丝通知提醒',
      '应援团和未关注人',
      '应援团消息',
      '接收消息',
      '未关注人消息',
      '联系人',
      '黑名单',
    ]);
    expect(find.text('消息设置'), findsOneWidget);
  });

  testWidgets('every row takes an accessibility press, which does what a tap does', (tester) async {
    final handle = tester.ensureSemantics();
    final world = await show(tester);
    for (final key in ['message-settings-badge', ..._drawn.keys]) {
      await tester.ensureVisible(byKey(key));
      await tester.pumpAndSettle();
      final node = tester.getSemantics(byKey(key));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue, reason: key);
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await runOutToast(tester);
    }
    expect(world.messages.saves, [false]);

    final node = tester.getSemantics(byKey('message-settings-replies'));
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(find.byType(NoticePickerPage), findsOneWidget);
    final back = tester.getSemantics(byKey('message-settings-back').last);
    expect(back.label, '返回');
    back.owner!.performAction(back.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(find.byType(NoticePickerPage), findsNothing);
    handle.dispose();
  });

  group('the bar', () {
    testWidgets('takes the worn 装扮\'s second-page colour and text colour', (tester) async {
      phone(tester);
      final world = await MessageSettingsWorld.create(skin: greenSkin);
      await world.pump(tester, const MessageSettingsPage());
      final bar = tester.widget<ColoredBox>(byKey('message-settings-bar'));
      expect(bar.color, const Color(0xFFD9E8D3));
      expect(tester.widget<Text>(byKey('message-settings-title')).style?.color, const Color(0xFF000000));
    });

    testWidgets('is white with the page\'s text without one', (tester) async {
      await show(tester);
      final bar = tester.widget<ColoredBox>(byKey('message-settings-bar'));
      expect(bar.color, MessageSettingsTheme.bar);
      expect(tester.widget<Text>(byKey('message-settings-title')).style?.color, MessageSettingsTheme.barInk);
    });

    testWidgets('‹ goes back', (tester) async {
      phone(tester);
      final world = await MessageSettingsWorld.create();
      await world.pump(
        tester,
        Builder(
          builder: (context) => GestureDetector(
            key: const ValueKey('open'),
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MessageSettingsPage())),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.tap(byKey('open'));
      await tester.pumpAndSettle();
      expect(find.byType(MessageSettingsPage), findsOneWidget);
      await tester.tap(byKey('message-settings-back'));
      await tester.pumpAndSettle();
      expect(find.byType(MessageSettingsPage), findsNothing);
    });
  });
}
