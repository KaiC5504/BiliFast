import 'dart:async';
import 'dart:io' show SocketException;

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/phone_frame.dart';
import 'package:bilifast/app/swipe_back_route.dart';
import 'package:bilifast/dynamic/card/dynamic_card.dart';
import 'package:bilifast/dynamic/fake_dynamic_api.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/shared/loading_tv.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/space/fake_space_api.dart';
import 'package:bilifast/space/space_page.dart';
import 'package:bilifast/space/uploader_tap.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';

const _mid = 4242;

const _tabs = [
  SpaceTab(kind: SpaceTabKind.home, title: '主页'),
  SpaceTab(kind: SpaceTabKind.dynamic, title: '动态'),
  SpaceTab(kind: SpaceTabKind.contribute, title: '投稿'),
];

SpaceProfile _profile({
  List<SpaceTab> tabs = _tabs,
  SpaceTabKind defaultTab = SpaceTabKind.contribute,
  String? banner,
  bool chargeable = true,
}) => SpaceProfile(
  mid: _mid,
  name: '演示UP主',
  face: '',
  sign: '一句简介',
  level: 6,
  fans: 178000,
  following: 18,
  likes: 2841000,
  banner: banner,
  tagLines: const [SpaceTagLine(text: 'IP属地：广东'), SpaceTagLine(text: '某某大学', link: true)],
  entries: const [
    SpaceEntry(kind: SpaceEntryKind.shop, title: '小店', note: '1件商品'),
    SpaceEntry(kind: SpaceEntryKind.charge, title: '充电', note: '5人充电'),
  ],
  chargeable: chargeable,
  tabs: tabs,
  defaultTab: defaultTab,
);

/// A post by the space's uploader, or by [mid].
DynamicItem _post(int i, {int mid = _mid}) => DynamicItem(
  id: '${9100 + i}',
  kind: DynamicKind.word,
  author: DynamicAuthor(mid: mid, name: '演示UP主', face: ''),
);

SpaceVideo _video(int i) => SpaceVideo(
  aid: 500 + i,
  bvid: 'BV1space${i.toString().padLeft(4, '0')}',
  title: '视频$i',
  cover: '',
  duration: 60,
  play: i,
);

UploaderCard _card({bool following = false}) =>
    UploaderCard(mid: _mid, name: '演示UP主', face: '', fans: 1, videos: 1, isVip: false, following: following);

/// A login whose fingerprint cookies are already there, so no `spi` call is needed.
const _login = {'SESSDATA': 'page-sess', 'bili_jct': 'page-jct', 'buvid3': 'b3', 'buvid4': 'b4'};

/// Counts the requests and answers with [_login]'s result, or not logged in when there is none.
final class _Gate implements LoginGate {
  _Gate(this._login);

  final Future<bool> Function()? _login;
  int requests = 0;

  @override
  Future<bool> request(BuildContext context) async {
    requests++;
    return await _login?.call() ?? false;
  }
}

class _Harness {
  _Harness(this.spaceApi, this.dynamicApi, this.pageApi, this.gate, this.services, this.http);

  final FakeSpaceApi spaceApi;
  final FakeDynamicApi dynamicApi;
  final FakePageApi pageApi;
  final _Gate gate;
  final AppServices services;
  final CannedHttp http;

  int get cardCalls => pageApi.calls.where((call) => call == 'uploaderCard mid=$_mid').length;
}

void main() {
  final navigator = GlobalKey<NavigatorState>();
  final logger = Logger(session: 'test')..add(MemorySink());

  Finder key(String value) => find.byKey(ValueKey(value));

  Future<void> frames(WidgetTester tester, [int count = 10]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// The space pushed over a home screen at the iPhone's size; [hold] keeps the profile's call waiting, [login] is
  /// what the login gate does, and [framed] puts the app in the Windows phone frame. [videos] are 投稿's, [dynamicApi]
  /// answers 动态.
  Future<_Harness> show(
    WidgetTester tester, {
    SpaceProfile? profile,
    List<SpaceVideo> videos = const [],
    FakeDynamicApi? dynamicApi,
    bool loggedIn = true,
    bool following = false,
    bool hold = false,
    Object? failure,
    Future<bool> Function(AppEnvironment environment, CannedHttp http)? login,
    bool framed = false,
  }) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: 62, bottom: 34)
      ..viewPadding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    final http = Canned.http(loggedIn: loggedIn);
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: http,
      logger: logger,
    );
    if (loggedIn) {
      environment.useFakeAccount();
    } else {
      await environment.refreshAccount();
    }
    final playback = AppPlayback(() => Completer<PlaybackController>().future);
    addTearDown(playback.dispose);
    final spaceApi = FakeSpaceApi(profileFor: (_) => profile ?? _profile(), videoList: videos);
    final dynamics = dynamicApi ?? FakeDynamicApi();
    if (hold) spaceApi.holds['profile'] = Completer<void>();
    if (failure != null) spaceApi.failures['profile'] = failure;
    final pageApi = FakePageApi(uploader: _card(following: following));
    final gate = _Gate(login == null ? null : () => login(environment, http));
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      pageApi: pageApi,
      spaceApi: spaceApi,
      dynamicApi: dynamics,
      loginGate: gate,
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) =>
            AppScope(services: services, child: framed ? PhoneFrame.wrap(context, child!) : child!),
        home: const Text('home'),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        SwipeBackPageRoute<void>(
          builder: (_) => const SpacePage(uploader: UploaderRef(mid: _mid, name: '演示UP主', face: '')),
        ),
      ),
    );
    if (hold || failure != null) {
      await frames(tester);
    } else {
      await tester.pumpAndSettle();
    }
    return _Harness(spaceApi, dynamics, pageApi, gate, services, http);
  }

  /// Presses the one control VoiceOver reads as [label], as VoiceOver and the Windows driver do; it fails when that
  /// control has no tap action.
  Future<void> press(WidgetTester tester, String label) async {
    tester.semantics.tap(find.semantics.byLabel(label));
    await tester.pump();
  }

  ScrollPosition scroll(WidgetTester tester) => tester.state<ScrollableState>(find.byType(Scrollable).first).position;

  /// [message] is up as a toast; then it is waited out, so no timer outlives the test.
  Future<void> expectToast(WidgetTester tester, String message) async {
    expect(find.descendant(of: key('toast'), matching: find.text(message)), findsOneWidget);
    // In frames: the fade has to finish before the toast's own two seconds start.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(key('toast'), findsNothing);
  }

  double barOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(find.ancestor(of: key('space-bar'), matching: find.byType(AnimatedOpacity)).first)
      .opacity;

  SystemUiOverlayStyle statusStyle(WidgetTester tester) => tester
      .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.descendant(of: find.byType(SpacePage), matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>)),
      )
      .value;

  testWidgets('the loading TV under the tapped face and name, then the header', (tester) async {
    final harness = await show(tester, hold: true);
    expect(find.byType(LoadingTvState), findsOneWidget);
    expect(find.descendant(of: key('space-loading-title'), matching: find.text('演示UP主')), findsOneWidget);
    expect(key('space-header'), findsNothing);
    expect(harness.spaceApi.calls, ['profile mid=$_mid']);

    harness.spaceApi.holds['profile']!.complete();
    await frames(tester);
    expect(find.byType(LoadingTvState), findsNothing);
    expect(key('space-header'), findsOneWidget);
    expect(find.text('17.8万'), findsOneWidget);
    expect(find.text('粉丝'), findsOneWidget);
    expect(find.text('284.1万'), findsOneWidget);
    expect(key('space-follow'), findsOneWidget);
    expect(key('space-charge'), findsOneWidget, reason: 'the uploader takes 充电');
    expect(key('space-loading-title'), findsNothing);
  });

  testWidgets('a failed load says why and offers a retry, which loads the space', (tester) async {
    final harness = await show(tester, failure: const BiliError.http(500));
    expect(key('space-retry'), findsOneWidget);
    expect(find.byType(LoadingTvState), findsNothing);
    expect(find.textContaining('网络请求失败（HTTP 500）'), findsOneWidget);
    expect(find.textContaining('点击重试'), findsOneWidget);

    harness.spaceApi.failures.remove('profile');
    await tester.tap(key('space-retry'));
    await frames(tester);
    expect(key('space-retry'), findsNothing);
    expect(key('space-header'), findsOneWidget);
    expect(harness.spaceApi.calls.where((call) => call.startsWith('profile')), ['profile mid=$_mid', 'profile mid=$_mid']);
  });

  testWidgets('a lost connection says so; 点击重试 answers an accessibility press', (tester) async {
    final harness = await show(tester, failure: const SocketException('down'));
    expect(find.textContaining('网络连接失败，请检查网络后重试'), findsOneWidget);

    harness.spaceApi.failures.remove('profile');
    await press(tester, '网络连接失败，请检查网络后重试，点击重试');
    await frames(tester);
    expect(key('space-header'), findsOneWidget);
    expect(harness.spaceApi.calls.where((call) => call.startsWith('profile')), ['profile mid=$_mid', 'profile mid=$_mid']);
  });

  testWidgets('an uploader who isn\'t there (-404) says so, with nothing to retry; 〈 still leaves', (tester) async {
    final harness = await show(tester, failure: const BiliError.api(code: -404, message: '啥都木有'));
    expect(find.text('用户不存在或已注销'), findsOneWidget);
    expect(key('space-retry'), findsNothing);
    expect(find.semantics.byLabel(RegExp('点击重试')), findsNothing);
    await tester.tap(key('space-failed'));
    await frames(tester);
    expect(harness.spaceApi.calls, ['profile mid=$_mid'], reason: 'a tap on the message asks nothing');

    await press(tester, '返回');
    await tester.pumpAndSettle();
    expect(find.byType(SpacePage), findsNothing);
  });

  testWidgets('+ 关注 follows at once, toasts 关注成功 and shows 已关注 with ▽', (tester) async {
    final harness = await show(tester);
    expect(harness.pageApi.calls, contains('uploaderCard mid=$_mid'));
    await tester.tap(key('space-follow'));
    await frames(tester);
    expect(harness.pageApi.calls, contains('follow on=true'));
    expect(key('space-followed'), findsOneWidget);
    expect(key('space-follow-more'), findsOneWidget);
    expect(key('space-follow'), findsNothing);
    expect(harness.services.follows.last, (mid: _mid, following: true));
    await expectToast(tester, '关注成功');
  });

  testWidgets('已关注 opens the sheet; 取消关注 unfollows and toasts 取消关注成功', (tester) async {
    final harness = await show(tester, following: true);
    expect(key('space-followed'), findsOneWidget);
    await tester.tap(key('space-followed'));
    await tester.pumpAndSettle();
    expect(key('space-sheet'), findsOneWidget);
    for (final label in ['加入特别关注', '设置分组', '取消关注', '取消']) {
      expect(find.descendant(of: key('space-sheet'), matching: find.text(label)), findsOneWidget);
    }
    expect(harness.pageApi.calls, isNot(contains('follow on=false')), reason: 'opening the sheet changes nothing');

    await tester.tap(key('space-sheet-unfollow'));
    await tester.pump();
    expect(harness.pageApi.calls, contains('follow on=false'));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(key('space-sheet'), findsNothing);
    expect(key('space-follow'), findsOneWidget);
    await expectToast(tester, '取消关注成功');
  });

  testWidgets('取消, the dim and back close the sheet without unfollowing', (tester) async {
    final harness = await show(tester, following: true);
    for (final close in ['space-sheet-cancel', 'space-sheet-dim', 'back']) {
      await tester.tap(key('space-followed'));
      await tester.pumpAndSettle();
      expect(key('space-sheet'), findsOneWidget);
      if (close == 'back') {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tapAt(tester.getTopLeft(key(close)) + const Offset(20, 20));
      }
      await tester.pumpAndSettle();
      expect(key('space-sheet'), findsNothing, reason: close);
      expect(find.byType(SpacePage), findsOneWidget, reason: '$close leaves the page up');
    }
    expect(harness.pageApi.calls, isNot(contains('follow on=false')));
  });

  testWidgets('logged out, + 关注 asks for the login and calls nothing', (tester) async {
    final harness = await show(tester, loggedIn: false);
    expect(harness.pageApi.calls, isEmpty, reason: 'logged out the card is not asked');
    await tester.tap(key('space-follow'));
    await frames(tester);
    expect(harness.gate.requests, 1);
    expect(harness.pageApi.calls, isEmpty);
    expect(key('space-follow'), findsOneWidget);
  });

  testWidgets('a 关注 made on another page shows here', (tester) async {
    final harness = await show(tester);
    expect(key('space-follow'), findsOneWidget);
    harness.services.follows.changed(_mid, following: true);
    await tester.pump();
    expect(key('space-followed'), findsOneWidget);
    harness.services.follows.changed(_mid + 1, following: false);
    await tester.pump();
    expect(key('space-followed'), findsOneWidget, reason: 'another uploader');
    harness.services.follows.changed(_mid, following: false);
    await tester.pump();
    expect(key('space-follow'), findsOneWidget);
  });

  testWidgets('past the name the white bar comes in; scrolled on, the tabs pin under it', (tester) async {
    await show(tester);
    expect(barOpacity(tester), 0);
    expect(statusStyle(tester), SystemUiOverlayStyle.dark, reason: 'over the light default banner');
    final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;

    // The name's line centres 292.5 down; the bar waits until it is under the 62 pt status bar.
    position.jumpTo(292.5 - 62 - 1);
    await tester.pumpAndSettle();
    expect(barOpacity(tester), 0);
    position.jumpTo(292.5 - 62 + 1);
    await tester.pumpAndSettle();
    expect(barOpacity(tester), 1);
    expect(key('space-pill'), findsOneWidget);

    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.getRect(key('space-tabs')).top, moreOrLessEquals(62 + 32));
    expect(tester.getRect(key('space-bar')).bottom, 62 + 32);
    expect(statusStyle(tester), SystemUiOverlayStyle.dark);

    // The bar's pill follows like the header's button.
    await tester.tap(key('space-pill'));
    await frames(tester);
    expect(find.descendant(of: key('space-pill'), matching: find.text('已关注')), findsOneWidget);
    await expectToast(tester, '关注成功');

    position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(barOpacity(tester), 0);
  });

  testWidgets('a picture banner has the status bar light until the bar comes in', (tester) async {
    await show(tester, profile: _profile(banner: 'https://i0.hdslb.com/bfs/space/banner.png'));
    expect(statusStyle(tester), SystemUiOverlayStyle.light);
    final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(statusStyle(tester), SystemUiOverlayStyle.dark);
  });

  testWidgets('a pull past the top stretches the banner', (tester) async {
    await show(tester);
    final banner = tester.getRect(key('space-banner-default'));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 120));
    await tester.pump();
    final pulled = tester.getRect(key('space-banner-default'));
    expect(pulled.top, banner.top);
    expect(pulled.height, greaterThan(banner.height + 40));
    await tester.pumpAndSettle();
    expect(tester.getRect(key('space-banner-default')), banner);
  });

  testWidgets('主页 toasts and stays unselected; 投稿 is selected', (tester) async {
    await show(tester);
    await tester.tap(key('space-tab-home'));
    await tester.pump();
    await expectToast(tester, '暂未开放');
    expect(tester.getSemantics(key('space-tab-home')), isSemantics(hasSelectedState: true, isSelected: false));
    expect(tester.getSemantics(key('space-tab-contribute')), isSemantics(hasSelectedState: true, isSelected: true));
    await tester.tap(key('space-tab-contribute'));
    await tester.pump();
    expect(key('toast'), findsNothing);
  });

  testWidgets('a space opening on 主页 still shows 投稿', (tester) async {
    await show(tester, profile: _profile(defaultTab: SpaceTabKind.home));
    expect(tester.getSemantics(key('space-tab-contribute')), isSemantics(hasSelectedState: true, isSelected: true));
    expect(tester.getSemantics(key('space-tab-home')), isSemantics(hasSelectedState: true, isSelected: false));
    final indicator = tester.getRect(key('space-tab-indicator'));
    expect(indicator.center.dx, moreOrLessEquals(tester.getRect(key('space-tab-contribute')).center.dx));
  });

  testWidgets('a space whose tabs have no 投稿 shows one, selected', (tester) async {
    await show(
      tester,
      profile: _profile(tabs: const [SpaceTab(kind: SpaceTabKind.home, title: '主页')]),
    );
    expect(find.descendant(of: key('space-tabs'), matching: find.text('投稿')), findsOneWidget);
    expect(tester.getSemantics(key('space-tab-contribute')), isSemantics(hasSelectedState: true, isSelected: true));
  });

  testWidgets('私信, search, ⋮, 详情, 充电, the cards and link tags toast 暂未开放', (tester) async {
    await show(tester);
    for (final target in [
      'space-chat',
      'space-search',
      'space-more',
      'space-detail',
      'space-charge',
      'space-entry-shop',
      'space-entry-charge',
    ]) {
      await tester.tap(key(target));
      await tester.pump();
      await expectToast(tester, '暂未开放');
    }
    await tester.tap(find.text('某某大学'));
    await tester.pump();
    await expectToast(tester, '暂未开放');
  });

  testWidgets('▽ and the sheet\'s 加入特别关注 and 设置分组 toast 暂未开放', (tester) async {
    final harness = await show(tester, following: true);
    await tester.tap(key('space-follow-more'));
    await tester.pump();
    await expectToast(tester, '暂未开放');
    for (final row in ['space-sheet-special', 'space-sheet-group']) {
      await tester.tap(key('space-followed'));
      await tester.pumpAndSettle();
      await tester.tap(key(row));
      await tester.pump();
      await expectToast(tester, '暂未开放');
      await tester.pumpAndSettle();
      expect(key('space-sheet'), findsNothing);
    }
    expect(harness.pageApi.calls, isNot(contains('follow on=false')));
  });

  testWidgets('〈 goes back', (tester) async {
    await show(tester);
    await tester.tap(key('space-back'));
    await tester.pumpAndSettle();
    expect(find.byType(SpacePage), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('〈 goes back while the space loads too', (tester) async {
    final harness = await show(tester, hold: true);
    await tester.tap(key('space-back'));
    await frames(tester, 20);
    expect(find.byType(SpacePage), findsNothing);
    harness.spaceApi.holds['profile']!.complete();
    await frames(tester);
  });

  testWidgets('every control answers an accessibility press', (tester) async {
    final harness = await show(tester);
    for (final label in ['私信', '搜索', '更多', '详情', '充电', '小店，1件商品', '充电，5人充电', '某某大学', '主页']) {
      await press(tester, label);
      expect(find.descendant(of: key('toast'), matching: find.text('暂未开放')), findsOneWidget, reason: label);
      await expectToast(tester, '暂未开放');
    }
    await press(tester, '动态');
    await frames(tester);
    expect(tester.getSemantics(key('space-tab-dynamic')), isSemantics(hasSelectedState: true, isSelected: true));
    expect(harness.dynamicApi.calls, ['spacePosts $_mid offset=']);
    await press(tester, '投稿');
    await frames(tester);
    expect(tester.getSemantics(key('space-tab-contribute')), isSemantics(hasSelectedState: true, isSelected: true));
    expect(key('toast'), findsNothing);

    await press(tester, '关注');
    await frames(tester);
    expect(harness.pageApi.calls, contains('follow on=true'));
    await expectToast(tester, '关注成功');

    await press(tester, '更多推荐');
    await expectToast(tester, '暂未开放');
    for (final row in ['加入特别关注', '设置分组']) {
      await press(tester, '已关注');
      await tester.pumpAndSettle();
      await press(tester, row);
      await expectToast(tester, '暂未开放');
      await tester.pumpAndSettle();
      expect(key('space-sheet'), findsNothing, reason: row);
    }
    await press(tester, '已关注');
    await tester.pumpAndSettle();
    await press(tester, '取消');
    await tester.pumpAndSettle();
    expect(key('space-sheet'), findsNothing);
    await press(tester, '已关注');
    await tester.pumpAndSettle();
    await press(tester, '取消关注');
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(harness.pageApi.calls, contains('follow on=false'));
    await expectToast(tester, '取消关注成功');

    // The bar's pill, once the header has gone under the bar.
    scroll(tester).jumpTo(scroll(tester).maxScrollExtent);
    await tester.pumpAndSettle();
    tester.semantics.tap(find.semantics.byPredicate((node) => node.label == '关注' && !node.isInvisible));
    await frames(tester);
    expect(harness.pageApi.calls.where((call) => call == 'follow on=true'), hasLength(2));
    await expectToast(tester, '关注成功');

    await press(tester, '返回');
    await tester.pumpAndSettle();
    expect(find.byType(SpacePage), findsNothing);
  });

  testWidgets('collapsed, the bar\'s hidden 私信 is out of the accessibility tree', (tester) async {
    await show(tester);
    expect(find.semantics.byLabel('私信'), findsOne);
    scroll(tester).jumpTo(scroll(tester).maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.semantics.byLabel('私信'), findsNothing);
    for (final label in ['返回', '搜索', '更多']) {
      expect(find.semantics.byLabel(label), findsOne, reason: label);
    }
    scroll(tester).jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.semantics.byLabel('私信'), findsOne);
  });

  testWidgets('scrolling under the discs, the header\'s 关注 row keeps the taps outside them', (tester) async {
    final harness = await show(tester);
    // The row runs 52.67 to 82.67 here, through the discs' 44 pt targets (47 to 91); the bar is still down.
    scroll(tester).jumpTo(180);
    await tester.pumpAndSettle();
    expect(barOpacity(tester), 0);
    // Inside ⋮'s target, 17 from its disc's centre: + 关注.
    const besideMore = Offset(403, 81);
    expect(tester.getRect(key('space-follow')).contains(besideMore), isTrue);
    await tester.tapAt(besideMore);
    await frames(tester);
    expect(harness.pageApi.calls, contains('follow on=true'));
    await expectToast(tester, '关注成功');

    // Inside 搜索's target, 17 from its disc's centre: 已关注, which opens its sheet.
    const besideSearch = Offset(385, 81);
    expect(tester.getRect(key('space-followed')).contains(besideSearch), isTrue);
    await tester.tapAt(besideSearch);
    await tester.pumpAndSettle();
    expect(key('space-sheet'), findsOneWidget);
    await tester.tap(key('space-sheet-cancel'));
    await tester.pumpAndSettle();

    // The discs themselves still answer.
    await tester.tapAt(tester.getCenter(key('space-more')));
    await tester.pump();
    await expectToast(tester, '暂未开放');
  });

  testWidgets('a login from the space\'s gate asks the 关注 state again', (tester) async {
    final harness = await show(
      tester,
      loggedIn: false,
      following: true,
      login: (environment, _) async {
        environment.useFakeAccount();
        return true;
      },
    );
    expect(harness.cardCalls, 0, reason: 'logged out the card is not asked');
    await tester.tap(key('space-follow'));
    await frames(tester);
    expect(harness.gate.requests, 1);
    expect(harness.cardCalls, 1);
    expect(key('space-followed'), findsOneWidget, reason: 'the account that logged in follows already');
    expect(harness.pageApi.calls, isNot(contains('follow on=true')), reason: 'the tap that asked for the login is not replayed');
  });

  testWidgets('a login on the login page asks the 关注 state again, once', (tester) async {
    final harness = await show(
      tester,
      loggedIn: false,
      following: true,
      login: (environment, http) {
        http.routes[Canned.navPath] = (200, Canned.navLoggedIn);
        return environment.didLogin(_login);
      },
    );
    await tester.tap(key('space-follow'));
    await frames(tester);
    expect(harness.gate.requests, 1);
    expect(harness.services.environment.account, isA<LoggedIn>());
    expect(harness.cardCalls, 1, reason: 'the login is heard once, though the gate answers it too');
    expect(key('space-followed'), findsOneWidget);
  });

  testWidgets('a login made elsewhere asks the 关注 state again', (tester) async {
    final harness = await show(tester, loggedIn: false, following: true);
    harness.http.routes[Canned.navPath] = (200, Canned.navLoggedIn);
    unawaited(harness.services.environment.didLogin(_login));
    await frames(tester);
    expect(harness.cardCalls, 1);
    expect(key('space-followed'), findsOneWidget);
  });

  void expectSelected(WidgetTester tester, String kind, {required bool selected}) => expect(
    tester.getSemantics(key('space-tab-$kind')),
    isSemantics(hasSelectedState: true, isSelected: selected),
    reason: kind,
  );

  /// A post's card, found below the fold too.
  Finder card(String id) => find.byKey(ValueKey('space-dynamic-$id'), skipOffstage: false);

  /// Scrolls the shown tab to its end and lets the paging check run.
  Future<void> toEnd(WidgetTester tester) async {
    scroll(tester).jumpTo(scroll(tester).maxScrollExtent);
    await frames(tester);
  }

  testWidgets('动态 selects, pink over its bar, and lists the space\'s posts as cards with grey between', (tester) async {
    final harness = await show(
      tester,
      dynamicApi: FakeDynamicApi(posts: [_post(1), _post(2, mid: _mid + 1), _post(3)]),
    );
    expect(harness.dynamicApi.calls, isEmpty, reason: '动态 is asked when first shown');

    await tester.tap(key('space-tab-dynamic'));
    await frames(tester);
    expect(key('toast'), findsNothing);
    expectSelected(tester, 'dynamic', selected: true);
    expectSelected(tester, 'contribute', selected: false);
    expect(
      tester.getRect(key('space-tab-indicator')).center.dx,
      moreOrLessEquals(tester.getRect(key('space-tab-dynamic')).center.dx),
    );
    final label = tester.widget<Text>(find.descendant(of: key('space-tab-dynamic'), matching: find.text('动态')));
    expect(label.style?.color, SpaceTheme.tabSelected);
    expect(harness.dynamicApi.calls, ['spacePosts $_mid offset=']);
    expect(
      tester
          .widgetList<DynamicCard>(find.byType(DynamicCard, skipOffstage: false))
          .map((card) => (card.item.id, card.inline, card.space)),
      [('9101', null, true), ('9103', null, true)],
    );
    expect(key('space-play-all'), findsNothing, reason: '投稿\'s strip stays in 投稿');
    // Each card draws the 10 pt grey under itself (136), so they stack with no gap of the list's own.
    expect(tester.getRect(card('9103')).top - tester.getRect(card('9101')).bottom, moreOrLessEquals(0));
    final fill = tester.widget<DecoratedSliver>(find.byType(DecoratedSliver));
    expect((fill.decoration as BoxDecoration).color, BiliColors.softGrey);
    expect(key('space-dynamics-end'), findsOneWidget);
  });

  testWidgets('动态\'s first load shows the TV; a failure says why with 点击重试, which asks again', (tester) async {
    final api = FakeDynamicApi(posts: [_post(1)]);
    final hold = api.holds['spacePosts'] = Completer<void>();
    await show(tester, dynamicApi: api);
    await tester.tap(key('space-tab-dynamic'));
    await frames(tester);
    expect(key('space-dynamics-loading'), findsOneWidget);
    expect(find.byType(LoadingTvState), findsOneWidget);
    expect(find.byType(DynamicCard, skipOffstage: false), findsNothing);

    // Risk control's answer, in its own words rather than 加载失败.
    api.failures['spacePosts'] = const BiliError.api(code: -352, message: '风控校验失败');
    api.holds.remove('spacePosts');
    hold.complete();
    await frames(tester);
    expect(key('space-dynamics-loading'), findsNothing);
    expect(key('space-dynamics-retry'), findsOneWidget);
    expect(find.text('请求过于频繁，请稍后再试，点击重试', findRichText: true), findsOneWidget);
    expect(find.textContaining('加载失败', findRichText: true), findsNothing);
    await frames(tester);
    expect(api.calls, ['spacePosts $_mid offset='], reason: 'a failure waits for the tap');

    api.failures.remove('spacePosts');
    await press(tester, '请求过于频繁，请稍后再试，点击重试');
    await frames(tester);
    expect(api.calls, ['spacePosts $_mid offset=', 'spacePosts $_mid offset=']);
    expect(key('space-dynamics-retry'), findsNothing);
    expect(find.byType(DynamicCard, skipOffstage: false), findsOneWidget);
  });

  testWidgets('动态 pages near the end, one call at a time, until a page says there is no more', (tester) async {
    final api = FakeDynamicApi(posts: [for (var i = 1; i <= 7; i++) _post(i)], pageSize: 3);
    final first = api.holds['spacePosts'] = Completer<void>();
    await show(tester, dynamicApi: api);
    await tester.tap(key('space-tab-dynamic'));
    await frames(tester);
    expect(api.calls, ['spacePosts $_mid offset=']);

    final second = Completer<void>();
    first.complete();
    api.holds['spacePosts'] = second;
    await frames(tester);
    await toEnd(tester);
    expect(api.calls, ['spacePosts $_mid offset=', 'spacePosts $_mid offset=p1']);
    expect(key('space-dynamics-more-spinner'), findsOneWidget);
    await toEnd(tester);
    expect(api.calls, hasLength(2), reason: 'one call at a time');

    // That page fails: why, with 点击重试, under the cards, and scrolling asks nothing more.
    api.failures['spacePosts'] = const BiliError.http(412);
    api.holds.remove('spacePosts');
    second.complete();
    await frames(tester);
    await toEnd(tester);
    expect(key('space-dynamics-retry'), findsOneWidget);
    expect(find.text('B 站暂时拒绝了请求（风控），稍后再试，点击重试', findRichText: true), findsOneWidget);
    expect(key('space-dynamics-more-spinner'), findsNothing);
    expect(api.calls, hasLength(2));

    api.failures.remove('spacePosts');
    await tester.tap(key('space-dynamics-retry'));
    await frames(tester);
    await toEnd(tester);
    await toEnd(tester);
    expect(api.calls, [
      'spacePosts $_mid offset=',
      'spacePosts $_mid offset=p1',
      'spacePosts $_mid offset=p1',
      'spacePosts $_mid offset=p2',
    ]);
    expect(card('9107'), findsOneWidget);
    expect(find.descendant(of: key('space-dynamics-end'), matching: find.text('已经到底啦~')), findsOneWidget);
    await toEnd(tester);
    expect(api.calls, hasLength(4), reason: 'the end asks nothing more');
  });

  for (final (what, second) in [
    ('an empty page', const <DynamicItem>[]),
    ('a page of posts already listed', [_post(2), _post(1)]),
  ]) {
    testWidgets('$what ends the list, though the answer says there is more', (tester) async {
      final api = FakeDynamicApi(
        spacePages: {
          _mid: [
            DynamicPage(items: [_post(1), _post(2)], offset: 'p1', hasMore: true),
            DynamicPage(items: second, offset: 'p2', hasMore: true),
            DynamicPage(items: [_post(3)], offset: 'p3', hasMore: true),
          ],
        },
      );
      await show(tester, dynamicApi: api);
      await tester.tap(key('space-tab-dynamic'));
      await frames(tester);
      await toEnd(tester);
      await toEnd(tester);
      await toEnd(tester);
      expect(api.calls, ['spacePosts $_mid offset=', 'spacePosts $_mid offset=p1']);
      expect(card('9101'), findsOneWidget);
      expect(card('9102'), findsOneWidget);
      expect(card('9103'), findsNothing);
      expect(find.descendant(of: key('space-dynamics-end'), matching: find.text('已经到底啦~')), findsOneWidget);
      expect(key('space-dynamics-more-spinner'), findsNothing);
    });
  }

  testWidgets('投稿 and 动态 keep their lists, 投稿\'s sort and where each was, asking nothing again', (tester) async {
    final harness = await show(
      tester,
      videos: [for (var i = 0; i < 30; i++) _video(i)],
      dynamicApi: FakeDynamicApi(posts: [for (var i = 1; i <= 4; i++) _post(i)]),
    );
    List<String> videoCalls() => harness.spaceApi.calls.where((call) => call.startsWith('videos')).toList();
    await tester.tap(key('space-sort'));
    await frames(tester);
    scroll(tester).jumpTo(900);
    await tester.pumpAndSettle();
    final asked = videoCalls();
    expect(asked.last, startsWith('videos mid=$_mid order=click'));
    final row = tester.getRect(key('space-row-BV1space0020'));
    expect(barOpacity(tester), 1);

    // The header scrolled away: 动态 opens at its top, under the pinned row.
    await tester.tap(key('space-tab-dynamic'));
    await frames(tester);
    expect(tester.getRect(key('space-tabs')).top, moreOrLessEquals(62 + 32));
    expect(tester.getRect(card('9101')).top, moreOrLessEquals(tester.getRect(key('space-tabs')).bottom));
    expect(barOpacity(tester), 1);
    expect(harness.dynamicApi.calls, ['spacePosts $_mid offset=']);

    await tester.tap(key('space-tab-contribute'));
    await frames(tester);
    expect(scroll(tester).pixels, 900);
    expect(tester.getRect(key('space-row-BV1space0020')), row);
    // Scrolled above the screen, so off stage to the finder.
    expect(tester.widget<Text>(find.byKey(const ValueKey('space-sort-label'), skipOffstage: false)).data, '最多播放');
    expect(videoCalls(), asked, reason: 'kept, not asked again');

    await tester.tap(key('space-tab-dynamic'));
    await frames(tester);
    expect(card('9101'), findsOneWidget);
    expect(harness.dynamicApi.calls, ['spacePosts $_mid offset='], reason: 'kept, not asked again');

    // A header shown in part shows as much in the other tab.
    scroll(tester).jumpTo(100);
    await tester.pumpAndSettle();
    await tester.tap(key('space-tab-contribute'));
    await frames(tester);
    expect(scroll(tester).pixels, 100);
    expect(barOpacity(tester), 0);
    expect(videoCalls(), asked);
  });

  testWidgets('a space whose default tab is 动态 opens on it; 投稿 is asked when first shown', (tester) async {
    final harness = await show(
      tester,
      profile: _profile(defaultTab: SpaceTabKind.dynamic),
      dynamicApi: FakeDynamicApi(posts: [_post(1)]),
    );
    expectSelected(tester, 'dynamic', selected: true);
    expectSelected(tester, 'contribute', selected: false);
    expect(harness.dynamicApi.calls, ['spacePosts $_mid offset=']);
    expect(harness.spaceApi.calls.where((call) => call.startsWith('videos')), isEmpty);

    await tester.tap(key('space-tab-contribute'));
    await frames(tester);
    expectSelected(tester, 'contribute', selected: true);
    expect(harness.spaceApi.calls.where((call) => call.startsWith('videos')), hasLength(1));
  });

  testWidgets('a default of 动态 that the row lacks opens 投稿', (tester) async {
    final harness = await show(
      tester,
      profile: _profile(
        tabs: const [SpaceTab(kind: SpaceTabKind.contribute, title: '投稿')],
        defaultTab: SpaceTabKind.dynamic,
      ),
    );
    expectSelected(tester, 'contribute', selected: true);
    expect(harness.dynamicApi.calls, isEmpty);
  });

  testWidgets(
    'on Windows the drawn status bar follows the page: light over a picture banner, dark under the bar',
    (tester) async {
      await show(tester, profile: _profile(banner: 'https://i0.hdslb.com/bfs/space/banner.png'), framed: true);
      await frames(tester, 2);
      expect(PhoneFrame.statusBarBrightness.value, Brightness.dark, reason: 'light content, as 72');
      scroll(tester).jumpTo(scroll(tester).maxScrollExtent);
      await tester.pumpAndSettle();
      expect(PhoneFrame.statusBarBrightness.value, Brightness.light, reason: 'dark content over the white bar');
      scroll(tester).jumpTo(0);
      await tester.pumpAndSettle();
      expect(PhoneFrame.statusBarBrightness.value, Brightness.dark);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
