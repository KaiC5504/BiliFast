import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/app_auth.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/favourites/fake_favourites_api.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/shared/loading_tv.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/skin/skin.dart';
import 'package:bilifast/space/fake_space_api.dart';
import 'package:bilifast/space/own/own_bangumi_tab.dart';
import 'package:bilifast/space/own/own_contribute_tab.dart';
import 'package:bilifast/space/own/own_favourites_tab.dart';
import 'package:bilifast/space/own/own_home_tab.dart';
import 'package:bilifast/space/own/own_space_page.dart';
import 'package:bilifast/space/space_api.dart';
import 'package:bilifast/space/space_page.dart';
import 'package:bilifast/space/space_route.dart';
import 'package:bilifast/space/uploader_tap.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/fake_keychain.dart';
import '../../playback/fakes.dart';

/// The fake account's mid, which `openSpace` takes for the account's own.
const _mid = 1;

const _tabs = [
  SpaceTab(kind: SpaceTabKind.home, title: '主页'),
  SpaceTab(kind: SpaceTabKind.dynamic, title: '动态'),
  SpaceTab(kind: SpaceTabKind.contribute, title: '投稿'),
  SpaceTab(kind: SpaceTabKind.favourite, title: '收藏'),
  SpaceTab(kind: SpaceTabKind.bangumi, title: '追番'),
];

SpaceProfile _profile({
  SpaceTabKind defaultTab = SpaceTabKind.contribute,
  List<SpaceTab> tabs = _tabs,
  bool own = true,
}) => SpaceProfile(
  mid: _mid,
  name: '测试账号',
  face: '',
  level: 5,
  vip: true,
  fans: 0,
  following: 13,
  likes: 0,
  tagLines: const [
    SpaceTagLine(text: 'IP属地：澳大利亚'),
    SpaceTagLine(text: '某某大学', link: true),
  ],
  tabs: tabs,
  defaultTab: defaultTab,
  own: own
      ? const OwnSpace(
          exp: 14805,
          nextExp: 28800,
          vipBadge: true,
          bannerLabel: SpaceBannerLabel(title: '幸运塔罗星 金牛座', subtitle: 'NO.000067'),
        )
      : null,
);

/// The space calls: the own one and anyone's, each answered with [answer]; [ownFailure], [profileFailure] and
/// [bangumiFailure] make them throw, [hold] keeps the own one waiting. The lists answer empty.
final class _Api implements SpaceApi {
  _Api(this.answer);

  SpaceProfile answer;
  Object? ownFailure;
  Object? profileFailure;
  Object? bangumiFailure;
  Completer<void>? hold;
  final calls = <String>[];

  @override
  Future<SpaceProfile> ownProfile(int mid) async {
    calls.add('ownProfile mid=$mid');
    if (hold case final hold?) await hold.future;
    if (ownFailure case final failure?) throw failure;
    return answer;
  }

  @override
  Future<SpaceProfile> profile(int mid) async {
    calls.add('profile mid=$mid');
    if (profileFailure case final failure?) throw failure;
    return answer;
  }

  @override
  Future<SpaceBangumiPage> bangumi(int mid, {required int page}) async {
    calls.add('bangumi mid=$mid page=$page');
    if (bangumiFailure case final failure?) throw failure;
    return const SpaceBangumiPage(items: [], hasMore: false, total: 0);
  }

  @override
  Future<SpaceVideoPage> videos(int mid, {required SpaceOrder order, String? next}) async =>
      const SpaceVideoPage(items: [], hasMore: false, total: 0);

  @override
  Future<SpaceVideoPage> chipVideos(int mid, SpaceChip chip, {String? next}) async =>
      const SpaceVideoPage(items: [], hasMore: false);
}

Skin _skin({
  bool primaryOnly = false,
  SkinColors colors = const SkinColors(color: 0xFFFFFFFF, colorSecondPage: 0xFF161513, lightText: true),
}) => Skin(
  equip: SkinEquip(
    id: 7,
    name: '测试装扮',
    ver: 1,
    packageUrl: '',
    packageMd5: '',
    primaryOnly: primaryOnly,
    colors: colors,
  ),
);

/// Authorized when asked, counting the asks; [onAsk] runs as the token comes.
final class _CountingAuth extends FakeAppAuth {
  _CountingAuth() : super(authorized: false);

  int asks = 0;
  VoidCallback? onAsk;

  @override
  Future<bool> request(BuildContext context) {
    asks++;
    onAsk?.call();
    return super.request(context);
  }
}

void main() {
  final logger = Logger(session: 'test')..add(MemorySink());
  late _Api api;
  late FakeFavouritesApi favourites;
  late _CountingAuth auth;
  late ValueNotifier<Skin?> skin;

  setUp(() {
    api = _Api(_profile());
    favourites = FakeFavouritesApi(
      folders: const [FavFolder(id: 9, title: '默认收藏夹', count: 0, isPrivate: false, contains: false, isDefault: true)],
    );
    auth = _CountingAuth();
    skin = ValueNotifier(null);
  });

  Finder key(String value) => find.byKey(ValueKey(value));

  Future<void> frames(WidgetTester tester, [int count = 10]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// The app at the iPhone's size with the fake account (mid 1) logged in, the own space pushed through `openSpace`
  /// for [mid].
  Future<void> show(WidgetTester tester, {int mid = _mid, bool settle = true}) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: 62, bottom: 34)
      ..viewPadding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: Canned.http(),
      logger: logger,
    );
    environment.useFakeAccount();
    final playback = AppPlayback(() => Completer<PlaybackController>().future);
    addTearDown(playback.dispose);
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      pageApi: FakePageApi(),
      spaceApi: api,
      favouritesApi: favourites,
      appAuth: auth,
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppScope(services: services, child: child!),
        home: Builder(
          builder: (context) => GestureDetector(
            onTap: () => unawaited(openSpace(context, UploaderRef(mid: mid, name: '测试账号', face: ''))),
            child: const Text('home'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('home'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await frames(tester);
    }
  }

  /// [show], with the page given [skin] to follow.
  Future<void> showOwn(WidgetTester tester, {bool settle = true}) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: 62, bottom: 34)
      ..viewPadding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: Canned.http(),
      logger: logger,
    );
    environment.useFakeAccount();
    final playback = AppPlayback(() => Completer<PlaybackController>().future);
    addTearDown(playback.dispose);
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      pageApi: FakePageApi(),
      spaceApi: api,
      favouritesApi: favourites,
      appAuth: auth,
    );
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('screen'),
        child: MaterialApp(
          navigatorKey: navigator,
          builder: (context, child) => AppScope(services: services, child: child!),
          home: const Text('home'),
        ),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => OwnSpacePage(
            uploader: const UploaderRef(mid: _mid, name: '测试账号', face: ''),
            skin: skin,
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await frames(tester);
    }
  }

  ScrollPosition scroll(WidgetTester tester) => tester.state<ScrollableState>(find.byType(Scrollable).first).position;

  void expectSelected(WidgetTester tester, SpaceTabKind kind, {bool isSelected = true}) => expect(
    tester.getSemantics(key('space-tab-${kind.name}')),
    isSemantics(hasSelectedState: true, isSelected: isSelected),
    reason: kind.name,
  );

  SystemUiOverlayStyle statusStyle(WidgetTester tester) => tester
      .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.descendant(of: find.byType(OwnSpacePage), matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>)),
      )
      .value;

  Color barFill(WidgetTester tester) =>
      tester.widget<ColoredBox>(find.descendant(of: key('own-space-bar'), matching: find.byType(ColoredBox))).color;

  Color? barNameInk(WidgetTester tester) => tester.widget<Text>(key('own-space-bar-name')).style?.color;

  double barOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(find.ancestor(of: key('own-space-bar'), matching: find.byType(AnimatedOpacity)).first)
      .opacity;

  /// [message] is up as a toast; then it is waited out, so no timer outlives the test.
  Future<void> expectToast(WidgetTester tester, String message) async {
    expect(find.descendant(of: key('toast'), matching: find.text(message)), findsOneWidget);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(key('toast'), findsNothing);
  }

  testWidgets('the account\'s own mid opens the own space; another mid opens theirs', (tester) async {
    await show(tester);
    expect(find.byType(OwnSpacePage), findsOneWidget);
    expect(find.byType(SpacePage), findsNothing);
    expect(api.calls, ['ownProfile mid=$_mid']);
    expect(key('own-space-header'), findsOneWidget);
    expect(key('own-space-edit'), findsOneWidget);
    expect(key('space-follow'), findsNothing, reason: 'no 关注 on one\'s own space');
  });

  testWidgets('another uploader\'s mid opens their space, as before', (tester) async {
    await show(tester, mid: 4242, settle: false);
    expect(find.byType(SpacePage), findsOneWidget);
    expect(find.byType(OwnSpacePage), findsNothing);
    expect(api.calls, ['profile mid=4242']);
  });

  testWidgets('the own call\'s extras draw the level\'s exp, the label and the 大', (tester) async {
    await showOwn(tester);
    expect(find.text('14805/28800'), findsOneWidget);
    final bar = tester.getRect(key('own-space-exp-bar'));
    final fill = tester.getRect(key('own-space-exp-fill'));
    expect(fill.left, bar.left);
    expect(fill.width / bar.width, closeTo(14805 / 28800, 0.001));
    expect(find.text('幸运塔罗星 金牛座'), findsOneWidget);
    expect(key('own-space-label-subtitle'), findsOneWidget);
    expect(key('own-space-vip-badge'), findsOneWidget);
    expect(find.text('粉丝'), findsOneWidget);
    expect(find.text('13'), findsOneWidget);
  });

  testWidgets('without the app token the space is asked as anyone\'s: the header draws what it has', (tester) async {
    final logs = MemorySink();
    Logger.shared.add(logs);
    addTearDown(() => Logger.shared.remove(logs));
    api
      ..answer = _profile(own: false, defaultTab: SpaceTabKind.home)
      ..ownFailure = BiliError.noAppToken;
    await showOwn(tester);
    expect(api.calls, ['ownProfile mid=$_mid', 'profile mid=$_mid']);
    expect(key('own-space-header'), findsOneWidget);
    expect(find.text('测试账号'), findsWidgets);
    expect(key('space-level'), findsOneWidget, reason: 'the level comes with anyone\'s space');
    expect(key('own-space-exp'), findsNothing, reason: 'no exp without the extras');
    expect(key('own-space-label-title'), findsNothing);
    expect(key('space-retry'), findsNothing);
    expect(logs.events.where((event) => event.msg == 'own space without app token'), hasLength(1));
    expect(logs.events.where((event) => event.msg == 'own space sections'), isEmpty);

    // 主页 would be empty and 追番 can only fail, so neither is offered, and the default 主页 opens 投稿.
    expect(key('space-tab-home'), findsNothing);
    expect(key('space-tab-bangumi'), findsNothing);
    expect(key('space-tab-contribute'), findsOneWidget);
    expect(key('space-tab-favourite'), findsOneWidget);
    expectSelected(tester, SpaceTabKind.contribute);
    expect(find.byType(OwnContributeSliver, skipOffstage: false), findsOneWidget);

    // 收藏 is the web login's, so it lists without the token.
    await tester.tap(key('space-tab-favourite'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('own-favourites-row-9'), skipOffstage: false), findsOneWidget);
    expect(auth.asks, 0);
  });

  testWidgets('the fake account\'s own mid answers the plain call without the extras, as the real one does', (
    tester,
  ) async {
    final space = FakeSpaceApi.demo();
    final profile = await space.profile(_mid);
    api
      ..answer = profile
      ..ownFailure = BiliError.noAppToken;
    await showOwn(tester);
    expect(profile.own, isNull);
    expect(key('space-tab-home'), findsNothing);
    expect(key('space-tab-bangumi'), findsNothing);
    expectSelected(tester, SpaceTabKind.contribute);
  });

  testWidgets('a successful own load logs what each 主页 section brought, counts only', (tester) async {
    final logs = MemorySink();
    Logger.shared.add(logs);
    addTearDown(() => Logger.shared.remove(logs));
    List<Map<String, Object>> lines() => [
      for (final event in logs.events)
        if (event.msg == 'own space sections') event.f.map((name, value) => MapEntry(name, value.toJson())),
    ];
    api.answer = FakeSpaceApi.demoOwn(_mid);
    await showOwn(tester);
    expect(lines(), [
      {
        'favourites': 'count 2 items 2',
        'bangumi': 'count 5 items 3',
        'coins': 'count 2 items 2',
        'likes': 'count 2 items 2',
        'garbs': 'count 2 items 2',
        'garbTotal': 7779,
        'banner': false,
        'bannerLabel': true,
      },
    ]);

    await tester.pumpWidget(const SizedBox.shrink());
    api.answer = _profile();
    await showOwn(tester);
    expect(lines(), hasLength(2));
    expect(lines().last['favourites'], 'absent');
  });

  testWidgets('a failed load says why and offers a retry, which loads the space', (tester) async {
    api.ownFailure = const BiliError.http(500);
    await showOwn(tester, settle: false);
    expect(key('space-retry'), findsOneWidget);
    expect(find.textContaining('网络请求失败（HTTP 500）'), findsOneWidget);
    expect(key('own-space-header'), findsNothing);
    expect(api.calls, ['ownProfile mid=$_mid'], reason: 'only a missing token falls back');

    api.ownFailure = null;
    await tester.tap(key('space-retry'));
    await frames(tester);
    expect(key('space-retry'), findsNothing);
    expect(key('own-space-header'), findsOneWidget);
    expect(api.calls, ['ownProfile mid=$_mid', 'ownProfile mid=$_mid']);
  });

  testWidgets('a fallback that fails too offers the retry', (tester) async {
    api
      ..ownFailure = BiliError.noAppToken
      ..profileFailure = const BiliError.http(502);
    await showOwn(tester, settle: false);
    expect(key('space-retry'), findsOneWidget);
    expect(api.calls, ['ownProfile mid=$_mid', 'profile mid=$_mid']);
  });

  testWidgets('while it loads: the TV under the bar with the tapped name, and 〈 still leaves', (tester) async {
    api.hold = Completer<void>();
    await showOwn(tester, settle: false);
    expect(find.byType(LoadingTvState), findsOneWidget);
    expect(tester.widget<Text>(key('own-space-bar-name')).data, '测试账号');
    expect(barOpacity(tester), 1);
    await tester.tap(key('own-space-back'));
    await frames(tester, 20);
    expect(find.byType(OwnSpacePage), findsNothing);
    api.hold!.complete();
    await frames(tester);
  });

  testWidgets('the tab row shows 主页 投稿 收藏 追番 and opens on 投稿 by default', (tester) async {
    await showOwn(tester);
    for (final kind in [SpaceTabKind.home, SpaceTabKind.contribute, SpaceTabKind.favourite, SpaceTabKind.bangumi]) {
      expect(key('space-tab-${kind.name}'), findsOneWidget, reason: kind.name);
    }
    expect(key('space-tab-dynamic'), findsNothing);
    expectSelected(tester, SpaceTabKind.contribute);
    expect(find.byType(OwnContributeSliver, skipOffstage: false), findsOneWidget);
  });

  testWidgets('it opens on the profile\'s default tab when that is one of the four', (tester) async {
    api.answer = _profile(defaultTab: SpaceTabKind.home);
    await showOwn(tester);
    expectSelected(tester, SpaceTabKind.home);
    expectSelected(tester, SpaceTabKind.contribute, isSelected: false);
    expect(find.byType(OwnHomeSliver, skipOffstage: false), findsOneWidget);
    final indicator = tester.getRect(key('space-tab-indicator'));
    expect(indicator.center.dx, moreOrLessEquals(tester.getRect(key('space-tab-home')).center.dx));
  });

  testWidgets('a default tab outside the four, or missing from the row, opens 投稿', (tester) async {
    api.answer = _profile(defaultTab: SpaceTabKind.dynamic);
    await showOwn(tester);
    expectSelected(tester, SpaceTabKind.contribute);
    expect(find.byType(OwnContributeSliver, skipOffstage: false), findsOneWidget);
  });

  testWidgets('a default 收藏 the row lacks opens 投稿, added to the row', (tester) async {
    api.answer = _profile(
      defaultTab: SpaceTabKind.favourite,
      tabs: const [SpaceTab(kind: SpaceTabKind.home, title: '主页')],
    );
    await showOwn(tester);
    expect(key('space-tab-favourite'), findsNothing);
    expectSelected(tester, SpaceTabKind.contribute);
  });

  testWidgets('tapping a tab switches the body below the header', (tester) async {
    await showOwn(tester);
    for (final (kind, sliver) in [
      (SpaceTabKind.favourite, OwnFavouritesSliver),
      (SpaceTabKind.bangumi, OwnBangumiSliver),
      (SpaceTabKind.home, OwnHomeSliver),
      (SpaceTabKind.contribute, OwnContributeSliver),
    ]) {
      await tester.tap(key('space-tab-${kind.name}'));
      await tester.pumpAndSettle();
      expectSelected(tester, kind);
      expect(find.byType(sliver, skipOffstage: false), findsOneWidget, reason: kind.name);
      expect(key('toast'), findsNothing);
    }
  });

  testWidgets('主页\'s 更多 switches to 收藏\'s and 追番\'s tab', (tester) async {
    api.answer = _profile(defaultTab: SpaceTabKind.home);
    await showOwn(tester);
    tester.widget<OwnHomeSliver>(find.byType(OwnHomeSliver, skipOffstage: false)).onMore(SpaceTabKind.favourite);
    await tester.pumpAndSettle();
    expectSelected(tester, SpaceTabKind.favourite);
    expect(tester.widget<OwnFavouritesSliver>(find.byType(OwnFavouritesSliver, skipOffstage: false)).pager.mid, _mid);

    await tester.tap(key('space-tab-home'));
    await tester.pumpAndSettle();
    tester.widget<OwnHomeSliver>(find.byType(OwnHomeSliver, skipOffstage: false)).onMore(SpaceTabKind.bangumi);
    await tester.pumpAndSettle();
    expectSelected(tester, SpaceTabKind.bangumi);
    expect(tester.widget<OwnBangumiSliver>(find.byType(OwnBangumiSliver, skipOffstage: false)).pager.mid, _mid);
  });

  testWidgets('收藏 and 追番 keep what they loaded across tab switches: no call on the way back', (tester) async {
    await showOwn(tester);
    for (final kind in [
      SpaceTabKind.favourite,
      SpaceTabKind.home,
      SpaceTabKind.favourite,
      SpaceTabKind.bangumi,
      SpaceTabKind.contribute,
      SpaceTabKind.bangumi,
      SpaceTabKind.favourite,
    ]) {
      await tester.tap(key('space-tab-${kind.name}'));
      await tester.pumpAndSettle();
      expectSelected(tester, kind);
    }
    expect(favourites.calls, ['folders mid=$_mid']);
    expect(api.calls.where((call) => call.startsWith('bangumi')), ['bangumi mid=$_mid page=1']);
    expect(find.byKey(const ValueKey('own-favourites-row-9'), skipOffstage: false), findsOneWidget);
  });

  testWidgets('收藏\'s first page landing after a switch away is kept for the way back', (tester) async {
    final hold = favourites.holds['folders'] = Completer<void>();
    await showOwn(tester);
    await tester.tap(key('space-tab-favourite'));
    await frames(tester);
    expect(find.byType(LoadingTvState), findsOneWidget);

    await tester.tap(key('space-tab-home'));
    await tester.pumpAndSettle();
    hold.complete();
    await tester.pumpAndSettle();

    await tester.tap(key('space-tab-favourite'));
    await tester.pumpAndSettle();
    expect(find.byType(LoadingTvState), findsNothing);
    expect(find.byKey(const ValueKey('own-favourites-row-9'), skipOffstage: false), findsOneWidget);
    expect(favourites.calls, ['folders mid=$_mid']);
  });

  testWidgets('收藏\'s header counts the space\'s folders at once', (tester) async {
    api.answer = SpaceProfile(
      mid: _mid,
      name: '测试账号',
      face: '',
      tabs: _tabs,
      own: const OwnSpace(favourites: SpaceSection(count: 7)),
    );
    favourites.holds['folders'] = Completer<void>();
    await showOwn(tester);
    await tester.tap(key('space-tab-favourite'));
    await frames(tester);
    expect(tester.widget<Text>(key('own-favourites-count')).data, '7');
    favourites.holds['folders']!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('追番 without the app token asks for it, and lists again once it is given', (tester) async {
    api.bangumiFailure = BiliError.noAppToken;
    auth.onAsk = () => api.bangumiFailure = null;
    await showOwn(tester);
    await tester.tap(key('space-tab-bangumi'));
    await tester.pumpAndSettle();
    expect(auth.asks, 1);
    expect(api.calls.where((call) => call.startsWith('bangumi')), [
      'bangumi mid=$_mid page=1',
      'bangumi mid=$_mid page=1',
    ]);
    expect(find.text(OwnBangumiSliver.endMessage), findsOneWidget);
    expect(key('own-bangumi-retry'), findsNothing);
  });

  testWidgets('scrolled past the name the bar comes in; a tab chosen there keeps the row pinned under it', (
    tester,
  ) async {
    await showOwn(tester);
    expect(barOpacity(tester), 0);
    // The name's line centres 400.5 down; the bar waits until it is under the 62 pt status bar.
    scroll(tester).jumpTo(400.5 - 62 - 1);
    await tester.pumpAndSettle();
    expect(barOpacity(tester), 0);
    scroll(tester).jumpTo(400.5 - 62 + 1);
    await tester.pumpAndSettle();
    expect(barOpacity(tester), 1);

    scroll(tester).jumpTo(scroll(tester).maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.getRect(key('space-tabs')).top, moreOrLessEquals(62 + 32));
    expect(tester.getRect(key('own-space-bar')).bottom, 62 + 32);

    for (final kind in [SpaceTabKind.favourite, SpaceTabKind.home, SpaceTabKind.bangumi]) {
      await tester.tap(key('space-tab-${kind.name}'));
      await tester.pumpAndSettle();
      expectSelected(tester, kind);
      expect(tester.getRect(key('space-tabs')).top, moreOrLessEquals(62 + 32), reason: kind.name);
      expect(barOpacity(tester), 1, reason: kind.name);
    }

    // Unscrolled, a tab changes in place.
    scroll(tester).jumpTo(0);
    await tester.pumpAndSettle();
    final tabs = tester.getRect(key('space-tabs')).top;
    await tester.tap(key('space-tab-contribute'));
    await tester.pumpAndSettle();
    expect(tester.getRect(key('space-tabs')).top, tabs);
    expect(scroll(tester).pixels, 0);
  });

  testWidgets('with the stock look the bar is white with grey ink and a dark status bar', (tester) async {
    await showOwn(tester);
    expect(statusStyle(tester), SystemUiOverlayStyle.dark, reason: 'no banner: the light default fill');
    scroll(tester).jumpTo(scroll(tester).maxScrollExtent);
    await tester.pumpAndSettle();
    expect(barFill(tester), const Color(0xFFFFFFFF));
    expect(barNameInk(tester), const Color(0xFF61666D));
    expect(statusStyle(tester), SystemUiOverlayStyle.dark);
    final back = find.descendant(of: key('own-space-back'), matching: find.byType(CustomPaint));
    expect(back, findsWidgets);
  });

  testWidgets('a skin that dresses second pages colours the bar, its ink and the status bar', (tester) async {
    skin.value = _skin();
    await showOwn(tester);
    scroll(tester).jumpTo(scroll(tester).maxScrollExtent);
    await tester.pumpAndSettle();
    expect(barFill(tester), const Color(0xFF161513));
    expect(barNameInk(tester), const Color(0xFFFFFFFF));
    expect(statusStyle(tester), SystemUiOverlayStyle.light);

    // A skin changed while the page is up is followed.
    skin.value = null;
    await tester.pump();
    expect(barFill(tester), const Color(0xFFFFFFFF));
    expect(statusStyle(tester), SystemUiOverlayStyle.dark);
  });

  testWidgets("the status bar over the bar goes by its fill, not the skin's color_mode", (tester) async {
    skin.value = _skin(colors: const SkinColors(color: 0xFF4A3B2C, colorSecondPage: 0xFFF5EBD7, lightText: true));
    await showOwn(tester);
    scroll(tester).jumpTo(scroll(tester).maxScrollExtent);
    await tester.pumpAndSettle();
    expect(barFill(tester), const Color(0xFFF5EBD7));
    expect(barNameInk(tester), const Color(0xFF4A3B2C));
    expect(statusStyle(tester), SystemUiOverlayStyle.dark, reason: 'a light fill under light color_mode');

    skin.value = _skin(colors: const SkinColors(colorSecondPage: 0xFF2B2F4A));
    await tester.pump();
    expect(barFill(tester), const Color(0xFF2B2F4A));
    expect(statusStyle(tester), SystemUiOverlayStyle.light, reason: 'a dark fill under dark color_mode');
  });

  testWidgets('a primary-only skin leaves the bar stock', (tester) async {
    skin.value = _skin(primaryOnly: true);
    await showOwn(tester);
    scroll(tester).jumpTo(scroll(tester).maxScrollExtent);
    await tester.pumpAndSettle();
    expect(barFill(tester), const Color(0xFFFFFFFF));
    expect(barNameInk(tester), const Color(0xFF61666D));
    expect(statusStyle(tester), SystemUiOverlayStyle.dark);
  });

  testWidgets('a picture banner has the status bar light until the bar comes in', (tester) async {
    api.answer = SpaceProfile(
      mid: _mid,
      name: '测试账号',
      face: '',
      tabs: _tabs,
      own: const OwnSpace(banner: 'https://i0.hdslb.com/bfs/garb/banner.png'),
    );
    await showOwn(tester);
    expect(statusStyle(tester), SystemUiOverlayStyle.light);
    expect(key('own-space-banner'), findsOneWidget);
    scroll(tester).jumpTo(scroll(tester).maxScrollExtent);
    await tester.pumpAndSettle();
    expect(statusStyle(tester), SystemUiOverlayStyle.dark);
  });

  testWidgets('编辑资料, both pills, 详情, link tags, 👕, search and ⋮ toast 暂未开放', (tester) async {
    await showOwn(tester);
    for (final target in [
      'own-space-edit',
      'own-space-medal',
      'own-space-fan-medal',
      'own-space-detail',
      'own-space-skin',
      'own-space-search',
      'own-space-more',
    ]) {
      await tester.tap(key(target));
      await tester.pump();
      await expectToast(tester, '暂未开放');
    }
    await tester.tap(find.text('某某大学'));
    await tester.pump();
    await expectToast(tester, '暂未开放');
  });

  testWidgets('every control answers an accessibility press', (tester) async {
    await showOwn(tester);
    for (final label in ['编辑资料', '成就勋章', '粉丝勋章', '详情', '装扮', '搜索', '更多', '某某大学']) {
      tester.semantics.tap(find.semantics.byLabel(label));
      await tester.pump();
      await expectToast(tester, '暂未开放');
    }
    tester.semantics.tap(find.semantics.byLabel('收藏'));
    await tester.pumpAndSettle();
    expectSelected(tester, SpaceTabKind.favourite);
    tester.semantics.tap(find.semantics.byLabel('返回'));
    await tester.pumpAndSettle();
    expect(find.byType(OwnSpacePage), findsNothing);
  });

  testWidgets('〈 goes back', (tester) async {
    await showOwn(tester);
    await tester.tap(key('own-space-back'));
    await tester.pumpAndSettle();
    expect(find.byType(OwnSpacePage), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('a pull past the top stretches the banner', (tester) async {
    await showOwn(tester);
    final banner = tester.getRect(key('own-space-banner-default'));
    expect(banner.height, closeTo(OwnSpaceTheme.bannerHeight, 0.01));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 120));
    await tester.pump();
    final pulled = tester.getRect(key('own-space-banner-default'));
    expect(pulled.top, banner.top);
    expect(pulled.height, greaterThan(banner.height + 40));
    expect(tester.getRect(key('own-space-edit')).top, greaterThan(OwnSpaceTheme.editTop + 40));
    await tester.pumpAndSettle();
    expect(tester.getRect(key('own-space-banner-default')), banner);
  });

  testWidgets('the 勋章 pills take taps across the name row\'s height, drawn where they were', (tester) async {
    await showOwn(tester);
    for (final target in ['own-space-medal', 'own-space-fan-medal']) {
      final pill = tester.getRect(key(target));
      expect(pill.height, OwnSpaceTheme.pillHeight, reason: target);
      expect(pill.center.dy, moreOrLessEquals(tester.getCenter(key('own-space-name')).dy), reason: target);
      for (final dy in [-SpaceTheme.nameBox / 2 + 1, SpaceTheme.nameBox / 2 - 1]) {
        await tester.tapAt(pill.center.translate(0, dy));
        await tester.pump();
        await expectToast(tester, '暂未开放');
      }
    }
  });

  testWidgets('scrolled to the pinned row, each short body\'s background runs to the screen\'s bottom', (tester) async {
    Future<int> pixelAt(int x, int y) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(key('screen'));
      return (await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = (await image.toByteData())!;
        final at = (y * image.width + x) * 4;
        image.dispose();
        return bytes.getUint8(at + 3) << 24 |
            bytes.getUint8(at) << 16 |
            bytes.getUint8(at + 1) << 8 |
            bytes.getUint8(at + 2);
      }))!;
    }

    for (final (kind, fill) in [
      (SpaceTabKind.home, OwnSpaceTabsTheme.greyPage),
      (SpaceTabKind.contribute, OwnSpaceTabsTheme.whitePage),
      (SpaceTabKind.favourite, OwnSpaceTabsTheme.whitePage),
      (SpaceTabKind.bangumi, OwnSpaceTabsTheme.greyPage),
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      api.answer = _profile(defaultTab: kind);
      await showOwn(tester);
      expectSelected(tester, kind);
      scroll(tester).jumpTo(scroll(tester).maxScrollExtent);
      await tester.pumpAndSettle();
      expect(tester.getRect(key('space-tabs')).top, moreOrLessEquals(62 + 32), reason: kind.name);
      for (final y in [700, 900, 955]) {
        expect(await pixelAt(220, y), fill.toARGB32(), reason: '${kind.name} at $y');
      }
    }
  });
}
