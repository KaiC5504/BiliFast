import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/space/fake_space_api.dart';
import 'package:bilifast/space/space_page.dart';
import 'package:bilifast/space/uploader_tap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';

/// [home] at the top left of the app at the iPhone's size, with a navigator and the services UP主空间 reaches, its
/// calls answered by [FakeSpaceApi], so whatever [home] opens can be found as a [SpacePage].
Future<void> pumpSpaceHost(WidgetTester tester, Widget home) async {
  tester.view
    ..physicalSize = const Size(440, 956)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final logger = Logger(session: 'test');
  final environment = await AppEnvironment.load(
    keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
    http: Canned.http(),
    logger: logger,
  );
  final playback = AppPlayback(() => Completer<PlaybackController>().future);
  addTearDown(playback.dispose);
  final services = AppServices(
    environment: environment,
    playback: playback,
    recents: await RecentStore.load(null, logger: logger),
    spaceApi: FakeSpaceApi.demo(),
  );
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => AppScope(services: services, child: child!),
      home: Align(alignment: Alignment.topLeft, child: home),
    ),
  );
  await tester.pump();
}

/// Lets a pushed space's route come in, without waiting for a page that may keep animating.
Future<void> pumpRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// The uploader each open [SpacePage] shows, bottom first.
List<UploaderRef> openSpaces(WidgetTester tester) => tester
    .widgetList<SpacePage>(find.byType(SpacePage, skipOffstage: false))
    .map((page) => page.uploader)
    .toList();

/// Pops the space on top, back to [home].
Future<void> closeSpace(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator)).pop();
  await pumpRoute(tester);
}
