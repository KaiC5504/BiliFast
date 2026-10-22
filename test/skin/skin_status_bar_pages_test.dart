import 'dart:ui' as ui;

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/route_observer.dart';
import 'package:bilifast/home/main_shell.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/me/fake_me_api.dart';
import 'package:bilifast/search/fake_search_api.dart';
import 'package:bilifast/settings/font_store.dart';
import 'package:bilifast/skin/skin.dart';
import 'package:bilifast/skin/skin_status_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../home/fake_login_gate.dart';
import '../home/feed_fakes.dart';
import '../home/skin_fixtures.dart';
import '../me/me_page_support.dart' show FixedSkinModel;
import '../playback/fakes.dart';

late SkinPictures _pictures;

/// Light stand-ins in the shapes of [SkinPictures]' dark head_bg and 我的 header.
Future<void> _drawLight() async {
  for (final (name, height) in [('light_head.png', 318), ('light_me.png', 1320)]) {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(Rect.fromLTWH(0, 0, 1320, height.toDouble()), Paint()..color = const Color(0xFFF5EBD7));
    final picture = recorder.endRecording();
    final image = await picture.toImage(1320, height);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    image.dispose();
    await _pictures[name].writeAsBytes(bytes!.buffer.asUint8List());
  }
}

void main() {
  setUpAll(() async {
    _pictures = await SkinPictures.draw();
    await _drawLight();
  });
  tearDownAll(() => _pictures.dispose());

  /// [skin] measured as the model measures it, then the shell over it on KaiC's iPhone.
  Future<void> show(WidgetTester tester, Skin skin) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: 62, bottom: 34)
      ..viewPadding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    final measured = skin.withStatusBar((await tester.runAsync(() => measureSkinStatusBar(skin)))!);
    await SkinPictures.load(tester, measured);
    final http = FeedHttp()..pages[1] = [for (var i = 0; i < 6; i++) feedItem('BV1s$i')];
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
      fonts: FontStore.memory(),
      searchApi: FakeSearchApi(defaultWord: '搜索'),
      meApi: FakeMeApi.demo(),
      loginGate: FakeLoginGate(),
    );
    final skins = FixedSkinModel(measured, environment: environment);
    addTearDown(skins.dispose);
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [pageRoutes],
        builder: (context, child) => AppScope(services: services, child: child!),
        home: MainShell(skin: skins),
      ),
    );
    await settle(tester);
  }

  Brightness? icons() => SystemChrome.latestStyle?.statusBarIconBrightness;

  Future<void> openMe(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('home-tab-mine')));
    await settle(tester);
    expect(find.byKey(const ValueKey('me-skin-picture')), findsOneWidget, reason: '我的 dressed');
  }

  testWidgets("a dark stand-in header gives white icons on 首页 and 我的 though the skin's color_mode asks dark", (
    tester,
  ) async {
    await show(
      tester,
      _pictures.skin(
        colors: SkinColors(
          color: 0xFFFFFFFF,
          tailColor: standInColors.tailColor,
          tailColorSelected: standInColors.tailColorSelected,
        ),
      ),
    );
    expect(find.byKey(const ValueKey('home-head-art')), findsOneWidget, reason: '首页 dressed');
    expect(icons(), Brightness.light);
    await openMe(tester);
    expect(icons(), Brightness.light);
  });

  testWidgets("a light one gives black icons on both though color_mode asks light", (tester) async {
    final light = _pictures.skin();
    final skin = Skin(
      equip: light.equip,
      headBg: _pictures['light_head.png'],
      headTabBg: light.headTabBg,
      headMyself: _pictures['light_me.png'],
      tailBg: light.tailBg,
      tailIcons: light.tailIcons,
      tailIconsSelected: light.tailIconsSelected,
      pubButton: light.pubButton,
    );
    expect(skin.lightText, isTrue);
    await show(tester, skin);
    expect(find.byKey(const ValueKey('home-head-art')), findsOneWidget);
    expect(icons(), Brightness.dark);
    await openMe(tester);
    expect(icons(), Brightness.dark);
  });
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
