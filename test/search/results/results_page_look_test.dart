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
import 'package:bilifast/shared/loading_tv.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/fake_keychain.dart';
import '../../playback/fakes.dart';
import '../../support/look_alike.dart';
import '../../support/stand_in_fonts.dart';

// The whole page in its results stage, so the results sit under the page's own field row as on the phone.

/// Where the 3× shots go for tools/screen_diff.py against 56, 57, 58, 60 and 67's 0.8 s frame, outside the repo:
/// `--dart-define=SEARCH_SHOTS=<folder>`. Nothing is written without it.
const _shots = String.fromEnvironment('SEARCH_SHOTS');

const _word = '青柠';

// Made-up rows shaped like 56's and 60's: the same lengths and mix of scripts.
List<SearchVideo> _videos(DateTime now) => [
  _video(
    1,
    HighlightedText.plain('同学们，v2发布!今晚最后的彩排!'),
    'CopperowlTK3000',
    play: 92000,
    duration: 162,
    published: now.subtract(const Duration(hours: 23, minutes: 2)),
  ),
  _video(
    2,
    HighlightedText.plain('周末周末朋友在聚会的时候，可是这里离春天还远呢~所以没有花开呀！月亮'),
    '林小橙子',
    play: 60000,
    duration: 21,
    published: DateTime(now.year, 1, 20),
  ),
  _video(
    3,
    const HighlightedText([HighlightRun('云海列车 旅人'), HighlightRun(_word, highlighted: true)]),
    '老周_Brest-修复珍藏版',
    play: 85,
    duration: 2312,
    published: DateTime(now.year, 1, 17),
  ),
  for (var i = 4; i < 12; i++)
    _video(
      i,
      HighlightedText.plain('示例视频标题 $i'),
      '示例作者',
      play: 488000,
      duration: 2312,
      published: DateTime(now.year, 1, 17),
    ),
];

SearchVideo _video(
  int i,
  HighlightedText title,
  String author, {
  required int play,
  required int duration,
  required DateTime published,
}) => SearchVideo(
  aid: 3000 + i,
  bvid: 'BV1look$i',
  title: title,
  author: author,
  mid: 600 + i,
  cover: '',
  play: play,
  danmaku: 10,
  duration: duration,
  published: published,
);

SearchUser _user(
  int i,
  String name, {
  required int fans,
  int videos = 0,
  required int level,
  int? officialType,
  String officialDesc = '',
}) => SearchUser(
  mid: 800 + i,
  name: name,
  face: '',
  fans: fans,
  videos: videos,
  level: level,
  sign: '',
  officialType: officialType,
  officialDesc: officialDesc,
);

final _users = [
  _user(1, _word, fans: 8, level: 2),
  _user(2, '青柠柠柠柠柠白狗探长', fans: 1481000, videos: 539, level: 6, officialType: 0, officialDesc: 'bilibili 优质UP主'),
  _user(3, '青柠电台', fans: 12000, videos: 79, level: 4),
  _user(4, '青橙青柠', fans: 12000, videos: 100, level: 3),
  _user(5, '-云-海-青-柠-', fans: 8385, videos: 7, level: 6),
  _user(6, '瓦青柠夏MAKA', fans: 8148, videos: 18, level: 6),
];

/// Fixed frames, as search_page_test.dart pumps: pumpAndSettle never returns on this page.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(loadSystemFontStandIns);

  final boundary = GlobalKey();
  late FakeSearchApi search;

  Future<void> show(WidgetTester tester, {bool holdVideos = false}) async {
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
    search = FakeSearchApi(videos: _videos(DateTime.now()), users: _users);
    if (holdVideos) search.held.add('videos');
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      pageApi: FakePageApi(),
      searchApi: search,
      searchHistory: SearchHistoryStore.memory(),
      fonts: FontStore.memory()..select(FontChoice.system),
    );
    // The services' font store sets the family, so the system font comes after them.
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
        home: const SearchPage(placeholder: _word),
      ),
    );
    await _settle(tester);
    // The empty field searches the placeholder, as 搜索 does.
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _settle(tester);
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    if (_shots.isEmpty) return;
    await saveShot(tester, find.byKey(boundary), '$_shots/$name.png');
  }

  Rect rectOf(WidgetTester tester, String key) => tester.getRect(find.byKey(ValueKey(key)));

  testWidgets('56: the tab row under the page\'s field row, then the video rows', (tester) async {
    await show(tester);
    await shoot(tester, '56');
    expect(search.calls.where((call) => call.startsWith('videos')), ['videos $_word 1']);
    // 56's measures, in pt: the field row ends 106 down, as 55's suggestions start.
    expect(rectOf(tester, 'search-tab-indicator').top, closeTo(140, 0.01));
    expect(rectOf(tester, 'search-tab-indicator').bottom, closeTo(143, 0.01));
    expect(rectOf(tester, 'search-tab-all').bottom, closeTo(146, 0.01));
    expect(rectOf(tester, 'search-row-BV1look1').top, closeTo(146.33, 0.01));
    expect(rectOf(tester, 'search-row-BV1look2').top, closeTo(267.33, 0.01));
  });

  testWidgets('57: scrolled, the tab row has gone behind the field row', (tester) async {
    await show(tester);
    final list = tester.state<ScrollableState>(
      find.descendant(of: find.byKey(const ValueKey('search-list-all')), matching: find.byType(Scrollable)),
    );
    list.position.jumpTo(SearchResultTheme.tabRowHeight + SearchResultTheme.hairline + 2 * 121);
    await _settle(tester);
    await shoot(tester, '57');
    expect(rectOf(tester, 'search-tab-all').bottom, lessThanOrEqualTo(106));
    expect(rectOf(tester, 'search-row-BV1look3').top, closeTo(106, 0.01));
  });

  testWidgets('58: 筛选 open under the tab row', (tester) async {
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('search-filter')));
    await _settle(tester);
    await shoot(tester, '58');
    expect(tester.getTopLeft(find.byKey(const ValueKey('search-filter-dim'))).dy, closeTo(146.33, 0.01));
  });

  testWidgets('67: the first page loads under the TV, centred, its box 297.33 under the field row', (tester) async {
    await show(tester, holdVideos: true);
    await shoot(tester, '67');
    expect(search.waiting, 1);
    final tv = tester.getRect(find.byType(LoadingTv));
    expect(tv.top, closeTo(106 + 892 / 3, 0.01));
    expect(tv.center.dx, closeTo(220, 0.01));
    expect(tester.getCenter(find.text(LoadingTvState.message)).dx, closeTo(220, 0.01));
    search
      ..held.clear()
      ..release();
    await _settle(tester);
    expect(find.byType(LoadingTv), findsNothing);
  });

  testWidgets('60: 用户 with its sort row', (tester) async {
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('search-tab-users')));
    await _settle(tester);
    await shoot(tester, '60');
    expect(rectOf(tester, 'search-tab-indicator').top, closeTo(140, 0.01));
    expect(rectOf(tester, 'search-row-user-801').top, closeTo(186, 0.01));
  });
}
