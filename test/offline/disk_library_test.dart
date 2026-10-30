import 'dart:io';

import 'package:bili_core/api.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/offline/offline_models.dart';
import 'package:bilifast/playback/codec_memory.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';
import 'disk_test_support.dart';

const cid = 137649199;

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

  DownloadProgress progress(int cid, {int video = 100, int audio = 10, double bps = 2000}) =>
      DownloadProgress('$cid', videoBytes: video, audioBytes: audio, videoTotal: 1000, audioTotal: 100, bps: bps);

  test('enqueue saves the entry, the cover, the face and every danmaku segment, then starts the engine', () async {
    final library = await rig.started();
    await library.enqueue([offlineRequest()]);
    await library.settled();

    final started = rig.engine.downloadsStarted.single;
    expect(started.id, '$cid');
    expect(started.video.path, rig.file(cid, 'v.m4s'));
    expect(started.audio.path, rig.file(cid, 'a.m4s'));
    expect(started.video.primary, contains('120-hevc'));
    expect(started.audio.primary, contains('30280'));
    expect(started.mediaHeaders, BiliClient.mediaHeaders);

    expect(rig.http.to(Canned.playUrlPath).single.url.queryParameters['qn'], '127');
    expect(rig.http.to(Canned.segmentPath).map((request) => request.url.queryParameters['segment_index']), ['1', '2']);
    for (final name in [
      'cover.jpg',
      'face.jpg',
      'dm${Platform.pathSeparator}1.so',
      'dm${Platform.pathSeparator}2.so',
    ]) {
      expect(File(rig.file(cid, name)).existsSync(), isTrue, reason: name);
    }
    expect(rig.pictureUrls.first.toString(), 'https://i1.hdslb.com/bfs/archive/cover$cid.jpg@720w_405h_1c_90q.jpg');

    final item = library.item(cid)!;
    expect(item.state, OfflineState.downloading);
    expect(item.quality, 120);
    expect(item.qualityName, '超清 4K');
    expect(item.vipOnly, isTrue);
    expect(item.coverFile, rig.file(cid, 'cover.jpg'));
    expect(item.faceFile, rig.file(cid, 'face.jpg'));
    expect(library.unseen, isTrue);
    expect(rig.host.excluded, rig.folder);

    final entry = rig.entry(cid);
    expect(entry['state'], 'downloading');
    expect((entry['video']! as Map)['id'], 120);
    expect((entry['danmaku']! as Map)['saved'], 2);
    final text = File(rig.file(cid, 'entry.json')).readAsStringSync();
    expect(text, isNot(contains('bilivideo')), reason: 'no signed address is kept');
    expect(text, isNot(contains(rig.folder)), reason: 'paths are kept relative');
    expect(rig.logText, isNot(contains('upsig')));
  });

  test('the highest quality offered is taken, in a codec the phone plays, and a ceiling is respected', () async {
    final memory = CodecMemory()..markFailed('hevc');
    rig = Rig(memory: memory);
    final library = await rig.started();
    await library.enqueue([offlineRequest()]);
    await library.settled();
    await library.enqueue([offlineRequest(cid: 2)], quality: 80);
    library.setConcurrency(2);
    await library.settled();

    final [best, capped] = rig.engine.downloadsStarted;
    expect(best.video.primary, contains('120-avc'), reason: 'HEVC was refused on this phone');
    expect(capped.video.primary, contains('80-av1'));
    expect(rig.http.to(Canned.playUrlPath).map((request) => request.url.queryParameters['qn']), ['127', '80']);
    expect(library.item(2)!.quality, 80);
    expect(library.item(2)!.vipOnly, isFalse);
  });

  test('parts start oldest first, as many at once as the concurrency allows', () async {
    final library = await rig.started();
    await library.enqueue([offlineRequest(cid: 1), offlineRequest(cid: 2), offlineRequest(cid: 3)]);
    await library.settled();
    expect(rig.engine.downloadsStarted.map((request) => request.id), ['1']);
    expect(library.item(2)!.state, OfflineState.waiting);

    library.setConcurrency(2);
    await library.settled();
    expect(rig.engine.downloadsStarted.map((request) => request.id), ['1', '2']);

    rig.engine.downloadController.add(const DownloadFinished('1', videoTotal: 1000, audioTotal: 100));
    await library.settled();
    expect(rig.engine.downloadsStarted.map((request) => request.id), ['1', '2', '3']);
    expect(library.item(1)!.state, OfflineState.done);
    expect(library.items.map((item) => item.cid), [3, 2, 1], reason: 'newest added first');

    library.setConcurrency(9);
    expect(library.concurrency, 3);
  });

  test('pause stops the download and lets the next start; resume and startAll queue them again', () async {
    final library = await rig.started();
    await library.enqueue([offlineRequest(cid: 1), offlineRequest(cid: 2)]);
    await library.settled();

    library.pause(1);
    await library.settled();
    expect(rig.engine.downloadsStopped, ['1']);
    expect(library.item(1)!.state, OfflineState.paused);
    expect(rig.engine.downloadsStarted.map((request) => request.id), ['1', '2']);

    library.resume(1);
    expect(library.item(1)!.state, OfflineState.waiting);

    library.pauseAll();
    await library.settled();
    expect(library.items.map((item) => item.state), everyElement(OfflineState.paused));
    expect(rig.engine.downloadsStopped, ['1', '2']);

    library.startAll();
    await library.settled();
    expect(library.item(1)!.state, OfflineState.downloading, reason: 'the older part goes first');
    expect(library.item(2)!.state, OfflineState.waiting);
    expect(rig.engine.downloadsStarted.map((request) => request.id), ['1', '2', '1']);
    expect(rig.entry(2)['state'], 'waiting');
  });

  test('delete stops the download and removes the part, files and all', () async {
    final library = await rig.started();
    await library.enqueue([offlineRequest()]);
    await library.settled();
    expect(library.usedBytes, greaterThan(0));

    await library.delete([cid]);
    await library.settled();
    expect(rig.engine.downloadsStopped, ['$cid']);
    expect(library.item(cid), isNull);
    expect(library.items, isEmpty);
    expect(Directory(rig.part(cid)).existsSync(), isFalse);
    expect(Directory(rig.folder).listSync().whereType<Directory>(), isEmpty);
    expect(library.usedBytes, 0);
  });

  test('a relaunch reads every part back and resumes the unfinished ones, but not paused or failed ones', () async {
    final first = await rig.started();
    await first.enqueue([offlineRequest(cid: 1), offlineRequest(cid: 2), offlineRequest(cid: 3)]);
    await first.settled();
    first.pause(2);
    rig.engine.downloadController.add(progress(1, video: 300, audio: 30));
    await first.settled();
    rig.close(first);
    // What the engine had written of part 1 when the app went.
    File('${rig.file(1, 'v.m4s')}.ranges').writeAsStringSync('{"total":1000,"done":[[0,99]]}');
    File('${rig.file(1, 'a.m4s')}.bg-ranges').writeAsStringSync('{"total":100,"done":[[0,9]]}');

    rig.engine = FakeEngine();
    final second = rig.make();
    final playUrls = rig.http.to(Canned.playUrlPath).length;
    await second.start();
    expect(second.item(1)!.bytes, 110, reason: 'counted from the ranges files');
    expect(second.item(1)!.totalBytes, 1100);
    await second.settled();

    expect(second.items.map((item) => item.cid), [3, 2, 1]);
    expect(second.item(1)!.state, OfflineState.downloading);
    expect(second.item(2)!.state, OfflineState.paused);
    expect(second.item(3)!.state, OfflineState.waiting);
    expect(second.item(1)!.quality, 120);
    expect(rig.engine.downloadsStarted.map((request) => request.id), ['1']);
    expect(rig.http.to(Canned.playUrlPath).length, playUrls + 1, reason: 'addresses are never kept');
    expect(rig.http.to(Canned.segmentPath).length, 2, reason: 'danmaku already saved is not asked again');
    expect(File('${rig.file(1, 'v.m4s')}.ranges').existsSync(), isTrue, reason: 'the same streams keep their bytes');
    expect(rig.host.calls.where((call) => call == 'takeBack'), hasLength(2));
  });

  test('progress events move the item on and reach listeners', () async {
    final library = await rig.started();
    await library.enqueue([offlineRequest()]);
    await library.settled();
    var heard = 0;
    library.addListener(() => heard += 1);
    // Progress reaches listeners at most once a second.
    rig.now = rig.now.add(const Duration(seconds: 2));

    rig.engine.downloadController.add(progress(cid, video: 500, audio: 50, bps: 1.5e6));
    await library.settled();

    final item = library.item(cid)!;
    expect(item.bytes, 550);
    expect(item.totalBytes, 1100);
    expect(item.bps, 1.5e6);
    expect(item.progress, closeTo(0.5, 0.001));
    expect(heard, greaterThan(0));
  });

  test('a finished part is done, unseen, and plays from its files with its danmaku', () async {
    final library = await rig.started();
    await library.enqueue([offlineRequest()]);
    await library.settled();
    library.markSeen();
    expect(await library.playback(cid), isNull, reason: 'not finished');

    rig.engine.downloadController.add(const DownloadFinished('$cid', videoTotal: 1000, audioTotal: 100));
    await library.settled();
    final item = library.item(cid)!;
    expect(item.state, OfflineState.done);
    expect(item.bytes, 1100);
    expect(item.totalBytes, 1100);
    expect(library.unseen, isTrue);
    expect(rig.entry(cid)['state'], 'done');
    expect(await library.playback(cid), isNull, reason: 'its files are gone');

    File(rig.file(cid, 'v.m4s')).writeAsStringSync('video');
    File(rig.file(cid, 'a.m4s')).writeAsStringSync('audio');
    final playback = (await library.playback(cid))!;
    expect(playback.files.videoPath, rig.file(cid, 'v.m4s'));
    expect(playback.files.audioPath, rig.file(cid, 'a.m4s'));
    expect(playback.files.video.id, 120);
    expect(playback.files.video.codecs, 'hev1.1.6.L153.90');
    expect(playback.files.video.baseURL, isEmpty);
    expect(playback.files.video.indexRange, ByteRange(1105, 1688));
    expect(playback.files.audio.id, 30280);
    expect(playback.danmakuFolder, rig.file(cid, 'dm'));
    expect(playback.danmakuSegments, 2);
  });

  test('refused addresses are asked again and swapped into the download', () async {
    final library = await rig.started();
    await library.enqueue([offlineRequest()]);
    await library.settled();
    rig.http.routes[Canned.playUrlPath] = (200, Canned.playUrl(tag: 'fresh'));

    rig.engine.downloadController.add(
      const DownloadFailed('$cid', failure: DownloadFailure.expired, track: TrackKind.video),
    );
    await library.settled();

    expect(rig.http.to(Canned.playUrlPath), hasLength(2));
    // The refused download ended; its next start carries the fresh addresses instead of parking them in the engine.
    expect(rig.engine.downloadUrlReplacements, isEmpty);
    expect(rig.engine.downloadsStarted, hasLength(2));
    expect(rig.engine.downloadsStarted.last.video.primary, contains('fresh'));
    expect(library.item(cid)!.state, OfflineState.downloading);
    expect(rig.logText, isNot(contains('upsig')));
  });

  test('a changed size starts that track over from nothing', () async {
    final library = await rig.started();
    await library.enqueue([offlineRequest()]);
    await library.settled();
    final part = File('${rig.file(cid, 'a.m4s')}.part')..writeAsStringSync('old');
    final kept = File('${rig.file(cid, 'v.m4s')}.part')..writeAsStringSync('kept');

    rig.engine.downloadController.add(
      const DownloadFailed('$cid', failure: DownloadFailure.sizeChanged, track: TrackKind.audio),
    );
    await library.settled();

    expect(part.existsSync(), isFalse);
    expect(kept.existsSync(), isTrue);
    expect(rig.engine.downloadsStopped, ['$cid']);
    expect(rig.engine.downloadsStarted, hasLength(2));
  });

  test('a video Bilibili no longer serves fails as unavailable, and the queue goes on', () async {
    final library = await rig.started();
    rig.http.routes[Canned.playUrlPath] = (200, '{"code":-404,"message":"啥都木有","ttl":1}');
    await library.enqueue([offlineRequest(cid: 1), offlineRequest(cid: 2)]);
    await library.settled();

    expect(library.item(1)!.state, OfflineState.failed);
    expect(library.item(1)!.failure, OfflineFailure.unavailable);
    expect(library.item(2)!.failure, OfflineFailure.unavailable);
    expect(rig.engine.downloadsStarted, isEmpty);
    expect(rig.entry(1)['failure'], 'unavailable');

    // 视频已失效 offers no retry: a tap asks Bilibili nothing.
    final asked = rig.http.to(Canned.playUrlPath).length;
    library.resume(1);
    await library.settled();
    expect(library.item(1)!.failure, OfflineFailure.unavailable);
    expect(rig.http.to(Canned.playUrlPath), hasLength(asked));
  });

  test('a network failure fails the part and holds the queue until 全部开始', () async {
    final library = await rig.started();
    rig.http.errors[Canned.playUrlPath] = const BiliError.network('SocketException');
    await library.enqueue([offlineRequest(cid: 1), offlineRequest(cid: 2)]);
    await library.settled();

    expect(rig.http.to(Canned.playUrlPath), hasLength(2), reason: 'one retry');
    expect(library.item(1)!.failure, OfflineFailure.network);
    expect(library.item(2)!.state, OfflineState.waiting);

    rig.http.errors.clear();
    library.startAll();
    await library.settled();
    expect(library.item(1)!.state, OfflineState.downloading);
    expect(rig.engine.downloadsStarted.map((request) => request.id), ['1']);
  });

  test('positions are kept, and survive a relaunch', () async {
    final library = await rig.started();
    await library.enqueue([offlineRequest()]);
    await library.settled();

    library.savePosition(cid, 23.5);
    expect(library.item(cid)!.position, 23.5);
    lifecycle(toBackground);
    await library.settled();
    lifecycle(toForeground);
    await library.settled();
    expect(rig.entry(cid)['position'], 23.5);

    rig.close(library);
    final again = rig.make();
    await again.start();
    expect(again.item(cid)!.position, 23.5);
  });

  test('concurrency and the unseen dot are kept across launches', () async {
    final library = await rig.started();
    library.setConcurrency(3);
    await library.enqueue([offlineRequest()]);
    await library.settled();
    rig.close(library);

    final again = rig.make();
    await again.start();
    expect(again.concurrency, 3);
    expect(again.unseen, isTrue);
    again.markSeen();
    await again.settled();
    rig.close(again);

    final third = rig.make();
    await third.start();
    expect(third.unseen, isFalse);
    expect(third.freeBytes, rig.host.free);
  });
}
