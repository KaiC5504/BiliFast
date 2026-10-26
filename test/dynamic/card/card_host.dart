import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/dynamic/card/dynamic_open.dart';
import 'package:bilifast/dynamic/fake_dynamic_api.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/settings/font_store.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/fake_keychain.dart';
import '../../home/fake_login_gate.dart';
import '../../playback/fakes.dart';
import '../../support/stand_in_fonts.dart';
import '../../video/mixed_lines.dart' show appTheme;

/// What the card's taps asked for, in order, in place of real pages and the platform.
final class Opened {
  final posts = <({String id, bool toComments})>[];
  final videos = <VideoRoute>[];
  final spaces = <int>[];
  final links = <Uri>[];
  final shares = <Uri>[];
}

/// The services a card reaches and what it opened.
final class CardHost {
  CardHost(this.services, this.api, this.pageApi, this.gate, this.opened, this.http);

  final AppServices services;
  final FakeDynamicApi api;
  final FakePageApi pageApi;
  final FakeLoginGate gate;
  final Opened opened;

  /// What the players' calls are answered with.
  final CannedHttp http;
}

/// [child] scrolling on a white page at the iPhone's size, with the services a 动态 card reaches: 动态's calls answered by
/// [api], the page's by a [FakePageApi], the login by a [FakeLoginGate], and [DynamicOpen] recording instead of opening.
/// [loggedIn] false makes the account logged out; true leaves it as the cookies say (a login). [systemFont] draws the
/// iPhone's system font with the stand-ins loaded.
Future<CardHost> pumpCardHost(
  WidgetTester tester,
  Widget child, {
  FakeDynamicApi? api,
  bool loggedIn = true,
  Future<PlaybackController> Function(AppEnvironment environment)? players,
  Key? screen,
  bool scroll = true,
  bool systemFont = false,
  void Function(AppServices services)? before,
}) async {
  tester.view
    ..physicalSize = const Size(440, 956)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final opened = _record();
  final logger = Logger(session: 'test');
  final http = Canned.http(loggedIn: loggedIn);
  final environment = await AppEnvironment.load(
    keychain: FakeKeychain(StoredCookies(loggedIn ? Canned.cookies : const {'buvid3': 'b3', 'buvid4': 'b4'})),
    http: http,
    logger: logger,
  );
  await environment.refreshAccount();
  final playback = AppPlayback(
    players == null ? () => Completer<PlaybackController>().future : () => players(environment),
  );
  addTearDown(playback.dispose);
  final dynamicApi = api ?? FakeDynamicApi();
  final pageApi = FakePageApi();
  final gate = FakeLoginGate();
  final services = AppServices(
    environment: environment,
    playback: playback,
    recents: await RecentStore.load(null, logger: logger),
    pageApi: pageApi,
    dynamicApi: dynamicApi,
    loginGate: gate,
    fonts: systemFont ? (FontStore.memory()..select(FontChoice.system)) : null,
  );
  before?.call(services);
  if (systemFont) {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    BiliFonts.family = BiliFonts.system;
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      builder: (context, app) => RepaintBoundary(
        key: screen,
        child: AppScope(services: services, child: app!),
      ),
      home: Material(
        color: Colors.white,
        child: scroll ? SingleChildScrollView(child: child) : child,
      ),
    ),
  );
  await tester.pump();
  return CardHost(services, dynamicApi, pageApi, gate, opened, http);
}

Opened _record() {
  final opened = Opened();
  DynamicOpen.post = (context, {required id, item, toComments = false}) async =>
      opened.posts.add((id: id, toComments: toComments));
  DynamicOpen.video = (context, route) async => opened.videos.add(route);
  DynamicOpen.space = (context, uploader) async => opened.spaces.add(uploader.mid);
  DynamicOpen.browser = (link) async {
    opened.links.add(link);
    return true;
  };
  DynamicOpen.share = (link) async {
    opened.shares.add(link);
    return true;
  };
  addTearDown(DynamicOpen.reset);
  return opened;
}

/// A post by an author with [mid], everything else plain, for tests that care about one part.
DynamicItem post(
  String id, {
  DynamicKind kind = DynamicKind.word,
  List<DynamicNode> nodes = const [DynamicTextNode('一条动态')],
  DynamicMajor? major,
  DynamicStat stat = const DynamicStat(),
  DynamicItem? original,
  DynamicGoods? goods,
  bool folded = false,
  DynamicAuthor author = const DynamicAuthor(mid: 7, name: '作者', face: '', pubTime: '3小时前'),
  List<DynamicMenuItem> menu = const [DynamicMenuItem.unfollow, DynamicMenuItem.report],
}) => DynamicItem(
  id: id,
  kind: kind,
  author: author,
  nodes: nodes,
  major: major,
  stat: stat,
  original: original,
  goods: goods,
  foldedLines: folded,
  menu: menu,
);
