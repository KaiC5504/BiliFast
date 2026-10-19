import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/playback/playback_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_player.dart';
import 'fakes.dart';

const bv = 'BV1GJ411x7h7';
const other = 'BV1AA411a1aa';

const onePartView = '{"code":0,"data":{"bvid":"$bv","aid":1,"title":"单P","owner":{"mid":1,"name":"UP"},'
    '"pages":[{"cid":137649199,"page":1,"part":"","duration":712}]}}';

const view =
    VideoView(bvid: bv, aid: 1, title: '单P', pages: [VideoPage(cid: 137649199, page: 1, part: '', duration: 712)]);

void main() {
  late CannedHttp http;
  late FakeTimers timers;
  late MemorySink logs;
  late PlaybackController controller;

  setUp(() {
    http = Canned.http()..errors[Canned.signedViewPath] = TimeoutException('no answer');
    timers = FakeTimers();
    logs = MemorySink();
    final now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 1000) * 1000);
    final logger = Logger(session: 'test')..add(logs);
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
  });

  tearDown(() => controller.dispose());

  final gaps = PlaybackController.detailRetryGaps;
  int asks() => http.to(Canned.signedViewPath).length;
  FakeTimer? retry(int attempt) => timers.activeWith(gaps[attempt]);

  /// Opens [bv] with its view only and lets every ask fail, the retries included.
  Future<void> openAndFail() async {
    await controller.openVideo(bv, cid: 137649199, view: view);
    await settle();
    for (var attempt = 0; attempt < gaps.length; attempt++) {
      retry(attempt)!.fire();
      await settle();
    }
  }

  test('the gaps are short and growing, and few', () {
    expect(gaps, [const Duration(seconds: 2), const Duration(seconds: 6)]);
  });

  test('a failed ask is retried after each gap in turn, then stops and says so', () async {
    var told = 0;
    controller.addListener(() => told += 1);
    await controller.openVideo(bv, cid: 137649199, view: view);
    await settle();
    expect(asks(), 1);
    expect(retry(0), isNotNull, reason: 'the first retry waits 2 s');
    expect(retry(1), isNull);
    expect(controller.detailFailed, isFalse, reason: 'retries are still to come');

    retry(0)!.fire();
    await settle();
    expect(asks(), 2);
    expect(retry(1), isNotNull, reason: 'the second waits 6 s');
    expect(controller.detailFailed, isFalse);

    final before = told;
    retry(1)!.fire();
    await settle();
    expect(asks(), 3);
    expect(retry(0), isNull);
    expect(retry(1), isNull, reason: 'no third retry');
    expect(controller.detailFailed, isTrue);
    expect(controller.detail, isNull);
    expect(told, greaterThan(before), reason: 'the page hears the failure');
    expect(controller.phase, isNot(PlaybackPhase.failed), reason: 'playback goes on without the detail');
  });

  test('a retry that succeeds fills the detail in and asks no more', () async {
    await controller.openVideo(bv, cid: 137649199, view: view);
    await settle();
    http.errors.remove(Canned.signedViewPath);
    http.routes[Canned.signedViewPath] = (200, onePartView);
    retry(0)!.fire();
    await settle();
    expect(controller.detail?.bvid, bv);
    expect(controller.detailFailed, isFalse);
    expect(retry(1), isNull);
    expect(asks(), 2);
  });

  test('a newer open or a close cancels the pending retry', () async {
    await controller.openVideo(bv, cid: 137649199, view: view);
    await settle();
    final pending = retry(0)!;
    await controller.openVideo(other);
    expect(pending.isActive, isFalse);
    pending.fire();
    await settle();
    expect(http.to(Canned.signedViewPath).where((call) => call.url.queryParameters['bvid'] == bv), hasLength(1));

    await controller.openVideo(bv, cid: 137649199, view: view);
    await settle();
    final second = retry(0)!;
    final before = asks();
    controller.close();
    expect(second.isActive, isFalse);
    second.fire();
    await settle();
    expect(asks(), before);
    expect(controller.detailFailed, isFalse);
  });

  test('an answer for an open that has gone starts no retry', () async {
    final gate = http.gates[Canned.signedViewPath] = Completer<void>();
    await controller.openVideo(bv, cid: 137649199, view: view);
    controller.close();
    gate.complete();
    await settle();
    expect(retry(0), isNull);
    expect(controller.detailFailed, isFalse);
  });

  test('retryDetail asks once more after the retries ran out, and only then', () async {
    controller.retryDetail();
    await controller.openVideo(bv, cid: 137649199, view: view);
    await settle();
    controller.retryDetail();
    await settle();
    expect(asks(), 1, reason: 'not while the automatic retries are still to come');

    retry(0)!.fire();
    await settle();
    retry(1)!.fire();
    await settle();
    expect(controller.detailFailed, isTrue);

    controller.retryDetail();
    expect(controller.detailFailed, isFalse, reason: 'the line goes while the ask is out');
    await settle();
    expect(asks(), 4);
    expect(controller.detailFailed, isTrue, reason: 'one ask, no retries of its own');
    expect(retry(0), isNull);
    expect(retry(1), isNull);

    http.errors.remove(Canned.signedViewPath);
    http.routes[Canned.signedViewPath] = (200, onePartView);
    controller.retryDetail();
    await settle();
    expect(asks(), 5);
    expect(controller.detail?.bvid, bv);
    expect(controller.detailFailed, isFalse);
    controller.retryDetail();
    await settle();
    expect(asks(), 5, reason: 'nothing to retry once the detail is in');
  });

  test('a return to the foreground asks once more for a detail that failed, and not otherwise', () async {
    await controller.openVideo(bv, cid: 137649199, view: view);
    await settle();
    await controller.appResumed();
    await settle();
    expect(asks(), 1, reason: 'the retries are still to come');

    retry(0)!.fire();
    await settle();
    retry(1)!.fire();
    await settle();
    expect(asks(), 3);

    await controller.appResumed();
    await settle();
    expect(asks(), 4);
    expect(controller.detailFailed, isTrue);
    expect(retry(0), isNull, reason: 'the resume asks once, with no retries');

    http.errors.remove(Canned.signedViewPath);
    http.routes[Canned.signedViewPath] = (200, onePartView);
    await controller.appResumed();
    await settle();
    expect(asks(), 5);
    expect(controller.detail?.bvid, bv);
    await controller.appResumed();
    await settle();
    expect(asks(), 5);
  });

  test('after the failure, a newer open forgets it', () async {
    await openAndFail();
    expect(controller.detailFailed, isTrue);
    await controller.openVideo(other);
    expect(controller.detailFailed, isFalse);
    controller.retryDetail();
    await settle();
    expect(http.to(Canned.signedViewPath).where((call) => call.url.queryParameters['bvid'] == bv), hasLength(3));
  });

  test('a detail for another video, or one that redirects, is dropped with a word in the log', () async {
    http.errors.remove(Canned.signedViewPath);
    http.routes[Canned.signedViewPath] = (200, onePartView.replaceFirst('"bvid":"$bv"', '"bvid":"$other"'));
    await controller.openVideo(bv, cid: 137649199, view: view);
    await settle();
    expect(controller.detail, isNull);
    expect(controller.detailFailed, isFalse, reason: 'asking again would get the same answer');
    expect(retry(0), isNull);
    final dropped = logs.events.where((event) => event.msg == 'detail dropped').toList();
    expect(dropped, hasLength(1));
    expect(dropped.single.level, LogLevel.info);
    expect(dropped.single.f['answered'], isA<LogString>().having((value) => value.value, 'value', other));

    http.routes[Canned.signedViewPath] =
        (200, onePartView.replaceFirst('"pages"', '"redirect_url":"https://www.bilibili.com/bangumi/play/ep1","pages"'));
    await controller.openVideo(bv, cid: 137649199, view: view);
    await settle();
    expect(controller.detail, isNull);
    expect(logs.events.where((event) => event.msg == 'detail dropped'), hasLength(2));
  });
}
