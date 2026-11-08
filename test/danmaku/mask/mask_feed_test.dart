import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bili_core/api.dart' show DanmakuMaskInfo;
import 'package:bili_core/devlog.dart';
import 'package:bilifast/danmaku/mask/mask_feed.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'web_mask_file.dart';

final _info = DanmakuMaskInfo(
  cid: 4242,
  plat: 0,
  fps: 30,
  time: 1,
  url: Uri.parse('https://mask.example/bfs/dm_mask/secret-mask-4242.webmask?deadline=1&upsig=signed-part'),
);

/// Serves [file] by ranges, recording each one asked.
final class FakeMaskSource {
  FakeMaskSource(this.file);

  final WebMaskFile file;
  final List<(int, int?)> asked = [];

  /// Every read throws this while set.
  Object? failWith;

  /// Reads starting at a key wait for its completer.
  final Map<int, Completer<void>> held = {};

  /// Reads starting at one of these return the right number of bytes, but not a segment.
  final Set<int> damaged = {};

  int _open = 0;
  int mostAtOnce = 0;

  Future<Uint8List> fetch(Uri url, {required int start, int? end}) async {
    asked.add((start, end));
    _open += 1;
    mostAtOnce = math.max(mostAtOnce, _open);
    try {
      await held[start]?.future;
      final failure = failWith;
      if (failure != null) throw failure;
      final bytes = Uint8List.sublistView(file.bytes, start, end == null ? null : end + 1);
      return damaged.contains(start) ? Uint8List(bytes.length) : Uint8List.fromList(bytes);
    } finally {
      _open -= 1;
    }
  }
}

/// A transport's error, whose text carries the address as cupertino_http's does.
final class _FetchFailure implements Exception {
  _FetchFailure(this.url);

  final Uri url;

  @override
  String toString() => 'request to $url failed (${url.host}${url.path})';
}

int? leftOf(MaskFrame? frame) => frame?.path.getBounds().left.round();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final file = WebMaskFile.tagged(segments: 5);
  late FakeMaskSource source;
  late MemorySink sink;
  late Logger logger;
  late WebMaskFeed feed;

  WebMaskFeed feedOver(WebMaskFile file, {Duration retryDelay = Duration.zero}) {
    source = FakeMaskSource(file);
    return WebMaskFeed(_info, fetch: source.fetch, logger: logger, retryDelay: retryDelay);
  }

  setUp(() {
    sink = MemorySink();
    logger = Logger(session: 'test')..add(sink);
    feed = feedOver(file);
  });

  tearDown(() => feed.dispose());

  Future<void> followed(double seconds) async {
    feed.follow(seconds);
    await feed.settle();
  }

  List<LogEvent> failures() => [
    for (final event in sink.events)
      if (event.msg == 'danmaku mask failed') event,
  ];

  group('reading', () {
    test('reads the head in two ranges, then the playhead\'s segment and the next', () async {
      await followed(0);

      expect(source.asked, [(0, 15), (16, file.headerLength - 1), file.rangeOf(0), file.rangeOf(1)]);
      expect(feed.loadedSegments, [0, 1]);
    });

    test('starting mid-video reads the segments there, the last one to the end of the file', () async {
      await followed(41);

      expect(source.asked.skip(2), [file.rangeOf(4)]);
      expect(file.rangeOf(4).$2, isNull);
      expect(feed.loadedSegments, [4]);
    });

    test('a file that isn\'t a mask counts as a failure', () async {
      source.damaged.add(0);
      await followed(0);

      expect(source.asked, [(0, 15)]);
      expect(failures().single.f['error'], const LogString('FormatException'));
      expect(feed.frameAt(0), isNull);
    });

    test('one read at a time', () async {
      source.held[0] = Completer();
      for (var i = 0; i < 5; i++) {
        feed.follow(i.toDouble());
      }
      await pumpEventQueue();
      expect(source.asked, [(0, 15)]);

      source.held.remove(0)!.complete();
      await followed(5);
      expect(source.mostAtOnce, 1);
    });
  });

  group('frameAt', () {
    test('null until the playhead\'s segment is in', () async {
      expect(feed.frameAt(0), isNull);
      feed.follow(0);
      expect(feed.frameAt(0), isNull);
      await feed.settle();

      expect(leftOf(feed.frameAt(0)), 0);
      expect(feed.frameAt(25), isNull, reason: 'segment 2 is not loaded');
    });

    test('the frame with the latest time at or before the playhead', () async {
      await followed(0);

      expect(leftOf(feed.frameAt(0.033)), 33);
      expect(leftOf(feed.frameAt(0.05)), 33);
      expect(leftOf(feed.frameAt(0.0669)), 33);
      expect(leftOf(feed.frameAt(0.067)), 67);
      expect(leftOf(feed.frameAt(9.999)), 9967);
      expect(leftOf(feed.frameAt(10.5)), 10500);
      expect(feed.frameAt(-1), isNull);
    });

    test('in the box\'s units, y down: potrace\'s flip undone', () async {
      await followed(0);
      final frame = feed.frameAt(1)!;

      expect(frame.box, const Size(180, 320));
      final bounds = frame.path.getBounds();
      expect(bounds.left, closeTo(1000, 0.01));
      expect(bounds.top, closeTo(10, 0.01));
      expect(bounds.right, closeTo(1010, 0.01));
      expect(bounds.bottom, closeTo(20, 0.01));
    });

    test('a segment whose first frame comes late shows the previous segment\'s last frame until then', () async {
      feed.dispose();
      feed = feedOver(WebMaskFile.tagged(segments: 3, firstFrameMs: 20));
      await followed(0);

      expect(feed.frameAt(0.01), isNull);
      expect(leftOf(feed.frameAt(10.01)), 9987);
      expect(leftOf(feed.frameAt(10.02)), 10020);
    });

    test('a frame whose SVG can\'t be read is skipped; the one before it stays up', () async {
      feed.dispose();
      final frames = [
        (ms: 0, svg: squareSvg(0)),
        (ms: 33, svg: '<svg viewBox="0 0 180 320"></svg>'),
        (ms: 67, svg: squareSvg(67)),
      ];
      feed = feedOver(WebMaskFile([frames], startsMs: const [0]));
      await followed(0);

      expect(leftOf(feed.frameAt(0.05)), 0);
      expect(leftOf(feed.frameAt(0.07)), 67);
      final loaded = sink.events.singleWhere((event) => event.msg == 'danmaku mask segment');
      expect(loaded.f['skipped'], const LogInt(1));
      expect(failures(), isEmpty);
    });

    test('builds a frame\'s path once while it shows', () async {
      await followed(0);

      expect(identical(feed.frameAt(0.04)!.path, feed.frameAt(0.05)!.path), isTrue);
      expect(identical(feed.frameAt(0.04)!.path, feed.frameAt(0.07)!.path), isFalse);
    });
  });

  group('following', () {
    test('asks the next segment only in the last 3 s of the playhead\'s', () async {
      await followed(0);
      final asked = source.asked.length;

      await followed(10.5);
      await followed(16.99);
      expect(source.asked, hasLength(asked));

      await followed(17);
      expect(source.asked.skip(asked), [file.rangeOf(2)]);
      expect(feed.loadedSegments, [0, 1, 2]);
    });

    test('a seek reads the target\'s segment first, then its next, and drops the far ones', () async {
      await followed(0);
      final asked = source.asked.length;

      await followed(35);
      expect(source.asked.skip(asked), [file.rangeOf(3), file.rangeOf(4)]);
      expect(feed.loadedSegments, [3, 4]);
      expect(feed.frameAt(5), isNull);
    });

    test('a seek while a segment is on its way: the target comes next, the old one is dropped', () async {
      source.held[file.offsets[1]] = Completer();
      feed.follow(0);
      while (source.asked.length < 4) {
        await pumpEventQueue();
      }
      feed.follow(35);
      await pumpEventQueue();
      expect(source.asked.last, file.rangeOf(1));

      source.held.remove(file.offsets[1])!.complete();
      await feed.settle();
      expect(source.asked.skip(4), [file.rangeOf(3), file.rangeOf(4)]);
      expect(feed.loadedSegments, [3, 4]);
      expect(source.mostAtOnce, 1);
    });

    test('never holds more than three: the previous segment, the playhead\'s and the next', () async {
      for (var ms = 0; ms < 50000; ms += 500) {
        await followed(ms / 1000);
        final current = ms ~/ 10000;
        expect(feed.loadedSegments.length, lessThanOrEqualTo(3));
        expect(feed.loadedSegments, everyElement(inInclusiveRange(current - 1, current + 1)));
        expect(feed.frameAt(ms / 1000), isNotNull);
      }
      expect(feed.loadedSegments, [3, 4]);
      expect(source.asked, hasLength(2 + 5), reason: 'each segment read once');
    });

    test('a small seek back finds the previous segment still there', () async {
      await followed(0);
      await followed(17);
      await followed(20);
      expect(feed.loadedSegments, [1, 2]);
      final asked = source.asked.length;

      await followed(15);
      expect(source.asked, hasLength(asked));
      expect(leftOf(feed.frameAt(15)), 15000);
    });

    test('notifies when the playhead\'s segment lands, not the next', () async {
      var notified = 0;
      feed.addListener(() => notified += 1);

      await followed(0);
      expect(notified, 1);

      await followed(17);
      expect(notified, 1);

      await followed(35);
      expect(notified, 2);
    });
  });

  group('failures', () {
    test('stops after three failed reads; frames stay null', () async {
      source.failWith = _FetchFailure(_info.url);
      for (var i = 0; i < 10; i++) {
        await followed(i.toDouble());
      }

      expect(source.asked, [(0, 15), (0, 15), (0, 15)]);
      expect(feed.frameAt(9), isNull);
      expect(failures(), hasLength(3));
      expect(sink.events.where((event) => event.msg == 'danmaku mask given up'), hasLength(1));
    });

    test('after a failure, waits retryDelay before asking again', () async {
      feed.dispose();
      feed = feedOver(file, retryDelay: const Duration(hours: 1));
      source.failWith = _FetchFailure(_info.url);
      await followed(0);
      source.failWith = null;
      await followed(1);

      expect(source.asked, [(0, 15)]);
    });

    test('a failure is asked again on a later follow, and what is loaded stays', () async {
      source.held[file.offsets[1]] = Completer();
      feed.follow(0);
      while (source.asked.length < 4) {
        await pumpEventQueue();
      }
      source.failWith = _FetchFailure(_info.url);
      source.held.remove(file.offsets[1])!.complete();
      await feed.settle();
      source.failWith = null;

      await followed(1);
      expect(source.asked.skip(4), [file.rangeOf(1)]);
      expect(feed.loadedSegments, [0, 1]);
      expect(failures(), hasLength(1));
    });

    test('a damaged segment counts as a failure', () async {
      source.damaged.add(file.offsets[1]);
      await followed(0);

      expect(feed.loadedSegments, [0]);
      expect(failures().single.f['error'], const LogString('FormatException'));
    });

    test('logs the cid and the error\'s type, never the address', () async {
      await followed(0);
      source.failWith = _FetchFailure(_info.url);
      await followed(35);
      await followed(36);

      expect(failures(), isNotEmpty);
      for (final event in failures()) {
        expect(event.f, {'cid': const LogInt(4242), 'error': const LogString('_FetchFailure')});
      }
      for (final event in sink.events) {
        final line = event.encode();
        expect(line, isNot(contains('mask.example')));
        expect(line, isNot(contains('secret-mask')));
        expect(line, isNot(contains('signed-part')));
      }
    });
  });

  test('dispose stops quietly: nothing more is asked, logged or notified', () async {
    var notified = 0;
    feed.addListener(() => notified += 1);
    source.held[file.offsets[0]] = Completer();
    feed.follow(0);
    while (source.asked.length < 3) {
      await pumpEventQueue();
    }
    final logged = sink.events.length;

    feed.dispose();
    source.failWith = _FetchFailure(_info.url);
    source.held.remove(file.offsets[0])!.complete();
    await pumpEventQueue();
    feed.follow(5);
    await pumpEventQueue();

    expect(source.asked, hasLength(3));
    expect(sink.events, hasLength(logged));
    expect(notified, 0);
    expect(feed.frameAt(0), isNull);
  });

  test('createMaskFeed gives a WebMaskFeed over the fetch', () {
    final created = createMaskFeed(_info, fetch: FakeMaskSource(file).fetch, logger: logger);
    expect(created, isA<WebMaskFeed>());
    created.dispose();
  });
}
