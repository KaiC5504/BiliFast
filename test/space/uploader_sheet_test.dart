import 'dart:async';

import 'package:bili_core/api.dart' show BiliError, SpaceProfile, SpaceVideo, UploaderCard;
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/shared/loading_tv.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/space/fake_space_api.dart';
import 'package:bilifast/space/space_page.dart';
import 'package:bilifast/space/uploader_sheet.dart';
import 'package:bilifast/space/uploader_sheet_grid.dart';
import 'package:bilifast/space/uploader_tap.dart';
import 'package:bilifast/video/actions/unfollow_confirm.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';

const _mid = 42;
const _playing = 'BV1sheet0002';
const _ref = UploaderRef(mid: _mid, name: '演示UP主', face: '');

/// The player box's bottom on the iPhone: the status bar and a 16:9 player.
const _top = 62 + 440 / 16 * 9;

class _Gate implements LoginGate {
  int asks = 0;

  @override
  Future<bool> request(BuildContext context) async {
    asks += 1;
    return false;
  }
}

SpaceVideo _video(int i) => SpaceVideo(
  aid: i,
  bvid: 'BV1sheet${i.toString().padLeft(4, '0')}',
  title: '演示视频 第$i期',
  cover: '',
  duration: 37 + i,
  play: 22000 + i,
  publishedText: '10月$i日',
);

void main() {
  late FakeSpaceApi spaceApi;
  late FakePageApi pageApi;
  late AppServices services;
  late UploaderSheetController sheet;
  late List<VideoRoute> opened;
  late int playerTaps;
  late _Gate gate;
  late GlobalKey<NavigatorState> nav;

  setUp(() {
    spaceApi = FakeSpaceApi(
      profileFor: (mid) => SpaceProfile(mid: mid, name: '演示UP主', face: '', fans: 30000, videoCount: 71, likes: 969000),
      videoList: [for (var i = 1; i <= 45; i++) _video(i)],
    );
    pageApi = FakePageApi(
      uploader: const UploaderCard(mid: 0, name: '', face: '', fans: 0, videos: 0, isVip: false, following: false),
    );
    opened = [];
    playerTaps = 0;
    gate = _Gate();
    nav = GlobalKey<NavigatorState>();
  });

  Future<void> frames(WidgetTester tester, [int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// A page with a player box over a body whose row opens the uploader, as the video page has them, at the iPhone's
  /// size. [following] is what the page knows of 关注 for the uploader.
  Future<void> show(
    WidgetTester tester, {
    bool loggedIn = true,
    bool? following,
    bool reduceMotion = false,
    Listenable? logins,
  }) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: 62, bottom: 34)
      ..viewPadding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    final logger = Logger(session: 'test');
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(loggedIn ? const StoredCookies(Canned.cookies) : const NoStoredCookies()),
      http: Canned.http(),
      logger: logger,
    );
    await environment.refreshAccount();
    final playback = AppPlayback(() => Completer<PlaybackController>().future);
    addTearDown(playback.dispose);
    services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      pageApi: pageApi,
      spaceApi: spaceApi,
      loginGate: gate,
    );
    sheet = UploaderSheetController();
    addTearDown(sheet.dispose);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        builder: (context, child) => AppScope(
          services: services,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
            child: child!,
          ),
        ),
        home: Scaffold(
          body: UploaderTap(
            open: sheet.open,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: _top,
                  child: GestureDetector(
                    key: const ValueKey('player'),
                    onTap: () => playerTaps += 1,
                    child: const ColoredBox(color: Colors.black),
                  ),
                ),
                Positioned(
                  left: 40,
                  top: 400,
                  child: Builder(
                    builder: (context) => GestureDetector(
                      key: const ValueKey('uploader-row'),
                      onTap: () => openUploader(context, _ref),
                      child: const SizedBox(width: 100, height: 40, child: Text('UP')),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: UploaderSheetLayer(
                    controller: sheet,
                    top: _top,
                    playingBvid: _playing,
                    followingOf: (mid) => mid == _mid ? following : null,
                    logins: logins,
                    openPage: (context, route) async => opened.add(route),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('uploader-row')));
    await frames(tester);
  }

  Finder text(String key) => find.byKey(ValueKey(key));

  String plain(WidgetTester tester, String key) => tester.widget<Text>(text(key)).textSpan!.toPlainText();

  ScrollPosition grid(WidgetTester tester) => tester
      .state<ScrollableState>(find.descendant(of: text('uploader-sheet-grid'), matching: find.byType(Scrollable)))
      .position;

  testWidgets('the uploader row opens the sheet under the player, which keeps taking taps; it rises over 300 ms', (
    tester,
  ) async {
    await show(tester);
    expect(find.byType(UploaderSheet), findsNothing);
    await tester.tap(find.byKey(const ValueKey('uploader-row')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final rising = tester.getRect(text('uploader-sheet-header'));
    expect(rising.top, greaterThan(_top), reason: 'still on its way up');
    await tester.pump(const Duration(milliseconds: 200));
    expect(sheet.uploader?.mid, _mid);
    final sheetRect = tester.getRect(text('uploader-sheet'));
    expect(sheetRect.top, _top);
    expect(sheetRect.bottom, 956);
    expect(tester.getRect(text('uploader-sheet-header')).top, _top);

    await tester.tap(find.byKey(const ValueKey('player')));
    expect(playerTaps, 1);
    expect(sheet.isOpen, isTrue);
    expect(find.text('演示UP主'), findsOneWidget);
  });

  testWidgets('under Reduce Motion it is up in one frame', (tester) async {
    await show(tester, reduceMotion: true);
    await tester.tap(find.byKey(const ValueKey('uploader-row')));
    await tester.pump();
    await tester.pump();
    expect(tester.getRect(text('uploader-sheet-header')).top, _top);
  });

  testWidgets('the first load shows the loading TV, then the counts and the grid', (tester) async {
    final videos = Completer<void>();
    spaceApi.holds['videos'] = videos;
    await show(tester);
    await open(tester);
    expect(find.byType(LoadingTvState), findsOneWidget);
    expect(find.byType(UploaderVideoCard), findsNothing);
    expect(plain(tester, 'uploader-sheet-counts'), '3万粉丝71投稿96.9万获赞');
    videos.complete();
    await frames(tester);
    expect(find.byType(LoadingTvState), findsNothing);
    expect(find.byType(UploaderVideoCard), findsWidgets);
    expect(spaceApi.calls, ['profile mid=$_mid', 'videos mid=$_mid order=pubdate next=null']);
    // Two to a row, 8 from the sides and each other, each cover 16:9.
    final first = tester.getRect(find.byType(UploaderVideoCard).at(0));
    final second = tester.getRect(find.byType(UploaderVideoCard).at(1));
    expect(first.left, 8);
    expect(second.left, 224);
    expect(first.width, 208);
    expect(first.top, _top + UploaderSheetTheme.gridTop);
    expect(first.height, 117 + 52);
    expect(find.text('2.2万'), findsWidgets);
    expect(find.text('10月1日'), findsOneWidget);
    expect(find.text('00:38'), findsOneWidget);
  });

  testWidgets('a failed first load says why and offers 重试, which loads again', (tester) async {
    spaceApi.failures['videos'] = const BiliError.http(500);
    await show(tester);
    await open(tester);
    expect(find.byKey(const ValueKey('uploader-sheet-failed')), findsOneWidget);
    expect(find.text('网络请求失败（HTTP 500）'), findsOneWidget);
    spaceApi.failures.clear();
    await tester.tap(find.byKey(const ValueKey('uploader-sheet-retry')));
    await frames(tester);
    expect(find.byType(UploaderVideoCard), findsWidgets);
    expect(spaceApi.calls.where((call) => call.startsWith('videos')), hasLength(2));
  });

  testWidgets('more pages load as the end nears, the small spinner meanwhile, until 已经到底啦~', (tester) async {
    await show(tester);
    await open(tester);
    expect(spaceApi.calls.where((call) => call.startsWith('videos')), hasLength(1));
    final held = Completer<void>();
    spaceApi.holds['videos'] = held;
    grid(tester).jumpTo(grid(tester).maxScrollExtent);
    await tester.pump();
    await tester.pump();
    expect(spaceApi.calls.last, 'videos mid=$_mid order=pubdate next=20');
    expect(find.byKey(const ValueKey('uploader-sheet-loading-more')), findsOneWidget);
    expect(find.text('已经到底啦~'), findsNothing);
    held.complete();
    spaceApi.holds.clear();
    await frames(tester);
    grid(tester).jumpTo(grid(tester).maxScrollExtent);
    await frames(tester);
    expect(spaceApi.calls.last, 'videos mid=$_mid order=pubdate next=40');
    grid(tester).jumpTo(grid(tester).maxScrollExtent);
    await frames(tester);
    expect(find.text('已经到底啦~'), findsOneWidget);
    expect(find.byKey(const ValueKey('uploader-sheet-loading-more')), findsNothing);
    expect(
      spaceApi.calls.where((call) => call.startsWith('videos')),
      hasLength(3),
      reason: 'nothing asked past the end',
    );
    expect(find.byType(UploaderVideoCard), findsWidgets);
  });

  testWidgets('a failed next page waits for 点击重试', (tester) async {
    await show(tester);
    await open(tester);
    spaceApi.failures['videos'] = const BiliError.http(500);
    grid(tester).jumpTo(grid(tester).maxScrollExtent);
    await frames(tester);
    expect(find.byKey(const ValueKey('uploader-sheet-footer-retry')), findsOneWidget);
    grid(tester).jumpTo(grid(tester).maxScrollExtent - 1);
    await frames(tester);
    expect(spaceApi.calls.where((call) => call.startsWith('videos')), hasLength(2), reason: 'no ask until the tap');
    spaceApi.failures.clear();
    await tester.tap(find.byKey(const ValueKey('uploader-sheet-footer-retry')));
    await frames(tester);
    expect(spaceApi.calls.last, 'videos mid=$_mid order=pubdate next=20');
  });

  testWidgets('the page\'s video draws its title pink after the playing mark; the others don\'t', (tester) async {
    await show(tester);
    await open(tester);
    final mark = find.byKey(const ValueKey('uploader-sheet-playing'));
    expect(mark, findsOneWidget);
    expect(find.descendant(of: find.byType(UploaderVideoCard).at(1), matching: mark), findsOneWidget);
    Color ink(String bvid) => tester.widget<Text>(text('uploader-sheet-title-$bvid')).style!.color!;
    expect(ink(_playing), BiliColors.pink);
    expect(ink('BV1sheet0001'), BiliColors.text);
  });

  testWidgets('a card opens its video as a new page and the sheet stays; the page\'s own opens nothing', (
    tester,
  ) async {
    await show(tester);
    await open(tester);
    await tester.tap(find.byType(UploaderVideoCard).at(0));
    await tester.pump();
    expect(opened.single.bvid, 'BV1sheet0001');
    expect(opened.single.title, '演示视频 第1期');
    expect(sheet.isOpen, isTrue);
    await tester.tap(find.byType(UploaderVideoCard).at(1));
    await tester.pump();
    expect(opened, hasLength(1));
  });

  testWidgets('the face and 进入空间 open the space, with the sheet still there underneath', (tester) async {
    await show(tester);
    await open(tester);
    await tester.tap(text('uploader-sheet-face'));
    await frames(tester, 20);
    expect(find.byType(SpacePage), findsOneWidget);
    expect(tester.widget<SpacePage>(find.byType(SpacePage)).uploader.mid, _mid);
    nav.currentState!.pop();
    await frames(tester, 20);
    expect(find.byType(SpacePage), findsNothing);
    expect(sheet.isOpen, isTrue);
    await tester.tap(text('uploader-sheet-enter'));
    await frames(tester, 20);
    expect(tester.widget<SpacePage>(find.byType(SpacePage)).uploader.name, '演示UP主');
    nav.currentState!.pop();
    await frames(tester, 20);
  });

  group('closing', () {
    testWidgets('dragged down by its header it follows the finger and closes; a short drag springs back', (
      tester,
    ) async {
      await show(tester);
      await open(tester);
      final header = text('uploader-sheet-header');
      final gesture = await tester.startGesture(tester.getCenter(header) - const Offset(100, 0));
      await gesture.moveBy(const Offset(0, 20));
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      expect(tester.getRect(header).top, greaterThan(_top + 30));
      await gesture.up();
      await frames(tester);
      expect(sheet.isOpen, isTrue);
      expect(tester.getRect(header).top, _top, reason: 'sprung back');

      await tester.timedDrag(header, const Offset(0, 300), const Duration(milliseconds: 300));
      await frames(tester);
      expect(sheet.isOpen, isFalse);
      expect(find.byType(UploaderSheet), findsNothing, reason: 'gone once it slid away');
    });

    testWidgets('pulled down with the grid at its top it goes the same way', (tester) async {
      await show(tester);
      await open(tester);
      await tester.timedDragFrom(const Offset(220, 600), const Offset(0, 300), const Duration(milliseconds: 300));
      await frames(tester);
      expect(sheet.isOpen, isFalse);
    });

    testWidgets('a pull up scrolls the grid and leaves the sheet', (tester) async {
      await show(tester);
      await open(tester);
      await tester.timedDragFrom(const Offset(220, 800), const Offset(0, -300), const Duration(milliseconds: 300));
      await frames(tester);
      expect(sheet.isOpen, isTrue);
      expect(grid(tester).pixels, greaterThan(0));
      expect(tester.getRect(text('uploader-sheet-header')).top, _top);
    });

    testWidgets('a swipe from the left edge closes it', (tester) async {
      await show(tester);
      await open(tester);
      await tester.timedDragFrom(const Offset(5, 700), const Offset(300, 0), const Duration(milliseconds: 200));
      await frames(tester);
      expect(sheet.isOpen, isFalse);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('back closes the unfollow confirm first, then the sheet', (tester) async {
      await show(tester, following: true);
      await open(tester);
      await tester.tap(text('uploader-sheet-follow'));
      await frames(tester);
      expect(find.byType(UnfollowConfirm), findsOneWidget);
      expect(sheet.back(), isTrue);
      await frames(tester);
      expect(find.byType(UnfollowConfirm), findsNothing);
      expect(sheet.isOpen, isTrue);
      expect(sheet.back(), isTrue);
      await frames(tester);
      expect(sheet.isOpen, isFalse);
      expect(sheet.back(), isFalse);
    });
  });

  group('关注', () {
    testWidgets('+ 关注 follows at once and says so; 已关注 asks first, and 取消 keeps it', (tester) async {
      await show(tester);
      await open(tester);
      expect(pageApi.calls, ['uploaderCard mid=$_mid'], reason: 'not the page\'s uploader: the card is asked');
      expect(find.text('关注'), findsOneWidget);
      await tester.tap(text('uploader-sheet-follow'));
      await frames(tester);
      expect(pageApi.calls.last, 'follow on=true');
      expect(find.text('已关注'), findsOneWidget);
      expect(services.follows.last, (mid: _mid, following: true));
      expect(find.text('关注成功'), findsOneWidget);
      await frames(tester, 50);

      await tester.tap(text('uploader-sheet-follow'));
      await frames(tester);
      expect(find.text('确定不再关注？'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('unfollow-取消')));
      await frames(tester);
      expect(find.byType(UnfollowConfirm), findsNothing);
      expect(pageApi.calls.where((call) => call.startsWith('follow')), hasLength(1));
      expect(find.text('已关注'), findsOneWidget);

      await tester.tap(text('uploader-sheet-follow'));
      await frames(tester);
      await tester.tap(find.byKey(const ValueKey('unfollow-确定')));
      await frames(tester);
      expect(pageApi.calls.last, 'follow on=false');
      expect(find.text('关注'), findsOneWidget);
      expect(services.follows.last, (mid: _mid, following: false));
      await frames(tester, 50);
    });

    testWidgets('the page\'s own uploader starts from the page\'s 关注 without asking', (tester) async {
      await show(tester, following: true);
      await open(tester);
      expect(pageApi.calls, isEmpty);
      expect(find.text('已关注'), findsOneWidget);
    });

    testWidgets('a change made on the page shows in the sheet', (tester) async {
      await show(tester, following: false);
      await open(tester);
      services.follows.changed(_mid, following: true);
      await frames(tester);
      expect(find.text('已关注'), findsOneWidget);
    });

    testWidgets('a check that failed is made again on the tap, and an uploader already followed shows 已关注', (
      tester,
    ) async {
      pageApi.failures['uploaderCard'] = const BiliError.http(500);
      await show(tester);
      await open(tester);
      expect(find.text('关注'), findsOneWidget);
      pageApi.failures.clear();
      pageApi.uploader = const UploaderCard(
        mid: 0,
        name: '',
        face: '',
        fans: 0,
        videos: 0,
        isVip: false,
        following: true,
      );
      await tester.tap(text('uploader-sheet-follow'));
      await frames(tester);
      expect(find.text('已关注'), findsOneWidget);
      expect(pageApi.calls, ['uploaderCard mid=$_mid', 'uploaderCard mid=$_mid'], reason: 'no follow sent');
    });

    testWidgets('取消关注 confirmed while the follow is still out goes once it returns', (tester) async {
      await show(tester, following: false);
      await open(tester);
      final held = pageApi.holds['follow'] = Completer<void>();
      await tester.tap(text('uploader-sheet-follow'));
      await frames(tester);
      expect(find.text('已关注'), findsOneWidget);
      await tester.tap(text('uploader-sheet-follow'));
      await frames(tester);
      await tester.tap(find.byKey(const ValueKey('unfollow-确定')));
      await frames(tester);
      expect(find.text('关注'), findsOneWidget);
      expect(pageApi.calls, ['follow on=true']);

      pageApi.holds.clear();
      held.complete();
      await frames(tester);
      expect(pageApi.calls, ['follow on=true', 'follow on=false']);
      expect(find.text('关注'), findsOneWidget);
      expect(services.follows.last, (mid: _mid, following: false));
      await frames(tester, 50);
    });

    testWidgets('logged out, 关注 asks for the login and sends nothing', (tester) async {
      await show(tester, loggedIn: false);
      await open(tester);
      await tester.tap(text('uploader-sheet-follow'));
      await frames(tester);
      expect(gate.asks, 1);
      expect(pageApi.calls, isEmpty);
      expect(find.text('关注'), findsOneWidget);
    });

    testWidgets('a login made from the page asks the card again', (tester) async {
      final logins = ValueNotifier<int>(0);
      addTearDown(logins.dispose);
      await show(tester, logins: logins);
      await open(tester);
      expect(pageApi.calls, ['uploaderCard mid=$_mid']);
      pageApi.uploader = const UploaderCard(
        mid: 0,
        name: '',
        face: '',
        fans: 0,
        videos: 0,
        isVip: false,
        following: true,
      );
      logins.value += 1;
      await frames(tester);
      expect(pageApi.calls, hasLength(2));
      expect(find.text('已关注'), findsOneWidget);
    });
  });
}
