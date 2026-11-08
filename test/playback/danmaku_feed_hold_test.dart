import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bilifast/playback/danmaku_feed.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CannedHttp http;
  late DanmakuFeed feed;

  setUp(() {
    http = Canned.http();
    final logger = Logger(session: 'test');
    final client = BiliClient(transport: http, cookies: CookieJar(Canned.cookies), logger: logger);
    feed = DanmakuFeed(client: client, logger: logger);
  });

  tearDown(() => feed.dispose());

  List<String> asked() => [
        for (final request in http.to(Canned.segmentPath)) request.url.queryParameters['segment_index']!,
      ];

  test('held, the playhead is followed and nothing is fetched; lifted, its segment and the next are fetched at once',
      () async {
    feed.load(cid: 42, durationMs: 700000);
    feed.holdFetches(true);
    feed.update(positionMs: 1000, playing: true);
    feed.update(positionMs: 340000, playing: true);
    await feed.settle();
    expect(asked(), isEmpty);

    feed.holdFetches(false);
    await feed.settle();
    expect(asked(), ['1', '2'], reason: 'playing within 30 s of the next segment, as an update would');
  });

  test('lifted while paused, only the segment under the playhead is fetched', () async {
    feed.load(cid: 42, durationMs: 700000);
    feed.holdFetches(true);
    feed.update(positionMs: 340000, playing: false);
    feed.holdFetches(false);
    await feed.settle();
    expect(asked(), ['1']);
  });

  test('a seek while held is where the fetch starts once lifted', () async {
    feed.load(cid: 42, durationMs: 1000000);
    feed.update(positionMs: 1000, playing: true);
    await feed.settle();
    feed.holdFetches(true);
    feed.seeked(400000);
    feed.holdFetches(false);
    await feed.settle();
    expect(asked(), ['1', '2']);
  });

  test('the hold outlasts a new video, and lifting it before any reading fetches nothing', () async {
    feed.holdFetches(true);
    feed.load(cid: 42, durationMs: 700000);
    feed.update(positionMs: 1000, playing: true);
    await feed.settle();
    expect(asked(), isEmpty);

    feed.load(cid: 43, durationMs: 700000);
    feed.holdFetches(false);
    await feed.settle();
    expect(asked(), isEmpty, reason: 'the new video has no playhead yet');

    feed.update(positionMs: 1000, playing: true);
    await feed.settle();
    expect(http.to(Canned.segmentPath).single.url.queryParameters['oid'], '43');
  });

  test('lifting a hold that was never set, or twice, asks nothing more', () async {
    feed.load(cid: 42, durationMs: 700000);
    feed.update(positionMs: 1000, playing: true);
    await feed.settle();
    feed.holdFetches(false);
    feed.holdFetches(true);
    feed.holdFetches(false);
    feed.holdFetches(false);
    await feed.settle();
    expect(asked(), ['1']);
  });
}
