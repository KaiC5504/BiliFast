import 'package:bili_core/api.dart' hide RichText, SearchPage;
import 'package:bilifast/search/fake_search_api.dart';
import 'package:bilifast/search/search_glyphs.dart';
import 'package:bilifast/search/search_history_store.dart';
import 'package:bilifast/search/search_home_view.dart';
import 'package:bilifast/search/search_model.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/gestures.dart' show kPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/system_font.dart';

const _hot = [
  HotWord(keyword: 'hot-1', showName: '热词一号', icon: 'https://i0.hdslb.com/bfs/test/hot.png'),
  HotWord(keyword: 'hot-2', showName: '热词二号'),
  HotWord(keyword: 'hot-3', showName: '热词三号'),
  HotWord(keyword: 'hot-4', showName: '热词四号'),
  HotWord(keyword: 'hot-5', showName: '热词五号'),
  HotWord(keyword: 'hot-6', showName: '热词六号'),
  HotWord(keyword: 'hot-7', showName: '热词七号'),
  HotWord(keyword: 'hot-8', showName: '热词八号'),
  HotWord(keyword: 'hot-9', showName: '热词九号'),
  HotWord(keyword: 'hot-10', showName: '热词十号'),
  HotWord(keyword: 'hot-11', showName: '热词多余'),
];

List<DiscoveryWord> _discovery(String tag) => [
  for (var i = 1; i <= 14; i++) DiscoveryWord(keyword: '$tag-$i', showName: '发现$tag$i'),
];

void main() {
  late FakeSearchApi api;
  late SearchHistoryStore history;
  late SearchModel model;
  late List<String> searched;
  late int clears;
  var discoveryRound = 0;

  setUp(() {
    discoveryRound = 0;
    api = _RoundsApi(() => _discovery('第${++discoveryRound}轮'));
    history = SearchHistoryStore.memory();
    searched = [];
    clears = 0;
  });

  Future<void> show(WidgetTester tester, {List<String> words = const [], bool still = false}) async {
    tester.view
      ..physicalSize = const Size(440, 850)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (still) {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    }
    for (final word in words.reversed) {
      history.add(word);
    }
    model = SearchModel(api: api, history: history, placeholder: '默认词');
    addTearDown(model.dispose);
    await model.loadHome();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchHomeView(model: model, onSearch: searched.add, onClearHistory: () => clears++),
        ),
      ),
    );
    await tester.pump();
  }

  /// Lets a toast run out, so its timer is not left pending.
  Future<void> toastGone(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Finder key(String value) => find.byKey(ValueKey(value));

  SearchGlyph glyphIn(WidgetTester tester, String value) =>
      tester.widget<SearchGlyphIcon>(find.descendant(of: key(value), matching: find.byType(SearchGlyphIcon))).glyph;

  Offset glyphCentre(WidgetTester tester, String value) =>
      tester.getCenter(find.descendant(of: key(value), matching: find.byType(SearchGlyphIcon)));

  /// Whether [target] is drawn darkened, as while a finger is on it.
  bool darkened(WidgetTester tester, Finder target) => find
      .descendant(
        of: target,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.position == DecorationPosition.foreground &&
              (widget.decoration as BoxDecoration).color == BiliColors.pressedFill,
        ),
      )
      .evaluate()
      .isNotEmpty;

  final twelve = [for (var i = 1; i <= 12; i++) '历史词$i'];

  testWidgets('热搜 shows ten words in two columns, each searching its keyword', (tester) async {
    await show(tester);
    expect(find.text('bilibili热搜'), findsOneWidget);
    expect(find.text('热词十号'), findsOneWidget);
    expect(find.text('热词多余'), findsNothing);
    expect(tester.getTopLeft(find.text('热词一号')).dx, 12);
    expect(tester.getTopLeft(find.text('热词二号')).dx, 232);
    expect(tester.getCenter(find.text('热词三号')).dy - tester.getCenter(find.text('热词一号')).dy, closeTo(34, 0.01));

    await tester.tap(find.text('热词二号'));
    expect(searched, ['hot-2']);
  });

  testWidgets('a long 热搜 word is cut with … before its badge', (tester) async {
    api = FakeSearchApi(
      hotWords: const [
        HotWord(keyword: 'k', showName: '一个非常非常长的热搜词语会被截断显示', icon: 'https://i0.hdslb.com/bfs/test/hot.png'),
      ],
    );
    await show(tester);
    final text = tester.widget<Text>(find.text('一个非常非常长的热搜词语会被截断显示'));
    expect(text.overflow, TextOverflow.ellipsis);
    expect(tester.getRect(find.text('一个非常非常长的热搜词语会被截断显示')).right, lessThanOrEqualTo(208 - 14 - 4));
  });

  testWidgets('完整榜单 and 反馈 say they are not open yet', (tester) async {
    await show(tester);
    await tester.tap(key('search-hot-more'));
    await tester.pump();
    expect(find.text('暂未开放'), findsOneWidget);
    await toastGone(tester);
    expect(find.text('暂未开放'), findsNothing);

    await tester.tap(key('search-feedback'));
    await tester.pump();
    expect(find.text('暂未开放'), findsOneWidget);
    await toastGone(tester);
  });

  testWidgets('no 搜索历史 section without history', (tester) async {
    await show(tester);
    expect(find.text('搜索历史'), findsNothing);
    expect(key('search-history-clear'), findsNothing);
  });

  testWidgets('搜索历史 folds to two rows, ⌄ shows them all and ⌃ folds them again', (tester) async {
    final words = [for (var i = 1; i <= 12; i++) '历史词$i'];
    await show(tester, words: words);
    // Chips of 历史词N are 14 + 4 glyphs + 14 wide: four to a row in 416.
    for (var i = 1; i <= 8; i++) {
      expect(key('search-history-历史词$i'), findsOneWidget);
    }
    expect(key('search-history-历史词9'), findsNothing);
    expect(glyphIn(tester, 'search-history-expand'), SearchGlyph.expand);

    await tester.tap(key('search-history-expand'));
    await tester.pump();
    expect(key('search-history-历史词12'), findsOneWidget);
    expect(glyphIn(tester, 'search-history-expand'), SearchGlyph.collapse);

    await tester.tap(key('search-history-expand'));
    await tester.pumpAndSettle();
    expect(key('search-history-历史词9'), findsNothing);
  });

  testWidgets('⌄ is gone, with its rule, while the history fits in the two folded rows', (tester) async {
    await show(tester, words: [for (var i = 1; i <= 8; i++) '历史词$i']);
    expect(key('search-history-历史词8'), findsOneWidget);
    expect(key('search-history-expand'), findsNothing);
    expect(key('search-history-clear'), findsOneWidget);
    expect(
      find.byWidgetPredicate((widget) => widget is ColoredBox && widget.color == SearchTheme.rule),
      findsOneWidget,
      reason: "搜索发现's alone",
    );

    history.add('历史词9');
    await tester.pump();
    expect(key('search-history-expand'), findsOneWidget, reason: 'a ninth chip makes a third row');
  });

  testWidgets('搜索历史 grows to its full height over the motion', (tester) async {
    await show(tester, words: twelve);
    final folded = tester.getSize(find.byType(AnimatedSize)).height;
    expect(folded, 30 + 8 + 30);
    await tester.tap(key('search-history-expand'));
    await tester.pump();
    await tester.pump(SearchTheme.historyMotion ~/ 2);
    final halfway = tester.getSize(find.byType(AnimatedSize)).height;
    expect(halfway, greaterThan(folded));
    expect(halfway, lessThan(30 * 3 + 8 * 2));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AnimatedSize)).height, 30 * 3 + 8 * 2);
  });

  testWidgets('under Reduce Motion 搜索历史 unfolds at once', (tester) async {
    await show(tester, words: twelve, still: true);
    await tester.tap(key('search-history-expand'));
    await tester.pump();
    expect(find.byType(AnimatedSize), findsNothing);
    expect(tester.getSize(find.byType(Wrap)).height, 30 * 3 + 8 * 2);
  });

  testWidgets('the header glyphs are pressed in 44 wide targets; ⌃ and 🗑 sit higher than ⌄', (tester) async {
    await show(tester, words: twelve);
    for (final glyph in [
      'search-history-clear',
      'search-history-expand',
      'search-discovery-refresh',
      'search-discovery-eye',
    ]) {
      expect(tester.getSize(key(glyph)).width, 44, reason: glyph);
    }
    final header = tester.getCenter(find.text('搜索历史')).dy;
    expect(glyphCentre(tester, 'search-history-expand').dy, closeTo(header, 0.01));
    expect(glyphCentre(tester, 'search-history-clear').dy, closeTo(header - SearchTheme.trashLift, 0.01));
    await tester.tap(key('search-history-expand'));
    await tester.pumpAndSettle();
    expect(glyphCentre(tester, 'search-history-expand').dy, closeTo(header - SearchTheme.collapseLift, 0.01));
    expect(glyphCentre(tester, 'search-history-expand').dx, 440 - SearchTheme.headerExpandGlyph);
  });

  testWidgets('history chips, 搜索发现 cells and 热搜 words darken while pressed', (tester) async {
    await show(tester, words: ['历史词1']);
    for (final target in [key('search-history-历史词1'), key('search-discovery-第1轮-1'), key('search-hot-hot-1')]) {
      expect(darkened(tester, target), isFalse);
      final gesture = await tester.startGesture(tester.getCenter(target));
      await tester.pump(kPressTimeout);
      expect(darkened(tester, target), isTrue, reason: '$target');
      await gesture.up();
      await tester.pump();
      expect(darkened(tester, target), isFalse);
    }
  });

  testWidgets('反馈 shrinks while pressed', (tester) async {
    await show(tester);
    double scale() => tester
        .widget<AnimatedScale>(find.descendant(of: key('search-feedback'), matching: find.byType(AnimatedScale)))
        .scale;
    expect(scale(), 1);
    final gesture = await tester.startGesture(tester.getCenter(key('search-feedback')));
    await tester.pump(kPressTimeout);
    expect(scale(), SearchTheme.feedbackPressedScale);
    await gesture.up();
    await tester.pump();
    expect(scale(), 1);
    await toastGone(tester);
  });

  testWidgets('a history chip searches its word; a long one is cut at 145 wide', (tester) async {
    await show(tester, words: ['短词', '一个很长很长很长的搜索历史记录']);
    expect(tester.getSize(key('search-history-短词')).height, 30);
    expect(tester.getSize(key('search-history-短词')).width, tester.getSize(find.text('短词')).width + 28);
    expect(tester.getSize(key('search-history-一个很长很长很长的搜索历史记录')).width, 145);
    await tester.tap(key('search-history-短词'));
    expect(searched, ['短词']);
  });

  testWidgets('🗑 asks the page to clear; the section goes once history is empty', (tester) async {
    await show(tester, words: ['历史词1']);
    await tester.tap(key('search-history-clear'));
    expect(clears, 1);
    history.clear();
    await tester.pump();
    expect(find.text('搜索历史'), findsNothing);
  });

  testWidgets('搜索发现 shows twelve cells; a cell searches, ↻ asks for new words', (tester) async {
    await show(tester);
    expect(key('search-discovery-第1轮-12'), findsOneWidget);
    expect(key('search-discovery-第1轮-13'), findsNothing);
    expect(tester.getSize(key('search-discovery-第1轮-1')).height, 30);

    await tester.tap(key('search-discovery-第1轮-3'));
    expect(searched, ['第1轮-3']);

    await tester.tap(key('search-discovery-refresh'));
    await tester.pump();
    expect(key('search-discovery-第2轮-1'), findsOneWidget);
    expect(api.calls.where((call) => call == 'discovery'), hasLength(2));
    expect(find.text('加载失败，请稍后重试'), findsNothing);
  });

  testWidgets('a failed ↻ keeps the words and says so', (tester) async {
    await show(tester);
    api.failNext('discovery');
    await tester.tap(key('search-discovery-refresh'));
    await tester.pump();
    await tester.pump();
    expect(find.text('加载失败，请稍后重试'), findsOneWidget);
    expect(key('search-discovery-第1轮-1'), findsOneWidget);
    await toastGone(tester);
  });

  testWidgets("a 搜索发现 word's suffix follows a · in grey on the same line, cut with …", (tester) async {
    final handle = tester.ensureSemantics();
    api = FakeSearchApi(
      discovery: const [
        DiscoveryWord(keyword: 'z', showName: '星海物语', suffix: '昨天更新'),
        DiscoveryWord(keyword: 'long', showName: '一个相当长的搜索发现词语', suffix: '今天更新了内容'),
      ],
    );
    await show(tester);
    RichText rich(String keyword) =>
        tester.widget<RichText>(find.descendant(of: key('search-discovery-$keyword'), matching: find.byType(RichText)));
    expect(rich('z').text.toPlainText(), '星海物语·昨天更新');
    final runs = <(String, Color?)>[];
    rich('z').text.visitChildren((span) {
      if (span is TextSpan && span.text != null) runs.add((span.text!, span.style?.color));
      return true;
    });
    expect(runs.last, ('·昨天更新', SearchTheme.grey));
    expect(rich('long').maxLines, 1);
    expect(rich('long').overflow, TextOverflow.ellipsis);
    expect(
      tester.getSize(find.descendant(of: key('search-discovery-long'), matching: find.byType(RichText))).height,
      SearchTheme.wordLine,
      reason: 'one line',
    );
    expect(find.bySemanticsLabel('星海物语·昨天更新'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the section titles are headers to VoiceOver', (tester) async {
    final handle = tester.ensureSemantics();
    await show(tester, words: ['历史词1']);
    for (final title in ['bilibili热搜', '搜索历史', '搜索发现']) {
      expect(tester.getSemantics(find.text(title)), isSemantics(label: title, isHeader: true), reason: title);
    }
    handle.dispose();
  });

  testWidgets('👁 hides 搜索发现\'s cells and shows them again', (tester) async {
    await show(tester);
    expect(glyphIn(tester, 'search-discovery-eye'), SearchGlyph.eye);
    await tester.tap(key('search-discovery-eye'));
    await tester.pump();
    expect(history.discoveryHidden, isTrue);
    expect(key('search-discovery-第1轮-1'), findsNothing);
    expect(find.text('搜索发现'), findsOneWidget);
    expect(glyphIn(tester, 'search-discovery-eye'), SearchGlyph.eyeOff);

    await tester.tap(key('search-discovery-eye'));
    await tester.pump();
    expect(history.discoveryHidden, isFalse);
    expect(key('search-discovery-第1轮-1'), findsOneWidget);
  });

  testWidgets('dragging the page closes the keyboard', (tester) async {
    await show(tester);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextField(focusNode: focus, autofocus: true),
              Expanded(
                child: SearchHomeView(model: model, onSearch: searched.add, onClearHistory: () {}),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    await tester.drag(key('search-home'), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse);
  });

  testWidgets('every control answers accessibility presses', (tester) async {
    final handle = tester.ensureSemantics();
    await show(tester, words: twelve);
    for (final label in ['热词一号', '历史词1', '发现第1轮1', '展开', '清空搜索历史', '换一换', '隐藏搜索发现', '完整榜单', '反馈']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
    tester.semantics.tap(find.semantics.byLabel('热词一号'));
    expect(searched, ['hot-1']);
    tester.semantics.tap(find.semantics.byLabel('反馈'));
    await tester.pump();
    await toastGone(tester);
    handle.dispose();
  });

  testWidgets('with no Material above it, the view names the system font fallback itself', (tester) async {
    tester.view
      ..physicalSize = const Size(440, 850)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    model = SearchModel(api: api, history: history);
    addTearDown(model.dispose);
    await model.loadHome();
    await expectSystemFallback(tester, () async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(440, 850)),
            child: SearchHomeView(model: model, onSearch: searched.add, onClearHistory: () {}),
          ),
        ),
      );
    }, find.text('热词一号'));
  });
}

/// Answers 热搜 and a new round of 搜索发现 on each call.
class _RoundsApi extends FakeSearchApi {
  _RoundsApi(this._round) : super(hotWords: _hot);

  final List<DiscoveryWord> Function() _round;

  @override
  Future<List<DiscoveryWord>> discovery() async {
    await super.discovery();
    return _round();
  }
}
