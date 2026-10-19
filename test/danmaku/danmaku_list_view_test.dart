import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/danmaku.dart';
import 'package:bilifast/danmaku/block_rule_store.dart';
import 'package:bilifast/danmaku/danmaku_list_view.dart';
import 'package:bilifast/danmaku/danmaku_session.dart';
import 'package:bilifast/danmaku/danmaku_settings_store.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/playback/danmaku_feed.dart';
import 'package:bilifast/shared/action_glyphs.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';
import '../support/fake_player_session.dart';

/// The page's session with the feed's two calls answered here: [rows] is what showed, [hidden] what 屏蔽弹幕 took.
class ListSession extends DanmakuSession {
  ListSession({
    required FakePageApi super.api,
    required this.rows,
    bool Function()? loggedIn,
    DanmakuTarget? target = (bvid: 'BV1GJ411x7h7', cid: 137649199),
  }) : super(
         feed: DanmakuFeed(
           client: BiliClient(transport: Canned.http(), cookies: CookieJar(Canned.cookies)),
         ),
         settings: DanmakuSettingsStore.memory(),
         rules: BlockRuleStore(api: api, isLoggedIn: () => true),
         target: () => target,
         position: () => 0,
         isLoggedIn: loggedIn ?? () => true,
         isVip: () => false,
         accountMid: () => 0,
         toast: (_) {},
         requestLogin: () {},
       );

  final List<DanmakuElem> rows;
  final List<DanmakuElem> hidden = [];
  int reads = 0;

  @override
  List<DanmakuElem> recent() {
    reads += 1;
    return rows;
  }

  @override
  void hide(DanmakuElem elem) => hidden.add(elem);
}

const rows = [
  DanmakuElem(id: 11, content: '第一个'),
  DanmakuElem(id: 12, content: '秒赤'),
  DanmakuElem(id: 13, content: '孤狼前行，不惧长路，寻找志同道合的伙伴，欢迎加入交流群1130137028'),
];

/// 当前弹幕列表 where the landscape panel puts it: 0.4 of 956 at the right, before the 62 pt safe area and the
/// panel's 16 pt margin.
final class Rig {
  Rig({List<DanmakuElem> shown = rows, this.loggedIn = true, FakePageApi? api}) : api = api ?? FakePageApi() {
    session = ListSession(api: this.api, rows: shown, loggedIn: () => loggedIn);
  }

  final FakePageApi api;

  /// The calls the list makes; the session's own block-rule refresh is left out.
  List<String> get likeCalls => [for (final call in api.calls) if (!call.startsWith('danmakuBlockRules')) call];
  late final ListSession session;
  bool loggedIn;
  final toasts = <String>[];
  final playerSession = FakePlayerSession();
  final chrome = ChromeState();
  final panels = PanelController();
  final orientation = OrientationController()..enterLandscape();

  late final ui = PlayerUi(
    session: playerSession,
    chrome: chrome,
    panels: panels,
    orientation: orientation,
    device: orientation.controls,
    onBack: () {},
    danmaku: session,
  );

  Future<void> mount(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(956, 440)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(left: 62, right: 62, bottom: 21);
    addTearDown(tester.view.reset);
    addTearDown(() {
      session.dispose();
      chrome.dispose();
      panels.dispose();
      orientation.dispose();
      playerSession.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ColoredBox(
          color: Colors.black,
          child: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 956 * BiliMetrics.panelWidth,
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(
                  right: 62 + BiliMetrics.panelTrailing,
                  bottom: 21 + BiliMetrics.panelBottom,
                ),
                child: DanmakuListView(ui: ui, toast: toasts.add, back: () {}, close: () {}),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }
}

Finder inRow(String text, String key) => find.descendant(
  of: find.ancestor(of: find.text(text), matching: find.byType(AnimatedOpacity)),
  matching: find.byKey(ValueKey(key)),
);

ActionIcon thumbOf(WidgetTester tester, String text) =>
    tester.widget<ActionIcon>(find.descendant(of: inRow(text, 'danmaku-list-like'), matching: find.byType(ActionIcon)));

String? countOf(WidgetTester tester, String text) {
  final count = inRow(text, 'danmaku-list-count');
  return count.evaluate().isEmpty ? null : tester.widget<Text>(count).data;
}

double opacityOf(WidgetTester tester, String text) =>
    tester.widget<AnimatedOpacity>(find.ancestor(of: find.text(text), matching: find.byType(AnimatedOpacity))).opacity;

void main() {
  testWidgets('lists what showed once, with the counts from one request', (tester) async {
    final rig = Rig()
      ..api.danmakuLikeStats[11] = (likes: 1, liked: false)
      ..api.danmakuLikeStats[12] = (likes: 12000, liked: true);
    await rig.mount(tester);
    for (final elem in rows) {
      expect(find.text(elem.content), findsOneWidget);
    }
    expect(rig.session.reads, 1);
    expect(rig.likeCalls, ['danmakuLikes 3']);
    expect(countOf(tester, '第一个'), '1');
    expect(countOf(tester, '秒赤'), '1.2万');
    expect(countOf(tester, rows[2].content), isNull, reason: 'no count at 0');
    expect(thumbOf(tester, '第一个').solid, isFalse);
    expect(thumbOf(tester, '第一个').color, DanmakuListTheme.thumb);
    expect(thumbOf(tester, '秒赤').solid, isTrue);
    expect(thumbOf(tester, '秒赤').color, DanmakuListTheme.liked);

    rig.session.notifyListeners();
    await tester.pump();
    expect(rig.session.reads, 1);
  });

  testWidgets('a long danmaku wraps and its row grows by whole lines', (tester) async {
    await Rig().mount(tester);
    final one = tester.getSize(find.ancestor(of: find.text('第一个'), matching: find.byType(AnimatedOpacity)));
    final long = tester.getSize(find.ancestor(of: find.text(rows[2].content), matching: find.byType(AnimatedOpacity)));
    expect(one.height, DanmakuListTheme.rowMinHeight);
    expect(long.height, greaterThan(one.height + DanmakuListTheme.textLine));
  });

  testWidgets('a long list asks for its counts in batches', (tester) async {
    final shown = [for (var i = 1; i <= 120; i++) DanmakuElem(id: i, content: '弹幕$i')];
    final rig = Rig(
      shown: [
        ...shown,
        const DanmakuElem(content: '没有id'),
        shown.first,
      ],
    );
    await rig.mount(tester);
    await tester.pump();
    expect(rig.likeCalls, ['danmakuLikes 50', 'danmakuLikes 50', 'danmakuLikes 20']);
  });

  testWidgets('a 👍 shows at once, and a second tap takes it back', (tester) async {
    final rig = Rig()..api.danmakuLikeStats[11] = (likes: 1, liked: false);
    await rig.mount(tester);
    final hold = Completer<void>();
    rig.api.holds['likeDanmaku'] = hold;
    await tester.tap(inRow('第一个', 'danmaku-list-like'));
    await tester.pump();
    expect(rig.api.calls.last, 'likeDanmaku dmid=11 on=true');
    expect(countOf(tester, '第一个'), '2');
    expect(thumbOf(tester, '第一个').solid, isTrue);
    expect(thumbOf(tester, '第一个').color, DanmakuListTheme.liked);

    await tester.tap(inRow('第一个', 'danmaku-list-like'));
    await tester.pump();
    expect(rig.api.calls.where((call) => call.startsWith('likeDanmaku')), hasLength(1), reason: 'one at a time');

    hold.complete();
    await tester.pump();
    expect(rig.api.danmakuLikeStats[11], (likes: 2, liked: true));
    expect(countOf(tester, '第一个'), '2');

    rig.api.holds.remove('likeDanmaku');
    await tester.tap(inRow('第一个', 'danmaku-list-like'));
    await tester.pump();
    expect(rig.api.calls.last, 'likeDanmaku dmid=11 on=false');
    expect(countOf(tester, '第一个'), '1');
    expect(thumbOf(tester, '第一个').solid, isFalse);
    expect(rig.toasts, isEmpty);
  });

  testWidgets('a refused 👍 goes back and says why', (tester) async {
    final rig = Rig()..api.failures['likeDanmaku'] = const BiliError.api(code: 36106, message: '该弹幕已被删除');
    await rig.mount(tester);
    await tester.tap(inRow('秒赤', 'danmaku-list-like'));
    await tester.pump();
    expect(countOf(tester, '秒赤'), isNull);
    expect(thumbOf(tester, '秒赤').solid, isFalse);
    expect(rig.toasts, ['该弹幕已被删除']);

    rig.api.failures['likeDanmaku'] = StateError('offline');
    await tester.tap(inRow('秒赤', 'danmaku-list-like'));
    await tester.pump();
    expect(rig.toasts.last, '操作失败');
    expect(thumbOf(tester, '秒赤').solid, isFalse);
  });

  testWidgets('logged out, a 👍 asks for the login and sends nothing', (tester) async {
    final rig = Rig(loggedIn: false);
    await rig.mount(tester);
    await tester.tap(inRow('第一个', 'danmaku-list-like'));
    await tester.pump();
    expect(rig.toasts, ['请先登录']);
    expect(rig.api.calls.where((call) => call.startsWith('likeDanmaku')), isEmpty);
    expect(countOf(tester, '第一个'), isNull);
  });

  testWidgets('counts that fail to load leave every 👍 at zero, quietly', (tester) async {
    final rig = Rig()..api.failures['danmakuLikes'] = const BiliError.api(code: -400, message: '请求错误');
    await rig.mount(tester);
    expect(find.text('第一个'), findsOneWidget);
    expect(countOf(tester, '第一个'), isNull);
    expect(rig.toasts, isEmpty);
  });

  testWidgets('⋮ opens 屏蔽弹幕 under it; it hides the danmaku and drops the row', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    expect(find.byKey(const ValueKey('danmaku-list-menu')), findsNothing);
    await tester.tap(inRow('第一个', 'danmaku-list-more'));
    await tester.pump();
    final menu = tester.getRect(find.byKey(const ValueKey('danmaku-list-menu')));
    final row = tester.getRect(find.ancestor(of: find.text('第一个'), matching: find.byType(AnimatedOpacity)));
    final more = tester.getRect(inRow('第一个', 'danmaku-list-more'));
    expect(menu.top, closeTo(row.bottom - DanmakuListTheme.popoverOverlap, 0.01));
    expect(menu.right, closeTo(956 - 62, 0.01));
    expect(menu.right - DanmakuListTheme.popoverPadX - DanmakuListTheme.popoverCell / 2, lessThan(more.right));
    expect(find.text('举报'), findsNothing);
    expect(opacityOf(tester, '第一个'), 1);
    expect(opacityOf(tester, '秒赤'), DanmakuListTheme.dimmed);

    await tester.tap(find.byKey(const ValueKey('danmaku-list-hide')));
    await tester.pump();
    expect(rig.session.hidden, [rows[0]]);
    expect(find.text('第一个'), findsNothing);
    expect(find.byKey(const ValueKey('danmaku-list-menu')), findsNothing);
    expect(opacityOf(tester, '秒赤'), 1);
  });

  testWidgets('a tap elsewhere closes the popover and does nothing else', (tester) async {
    final rig = Rig();
    await rig.mount(tester);
    await tester.tap(inRow('秒赤', 'danmaku-list-more'));
    await tester.pump();
    expect(find.byKey(const ValueKey('danmaku-list-menu')), findsOneWidget);
    await tester.tapAt(tester.getCenter(find.text(rows[2].content)));
    await tester.pump();
    expect(find.byKey(const ValueKey('danmaku-list-menu')), findsNothing);
    expect(rig.session.hidden, isEmpty);
    expect(rig.api.calls.where((call) => call.startsWith('likeDanmaku')), isEmpty);

    await tester.tap(inRow('秒赤', 'danmaku-list-more'));
    await tester.pump();
    await tester.tapAt(tester.getTopLeft(find.byType(DanmakuListView)) + const Offset(10, 400));
    await tester.pump();
    expect(find.byKey(const ValueKey('danmaku-list-menu')), findsNothing);
  });

  testWidgets('the popover opens upwards from a row too low for it', (tester) async {
    final shown = [for (var i = 1; i <= 8; i++) DanmakuElem(id: i, content: '弹幕$i')];
    await Rig(shown: shown).mount(tester);
    await tester.tap(inRow('弹幕8', 'danmaku-list-more'));
    await tester.pump();
    final menu = tester.getRect(find.byKey(const ValueKey('danmaku-list-menu')));
    final row = tester.getRect(find.ancestor(of: find.text('弹幕8'), matching: find.byType(AnimatedOpacity)));
    expect(menu.bottom, closeTo(row.top + DanmakuListTheme.popoverOverlap, 0.01));
    await tester.tap(find.byKey(const ValueKey('danmaku-list-hide')));
    await tester.pump();
    expect(find.text('弹幕8'), findsNothing);
  });

  testWidgets('nothing shown yet reads 暂无弹幕 and asks for nothing', (tester) async {
    final rig = Rig(shown: const []);
    await rig.mount(tester);
    expect(find.text('暂无弹幕'), findsOneWidget);
    expect(rig.likeCalls, isEmpty);
  });

  testWidgets('every control answers an accessibility press', (tester) async {
    final semantics = tester.ensureSemantics();
    final rig = Rig();
    await rig.mount(tester);
    expect(find.bySemanticsLabel('点赞：第一个'), findsOneWidget);
    tester.semantics.tap(find.semantics.byLabel('点赞：第一个'));
    await tester.pump();
    expect(rig.api.calls.last, 'likeDanmaku dmid=11 on=true');
    tester.semantics.tap(find.semantics.byLabel('更多：秒赤'));
    await tester.pump();
    tester.semantics.tap(find.semantics.byLabel('屏蔽弹幕'));
    await tester.pump();
    expect(rig.session.hidden, [rows[1]]);
    semantics.dispose();
  });
}
