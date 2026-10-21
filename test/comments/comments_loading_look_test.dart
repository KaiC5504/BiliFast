import 'dart:async';
import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart' show ManualClock;
import 'package:bilifast/account/keychain_store.dart';
import 'package:bilifast/account/login_gate.dart';
import 'package:bilifast/app/app_environment.dart';
import 'package:bilifast/app/app_scope.dart';
import 'package:bilifast/app/phone_frame.dart';
import 'package:bilifast/app/route_observer.dart';
import 'package:bilifast/app/swipe_back_route.dart';
import 'package:bilifast/comments/comments_tab.dart';
import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation.dart';
import 'package:bilifast/device/player_device.dart';
import 'package:bilifast/home/recent_store.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/shared/loading_tv.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:bilifast/video/fake_page_api.dart';
import 'package:bilifast/video/page_session.dart' show SessionOpen;
import 'package:bilifast/video/page_tabs.dart';
import 'package:bilifast/video/player_session.dart';
import 'package:bilifast/video/video_page.dart';
import 'package:bilifast/video/video_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../app/fake_keychain.dart';
import '../device/fake_orientation_host.dart' show FakeOrientationHost;
import '../playback/fakes.dart';
import '../support/fake_player.dart';
import '../support/fake_player_session.dart';
import '../support/fake_video_actions.dart';
import '../support/look_alike.dart';
import '../support/stand_in_fonts.dart';
import '../video/mixed_lines.dart' show appTheme;

class _NoLogin implements LoginGate {
  @override
  Future<bool> request(BuildContext context) async => false;
}

/// 评论's first load on the video page as KaiC's iPhone draws it, under the system font, against 64 (0.5 s before the
/// page's detail, 1.0 s after). With BILIFAST_SHOTS naming a folder outside the repo, the 3× shots are saved there for
/// tools/screen_diff.py.
void main() {
  testWidgets('评论 loading: the TV before the aid is known, then over what is left above the write bar', (tester) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    await tester.runAsync(loadSystemFontStandIns);
    showAsPhone(tester);

    final orientation = OrientationController(host: FakeOrientationHost());
    final logger = Logger(session: 'test');
    final environment = await AppEnvironment.load(
      keychain: FakeKeychain(const StoredCookies(Canned.cookies)),
      http: Canned.http(),
      logger: logger,
    );
    final player = FakePlayer();
    final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
    final controller = PlaybackController(
      client: environment.client,
      engine: FakeEngine(),
      player: player,
      clock: ManualClock(10000).clock,
      now: () => now,
      startTimer: FakeTimers().start,
      logger: logger,
    );
    // Held, so the page knows no aid yet.
    final started = Completer<PlaybackController>();
    final playback = AppPlayback(() => started.future);
    addTearDown(playback.dispose);
    final held = Completer<void>();
    final api = FakePageApi()..holds['comments'] = held;
    final services = AppServices(
      environment: environment,
      playback: playback,
      recents: await RecentStore.load(null, logger: logger),
      device: PlayerDevice(orientation: orientation, controls: NoDeviceControls()),
      loginGate: _NoLogin(),
      pageApi: api,
    );
    BiliFonts.family = BiliFonts.system;

    final sessions = <FakePlayerSession>[];
    PlayerSession session({
      required PlaybackController controller,
      required AppServices services,
      required SessionOpen open,
      required void Function(double seconds) onSeeked,
      required VoidCallback requestLogin,
      required VoidCallback willPlay,
    }) {
      final made = FakePlayerSession(player: player);
      sessions.add(made);
      return made;
    }

    final nav = GlobalKey<NavigatorState>();
    const screen = ValueKey('screen');
    await tester.pumpWidget(
      RepaintBoundary(
        key: screen,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(),
          navigatorKey: nav,
          navigatorObservers: [pageRoutes],
          builder: (context, child) => AppScope(services: services, child: child!),
          home: const SizedBox(),
        ),
      ),
    );
    unawaited(
      nav.currentState!.push(
        SwipeBackPageRoute<void>(
          builder: (_) => VideoPage(
            route: const VideoRoute(bvid: 'BV1GJ411x7h7', cid: 137649199, start: 0),
            createSession: session,
            createDetails: ({
              required session,
              required services,
              required toast,
              required requestLogin,
              required logins,
            }) => FakePageDetails(),
          ),
        ),
      ),
    );
    Future<void> frames(int count) async {
      for (var i = 0; i < count; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await frames(20);
    await tester.tap(find.byKey(const ValueKey('tab-comments')));
    await frames(20);
    final shots = Platform.environment['BILIFAST_SHOTS'];
    // Asset decoding needs real async; without it the shot has no faces.
    await tester.runAsync(() => LoadingTv.precache(tester.element(find.byType(LoadingTv))));
    await frames(2);

    final tabs = tester.getRect(find.byType(PageTabRow));
    expect(find.byType(CommentsSlot), findsOneWidget);
    final slot = tester.getRect(find.byKey(const ValueKey('comments-slot-loading')));
    // 64 at 0.5 s: centred in a box as tall as the list, which is laid out as if the player were already the bar.
    final list = tester.getRect(find.byType(CommentsSlot));
    expect(list.bottom, PhoneFrame.portrait.height);
    expect(slot.center.dy, moreOrLessEquals(tabs.bottom + list.height / 2, epsilon: 0.01));
    if (shots != null) await saveShot(tester, find.byKey(screen), '$shots/64-slot-ours.png');

    started.complete(controller);
    await frames(20);
    sessions.single
      ..video = controller.video
      ..isVertical = false
      ..changed();
    await frames(10);
    expect(find.byType(CommentsTab), findsOneWidget);
    expect(api.calls, contains(startsWith('comments ')));
    final tv = tester.getRect(find.byType(LoadingTvState));
    final bar = tester.getRect(find.byKey(const ValueKey('comment-bar')));
    expect(tv.center.dy, moreOrLessEquals((tabs.bottom + bar.top) / 2, epsilon: 0.01));
    final face = tester.getRect(find.byType(LoadingTv));
    expect(face.size, const Size.square(LoadingTvTheme.size));
    expect(face.center.dx, 220);
    if (shots != null) await saveShot(tester, find.byKey(screen), '$shots/64-first-ours.png');

    held.complete();
    await frames(10);
    expect(find.byType(LoadingTvState), findsNothing);
    nav.currentState!.pop();
    await frames(20);
  });
}
