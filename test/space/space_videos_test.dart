import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/space/fake_space_api.dart';
import 'package:bilifast/space/space_api.dart';
import 'package:bilifast/space/space_video_menu.dart';
import 'package:bilifast/space/space_video_row.dart';
import 'package:bilifast/space/space_videos.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../home/fake_login_gate.dart';
import '../search/results/results_support.dart';

const _mid = 4242;

/// Made-up videos: no real titles or ids. Plays fall as the index grows except where [plays] says otherwise.
List<SpaceVideo> videos(int count, {List<int>? plays}) => [
  for (var i = 0; i < count; i++)
    SpaceVideo(
      aid: 9000 + i,
      bvid: 'BV1space${i.toString().padLeft(3, '0')}',
      title: '测试视频 $i',
      cover: '',
      duration: 28 + i * 60,
      play: plays?[i] ?? 1000 * (count - i),
      danmaku: i,
      publishedText: '${i + 1}小时前',
      badges: i == 2 ? const ['合作'] : const [],
    ),
];

const _video = SpaceChip(kind: SpaceChipKind.video, title: '视频');
const _article = SpaceChip(kind: SpaceChipKind.article, title: '图文');
const _season = SpaceChip(kind: SpaceChipKind.season, title: '测试合集', seasonId: 7);

SpaceProfile profile({List<SpaceChip> chips = const [_video, _article, _season]}) =>
    SpaceProfile(mid: _mid, name: '测试UP主', face: '', chips: chips);

/// Answers each call with [answer]'s page, counting them: for a server that repeats itself.
class _ScriptedSpaceApi implements SpaceApi {
  _ScriptedSpaceApi(this.answer);

  final SpaceVideoPage Function(String? next) answer;
  final calls = <String?>[];

  @override
  Future<SpaceProfile> profile(int mid) async => throw UnimplementedError();

  @override
  Future<SpaceProfile> ownProfile(int mid) async => throw UnimplementedError();

  @override
  Future<SpaceBangumiPage> bangumi(int mid, {required int page}) async => throw UnimplementedError();

  @override
  Future<SpaceVideoPage> videos(int mid, {required SpaceOrder order, String? next}) async {
    calls.add(next);
    return answer(next);
  }

  @override
  Future<SpaceVideoPage> chipVideos(int mid, SpaceChip chip, {String? next}) async => throw UnimplementedError();
}

void main() {
  late FakeSpaceApi api;
  late FakePageApi pageApi;
  late FakeLoginGate gate;
  late List<VideoRoute> opened;
  late List<Uri> shared;
  late ScrollController scroll;

  setUp(() {
    api = FakeSpaceApi(videoList: videos(45));
    pageApi = FakePageApi();
    gate = FakeLoginGate();
    opened = [];
    shared = [];
    scroll = ScrollController();
  });

  tearDown(() => scroll.dispose());

  /// The list under a 463.33 header, as 63 and 70 have it, in a scroll view of its own.
  Future<AppServices> show(
    WidgetTester tester, {
    SpaceProfile? space,
    SpaceApi? spaceApi,
    bool loggedIn = true,
    Future<bool> Function(Uri link)? share,
  }) async {
    final services = await resultServices(loggedIn: loggedIn, api: pageApi, gate: gate);
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpInApp(
      tester,
      services,
      CustomScrollView(
        controller: scroll,
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 1390 / 3)),
          SpaceVideosSliver(
            profile: space ?? profile(),
            api: spaceApi ?? api,
            open: (context, route) => opened.add(route),
            share:
                share ??
                (link) async {
                  shared.add(link);
                  return true;
                },
          ),
        ],
      ),
    );
    await settle(tester);
    return services;
  }

  Finder row(int i) => find.byKey(ValueKey('space-row-BV1space${i.toString().padLeft(3, '0')}'));

  testWidgets('rows: the cover with its length and badge, the title, the date, plays and danmaku', (tester) async {
    await show(tester);
    expect(api.calls, ['videos mid=$_mid order=pubdate next=null']);
    expect(find.text('测试视频 0'), findsOneWidget);
    expect(find.text('1小时前'), findsOneWidget);
    expect(find.text('4.5万'), findsOneWidget, reason: "the first row's 45000 plays");
    expect(find.text('0:28'), findsOneWidget);
    expect(find.text('01:28'), findsOneWidget);
    expect(find.text('合作'), findsOneWidget);

    final first = tester.getRect(row(0));
    expect(first.top, closeTo(1390 / 3 + 42 + 82 / 3, 0.01), reason: 'under the chips and 播放全部');
    expect(first.height, 93);
    expect(tester.getRect(row(1)).top, first.top + 93);
    expect(tester.getCenter(find.byKey(const ValueKey('space-more-BV1space000'))).dx, 420);
  });

  test('lengths read as the official rows do', () {
    expect(SpaceVideoFormat.duration(28), '0:28');
    expect(SpaceVideoFormat.duration(82), '01:22');
    expect(SpaceVideoFormat.duration(1235), '20:35');
    expect(SpaceVideoFormat.duration(6429), '1:47:09');
    expect(SpaceVideoFormat.count(776000), '77.6万');
    expect(SpaceVideoFormat.count(1120), '1120');
  });

  testWidgets('the chips are hidden when there is only 视频', (tester) async {
    await show(tester, space: profile(chips: const [_video]));
    expect(find.byKey(const ValueKey('space-chip-0')), findsNothing);
    expect(tester.getRect(row(0)).top, closeTo(1390 / 3 + 82 / 3, 0.01));
    expect(find.text('最新发布'), findsOneWidget);
  });

  testWidgets('a 合集 chip lists its videos without the sort, and 视频 lists the uploader’s again', (tester) async {
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('space-chip-2')));
    await settle(tester);
    expect(api.calls.last, 'chipVideos mid=$_mid chip=测试合集 next=null');
    expect(find.byKey(const ValueKey('space-sort')), findsNothing);
    expect(row(12), findsNothing, reason: 'the fake chip holds the first 12');
    expect(tester.widget<Semantics>(_chipSemantics('测试合集')).properties.selected, isTrue);

    await tester.tap(find.byKey(const ValueKey('space-chip-0')));
    await settle(tester);
    expect(api.calls.last, 'videos mid=$_mid order=pubdate next=null');
    expect(find.byKey(const ValueKey('space-sort')), findsOneWidget);
  });

  testWidgets('chips without 视频 (only 图文 and 合集) list the uploader’s videos with none chosen', (tester) async {
    await show(tester, space: profile(chips: const [_article, _season]));
    expect(api.calls, ['videos mid=$_mid order=pubdate next=null']);
    expect(find.byKey(const ValueKey('space-chip-1')), findsOneWidget);
    for (final title in ['图文', '测试合集']) {
      expect(tester.widget<Semantics>(_chipSemantics(title)).properties.selected, isFalse, reason: title);
    }
    expect(find.text('测试视频 0'), findsOneWidget);
    expect(find.byKey(const ValueKey('space-sort')), findsOneWidget);
  });

  testWidgets('图文 toasts 暂未开放 and stays unchosen', (tester) async {
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('space-chip-1')));
    await tester.pump();
    expect(find.text('暂未开放'), findsOneWidget);
    expect(api.calls, hasLength(1));
    expect(tester.widget<Semantics>(_chipSemantics('图文')).properties.selected, isFalse);
    expect(tester.widget<Semantics>(_chipSemantics('视频')).properties.selected, isTrue);
    await toastGone(tester);
  });

  testWidgets('the sort toggles to 最多播放 and back, reloading from the top each time', (tester) async {
    api = FakeSpaceApi(videoList: videos(45, plays: [for (var i = 0; i < 45; i++) i * 10]));
    await show(tester);
    expect(find.text('测试视频 0'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('space-sort')));
    await settle(tester);
    expect(find.text('最多播放'), findsOneWidget);
    expect(api.calls.last, 'videos mid=$_mid order=click next=null');
    expect(find.text('测试视频 44'), findsOneWidget, reason: 'the most played first');
    expect(find.text('测试视频 0'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('space-sort')));
    await settle(tester);
    expect(find.text('最新发布'), findsOneWidget);
    expect(api.calls.last, 'videos mid=$_mid order=pubdate next=null');
  });

  testWidgets('播放全部 opens the first video in the order shown', (tester) async {
    api = FakeSpaceApi(videoList: videos(45, plays: [for (var i = 0; i < 45; i++) i * 10]));
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('space-play-all')));
    expect(opened.single.bvid, 'BV1space000');
    expect(opened.single.title, '测试视频 0');

    await tester.tap(find.byKey(const ValueKey('space-sort')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('space-play-all')));
    expect(opened.last.bvid, 'BV1space044');
  });

  testWidgets('播放全部 opens nothing while the first page loads, nor on an empty list', (tester) async {
    final hold = api.holds['videos'] = Completer<void>();
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('space-play-all')));
    await tester.pump();
    expect(opened, isEmpty);
    api.holds.remove('videos');
    hold.complete();
    await settle(tester);

    api = FakeSpaceApi();
    await show(tester);
    expect(find.text(SpaceVideosSliver.endMessage), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('space-play-all')));
    await tester.pump();
    expect(opened, isEmpty);
  });

  testWidgets('every control answers an accessibility press', (tester) async {
    final handle = tester.ensureSemantics();
    api = FakeSpaceApi(videoList: videos(45, plays: [for (var i = 0; i < 45; i++) i * 10]));
    await show(tester);

    tester.semantics.tap(find.semantics.byLabel('排序：最新发布'));
    await settle(tester);
    expect(api.calls.last, 'videos mid=$_mid order=click next=null');

    tester.semantics.tap(find.semantics.byLabel('播放全部'));
    expect(opened.single.bvid, 'BV1space044');
    tester.semantics.tap(find.semantics.byLabel(RegExp('^测试视频 43，')));
    expect(opened.last.bvid, 'BV1space043');

    tester.semantics.tap(find.semantics.byLabel('更多操作').first);
    await settle(tester);
    expect(find.byKey(const ValueKey('space-menu')), findsOneWidget);
    tester.semantics.tap(find.semantics.byLabel('添加至稍后再看'));
    await settle(tester);
    expect(pageApi.calls, ['addToWatchLater aid=9044']);
    await toastGone(tester);

    tester.semantics.tap(find.semantics.byLabel('更多操作').first);
    await settle(tester);
    tester.semantics.tap(find.semantics.byLabel('分享'));
    await settle(tester);
    expect(shared, [Uri.parse('https://www.bilibili.com/video/BV1space044')]);

    tester.semantics.tap(find.semantics.byLabel('测试合集'));
    await settle(tester);
    expect(api.calls.last, 'chipVideos mid=$_mid chip=测试合集 next=null');
    tester.semantics.tap(find.semantics.byLabel('视频'));
    await settle(tester);
    expect(api.calls.last, 'videos mid=$_mid order=click next=null');

    api.failures['videos'] = const BiliHTTPError(500);
    tester.semantics.tap(find.semantics.byLabel('排序：最多播放'));
    await settle(tester);
    expect(find.byKey(const ValueKey('space-videos-retry')), findsOneWidget);
    api.failures.remove('videos');
    tester.semantics.tap(find.semantics.byLabel('重试'));
    await settle(tester);
    expect(api.calls.last, 'videos mid=$_mid order=pubdate next=null');
    expect(find.text('测试视频 0'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a row opens its video', (tester) async {
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('space-video-BV1space001')));
    expect(opened.single.bvid, 'BV1space001');
    expect(opened.single.title, '测试视频 1');
    expect(opened.single.cover, isNull, reason: 'an empty cover flies nothing');
  });

  group('⋮', () {
    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('space-more-BV1space000')));
      await settle(tester);
      expect(find.byKey(const ValueKey('space-menu')), findsOneWidget);
      expect(find.text('添加至稍后再看'), findsOneWidget);
      expect(find.text('分享'), findsOneWidget);
    }

    testWidgets('the popover hangs under the dots, its arrow at their centre', (tester) async {
      await show(tester);
      final dots = tester.getCenter(find.byKey(const ValueKey('space-more-BV1space000')));
      await openMenu(tester);
      final menu = tester.getRect(find.byKey(const ValueKey('space-menu')));
      expect(menu.top, dots.dy + 16);
      expect(menu.right, 435);
      expect(menu.size, const Size(200, 104));
      expect(
        tester.widget<SpaceVideoMenu>(find.byType(SpaceVideoMenu)).arrowX,
        closeTo(dots.dx + SpaceVideosTheme.menuArrowShift - menu.left, 0.01),
      );
    });

    testWidgets('near the bottom it opens above the dots', (tester) async {
      await show(tester);
      final dots = tester.getCenter(find.byKey(const ValueKey('space-more-BV1space003')));
      expect(dots.dy, greaterThan(956 - 34 - 16 - 104));
      await tester.tap(find.byKey(const ValueKey('space-more-BV1space003')));
      await settle(tester);
      final menu = tester.getRect(find.byKey(const ValueKey('space-menu')));
      expect(menu.bottom, dots.dy - 16);
      expect(tester.widget<SpaceVideoMenu>(find.byType(SpaceVideoMenu)).below, isFalse);
    });

    testWidgets('a tap on the dim closes it and does nothing', (tester) async {
      await show(tester);
      await openMenu(tester);
      await tester.tapAt(const Offset(40, 120));
      await settle(tester);
      expect(find.byKey(const ValueKey('space-menu')), findsNothing);
      expect(pageApi.calls, isEmpty);
      expect(shared, isEmpty);
    });

    testWidgets('添加至稍后再看 adds it and toasts', (tester) async {
      await show(tester);
      await openMenu(tester);
      await tester.tap(find.byKey(const ValueKey('space-menu-watch-later')));
      await settle(tester);
      expect(find.byKey(const ValueKey('space-menu')), findsNothing);
      expect(pageApi.calls, ['addToWatchLater aid=9000']);
      expect(find.text('已添加至稍后再看'), findsOneWidget);
      await toastGone(tester);
    });

    testWidgets('logged out, 添加至稍后再看 opens the login page and adds nothing', (tester) async {
      await show(tester, loggedIn: false);
      await openMenu(tester);
      await tester.tap(find.byKey(const ValueKey('space-menu-watch-later')));
      await settle(tester);
      expect(gate.requests, 1);
      expect(pageApi.calls, isEmpty);
    });

    testWidgets('a failed 添加至稍后再看 says why, and a lapsed login opens the login page', (tester) async {
      pageApi.failures['addToWatchLater'] = const BiliAPIError(code: 90001, message: '稍后再看已满');
      await show(tester);
      await openMenu(tester);
      await tester.tap(find.byKey(const ValueKey('space-menu-watch-later')));
      await settle(tester);
      expect(find.text('稍后再看已满'), findsOneWidget);
      await toastGone(tester);

      pageApi.failures['addToWatchLater'] = const BiliAPIError(code: -101, message: '账号未登录');
      await openMenu(tester);
      await tester.tap(find.byKey(const ValueKey('space-menu-watch-later')));
      await settle(tester);
      expect(gate.requests, 1);
    });

    testWidgets('a 添加至稍后再看 that fails after the page is gone is still logged, by its code only', (tester) async {
      final sink = MemorySink();
      Logger.shared.add(sink);
      addTearDown(() => Logger.shared.remove(sink));
      pageApi.failures['addToWatchLater'] = const BiliAPIError(code: 90001, message: '稍后再看已满');
      final hold = pageApi.holds['addToWatchLater'] = Completer<void>();
      await show(tester);
      await openMenu(tester);
      await tester.tap(find.byKey(const ValueKey('space-menu-watch-later')));
      await settle(tester);
      expect(pageApi.calls, ['addToWatchLater aid=9000']);

      await tester.pumpWidget(const SizedBox.shrink());
      hold.complete();
      await tester.pump();
      final logged = sink.events.singleWhere((event) => event.msg == 'space watch later failed');
      expect('${logged.f['error']}', contains('api 90001'));
      expect('${logged.f}', isNot(contains('稍后再看已满')));
      expect(find.text('稍后再看已满'), findsNothing);
    });

    testWidgets('分享 shares the video’s link, logged in or out', (tester) async {
      await show(tester, loggedIn: false);
      await openMenu(tester);
      await tester.tap(find.byKey(const ValueKey('space-menu-share')));
      await settle(tester);
      expect(shared, [Uri.parse('https://www.bilibili.com/video/BV1space000')]);
      expect(gate.requests, 0);
    });

    testWidgets('a share sheet that fails says so', (tester) async {
      await show(tester, share: (link) async => throw StateError('no sheet'));
      await openMenu(tester);
      await tester.tap(find.byKey(const ValueKey('space-menu-share')));
      await settle(tester);
      expect(find.text('分享失败'), findsOneWidget);
      await toastGone(tester);
    });
  });

  group('paging', () {
    testWidgets('the first load shows the loading TV, and the next page comes as the end nears, one call at a time', (
      tester,
    ) async {
      api.holds['videos'] = Completer<void>();
      await show(tester);
      expect(find.byKey(const ValueKey('space-videos-loading')), findsOneWidget);
      api.holds.remove('videos')!.complete();
      await settle(tester);
      expect(find.byKey(const ValueKey('space-videos-loading')), findsNothing);
      expect(api.calls, hasLength(1));

      final hold = api.holds['videos'] = Completer<void>();
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await settle(tester);
      expect(api.calls, ['videos mid=$_mid order=pubdate next=null', 'videos mid=$_mid order=pubdate next=20']);
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);

      scroll.jumpTo(scroll.position.maxScrollExtent - 10);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await settle(tester);
      expect(api.calls, hasLength(2), reason: 'the page is still out');

      api.holds.remove('videos');
      hold.complete();
      await settle(tester);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await settle(tester);
      expect(api.calls.last, 'videos mid=$_mid order=pubdate next=40');
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await settle(tester);
      expect(find.text(SpaceVideosSliver.endMessage), findsOneWidget);
      expect(find.text('测试视频 44'), findsOneWidget);
      expect(api.calls, hasLength(3), reason: 'the end asks for nothing more');
    });

    testWidgets('a page that adds no rows ends the list', (tester) async {
      final scripted = _ScriptedSpaceApi(
        (next) => SpaceVideoPage(items: videos(20), hasMore: true, next: '${(int.tryParse(next ?? '') ?? 0) + 20}'),
      );
      await show(tester, spaceApi: scripted);
      for (var i = 0; i < 4; i++) {
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await settle(tester);
      }
      expect(scripted.calls, [null, '20']);
      expect(find.text(SpaceVideosSliver.endMessage), findsOneWidget);
    });

    testWidgets('a short list asks for the next page without a scroll, and an empty one ends at once', (tester) async {
      api = FakeSpaceApi(videoList: videos(6), pageSize: 3);
      await show(tester);
      expect(api.calls, hasLength(2));
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await settle(tester);
      expect(find.text(SpaceVideosSliver.endMessage), findsOneWidget);

      api = FakeSpaceApi();
      await show(tester);
      expect(api.calls, hasLength(1));
      expect(find.text(SpaceVideosSliver.endMessage), findsOneWidget);
    });

    testWidgets('a failed first page offers 重试, which loads it', (tester) async {
      api.failures['videos'] = const BiliHTTPError(500);
      await show(tester);
      expect(find.byKey(const ValueKey('space-videos-error')), findsOneWidget);
      expect(api.calls, hasLength(1));
      api.failures.remove('videos');
      await tester.tap(find.byKey(const ValueKey('space-videos-retry')));
      await settle(tester);
      expect(api.calls, hasLength(2));
      expect(find.text('测试视频 0'), findsOneWidget);
    });

    testWidgets('a failed later page offers 重试 under the rows and asks nothing more until it is tapped', (
      tester,
    ) async {
      await show(tester);
      api.failures['videos'] = const BiliHTTPError(500);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await settle(tester);
      expect(api.calls, hasLength(2));
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await settle(tester);
      expect(api.calls, hasLength(2));
      expect(find.byKey(const ValueKey('space-videos-retry')), findsOneWidget);

      api.failures.remove('videos');
      await tester.tap(find.byKey(const ValueKey('space-videos-retry')));
      await settle(tester);
      expect(api.calls.last, 'videos mid=$_mid order=pubdate next=20');
      expect(find.byKey(const ValueKey('space-videos-retry')), findsNothing);
    });

    testWidgets('a chip or sort change waits for the call out, drops its answer, then asks for the new list', (
      tester,
    ) async {
      api = FakeSpaceApi(videoList: videos(45, plays: [for (var i = 0; i < 45; i++) i * 10]));
      final hold = api.holds['videos'] = Completer<void>();
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('space-chip-2')));
      await settle(tester);
      expect(api.calls, hasLength(1), reason: 'the first page is still out');
      expect(find.byKey(const ValueKey('space-videos-loading')), findsOneWidget);
      api.holds.remove('videos');
      hold.complete();
      await settle(tester);
      expect(api.calls, ['videos mid=$_mid order=pubdate next=null', 'chipVideos mid=$_mid chip=测试合集 next=null']);
      expect(row(0), findsOneWidget);
      expect(row(12), findsNothing);
      expect(tester.widget<Semantics>(_chipSemantics('测试合集')).properties.selected, isTrue);
      expect(find.byKey(const ValueKey('space-sort')), findsNothing);

      // The same for the sort: 最多播放's answer, late after the toggle back, is not shown under 最新发布.
      await tester.tap(find.byKey(const ValueKey('space-chip-0')));
      await settle(tester);
      final late = api.holds['videos'] = Completer<void>();
      await tester.tap(find.byKey(const ValueKey('space-sort')));
      await tester.pump();
      expect(api.calls.last, 'videos mid=$_mid order=click next=null');
      await tester.tap(find.byKey(const ValueKey('space-sort')));
      await settle(tester);
      expect(api.calls.last, 'videos mid=$_mid order=click next=null', reason: '最多播放 is still out');
      api.holds.remove('videos');
      late.complete();
      await settle(tester);
      expect(api.calls.last, 'videos mid=$_mid order=pubdate next=null');
      expect(find.text('最新发布'), findsOneWidget);
      expect(find.text('测试视频 0'), findsOneWidget);
      expect(find.text('测试视频 44'), findsNothing);
    });

    testWidgets('quick chip and sort taps while a call is out put one more call out, for the last choice', (
      tester,
    ) async {
      api = FakeSpaceApi(videoList: videos(45, plays: [for (var i = 0; i < 45; i++) i * 10]));
      final hold = api.holds['videos'] = Completer<void>();
      await show(tester);
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byKey(const ValueKey('space-sort')));
        await tester.pump();
      }
      await tester.tap(find.byKey(const ValueKey('space-chip-2')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('space-chip-0')));
      await tester.pump();
      expect(api.calls, hasLength(1));
      expect(find.text('最多播放'), findsOneWidget);

      api.holds.remove('videos');
      hold.complete();
      await settle(tester);
      expect(api.calls, ['videos mid=$_mid order=pubdate next=null', 'videos mid=$_mid order=click next=null']);
      expect(find.text('测试视频 44'), findsOneWidget, reason: 'the most played first');
      expect(find.text('测试视频 0'), findsNothing);
      expect(tester.widget<Semantics>(_chipSemantics('视频')).properties.selected, isTrue);
    });

    testWidgets('the sort toggled while the next page is out drops that page, then lists the new order from the top', (
      tester,
    ) async {
      api = FakeSpaceApi(videoList: videos(45, plays: [for (var i = 0; i < 45; i++) i * 10]));
      await show(tester);
      final twentyRows = scroll.position.maxScrollExtent;
      final hold = api.holds['videos'] = Completer<void>();
      scroll.jumpTo(twentyRows);
      await settle(tester);
      expect(api.calls.last, 'videos mid=$_mid order=pubdate next=20');

      scroll.jumpTo(0);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('space-sort')));
      await settle(tester);
      expect(api.calls, hasLength(2));
      api.holds.remove('videos');
      hold.complete();
      await settle(tester);
      expect(api.calls.last, 'videos mid=$_mid order=click next=null');
      expect(row(44), findsOneWidget);
      expect(scroll.position.maxScrollExtent, twentyRows, reason: "最新发布's second page isn't added");

      scroll.jumpTo(scroll.position.maxScrollExtent);
      await settle(tester);
      expect(api.calls.last, 'videos mid=$_mid order=click next=20');
      expect(api.calls, hasLength(4));
    });
  });
}

Finder _chipSemantics(String title) =>
    find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == title);
