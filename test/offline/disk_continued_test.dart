import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/offline/disk/background_trials.dart';
import 'package:bilifast/offline/offline_host.dart';
import 'package:bilifast/offline/offline_library.dart';
import 'package:bilifast/offline/offline_models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';
import 'disk_test_support.dart';

const cid = 137649199;
const mib = 1 << 20;

/// iOS's continued processing (the engine kept running away under a Live Activity) and the trials that pick how
/// downloads go on while the app is away.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Rig rig;

  setUp(() => rig = Rig(host: FakeOfflineHost()..continuedProcessing = true));

  tearDown(() {
    rig.dispose();
    if (TestWidgetsFlutterBinding.instance.lifecycleState case final state? when state != AppLifecycleState.resumed) {
      lifecycle(toForeground);
    }
  });

  Iterable<LogEvent> logged(String msg) => rig.logs.events.where((event) => event.msg == msg);

  Iterable<LogEvent> continued(String event) =>
      logged('offline continued').where((line) => line.f['event']?.toJson() == event);

  String trialsPath() => '${rig.folder}${Platform.pathSeparator}trials.json';

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 400 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(done(), isTrue);
  }

  DownloadProgress progress(int cid, int bytes) =>
      DownloadProgress('$cid', videoBytes: bytes, audioBytes: 0, videoTotal: 40 * mib, audioTotal: mib, bps: 0);

  DownloadGaps gaps(int cid, {int from = 0}) => DownloadGaps(
    id: '$cid',
    video: [ByteRange(from, 40 * mib - 1)],
    audio: [ByteRange(0, mib - 1)],
    videoTotal: 40 * mib,
    audioTotal: mib,
  );

  /// A library with [parts] enqueued and the continued processing their enqueue asked for running.
  Future<DiskOfflineLibrary> running(List<OfflineRequest> parts) async {
    final library = await rig.started();
    await library.enqueue(parts);
    await library.settled();
    rig.host.continuedStarted!();
    await library.settled();
    return library;
  }

  group('asking', () {
    test('downloads the user adds ask iOS for continued processing once, titled 离线缓存', () async {
      final library = await rig.started();
      expect(rig.host.calls, isNot(contains('beginContinued')), reason: 'nothing to download at launch');

      await library.enqueue([offlineRequest(cid: 1, title: '第一个')]);
      await library.settled();
      expect(rig.host.continuedBegun, [(title: '离线缓存', subtitle: '第一个')]);

      await library.enqueue([offlineRequest(cid: 2), offlineRequest(cid: 3)]);
      await library.settled();
      expect(rig.host.continuedBegun, hasLength(1), reason: 'one request at a time');
      expect(continued('asked').single.f['why']?.toJson(), 'enqueue');
    });

    test('resume, 全部开始, the return and a launch each ask once; a refusal is logged and leaves nothing out', () async {
      rig.host.continuedRefusal = 'busy';
      final library = await rig.started();
      await library.enqueue([offlineRequest()]);
      await library.settled();
      library
        ..pause(cid)
        ..resume(cid);
      await library.settled();
      library
        ..pause(cid)
        ..startAll();
      await library.settled();
      rig.engine.gaps['$cid'] = gaps(cid);
      lifecycle(toBackground);
      await library.settled();
      lifecycle(toForeground);
      await library.settled();
      rig.close(library);
      await rig.started();

      expect(continued('asked').map((line) => line.f['why']?.toJson()), [
        'enqueue',
        'resume',
        'startAll',
        'return',
        'launch',
      ]);
      expect(continued('refused').map((line) => line.f['reason']?.toJson()), everyElement('busy'));
      expect(continued('refused'), hasLength(5));
      expect(rig.host.calls.where((call) => call.startsWith('endContinued')), isEmpty);
    });

    test('without continued processing nothing is asked', () async {
      rig.host.continuedProcessing = false;
      final library = await rig.started();
      await library.enqueue([offlineRequest()]);
      await library.settled();
      expect(rig.host.calls, isNot(contains('beginContinued')));
      expect(logged('offline continued'), isEmpty);
    });

    test('a request iOS does not start within the wait is withdrawn, and a start after it is ended at once', () async {
      rig.continuedStartWait = const Duration(milliseconds: 20);
      final library = await rig.started();
      await library.enqueue([offlineRequest()]);
      await library.settled();

      await until(() => continued('not started').isNotEmpty);
      expect(continued('not started').single.f['why']?.toJson(), 'enqueue');
      expect(rig.host.calls.where((call) => call.startsWith('endContinued')), ['endContinued false']);

      rig.host.continuedStarted!();
      await library.settled();
      expect(continued('started').single.f['kept']?.toJson(), isFalse);
      expect(rig.host.calls.last, 'endContinued true');
      expect(rig.host.continuedUpdates, isEmpty);

      library
        ..pause(cid)
        ..resume(cid);
      await library.settled();
      expect(rig.host.continuedBegun, hasLength(2), reason: 'the next action asks again');
    });

    test('a request that throws is logged as failed and the next action asks again', () async {
      rig.host.continuedError = StateError('no scheduler');
      final library = await rig.started();
      await library.enqueue([offlineRequest()]);
      await library.settled();
      expect(continued('failed').single.f['reason']?.toJson(), 'no scheduler');

      rig.host.continuedError = null;
      library
        ..pause(cid)
        ..resume(cid);
      await library.settled();
      expect(rig.host.continuedBegun, hasLength(2));
    });

    test('Control Center while the request waits: the return asks nothing more and the start is kept', () async {
      final library = await rig.started();
      await library.enqueue([offlineRequest()]);
      await library.settled();
      rig.engine.gaps['$cid'] = gaps(cid);

      lifecycle([AppLifecycleState.inactive]);
      await library.settled();
      expect(logged('offline away').single.f['continued']?.toJson(), 'asking');
      expect(rig.host.calls, isNot(contains('endContinued true')), reason: 'the request is left waiting');
      lifecycle([AppLifecycleState.resumed]);
      await library.settled();
      expect(rig.host.continuedBegun, hasLength(1));

      rig.host.continuedStarted!();
      await library.settled();
      expect(continued('started').single.f['kept'], isNull);
      expect(rig.host.continuedUpdates, isNotEmpty);
    });

    test('a start that comes while away on a hand-off is ended at once; the return asks again', () async {
      final library = await rig.started();
      await library.enqueue([offlineRequest()]);
      await library.settled();
      rig.engine.gaps['$cid'] = gaps(cid);
      lifecycle(toBackground);
      await library.settled();
      expect(rig.host.handedOff, hasLength(1));

      rig.host.continuedStarted!();
      await library.settled();
      expect(continued('started').single.f['kept']?.toJson(), isFalse);
      expect(rig.host.calls.last, 'endContinued true');

      lifecycle(toForeground);
      await library.settled();
      expect(rig.host.continuedBegun, hasLength(2));
      expect(continued('asked').last.f['why']?.toJson(), 'return');
    });
  });

  group('running', () {
    test('the Live Activity hears the progress when it moves: the one video left by name, more by count', () async {
      rig.continuedUpdateGap = const Duration(milliseconds: 10);
      final library = await running([offlineRequest(cid: 1, title: '第一个'), offlineRequest(cid: 2, title: '第二个')]);
      expect(rig.host.continuedUpdates.first, (done: 0, total: 0, subtitle: '还剩 2 个视频'));
      expect(continued('started').single.f['why']?.toJson(), 'enqueue');

      rig.engine.downloadController.add(progress(1, 3 * mib));
      await until(() => rig.host.continuedUpdates.last.done == 3 * mib);
      expect(rig.host.continuedUpdates.last, (done: 3 * mib, total: 41 * mib, subtitle: '还剩 2 个视频'));

      rig.engine.downloadController.add(const DownloadFinished('1', videoTotal: 40 * mib, audioTotal: mib));
      await library.settled();
      await until(() => rig.host.continuedUpdates.last.subtitle == '第二个');
      expect(rig.host.continuedUpdates.last, (done: 41 * mib, total: 41 * mib, subtitle: '第二个'));

      final sent = rig.host.continuedUpdates.length;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(rig.host.continuedUpdates, hasLength(sent), reason: 'nothing moved');
      expect(rig.logText, isNot(contains('第二个')));
    });

    test('a part added while it runs joins the task; a deleted one drops out', () async {
      rig.continuedUpdateGap = const Duration(milliseconds: 10);
      final library = await running([offlineRequest(cid: 1)]);
      await library.enqueue([offlineRequest(cid: 2), offlineRequest(cid: 3)]);
      await library.settled();
      await until(() => rig.host.continuedUpdates.last.subtitle == '还剩 3 个视频');
      expect(rig.host.continuedBegun, hasLength(1));

      await library.delete([3]);
      await until(() => rig.host.continuedUpdates.last.subtitle == '还剩 2 个视频');
    });

    test('the task completes once the last part finishes, after its entry is written', () async {
      final library = await running([offlineRequest()]);
      String? stateAtEnd;
      rig.host.endingContinued = () => stateAtEnd = rig.entry(cid)['state'] as String?;
      rig.now = rig.now.add(const Duration(seconds: 90));

      rig.engine.downloadController.add(const DownloadFinished('$cid', videoTotal: 1000, audioTotal: 100));
      await library.settled();

      expect(rig.host.calls.last, 'endContinued true');
      expect(stateAtEnd, 'done');
      final completed = continued('completed').single;
      expect(completed.f['success']?.toJson(), isTrue);
      expect(completed.f['secs']?.toJson(), 90.0);
    });

    test('a part that fails ends the task as failed', () async {
      final library = await running([offlineRequest()]);
      rig.engine.downloadController.add(const DownloadFailed('$cid', failure: DownloadFailure.network));
      await library.settled();
      expect(rig.host.calls.last, 'endContinued false');
      expect(continued('completed').single.f['success']?.toJson(), isFalse);
    });

    test('全部暂停 ends the task as a success; a pause with work left does not', () async {
      final library = await running([offlineRequest(cid: 1), offlineRequest(cid: 2)]);
      library.pause(2);
      await library.settled();
      expect(rig.host.calls, isNot(contains('endContinued true')));

      library.pauseAll();
      await library.settled();
      expect(rig.host.calls.last, 'endContinued true');
      expect(continued('completed').single.f['success']?.toJson(), isTrue);
    });

    test('ended in the foreground, downloads go on and nothing asks again until the next action', () async {
      final library = await running([offlineRequest()]);
      rig.host.continuedEnded!(true);
      await library.settled();
      final ended = continued('ended').single;
      expect(ended.f['locked']?.toJson(), isTrue);
      expect(ended.f['away']?.toJson(), isFalse);
      expect(rig.engine.downloadsStopped, isEmpty);
      expect(rig.host.handedOff, isEmpty);
      expect(rig.host.continuedBegun, hasLength(1));

      library
        ..pause(cid)
        ..resume(cid);
      await library.settled();
      expect(rig.host.continuedBegun, hasLength(2));
    });
  });

  group('trips', () {
    test(
      'a continued trip leaves the engine downloading away: nothing stopped or handed off, the queue goes on',
      () async {
        final library = await running([offlineRequest(cid: 1), offlineRequest(cid: 2)]);
        rig.host.calls.clear();

        lifecycle(toBackground);
        await library.settled();
        expect(rig.host.calls, isEmpty, reason: 'no grace and no hand-off');
        expect(rig.engine.downloadsStopped, isEmpty);
        final away = logged('offline away').single;
        expect(away.f['arm']?.toJson(), 'continued');
        expect(away.f['why']?.toJson(), 'pinned');
        expect(away.f['continued']?.toJson(), 'running');
        expect(away.f['parts']?.toJson(), 2);

        rig.engine.downloadController.add(const DownloadFinished('1', videoTotal: 10 * mib, audioTotal: mib));
        await library.settled();
        expect(rig.engine.downloadsStarted.map((request) => request.id), ['1', '2'], reason: 'the queue goes on away');
        final asked = rig.http.to(Canned.playUrlPath).length;
        await library.refreshUrls(2);
        expect(rig.http.to(Canned.playUrlPath), hasLength(asked + 1), reason: 'addresses are renewed away too');

        rig.engine.downloadController.add(progress(2, 5 * mib));
        rig.now = rig.now.add(const Duration(seconds: 60));
        lifecycle(toForeground);
        await library.settled();

        final trip = (library.trials as PinnedTrials).recorded.single;
        expect(trip.arm, BackgroundArm.continuedArm);
        expect(trip.gainedBytes, 16 * mib);
        expect(trip.wastedBytes, 0);
        expect(trip.seconds, 60);
        expect(trip.allDone, isFalse);
        expect(trip.scored, isTrue);
        final line = logged('offline trip').single;
        expect(line.f['gainedMb']?.toJson(), 16);
        expect(line.f['mbps']?.toJson(), 0.3);
        expect(line.f['scored']?.toJson(), isTrue);
        expect(line.f.containsKey('continuedEndedAfter'), isFalse);
        expect(logged('offline trials'), hasLength(1));
        expect(rig.engine.downloadsStarted, hasLength(2), reason: 'nothing to start again on the return');
        expect(rig.host.continuedBegun, hasLength(1), reason: 'the task still runs');
      },
    );

    test('away on a continued trip, the engine\'s progress is logged every so often until the return', () async {
      rig.awayProgressGap = const Duration(milliseconds: 10);
      final library = await running([offlineRequest()]);
      lifecycle(toBackground);
      await library.settled();

      rig.engine.downloadController.add(progress(cid, 20 * mib));
      rig.now = rig.now.add(const Duration(seconds: 10));
      await until(() => logged('offline away progress').any((line) => line.f['mb']?.toJson() == 20));
      final line = logged('offline away progress').last;
      expect(line.f['secs']?.toJson(), 10);
      expect(line.f['mbps']?.toJson(), 2.0);

      lifecycle(toForeground);
      await library.settled();
      final lines = logged('offline away progress').length;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(logged('offline away progress'), hasLength(lines));
    });

    test('a hand-off trip ends the running task first and hands off with its arm\'s connections and pieces', () async {
      rig.trials = () =>
          PinnedTrials(whileContinued: const BackgroundArm.handOff(connections: 6, maxPieceBytes: 32 * mib));
      final library = await running([offlineRequest()]);
      rig.host.calls.clear();
      rig.engine.gaps['$cid'] = DownloadGaps(
        id: '$cid',
        video: [ByteRange(0, 200 * mib - 1)],
        audio: [ByteRange(0, mib - 1)],
        videoTotal: 200 * mib,
        audioTotal: mib,
      );

      lifecycle(toBackground);
      await library.settled();

      expect(rig.host.calls, ['endContinued true', 'beginGrace', 'handOff', 'endGrace']);
      expect(rig.host.handOffConnections, [6]);
      expect(rig.host.handedOff.single.map((range) => range.end - range.start + 1).reduce(math.max), 32 * mib);
      final handed = logged('offline handed off').single;
      expect(handed.f['arm']?.toJson(), 'handoff-6x32');
      expect(handed.f['connections']?.toJson(), 6);
      expect(handed.f['fallback']?.toJson(), isFalse);
      expect(continued('completed').single.f['why']?.toJson(), 'hand-off');
      expect((library.trials as PinnedTrials).asked, [true]);
      expect(logged('offline away').single.f['arm']?.toJson(), 'handoff-6x32');
    });

    test(
      'continued processing ended away hands the rest off with the best hand-off, the engine\'s gain kept',
      () async {
        rig.trials = () => PinnedTrials(handOff: const BackgroundArm.handOff(connections: 2, maxPieceBytes: 64 * mib));
        final library = await running([offlineRequest()]);
        final left = rig.now;
        lifecycle(toBackground);
        await library.settled();
        expect(rig.host.handedOff, isEmpty);

        rig.engine.downloadController.add(progress(cid, 10 * mib));
        rig.engine.gaps['$cid'] = gaps(cid, from: 10 * mib);
        rig.now = left.add(const Duration(seconds: 30));
        rig.host.calls.clear();
        rig.host.continuedEnded!(false);
        await library.settled();

        expect(rig.engine.downloadsStopped, ['$cid']);
        expect(rig.host.calls, ['beginGrace', 'handOff', 'endGrace']);
        expect(rig.host.handOffConnections, [2]);
        final handed = logged('offline handed off').single;
        expect(handed.f['arm']?.toJson(), 'handoff-2x64');
        expect(handed.f['fallback']?.toJson(), isTrue);
        final ended = continued('ended').single;
        expect(ended.f['away']?.toJson(), isTrue);
        expect(ended.f['secs']?.toJson(), 30.0);

        rig.host.rangeFinished!(
          const BackgroundRangeResult(
            id: '$cid',
            video: true,
            start: 10 * mib,
            end: 16 * mib - 1,
            done: true,
            status: 206,
          ),
        );
        expect(library.item(cid)!.bytes, 16 * mib);
        rig.host.results = [
          const BackgroundRangeResult(
            id: '$cid',
            video: true,
            start: 10 * mib,
            end: 16 * mib - 1,
            done: true,
            status: 206,
          ),
          const BackgroundRangeResult(
            id: '$cid',
            video: true,
            start: 16 * mib,
            end: 32 * mib - 1,
            done: false,
            status: 0,
            received: 3 * mib,
          ),
        ];
        rig.now = left.add(const Duration(seconds: 90));
        lifecycle(toForeground);
        await library.settled();

        final trip = (library.trials as PinnedTrials).recorded.single;
        expect(trip.arm, BackgroundArm.continuedArm);
        expect(trip.gainedBytes, 16 * mib, reason: '10 MiB by the engine, 6 MiB by the transfers, counted once');
        expect(trip.wastedBytes, 3 * mib);
        expect(trip.continuedEndedAfter, 30);
        expect(trip.seconds, 90);
        expect(trip.allDone, isFalse);
        final line = logged('offline trip').single;
        expect(line.f['continuedEndedAfter']?.toJson(), 30.0);
        expect(line.f['fallbackArm']?.toJson(), 'handoff-2x64');
        expect(line.f['engineMb']?.toJson(), 10);
        expect(rig.engine.downloadsStarted, hasLength(2), reason: 'the engine takes over again');
      },
    );

    test('each trip is kept in trials.json and read back at the next launch', () async {
      rig.host.continuedProcessing = false;
      final library = await rig.started();
      await library.enqueue([offlineRequest()]);
      await library.settled();
      rig.engine.gaps['$cid'] = gaps(cid);
      lifecycle(toBackground);
      await library.settled();
      rig.host.results = [
        const BackgroundRangeResult(id: '$cid', video: true, start: 0, end: 16 * mib - 1, done: true, status: 206),
        const BackgroundRangeResult(id: '$cid', video: false, start: 0, end: mib - 1, done: false, status: 0),
      ];
      rig.now = rig.now.add(const Duration(seconds: 40));
      lifecycle(toForeground);
      await library.settled();

      final saved = jsonDecode(File(trialsPath()).readAsStringSync()) as Map<String, Object?>;
      final kept = (saved['trips']! as List<Object?>).single! as Map<String, Object?>;
      expect(kept['arm'], 'handoff-3x128');
      expect(kept['gained'], 16 * mib);
      expect(logged('offline trip').single.f['scored']?.toJson(), isTrue);

      rig.close(library);
      final relaunched = await rig.started();
      expect(relaunched.trials.trips.single.arm, BackgroundArm.fallback);
      expect(relaunched.trials.trips.single.gainedBytes, 16 * mib);
    });

    test('an unreadable trials.json is logged and the trials start empty', () async {
      File(trialsPath()).writeAsStringSync('{not json');
      final library = await rig.started();
      expect(library.trials.trips, isEmpty);
      expect(logged('offline trials unreadable').single.f['error']?.toJson(), 'FormatException');
    });

    test('a short trip is recorded unscored, and leaving with nothing downloading opens none', () async {
      rig.host.continuedProcessing = false;
      final library = await rig.started();
      await library.enqueue([offlineRequest()]);
      await library.settled();
      rig.engine.gaps['$cid'] = gaps(cid);
      lifecycle(toBackground);
      await library.settled();
      lifecycle(toForeground);
      await library.settled();

      final line = logged('offline trip').single;
      expect(line.f['scored']?.toJson(), isFalse);
      expect(line.f['secs']?.toJson(), 0.0);
      expect((library.trials as PinnedTrials).recorded.single.scored, isFalse);

      library.pause(cid);
      lifecycle(toBackground);
      await library.settled();
      lifecycle(toForeground);
      await library.settled();
      expect(logged('offline away'), hasLength(1));
      expect(logged('offline trip'), hasLength(1));
    });

    test('without background transfers no trip is opened', () async {
      rig.dispose();
      rig = Rig(host: FakeOfflineHost(backgroundTransfers: false));
      final library = await rig.started();
      await library.enqueue([offlineRequest()]);
      await library.settled();
      lifecycle(toBackground);
      await library.settled();
      lifecycle(toForeground);
      await library.settled();

      expect(logged('offline away'), isEmpty);
      expect(library.trials.trips, isEmpty);
      expect(File(trialsPath()).existsSync(), isFalse);
    });
  });
}
