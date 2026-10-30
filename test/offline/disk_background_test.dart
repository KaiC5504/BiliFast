import 'package:bili_core/api.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/offline/disk/background_plan.dart';
import 'package:bilifast/offline/offline_host.dart';
import 'package:bilifast/offline/offline_models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';
import 'disk_test_support.dart';

const cid = 137649199;
const mib = 1 << 20;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Rig rig;

  setUp(() => rig = Rig());

  tearDown(() {
    rig.dispose();
    if (TestWidgetsFlutterBinding.instance.lifecycleState case final state? when state != AppLifecycleState.resumed) {
      lifecycle(toForeground);
    }
  });

  DownloadGaps gaps({List<ByteRange>? video, List<ByteRange>? audio}) => DownloadGaps(
    id: '$cid',
    video: video ?? [ByteRange(0, 40 * mib - 1)],
    audio: audio ?? [ByteRange(100, 199)],
    videoTotal: 40 * mib,
    audioTotal: 1000,
  );

  test('gaps are cut into pieces of at most 16 MiB', () {
    expect(backgroundPieces([ByteRange(0, 40 * mib - 1), ByteRange(50 * mib, 50 * mib)]), [
      ByteRange(0, 16 * mib - 1),
      ByteRange(16 * mib, 32 * mib - 1),
      ByteRange(32 * mib, 40 * mib - 1),
      ByteRange(50 * mib, 50 * mib),
    ]);
    expect(backgroundPieces([ByteRange(0, 16 * mib - 1)]), [ByteRange(0, 16 * mib - 1)]);
    expect(backgroundPieces([ByteRange(3 * mib, 20 * mib)]), [
      ByteRange(3 * mib, 16 * mib - 1),
      ByteRange(16 * mib, 20 * mib),
    ], reason: 'cut on the grid, not from where the gap starts');
  });

  test('a track whose total is not known yet stays out of the hand-off, and its part waits for the return', () async {
    final library = await rig.started();
    await library.enqueue([offlineRequest()]);
    await library.settled();
    rig.host.calls.clear();
    rig.engine.gaps['$cid'] = DownloadGaps(
      id: '$cid',
      video: [ByteRange(0, mib - 1)],
      audio: const [],
      videoTotal: mib,
      audioTotal: 0,
    );

    lifecycle(toBackground);
    await library.settled();

    expect(rig.host.handedOff.single.map((range) => (range.video, range.start, range.end)), [(true, 0, mib - 1)]);
    expect(rig.engine.downloadsStarted, hasLength(1), reason: 'the engine would write over the transfers');
    expect(rig.host.calls, ['beginGrace', 'handOff', 'endGrace']);

    lifecycle(toForeground);
    await library.settled();
    expect(rig.engine.downloadsStarted, hasLength(2));
  });

  test('leaving hands what the engine lacks to the background session, and the return takes it back', () async {
    final library = await rig.started();
    await library.enqueue([offlineRequest()]);
    await library.settled();
    rig.host.calls.clear();
    rig.engine.gaps['$cid'] = gaps();

    lifecycle(toBackground);
    await library.settled();

    expect(rig.engine.downloadsStopped, ['$cid']);
    expect(rig.host.calls, containsAllInOrder(['beginGrace', 'handOff', 'endGrace']));
    final ranges = rig.host.handedOff.single;
    expect(ranges.map((range) => (range.video, range.start, range.end)), [
      (true, 0, 16 * mib - 1),
      (true, 16 * mib, 32 * mib - 1),
      (true, 32 * mib, 40 * mib - 1),
      (false, 100, 199),
    ]);
    expect(ranges.first.id, '$cid');
    expect(ranges.first.url, contains('120-hevc'));
    expect(ranges.last.url, contains('30280'));
    expect(ranges.first.headers, BiliClient.mediaHeaders);
    expect(ranges.first.partPath, '${rig.file(cid, 'v.m4s')}.part');
    expect(ranges.first.backgroundRangesPath, '${rig.file(cid, 'v.m4s')}.bg-ranges');
    expect(ranges.last.partPath, '${rig.file(cid, 'a.m4s')}.part');
    expect(rig.engine.downloadsStarted, hasLength(1), reason: 'nothing runs in the engine meanwhile');
    expect(library.item(cid)!.state, OfflineState.downloading);

    rig.host.rangeFinished!(
      const BackgroundRangeResult(id: '$cid', video: true, start: 0, end: 16 * mib - 1, done: true, status: 206),
    );
    expect(library.item(cid)!.bytes, 16 * mib);

    rig.host.results = [
      const BackgroundRangeResult(id: '$cid', video: true, start: 0, end: 16 * mib - 1, done: true, status: 206),
      const BackgroundRangeResult(id: '$cid', video: true, start: 16 * mib, end: 32 * mib - 1, done: false, status: 0),
    ];
    lifecycle(toForeground);
    await library.settled();

    expect(rig.host.calls.last, 'takeBack');
    expect(rig.engine.downloadsStarted, hasLength(2), reason: 'the engine takes in what the transfers wrote');
    expect(rig.engine.downloadsStarted.last.video.path, rig.file(cid, 'v.m4s'));
    final takenBack = rig.logs.events.where((event) => event.msg == 'offline taken back').single;
    expect(takenBack.f['done']?.toJson(), 1);
    expect(takenBack.f['cancelled']?.toJson(), 1);
    expect(rig.logText, isNot(contains('upsig')));
  });

  test('addresses close to their deadline are asked again before the hand-off', () async {
    final library = await rig.started();
    await library.enqueue([offlineRequest()]);
    await library.settled();
    rig.host.calls.clear();
    rig.engine.gaps['$cid'] = gaps();
    rig.http.routes[Canned.playUrlPath] = (200, Canned.playUrl(tag: 'fresh'));
    rig.now = DateTime.fromMillisecondsSinceEpoch((Canned.deadline - 20 * 60) * 1000);

    lifecycle(toBackground);
    await library.settled();

    expect(rig.http.to(Canned.playUrlPath), hasLength(2));
    expect(rig.host.handedOff.single.map((range) => range.url), everyElement(contains('fresh')));
  });

  test('a part whose sizes are not known yet goes on in the engine for the grace', () async {
    final library = await rig.started();
    await library.enqueue([offlineRequest()]);
    await library.settled();
    rig.host.calls.clear();

    lifecycle(toBackground);
    await library.settled();

    expect(rig.host.handedOff, isEmpty);
    expect(rig.engine.downloadsStarted, hasLength(2), reason: 'started again after the stop');
    expect(rig.host.calls, ['beginGrace']);

    rig.host.graceEnding!();
    await library.settled();
    expect(rig.engine.downloadsStopped, ['$cid', '$cid']);
    expect(rig.host.calls, ['beginGrace', 'endGrace']);
  });

  test('a refused hand-off falls back to the grace', () async {
    rig.host.handOffError = StateError('refused');
    final library = await rig.started();
    await library.enqueue([offlineRequest()]);
    await library.settled();
    rig.host.calls.clear();
    rig.engine.gaps['$cid'] = gaps();

    lifecycle(toBackground);
    await library.settled();

    expect(rig.engine.downloadsStarted, hasLength(2));
    expect(rig.host.calls, ['beginGrace', 'handOff']);
  });

  test(
    'without background transfers the engine goes on in the grace, stops when it ends and resumes on return',
    () async {
      rig.dispose();
      rig = Rig(host: FakeOfflineHost(backgroundTransfers: false));
      final library = await rig.started();
      await library.enqueue([offlineRequest(cid: 1), offlineRequest(cid: 2)]);
      await library.settled();

      lifecycle(toBackground);
      await library.settled();
      expect(rig.host.calls, ['beginGrace']);
      expect(rig.engine.downloadsStopped, isEmpty, reason: 'the engine keeps going');

      rig.engine.downloadController.add(const DownloadFinished('1', videoTotal: 10, audioTotal: 10));
      await library.settled();
      expect(rig.engine.downloadsStarted.map((request) => request.id), ['1', '2'], reason: 'the queue goes on');

      rig.host.graceEnding!();
      await library.settled();
      expect(rig.engine.downloadsStopped, ['2']);
      expect(rig.host.calls, ['beginGrace', 'endGrace']);

      lifecycle(toForeground);
      await library.settled();
      expect(rig.engine.downloadsStarted.map((request) => request.id), ['1', '2', '2']);
      expect(library.item(2)!.state, OfflineState.downloading);
    },
  );

  test('nothing downloading: leaving asks iOS for no time', () async {
    final library = await rig.started();
    await library.enqueue([offlineRequest()]);
    await library.settled();
    rig.host.calls.clear();
    library.pause(cid);

    lifecycle(toBackground);
    await library.settled();
    expect(rig.host.calls, isEmpty);
  });
}
