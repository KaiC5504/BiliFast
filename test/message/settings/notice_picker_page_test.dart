import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bilifast/message/fake_message_api.dart';
import 'package:bilifast/message/message_routes.dart';
import 'package:bilifast/message/settings/notice_picker_page.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'message_settings_support.dart';

const _words = {
  NoticeSettingKind.replies: ['所有人', '关注的人', '不接收任何消息提醒'],
  NoticeSettingKind.likes: ['所有人', '关注的人', '不接收任何消息提醒'],
  NoticeSettingKind.fans: ['接收提醒', '永不提醒'],
};

const _titles = {
  NoticeSettingKind.replies: '回复与@消息提醒',
  NoticeSettingKind.likes: '收到喜欢消息提醒',
  NoticeSettingKind.fans: '新增粉丝消息提醒',
};

void main() {
  Future<MessageSettingsWorld> show(WidgetTester tester, NoticeSettingKind kind, {FakeMessageApi? api}) async {
    phone(tester);
    final world = await MessageSettingsWorld.create(api: api);
    await world.pump(tester, NoticePickerPage(kind: kind));
    return world;
  }

  /// The choice with the ✓, by its key's name; null when none has it.
  String? chosen(WidgetTester tester) {
    final check = find.byKey(const ValueKey('message-settings-check'));
    if (check.evaluate().isEmpty) return null;
    final row = find.ancestor(of: check, matching: find.byWidgetPredicate((widget) => widget.key is ValueKey<String>));
    final keys = [
      for (final element in row.evaluate())
        if ((element.widget.key! as ValueKey<String>).value case final key when key.startsWith('notice-picker-'))
          key.substring('notice-picker-'.length),
    ];
    return keys.single;
  }

  Color? colourOf(WidgetTester tester, String words) => tester.widget<Text>(find.text(words)).style?.color;

  List<String> writes(FakeMessageApi api) => [
    for (final call in api.calls)
      if (call.startsWith('setNoticeSetting')) call,
  ];

  for (final kind in NoticeSettingKind.values) {
    testWidgets('${kind.name}: titled ${_titles[kind]}, its choices in its own words', (tester) async {
      await show(tester, kind);
      expect(find.text(_titles[kind]!), findsOneWidget);
      final rows = [for (final audience in kind.choices) tester.getRect(byKey('notice-picker-${audience.name}')).top];
      expect(rows, [...rows]..sort());
      expect([for (final audience in kind.choices) kind.wordFor(audience)], _words[kind]);
      for (final words in _words[kind]!) {
        expect(find.text(words), findsOneWidget, reason: words);
      }
    });
  }

  testWidgets('新增粉丝 has no 关注的人', (tester) async {
    await show(tester, NoticeSettingKind.fans);
    expect(byKey('notice-picker-following'), findsNothing);
    expect(find.text('关注的人'), findsNothing);
  });

  testWidgets('the account\'s choice has the ✓ and pink semibold words, the others plain', (tester) async {
    final api = FakeMessageApi(settings: const {NoticeSettingKind.likes: NoticeAudience.following});
    await show(tester, NoticeSettingKind.likes, api: api);
    expect(callCount(api, 'noticeSettings'), 1);
    expect(chosen(tester), 'following');
    expect(colourOf(tester, '关注的人'), MessageSettingsTheme.chosen);
    expect(tester.widget<Text>(find.text('关注的人')).style?.fontWeight, MessageSettingsTheme.chosenWeight);
    expect(colourOf(tester, '所有人'), MessageSettingsTheme.rowTitle);
    expect(colourOf(tester, '不接收任何消息提醒'), MessageSettingsTheme.rowTitle);
    expect(find.byKey(const ValueKey('message-settings-check')), findsOneWidget);
  });

  testWidgets('新增粉丝 on 关注的人 counts as 接收提醒', (tester) async {
    await show(
      tester,
      NoticeSettingKind.fans,
      api: FakeMessageApi(settings: const {NoticeSettingKind.fans: NoticeAudience.following}),
    );
    expect(chosen(tester), 'everyone');
  });

  for (final kind in NoticeSettingKind.values) {
    testWidgets('${kind.name}: a tap moves the ✓ at once and writes it once', (tester) async {
      final api = FakeMessageApi();
      final world = await show(tester, kind, api: api);
      expect(chosen(tester), 'everyone');
      final hold = api.holds['setNoticeSetting'] = Completer<void>();
      await tester.tap(byKey('notice-picker-off'));
      await tester.pump();
      expect(chosen(tester), 'off', reason: 'before the write lands');
      hold.complete();
      await tester.pumpAndSettle();
      expect(chosen(tester), 'off');
      expect(writes(api), ['setNoticeSetting ${kind.name} off']);
      expect(world.api.settings[kind], NoticeAudience.off);
    });
  }

  testWidgets('a tap on the chosen one writes nothing', (tester) async {
    final api = FakeMessageApi(settings: const {NoticeSettingKind.replies: NoticeAudience.following});
    await show(tester, NoticeSettingKind.replies, api: api);
    await tester.tap(byKey('notice-picker-following'));
    await tester.pumpAndSettle();
    expect(writes(api), isEmpty);
    expect(chosen(tester), 'following');

    await tester.tap(byKey('notice-picker-everyone'));
    await tester.pumpAndSettle();
    await tester.tap(byKey('notice-picker-everyone'));
    await tester.pumpAndSettle();
    expect(writes(api), ['setNoticeSetting replies everyone']);
  });

  testWidgets('a write that fails puts the ✓ back, with a toast; a later one writes', (tester) async {
    final api = FakeMessageApi();
    api.failures['setNoticeSetting'] = StateError('refused');
    await show(tester, NoticeSettingKind.likes, api: api);
    await tester.tap(byKey('notice-picker-following'));
    await tester.pumpAndSettle();
    expect(chosen(tester), 'everyone');
    expect(colourOf(tester, '所有人'), MessageSettingsTheme.chosen);
    expect(find.text('设置失败，请稍后重试'), findsOneWidget);
    expect(api.settings[NoticeSettingKind.likes], NoticeAudience.everyone);
    await runOutToast(tester);

    api.failures.clear();
    await tester.tap(byKey('notice-picker-following'));
    await tester.pumpAndSettle();
    expect(chosen(tester), 'following');
    expect(writes(api), ['setNoticeSetting likes following', 'setNoticeSetting likes following']);
  });

  testWidgets('a write with no call behind it puts the ✓ back and toasts 暂未开放', (tester) async {
    final api = FakeMessageApi();
    api.failures['setNoticeSetting'] = UnsupportedError('no call');
    await show(tester, NoticeSettingKind.fans, api: api);
    await tester.tap(byKey('notice-picker-off'));
    await tester.pumpAndSettle();
    expect(chosen(tester), 'everyone');
    expect(find.text('暂未开放'), findsOneWidget);
    await runOutToast(tester);
  });

  testWidgets('a tap while a write is out is dropped', (tester) async {
    final api = FakeMessageApi();
    await show(tester, NoticeSettingKind.replies, api: api);
    final hold = api.holds['setNoticeSetting'] = Completer<void>();
    await tester.tap(byKey('notice-picker-following'));
    await tester.pump();
    await tester.tap(byKey('notice-picker-off'));
    await tester.pump();
    expect(chosen(tester), 'following');
    hold.complete();
    await tester.pumpAndSettle();
    expect(writes(api), ['setNoticeSetting replies following']);
    expect(chosen(tester), 'following');
  });

  group('a read that fails', () {
    testWidgets('toasts, chooses nothing, and the page still writes', (tester) async {
      final api = FakeMessageApi();
      api.failures['noticeSettings'] = StateError('offline');
      await show(tester, NoticeSettingKind.replies, api: api);
      expect(chosen(tester), isNull);
      expect(find.text('加载失败，请稍后重试'), findsOneWidget);
      await runOutToast(tester);

      await tester.tap(byKey('notice-picker-everyone'));
      await tester.pumpAndSettle();
      expect(chosen(tester), 'everyone');
      expect(writes(api), ['setNoticeSetting replies everyone']);
    });

    testWidgets('with no call behind it toasts 暂未开放', (tester) async {
      final api = FakeMessageApi();
      api.failures['noticeSettings'] = UnsupportedError('no call');
      await show(tester, NoticeSettingKind.likes, api: api);
      expect(chosen(tester), isNull);
      expect(find.text('暂未开放'), findsOneWidget);
      await runOutToast(tester);
    });
  });

  testWidgets('a tap before the read answers is kept over the answer', (tester) async {
    final api = FakeMessageApi(settings: const {NoticeSettingKind.replies: NoticeAudience.off});
    final hold = api.holds['noticeSettings'] = Completer<void>();
    phone(tester);
    final world = await MessageSettingsWorld.create(api: api);
    await world.pump(tester, const NoticePickerPage(kind: NoticeSettingKind.replies));
    expect(chosen(tester), isNull);
    await tester.tap(byKey('notice-picker-following'));
    await tester.pumpAndSettle();
    hold.complete();
    await tester.pumpAndSettle();
    expect(chosen(tester), 'following');
    expect(writes(api), ['setNoticeSetting replies following']);
  });

  testWidgets('openNoticePicker pushes the picker for its kind, and ‹ goes back', (tester) async {
    phone(tester);
    final world = await MessageSettingsWorld.create();
    await world.pump(
      tester,
      Builder(
        builder: (context) => GestureDetector(
          key: const ValueKey('open'),
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(openNoticePicker(context, NoticeSettingKind.fans)),
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.tap(byKey('open'));
    await tester.pumpAndSettle();
    expect(find.text('新增粉丝消息提醒'), findsOneWidget);
    expect(chosen(tester), 'everyone');
    await tester.tap(byKey('message-settings-back'));
    await tester.pumpAndSettle();
    expect(find.byType(NoticePickerPage), findsNothing);
  });

  testWidgets('every choice takes an accessibility press and says whether it is chosen', (tester) async {
    final handle = tester.ensureSemantics();
    final api = FakeMessageApi();
    await show(tester, NoticeSettingKind.replies, api: api);
    expect(
      tester.getSemantics(byKey('notice-picker-everyone')),
      isSemantics(isSelected: true, isButton: true, hasTapAction: true, hasSelectedState: true),
    );
    final node = tester.getSemantics(byKey('notice-picker-following'));
    expect(node, isSemantics(isSelected: false, isButton: true, hasTapAction: true, hasSelectedState: true));
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(chosen(tester), 'following');
    expect(writes(api), ['setNoticeSetting replies following']);
    handle.dispose();
  });
}
