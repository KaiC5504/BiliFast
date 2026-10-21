import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/search/fake_search_api.dart';
import 'package:bilifast/search/search_filters.dart';
import 'package:bilifast/search/search_history_store.dart';
import 'package:bilifast/search/search_model.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/fake_keychain.dart';
import '../../home/fake_login_gate.dart';
import '../../playback/fakes.dart';

/// A [SearchModel] whose state the test sets, so the view is checked apart from the model's own paging: it records
/// what the view asks of it.
class StubSearchModel extends SearchModel {
  StubSearchModel() : super(api: FakeSearchApi(), history: SearchHistoryStore.memory(), placeholder: '');

  String keywordValue = '测试';
  int searchesValue = 1;
  SearchTab tabValue = SearchTab.all;
  SearchFilters filtersValue = const SearchFilters();
  SearchResults<SearchVideo> videosValue = const SearchResults();
  SearchResults<SearchUser> usersValue = const SearchResults();

  int loadMores = 0;
  int retries = 0;
  final tabs = <SearchTab>[];
  final filterChanges = <SearchFilters>[];
  final follows = <(int, bool)>[];

  @override
  String get keyword => keywordValue;
  @override
  int get searches => searchesValue;
  @override
  SearchStage get stage => SearchStage.results;
  @override
  SearchTab get tab => tabValue;
  @override
  SearchFilters get filters => filtersValue;
  @override
  SearchResults<SearchVideo> get videos => videosValue;
  @override
  SearchResults<SearchUser> get users => usersValue;

  void update(void Function() change) {
    change();
    notifyListeners();
  }

  @override
  void selectTab(SearchTab tab) {
    tabs.add(tab);
    update(() => tabValue = tab);
  }

  @override
  void setFilters(SearchFilters filters) {
    filterChanges.add(filters);
    update(() => filtersValue = filters);
  }

  @override
  Future<void> loadMore() async => loadMores++;

  @override
  Future<void> retry() async => retries++;

  @override
  void setFollowing(int mid, {required bool following}) {
    follows.add((mid, following));
    update(
      () => usersValue = SearchResults(
        items: [for (final user in usersValue.items) user.mid == mid ? withFollowing(user, following) : user],
        loaded: usersValue.loaded,
        exhausted: usersValue.exhausted,
      ),
    );
  }
}

SearchUser withFollowing(SearchUser user, bool following) => SearchUser(
  mid: user.mid,
  name: user.name,
  face: user.face,
  fans: user.fans,
  videos: user.videos,
  level: user.level,
  sign: user.sign,
  officialType: user.officialType,
  officialDesc: user.officialDesc,
  following: following,
);

/// Made-up rows: no real titles, names or ids.
SearchVideo video(
  int i, {
  HighlightedText? title,
  String author = '测试作者',
  String cover = '',
  int play = 92000,
  int duration = 162,
  DateTime? published,
}) => SearchVideo(
  aid: 1000 + i,
  bvid: 'BV1search$i',
  title: title ?? HighlightedText.plain('测试视频标题 $i'),
  author: author,
  mid: 500 + i,
  cover: cover,
  play: play,
  danmaku: 10,
  duration: duration,
  published: published,
);

SearchUser user(
  int i, {
  String name = '测试用户',
  int fans = 8,
  int videos = 0,
  int level = 2,
  int? officialType,
  String officialDesc = '',
  bool following = false,
}) => SearchUser(
  mid: 700 + i,
  name: '$name$i',
  face: '',
  fans: fans,
  videos: videos,
  level: level,
  sign: '',
  officialType: officialType,
  officialDesc: officialDesc,
  following: following,
);

/// The app's services as the results reach them: the account logged in or out, the page's calls on [api].
Future<AppServices> resultServices({required bool loggedIn, required FakePageApi api, LoginGate? gate}) async {
  final environment = await AppEnvironment.load(
    keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
    http: Canned.http(loggedIn: loggedIn),
    logger: Logger(session: 'test'),
  );
  await environment.refreshAccount();
  final playback = AppPlayback(() async => throw UnimplementedError());
  addTearDown(playback.dispose);
  return AppServices(
    environment: environment,
    playback: playback,
    recents: await RecentStore.load(null, logger: Logger(session: 'test')),
    loginGate: gate ?? FakeLoginGate(),
    pageApi: api,
  );
}

/// [child] inside the app's scope and a page's Material, on a phone-sized view at 1×.
Future<void> pumpInApp(WidgetTester tester, AppServices services, Widget child, {bool phone = true}) async {
  if (phone) {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, page) => AppScope(services: services, child: page!),
      home: Scaffold(body: child),
    ),
  );
}

Future<void> settle(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lets a toast run out, so its timer is not left pending.
Future<void> toastGone(WidgetTester tester) => settle(tester, 60);
