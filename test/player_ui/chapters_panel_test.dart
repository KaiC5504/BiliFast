import 'package:bili_core/api.dart' show Chapter, VideoPage;
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/player_ui/chrome_state.dart';
import 'package:bilifast/player_ui/panels/chapters_panel.dart';
import 'package:bilifast/player_ui/panels/panel_controller.dart';
import 'package:bilifast/player_ui/panels/panel_layer.dart';
import 'package:bilifast/player_ui/player_ui.dart';
import 'package:bilifast/shared/cover_placeholder.dart';
import 'package:bilifast/shared/remote_image.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/intro/collection_row.dart' show PlayingBars;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player_session.dart';

const _screen = Size(956, 440);

const _chapters = [
  Chapter(from: 0, to: 108, title: '1', image: 'https://i0.hdslb.com/bfs/vchapter/one.jpg'),
  Chapter(from: 108, to: 241, title: '2.3'),
  Chapter(from: 241, to: 3725, title: '尾声'),
];

const _part = VideoPage(cid: 1, page: 1, part: 'P1', duration: 3725);

final class _Rig {
  _Rig(this.session, this.ui);

  final FakePlayerSession session;
  final PlayerUi ui;

  PanelController get panels => ui.panels;
}

/// The layer in landscape full screen on KaiC's iPhone (its 62 pt sides and 21 pt home indicator), at 1×. Unsettled,
/// it pumps through the slide in, for moving bars that no pumpAndSettle outlasts.
Future<_Rig> _pump(
  WidgetTester tester, {
  List<Chapter> chapters = _chapters,
  double at = 150,
  bool settle = true,
}) async {
  tester.view
    ..physicalSize = _screen
    ..devicePixelRatio = 1
    ..padding = const FakeViewPadding(left: 62, right: 62, bottom: 21)
    ..viewPadding = const FakeViewPadding(left: 62, right: 62, bottom: 21);
  addTearDown(tester.view.reset);
  final session = FakePlayerSession()
    ..chapters = chapters
    ..part = _part;
  session.scrubbing.value = at;
  final orientation = OrientationController()..enterLandscape();
  final chrome = ChromeState();
  final panels = PanelController();
  final ui = PlayerUi(
    session: session,
    chrome: chrome,
    panels: panels,
    orientation: orientation,
    device: NoDeviceControls(),
    onBack: () {},
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: BiliColors.videoBackground)),
          Positioned.fill(child: PanelLayer(ui: ui)),
        ],
      ),
    ),
  );
  addTearDown(() {
    chrome.dispose();
    panels.dispose();
    orientation.dispose();
    session.dispose();
  });
  panels.open(PlayerPanel.chapters);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }
  return _Rig(session, ui);
}

Finder get _frame => find.byKey(const ValueKey('panel-frame'));

Finder get _switch => find.byKey(const ValueKey('chapter-bar-switch'));

Color? _colour(WidgetTester tester, String text) => tester
    .widget<RichText>(find.descendant(of: find.text(text), matching: find.byType(RichText)).first)
    .text
    .style
    ?.color;

/// The switch's track: pink while 章节进度条 is on.
Color? _track(WidgetTester tester) {
  final track = find.descendant(of: _switch, matching: find.byType(AnimatedContainer));
  return (tester.widget<AnimatedContainer>(track).decoration! as BoxDecoration).color;
}

Finder _rowOf(String title) => find.ancestor(of: find.text(title), matching: find.byType(GestureDetector)).first;

void main() {
  testWidgets("a hard-edged strip 382 of 956 pt at the right, in 273's shade", (tester) async {
    await _pump(tester);
    expect(tester.getTopLeft(_frame), const Offset(574, 0));
    expect(tester.getBottomRight(_frame), Offset(_screen.width, _screen.height));
    final shade = tester.widgetList<ColoredBox>(find.byType(ColoredBox)).map((box) => box.color);
    expect(shade, contains(ChapterPanelTheme.shade));
    expect(PanelFrame.of(PlayerPanel.chapters).edge, isTrue);
  });

  testWidgets('a row per chapter: its frame, title and range, 92 apart under the header', (tester) async {
    await _pump(tester);
    expect(find.text('章节'), findsOneWidget);
    expect(find.text('章节进度条'), findsOneWidget);
    for (final range in ['00:00 - 01:48', '01:48 - 04:01', '04:01 - 1:02:05']) {
      expect(find.text(range), findsOneWidget, reason: range);
    }
    expect(_colour(tester, '00:00 - 01:48'), BiliColors.panelSecondary);
    expect(tester.getCenter(find.text('章节')).dy, closeTo(ChapterPanelTheme.headerCentre, 0.01));
    expect(tester.getTopLeft(find.text('章节')).dx, 574 + ChapterPanelTheme.lead);

    final frames = find.byType(ClipRRect);
    expect(frames, findsNWidgets(3));
    final rects = [for (var i = 0; i < 3; i++) tester.getRect(frames.at(i))];
    expect(rects.first, const Rect.fromLTWH(586, 57, 128, 72));
    expect(rects[1].top - rects[0].top, 92);
    expect(rects[2].top - rects[1].top, 92);
    expect(tester.widget<ClipRRect>(frames.first).borderRadius, BorderRadius.circular(ChapterPanelTheme.frameRadius));
    // The text starts 10 after the frame.
    expect(tester.getTopLeft(find.text('00:00 - 01:48')).dx, 724);

    // The frame's picture, or the cover placeholder when the answer has none.
    final images = tester.widgetList<RemoteImage>(find.byType(RemoteImage)).toList();
    expect(images.map((image) => image.url), ['https://i0.hdslb.com/bfs/vchapter/one.jpg', null, null]);
    expect(images.every((image) => image.placeholder is CoverPlaceholder), isTrue);
  });

  testWidgets('a hairline between rows, none over the first, ending at the safe area', (tester) async {
    await _pump(tester);
    final rows = find.descendant(of: _frame, matching: find.byType(Container));
    final borders = [
      for (final container in tester.widgetList<Container>(rows))
        if (container.decoration case BoxDecoration(:final Border border)) border.top,
    ];
    expect(borders, hasLength(2));
    expect(borders.first.color, BiliColors.panelHairline);
    expect(borders.first.width, BiliMetrics.panelHairline);
    final second = tester.getRect(find.descendant(of: _rowOf('2.3'), matching: find.byType(DecoratedBox)).first);
    expect(second.top, closeTo(57 + 72 + ChapterPanelTheme.rowBottom, 0.01));
    expect(second.left, 586);
    expect(second.right, _screen.width - 62);
  });

  testWidgets('the playing chapter is pink after the moving bars, and the mark follows the playhead', (tester) async {
    final rig = await _pump(tester);
    expect(_colour(tester, '2.3'), ChapterPanelTheme.playing);
    expect(_colour(tester, '1'), BiliColors.panelText);
    expect(_colour(tester, '尾声'), BiliColors.panelText);
    final bars = find.byType(PlayingBars);
    expect(bars, findsOneWidget);
    expect(find.descendant(of: _rowOf('2.3'), matching: bars), findsOneWidget);
    expect(tester.widget<PlayingBars>(bars).color, const Color(0xFFFB7299));
    expect(tester.widget<PlayingBars>(bars).height, ChapterPanelTheme.barsHeight);
    // Before the title, a point above its middle.
    expect(tester.getRect(bars).right, lessThan(tester.getTopLeft(find.text('2.3')).dx));
    expect(
      tester.getCenter(bars).dy,
      closeTo(
        tester.getCenter(find.text('2.3')).dy + ChapterPanelTheme.barsCentre - ChapterPanelTheme.rowTitleCentre,
        0.01,
      ),
    );

    rig.session.scrubbing.value = 3000;
    await tester.pump();
    expect(_colour(tester, '尾声'), ChapterPanelTheme.playing);
    expect(_colour(tester, '2.3'), BiliColors.panelText);
    expect(find.descendant(of: _rowOf('尾声'), matching: bars), findsOneWidget);

    rig.session.scrubbing.value = 0;
    await tester.pump();
    expect(_colour(tester, '1'), ChapterPanelTheme.playing);
  });

  testWidgets('the moving bars repaint their own layer: nothing else in the panel, nor the page under it, builds or '
      'paints per frame', (tester) async {
    PlayingBars.debugHoldStill = false;
    await _pump(tester, settle: false);
    final boundary = find.byKey(const ValueKey('chapter-bars'));
    expect(tester.widget(boundary), isA<RepaintBoundary>());
    expect(find.descendant(of: _rowOf('2.3'), matching: boundary), findsOneWidget);
    expect(find.descendant(of: boundary, matching: find.byType(PlayingBars)), findsOneWidget);
    final bars = tester.element(boundary);
    final barsBox = tester.renderObject(boundary);
    final layer = tester.renderObject(find.byType(PanelLayer));
    final panel = tester.renderObject(find.byType(ChaptersPanel));

    final built = <Element>[];
    final painted = <RenderObject>[];
    debugOnRebuildDirtyWidget = (element, _) => built.add(element);
    debugOnProfilePaint = painted.add;
    try {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 34));
      }
    } finally {
      debugOnRebuildDirtyWidget = null;
      debugOnProfilePaint = null;
    }

    bool builtUnder(Element element) {
      var under = false;
      element.visitAncestorElements((ancestor) {
        under = identical(ancestor, bars);
        return !under;
      });
      return under;
    }

    bool paintedUnder(RenderObject object, RenderObject ancestor) {
      for (RenderObject? at = object; at != null; at = at.parent) {
        if (identical(at, ancestor)) return true;
      }
      return false;
    }

    expect(painted.where((object) => paintedUnder(object, barsBox)), isNotEmpty, reason: 'the bars move');
    expect([
      for (final element in built)
        if (!builtUnder(element)) element.widget.runtimeType,
    ], isEmpty);
    expect(
      [
        for (final object in painted)
          if (!paintedUnder(object, layer)) object.runtimeType,
      ],
      isEmpty,
      reason: 'the page under the layer',
    );
    expect(
      [
        for (final object in painted)
          if (paintedUnder(object, panel) && !paintedUnder(object, barsBox)) object.runtimeType,
      ],
      isEmpty,
      reason: "the panel's header and rows",
    );
  });

  test('the chapter holding a second is the last starting at or before it', () {
    expect(ChaptersPanel.playingIndex(_chapters, 0), 0);
    expect(ChaptersPanel.playingIndex(_chapters, 107.9), 0);
    expect(ChaptersPanel.playingIndex(_chapters, 108), 1);
    expect(ChaptersPanel.playingIndex(_chapters, 9999), 2);
    expect(ChaptersPanel.playingIndex(const [Chapter(from: 30, to: 60, title: '')], 10), isNull);
    expect(ChaptersPanel.playingIndex(const [], 10), isNull);
  });

  testWidgets('章节进度条 shows the setting and turns it both ways', (tester) async {
    final rig = await _pump(tester);
    expect(_track(tester), ChapterPanelTheme.switchOn);
    await tester.tap(_switch);
    await tester.pumpAndSettle();
    expect(rig.session.calls, ['setChapterBar false']);
    expect(_track(tester), ChapterPanelTheme.switchOff);
    await tester.tap(find.text('章节进度条'));
    await tester.pumpAndSettle();
    expect(rig.session.calls, ['setChapterBar false', 'setChapterBar true']);
    expect(_track(tester), ChapterPanelTheme.switchOn);
    expect(rig.panels.value, PlayerPanel.chapters);
  });

  testWidgets("the switch is 273's pill, past the safe area, centred on the header", (tester) async {
    await _pump(tester);
    final track = find.descendant(of: _switch, matching: find.byType(AnimatedContainer));
    final rect = tester.getRect(track);
    expect(rect.width, closeTo(ChapterPanelTheme.switchWidth, 0.01));
    expect(rect.height, closeTo(ChapterPanelTheme.switchHeight, 0.01));
    expect(rect.right, closeTo(_screen.width - ChapterPanelTheme.switchRight, 0.01));
    expect(rect.center.dy, closeTo(ChapterPanelTheme.switchCentre, 0.01));
    expect(rect.left - tester.getTopRight(find.text('章节进度条')).dx, closeTo(ChapterPanelTheme.switchGap, 0.01));
    expect(tester.getCenter(find.text('章节进度条')).dy, closeTo(ChapterPanelTheme.headerCentre, 0.01));
    // A touch at least as tall as the system's.
    expect(tester.getSize(_switch).height, greaterThanOrEqualTo(BiliMetrics.panelHitBox));
  });

  // The keyframe before a chapter's start belongs to the chapter before, which would then show as playing.
  testWidgets("a tap on a row seeks exactly to the chapter's start and closes", (tester) async {
    final rig = await _pump(tester);
    await tester.tap(find.text('01:48 - 04:01'));
    await tester.pumpAndSettle();
    expect(rig.session.calls, ['commitSeek 108.0 precise']);
    expect(rig.panels.value, isNull);
  });

  testWidgets('the playing row too seeks exactly to its start', (tester) async {
    final rig = await _pump(tester, at: 200);
    await tester.tap(find.text('2.3'));
    await tester.pumpAndSettle();
    expect(rig.session.calls, ['commitSeek 108.0 precise']);
    expect(rig.panels.value, isNull);
  });

  group('closes when another part plays', () {
    const next = VideoPage(cid: 2, page: 2, part: 'P2', duration: 600);

    for (final (name, theirs) in [
      ('with chapters of its own', _chapters),
      ('whose chapters are still loading', const <Chapter>[]),
    ]) {
      testWidgets('one $name', (tester) async {
        final rig = await _pump(tester);
        rig.session
          ..part = next
          ..chapters = theirs
          ..changed();
        await tester.pumpAndSettle();
        expect(rig.panels.value, isNull);
        expect(_frame, findsNothing);
      });
    }

    testWidgets('also when the session named no part between the two', (tester) async {
      final rig = await _pump(tester);
      rig.session
        ..opening = true
        ..part = null
        ..changed();
      await tester.pumpAndSettle();
      expect(rig.panels.value, PlayerPanel.chapters);
      rig.session
        ..part = next
        ..changed();
      await tester.pumpAndSettle();
      expect(rig.panels.value, isNull);
    });

    testWidgets('but not on an empty list while its own part opens, nor on that part coming back', (tester) async {
      final rig = await _pump(tester);
      rig.session
        ..opening = true
        ..part = null
        ..changed();
      await tester.pumpAndSettle();
      rig.session
        ..part = _part
        ..chapters = const []
        ..changed();
      await tester.pumpAndSettle();
      expect(rig.panels.value, PlayerPanel.chapters);
      rig.session
        ..chapters = _chapters
        ..opening = false
        ..changed();
      await tester.pumpAndSettle();
      expect(rig.panels.value, PlayerPanel.chapters);
      expect(find.text('2.3'), findsOneWidget);
    });

    testWidgets('and when the part settles with no chapters', (tester) async {
      final rig = await _pump(tester);
      rig.session
        ..opening = true
        ..chapters = const []
        ..changed();
      await tester.pumpAndSettle();
      expect(rig.panels.value, PlayerPanel.chapters);
      rig.session
        ..opening = false
        ..changed();
      await tester.pumpAndSettle();
      expect(rig.panels.value, isNull);
    });
  });

  group('the header stays over the list; opened with the playing row out of sight, the list starts at it', () {
    final many = [for (var i = 0; i < 12; i++) Chapter(from: i * 60.0, to: (i + 1) * 60.0, title: '第${i + 1}章')];

    ScrollPosition position(WidgetTester tester) =>
        tester.state<ScrollableState>(find.descendant(of: _frame, matching: find.byType(Scrollable))).position;

    void expectHeader(WidgetTester tester) {
      expect(tester.getCenter(find.text('章节')).dy, closeTo(ChapterPanelTheme.headerCentre, 0.01));
      expect(tester.getCenter(find.text('章节进度条')).dy, closeTo(ChapterPanelTheme.headerCentre, 0.01));
      final track = find.descendant(of: _switch, matching: find.byType(AnimatedContainer));
      expect(tester.getRect(track).center.dy, closeTo(ChapterPanelTheme.switchCentre, 0.01));
    }

    double frameTop(WidgetTester tester, String title) =>
        tester.getTopLeft(find.descendant(of: _rowOf(title), matching: find.byType(ClipRRect))).dy;

    testWidgets('one far down comes to the top, its hairline where the header ends', (tester) async {
      await _pump(tester, chapters: many, at: 5 * 60 + 5);
      expect(position(tester).pixels, greaterThan(0));
      expect(tester.getTopLeft(_rowOf('第6章')).dy, closeTo(ChapterPanelTheme.listTop, 0.01));
      expect(
        frameTop(tester, '第6章'),
        closeTo(ChapterPanelTheme.listTop + BiliMetrics.panelHairline + ChapterPanelTheme.rowTop, 0.01),
      );
      expect(_colour(tester, '第6章'), ChapterPanelTheme.playing);
      expectHeader(tester);
    });

    testWidgets('one cut by the bottom edge comes to the top too', (tester) async {
      await _pump(tester, chapters: many, at: 4 * 60 + 5);
      expect(tester.getTopLeft(_rowOf('第5章')).dy, closeTo(ChapterPanelTheme.listTop, 0.01));
      expectHeader(tester);
    });

    testWidgets('the last comes as far up as the list goes, ending clear of the home indicator', (tester) async {
      await _pump(tester, chapters: many, at: 11 * 60 + 5);
      expect(position(tester).pixels, position(tester).maxScrollExtent);
      expect(tester.getBottomLeft(_rowOf('第12章')).dy, closeTo(_screen.height - 21 - BiliMetrics.panelBottom, 0.01));
      expectHeader(tester);
    });

    testWidgets('one already in sight leaves the list at its top', (tester) async {
      await _pump(tester, chapters: many, at: 3 * 60 + 5);
      expect(position(tester).pixels, 0);
      expect(_colour(tester, '第4章'), ChapterPanelTheme.playing);
      expect(frameTop(tester, '第1章'), closeTo(57, 0.01));
    });

    testWidgets('scrolled by hand, the rows pass under the header and its switch still answers', (tester) async {
      final rig = await _pump(tester, chapters: many, at: 5);
      await tester.drag(find.text('第3章'), const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(position(tester).pixels, greaterThan(100));
      expectHeader(tester);
      await tester.tap(_switch);
      await tester.pumpAndSettle();
      expect(rig.session.calls, ['setChapterBar false']);
    });
  });

  for (final (name, turn) in [
    ('the small player', (OrientationController o) => o.exitToInline()),
    ('竖屏', (OrientationController o) => o.enterVertical()),
  ]) {
    testWidgets('turned upright to $name, it closes', (tester) async {
      final rig = await _pump(tester);
      turn(rig.ui.orientation);
      tester.view.physicalSize = _screen.flipped;
      await tester.pumpAndSettle();
      expect(rig.panels.value, isNull);
      expect(_frame, findsNothing);
    });
  }

  testWidgets('every control answers accessibility presses', (tester) async {
    final handle = tester.ensureSemantics();
    final rig = await _pump(tester);
    expect(
      tester.getSemantics(_switch),
      isSemantics(label: '章节进度条', hasToggledState: true, isToggled: true, hasTapAction: true),
    );
    tester.semantics.tap(find.semantics.byLabel('章节进度条'));
    await tester.pumpAndSettle();
    expect(rig.session.calls, ['setChapterBar false']);
    expect(tester.getSemantics(_switch), isSemantics(label: '章节进度条', hasToggledState: true, isToggled: false));

    expect(
      tester.getSemantics(_rowOf('2.3')),
      isSemantics(label: '2.3', value: '01:48 - 04:01', isButton: true, isSelected: true, hasTapAction: true),
    );
    expect(tester.getSemantics(_rowOf('1')), isSemantics(label: '1', isButton: true, isSelected: false));
    tester.semantics.tap(find.semantics.byLabel('尾声'));
    await tester.pumpAndSettle();
    expect(rig.session.calls, ['setChapterBar false', 'commitSeek 241.0 precise']);
    expect(rig.panels.value, isNull);
    handle.dispose();
  });
}
