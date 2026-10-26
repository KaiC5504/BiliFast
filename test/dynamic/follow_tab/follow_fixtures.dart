import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/dynamic/fake_dynamic_api.dart';
import 'package:bilifast/home/main_shell.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/me/fake_me_api.dart';
import 'package:bilifast/search/fake_search_api.dart';
import 'package:bilifast/settings/font_store.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/skin/skin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/fake_keychain.dart';
import '../../home/fake_login_gate.dart';
import '../../home/feed_fakes.dart';
import '../../home/skin_fixtures.dart';
import '../../me/me_page_support.dart' show FixedSkinModel;
import '../../playback/fakes.dart';
import '../../support/look_alike.dart';
import '../../support/stand_in_fonts.dart';
import '../../video/mixed_lines.dart' show appTheme;

const shellScreen = ValueKey('screen');

/// A plain post by [mid], numbered [n].
DynamicItem post(int n, {int mid = 1, DynamicKind kind = DynamicKind.word}) => DynamicItem(
  id: 'p$n',
  kind: kind,
  typeName: 'DYNAMIC_TYPE_WORD',
  author: DynamicAuthor(mid: mid, name: '作者$mid', face: ''),
  nodes: [DynamicTextNode('第$n条')],
);

List<DynamicItem> posts(int count, {int mid = 1, int from = 0}) => [
  for (var i = from; i < from + count; i++) post(i, mid: mid),
];

const faces = [
  DynamicUp(mid: 101, name: '晚风的星星', face: '', hasUpdate: true),
  DynamicUp(mid: 102, name: '云舟mimi', face: '', hasUpdate: true),
  DynamicUp(mid: 103, name: '星海远航计划', face: '', hasUpdate: true),
  DynamicUp(mid: 104, name: '云海', face: '', hasUpdate: true),
];

/// 最常访问 in two pages: [first] with more to come under offset `u1`, then [rest]; [failMore] makes the second throw.
final class PagedUpsApi extends FakeDynamicApi {
  PagedUpsApi({super.posts, required this.first, required this.rest});

  final List<DynamicUp> first;
  final List<DynamicUp> rest;
  Object? failMore;

  @override
  Future<DynamicUpList> ups({String? offset}) async {
    calls.add('ups offset=${offset ?? ''}');
    if (offset == null) return DynamicUpList(ups: first, offset: 'u1', hasMore: true);
    if (failMore case final error?) throw error;
    return DynamicUpList(ups: rest);
  }
}

/// What the test's shell runs on.
final class ShellRig {
  ShellRig({required this.api, required this.http, required this.gate, required this.services});

  final FakeDynamicApi api;
  final FeedHttp http;
  final FakeLoginGate gate;
  final AppServices services;
}

/// The bottom bar's shell at 440×956 (over a 34 pt home indicator and a 62 pt status bar), or as KaiC's iPhone at 3×
/// under the system font when [phone]. [loginGate] stands in for the rig's [FakeLoginGate].
Future<ShellRig> showShell(
  WidgetTester tester, {
  FakeDynamicApi? api,
  bool loggedIn = true,
  bool phone = false,
  Map<String, WidgetBuilder> routes = const {},
  Skin? skin,
  LoginGate? loginGate,
}) async {
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
  final http = FeedHttp(loggedIn: loggedIn)..pages[1] = [for (var i = 0; i < 6; i++) feedItem('BV1f$i')];
  final logger = Logger(session: 'test');
  final environment = await AppEnvironment.load(
    keychain: FakeKeychain(loggedIn ? StoredCookies(Canned.cookies) : const NoStoredCookies()),
    http: http,
    logger: logger,
  );
  await environment.refreshAccount();
  final playback = AppPlayback(() => throw StateError('no playback here'));
  addTearDown(playback.dispose);
  final gate = FakeLoginGate();
  final dynamicApi = api ?? FakeDynamicApi(posts: posts(30), upList: faces);
  final services = AppServices(
    environment: environment,
    playback: playback,
    recents: await RecentStore.load(null, logger: logger),
    fonts: FontStore.memory()..select(FontChoice.system),
    searchApi: FakeSearchApi(defaultWord: '星海新版本即将上线'),
    meApi: FakeMeApi.demo(),
    dynamicApi: dynamicApi,
    loginGate: loginGate ?? gate,
  );
  if (skin != null) await SkinPictures.load(tester, skin);
  final skins = skin == null ? null : FixedSkinModel(skin, environment: environment);
  if (skins != null) addTearDown(skins.dispose);
  if (phone) BiliFonts.family = BiliFonts.system;
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(),
      routes: routes,
      builder: (context, child) => RepaintBoundary(
        key: shellScreen,
        child: AppScope(services: services, child: child!),
      ),
      home: MainShell(skin: skins),
    ),
  );
  return ShellRig(api: dynamicApi, http: http, gate: gate, services: services);
}

/// Lets answers land and frames run, without waiting on endless animations.
Future<void> settle(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
