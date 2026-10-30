import 'dart:async';
import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart' show ManualClock;
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/route_observer.dart';
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/device/player_device.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/offline/fake_offline_library.dart';
import 'package:bilifast/offline/offline_models.dart';
import 'package:bilifast/offline/offline_route.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player_ui/panels/panel_layer.dart';
import 'package:bilifast/player_ui/seek_bar.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../playback/fakes.dart';
import '../support/fake_player.dart';
import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import '../video/mixed_lines.dart' show appTheme;

class _NoLogin implements LoginGate {
  @override
  Future<bool> request(BuildContext context) async => false;
}

/// The offline page as KaiC's iPhone draws it, under the system font, against 158 (one cached video, paused at
/// 00:20/06:23) and 159 (its ⋮ sheet), measured in px / 3. With BILIFAST_SHOTS naming a folder outside the repo, the
/// 3× shots are saved there for tools/screen_diff.py.
void main() {
  final item = OfflineItem(
    request: const OfflineRequest(
      bvid: 'BV1fake00003',
      aid: 9003,
      cid: 7003,
      title: '神枪看小羊崽复播：你看这次她真的自己打的，她表情会动',
      duration: 383,
      cover: '',
      ownerMid: 103,
      ownerName: '火播君',
    ),
    state: OfflineState.done,
    addedAt: DateTime(2026, 10, 30, 17, 12),
    quality: 80,
    qualityName: '1080P 高清',
    bytes: 82208358,
    totalBytes: 82208358,
    position: 20,
  );

  Future<void> render(WidgetTester tester, {required bool sheet}) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    final savedPrefs = PlayerPrefs.shared;
    PlayerPrefs.shared = PlayerPrefs.memory();
    addTearDown(() => PlayerPrefs.shared = savedPrefs);
    await tester.runAsync(loadSystemFontStandIns);
    await tester.runAsync(loadIconFonts);
    await tester.runAsync(SeekBar.precache);
    showAsPhone(tester);
    BiliFonts.family = BiliFonts.system;

    final http = Canned.http();
    final logger = Logger(session: 'test');
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: http,
      logger: logger,
    );
    await environment.refreshAccount();
    final players = <FakePlayer>[];
    final playback = AppPlayback(() async {
      final player = FakePlayer();
      players.add(player);
      return PlaybackController(
        client: environment.client,
        engine: FakeEngine(),
        player: player,
        clock: ManualClock(10000).clock,
        startTimer: FakeTimers().start,
        logger: logger,
      );
    });
    addTearDown(playback.dispose);
    final library = FakeOfflineLibrary(items: [item]);
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      device: PlayerDevice(orientation: OrientationController(), controls: NoDeviceControls()),
      loginGate: _NoLogin(),
      pageApi: FakePageApi(),
      offline: library,
    );
    // The services' font store puts its own choice in place.
    BiliFonts.family = BiliFonts.system;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        navigatorKey: services.navigator,
        navigatorObservers: [pageRoutes],
        builder: (context, child) => RepaintBoundary(
          key: const ValueKey('screen'),
          // Still, so the bars stand as 160 caught them and the sheet is in at once.
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: AppScope(services: services, child: child!),
          ),
        ),
        home: const SizedBox(),
      ),
    );
    unawaited(openOfflinePage(services.navigator.currentContext!, item));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    players.single
      ..emit(const DurationChanged(383))
      ..emit(const StatusChanged(PlayerStatus.playing))
      ..emit(const PositionChanged(seconds: 20, hostMs: 0, rate: 1))
      ..emit(const StatusChanged(PlayerStatus.paused));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    tester.widget<PanelLayer>(find.byType(PanelLayer)).ui.chrome.show();
    await tester.pump(const Duration(milliseconds: 400));
    if (sheet) {
      await tester.tap(find.byKey(const ValueKey('offline-row-more')));
      await tester.pump(const Duration(milliseconds: 400));
    }
    final shots = Platform.environment['BILIFAST_SHOTS'];
    if (shots != null) {
      await saveShot(tester, find.byKey(const ValueKey('screen')), '$shots/offline-${sheet ? '159' : '158'}.png');
    }
  }

  Rect rectOf(WidgetTester tester, String key) => tester.getRect(find.byKey(ValueKey(key)));

  testWidgets('158: the band, the row and the footer where the official page has them', (tester) async {
    await render(tester, sheet: false);
    expect(find.text('（1个视频）'), findsOneWidget);
    // The player ends at 309.67; the band's capsule spans 316.67-346.67, border to border, ending at x 428.
    final capsule = rectOf(tester, 'danmaku-capsule');
    expect(capsule.top, closeTo(316.67, 0.01));
    expect(capsule.bottom, closeTo(346.67, 0.01));
    expect(capsule.right, closeTo(428, 0.5));
    // The cover: 12-147 across, 363.67-439.67 down.
    final cover = tester.getRect(
      find.ancestor(of: find.byKey(const ValueKey('offline-row-duration')), matching: find.byType(ClipRRect)).first,
    );
    expect(cover.left, closeTo(12, 0.34));
    expect(cover.right, closeTo(147, 0.34));
    expect(cover.top, closeTo(363.67, 0.34));
    expect(cover.bottom, closeTo(439.67, 0.34));
    expect(find.text('78.4M'), findsOneWidget);
    expect(find.text('06:23'), findsOneWidget);
    expect(find.byKey(const ValueKey('portrait-vertical')), findsNothing);
  });

  testWidgets('159: the sheet over the dimmed page, 查看详情页 and 取消', (tester) async {
    await render(tester, sheet: true);
    final sheet = rectOf(tester, 'offline-sheet');
    // 查看详情页 812-862, the band to 867, 取消 to 922, the home indicator's 34 under it.
    expect(sheet.top, closeTo(812, 0.5));
    expect(sheet.bottom, 956);
    expect(rectOf(tester, 'offline-sheet-details').height, closeTo(50, 0.01));
    expect(rectOf(tester, 'offline-sheet-cancel').top, closeTo(867, 0.5));
    expect(rectOf(tester, 'offline-sheet-cancel').bottom, closeTo(922, 0.5));
  });
}
