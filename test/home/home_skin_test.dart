import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/home_page.dart';
import 'package:bilifast/home/home_tab_bar.dart';
import 'package:bilifast/home/main_shell.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/home/tab_bar_icons.dart';
import 'package:bilifast/me/fake_me_api.dart';
import 'package:bilifast/me/me_page.dart';
import 'package:bilifast/search/fake_search_api.dart';
import 'package:bilifast/settings/font_store.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/skin/skin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import '../video/mixed_lines.dart';
import 'fake_login_gate.dart';
import 'feed_fakes.dart';
import 'skin_fixtures.dart';

late SkinPictures _pictures;

const _screen = ValueKey('screen');

/// 110's default word.
const _word = '曜荣耀典藏';

void main() {
  setUpAll(() async => _pictures = await SkinPictures.draw());
  tearDownAll(() => _pictures.dispose());

  late FeedHttp http;

  setUp(() {
    http = FeedHttp()..pages[1] = [for (var i = 0; i < 20; i++) feedItem('BV1s$i')];
  });

  /// The shell on KaiC's iPhone (62 pt status bar, 34 pt home indicator), its 装扮 [skin] held in the returned
  /// notifier; [phone] draws it at 3× under the system font.
  Future<ValueNotifier<Skin?>> show(WidgetTester tester, Skin? skin, {bool phone = false}) async {
    await tester.pumpWidget(const SizedBox.shrink());
    if (phone) {
      final saved = BiliFonts.family;
      addTearDown(() => BiliFonts.family = saved);
      await tester.runAsync(loadSystemFontStandIns);
      showAsPhone(tester);
    } else {
      tester.view
        ..physicalSize = const Size(440, 956)
        ..devicePixelRatio = 1
        ..padding = const FakeViewPadding(top: 62, bottom: 34)
        ..viewPadding = const FakeViewPadding(top: 62, bottom: 34);
      addTearDown(tester.view.reset);
    }
    if (skin != null) await SkinPictures.load(tester, skin);
    final logger = Logger(session: 'test');
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(StoredCookies(Canned.cookies)),
      http: http,
      logger: logger,
    );
    await environment.refreshAccount();
    final playback = AppPlayback(() => throw StateError('no playback here'));
    addTearDown(playback.dispose);
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      fonts: FontStore.memory()..select(FontChoice.system),
      searchApi: FakeSearchApi(defaultWord: _word),
      meApi: FakeMeApi.demo(),
      loginGate: FakeLoginGate(),
    );
    final notifier = ValueNotifier<Skin?>(skin);
    addTearDown(notifier.dispose);
    if (phone) BiliFonts.family = BiliFonts.system;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        builder: (context, child) => RepaintBoundary(
          key: _screen,
          child: AppScope(services: services, child: child!),
        ),
        home: MainShell(skin: notifier),
      ),
    );
    return notifier;
  }

  Future<void> settle(WidgetTester tester, [int frames = 20]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Finder headArt() => find.byKey(const ValueKey('home-head-art'));
  Finder tabArt() => find.byKey(const ValueKey('home-head-tab-art'));
  Rect divider(WidgetTester tester) => tester.getRect(find.byType(Divider).first);

  Image imageIn(WidgetTester tester, Finder finder) =>
      tester.widget<Image>(find.descendant(of: finder, matching: find.byType(Image)));

  Color? recommendColour(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('home-tab-recommend'))).style?.color;

  Color? indicatorColour(WidgetTester tester) =>
      (tester.widget<Container>(find.byKey(const ValueKey('home-tab-indicator'))).decoration! as BoxDecoration).color;

  Container field(WidgetTester tester) => tester.widget<Container>(find.byKey(const ValueKey('home-search-field')));

  ScrollPosition feedScroll(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(of: find.byKey(const ValueKey('feed')), matching: find.byType(Scrollable)).first,
      )
      .position;

  double bottomInset(WidgetTester tester, Type page) =>
      MediaQuery.paddingOf(tester.element(find.byType(page, skipOffstage: false))).bottom;

  group('首页 dressed by head_bg', () {
    testWidgets(
      'to the top row\'s bottom with head_tab_bg behind the tab row, both centre-cropped; the hairline grey',
      (tester) async {
        await show(tester, _pictures.skin());
        await settle(tester);
        expect(tester.getRect(headArt()), const Rect.fromLTRB(0, 0, 440, 106));
        expect(tester.getRect(tabArt()), Rect.fromLTRB(0, 106, 440, divider(tester).top));
        for (final (art, name) in [(headArt(), 'head_bg.png'), (tabArt(), 'head_tab_bg.png')]) {
          final image = imageIn(tester, art);
          expect((image.image as FileImage).file.path, _pictures[name].path);
          expect(image.fit, BoxFit.cover);
          expect(image.alignment, Alignment.center);
        }
        expect(tester.widget<Divider>(find.byType(Divider).first).color, HomeTabBarTheme.headDivider);
      },
    );

    testWidgets('behind the whole top when the package has no tab picture', (tester) async {
      await show(tester, _pictures.skin(tab: false));
      await settle(tester);
      expect(tester.getRect(headArt()), Rect.fromLTRB(0, 0, 440, divider(tester).top));
      expect(tabArt(), findsNothing);
    });

    testWidgets("推荐 and its indicator in the skin's colour, the field white without its rim, the avatar and field "
        'where they were, the status bar light', (tester) async {
      await show(tester, null);
      await settle(tester);
      final avatar = tester.getRect(find.byKey(const ValueKey('home-avatar')));
      final entry = tester.getRect(find.byKey(const ValueKey('home-search')));
      final recommend = tester.getRect(find.byKey(const ValueKey('home-tab-recommend')));
      expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.dark);

      await show(tester, _pictures.skin());
      await settle(tester);
      expect(recommendColour(tester), const Color(0xFFFFFFFF));
      expect(indicatorColour(tester), const Color(0xFFFFFFFF));
      final decoration = field(tester).decoration! as ShapeDecoration;
      expect(decoration.color, HomeTabBarTheme.headField);
      expect((field(tester).foregroundDecoration! as ShapeDecoration).shape, const StadiumBorder());
      expect(tester.getRect(find.byKey(const ValueKey('home-avatar'))), avatar);
      expect(tester.getRect(find.byKey(const ValueKey('home-search'))), entry);
      expect(tester.getRect(find.byKey(const ValueKey('home-tab-recommend'))), recommend);
      expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.light);
    });

    testWidgets('a dark-text skin keeps the status bar dark', (tester) async {
      await show(
        tester,
        _pictures.skin(
          colors: const SkinColors(color: 0xFF222222, tailColor: 0xFFFAF0E4, tailColorSelected: 0xFFFFDA76),
        ),
      );
      await settle(tester);
      expect(recommendColour(tester), const Color(0xFF222222));
      expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.dark);
    });

    testWidgets('a skin without head_bg leaves the top stock, whatever its colours', (tester) async {
      await show(tester, _pictures.skin(head: false));
      await settle(tester);
      expect(headArt(), findsNothing);
      expect(tabArt(), findsNothing);
      expect(recommendColour(tester), BiliColors.pink);
      expect(indicatorColour(tester), BiliColors.pink);
      expect(field(tester).decoration, isNull);
      expect(tester.widget<Divider>(find.byType(Divider).first).color, BiliColors.divider);
      expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.dark);
      expect(find.byType(SkinTabIcon), findsNWidgets(4), reason: 'the bar still takes it');
    });
  });

  testWidgets('under a dressed bar the pages run to the bottom inset by the stock bar: the feed ends where the stock '
      "bar's feed does, 我的 gets the same inset", (tester) async {
    /// The lowest card's bottom with 推荐 scrolled to its end.
    Future<double> end() async {
      final scroll = feedScroll(tester);
      for (var i = 0; i < 2; i++) {
        scroll.jumpTo(scroll.maxScrollExtent);
        await settle(tester);
      }
      return find
          .byWidgetPredicate((widget) => '${widget.key}'.startsWith("[<'feed-card-"))
          .evaluate()
          .map((card) => tester.getRect(find.byWidget(card.widget)).bottom)
          .reduce((a, b) => a > b ? a : b);
    }

    await show(tester, null);
    await settle(tester);
    final stockEnd = await end();

    await show(tester, _pictures.skin());
    await settle(tester);
    final bar = tester.getRect(find.byType(HomeTabBar));
    expect(bar, const Rect.fromLTRB(0, 873, 440, 956));
    expect(tester.getRect(find.byType(HomePage)).bottom, 956);
    expect(tester.getRect(find.byKey(const ValueKey('feed'))).bottom, 956);
    expect(bottomInset(tester, HomePage), HomeTabBarTheme.height + 34);
    expect(bottomInset(tester, MePage), HomeTabBarTheme.height + 34);
    expect(await end(), stockEnd);
    expect(stockEnd, lessThan(bar.top));

    await tester.tap(find.byKey(const ValueKey('home-tab-mine')));
    await settle(tester);
    expect(tester.getRect(find.byType(MePage)), const Rect.fromLTRB(0, 0, 440, 956));
    expect(bottomInset(tester, MePage), HomeTabBarTheme.height + 34);
  });

  testWidgets('a skin coming and going: the stock layout back exactly, both pages and 推荐\'s place kept', (
    tester,
  ) async {
    final skin = await show(tester, null);
    await settle(tester);
    final stockFeed = tester.getRect(find.byKey(const ValueKey('feed')));
    expect(stockFeed.bottom, 873);
    expect(bottomInset(tester, HomePage), 0);
    expect(bottomInset(tester, MePage), 0);
    final home = tester.state(find.byType(HomePage));
    final me = tester.state(find.byType(MePage, skipOffstage: false));
    await tester.drag(find.byKey(const ValueKey('feed')), const Offset(0, -600));
    await settle(tester);
    final at = feedScroll(tester).pixels;
    expect(at, greaterThan(300));

    final dressed = _pictures.skin();
    await SkinPictures.load(tester, dressed);
    skin.value = dressed;
    await settle(tester);
    expect(find.byKey(const ValueKey('home-tab-art')), findsOneWidget);
    expect(headArt(), findsOneWidget);
    expect(tester.getRect(find.byKey(const ValueKey('feed'))).bottom, 956);
    expect(feedScroll(tester).pixels, at);
    expect(tester.state(find.byType(HomePage)), same(home));
    expect(tester.state(find.byType(MePage, skipOffstage: false)), same(me));

    skin.value = null;
    await settle(tester);
    expect(find.byKey(const ValueKey('home-tab-art')), findsNothing);
    expect(headArt(), findsNothing);
    expect(find.byType(HomeTabIcon), findsNWidgets(HomeTab.values.length));
    expect(tester.getRect(find.byKey(const ValueKey('feed'))), stockFeed);
    expect(bottomInset(tester, HomePage), 0);
    expect(feedScroll(tester).pixels, at);
    expect(tester.state(find.byType(HomePage)), same(home));
  });

  testWidgets('every place answers its press under a dressed bar', (tester) async {
    await show(tester, _pictures.skin());
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('home-tab-mine')));
    await settle(tester);
    expect(tester.widget<MePage>(find.byType(MePage)).active, isTrue);
    for (final tab in [HomeTab.follow, HomeTab.post, HomeTab.messages]) {
      await tester.tap(find.byKey(ValueKey('home-tab-${tab.name}')));
      await tester.pump();
      expect(find.text('暂未开放'), findsOneWidget, reason: tab.label);
      await settle(tester, 60);
    }
    final asked = List.of(http.asked);
    await tester.tap(find.byKey(const ValueKey('home-tab-home')));
    await settle(tester);
    expect(find.byType(HomePage), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-tab-home')));
    await settle(tester, 40);
    expect(http.asked, [...asked, 1], reason: '首页 on 首页 still refreshes 推荐');
  });

  /// The dressed screens as KaiC's iPhone draws them under the system font, against 110 (首页) and 109 (我的'). With
  /// BILIFAST_SHOTS naming a folder outside the repo, the 3× shots are saved there for tools/screen_diff.py.
  for (final (selected, shot) in [(HomeTab.home, '110-home'), (HomeTab.mine, '109-me')]) {
    testWidgets('under the system font with a stand-in skin, ${selected.label} where $shot has it', (tester) async {
      await show(tester, _pictures.skin(), phone: true);
      await settle(tester, 40);
      if (selected == HomeTab.mine) {
        await tester.tap(find.byKey(const ValueKey('home-tab-mine')));
        await settle(tester);
      } else {
        expect(tester.getRect(headArt()), const Rect.fromLTRB(0, 0, 440, 106));
        expect(tester.getRect(find.byKey(const ValueKey('home-search'))), const Rect.fromLTRB(64, 67, 364, 101));
        expect(tester.getRect(find.byKey(const ValueKey('home-avatar'))).center.dy, 84);
      }
      expect(tester.getRect(find.byType(HomeTabBar)), const Rect.fromLTRB(0, 873, 440, 956));
      expect(tester.getRect(find.byKey(const ValueKey('home-tab-art'))), const Rect.fromLTRB(0, 873, 440, 956));
      for (final (i, tab) in HomeTab.values.indexed) {
        final box = tester.getRect(find.byKey(ValueKey('home-tab-${tab.name}-skin')));
        expect(box.center.dx, 44 + 88.0 * i, reason: tab.label);
        expect(
          box.center.dy,
          moreOrLessEquals(tab == HomeTab.post ? 873 + 88 / 3 : 873 + 19 / 3, epsilon: 0.01),
          reason: tab.label,
        );
      }

      final shots = Platform.environment['BILIFAST_SHOTS'];
      if (shots != null) await saveShot(tester, find.byKey(_screen), '$shots/$shot-skin-ours.png');
    });
  }
}
