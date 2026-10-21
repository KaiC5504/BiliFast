import 'dart:async';

import 'package:bili_core/api.dart' hide SearchPage;
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/search/fake_search_api.dart';
import 'package:bilifast/search/search_history_store.dart';
import 'package:bilifast/search/search_page.dart';
import 'package:bilifast/settings/font_store.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';

/// Where the 3× shots go for tools/screen_diff.py, outside the repo: `--dart-define=SEARCH_SHOTS=<folder>`. Nothing is
/// written without it.
const _shots = String.fromEnvironment('SEARCH_SHOTS');

// Made-up words shaped like 52-55's: the same lengths and mix of scripts.
const _badge = 'https://i0.hdslb.com/bfs/test/badge.png';
const _hot = [
  HotWord(keyword: 'h1', showName: '李明说球队今晚王者归来'),
  HotWord(keyword: 'h2', showName: '海边奇想计划实机首曝', icon: _badge),
  HotWord(keyword: 'h3', showName: '北京4-2上海', icon: _badge),
  HotWord(keyword: 'h4', showName: '金枪鱼是鲨鱼吗', icon: _badge),
  HotWord(keyword: 'h5', showName: '纪念长江大桥建成通车六十周年', icon: _badge),
  HotWord(keyword: 'h6', showName: '星海3国内定档', icon: _badge),
  HotWord(keyword: 'h7', showName: '网络用语是否会对日常表达造成影响', icon: _badge),
  HotWord(keyword: 'h8', showName: 'OpenLake全面开源DeepRiver'),
  HotWord(keyword: 'h9', showName: 'CBA揭幕战北京击败广州队'),
  HotWord(keyword: 'h10', showName: '米兰11连胜如何遭罗马终结'),
];
const _history = [
  '午后散步日记',
  '青石',
  'SAX UP',
  '云朵小船',
  'BDK围棋俱乐部',
  'b站如何关闭首页的推荐',
  '6K',
  '环绕声场',
  '星河小旅人季活动',
  '蔬菜保卫萝卜online模式',
  '五月唱歌',
  '朋友们 被我新做的菜吓到了',
  'ZmOOHH',
  'Daler',
  'NOLAVI',
  '绘本',
  '蛋糕',
  '星河最新活动公布',
];
const _discovery = [
  '云海镇',
  '露米娅',
  '星河活动最新公布',
  '星河每日任务蓝晶',
  '本周推荐好物',
  '大厨看BDK老板暗示主厨已经回归',
  '五月唱歌',
  '星河限定返场',
  '给远方朋友寄去信件',
  'supplementaryyy色调',
  '星际征途新角色 晨曦全招式演示',
  '星河最新活动公布',
];
const _suggestions = ['keipx联动', 'keitools2', '桂柚丶', '桂花机器人', 'keiabs', '桂拳战士', '贵转', '桂语', '魔法学院kei', '桂柚'];

/// A suggestion with "kei" marked wherever it appears, as the answer's `<em>` does.
SearchSuggestion _suggestion(String word) {
  final runs = <HighlightRun>[];
  var rest = word;
  while (rest.isNotEmpty) {
    final at = rest.indexOf('kei');
    if (at < 0) {
      runs.add(HighlightRun(rest));
      break;
    }
    if (at > 0) runs.add(HighlightRun(rest.substring(0, at)));
    runs.add(const HighlightRun('kei', highlighted: true));
    rest = rest.substring(at + 3);
  }
  return SearchSuggestion(keyword: word, text: HighlightedText(runs));
}

void main() {
  setUpAll(loadSystemFontStandIns);

  final boundary = GlobalKey();

  Future<void> show(WidgetTester tester, {required List<String> history}) async {
    showAsPhone(tester);
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    final logger = Logger(session: 'test');
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: Canned.http(),
      logger: logger,
    );
    final playback = AppPlayback(() => Completer<PlaybackController>().future);
    addTearDown(playback.dispose);
    final store = SearchHistoryStore.memory();
    for (final word in history.reversed) {
      store.add(word);
    }
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      searchApi: FakeSearchApi(
        hotWords: _hot,
        discovery: [for (final word in _discovery) DiscoveryWord(keyword: word, showName: word)],
        suggest: (term) => [for (final word in _suggestions) _suggestion(word)],
      ),
      searchHistory: store,
      fonts: FontStore.memory()..select(FontChoice.system),
    );
    // After the services: their FontStore sets the family.
    BiliFonts.family = BiliFonts.system;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          fontFamily: BiliFonts.family,
          fontFamilyFallback: BiliFonts.fallback,
          textTheme: BiliFonts.untracked,
        ),
        builder: (context, child) => RepaintBoundary(
          key: boundary,
          child: AppScope(services: services, child: child!),
        ),
        home: const SearchPage(placeholder: '本周推荐好物'),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The page as 53 shows it: the keyboard down, so no caret.
  Future<void> dropKeyboard(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    if (_shots.isEmpty) return;
    await saveShot(tester, find.byKey(boundary), '$_shots/$name.png');
  }

  Rect rectOf(WidgetTester tester, String key) => tester.getRect(find.byKey(ValueKey(key)));

  testWidgets('53: the empty page with history folded to two rows', (tester) async {
    await show(tester, history: _history);
    await dropKeyboard(tester);
    await shoot(tester, '53');
    // 53's measures, in pt.
    expect(tester.getRect(find.byKey(const ValueKey('search-field'))).center.dy, closeTo(84, 0.5));
    expect(
      rectOf(tester, 'search-history-午后散步日记'),
      rectMoreOrLessEquals(const Rect.fromLTRB(12, 359, 124, 389), epsilon: 0.5),
    );
    expect(rectOf(tester, 'search-history-b站如何关闭首页的推荐').width, closeTo(145, 0.5));
    expect(find.byKey(const ValueKey('search-history-环绕声场')), findsNothing, reason: 'folded to two rows');
    expect(
      rectOf(tester, 'search-discovery-云海镇'),
      rectMoreOrLessEquals(const Rect.fromLTRB(12, 484, 216.5, 514), epsilon: 0.5),
    );
    expect(rectOf(tester, 'search-feedback').top, closeTo(732, 0.5));
  });

  testWidgets('54: the history unfolded', (tester) async {
    await show(tester, history: _history);
    await dropKeyboard(tester);
    await tester.tap(find.byKey(const ValueKey('search-history-expand')));
    await tester.pumpAndSettle();
    await shoot(tester, '54');
    expect(rectOf(tester, 'search-history-星河最新活动公布').bottom, closeTo(541, 0.5));
    expect(rectOf(tester, 'search-discovery-云海镇').top, closeTo(598, 0.5));
  });

  testWidgets('52: as the page opens, with the keyboard up', (tester) async {
    await show(tester, history: _history.sublist(1));
    await shoot(tester, '52');
    expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);
  });

  testWidgets('55: suggestions while typing', (tester) async {
    await show(tester, history: _history);
    await tester.enterText(find.byKey(const ValueKey('search-field')), 'KEI');
    await tester.pumpAndSettle();
    await dropKeyboard(tester);
    await shoot(tester, '55');
    expect(
      rectOf(tester, 'search-suggestion-keipx联动'),
      rectMoreOrLessEquals(const Rect.fromLTRB(0, 106, 440, 150), epsilon: 0.5),
    );
    expect(rectOf(tester, 'search-suggestion-桂柚').bottom, closeTo(546, 0.5));
  });
}
