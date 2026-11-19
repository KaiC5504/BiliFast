import 'package:bili_core/api.dart';
import 'package:bilifast/dynamic/fake_dynamic_api.dart';
import 'package:bilifast/dynamic/follow_tab/follow_parts.dart';
import 'package:bilifast/dynamic/follow_tab/follow_top.dart';
import 'package:bilifast/home/home_tab_bar.dart';
import 'package:bilifast/live/live_entry.dart';
import 'package:bilifast/live/live_routes.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'follow_fixtures.dart';

/// Made up: one live face of its own, and 云舟mimi (102) who is among the faces too.
const _live = [
  DynamicLiveUp(mid: 201, name: '晚星直播', face: '', roomId: 30001),
  DynamicLiveUp(mid: 102, name: '云舟mimi', face: '', roomId: 30002),
];

/// 关注's top on its own at 1×, its top at the screen's.
class _Top {
  final opened = <DynamicUp>[];
  final rooms = <LiveRoomEntry>[];
  int more = 0;

  Future<void> show(
    WidgetTester tester, {
    List<DynamicUp> ups = faces,
    List<DynamicLiveUp> live = _live,
    DynamicFeedType type = DynamicFeedType.all,
  }) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    FollowFacesRow.openRoom = (context, entry) async => rooms.add(entry);
    addTearDown(() => FollowFacesRow.openRoom = openLiveRoom);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 440,
            child: FollowTop(
              type: type,
              ups: ups,
              liveUps: live,
              dot: (up) => up.hasUpdate,
              onSelect: (_) {},
              onOpenFace: opened.add,
              onMore: () => more++,
              onNearEnd: () {},
              facesController: controller,
              facesKey: GlobalKey(),
            ),
          ),
        ),
      ),
    );
  }
}

Rect _faceOf(WidgetTester tester, String key) =>
    tester.getRect(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(ClipOval)));

void main() {
  testWidgets('the live faces lead in their order, then the line, then the faces without anyone already led', (
    tester,
  ) async {
    await _Top().show(tester);
    // The faces' centres sit 82 + 26 down; live ones keep the 74 pt pitch, and the line adds 16 before the rest.
    expect(_faceOf(tester, 'follow-live-201'), Rect.fromCenter(center: const Offset(45, 108), width: 52, height: 52));
    expect(_faceOf(tester, 'follow-live-102'), Rect.fromCenter(center: const Offset(119, 108), width: 52, height: 52));
    expect(
      tester.getRect(find.byKey(const ValueKey('follow-live-rule'))),
      Rect.fromCenter(center: const Offset(163.5, 108), width: 1, height: 24),
    );
    expect(find.byKey(const ValueKey('follow-face-102'), skipOffstage: false), findsNothing, reason: 'shown once');
    for (final (i, mid) in [101, 103, 104].indexed) {
      expect(
        _faceOf(tester, 'follow-face-$mid'),
        Rect.fromCenter(center: Offset(209 + 74.0 * i, 108), width: 52, height: 52),
        reason: '$mid',
      );
    }
    expect(FollowFacesRow.shown(faces, _live).map((up) => up.mid), [101, 103, 104]);
  });

  testWidgets('a live face: the 56 pt ring, the pill 21 under its centre with the bars and 直播中, and no dot', (
    tester,
  ) async {
    await _Top().show(tester);
    final pill = tester.getRect(find.byKey(const ValueKey('follow-live-pill-102')));
    expect(pill, Rect.fromCenter(center: const Offset(119, 108 + 21), width: 54, height: 18));
    final bars = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('follow-live-102')),
        matching: find.image(const AssetImage('assets/images/live/live_ing.gif')),
      ),
    );
    expect(bars, Rect.fromLTWH(119 - 26 + 2, 108 + 21 - 8 + 1, 16, 16));
    final words = find.descendant(of: find.byKey(const ValueKey('follow-live-102')), matching: find.text('直播中'));
    expect(tester.getRect(words).left, 119 - 26 + 18);
    final rings = [
      for (final box in tester.widgetList<DecoratedBox>(
        find.descendant(of: find.byKey(const ValueKey('follow-live-102')), matching: find.byType(DecoratedBox)),
      ))
        if (box.decoration case ShapeDecoration(shape: CircleBorder(:final side)) when side.color == BiliColors.pink)
          side.width,
    ];
    expect(rings, [DynamicFeedTheme.liveRingStroke]);
    expect(
      find.descendant(of: find.byKey(const ValueKey('follow-live-102')), matching: find.text('云舟mimi')),
      findsOneWidget,
    );
    // 102 has news among the faces; led as live it shows none.
    expect(find.byKey(const ValueKey('follow-dot-102'), skipOffstage: false), findsNothing);
    expect(find.byKey(const ValueKey('follow-dot-101')), findsOneWidget);
  });

  testWidgets('the title reads N人直播中 · 更多 ›, 更多 where it was; one tap opens 我的关注 as before', (tester) async {
    final top = _Top();
    await top.show(tester, live: const []);
    final more = tester.getRect(find.text('更多'));
    expect(find.byKey(const ValueKey('follow-faces-live-count')), findsNothing);
    expect(find.textContaining('直播中'), findsNothing);

    await top.show(tester);
    expect(tester.getRect(find.text('更多')), more);
    final lead = tester.getRect(find.byKey(const ValueKey('follow-faces-live-count')));
    expect(find.text('2人直播中'), findsOneWidget);
    expect(lead.right, closeTo(more.left - DynamicFeedTheme.liveLeadGap, 0.01));
    final dot = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('follow-faces-more')),
        matching: find.byWidgetPredicate(
          (widget) => widget is SizedBox && widget.width == DynamicFeedTheme.liveLeadDot,
        ),
      ),
    );
    expect(dot.center.dx, closeTo(more.left - DynamicFeedTheme.liveLeadGap / 2, 0.01));
    expect(dot.center.dy, closeTo(more.center.dy, 0.01));

    await tester.tap(find.text('2人直播中'));
    await tester.tap(find.text('更多'));
    expect(top.more, 2);

    await top.show(tester, live: _live.take(1).toList());
    expect(find.text('1人直播中'), findsOneWidget);
  });

  testWidgets('视频 keeps its title bare, live or not', (tester) async {
    await _Top().show(tester, type: DynamicFeedType.video);
    expect(find.byKey(const ValueKey('follow-faces-more')), findsNothing);
    expect(find.textContaining('人直播中'), findsNothing);
    expect(find.byKey(const ValueKey('follow-live-201')), findsOneWidget);
  });

  testWidgets('a live face opens its room; one without a room id opens as any face does', (tester) async {
    final top = _Top();
    await top.show(
      tester,
      live: const [
        DynamicLiveUp(mid: 201, name: '晚星直播', face: 'https://i0.hdslb.com/bfs/face/fake-201.jpg', roomId: 30001),
        DynamicLiveUp(mid: 202, name: '无房间号', face: ''),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('follow-live-201')));
    expect(
      top.rooms.map((entry) => (entry.roomId, entry.uid, entry.anchorName, entry.anchorFace)),
      [(30001, 201, '晚星直播', 'https://i0.hdslb.com/bfs/face/fake-201.jpg')],
    );
    expect(top.opened, isEmpty);

    await tester.tap(find.byKey(const ValueKey('follow-live-202')));
    expect(top.rooms, hasLength(1));
    expect(top.opened.map((up) => (up.mid, up.name, up.hasUpdate)), [(202, '无房间号', false)]);
  });

  testWidgets('VoiceOver reads each live face with 直播中 and presses it', (tester) async {
    final handle = tester.ensureSemantics();
    final top = _Top();
    await top.show(tester);
    expect(find.semantics.byLabel('晚星直播，直播中'), findsOne);
    expect(find.semantics.byLabel('云舟mimi，直播中'), findsOne);
    expect(find.semantics.byLabel('2人直播中 · 更多'), findsOne);
    tester.semantics.tap(find.semantics.byLabel('云舟mimi，直播中'));
    expect(top.rooms.single.roomId, 30002);
    tester.semantics.tap(find.semantics.byLabel('2人直播中 · 更多'));
    expect(top.more, 1);
    handle.dispose();
  });

  testWidgets('with none live the row is as it was: the faces from 45, no line, no lead, clipped to its box', (
    tester,
  ) async {
    await _Top().show(tester, live: const []);
    for (final (i, up) in faces.indexed) {
      expect(
        _faceOf(tester, 'follow-face-${up.mid}'),
        Rect.fromCenter(center: Offset(45 + 74.0 * i, 108), width: 52, height: 52),
      );
    }
    expect(find.byKey(const ValueKey('follow-live-rule')), findsNothing);
    expect(find.byType(FollowLiveFace), findsNothing);
    expect(tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView)).clipBehavior, Clip.hardEdge);
  });

  testWidgets('live faces alone still show the section, with no line after them', (tester) async {
    await _Top().show(tester, ups: const []);
    expect(find.text('最常访问'), findsOneWidget);
    expect(find.byKey(const ValueKey('follow-live-201')), findsOneWidget);
    expect(find.byKey(const ValueKey('follow-live-rule')), findsNothing);
    expect(tester.getSize(find.byType(FollowTop)).height, DynamicFeedTheme.top);
  });

  group('on 关注', () {
    setUp(() => FollowPosts.cardOverride = (item, inline) => SizedBox(height: 300, child: Text('post ${item.id}')));
    tearDown(() => FollowPosts.cardOverride = null);

    testWidgets("the portal's live faces lead the row; one without a room opens the face sheet", (tester) async {
      await showShell(
        tester,
        api: FakeDynamicApi(
          posts: posts(3, mid: 202),
          upList: faces,
          liveUps: const [
            DynamicLiveUp(mid: 201, name: '晚星直播', face: '', roomId: 30001),
            DynamicLiveUp(mid: 202, name: '无房间号', face: ''),
          ],
        ),
      );
      await tester.tap(find.byKey(ValueKey('home-tab-${HomeTab.follow.name}')));
      await settle(tester);
      expect(find.text('2人直播中'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('follow-live-202'))).dx,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('follow-face-101'))).dx),
      );

      await tester.tap(find.byKey(const ValueKey('follow-live-202')));
      await settle(tester, 20);
      expect(find.byKey(const ValueKey('face-sheet')), findsOneWidget);
      expect(find.text('无房间号的动态'), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const ValueKey('face-sheet')), matching: find.text('post p0')),
        findsOneWidget,
      );
    });

    test('the --fake-account demo answers two live faces with the first page of faces', () async {
      final list = await FakeDynamicApi.demo().ups();
      expect(list.liveUps, hasLength(2));
      expect(list.liveUps.every((up) => up.roomId > 0), isTrue);
      expect(await FakeDynamicApi.demo().ups(offset: 'u1').then((page) => page.liveUps), isEmpty);
      expect(await FakeDynamicApi().ups().then((page) => page.liveUps), isEmpty);
    });
  });
}
