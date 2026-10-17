import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/playback/danmaku_feed.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late CannedHttp http;
  late DanmakuFeed feed;

  setUp(() {
    http = Canned.http();
    final logger = Logger(session: 'test');
    feed = DanmakuFeed(client: BiliClient(transport: http, cookies: CookieJar(Canned.cookies), logger: logger), logger: logger);
  });

  tearDown(() => feed.dispose());

  List<String> asked() => [
        for (final request in http.to(Canned.segmentPath))
          '${request.url.queryParameters['oid']}#${request.url.queryParameters['segment_index']}',
      ];

  test('asks for the segment under the playhead and adds it to the timeline', () async {
    feed.load(cid: 42, durationMs: 700000);
    expect(feed.timeline, isNull);
    feed.update(positionMs: 1000, playing: true);
    feed.update(positionMs: 1100, playing: true);
    await feed.settle();

    expect(asked(), ['42#1']);
    final timeline = feed.timeline!;
    expect(timeline.advance(500), isEmpty);
    expect(timeline.advance(1500).map((item) => item.text), ['前方高能']);
    expect(timeline.advance(2400).map((item) => item.text), ['来了']);
  });

  test('fetches the next segment only within 30 s of it, and only while playing', () async {
    feed.load(cid: 42, durationMs: 700000);
    feed.update(positionMs: 340000, playing: false);
    await feed.settle();
    expect(asked(), ['42#1']);

    feed.update(positionMs: 340000, playing: true);
    await feed.settle();
    expect(asked(), ['42#1', '42#2']);

    feed.update(positionMs: 341000, playing: true);
    await feed.settle();
    expect(asked(), hasLength(2), reason: 'never the same segment twice');
  });

  test('no segment past the end of the video', () async {
    feed.load(cid: 42, durationMs: 350000);
    feed.update(positionMs: 345000, playing: true);
    await feed.settle();
    expect(asked(), ['42#1']);
  });

  test('a failed segment is asked again only after the playhead moves to another segment', () async {
    http.dataRoutes[Canned.segmentPath] = (500, http.dataRoutes[Canned.segmentPath]!.$2);
    feed.load(cid: 42, durationMs: 1000000);
    feed.update(positionMs: 1000, playing: true);
    await feed.settle();
    feed.update(positionMs: 2000, playing: true);
    await feed.settle();
    expect(asked(), ['42#1'], reason: 'no loop of requests');

    feed.seeked(400000);
    feed.update(positionMs: 400000, playing: true);
    feed.seeked(1000);
    feed.update(positionMs: 1000, playing: true);
    await feed.settle();
    expect(asked(), ['42#1', '42#2', '42#1']);
  });

  test('stops when the uploader closed danmaku', () async {
    http.dataRoutes[Canned.segmentPath] = (200, danmakuSegmentBytes(const [], closed: true));
    feed.load(cid: 42, durationMs: 1000000);
    feed.update(positionMs: 1000, playing: true);
    await feed.settle();
    expect(feed.closed, isTrue);
    expect(feed.timeline, isNull);
    feed.update(positionMs: 400000, playing: true);
    await feed.settle();
    expect(asked(), ['42#1']);
  });

  test('a segment for the previous video is dropped', () async {
    final gate = Completer<void>();
    http.gates[Canned.segmentPath] = gate;
    feed.load(cid: 42, durationMs: 700000);
    feed.update(positionMs: 1000, playing: true);
    feed.load(cid: 43, durationMs: 700000);
    gate.complete();
    await settle();
    expect(feed.timeline, isNull);
    expect(feed.cid, 43);
  });

  test('nothing is asked without a video', () async {
    feed.update(positionMs: 1000, playing: true);
    await feed.settle();
    expect(http.requests, isEmpty);
  });
}
