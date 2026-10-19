import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:bili_core/api.dart';
import 'package:bili_core/danmaku.dart';
import 'package:bilifast/danmaku/block_rule_store.dart';
import 'package:bilifast/danmaku/block_words_view.dart';
import 'package:bilifast/danmaku/danmaku_session.dart';
import 'package:bilifast/danmaku/danmaku_settings_store.dart';
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/playback/danmaku_feed.dart';
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';
import '../support/fake_player_session.dart';

class Rig {
  Rig(this.api, this.store, this.toasts, this.backs);

  final FakePageApi api;
  final BlockRuleStore store;
  final List<String> toasts;
  final List<int> backs;

  int get fetches => api.calls.where((call) => call == 'danmakuBlockRules').length;
}

const _rules = [
  BlockRule(id: 1, kind: BlockRuleKind.keyword, filter: 'CA'),
  BlockRule(id: 2, kind: BlockRuleKind.keyword, filter: 'CB'),
  BlockRule(id: 3, kind: BlockRuleKind.keyword, filter: '剧透'),
  BlockRule(id: 4, kind: BlockRuleKind.regex, filter: '/^6+\$/'),
  BlockRule(id: 5, kind: BlockRuleKind.user, filter: 'a1b2c3d4'),
];

Future<Rig> pumpView(WidgetTester tester, {bool loggedIn = true}) async {
  tester.view.physicalSize = const Size(956, 440);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = FakePageApi()..blockRules = [..._rules];
  final store = BlockRuleStore(api: api, isLoggedIn: () => loggedIn);
  final feed = DanmakuFeed(
    client: BiliClient(transport: Canned.http(), cookies: CookieJar(Canned.cookies)),
  );
  final settings = DanmakuSettingsStore.memory();
  final danmaku = DanmakuSession(
    feed: feed,
    settings: settings,
    rules: store,
    api: api,
    target: () => null,
    position: () => 0,
    isLoggedIn: () => loggedIn,
    isVip: () => false,
    accountMid: () => 0,
    requestLogin: () {},
  );
  final session = FakePlayerSession();
  final chrome = ChromeState();
  final panels = PanelController();
  final orientation = OrientationController()..enterLandscape();
  final ui = PlayerUi(
    session: session,
    chrome: chrome,
    panels: panels,
    orientation: orientation,
    device: NoDeviceControls(),
    onBack: () {},
    danmaku: danmaku,
  );
  final toasts = <String>[];
  final backs = <int>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(padding: const EdgeInsets.only(left: 62, right: 62, bottom: 21)),
          child: BlockWordsView(ui: ui, toast: toasts.add, back: () => backs.add(1), close: () {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() {
    danmaku.dispose();
    settings.dispose();
    feed.dispose();
    store.dispose();
    chrome.dispose();
    panels.dispose();
    orientation.dispose();
    session.dispose();
  });
  return Rig(api, store, toasts, backs);
}

Finder key(String value) => find.byKey(ValueKey(value));

Future<void> tap(WidgetTester tester, String value) async {
  await tester.tap(key(value));
  await tester.pumpAndSettle();
}

Future<void> type(WidgetTester tester, String text) async {
  await tester.enterText(key('block-words-field'), text);
  await tester.pump();
}

String fieldText(WidgetTester tester) => tester.widget<TextField>(key('block-words-field')).controller!.text;

void main() {
  testWidgets('opening refreshes the store and shows the keywords as chips', (tester) async {
    final rig = await pumpView(tester);
    expect(rig.fetches, 1);
    expect(find.text('CA'), findsOneWidget);
    expect(find.text('CB'), findsOneWidget);
    expect(find.text('剧透'), findsOneWidget);
    expect(find.text('/^6+\$/'), findsNothing);
    expect(find.text('a1b2c3d4'), findsNothing);
  });

  testWidgets('the chips fill two columns, the left one first, split at the centre', (tester) async {
    await pumpView(tester);
    final a = tester.getTopLeft(key('block-rule-1'));
    final b = tester.getTopLeft(key('block-rule-2'));
    final c = tester.getTopLeft(key('block-rule-3'));
    expect(a, const Offset(82, 94));
    expect(b, const Offset(498, 94));
    expect(c.dx, 82);
    expect(c.dy, 94 + BlockWordsTheme.chipHeight + BlockWordsTheme.rowGap);
  });

  testWidgets('each tab shows its own rules, the selected one pink with an underline', (tester) async {
    await pumpView(tester);
    Color? colour(String text) => tester.widget<Text>(find.text(text)).style?.color;
    expect(colour('关键词'), BlockWordsTheme.pink);
    expect(colour('正则'), BlockWordsTheme.text);

    await tap(tester, 'block-words-tab-regex');
    expect(find.text('/^6+\$/'), findsOneWidget);
    expect(find.text('CA'), findsNothing);
    expect(colour('正则'), BlockWordsTheme.pink);
    expect(colour('关键词'), BlockWordsTheme.text);

    await tap(tester, 'block-words-tab-user');
    expect(find.text('a1b2c3d4'), findsOneWidget);
    expect(find.text('/^6+\$/'), findsNothing);

    await tap(tester, 'block-words-tab-keyword');
    expect(find.text('CA'), findsOneWidget);
  });

  testWidgets('添加 sends plain text as a keyword and clears the field', (tester) async {
    final rig = await pumpView(tester);
    await type(tester, '剧场版');
    await tap(tester, 'block-words-add');
    expect(rig.api.calls.last, 'addBlockRule keyword=剧场版');
    expect(fieldText(tester), isEmpty);
    expect(find.text('剧场版'), findsOneWidget);
    expect(rig.toasts, isEmpty);
  });

  testWidgets('text between slashes is added as a regex, slashes kept, and 正则 shows it', (tester) async {
    final rig = await pumpView(tester);
    await type(tester, '/^哈+\$/');
    await tap(tester, 'block-words-add');
    expect(rig.api.calls.last, 'addBlockRule regex=/^哈+\$/');
    expect(find.text('/^哈+\$/'), findsOneWidget);
    expect(tester.widget<Text>(find.text('正则')).style?.color, BlockWordsTheme.pink);
    expect(find.text('CA'), findsNothing);
  });

  testWidgets('plain text added on another tab is a keyword, and 关键词 shows it', (tester) async {
    final rig = await pumpView(tester);
    for (final tab in ['block-words-tab-regex', 'block-words-tab-user']) {
      await tap(tester, tab);
      await type(tester, '新词 $tab');
      await tap(tester, 'block-words-add');
      expect(rig.api.calls.last, 'addBlockRule keyword=新词 $tab');
      expect(fieldText(tester), isEmpty);
      expect(find.text('新词 $tab'), findsOneWidget);
      expect(tester.widget<Text>(find.text('关键词')).style?.color, BlockWordsTheme.pink);
    }
  });

  testWidgets('a failure toasts through the panel even after the view has gone', (tester) async {
    final rig = await pumpView(tester);
    final add = Completer<void>(), remove = Completer<void>(), sync = Completer<void>();
    rig.api
      ..holds['addBlockRule'] = add
      ..holds['deleteBlockRule'] = remove
      ..holds['danmakuBlockRules'] = sync
      ..failures['addBlockRule'] = const BiliError.api(code: 36701, message: '屏蔽词数量已达上限')
      ..failures['deleteBlockRule'] = const BiliError.http(500)
      ..failures['danmakuBlockRules'] = const BiliError.http(500);
    await type(tester, '新词');
    await tap(tester, 'block-words-add');
    await tap(tester, 'block-rule-remove-1');
    await tap(tester, 'block-words-sync');
    await tester.pumpWidget(const SizedBox());
    add.complete();
    remove.complete();
    sync.complete();
    await tester.pump();
    expect(rig.toasts, ['屏蔽词数量已达上限', BlockRuleStore.removeFailed, BlockRuleStore.syncFailed]);
  });

  testWidgets('添加 with an empty field does nothing', (tester) async {
    final rig = await pumpView(tester);
    await type(tester, '   ');
    await tap(tester, 'block-words-add');
    expect(rig.api.calls.where((call) => call.startsWith('addBlockRule')), isEmpty);
    expect(rig.toasts, isEmpty);
  });

  testWidgets('a word already there toasts and stays typed', (tester) async {
    final rig = await pumpView(tester);
    await type(tester, 'CA');
    await tap(tester, 'block-words-add');
    expect(rig.toasts, [BlockRuleStore.duplicateMessage]);
    expect(fieldText(tester), 'CA');
  });

  testWidgets('a refusal toasts the server\'s words and keeps the text', (tester) async {
    final rig = await pumpView(tester);
    rig.api.failures['addBlockRule'] = const BiliError.api(code: 36701, message: '屏蔽词数量已达上限');
    await type(tester, '新词');
    await tap(tester, 'block-words-add');
    expect(rig.toasts, ['屏蔽词数量已达上限']);
    expect(fieldText(tester), '新词');
  });

  testWidgets('✕ on a chip removes the rule', (tester) async {
    final rig = await pumpView(tester);
    await tap(tester, 'block-rule-remove-1');
    expect(rig.api.calls.last, 'deleteBlockRule id=1');
    expect(find.text('CA'), findsNothing);
    expect(rig.store.rules.map((rule) => rule.id), isNot(contains(1)));
  });

  testWidgets('a failed removal toasts', (tester) async {
    final rig = await pumpView(tester);
    rig.api.failures['deleteBlockRule'] = const BiliError.http(500);
    await tap(tester, 'block-rule-remove-1');
    expect(rig.toasts, [BlockRuleStore.removeFailed]);
    expect(find.text('CA'), findsOneWidget);
  });

  testWidgets('同步 asks the server again although the list is fresh', (tester) async {
    final rig = await pumpView(tester);
    rig.api.blockRules = [...rig.api.blockRules, const BlockRule(id: 9, kind: BlockRuleKind.keyword, filter: '新的')];
    await tap(tester, 'block-words-sync');
    expect(rig.fetches, 2);
    expect(find.text('新的'), findsOneWidget);
  });

  testWidgets('a failed 同步 toasts', (tester) async {
    final rig = await pumpView(tester);
    rig.api.failures['danmakuBlockRules'] = const BiliError.http(500);
    await tap(tester, 'block-words-sync');
    expect(rig.toasts, [BlockRuleStore.syncFailed]);
  });

  testWidgets('✕ goes back to 弹幕设置', (tester) async {
    final rig = await pumpView(tester);
    await tap(tester, 'block-words-back');
    expect(rig.backs, [1]);
  });

  testWidgets('logged out: nothing is asked and 添加 and 同步 toast 请先登录', (tester) async {
    final rig = await pumpView(tester, loggedIn: false);
    expect(rig.api.calls, isEmpty);
    expect(find.text('CA'), findsNothing);
    await type(tester, '新词');
    await tap(tester, 'block-words-add');
    await tap(tester, 'block-words-sync');
    expect(rig.toasts, [BlockRuleStore.needLogin, BlockRuleStore.needLogin]);
    expect(rig.api.calls, isEmpty);
  });

  testWidgets('every control has a label to press', (tester) async {
    await pumpView(tester);
    final handle = tester.ensureSemantics();
    for (final label in ['返回', '添加', '同步', '关键词', '正则', '举报屏蔽用户', '删除 CA']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
    expect(tester.getSemantics(find.bySemanticsLabel('关键词')).flagsCollection.isSelected, Tristate.isTrue);
    handle.dispose();
  });

  testWidgets('every control answers an accessibility press', (tester) async {
    final handle = tester.ensureSemantics();
    final rig = await pumpView(tester);
    Future<void> press(String label) async {
      tester.semantics.tap(find.semantics.byLabel(label));
      await tester.pumpAndSettle();
    }

    await press('正则');
    expect(find.text('/^6+\$/'), findsOneWidget);
    await press('举报屏蔽用户');
    expect(find.text('a1b2c3d4'), findsOneWidget);
    await press('关键词');
    expect(find.text('CA'), findsOneWidget);
    expect(tester.getSemantics(find.bySemanticsLabel('关键词')).flagsCollection.isSelected, Tristate.isTrue);

    await type(tester, '剧场版');
    await press('添加');
    expect(rig.api.calls.last, 'addBlockRule keyword=剧场版');
    expect(find.text('剧场版'), findsOneWidget);

    await press('同步');
    expect(rig.fetches, 2);

    await press('删除 CA');
    expect(rig.api.calls.last, 'deleteBlockRule id=1');
    expect(find.text('CA'), findsNothing);
    expect(rig.toasts, isEmpty);
    handle.dispose();
  });
}
