import 'dart:async';
import 'dart:io';

import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/offline/offline_models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/fakes.dart';
import 'disk_test_support.dart';

const cid = 137649199;
const riskControl = '{"code":-352,"message":"-352","ttl":1}';

/// The phone full for every `entry.json` written; every other file as it is.
final class _FullDisk extends IOOverrides {
  @override
  File createFile(String path) => path.endsWith('entry.json.tmp') ? _FullFile(path) : super.createFile(path);
}

final class _FullFile implements File {
  _FullFile(this.path);

  @override
  final String path;

  @override
  Future<File> writeAsBytes(List<int> bytes, {FileMode mode = FileMode.write, bool flush = false}) async =>
      throw FileSystemException('Cannot write', path, const OSError('No space left on device', 28));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Rig rig;

  setUp(() => rig = Rig());

  tearDown(() {
    rig.dispose();
    if (TestWidgetsFlutterBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      lifecycle(const [AppLifecycleState.resumed]);
    }
  });

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 400 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(done(), isTrue);
  }

  DownloadProgress progress(int cid, int bytes) =>
      DownloadProgress('$cid', videoBytes: bytes, audioBytes: 0, videoTotal: 1000, audioTotal: 100, bps: 0);

  DownloadFailed expired(int cid) => DownloadFailed('$cid', failure: DownloadFailure.expired, track: TrackKind.video);

  group('the strikes', () {
    test('the progress an engine start reports before any byte is not progress: refusals fail the part', () async {
      final library = await rig.started();
      await library.enqueue([offlineRequest()]);
      await library.settled();
      for (var round = 0; round < 5; round++) {
        rig.engine.downloadController.add(progress(cid, 100));
        rig.engine.downloadController.add(expired(cid));
        await library.settled();
      }
      expect(library.item(cid)!.state, OfflineState.failed);
      expect(library.item(cid)!.failure, OfflineFailure.network);
      expect(rig.http.to(Canned.playUrlPath), hasLength(3), reason: 'the first ask, then one per allowed strike');
    });

    test('bytes beyond the start clear them', () async {
      final library = await rig.started();
      await library.enqueue([offlineRequest()]);
      await library.settled();
      for (var round = 0; round < 5; round++) {
        rig.engine.downloadController.add(progress(cid, 100 + round));
        rig.engine.downloadController.add(progress(cid, 200 + round));
        rig.engine.downloadController.add(expired(cid));
        await library.settled();
      }
      expect(library.item(cid)!.state, OfflineState.downloading);
      expect(rig.http.to(Canned.playUrlPath), hasLength(6));
    });
  });

  test('a renewal whose start the engine answers after a pause stops that download', () async {
    final library = await rig.started();
    await library.enqueue([offlineRequest()]);
    await library.settled();
    // The engine let go of the refused download.
    rig.engine.running.remove('$cid');
    rig.engine.startGate = Completer<void>();
    rig.engine.downloadController.add(expired(cid));
    await until(() => rig.engine.downloadsStarted.length == 2);

    library.pause(cid);
    rig.engine.startGate!.complete();
    await library.settled();
    expect(library.item(cid)!.state, OfflineState.paused);
    expect(rig.engine.running, isNot(contains('$cid')));
    expect(rig.engine.downloadsStopped, ['$cid']);
  });

  test('pause and resume while the engine start is on its way leave the engine downloading', () async {
    final library = await rig.started();
    rig.engine.startGate = Completer<void>();
    await library.enqueue([offlineRequest(cid: 1)]);
    await until(() => rig.engine.downloadsStarted.isNotEmpty);

    library.pause(1);
    library.resume(1);
    await until(() => rig.engine.downloadsStarted.length == 2);
    rig.engine.startGate!.complete();
    await library.settled();

    expect(library.item(1)!.state, OfflineState.downloading);
    expect(rig.engine.running, contains('1'));
    expect(rig.engine.downloadsStopped, isEmpty);
  });

  test('a part added again while its delete waits on the engine keeps its folder', () async {
    final library = await rig.started();
    await library.enqueue([offlineRequest(cid: 1)]);
    await library.settled();

    rig.engine.stopGate = Completer<void>();
    final deleting = library.delete([1]);
    final adding = library.enqueue([offlineRequest(cid: 1)]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    rig.engine.stopGate!.complete();
    rig.engine.stopGate = null;
    await deleting;
    await adding;
    await library.settled();

    expect(library.item(1), isNotNull);
    expect(File(rig.file(1, 'entry.json')).existsSync(), isTrue);
    expect(rig.engine.running, contains('1'));
  });

  test('a resumed part in a codec the phone now refuses starts over in one it plays', () async {
    final first = await rig.started();
    await first.enqueue([offlineRequest(cid: 1)]);
    await first.settled();
    rig.close(first);
    final part = File('${rig.file(1, 'v.m4s')}.part')..writeAsStringSync('hevc bytes');
    File('${rig.file(1, 'v.m4s')}.ranges').writeAsStringSync('{"total":1000,"done":[[0,9]]}');
    rig.memory.markFailed('hevc');

    rig.engine = FakeEngine();
    final second = rig.make();
    await second.start();
    await second.settled();
    expect(rig.engine.downloadsStarted.single.video.primary, contains('120-avc'));
    expect(part.existsSync(), isFalse, reason: 'the old codec\'s bytes are dropped');
    expect(second.item(1)!.quality, 120);
  });

  test('with nothing at or below the ceiling the lowest is taken, under its own quality and name', () async {
    final library = await rig.started();
    await library.enqueue([offlineRequest()], quality: 16);
    await library.settled();
    expect(rig.http.to(Canned.playUrlPath).single.url.queryParameters['qn'], '16');
    expect(rig.engine.downloadsStarted.single.video.primary, contains('80-av1'));
    final item = library.item(cid)!;
    expect(item.quality, 80);
    expect(item.qualityName, '高清 1080P');
    expect(rig.entry(cid)['quality'], 80);
    expect(rig.entry(cid)['qualityName'], '高清 1080P');
  });

  group('the background session', () {
    test('each range carries its track\'s total', () async {
      final library = await rig.started();
      await library.enqueue([offlineRequest()]);
      await library.settled();
      rig.engine.gaps['$cid'] = DownloadGaps(
        id: '$cid',
        video: [ByteRange(10, 999)],
        audio: [ByteRange(5, 99)],
        videoTotal: 1000,
        audioTotal: 100,
      );
      lifecycle(toBackground);
      await library.settled();
      expect(rig.host.handedOff.single.map((range) => (range.video, range.total)), [(true, 1000), (false, 100)]);
    });

    test('while handed off a refusal asks nothing and starts nothing; the return does', () async {
      final library = await rig.started();
      await library.enqueue([offlineRequest()]);
      await library.settled();
      rig.engine.gaps['$cid'] = DownloadGaps(
        id: '$cid',
        video: [ByteRange(10, 999)],
        audio: const [],
        videoTotal: 1000,
        audioTotal: 100,
      );
      lifecycle(toBackground);
      await library.settled();
      final asked = rig.http.to(Canned.playUrlPath).length;

      rig.engine.downloadController.add(expired(cid));
      await library.settled();
      expect(rig.http.to(Canned.playUrlPath), hasLength(asked));
      expect(rig.engine.downloadsStarted, hasLength(1));

      lifecycle(toForeground);
      await library.settled();
      expect(rig.engine.downloadsStarted, hasLength(2));
      expect(library.item(cid)!.state, OfflineState.downloading);
    });

    test('a launch before Flutter knows its state asks iOS, and a background one waits for the app to open', () async {
      final first = await rig.started();
      await first.enqueue([offlineRequest()]);
      await first.settled();
      rig.close(first);

      TestWidgetsFlutterBinding.instance.resetInternalState();
      rig.host
        ..background = true
        ..calls.clear();
      rig.engine = FakeEngine();
      final second = rig.make();
      await second.start();
      await second.settled();
      expect(rig.host.backgroundAsks, 1);
      expect(rig.host.calls, isNot(contains('takeBack')), reason: 'the transfers iOS launched it for go on');
      expect(rig.engine.downloadsStarted, isEmpty);

      lifecycle(const [AppLifecycleState.resumed]);
      await second.settled();
      expect(rig.host.calls, contains('takeBack'));
      expect(rig.engine.downloadsStarted, hasLength(1));
    });
  });

  test('risk control on a refresh holds the queue and is never asked again on its own', () async {
    final library = await rig.started();
    await library.enqueue([offlineRequest(cid: 1), offlineRequest(cid: 2)]);
    await library.settled();
    rig.http.routes[Canned.playUrlPath] = (200, riskControl);

    await library.refreshUrls(1);
    await library.settled();
    expect(rig.http.to(Canned.playUrlPath), hasLength(2));
    expect(library.item(1)!.state, OfflineState.downloading, reason: 'its addresses still work for now');
    expect(rig.logs.events.where((event) => event.msg == 'offline url refresh refused'), hasLength(1));

    rig.engine.downloadController.add(expired(1));
    await library.settled();
    expect(library.item(1)!.failure, OfflineFailure.network);
    expect(library.item(2)!.state, OfflineState.waiting, reason: 'held');
    expect(rig.http.to(Canned.playUrlPath), hasLength(2));
  });

  test('a file the engine cannot write for another reason fails that part only', () async {
    final library = await rig.started();
    await library.enqueue([offlineRequest(cid: 1), offlineRequest(cid: 2)]);
    await library.settled();

    rig.engine.downloadController.add(const DownloadFailed('1', failure: DownloadFailure.file, osError: 5));
    await library.settled();
    expect(library.item(1)!.failure, OfflineFailure.unknown);
    expect(library.item(2)!.state, OfflineState.downloading, reason: 'the queue goes on');
    final failed = rig.logs.events.where((event) => event.msg == 'offline download failed').single;
    expect(failed.f['osError']?.toJson(), 5);

    rig.engine.downloadController.add(const DownloadFailed('2', failure: DownloadFailure.disk, osError: 28));
    await library.settled();
    expect(library.item(2)!.failure, OfflineFailure.disk);
  });

  group('the part folders', () {
    test('a full phone met saving an entry fails the part as disk and holds the queue', () async {
      final library = await rig.started();
      await IOOverrides.runWithIOOverrides(
        () => library.enqueue([offlineRequest(cid: 1), offlineRequest(cid: 2)]),
        _FullDisk(),
      );
      await library.settled();
      expect(library.item(1)!.failure, OfflineFailure.disk);
      expect(library.item(2)!.failure, OfflineFailure.disk);
      expect(rig.engine.downloadsStarted, isEmpty);
    });

    test('a launch removes folders no entry describes and a delete cut short, and logs their size', () async {
      final first = await rig.started();
      await first.enqueue([offlineRequest(cid: 1), offlineRequest(cid: 2)]);
      await first.settled();
      rig.close(first);
      File(rig.file(1, 'entry.json')).deleteSync();
      File(rig.file(1, 'v.m4s.part')).writeAsBytesSync(List.filled(4000, 1));
      File(rig.file(2, '.deleting')).writeAsBytesSync(const []);
      Directory(rig.part(3)).createSync();
      File(rig.file(3, 'entry.json')).writeAsStringSync('{"request":');

      final second = rig.make();
      await second.start();
      await second.settled();
      expect(second.items, isEmpty);
      for (final cid in [1, 2, 3]) {
        expect(Directory(rig.part(cid)).existsSync(), isFalse, reason: '$cid');
      }
      final removed = {
        for (final event in rig.logs.events.where((event) => event.msg == 'offline folder removed'))
          event.f['cid']?.toJson(): (event.f['reason']?.toJson(), event.f['bytes']?.toJson()),
      };
      expect(removed[1]?.$1, 'unreadable');
      expect(removed[1]?.$2 as int, greaterThanOrEqualTo(4000));
      expect(removed[2]?.$1, 'deleted');
      expect(removed[3]?.$1, 'unreadable');
    });

    test('a delete whose folder cannot be renamed is finished at the next launch', () async {
      final first = await rig.started();
      await first.enqueue([offlineRequest(cid: 1)]);
      await first.settled();
      final held = File(rig.file(1, 'v.m4s.part')).openSync(mode: FileMode.write);
      await first.delete([1]);
      await first.settled();
      held.closeSync();
      expect(first.item(1), isNull);
      expect(Directory(rig.part(1)).existsSync(), isTrue, reason: 'Windows refuses to rename a folder in use');
      expect(File(rig.file(1, '.deleting')).existsSync(), isTrue);
      rig.close(first);

      final second = rig.make();
      await second.start();
      await second.settled();
      expect(second.item(1), isNull);
      expect(Directory(rig.part(1)).existsSync(), isFalse);
    }, skip: Platform.isWindows ? false : 'only Windows refuses to rename a folder with an open file');
  });
}
