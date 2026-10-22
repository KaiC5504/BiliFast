import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/route_observer.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/me/fake_me_api.dart';
import 'package:bilifast/me/me_model.dart';
import 'package:bilifast/me/me_page.dart';
import 'package:bilifast/settings/font_store.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/space/fake_space_api.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';

/// 87's account: KaiC5504, LV5, 年度大会员, B币 2.3 and 硬币 878, wearing a frame.
const kaiProfile = MeProfile(
  mid: 2233,
  name: 'KaiC5504',
  face: '',
  pendant: 'https://i0.hdslb.com/bfs/garb/item/pendant.png',
  level: 5,
  coins: 878,
  bcoin: 2.3,
  vip: true,
  vipLabel: '年度大会员',
  vipBadge: true,
);

const kaiCounts = MeCounts(dynamics: 0, following: 13, followers: 0);

/// A model showing whatever [view] the test sets, counting showings and pulls.
class FixedMeModel extends MeModel {
  FixedMeModel(this._view, {required super.api, required super.environment});

  MeView _view;
  int showings = 0;
  int refreshes = 0;

  /// What the pull answers: null on success, else the message to toast.
  String? refreshAnswer;

  /// Holds the pull's answer until completed.
  Completer<void>? refreshGate;

  @override
  MeView get view => _view;

  set view(MeView next) {
    _view = next;
    notifyListeners();
  }

  @override
  void shown() => showings++;

  @override
  Future<String?> refresh() async {
    refreshes++;
    await refreshGate?.future;
    return refreshAnswer;
  }
}

/// What a test of 我的 holds on to.
class MeHarness {
  MeHarness({required this.model, required this.services, required this.opened, required this.active});

  final FixedMeModel model;
  final AppServices services;

  /// Whether 我的 is the bar's current tab.
  final ValueNotifier<bool> active;

  /// The links the page asked to open outside the app.
  final List<Uri> opened;
}

/// 我的 above a 83 pt stand-in for the bottom bar, as MainShell lays it out (the page's bottom padding taken off), on
/// KaiC's iPhone at [pixelRatio]; wrapped in a RepaintBoundary keyed `screen`.
Future<MeHarness> showMe(
  WidgetTester tester, {
  MeView view = const MeShown(kaiProfile, kaiCounts),
  bool active = true,
  LoginGate? loginGate,
  double pixelRatio = 1,
  ThemeData? theme,
  FontStore? fonts,
  bool openSucceeds = true,
  WidgetBuilder? developerPage,
}) async {
  tester.view
    ..physicalSize = const Size(440, 956) * pixelRatio
    ..devicePixelRatio = pixelRatio
    ..padding = FakeViewPadding(top: 62 * pixelRatio, bottom: 34 * pixelRatio)
    ..viewPadding = FakeViewPadding(top: 62 * pixelRatio, bottom: 34 * pixelRatio);
  addTearDown(tester.view.reset);
  final logger = Logger(session: 'test');
  final environment = await AppEnvironment.load(
    keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
    http: Canned.http(),
    logger: logger,
  );
  final model = FixedMeModel(view, api: FakeMeApi.demo(), environment: environment);
  addTearDown(model.dispose);
  final playback = AppPlayback(() => throw StateError('no playback here'));
  addTearDown(playback.dispose);
  final services = AppServices(
    environment: environment,
    playback: playback,
    recents: await RecentStore.load(null, logger: logger),
    fonts: fonts ?? FontStore.memory(),
    loginGate: loginGate,
    pageApi: FakePageApi(),
    spaceApi: FakeSpaceApi(),
    meApi: FakeMeApi.demo(),
  );
  final shownTab = ValueNotifier(active);
  addTearDown(shownTab.dispose);
  final opened = <Uri>[];
  Future<bool> open(Uri link) async {
    opened.add(link);
    return openSucceeds;
  }

  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      navigatorObservers: [pageRoutes],
      builder: (context, child) => RepaintBoundary(
        key: const ValueKey('screen'),
        child: AppScope(services: services, child: child!),
      ),
      home: Scaffold(
        backgroundColor: MeTheme.background,
        body: Column(
          children: [
            Expanded(
              child: ValueListenableBuilder(
                valueListenable: shownTab,
                builder: (context, active, _) => MediaQuery.removePadding(
                  context: context,
                  removeBottom: true,
                  child: MePage(active: active, developerPage: developerPage, model: model, openLink: open),
                ),
              ),
            ),
            const SizedBox(height: 83),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
  return MeHarness(model: model, services: services, opened: opened, active: shownTab);
}
