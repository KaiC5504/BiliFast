import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:bili_core/shared.dart';
import 'package:bili_core/src/engine/attempt.dart';
import 'package:bili_core/src/engine/offline_download.dart';
import 'package:bili_core/src/engine/offline_ranges.dart';
import 'package:test/test.dart';

import 'support/sim_cdn.dart';

const _kib = 1024;
const _piece = 256 * _kib;

/// One SimCDN serving several files by name (the path's last segment), each its own size and its own bytes (the
/// pattern XOR a key), so a byte landing in the wrong file shows. Requests can be held, refused or lied about.
final class _Files implements RangeTransport {
  _Files(this.files) : cdn = SimCDN(size: files.values.map((file) => file.size).reduce(max));

  final Map<String, ({int size, int key})> files;
  final SimCDN cdn;

  /// While false every request waits before it is sent.
  bool open = true;

  /// Every request fails as a dropped connection.
  bool broken = false;

  /// Requests for a file starting at or after its offset wait until cancelled.
  final holdFrom = <String, int>{};

  /// Responses for a file starting at or after its offset claim one byte more in total.
  final lieFrom = <String, int>{};
  bool Function(Uri url) refuse = (_) => false;
  final requests = <({String file, String node, String query, ByteRange range})>[];

  @override
  int? get connectionsPerHost => null;

  @override
  String get name => 'files';

  @override
  void close() {}

  Uint8List content(String file) {
    final (:size, :key) = files[file]!;
    return Uint8List.fromList([for (var index = 0; index < size; index++) ((index * 31 + 7) & 0xff) ^ key]);
  }

  List<ByteRange> requested(String file) => [
    for (final request in requests)
      if (request.file == file) request.range,
  ];

  @override
  Future<TransportResponse> fetch(Uri url, ByteRange range, {CancelToken? cancel}) async {
    final file = url.pathSegments.last;
    final (:size, :key) = files[file]!;
    requests.add((file: file, node: NodeCatalog.nodeKey('$url'), query: url.query, range: range));
    while (!open) {
      await cancellableSleep(5, cancel);
    }
    if (broken) {
      await cancellableSleep(2, cancel);
      throw const ConnectionLost();
    }
    if (refuse(url)) {
      await cancellableSleep(2, cancel);
      return TransportResponse(status: 403, headers: const {}, body: const Stream.empty());
    }
    while (range.start >= (holdFrom[file] ?? 1 << 62)) {
      await cancellableSleep(5, cancel);
    }
    if (range.end >= size) {
      return TransportResponse(status: 416, headers: {'content-range': 'bytes */$size'}, body: const Stream.empty());
    }
    final response = await cdn.fetch(url, range, cancel: cancel);
    final total = range.start >= (lieFrom[file] ?? 1 << 62) ? size + 1 : size;
    return TransportResponse(
      status: response.status,
      headers: {'content-range': 'bytes ${range.start}-${range.end}/$total'},
      body: response.body.map((chunk) {
        final out = Uint8List.fromList(chunk);
        for (var index = 0; index < out.length; index++) {
          out[index] ^= key;
        }
        return out;
      }),
    );
  }
}

/// No hedged copies on these fast simulated nodes, and room for a held request to wait.
final _config = TestEngine.config.copyWith(
  hedgeDelayMs: 5000,
  firstByteTimeoutMs: 15000,
  stallTimeoutMs: 5000,
  attemptTimeoutMs: 20000,
);

String _url(String file, {String sig = 'old'}) =>
    'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/$file?sig=$sig&os=cosbv';

final class _Run {
  _Run(this.dir, this.transport, {RipperConfig? config, int connections = 4, Duration? networkTimeout}) {
    downloads = OfflineDownloads(
      transport: transport,
      auto: AutoConcurrency(),
      mode: () => NodeMode.overseas,
      config: config ?? _config,
      policy: MediaURLPolicy.bilibili,
      emit: events.add,
      connections: connections,
      pieceBytes: _piece,
      progressInterval: const Duration(milliseconds: 20),
      flushInterval: const Duration(milliseconds: 50),
      networkTimeout: networkTimeout ?? const Duration(seconds: 20),
      logger: Logger(session: 'test')..add(logs),
    );
    addTearDown(downloads.dispose);
  }

  final Directory dir;
  final _Files transport;
  late final OfflineDownloads downloads;
  final events = <DownloadEvent>[];
  final logs = MemorySink();

  Iterable<LogEvent> logged(String msg) => logs.events.where((event) => event.msg == msg);

  String path(String name) => '${dir.path}${Platform.pathSeparator}$name';

  DownloadRequest request(String id, {String video = 'v.m4s', String audio = 'a.m4s', String sig = 'old'}) =>
      DownloadRequest(
        id: id,
        video: DownloadTrack(
          primary: _url(video, sig: sig),
          backups: const [],
          path: path('$id.video.m4s'),
        ),
        audio: DownloadTrack(
          primary: _url(audio, sig: sig),
          backups: const [],
          path: path('$id.audio.m4s'),
        ),
        mediaHeaders: const {},
      );

  T? last<T extends DownloadEvent>(String id) => events.whereType<T>().where((event) => event.id == id).lastOrNull;

  Future<DownloadFinished> finished(String id) async {
    expect(
      await eventually(() => last<DownloadFinished>(id) != null || last<DownloadFailed>(id) != null, seconds: 15),
      isTrue,
    );
    expect(last<DownloadFailed>(id), isNull, reason: '${last<DownloadFailed>(id)?.failure}');
    return last<DownloadFinished>(id)!;
  }

  Future<DownloadFailed> failed(String id) async {
    expect(await eventually(() => last<DownloadFailed>(id) != null, seconds: 15), isTrue);
    return last<DownloadFailed>(id)!;
  }
}

Future<Directory> _temp() async {
  final dir = await Directory.systemTemp.createTemp('offline');
  addTearDown(() async {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // A file still open on Windows; the system cleans its temp folder.
    }
  });
  return dir;
}

bool _overlaps(ByteRange a, ByteRange b) => a.start <= b.end && b.start <= a.end;

Future<void> _writeAt(String path, Uint8List content, List<ByteRange> ranges) async {
  final file = await File(path).open(mode: FileMode.append);
  for (final range in ranges) {
    await file.setPosition(range.start);
    await file.writeFrom(content, range.start, range.end + 1);
  }
  await file.close();
}

void main() {
  test('downloads both tracks whole over several nodes', () async {
    final files = _Files({'v.m4s': (size: 3 * 1024 * _kib + 77, key: 0x11), 'a.m4s': (size: 300 * _kib, key: 0x22)});
    final run = _Run(await _temp(), files);
    final request = run.request('1');
    await run.downloads.start(request);
    final finished = await run.finished('1');
    expect(finished.videoTotal, files.files['v.m4s']!.size);
    expect(finished.audioTotal, files.files['a.m4s']!.size);
    expect(await File(request.video.path).readAsBytes(), files.content('v.m4s'));
    expect(await File(request.audio.path).readAsBytes(), files.content('a.m4s'));
    final pieceNodes = {
      for (final request in files.requests)
        if (request.range.length > 1) request.node,
    };
    expect(pieceNodes.length, greaterThanOrEqualTo(3));
    final progress = run.events.whereType<DownloadProgress>().toList();
    expect(progress, isNotEmpty);
    expect(run.downloads.running, isEmpty);
  });

  group('stop', () {
    const videoSize = 3 * 1024 * _kib;
    const audioSize = 512 * _kib;
    const videoHeld = 1536 * _kib;
    const audioHeld = 256 * _kib;

    /// A download whose back halves are held, stopped once the front halves are in.
    Future<(_Run, DownloadRequest, DownloadGaps)> stopped() async {
      final files = _Files({'v.m4s': (size: videoSize, key: 0x31), 'a.m4s': (size: audioSize, key: 0x32)});
      files.holdFrom
        ..['v.m4s'] = videoHeld
        ..['a.m4s'] = audioHeld;
      final run = _Run(await _temp(), files);
      final request = run.request('7');
      await run.downloads.start(request);
      expect(
        await eventually(() {
          final progress = run.last<DownloadProgress>('7');
          return progress != null && progress.videoBytes == videoHeld && progress.audioBytes == audioHeld;
        }, seconds: 10),
        isTrue,
      );
      final gaps = await run.downloads.stop('7');
      return (run, request, gaps);
    }

    test('reports the missing ranges and leaves the parts and their ranges', () async {
      final (run, request, gaps) = await stopped();
      expect(gaps.id, '7');
      expect(gaps.video, [ByteRange(videoHeld, videoSize - 1)]);
      expect(gaps.audio, [ByteRange(audioHeld, audioSize - 1)]);
      expect(gaps.videoTotal, videoSize);
      expect(gaps.audioTotal, audioSize);
      expect(run.downloads.running, isEmpty);
      final video = await RangesRecord.read(DownloadRanges.rangesPath(request.video.path));
      expect(video?.total, videoSize);
      expect(video?.done, [ByteRange(0, videoHeld - 1)]);
      expect(File(DownloadRanges.partPath(request.video.path)).existsSync(), isTrue);
      expect(File(request.video.path).existsSync(), isFalse);
      expect(run.events.whereType<DownloadFailed>(), isEmpty);
      expect(run.events.whereType<DownloadFinished>(), isEmpty);

      final unknown = await run.downloads.stop('nothing');
      expect(unknown.isEmpty, isTrue);
      expect((unknown.videoTotal, unknown.audioTotal), (0, 0));
    });

    test('resumes from the ranges file without fetching a byte twice', () async {
      final (first, request, gaps) = await stopped();
      final files = _Files({'v.m4s': (size: videoSize, key: 0x31), 'a.m4s': (size: audioSize, key: 0x32)});
      final run = _Run(first.dir, files);
      await run.downloads.start(request);
      await run.finished('7');
      expect(await File(request.video.path).readAsBytes(), files.content('v.m4s'));
      expect(await File(request.audio.path).readAsBytes(), files.content('a.m4s'));
      // Within the run a late piece may still get a hedged copy; what the ranges file holds is never asked again.
      for (final (file, missing) in [('v.m4s', gaps.video), ('a.m4s', gaps.audio)]) {
        final asked = files.requested(file);
        expect(asked.every((range) => missing.any((gap) => gap.contains(range))), isTrue, reason: '$file $asked');
        expect(mergeRanges(asked), missing);
      }
    });
  });

  test('folds the background ranges in at start and fetches neither them nor its own', () async {
    const videoSize = 1024 * _kib + 100;
    const audioSize = 300 * _kib;
    final files = _Files({'v.m4s': (size: videoSize, key: 0x41), 'a.m4s': (size: audioSize, key: 0x42)});
    final run = _Run(await _temp(), files);
    final request = run.request('9');
    final own = [ByteRange(0, _piece - 1)];
    final background = [ByteRange(2 * _piece, 3 * _piece - 1)];
    final audioBackground = [ByteRange(0, 100 * _kib - 1)];
    final video = request.video.path;
    final audio = request.audio.path;
    await _writeAt(DownloadRanges.partPath(video), files.content('v.m4s'), [...own, ...background]);
    await _writeAt(DownloadRanges.partPath(audio), files.content('a.m4s'), audioBackground);
    await RangesRecord(videoSize, own).write(DownloadRanges.rangesPath(video));
    await RangesRecord(videoSize, background).write(DownloadRanges.backgroundRangesPath(video));
    await RangesRecord(audioSize, audioBackground).write(DownloadRanges.backgroundRangesPath(audio));

    files.open = false;
    await run.downloads.start(request);
    expect((await RangesRecord.read(DownloadRanges.rangesPath(video)))?.done, [...own, ...background]);
    expect((await RangesRecord.read(DownloadRanges.rangesPath(audio)))?.done, audioBackground);
    expect(File(DownloadRanges.backgroundRangesPath(video)).existsSync(), isFalse);
    expect(File(DownloadRanges.backgroundRangesPath(audio)).existsSync(), isFalse);
    final started = run.last<DownloadProgress>('9')!;
    expect(started.videoBytes, 2 * _piece);
    expect(started.audioBytes, 100 * _kib);

    files.open = true;
    await run.finished('9');
    expect(await File(video).readAsBytes(), files.content('v.m4s'));
    expect(await File(audio).readAsBytes(), files.content('a.m4s'));
    for (final range in files.requested('v.m4s')) {
      expect([...own, ...background].any((held) => _overlaps(held, range)), isFalse, reason: '$range');
    }
    for (final range in files.requested('a.m4s')) {
      expect(audioBackground.any((held) => _overlaps(held, range)), isFalse, reason: '$range');
    }
  });

  test('a total that changes fails the track and deletes its part and ranges', () async {
    const videoSize = 2 * 1024 * _kib;
    final files = _Files({'v.m4s': (size: videoSize, key: 0x51), 'a.m4s': (size: 200 * _kib, key: 0x52)});
    files.lieFrom['v.m4s'] = 1024 * _kib;
    final run = _Run(await _temp(), files);
    final request = run.request('3');
    await run.downloads.start(request);
    final failed = await run.failed('3');
    expect(failed.failure, DownloadFailure.sizeChanged);
    expect(failed.track, TrackKind.video);
    expect(File(DownloadRanges.partPath(request.video.path)).existsSync(), isFalse);
    expect(File(DownloadRanges.rangesPath(request.video.path)).existsSync(), isFalse);
    expect(File(request.video.path).existsSync(), isFalse);
    expect(run.downloads.running, isEmpty);
  });

  test(
    'a discarded part whose files cannot be removed still ends: the failure is sent and stop and start answer',
    () async {
      final files = _Files({'v.m4s': (size: 2 * 1024 * _kib, key: 0x55), 'a.m4s': (size: 200 * _kib, key: 0x56)});
      files.lieFrom['v.m4s'] = 1024 * _kib;
      final run = _Run(await _temp(), files);
      final request = run.request('15');
      // Windows refuses to delete a file another handle holds open.
      final held = await File('${DownloadRanges.rangesPath(request.video.path)}.tmp').open(mode: FileMode.write);
      addTearDown(held.close);
      await run.downloads.start(request);
      final failed = await run.failed('15');
      expect(failed.failure, DownloadFailure.sizeChanged, reason: 'the first failure is the one reported');
      expect(run.logged('download end failed').single.f['track']?.toJson(), 'video');
      expect(run.downloads.running, isEmpty);
      await run.downloads.stop('15').timeout(const Duration(seconds: 5));
      files.lieFrom.clear();
      run.events.clear();
      await run.downloads.start(request).timeout(const Duration(seconds: 5));
      await run.downloads.stop('15').timeout(const Duration(seconds: 5));
    },
    skip: Platform.isWindows ? false : 'only Windows refuses to delete an open file',
  );

  test('a total that differs from the request fails at the first piece', () async {
    final files = _Files({'v.m4s': (size: 1024 * _kib, key: 0x53), 'a.m4s': (size: 200 * _kib, key: 0x54)});
    final run = _Run(await _temp(), files);
    final plain = run.request('4');
    final request = DownloadRequest(
      id: '4',
      video: DownloadTrack(primary: plain.video.primary, backups: const [], path: plain.video.path, totalSize: 999999),
      audio: plain.audio,
      mediaHeaders: const {},
    );
    await run.downloads.start(request);
    final failed = await run.failed('4');
    expect(failed.failure, DownloadFailure.sizeChanged);
    expect(failed.track, TrackKind.video);
  });

  test('refused everywhere is expired; fresh addresses then finish it', () async {
    final files = _Files({'v.m4s': (size: 1024 * _kib, key: 0x61), 'a.m4s': (size: 200 * _kib, key: 0x62)});
    files.refuse = (url) => url.query.contains('sig=old');
    final run = _Run(await _temp(), files, config: _config.copyWith(retryWindowMs: 100));
    final request = run.request('5');
    await run.downloads.start(request);
    final failed = await run.failed('5');
    expect(failed.failure, DownloadFailure.expired);
    expect(failed.detail, contains('403'));
    expect(run.downloads.running, isEmpty);

    final before = files.requests.length;
    run.events.clear();
    run.downloads
      ..replaceUrls(
        '5',
        TrackKind.video,
        primary: _url('v.m4s', sig: 'new'),
        backups: const [],
      )
      ..replaceUrls(
        '5',
        TrackKind.audio,
        primary: _url('a.m4s', sig: 'new'),
        backups: const [],
      );
    await run.downloads.start(request);
    await run.finished('5');
    expect(files.requests.skip(before).every((request) => request.query.contains('sig=new')), isTrue);
    expect(await File(request.video.path).readAsBytes(), files.content('v.m4s'));
    expect(await File(request.audio.path).readAsBytes(), files.content('a.m4s'));
  });

  test('finishing renames each part and drops its ranges; a finished start finishes at once', () async {
    final files = _Files({'v.m4s': (size: 1024 * _kib + 5, key: 0x71), 'a.m4s': (size: 128 * _kib, key: 0x72)});
    final run = _Run(await _temp(), files);
    final request = run.request('2');
    await run.downloads.start(request);
    final finished = await run.finished('2');
    expect((finished.videoTotal, finished.audioTotal), (1024 * _kib + 5, 128 * _kib));
    for (final track in [request.video, request.audio]) {
      expect(File(track.path).existsSync(), isTrue);
      expect(File(DownloadRanges.partPath(track.path)).existsSync(), isFalse);
      expect(File(DownloadRanges.rangesPath(track.path)).existsSync(), isFalse);
      expect(File('${DownloadRanges.rangesPath(track.path)}.tmp').existsSync(), isFalse);
    }

    run.events.clear();
    final asked = files.requests.length;
    await run.downloads.start(request);
    final again = await run.finished('2');
    expect((again.videoTotal, again.audioTotal), (1024 * _kib + 5, 128 * _kib));
    expect(files.requests.length, asked);
  });

  test('downloads run side by side within one connection share', () async {
    final files = _Files({
      for (var index = 1; index <= 3; index++) ...{
        'v$index.m4s': (size: (1024 + 300 * index) * _kib, key: 0x80 + index),
        'a$index.m4s': (size: (100 + 20 * index) * _kib, key: 0x90 + index),
      },
    });
    final run = _Run(await _temp(), files, connections: 3);
    final requests = [
      for (var index = 1; index <= 3; index++) run.request('$index', video: 'v$index.m4s', audio: 'a$index.m4s'),
    ];
    await Future.wait([for (final request in requests) run.downloads.start(request)]);
    for (final (index, request) in requests.indexed) {
      await run.finished(request.id);
      expect(await File(request.video.path).readAsBytes(), files.content('v${index + 1}.m4s'));
      expect(await File(request.audio.path).readAsBytes(), files.content('a${index + 1}.m4s'));
    }
    expect(files.cdn.peakInflight, lessThanOrEqualTo(3));
  });

  test('every node failing past the timeout is a network failure', () async {
    final files = _Files({'v.m4s': (size: 512 * _kib, key: 1), 'a.m4s': (size: 64 * _kib, key: 2)});
    files.broken = true;
    final run = _Run(
      await _temp(),
      files,
      config: _config.copyWith(retryWindowMs: 50),
      networkTimeout: const Duration(milliseconds: 300),
    );
    await run.downloads.start(run.request('6'));
    final failed = await run.failed('6');
    expect(failed.failure, DownloadFailure.network);
    expect(failed.detail, isNot(contains('http')));
  });

  test('a part that cannot be written is a disk failure', () async {
    final files = _Files({'v.m4s': (size: 512 * _kib, key: 1), 'a.m4s': (size: 64 * _kib, key: 2)});
    final dir = await _temp();
    final blocker = File('${dir.path}${Platform.pathSeparator}blocker');
    await blocker.writeAsString('a file where a folder should be');
    final run = _Run(dir, files);
    final plain = run.request('8');
    final request = DownloadRequest(
      id: '8',
      video: DownloadTrack(
        primary: plain.video.primary,
        backups: const [],
        path: '${blocker.path}${Platform.pathSeparator}8.video.m4s',
      ),
      audio: plain.audio,
      mediaHeaders: const {},
    );
    await run.downloads.start(request);
    final failed = await run.failed('8');
    expect(failed.failure, DownloadFailure.file, reason: 'only a full phone is a disk failure');
    expect(failed.osError, isNotNull);
    expect(run.downloads.running, isEmpty);
  });

  test('only the full-disk codes count as a full phone', () {
    for (final code in [28, 112, 39]) {
      expect(isDiskFullCode(code), isTrue, reason: '$code');
    }
    for (final code in [2, 5, 13, 17, 20, 21, 32]) {
      expect(isDiskFullCode(code), isFalse, reason: '$code');
    }
  });

  group('ranges that vouch for bytes the part lacks', () {
    const videoSize = 1024 * _kib;
    const audioSize = 128 * _kib;

    test('a missing part drops every claim and fetches it all again', () async {
      final files = _Files({'v.m4s': (size: videoSize, key: 0x13), 'a.m4s': (size: audioSize, key: 0x14)});
      final run = _Run(await _temp(), files);
      final request = run.request('11');
      await RangesRecord(videoSize, [ByteRange(0, _piece - 1)]).write(DownloadRanges.rangesPath(request.video.path));
      await run.downloads.start(request);
      await run.finished('11');
      expect(await File(request.video.path).readAsBytes(), files.content('v.m4s'));
      final trimmed = run.logged('download ranges trimmed').single;
      expect(trimmed.f['track']?.toJson(), 'video');
      expect(trimmed.f['part']?.toJson(), 0);
      expect(trimmed.f['claimed']?.toJson(), _piece);
    });

    test('a part shorter than its ranges keeps only what it holds', () async {
      final files = _Files({'v.m4s': (size: videoSize, key: 0x15), 'a.m4s': (size: audioSize, key: 0x16)});
      final run = _Run(await _temp(), files);
      final request = run.request('12');
      final video = request.video.path;
      await _writeAt(DownloadRanges.partPath(video), files.content('v.m4s'), [ByteRange(0, _piece ~/ 2 - 1)]);
      await RangesRecord(videoSize, [ByteRange(0, _piece - 1)]).write(DownloadRanges.rangesPath(video));
      files.open = false;
      await run.downloads.start(request);
      expect(run.last<DownloadProgress>('12')!.videoBytes, _piece ~/ 2);
      expect((await RangesRecord.read(DownloadRanges.rangesPath(video)))?.done, [ByteRange(0, _piece ~/ 2 - 1)]);
      files.open = true;
      await run.finished('12');
      expect(await File(video).readAsBytes(), files.content('v.m4s'));
      expect(files.requested('v.m4s').any((range) => range.start == _piece ~/ 2), isTrue);
    });
  });

  test('an unreadable ranges file is logged and its part fetched again', () async {
    const videoSize = 512 * _kib;
    final files = _Files({'v.m4s': (size: videoSize, key: 0x19), 'a.m4s': (size: 64 * _kib, key: 0x1a)});
    final run = _Run(await _temp(), files);
    final request = run.request('14');
    await _writeAt(DownloadRanges.partPath(request.video.path), files.content('v.m4s'), [ByteRange(0, _piece - 1)]);
    await File(DownloadRanges.rangesPath(request.video.path)).writeAsString('{"total": 524288, "done": [[0');
    await File(DownloadRanges.backgroundRangesPath(request.audio.path)).writeAsString('not json');
    await run.downloads.start(request);
    await run.finished('14');
    expect(await File(request.video.path).readAsBytes(), files.content('v.m4s'));
    final unreadable = run.logged('download ranges unreadable').toList();
    expect(unreadable.map((event) => (event.f['track']?.toJson(), event.f['file']?.toJson())), [
      ('video', 'ranges'),
      ('audio', 'bg-ranges'),
    ]);
    expect(unreadable.first.f['bytes']?.toJson(), 29);
  });
}
