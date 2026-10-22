import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/home/home_tab_bar.dart';
import 'package:bilifast/home/tab_bar_icons.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/skin/skin.dart';
import 'package:bilifast/skin/svga_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../video/mixed_lines.dart';
import 'skin_fixtures.dart';

late SkinPictures _pictures;

const _barTop = 873.0;

void main() {
  setUpAll(() async => _pictures = await SkinPictures.draw());
  tearDownAll(() => _pictures.dispose());

  final taps = <HomeTab>[];
  var pageTaps = 0;

  setUp(() {
    taps.clear();
    pageTaps = 0;
  });

  /// The bar at the bottom of a 440×956 page over a 34 pt home indicator, the page's taps counted; [load] decodes the
  /// skin's pictures first.
  Future<void> show(WidgetTester tester, Skin? skin, {bool still = false, bool load = true}) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(bottom: 34)
      ..viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const SizedBox.shrink());
    if (skin != null && load) await SkinPictures.load(tester, skin);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: _Host(skin: skin, still: still, onTap: taps.add, onPage: () => pageTaps++),
      ),
    );
  }

  Finder slot(HomeTab tab) => find.byKey(ValueKey('home-tab-${tab.name}'));
  Finder dressedBox(HomeTab tab) => find.byKey(ValueKey('home-tab-${tab.name}-skin'));
  Finder art() => find.byKey(const ValueKey('home-tab-art'));

  String pictureIn(WidgetTester tester, HomeTab tab) {
    final image = tester.widget<Image>(find.descendant(of: dressedBox(tab), matching: find.byType(Image)).first);
    return (image.image as FileImage).file.path;
  }

  String file(String name) => _pictures[name].path;

  Future<void> tapTab(WidgetTester tester, HomeTab tab) async {
    await tester.tap(slot(tab));
    await tester.pump();
  }

  Color? labelColour(WidgetTester tester, HomeTab tab) =>
      tester.widget<Text>(find.descendant(of: slot(tab), matching: find.text(tab.label))).style?.color;

  bool hasHairline(WidgetTester tester) => tester
      .widgetList<DecoratedBox>(find.descendant(of: find.byType(HomeTabBar), matching: find.byType(DecoratedBox)))
      .any((box) => (box.decoration as BoxDecoration?)?.border != null);

  for (final (name, skin) in <(String, Skin? Function())>[
    ('no skin', () => null),
    ('four icons each way', () => _pictures.skin(icons: 4)),
    ('no label colours', () => _pictures.skin(colors: const SkinColors(color: 0xFFFFFFFF))),
    ('no tail_bg', () => _pictures.skin(tail: null)),
    ('a tail_bg that won\'t decode', () => _pictures.skin(tail: 'broken.png')),
    ('an icon that won\'t decode', () => _pictures.skin(iconFiles: {3: 'broken.png'})),
    ('a pub button that won\'t decode', () => _pictures.skin(pubFile: 'broken.png')),
  ]) {
    testWidgets('$name: the stock bar, its hairline, glyphs and labels', (tester) async {
      await show(tester, skin());
      expect(find.byType(HomeTabIcon), findsNWidgets(HomeTab.values.length));
      expect(find.byType(SkinTabIcon), findsNothing);
      expect(find.byType(SkinPicture), findsNothing);
      expect(art(), findsNothing);
      expect(hasHairline(tester), isTrue);
      expect(tester.getRect(find.byType(HomeTabBar)), const Rect.fromLTRB(0, _barTop, 440, 956));
      for (final tab in HomeTab.values) {
        if (tab == HomeTab.post) continue;
        expect(labelColour(tester, tab), tab == HomeTab.home ? HomeTabBarTheme.selected : HomeTabBarTheme.label);
      }
    });
  }

  for (final (picture, height) in [('tail_bg.png', 83.0), ('tail_bg_tall.png', 110.0), ('tail_bg_flat.png', 83.0)]) {
    testWidgets(
      '$picture: full width, on the screen\'s bottom, ${height == 83 ? 'covering' : 'rising over'} the row; no '
      'hairline',
      (tester) async {
        await show(tester, _pictures.skin(tail: picture));
        expect(
          tester.getRect(find.byType(HomeTabBar)),
          const Rect.fromLTRB(0, _barTop - HomeTabBarTheme.skinIconOverhang, 440, 956),
          reason: 'grown by the icons\' rise, its row where it was',
        );
        expect(tester.getRect(slot(HomeTab.home)).top, _barTop);
        expect(tester.getRect(art()), Rect.fromLTRB(0, 956 - height, 440, 956));
        final image = tester.widget<Image>(find.descendant(of: art(), matching: find.byType(Image)));
        expect((image.image as FileImage).file.path, file(picture));
        expect(image.fit, BoxFit.cover);
        expect(image.alignment, Alignment.bottomCenter);
        expect(hasHairline(tester), isFalse);
      },
    );
  }

  testWidgets('icons by place: 首页 main, 关注 channel, 消息 shop, 我的 myself, 发布 the pub button, in their boxes', (
    tester,
  ) async {
    await show(tester, _pictures.skin());
    expect(find.byType(HomeTabIcon), findsNothing);
    expect(pictureIn(tester, HomeTab.home), file('tail_icon_selected_0.png'));
    expect(pictureIn(tester, HomeTab.follow), file('tail_icon_1.png'));
    expect(pictureIn(tester, HomeTab.post), file('pub.png'));
    expect(pictureIn(tester, HomeTab.messages), file('tail_icon_3.png'));
    expect(pictureIn(tester, HomeTab.mine), file('tail_icon_4.png'));
    for (final (i, tab) in HomeTab.values.indexed) {
      final box = tester.getRect(find.descendant(of: dressedBox(tab), matching: find.byType(SkinPicture)).first);
      final expected = tab == HomeTab.post
          ? Rect.fromCenter(
              center: Offset(220, _barTop + HomeTabBarTheme.skinPostCentre),
              width: HomeTabBarTheme.skinPostSize,
              height: HomeTabBarTheme.skinPostSize,
            )
          : Rect.fromCenter(
              center: Offset(44 + 88.0 * i, _barTop + HomeTabBarTheme.skinIconCentre),
              width: HomeTabBarTheme.skinIconWidth,
              height: HomeTabBarTheme.skinIconHeight,
            );
      expect(box.left, moreOrLessEquals(expected.left), reason: tab.label);
      expect(box.top, moreOrLessEquals(expected.top), reason: tab.label);
      expect(box.size, expected.size, reason: tab.label);
    }
    expect(
      tester.getRect(find.descendant(of: dressedBox(HomeTab.mine), matching: find.byType(SkinPicture))).top,
      lessThan(_barTop - 15),
      reason: 'the icon rises 16 pt over the bar',
    );

    await tapTab(tester, HomeTab.mine);
    expect(pictureIn(tester, HomeTab.home), file('tail_icon_0.png'));
    expect(pictureIn(tester, HomeTab.mine), file('tail_icon_selected_4.png'));
    expect(pictureIn(tester, HomeTab.follow), file('tail_icon_1.png'));
  });

  testWidgets('without a pub button 发布 keeps the stock +', (tester) async {
    await show(tester, _pictures.skin(pub: false));
    final post = find.descendant(of: slot(HomeTab.post), matching: find.byType(HomeTabIcon));
    expect(post, findsOneWidget);
    expect(tester.getCenter(post).dy, moreOrLessEquals(_barTop + HomeTabBarTheme.postCentre));
    expect(find.byType(SkinTabIcon), findsNWidgets(4));
  });

  testWidgets("labels where the stock bar's are, in the skin's colours", (tester) async {
    await show(tester, null);
    final stock = {
      for (final tab in HomeTab.values)
        if (tab != HomeTab.post) tab: tester.getRect(find.text(tab.label)),
    };
    await show(tester, _pictures.skin());
    for (final MapEntry(key: tab, value: rect) in stock.entries) {
      expect(tester.getRect(find.text(tab.label)), rect, reason: tab.label);
      expect(labelColour(tester, tab), Color(tab == HomeTab.home ? 0xFFFFDA76 : 0xFFFAF0E4), reason: tab.label);
    }
    await tapTab(tester, HomeTab.mine);
    expect(labelColour(tester, HomeTab.mine), const Color(0xFFFFDA76));
    expect(labelColour(tester, HomeTab.home), const Color(0xFFFAF0E4));
  });

  group('an animated selected icon', () {
    SvgaView? svga(WidgetTester tester, HomeTab tab) {
      final found = find.descendant(of: dressedBox(tab), matching: find.byType(SvgaView));
      return found.evaluate().isEmpty ? null : tester.widget<SvgaView>(found);
    }

    Key? playKey(WidgetTester tester, HomeTab tab) =>
        tester.widget<SkinPicture>(find.descendant(of: dressedBox(tab), matching: find.byType(SkinPicture)).first).key;

    for (final cycle in [false, true]) {
      testWidgets('plays from its first frame each time its place is selected, ${cycle ? 'looping' : 'once'}', (
        tester,
      ) async {
        await show(
          tester,
          _pictures.skin(
            animated: {0, 4},
            colors: SkinColors(
              color: standInColors.color,
              tailColor: standInColors.tailColor,
              tailColorSelected: standInColors.tailColorSelected,
              tailIconCycle: cycle,
            ),
          ),
        );
        final home = svga(tester, HomeTab.home)!;
        expect(home.file.path, file('tail_icon_selected_0.svga'));
        expect(home.play, isTrue);
        expect(home.loop, cycle);
        expect(svga(tester, HomeTab.mine), isNull, reason: 'unselected icons are still pictures');
        final first = playKey(tester, HomeTab.home);

        await tapTab(tester, HomeTab.mine);
        expect(svga(tester, HomeTab.home), isNull);
        expect(pictureIn(tester, HomeTab.home), file('tail_icon_0.png'));
        final mine = svga(tester, HomeTab.mine)!;
        expect(mine.file.path, file('tail_icon_selected_4.svga'));
        expect(mine.play, isTrue);
        expect(mine.loop, cycle);

        await tapTab(tester, HomeTab.home);
        expect(svga(tester, HomeTab.home)!.play, isTrue);
        expect(playKey(tester, HomeTab.home), isNot(first), reason: 'a new selection plays afresh');
        final again = playKey(tester, HomeTab.home);
        await tapTab(tester, HomeTab.follow);
        await tapTab(tester, HomeTab.home);
        expect(playKey(tester, HomeTab.home), isNot(again));
      });
    }

    testWidgets('stays on its first frame under Reduce Motion', (tester) async {
      await show(tester, _pictures.skin(animated: {0}), still: true);
      expect(svga(tester, HomeTab.home)!.play, isFalse);
    });
  });

  group('the change of place', () {
    double opacity(WidgetTester tester, HomeTab tab) => tester
        .widget<FadeTransition>(find.descendant(of: dressedBox(tab), matching: find.byType(FadeTransition)).first)
        .opacity
        .value;

    /// How far the picture sits under its box.
    double drop(WidgetTester tester, HomeTab tab) =>
        tester.getTopLeft(find.descendant(of: dressedBox(tab), matching: find.byType(Image)).first).dy -
        tester.getTopLeft(find.descendant(of: dressedBox(tab), matching: find.byType(SkinTabIcon))).dy;

    SkinColors colors({required bool animated}) => SkinColors(
      color: standInColors.color,
      tailColor: standInColors.tailColor,
      tailColorSelected: standInColors.tailColorSelected,
      tailIconAnimated: animated,
    );

    testWidgets('with tail_icon_ani fades both incoming pictures in over 300 ms, rising 20 pt into place', (
      tester,
    ) async {
      await show(tester, _pictures.skin(colors: colors(animated: true)));
      for (final tab in [HomeTab.home, HomeTab.mine]) {
        expect(opacity(tester, tab), 1);
        expect(drop(tester, tab), 0);
      }
      await tapTab(tester, HomeTab.mine);
      for (final tab in [HomeTab.home, HomeTab.mine]) {
        expect(opacity(tester, tab), 0, reason: tab.label);
        expect(drop(tester, tab), moreOrLessEquals(HomeTabBarTheme.skinIconRise), reason: tab.label);
      }
      expect(opacity(tester, HomeTab.follow), 1, reason: 'the others stay');
      await tester.pump(const Duration(milliseconds: 150));
      for (final tab in [HomeTab.home, HomeTab.mine]) {
        expect(opacity(tester, tab), inExclusiveRange(0, 1), reason: tab.label);
        expect(drop(tester, tab), inExclusiveRange(0, HomeTabBarTheme.skinIconRise), reason: tab.label);
      }
      await tester.pump(const Duration(milliseconds: 150));
      for (final tab in [HomeTab.home, HomeTab.mine]) {
        expect(opacity(tester, tab), 1, reason: tab.label);
        expect(drop(tester, tab), 0, reason: tab.label);
      }
      expect(pictureIn(tester, HomeTab.mine), file('tail_icon_selected_4.png'));
    });

    for (final (name, animated, still) in [
      ('without tail_icon_ani', false, false),
      ('under Reduce Motion', true, true),
    ]) {
      testWidgets('$name the picture changes at once', (tester) async {
        await show(
          tester,
          _pictures.skin(colors: colors(animated: animated)),
          still: still,
        );
        await tapTab(tester, HomeTab.mine);
        for (final tab in [HomeTab.home, HomeTab.mine]) {
          expect(opacity(tester, tab), 1, reason: tab.label);
          expect(drop(tester, tab), 0, reason: tab.label);
        }
        expect(tester.binding.transientCallbackCount, 0);
      });
    }
  });

  testWidgets('presses reach every place over its icon, its label and the icon\'s rise over the bar; beside and '
      'above the icons the page keeps its taps, under the rest of the picture too', (tester) async {
    final semantics = tester.ensureSemantics();
    await show(tester, _pictures.skin(tail: 'tail_bg_tall.png'));
    for (final (i, tab) in HomeTab.values.indexed) {
      expect(tester.getRect(slot(tab)), Rect.fromLTWH(88.0 * i, _barTop, 88, HomeTabBarTheme.height));
      await tester.tapAt(Offset(44 + 88.0 * i, _barTop + 4));
      await tester.pump();
      await tester.tapAt(Offset(44 + 88.0 * i, _barTop + HomeTabBarTheme.labelTop + 6));
      await tester.pump();
      expect(taps, [tab, tab], reason: tab.label);
      taps.clear();
      expect(
        tester.getSemantics(slot(tab)),
        isSemantics(
          label: tab.label,
          isButton: true,
          hasTapAction: true,
          hasSelectedState: true,
          isSelected: tab == HomeTab.home || tab == HomeTab.follow || tab == HomeTab.mine,
        ),
        reason: tab.label,
      );
      if (tab == HomeTab.post) continue;
      final icon = tester.getRect(find.descendant(of: dressedBox(tab), matching: find.byType(SkinPicture)).first);
      expect(icon.top, lessThan(_barTop - 16));
      expect(
        tester.getRect(find.byKey(ValueKey('home-tab-${tab.name}-rise'))),
        rectMoreOrLessEquals(Rect.fromLTRB(icon.left, icon.top, icon.right, _barTop)),
        reason: tab.label,
      );
      for (final at in [
        icon.topLeft + const Offset(1, 1),
        icon.topRight + const Offset(-1, 1),
        Offset(icon.center.dx, _barTop - 1),
      ]) {
        await tester.tapAt(at);
        await tester.pump();
      }
      expect(taps, [tab, tab, tab], reason: "${tab.label}'s rise");
      taps.clear();
    }
    expect(find.byKey(const ValueKey('home-tab-post-rise')), findsNothing, reason: "发布's picture stays under the top");
    expect(pageTaps, 0);
    final rise = _barTop - HomeTabBarTheme.skinIconOverhang;
    for (final at in [
      Offset(44, rise - 1),
      const Offset(88, _barTop - 8),
      const Offset(220, _barTop - 8),
      const Offset(5, _barTop - 8),
      const Offset(44, _barTop - 24),
    ]) {
      await tester.tapAt(at);
      await tester.pump();
    }
    expect(pageTaps, 5, reason: 'the picture rising beside and above the icons takes no taps');
    expect(taps, isEmpty);
    semantics.dispose();
  });

  group('the decode gate', () {
    testWidgets('stock until the picture and the icons have decoded, then dressed', (tester) async {
      imageCache
        ..clear()
        ..clearLiveImages();
      await show(tester, _pictures.skin(), load: false);
      expect(art(), findsNothing);
      expect(hasHairline(tester), isTrue);
      expect(find.byType(HomeTabIcon), findsNWidgets(HomeTab.values.length));
      expect(labelColour(tester, HomeTab.home), HomeTabBarTheme.selected, reason: 'no skin colour without its picture');
      for (var i = 0; i < 100 && art().evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(art(), findsOneWidget);
      expect(find.byType(SkinTabIcon), findsNWidgets(4));
      expect(labelColour(tester, HomeTab.home), const Color(0xFFFFDA76));
    });

    testWidgets("a broken picture the bar doesn't draw (dynamic's icon) leaves it dressed", (tester) async {
      await show(tester, _pictures.skin(iconFiles: {2: 'broken.png'}));
      expect(art(), findsOneWidget);
      expect(find.byType(SkinTabIcon), findsNWidgets(4));
    });

    testWidgets('a picture failing as it draws drops the bar back to stock, logged', (tester) async {
      final logs = MemorySink();
      Logger.shared.add(logs);
      addTearDown(() => Logger.shared.remove(logs));
      await show(tester, _pictures.skin());
      final image = find.descendant(of: dressedBox(HomeTab.mine), matching: find.byType(Image));
      tester.widget<Image>(image).errorBuilder!(tester.element(image), Exception('gone'), null);
      await tester.pump();
      await tester.pump();
      expect(art(), findsNothing);
      expect(hasHairline(tester), isTrue);
      expect(find.byType(HomeTabIcon), findsNWidgets(HomeTab.values.length));
      final logged = logs.events.where((event) => event.msg == 'skin picture failed').toList();
      expect(logged, hasLength(1));
      expect(logged.single.f['file']?.toJson(), 'tail_icon_4.png');
    });
  });
}

/// The page with the bar on its bottom, selecting what's tapped as `MainShell` does.
class _Host extends StatefulWidget {
  const _Host({required this.skin, required this.still, required this.onTap, required this.onPage});

  final Skin? skin;
  final bool still;
  final ValueChanged<HomeTab> onTap;
  final VoidCallback onPage;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  HomeTab _selected = HomeTab.home;

  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: widget.still),
    child: Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPage,
            child: const ColoredBox(color: Color(0xFFFFFFFF)),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: HomeTabBar(
            selected: _selected,
            skin: widget.skin,
            onTap: (tab) {
              widget.onTap(tab);
              if (tab == HomeTab.home || tab == HomeTab.follow || tab == HomeTab.mine) setState(() => _selected = tab);
            },
          ),
        ),
      ],
    ),
  );
}
