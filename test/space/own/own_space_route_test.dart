import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/favourites/fake_favourites_api.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/space/fake_space_api.dart';
import 'package:bilifast/space/own/own_space_page.dart';
import 'package:bilifast/space/space_page.dart';
import 'package:bilifast/space/space_route.dart';
import 'package:bilifast/space/uploader_tap.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/fake_keychain.dart';
import '../../playback/fakes.dart';

/// The canned nav's account.
const _mid = 12345;

void main() {
  testWidgets('the account\'s mid opens its own space, anyone\'s once logged out, and its own again after a login', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(440, 956)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: 62, bottom: 34)
      ..viewPadding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    final logger = Logger(session: 'test');
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: Canned.http(),
      logger: logger,
    );
    await environment.refreshAccount();
    expect(environment.mid, _mid);
    final playback = AppPlayback(() => Completer<PlaybackController>().future);
    addTearDown(playback.dispose);
    final space = FakeSpaceApi(ownMid: _mid);
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      pageApi: FakePageApi(),
      spaceApi: space,
      favouritesApi: FakeFavouritesApi(),
    );
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => AppScope(services: services, child: child!),
        home: Builder(
          builder: (context) => GestureDetector(
            onTap: () => unawaited(openSpace(context, const UploaderRef(mid: _mid, name: '测试用户', face: ''))),
            child: const Text('home'),
          ),
        ),
      ),
    );

    Future<void> frames([int count = 20]) async {
      for (var i = 0; i < count; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> openSpaceOfMid() async {
      await tester.tap(find.text('home'));
      await frames();
    }

    Future<void> back() async {
      navigator.currentState!.pop();
      await frames();
      expect(find.byType(OwnSpacePage), findsNothing);
      expect(find.byType(SpacePage), findsNothing);
    }

    await openSpaceOfMid();
    expect(find.byType(OwnSpacePage), findsOneWidget);
    expect(space.calls, ['ownProfile mid=$_mid']);
    await back();

    try {
      await environment.logout();
    } on LogoutIncomplete catch (_) {}
    await frames();
    expect(environment.mid, isNull);
    var asked = space.calls.length;
    await openSpaceOfMid();
    expect(find.byType(SpacePage), findsOneWidget);
    expect(find.byType(OwnSpacePage), findsNothing);
    expect(space.calls.skip(asked).first, 'profile mid=$_mid');
    expect(space.calls.skip(asked), isNot(contains('ownProfile mid=$_mid')));
    await back();

    expect(await environment.didLogin(Canned.cookies), isTrue);
    await frames();
    expect(environment.mid, _mid);
    asked = space.calls.length;
    await openSpaceOfMid();
    expect(find.byType(OwnSpacePage), findsOneWidget);
    expect(space.calls.skip(asked), ['ownProfile mid=$_mid']);
    await back();
  });
}
