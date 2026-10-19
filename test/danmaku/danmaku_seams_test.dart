import 'package:bili_core/api.dart';
import 'package:bili_core/danmaku.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/danmaku/block_rule_store.dart';
import 'package:bilifast/danmaku/danmaku_session.dart';
import 'package:bilifast/danmaku/danmaku_settings_store.dart';
import 'package:bilifast/danmaku/send/danmaku_send_model.dart';
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/playback/danmaku_feed.dart';
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/panels/panel_layer.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';
import '../support/fake_player_session.dart';

/// The real store, session and feed wired as the page wires them, over the fake page API and canned segments.
final class Seam {
  Seam({List<BlockRule> serverRules = const []}) {
    api.blockRules = List.of(serverRules);
    feed = DanmakuFeed(client: BiliClient(transport: http, cookies: CookieJar(Canned.cookies), logger: logger), logger: logger);
    rules = BlockRuleStore(api: api, isLoggedIn: () => true, logger: logger);
    session = DanmakuSession(
      feed: feed,
      settings: settings,
      rules: rules,
      api: api,
      target: () => (bvid: 'BV1GJ411x7h7', cid: 42),
      position: () => position,
      isLoggedIn: () => true,
      isVip: () => false,
      accountMid: () => 12345,
      toast: (_) {},
      requestLogin: () {},
      logger: logger,
    );
  }

  final logger = Logger(session: 'test');
  final http = Canned.http()
    ..dataRoutes[Canned.segmentPath] = (200, danmakuSegmentBytes([(1000, '前方高能'), (2000, '来了'), (3000, 'abc')]));
  final api = FakePageApi();
  final settings = DanmakuSettingsStore.memory();
  late final DanmakuFeed feed;
  late final BlockRuleStore rules;
  late final DanmakuSession session;
  double position = 5;

  void load() {
    feed.load(cid: 42, durationMs: 300000);
    feed.update(positionMs: 1000, playing: true);
  }

  List<DisplayDanmaku> items() {
    final timeline = feed.timeline;
    if (timeline == null) return const [];
    timeline.seek(-1);
    return [for (var ms = 999; ms < 10000; ms += 1000) ...timeline.advance(ms)];
  }

  List<String> shown() => [for (final item in items()) item.text];

  void filter(DanmakuFilterOptions Function(DanmakuFilterOptions) change) =>
      settings.update(settings.value.copyWith(filter: change(settings.value.filter)));

  /// Lets the rules' fetch land and every decode or re-filter it set off finish.
  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await feed.settle();
    }
  }

  void dispose() {
    session.dispose();
    rules.dispose();
    feed.dispose();
  }
}

/// Runs real time (the feed decodes on isolates) between frames until [done].
Future<void> until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
}

PlayerUi landscapeUi(Seam seam) => PlayerUi(
  session: FakePlayerSession(),
  chrome: ChromeState(),
  panels: PanelController(),
  orientation: OrientationController()..enterLandscape(),
  device: NoDeviceControls(),
  onBack: () {},
  danmaku: seam.session,
);

Future<void> showPanels(WidgetTester tester, PlayerUi ui) async {
  tester.view.physicalSize = const Size(956, 440);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Stack(children: [Positioned.fill(child: PanelLayer(ui: ui))])));
}

void main() {
  late Seam seam;

  tearDown(() => seam.dispose());

  group('屏蔽词 through the store, the session and the feed', () {
    test('a keyword added through the store hides the danmaku it matches', () async {
      seam = Seam();
      seam.load();
      await seam.settle();
      expect(seam.shown(), ['前方高能', '来了', 'abc']);

      expect(await seam.rules.add(BlockRuleKind.keyword, '高能'), isNull);
      await seam.settle();
      expect(seam.shown(), ['来了', 'abc']);
    });

    test('a regex typed between slashes hides the danmaku it matches', () async {
      seam = Seam();
      seam.load();
      await seam.settle();

      expect(await seam.rules.add(BlockRuleKind.regex, r'/^a.c$/'), isNull);
      await seam.settle();
      expect(seam.shown(), ['前方高能', '来了']);
    });

    test('removing a rule brings its danmaku back', () async {
      seam = Seam();
      seam.load();
      await seam.settle();
      await seam.rules.add(BlockRuleKind.keyword, '来');
      await seam.settle();
      expect(seam.shown(), ['前方高能', 'abc']);

      expect(await seam.rules.remove(seam.rules.rules.single), isNull);
      await seam.settle();
      expect(seam.shown(), ['前方高能', '来了', 'abc']);
    });

    test("the server's rules, there when the page opens, apply to the first segment", () async {
      seam = Seam(serverRules: [const BlockRule(id: 7, kind: BlockRuleKind.keyword, filter: '高能')]);
      seam.load();
      await seam.settle();
      expect(seam.shown(), ['来了', 'abc']);
    });

    test('弹幕观看屏蔽词 off lets the blocked danmaku through', () async {
      seam = Seam(serverRules: [const BlockRule(id: 7, kind: BlockRuleKind.keyword, filter: '高能')]);
      seam.load();
      await seam.settle();
      expect(seam.shown(), ['来了', 'abc']);

      seam.filter((filter) => filter.copyWith(applyRules: false));
      await seam.settle();
      expect(seam.shown(), ['前方高能', '来了', 'abc']);
    });

    test('your own danmaku matching a rule still shows, boxed, through a filter change', () async {
      seam = Seam(serverRules: [const BlockRule(id: 7, kind: BlockRuleKind.keyword, filter: '高能')]);
      seam.load();
      await seam.settle();
      seam.position = 1.2;

      expect(await seam.session.send('高能来了', const DanmakuStyle()), isNull);
      expect(seam.items().singleWhere((item) => item.text == '高能来了').isOwn, isTrue);

      seam.filter((filter) => filter.copyWith(blockScroll: true));
      await seam.settle();
      expect([for (final item in seam.items()) if (item.isOwn) item.text], ['高能来了']);
    });
  });

  group('the panels over the real session and feed', () {
    testWidgets("弹幕设置's 滚动 square takes the scrolling danmaku off the timeline", (tester) async {
      seam = Seam();
      final ui = landscapeUi(seam);
      seam.load();
      await until(tester, () => seam.feed.timeline != null);
      expect(seam.shown(), hasLength(3));
      await showPanels(tester, ui);
      ui.panels.open(PlayerPanel.danmakuSettings);
      await tester.pumpAndSettle();

      final square = find.byKey(const ValueKey('danmaku-type-scroll'));
      await tester.ensureVisible(square);
      await tester.pumpAndSettle();
      await tester.tap(square);
      await tester.pump();
      expect(seam.settings.value.filter.blockScroll, isTrue);
      await until(tester, () => seam.shown().isEmpty);
      expect(seam.shown(), isEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("当前弹幕列表's 屏蔽弹幕 takes the danmaku off the stage", (tester) async {
      seam = Seam();
      final ui = landscapeUi(seam);
      seam.load();
      await until(tester, () => seam.feed.timeline != null);
      await showPanels(tester, ui);
      ui.panels.open(PlayerPanel.danmakuList);
      await tester.pumpAndSettle();
      expect(find.text('来了'), findsOneWidget);

      final more = find.descendant(
        of: find.ancestor(of: find.text('来了'), matching: find.byType(AnimatedOpacity)),
        matching: find.byKey(const ValueKey('danmaku-list-more')),
      );
      await tester.tap(more);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('danmaku-list-hide')));
      await tester.pump();
      expect(seam.shown(), ['前方高能', 'abc']);
      expect(find.text('来了'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
