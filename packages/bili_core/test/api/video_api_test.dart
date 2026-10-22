import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:test/test.dart';

import 'fake_http.dart';
import 'fixtures.dart';

const navPath = '/x/web-interface/nav';
const viewPath = '/x/web-interface/wbi/view';
const playerPath = '/x/player/wbi/v2';
const relatedPath = '/x/web-interface/archive/related';
const onlinePath = '/x/player/online/total';
const heartbeatPath = '/x/click-interface/web/heartbeat';
const watchLaterPath = '/x/v2/history/toview/add';

T decode<T>(String json, T Function(Object? json) decoder) => decodeEnvelope(json, decoder).data as T;

void main() {
  late FakeHTTP fakeHTTP;
  late BiliClient client;

  setUp(() {
    fakeHTTP = FakeHTTP();
    fakeHTTP.routes[navPath] = (200, Fixtures.navLoggedIn);
    client = BiliClient(
        transport: fakeHTTP,
        cookies: CookieJar({'bili_jct': 'T', 'SESSDATA': 's', 'buvid3': 'b3', 'buvid4': 'b4'}),
        now: () => testNow,
        logger: Logger(session: 'test'));
  });

  group('the seek preview', () {
    // Made-up sheets of 2 × 2 frames, every 5 s; the index opens with its extra 0.
    const answer = '''
{"code":0,"message":"0","ttl":1,"data":{"pvdata":"//i0.hdslb.com/bfs/videoshot/x.bin",
 "img_x_len":2,"img_y_len":2,"img_x_size":160,"img_y_size":90,
 "image":["//i0.hdslb.com/bfs/videoshot/a.jpg","http://i0.hdslb.com/bfs/videoshot/b.jpg"],
 "index":[0,0,5,10,15,20,25]}}''';

    test('asks for the frames with their times and reads the sheets over https', () async {
      fakeHTTP.routes['/x/player/videoshot'] = (200, answer);
      final shot = await client.videoShot(bvid: 'BV1GJ411x7h7', cid: 99);
      expect(fakeHTTP.query(fakeHTTP.requestsTo('/x/player/videoshot').single), {
        'bvid': 'BV1GJ411x7h7',
        'cid': '99',
        'index': '1',
      });
      expect(shot.sheets, ['https://i0.hdslb.com/bfs/videoshot/a.jpg', 'https://i0.hdslb.com/bfs/videoshot/b.jpg']);
      expect((shot.columns, shot.rows, shot.cellWidth, shot.cellHeight), (2, 2, 160.0, 90.0));
      expect(shot.usable, isTrue);
    });

    test('a time finds the frame shown last before it, across sheets, held at the ends', () {
      final shot = VideoShot.fromJson(decode(answer, (json) => json));
      expect(shot.frameAt(0), (sheet: shot.sheets[0], column: 0, row: 0));
      expect(shot.frameAt(4.9), (sheet: shot.sheets[0], column: 0, row: 0));
      expect(shot.frameAt(5), (sheet: shot.sheets[0], column: 1, row: 0));
      expect(shot.frameAt(12), (sheet: shot.sheets[0], column: 0, row: 1));
      expect(shot.frameAt(20), (sheet: shot.sheets[1], column: 0, row: 0));
      expect(shot.frameAt(999), (sheet: shot.sheets[1], column: 1, row: 0));
    });

    test('an answer without frames is unusable and finds none', () {
      final shot = VideoShot.fromJson(<String, Object?>{'image': <Object?>[], 'index': <Object?>[]});
      expect(shot.usable, isFalse);
      expect(shot.frameAt(10), isNull);
    });
  });

  test('video detail decodes season, staff, stats and shape', () async {
    fakeHTTP.routes[viewPath] = (200, Fixtures.viewDetail);
    final detail = await client.videoDetail(bvid: 'BV1GJ411x7h7');
    expect(detail.season?.sections.map((section) => section.episodes.length), [2, 1]);
    expect(detail.season?.sections[0].episodes[1].cid, 137649300);
    expect(detail.stat.like, 9131);
    expect(detail.isVertical, isTrue);
    expect(detail.honor, '活动');
    expect(detail.descParts.last.mentionMid, 42);
    expect(fakeHTTP.query(fakeHTTP.requestsTo(viewPath)[0])['w_rid'], isNotNull);
    expect(fakeHTTP.query(fakeHTTP.requestsTo(viewPath)[0])['bvid'], 'BV1GJ411x7h7');
  });

  test('video detail fields and a season episode from arc', () {
    final detail = decode(Fixtures.viewDetail, VideoDetail.fromJson);
    expect(detail.bvid, 'BV1GJ411x7h7');
    expect(detail.aid, 80433022);
    expect(detail.title, '测试视频');
    expect(detail.cover, 'https://i0.hdslb.com/bfs/archive/cover-0001.jpg');
    expect(detail.pubdate, 1760000000);
    expect(detail.duration, 312);
    expect(detail.copyright, 1);
    expect(detail.owner, const VideoOwner(mid: 1, name: 'UP主', face: 'https://i0.hdslb.com/bfs/face/face-0001.jpg'));
    expect(detail.stat.view, 123456);
    expect(detail.stat.favorite, 7890);
    expect(detail.pages.map((page) => page.cid), [137649199, 137649200]);
    expect(detail.staff, isEmpty);
    expect(detail.redirectURL, isNull);
    expect(detail.descParts, const [DescPart(text: '视频简介 '), DescPart(text: '测试用户', mentionMid: 42)]);
    final season = detail.season!;
    expect(season.title, '测试合集');
    expect(season.sections.map((section) => section.title), ['正片', '特别篇']);
    expect(
        season.sections[0].episodes[1],
        const SeasonEpisode(
            aid: 80433100,
            bvid: 'BV1AB411c7mD',
            cid: 137649300,
            title: '第二集',
            cover: 'https://i0.hdslb.com/bfs/archive/ep-0002.jpg',
            duration: 300,
            pubdate: 1760000500,
            views: 2000,
            danmaku: 20));
  });

  test('a rotated file swaps the displayed shape', () {
    final rotated = Fixtures.viewDetail.replaceAll('"rotate":0', '"rotate":1');
    final detail = decode(rotated, VideoDetail.fromJson);
    expect(detail.isVertical, isFalse);
    expect(detail.width, 1920);
    expect(detail.height, 1080);
  });

  test('hidden counts and broken elements do not fail the detail', () {
    final hidden = Fixtures.viewDetail
        .replaceAll('"view":123456', '"view":"--"')
        .replaceAll('"cid":137649400,"title":"番外","bvid":"BV1CD411d8nE"', '"cid":137649400,"title":"番外"');
    final detail = decode(hidden, VideoDetail.fromJson);
    expect(detail.stat.view, 0);
    expect(detail.stat.like, 9131);
    // The special section's only episode has no bvid in either place, so it is dropped but the section stays.
    expect(detail.season?.sections.map((section) => section.episodes.length), [2, 0]);
  });

  test('a wrong type in decorative blocks does not fail the detail', () {
    final broken = Fixtures.viewDetail
        .replaceAll('"staff":[]', '"staff":"none"')
        .replaceAll(
            '"desc_v2":[{"raw_text":"视频简介 ","type":1,"biz_id":0},{"raw_text":"测试用户","type":2,"biz_id":42}]', '"desc_v2":"oops"')
        .replaceAll('"honor_reply":{"honor":[{"aid":80433022,"type":4,"desc":"活动","weekly_recommend_num":0}]}',
            '"honor_reply":{"honor":"none"}');
    expect(broken.contains('"staff":"none"') && broken.contains('"desc_v2":"oops"') && broken.contains('"honor":"none"'),
        isTrue);
    final detail = decode(broken, VideoDetail.fromJson);
    expect(detail.staff, isEmpty);
    expect(detail.descParts, const [DescPart(text: '视频简介 @测试用户')]);
    expect(detail.honor, isNull);
    expect(detail.title, '测试视频');
    expect(detail.pages.length, 2);
  });

  test('the argue notice is read from argue_info', () {
    String withArgue(String argue) => Fixtures.viewDetail.replaceAll('"staff":[],', '"staff":[],"argue_info":$argue,');
    final notice = decode(
        withArgue('{"argue_msg":"个人观点，仅供参考","argue_type":0,"argue_link":""}'), VideoDetail.fromJson);
    expect(notice.argueMessage, '个人观点，仅供参考');
    expect(notice, isNot(decode(Fixtures.viewDetail, VideoDetail.fromJson)));
  });

  test('an empty, blank, missing or malformed argue notice is none', () {
    String withArgue(String argue) => Fixtures.viewDetail.replaceAll('"staff":[],', '"staff":[],"argue_info":$argue,');
    expect(withArgue('null').contains('"argue_info":null'), isTrue);
    expect(decode(Fixtures.viewDetail, VideoDetail.fromJson).argueMessage, isNull);
    for (final argue in [
      '{"argue_msg":"","argue_type":0,"argue_link":""}',
      '{"argue_msg":"  ","argue_type":0}',
      '{"argue_type":0}',
      '{"argue_msg":5}',
      '"none"',
      'null',
    ]) {
      final detail = decode(withArgue(argue), VideoDetail.fromJson);
      expect(detail.argueMessage, isNull, reason: argue);
      expect(detail.title, '测试视频', reason: argue);
    }
  });

  test('a description without parts falls back to the plain text', () {
    final plain = Fixtures.viewDetail.replaceAll(
        '"desc_v2":[{"raw_text":"视频简介 ","type":1,"biz_id":0},{"raw_text":"测试用户","type":2,"biz_id":42}],', '"desc_v2":null,');
    final detail = decode(plain, VideoDetail.fromJson);
    expect(detail.descParts, const [DescPart(text: '视频简介 @测试用户')]);
  });

  test('player info keeps chapters only for type 2', () async {
    fakeHTTP.routes[playerPath] = (200, Fixtures.playerV2);
    final info = await client.playerInfo(bvid: 'BV1GJ411x7h7', cid: 137649199);
    expect(info.lastPlayCid, 137649200);
    expect(info.chapters, const [
      Chapter(from: 0, to: 60, title: '开场'),
      Chapter(from: 60, to: 150, title: '正片'),
      Chapter(from: 150, to: 212, title: '结尾'),
    ]);
    final query = fakeHTTP.query(fakeHTTP.requestsTo(playerPath)[0]);
    expect(query['cid'], '137649199');
    expect(query['w_rid'], isNotNull);

    fakeHTTP.routes[playerPath] = (200, Fixtures.playerV2Highlights);
    final highlights = await client.playerInfo(bvid: 'BV1GJ411x7h7', cid: 137649199);
    expect(highlights.chapters, isEmpty);
  });

  test('related drops redirected items', () async {
    fakeHTTP.routes[relatedPath] = (200, Fixtures.related);
    final cards = await client.related(bvid: 'BV1GJ411x7h7');
    expect(cards, const [
      VideoCard(
          aid: 90000001,
          bvid: 'BV1EF411e9oF',
          cid: 137650001,
          title: '相关视频一',
          cover: 'https://i0.hdslb.com/bfs/archive/rel-0001.jpg',
          duration: 605,
          ownerMid: 77,
          ownerName: '另一个UP',
          views: 50000,
          danmaku: 120,
          likes: 1500),
    ]);
    expect(fakeHTTP.query(fakeHTTP.requestsTo(relatedPath)[0])['bvid'], 'BV1GJ411x7h7');
  });

  test('related drops items without a bvid', () async {
    fakeHTTP.routes[relatedPath] = (200, Fixtures.related.replaceAll('"bvid":"BV1EF411e9oF"', '"bvid":""'));
    expect(await client.related(bvid: 'BV1GJ411x7h7'), isEmpty);
  });

  test('related with null data is empty', () async {
    fakeHTTP.routes[relatedPath] = (200, '{"code":0,"message":"0","data":null}');
    expect(await client.related(bvid: 'BV1GJ411x7h7'), isEmpty);
  });

  test('related still throws on an API error', () async {
    fakeHTTP.routes[relatedPath] = (200, '{"code":-404,"message":"啥都木有","data":null}');
    await expectLater(client.related(bvid: 'BV1GJ411x7h7'),
        throwsA(isA<BiliAPIError>().having((error) => error.code, 'code', -404)));
  });

  test('the online count is the display string', () async {
    fakeHTTP.routes[onlinePath] = (200, Fixtures.online);
    final total = await client.onlineCount(aid: 80433022, bvid: 'BV1GJ411x7h7', cid: 137649199);
    expect(total, '1.2万+');
    final query = fakeHTTP.query(fakeHTTP.requestsTo(onlinePath)[0]);
    expect(query['aid'], '80433022');
    expect(query['cid'], '137649199');
    expect(query['bvid'], 'BV1GJ411x7h7');
  });

  test('heartbeat form fields', () async {
    fakeHTTP.routes[heartbeatPath] = (200, '{"code":0,"message":"0","ttl":1}');
    await client.heartbeat(bvid: 'BV1', cid: 2, playedTime: -1);
    final request = fakeHTTP.requestsTo(heartbeatPath).first;
    expect(request.method, 'POST');
    expect(fakeHTTP.bodyText(request), 'bvid=BV1&cid=2&csrf=T&played_time=-1&type=3');
  });

  test('add to watch later form', () async {
    fakeHTTP.routes[watchLaterPath] = (200, '{"code":0,"message":"0","ttl":1,"data":null}');
    await client.addToWatchLater(aid: 80433022);
    expect(fakeHTTP.bodyText(fakeHTTP.requestsTo(watchLaterPath).first), 'aid=80433022&csrf=T');
  });

  test('play URL carries resume fields', () {
    final resumed = decode(Fixtures.playURLResume, PlayURLInfo.fromJson);
    expect(resumed.lastPlayTimeMs, 65000);
    expect(resumed.lastPlayCid, 137649199);
    final old = decode(Fixtures.playURL, PlayURLInfo.fromJson);
    expect(old.lastPlayTimeMs, 0);
    expect(old.lastPlayCid, 0);
  });
}
