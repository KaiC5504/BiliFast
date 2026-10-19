import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/history/watch_history_page.dart';
import 'package:bilifast/home/avatar_page.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/settings/settings_page.dart';
import 'package:bilifast/video/video_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/fake_player.dart';
import 'fake_login_gate.dart';

/// 2026-10-19 21:00 local.
final _now = DateTime(2026, 10, 19, 21);

RecentVideo _video(int index, {int duration = 0, String? cover}) => RecentVideo(
  bvid: 'BV1v$index',
  cid: index,
  title: '视频 $index',
  part: '',
  page: 1,
  pageCount: 1,
  duration: duration,
  cover: cover,
);

void main() {
  late RecentStore recents;
  late PlaybackController controller;
  late FakeLoginGate gate;
  var clock = _now;

  Future<void> show(WidgetTester tester, {List<RecentVideo> opened = const []}) async {
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    final logger = Logger(session: 'test');
    final http = Canned.http();
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: http,
      logger: logger,
    );
    await environment.refreshAccount();
    recents = await RecentStore.load(null, logger: logger, now: () => clock);
    for (final video in opened.reversed) {
      recents.add(video);
    }
    clock = _now;
    controller = PlaybackController(
      client: environment.client,
      engine: FakeEngine(),
      player: FakePlayer(),
      clock: ManualClock(10000).clock,
      now: () => _now,
      startTimer: FakeTimers().start,
      logger: logger,
    );
    final playback = AppPlayback(() async => controller);
    addTearDown(playback.dispose);
    gate = FakeLoginGate();
    final services = AppServices(environment: environment, playback: playback, recents: recents, loginGate: gate);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppScope(services: services, child: child!),
        home: const Scaffold(body: Center(child: Text('首页'))),
      ),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    final pushed = navigator.push(MaterialPageRoute<void>(builder: (_) => const AvatarPage()));
    pushed.ignore();
    await settle(tester);
  }

  setUp(() => clock = _now);

  testWidgets('the bar, 最近 and the four shortcuts sit where 49 has them', (tester) async {
    await show(tester);
    Rect rect(String key) => tester.getRect(find.byKey(ValueKey(key)));
    expect(rect('avatar-back').center.dy, closeTo(84, 0.5));
    expect(rect('avatar-settings').center, offsetMoreOrLessEquals(const Offset(416, 84), epsilon: 0.5));
    expect(tester.getCenter(find.text('最近')).dx, closeTo(132.3, 0.5));
    final shortcuts = ['avatar-offline', 'avatar-history', 'avatar-favourites', 'avatar-later'];
    for (final (index, key) in shortcuts.indexed) {
      expect(rect(key).center.dx, closeTo(55 + 110 * index, 0.5), reason: key);
    }
    for (final label in ['离线缓存', '历史记录', '我的收藏', '稍后再看']) {
      expect(tester.getCenter(find.text(label)).dy, closeTo(168.2, 1), reason: label);
    }
    expect(find.text('看视频'), findsNothing);
    expect(find.text('听视频'), findsNothing);
    expect(find.text('开发者'), findsNothing);
    expect(find.text('登录'), findsNothing);
  });

  testWidgets('up to five recents in 49\'s rows: cover, duration, title, when, and ✕', (tester) async {
    clock = _now.subtract(const Duration(hours: 2));
    await show(tester, opened: [for (var i = 0; i < 7; i++) _video(i, duration: i == 0 ? 81593 : 133)]);
    expect(find.text('最近在看的视频'), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      expect(find.text('视频 $i'), findsOneWidget);
    }
    expect(find.text('视频 5'), findsNothing, reason: 'five at most');
    expect(find.text('22:39:53'), findsOneWidget);
    expect(find.text('2:13'), findsNWidgets(4));
    expect(find.text('2小时前播放'), findsNWidgets(5));
    final first = find.byKey(const ValueKey('avatar-recent-BV1v0#0'));
    final second = find.byKey(const ValueKey('avatar-recent-BV1v1#1'));
    expect(tester.getTopLeft(first).dy + 14, closeTo(252, 0.5), reason: "the first cover's top on 49");
    expect(tester.getTopLeft(second).dy - tester.getTopLeft(first).dy, 104);
    expect(
      tester.getCenter(find.byKey(const ValueKey('avatar-remove-BV1v0#0'))),
      offsetMoreOrLessEquals(const Offset(420, 322), epsilon: 0.5),
    );
  });

  testWidgets('the pink progress line runs along the cover as far as the part was watched', (tester) async {
    await show(tester, opened: [_video(0, duration: 100), _video(1, duration: 100)]);
    recents.recordProgress(bvid: 'BV1v0', cid: 0, seconds: 25);
    await settle(tester);
    final line = find.byKey(const ValueKey('avatar-recent-progress'));
    expect(line, findsOneWidget, reason: 'only the part with progress');
    expect(tester.getSize(line), const Size(34, 2));
  });

  testWidgets('✕ removes that one recent, from the page and the store', (tester) async {
    await show(tester, opened: [_video(0), _video(1), _video(2)]);
    await tester.tap(find.byKey(const ValueKey('avatar-remove-BV1v1#1')));
    await settle(tester);
    expect(find.text('视频 1'), findsNothing);
    expect([for (final item in recents.items) item.bvid], ['BV1v0', 'BV1v2']);
  });

  testWidgets('with nothing opened yet the card says so', (tester) async {
    await show(tester);
    expect(find.text('还没有打开过视频'), findsOneWidget);
  });

  testWidgets('a row opens its video', (tester) async {
    await show(tester, opened: [_video(0)]);
    await tester.tap(find.byKey(const ValueKey('avatar-recent-BV1v0#0')));
    await settle(tester, 20);
    final route = tester.widget<VideoPage>(find.byType(VideoPage)).route;
    expect(route.bvid, 'BV1v0');
    expect(route.cid, 0);
  });

  testWidgets('全部 opens 最近打开', (tester) async {
    await show(tester, opened: [_video(0)]);
    await tester.tap(find.byKey(const ValueKey('avatar-all')));
    await settle(tester, 20);
    expect(find.text('最近打开'), findsOneWidget);
    expect(find.byKey(const ValueKey('recent-BV1v0#0')), findsOneWidget);
  });

  testWidgets('⚙ opens 设置', (tester) async {
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('avatar-settings')));
    await settle(tester, 20);
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-font')), findsOneWidget);
  });

  testWidgets('历史记录 opens 历史记录; the other shortcuts say 即将推出', (tester) async {
    await show(tester);
    for (final key in ['avatar-offline', 'avatar-favourites', 'avatar-later']) {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pump();
      expect(find.text('即将推出'), findsOneWidget, reason: key);
      await settle(tester, 60);
    }
    expect(find.byType(WatchHistoryPage), findsNothing);
    await tester.tap(find.byKey(const ValueKey('avatar-history')));
    await settle(tester, 20);
    expect(find.byType(WatchHistoryPage), findsOneWidget);
    expect(gate.requests, 0);
  });

  testWidgets('back returns to where the page was opened from', (tester) async {
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('avatar-back')));
    await settle(tester, 20);
    expect(find.byType(AvatarPage), findsNothing);
    expect(find.text('首页'), findsOneWidget);
  });

  testWidgets('every control is a button VoiceOver can press', (tester) async {
    final semantics = tester.ensureSemantics();
    await show(tester, opened: [_video(0)]);
    for (final label in ['返回', '设置', '离线缓存', '历史记录', '我的收藏', '稍后再看', '全部', '视频 0', '移除']) {
      final nodes = find.semantics.byLabel(label).evaluate();
      expect(nodes, hasLength(1), reason: label);
      expect(nodes.single.getSemanticsData().hasAction(SemanticsAction.tap), isTrue, reason: label);
    }
    semantics.dispose();
  });
}

Future<void> settle(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
