import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:bilifast/video/collapsing_player.dart';
import 'package:bilifast/video/intro/intro_tab.dart';
import 'package:bilifast/video/intro/uploader_row.dart';
import 'package:bilifast/video/page_session.dart';
import 'package:bilifast/video/player_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../playback/fakes.dart';
import '../../support/fake_player.dart';
import '../../support/fake_player_session.dart';
import '../../support/fake_video_actions.dart';

const bv = 'BV1GJ411x7h7';
const retryLabel = '加载失败，点击重试';

const onePartView = '{"code":0,"data":{"bvid":"$bv","aid":1,"title":"单P","owner":{"mid":1,"name":"UP"},'
    '"pages":[{"cid":137649199,"page":1,"part":"","duration":712}]}}';

VideoDetail detail() => const VideoDetail(
  bvid: bv,
  aid: 1,
  title: '单P',
  cover: '',
  pubdate: 0,
  duration: 712,
  desc: '',
  descParts: [],
  copyright: 1,
  owner: VideoOwner(mid: 1, name: 'UP', face: ''),
  stat: VideoStat(view: 1, danmaku: 0, reply: 0, favorite: 0, coin: 0, share: 0, like: 0),
  pages: [],
  season: null,
  staff: [],
  width: 1920,
  height: 1080,
  honor: null,
  redirectURL: null,
);

void main() {
  group('the retry line', () {
    late FakePageDetails details;
    late int retries;

    setUp(() {
      details = FakePageDetails();
      retries = 0;
    });

    tearDown(() => details.dispose());

    Future<void> host(WidgetTester tester, IntroContent content) async {
      tester.view.physicalSize = const Size(440, 956);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(440, 956), padding: EdgeInsets.only(bottom: 34)),
            child: Scaffold(
              body: PlayerReserve(
                height: 300,
                child: IntroTab(
                  content: content,
                  details: details,
                  onSeek: (_) {},
                  onOpenVideo: (_) {},
                  onPlayEpisode: (_) {},
                  onOpenEpisodes: () {},
                  onOpenRelated: (_) {},
                  onWatchLater: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
    }

    void retry() => retries += 1;
    final line = find.byKey(const ValueKey('intro-retry'));

    testWidgets('shows only once the detail failed, centred below the player, and a tap asks again', (tester) async {
      await host(tester, IntroContent(onRetryDetail: retry));
      expect(line, findsNothing, reason: 'still waiting: nothing shows');

      await host(tester, IntroContent(detailFailed: true, onRetryDetail: retry));
      expect(line, findsOneWidget);
      expect(find.text(retryLabel, findRichText: true), findsOneWidget);
      final centre = tester.getCenter(find.text(retryLabel, findRichText: true));
      expect(centre.dx, moreOrLessEquals(220, epsilon: 1));
      expect(centre.dy, greaterThan(300), reason: 'below the player');

      await tester.tap(line);
      expect(retries, 1);
    });

    testWidgets('answers an accessibility press', (tester) async {
      final semantics = tester.ensureSemantics();
      await host(tester, IntroContent(detailFailed: true, onRetryDetail: retry));
      tester.semantics.tap(find.semantics.byLabel(retryLabel));
      expect(retries, 1);
      semantics.dispose();
    });

    testWidgets('gives way to the detail when a retry brings it', (tester) async {
      await host(tester, IntroContent(detailFailed: true, onRetryDetail: retry));
      expect(line, findsOneWidget);
      await host(tester, IntroContent(detail: detail(), onRetryDetail: retry));
      expect(line, findsNothing);
      expect(find.byType(UploaderRow, skipOffstage: false), findsOneWidget);
    });
  });

  group('IntroContent.of', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    late CannedHttp http;
    late FakeTimers timers;
    late PlaybackController controller;
    late PagePlayerSession session;

    setUp(() {
      http = Canned.http()
        ..errors[Canned.signedViewPath] = TimeoutException('no answer')
        ..routes['/x/web-interface/archive/related'] = (200, '{"code":0,"data":[]}');
      timers = FakeTimers();
      final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
      final logger = Logger(session: 'test');
      final client = BiliClient(transport: http, cookies: CookieJar(Canned.cookies), now: () => now, logger: logger);
      controller = PlaybackController(
        client: client,
        engine: FakeEngine(),
        player: FakePlayer(),
        clock: ManualClock(10000).clock,
        now: () => now,
        startTimer: timers.start,
        logger: logger,
      );
      session = PagePlayerSession(
        controller: controller,
        client: client,
        open: (bvid, {cid}) {},
        isVip: () => false,
        isLoggedIn: () => true,
        requestLogin: () {},
        prefs: PlayerPrefs.memory(),
        clock: ManualClock(10000).clock,
        periodic: (_, _) => FakeTimer(Duration.zero, () {}),
        startTimer: FakeTimers().start,
        logger: logger,
      );
    });

    tearDown(() {
      session.dispose();
      controller.dispose();
    });

    test("carries the page session's failure and its retry, which fills the detail in", () async {
      const view =
          VideoView(bvid: bv, aid: 1, title: '单P', pages: [VideoPage(cid: 137649199, page: 1, part: '', duration: 712)]);
      final seen = <IntroContent>[];
      session.addListener(() => seen.add(IntroContent.of(session)));
      await controller.openVideo(bv, cid: 137649199, view: view);
      await settle();
      expect(IntroContent.of(session).detailFailed, isFalse);
      for (final gap in PlaybackController.detailRetryGaps) {
        timers.activeWith(gap)!.fire();
        await settle();
      }
      final failed = IntroContent.of(session);
      expect(failed.detailFailed, isTrue);
      expect(failed.detail, isNull);
      expect(seen.last, failed, reason: 'the page hears the change and rebuilds 简介');
      expect(IntroContent.of(session), failed, reason: 'the same state compares equal, so no needless rebuild');

      http.errors.remove(Canned.signedViewPath);
      http.routes[Canned.signedViewPath] = (200, onePartView);
      failed.onRetryDetail!();
      await settle();
      final filled = IntroContent.of(session);
      expect(filled.detail?.bvid, bv);
      expect(filled.detailFailed, isFalse);
      expect(seen.last, filled);
    });

    test('a session without the controller behind it offers no retry', () {
      final fake = FakePlayerSession();
      addTearDown(fake.dispose);
      final content = IntroContent.of(fake);
      expect(content.detailFailed, isFalse);
      expect(content.onRetryDetail, isNull);
    });
  });
}
