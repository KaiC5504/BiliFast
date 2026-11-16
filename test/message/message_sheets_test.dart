import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/message/chat/chat_page.dart';
import 'package:bilifast/message/fake_message_api.dart';
import 'package:bilifast/message/message_sheets.dart';
import 'package:bilifast/message/settings/message_settings_page.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../home/fake_login_gate.dart';
import '../playback/fakes.dart';
import '../video/mixed_lines.dart' show appTheme;

final _now = DateTime(2026, 11, 16, 9, 55);

ChatSession _box(NoticeBox box) => ChatSession(
  talkerId: 900 + box.index,
  box: box,
  name: box.label,
  face: '',
  lastText: '演示通知',
  time: DateTime(2026, 11, 13, 9),
);

Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  /// A page with two buttons: ⋮'s sheet over [sessions] and 一键已读's alert, whose answers land in [answers].
  Future<List<bool>> show(WidgetTester tester, {List<ChatSession> sessions = const []}) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: 62, bottom: 34)
      ..viewPadding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    final logger = Logger(session: 'test');
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: Canned.http(),
      logger: logger,
    );
    await environment.refreshAccount();
    final playback = AppPlayback(() async => throw UnimplementedError());
    addTearDown(playback.dispose);
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      loginGate: FakeLoginGate(),
      messageApi: FakeMessageApi(),
    );
    final answers = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => AppScope(services: services, child: child!),
        home: Builder(
          builder: (context) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                key: const ValueKey('open-sheet'),
                behavior: HitTestBehavior.opaque,
                onTap: () => unawaited(showMessageMoreSheet(context, sessions: sessions, now: _now)),
                child: const SizedBox.square(dimension: 60),
              ),
              GestureDetector(
                key: const ValueKey('open-alert'),
                behavior: HitTestBehavior.opaque,
                onTap: () async => answers.add(await confirmReadAll(context)),
                child: const SizedBox.square(dimension: 60),
              ),
            ],
          ),
        ),
      ),
    );
    return answers;
  }

  Future<void> pick(WidgetTester tester, MessageSheetChoice choice) async {
    await tester.tap(_key('open-sheet'));
    await _settle(tester);
    await tester.tap(_key('message-sheet-${choice.name}'));
    await _settle(tester);
  }

  testWidgets('⋮\'s sheet: over the whole screen, its grabber, then eight 52 pt rows in 212\'s order on a white card '
      '16 in; a tap on the dim closes it', (tester) async {
    await show(tester);
    await tester.tap(_key('open-sheet'));
    await _settle(tester);
    final sheet = tester.getRect(_key('message-sheet'));
    expect(sheet.bottom, 956);
    expect(sheet.left, 0);
    expect(sheet.width, 440);
    final rows = [for (final choice in MessageSheetChoice.values) tester.getRect(_key('message-sheet-${choice.name}'))];
    expect(rows.first.top, sheet.top + MessageTabTheme.cardTop);
    for (final (i, row) in rows.indexed) {
      expect(row.left, MessageTabTheme.cardInset);
      expect(row.right, 440 - MessageTabTheme.cardInset);
      expect(row.height, MessageTabTheme.sheetRow);
      if (i > 0) expect(row.top, rows[i - 1].bottom);
    }
    expect(956 - rows.last.bottom, MessageTabTheme.cardBottom + 34);
    expect(
      [for (final choice in MessageSheetChoice.values) choice.label],
      ['消息设置', '通讯录', '应援团消息助手', '防骚扰和互动人群设置', '社区中心', '系统通知', '服务通知', '创作助手'],
    );
    for (final choice in MessageSheetChoice.values) {
      expect(find.text(choice.label), findsOneWidget);
    }

    await tester.tapAt(const Offset(220, 100));
    await _settle(tester);
    expect(_key('message-sheet'), findsNothing);
  });

  testWidgets('every row draws its glyph: the icon font\'s where the APK has it, else drawn', (tester) async {
    await show(tester);
    await tester.tap(_key('open-sheet'));
    await _settle(tester);
    String? asset(MessageSheetChoice choice) {
      final images = find.descendant(of: _key('message-sheet-${choice.name}'), matching: find.byType(Image));
      if (images.evaluate().isEmpty) return null;
      return (tester.widget<Image>(images).image as ExactAssetImage).assetName;
    }

    expect(asset(MessageSheetChoice.settings), 'assets/images/message/tab_sheet_settings.png');
    expect(asset(MessageSheetChoice.contacts), 'assets/images/message/tab_sheet_contacts.png');
    expect(asset(MessageSheetChoice.fanClub), 'assets/images/message/tab_sheet_fan_club.png');
    expect(asset(MessageSheetChoice.system), 'assets/images/message/tab_sheet_system.png');
    expect(asset(MessageSheetChoice.creator), 'assets/images/message/tab_sheet_creator.png');
    for (final choice in [MessageSheetChoice.harassment, MessageSheetChoice.community, MessageSheetChoice.service]) {
      expect(asset(choice), isNull, reason: choice.label);
      expect(
        find.descendant(of: _key('message-sheet-${choice.name}'), matching: find.byType(CustomPaint)),
        findsWidgets,
        reason: choice.label,
      );
    }
    for (final choice in MessageSheetChoice.values) {
      final row = tester.getRect(_key('message-sheet-${choice.name}'));
      final glyph = find.descendant(
        of: _key('message-sheet-${choice.name}'),
        matching: find.byWidgetPredicate((widget) => widget is Image || widget is CustomPaint),
      );
      expect(
        tester.getCenter(glyph.first).dx,
        moreOrLessEquals(row.left + MessageTabTheme.sheetGlyphCentre, epsilon: 0.01),
        reason: choice.label,
      );
    }
  });

  testWidgets('消息设置 opens its page', (tester) async {
    await show(tester);
    await pick(tester, MessageSheetChoice.settings);
    expect(_key('message-sheet'), findsNothing);
    expect(find.byType(MessageSettingsPage), findsOneWidget);
  });

  testWidgets('通讯录, 应援团消息助手 and 防骚扰和互动人群设置 say 暂未开放', (tester) async {
    await show(tester);
    for (final choice in [MessageSheetChoice.contacts, MessageSheetChoice.fanClub, MessageSheetChoice.harassment]) {
      await pick(tester, choice);
      expect(find.text('暂未开放'), findsOneWidget, reason: choice.label);
      expect(_key('message-sheet'), findsNothing);
      await _settle(tester, 60);
    }
    expect(find.byType(ChatPage), findsNothing);
  });

  testWidgets('系统通知 opens its own list as a session of box 系统通知', (tester) async {
    await show(tester);
    await pick(tester, MessageSheetChoice.system);
    final session = tester.widget<ChatPage>(find.byType(ChatPage)).session;
    expect(session.box, NoticeBox.system);
    expect(session.talkerId, 0);
    expect(session.name, '系统通知');
    expect(session.time, _now);
  });

  testWidgets('社区中心, 服务通知 and 创作助手 open the list\'s session of their box', (tester) async {
    final sessions = [
      for (final box in [NoticeBox.community, NoticeBox.service, NoticeBox.creator]) _box(box),
    ];
    await show(tester, sessions: sessions);
    for (final (choice, session) in [
      (MessageSheetChoice.community, sessions[0]),
      (MessageSheetChoice.service, sessions[1]),
      (MessageSheetChoice.creator, sessions[2]),
    ]) {
      await pick(tester, choice);
      expect(tester.widget<ChatPage>(find.byType(ChatPage)).session, session, reason: choice.label);
      Navigator.of(tester.element(find.byType(ChatPage))).pop();
      await _settle(tester);
    }
  });

  testWidgets('a box the list doesn\'t hold says 暂未开放', (tester) async {
    await show(tester, sessions: [_box(NoticeBox.service)]);
    for (final choice in [MessageSheetChoice.community, MessageSheetChoice.creator]) {
      await pick(tester, choice);
      expect(find.text('暂未开放'), findsOneWidget, reason: choice.label);
      expect(find.byType(ChatPage), findsNothing);
      await _settle(tester, 60);
    }
  });

  testWidgets('一键已读\'s alert (211): 280 wide in the middle of the safe area, its question, 取消 and pink 清除', (
    tester,
  ) async {
    final answers = await show(tester);
    await tester.tap(_key('open-alert'));
    await _settle(tester);
    final alert = tester.getRect(_key('message-read-all'));
    expect(alert.width, MessageTabTheme.alertWidth);
    expect(alert.center.dx, 220);
    expect(alert.center.dy, moreOrLessEquals((62 + 956 - 34) / 2, epsilon: 0.01));
    expect(
      alert.height,
      moreOrLessEquals(MessageTabTheme.alertBody + MessageTabTheme.alertRule + MessageTabTheme.alertButton),
    );
    expect(find.text('一键已读'), findsOneWidget);
    expect(find.text('是否清除全部新消息提醒?'), findsOneWidget);
    Color? colour(String label) => tester
        .widget<Text>(find.descendant(of: _key('message-read-all-$label'), matching: find.text(label)))
        .style
        ?.color;
    expect(colour('取消'), MessageTabTheme.alertCancel);
    expect(colour('清除'), MessageTabTheme.alertAction);

    await tester.tap(_key('message-read-all-清除'));
    await _settle(tester);
    expect(_key('message-read-all'), findsNothing);

    await tester.tap(_key('open-alert'));
    await _settle(tester);
    await tester.tap(_key('message-read-all-取消'));
    await _settle(tester);

    await tester.tap(_key('open-alert'));
    await _settle(tester);
    await tester.tapAt(const Offset(220, 100));
    await _settle(tester);
    expect(answers, [true, false, false]);
  });
}
