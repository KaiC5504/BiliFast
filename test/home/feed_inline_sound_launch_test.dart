import 'package:bili_core/devlog.dart';
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/home/feed_big_card.dart';
import 'package:bilifast/home/feed_inline_player.dart';
import 'package:bilifast/home/home_page.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import 'feed_fakes.dart';

// The notifier takes 大卡默认声音 on its first read, so nothing else in this file may read it first.
void main() {
  testWidgets('首页 takes 大卡默认声音 at launch, so 设置 changing it before any big card shows waits for the next', (
    tester,
  ) async {
    final launched = PlayerPrefs.shared;
    addTearDown(() => PlayerPrefs.shared = launched);
    PlayerPrefs.shared = PlayerPrefs.memory()..bigCardSound = true;
    HomePage.feedPages = (index) async => const [];
    HomePage.precacheBigCover = (context, url, size) async => true;
    addTearDown(() {
      HomePage.feedPages = null;
      HomePage.precacheBigCover = FeedBigCardView.precacheCover;
      FeedInlineChoices.reset();
    });
    final logger = Logger(session: 'test');
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(StoredCookies(Canned.cookies)),
      http: FeedHttp(),
      logger: logger,
    );
    final playback = AppPlayback(() async => throw StateError('no player here'));
    addTearDown(playback.dispose);
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppScope(services: services, child: child!),
        home: const HomePage(),
      ),
    );
    await tester.pump();
    PlayerPrefs.shared.bigCardSound = false;
    expect(FeedInlineChoices.sound.value, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  });
}
