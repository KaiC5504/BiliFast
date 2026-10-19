import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_core/api.dart';
import 'package:bili_core/danmaku.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/danmaku/danmaku_scene.dart';
import 'package:bilifast/playback/danmaku_feed.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// A `DmSegMobileReply` with the fields the filter reads.
Uint8List segmentOf(List<DanmakuElem> elems) {
  final out = BytesBuilder();
  void varint(BytesBuilder to, int value) {
    var v = value;
    while (v >= 0x80) {
      to.addByte((v & 0x7F) | 0x80);
      v >>= 7;
    }
    to.addByte(v);
  }

  for (final elem in elems) {
    final bytes = BytesBuilder();
    void number(int field, int value) {
      varint(bytes, field << 3);
      varint(bytes, value);
    }

    void text(int field, String value) {
      final encoded = utf8.encode(value);
      varint(bytes, field << 3 | 2);
      varint(bytes, encoded.length);
      bytes.add(encoded);
    }

    number(1, elem.id);
    number(2, elem.progressMs);
    number(3, elem.mode);
    number(4, elem.fontSize);
    number(5, elem.color);
    text(6, elem.midHash);
    text(7, elem.content);
    final encoded = bytes.toBytes();
    out.addByte(1 << 3 | 2);
    varint(out, encoded.length);
    out.add(encoded);
  }
  return out.toBytes();
}

/// What [timeline] hands out from the start up to [ms], walked in steps under its jump limit.
List<DisplayDanmaku> walk(DanmakuTimeline timeline, int ms) {
  var cursor = -1;
  timeline.seek(cursor);
  final items = <DisplayDanmaku>[];
  while (cursor < ms) {
    cursor = cursor + 1000 < ms ? cursor + 1000 : ms;
    items.addAll(timeline.advance(cursor));
  }
  return items;
}

List<String> texts(DanmakuTimeline? timeline, [int ms = 360000]) =>
    [for (final item in walk(timeline!, ms)) item.text];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  Future<void> loaded(List<DanmakuElem> elems, {int cid = 42}) async {
    http.dataRoutes[Canned.segmentPath] = (200, segmentOf(elems));
    feed.load(cid: cid, durationMs: 300000);
    feed.update(positionMs: 1000, playing: true);
    await feed.settle();
  }

  DanmakuDraft draft(String text, {int progressMs = 1400, bool gradient = false}) => DanmakuDraft(
        cid: 42,
        bvid: 'BV1GJ411x7h7',
        text: text,
        mode: 1,
        fontSize: 25,
        color: 0xFFFFFF,
        gradient: gradient,
        progressMs: progressMs,
      );

  group('filtering', () {
    final elems = [
      const DanmakuElem(id: 1, progressMs: 1000, content: '前方高能'),
      const DanmakuElem(id: 2, progressMs: 2000, content: '来了'),
      const DanmakuElem(id: 3, progressMs: 3000, content: '彩色', color: 0xFF0000),
    ];

    test('a 弹幕设置 change filters what is loaded again, into a new timeline', () async {
      await loaded(elems);
      final before = feed.timeline;
      var notified = 0;
      feed.addListener(() => notified++);

      feed.setFilter(const DanmakuFilterOptions(blockColored: true), const []);
      await feed.settle();

      expect(feed.timeline, isNot(same(before)));
      expect(notified, greaterThan(0));
      expect(texts(feed.timeline), ['前方高能', '来了']);
      expect([for (final elem in feed.recent(10000)) elem.content], ['前方高能', '来了']);

      feed.setFilter(const DanmakuFilterOptions(), const []);
      await feed.settle();
      expect(texts(feed.timeline), ['前方高能', '来了', '彩色']);
    });

    test('a 屏蔽词 change filters what is loaded again', () async {
      await loaded(elems);
      feed.setFilter(const DanmakuFilterOptions(), const [BlockRule(id: 1, kind: BlockRuleKind.keyword, filter: '来')]);
      await feed.settle();
      expect(texts(feed.timeline), ['前方高能', '彩色']);

      feed.setFilter(const DanmakuFilterOptions(), const [BlockRule(id: 2, kind: BlockRuleKind.regex, filter: '/^前方/')]);
      await feed.settle();
      expect(texts(feed.timeline), ['来了', '彩色']);
    });

    test('the same filter again changes nothing', () async {
      await loaded(elems);
      final before = feed.timeline;
      feed.setFilter(const DanmakuFilterOptions(), const []);
      await feed.settle();
      expect(feed.timeline, same(before));
    });

    test('a segment loaded later uses the current filter', () async {
      feed.setFilter(const DanmakuFilterOptions(blockColored: true), const [
        BlockRule(id: 1, kind: BlockRuleKind.keyword, filter: '高能'),
      ]);
      await loaded(elems);
      expect(texts(feed.timeline), ['来了']);
    });

    test('changes made while a re-filter runs end on the latest', () async {
      await loaded(elems);
      feed.setFilter(const DanmakuFilterOptions(blockColored: true), const []);
      feed.setFilter(const DanmakuFilterOptions(), const [BlockRule(id: 1, kind: BlockRuleKind.keyword, filter: '前方')]);
      await feed.settle();
      expect(texts(feed.timeline), ['来了', '彩色']);
    });

    test('the account\'s own danmaku from the server get the white box', () async {
      await loaded([
        const DanmakuElem(id: 1, progressMs: 1000, content: '别人的', midHash: 'abcdef'),
        DanmakuElem(id: 2, progressMs: 2000, content: '我的', midHash: MidHash.of(12345)),
      ]);
      expect([for (final item in walk(feed.timeline!, 5000)) item.isOwn], [false, false]);

      feed.ownMid = 12345;
      await feed.settle();
      expect([for (final item in walk(feed.timeline!, 5000)) (item.text, item.isOwn)], [('别人的', false), ('我的', true)]);

      feed.ownMid = 0;
      await feed.settle();
      expect([for (final item in walk(feed.timeline!, 5000)) item.isOwn], [false, false]);
    });
  });

  group('a sent danmaku', () {
    test('shows at once in its box though the playhead passed its time, without replaying the rest', () async {
      await loaded([
        const DanmakuElem(id: 1, progressMs: 1000, content: '前方高能'),
        const DanmakuElem(id: 2, progressMs: 2000, content: '来了'),
      ]);
      feed.ownMid = 12345;
      final scene = DanmakuScene()..size = const Size(400, 225);
      addTearDown(scene.dispose);
      List<String> onScreen() => [for (final item in scene.visible) item.text];

      scene.step(1.5, timeline: feed.timeline!);
      expect(onScreen(), ['前方高能']);

      feed.update(positionMs: 1500, playing: false);
      feed.addOwn(draft('我发的'), dmid: 9000);
      scene.step(1.5, timeline: feed.timeline!);
      expect(onScreen(), unorderedEquals(['前方高能', '我发的']), reason: 'shown while paused, once each');

      scene.step(2.1, timeline: feed.timeline!);
      expect(onScreen(), unorderedEquals(['前方高能', '我发的', '来了']));

      final own = walk(feed.timeline!, 5000).singleWhere((item) => item.text == '我发的');
      expect(own.isOwn, isTrue);
      expect(own.elem.id, 9000);
      expect(own.elem.progressMs, 1500, reason: 'at the playhead, as Swift does');
      expect(own.elem.midHash, MidHash.of(12345));
    });

    test('shows before any segment arrived, and keeps through a filter change', () async {
      http.dataRoutes[Canned.segmentPath] = (200, segmentOf(const [DanmakuElem(progressMs: 1000, content: '来了')]));
      final gate = Completer<void>();
      http.gates[Canned.segmentPath] = gate;
      feed.load(cid: 42, durationMs: 300000);
      feed.update(positionMs: 1000, playing: true);
      feed.addOwn(draft('抢先', progressMs: 900), dmid: 1);
      expect(texts(feed.timeline), ['抢先']);

      gate.complete();
      await feed.settle();
      expect(texts(feed.timeline), ['抢先', '来了'], reason: 'at 1000 ms both; the own one was there first');

      feed.setFilter(const DanmakuFilterOptions(blockScroll: true), const []);
      await feed.settle();
      expect(texts(feed.timeline), ['抢先'], reason: 'own danmaku are not filtered, as in Swift');
    });

    test('a gradient one carries the colourful flag', () async {
      await loaded(const [DanmakuElem(progressMs: 1000, content: '前方高能')]);
      feed.addOwn(draft('渐变', gradient: true), dmid: 5);
      expect(walk(feed.timeline!, 5000).singleWhere((item) => item.text == '渐变').elem.colorful, 60001);
    });
  });

  test('hide drops that danmaku for this video, until the next load', () async {
    final elems = [
      const DanmakuElem(id: 1, progressMs: 1000, content: '前方高能'),
      const DanmakuElem(id: 2, progressMs: 2000, content: '来了'),
    ];
    await loaded(elems);
    final before = feed.timeline;
    feed.hide(feed.recent(5000).first);
    expect(feed.timeline, isNot(same(before)));
    expect(texts(feed.timeline), ['来了']);
    expect([for (final elem in feed.recent(5000)) elem.content], ['来了']);

    feed.setFilter(const DanmakuFilterOptions(dedupe: true), const []);
    await feed.settle();
    expect(texts(feed.timeline), ['来了'], reason: 'still hidden after a re-filter');

    await loaded(elems, cid: 43);
    expect(texts(feed.timeline), ['前方高能', '来了']);
  });

  test('recent lists what showed up to the playhead, latest last, at most the limit', () async {
    await loaded([for (var i = 1; i <= 10; i++) DanmakuElem(id: i, progressMs: i * 1000, content: '第$i条')]);
    feed.update(positionMs: 5500, playing: true);
    feed.addOwn(draft('我发的', progressMs: 5400), dmid: 99);

    expect([for (final elem in feed.recent(6000)) elem.content], [
      for (var i = 1; i <= 5; i++) '第$i条',
      '我发的',
      '第6条',
    ]);
    expect([for (final elem in feed.recent(6000, limit: 3)) elem.content], ['第5条', '我发的', '第6条']);
    expect(feed.recent(500), isEmpty);

    feed.hide(feed.recent(6000).last);
    expect(feed.recent(6000, limit: 1).single.content, '我发的');
  });

  test('closing by the uploader notifies, and nothing shows after', () async {
    http.dataRoutes[Canned.segmentPath] = (200, danmakuSegmentBytes(const [], closed: true));
    feed.load(cid: 42, durationMs: 1000000);
    var notified = 0;
    feed.addListener(() => notified++);
    feed.update(positionMs: 1000, playing: true);
    await feed.settle();
    expect(feed.closed, isTrue);
    expect(notified, 1);

    feed.addOwn(draft('发不出'), dmid: 1);
    feed.setFilter(const DanmakuFilterOptions(blockColored: true), const []);
    await feed.settle();
    expect(feed.timeline, isNull);
    expect(feed.recent(5000), isEmpty);
  });
}
