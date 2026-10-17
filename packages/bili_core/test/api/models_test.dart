import 'package:bili_core/api.dart';
import 'package:bili_core/shared.dart';
import 'package:test/test.dart';

import 'fake_http.dart';
import 'fixtures.dart';

String playURL(List<String> video, {List<String> audio = const [], String extra = ''}) =>
    '{"code":0,"data":{"quality":80,"dash":{"duration":10,"video":[${video.join(',')}],"audio":[${audio.join(',')}]}$extra}}';

String stream({int id = 80, required String extra}) =>
    '{"id":$id,"baseUrl":"https://h/a.m4s","bandwidth":1,"mimeType":"video/mp4","codecs":"avc1","codecid":7,$extra}';

const goodBase = '"SegmentBase":{"Initialization":"0-9","indexRange":"10-19"}';

void main() {
  test('nav logged out still carries WBI keys', () {
    final envelope = decodeEnvelope(Fixtures.navLoggedOut, NavInfo.fromJson);
    expect(envelope.code, -101);
    expect(envelope.data?.isLogin, false);
    expect(envelope.data?.imgURL, 'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png');
  });

  test('nav logged in', () {
    final nav = decodeEnvelope(Fixtures.navLoggedIn, NavInfo.fromJson).data!;
    expect(nav.isLogin, isTrue);
    expect(nav.isVip, isTrue);
    expect(nav.mid, 12345);
    expect(nav.uname, '测试用户');
    expect(nav.face, 'https://i0.hdslb.com/bfs/face/test.jpg');
  });

  test('view', () {
    final view = decodeEnvelope(Fixtures.view, VideoView.fromJson).data!;
    expect(view.bvid, 'BV1GJ411x7h7');
    expect(view.owner, 'UP主');
    expect(view.pages.map((page) => page.cid), [137649199, 137649200]);
    expect(view.pages[1].part, '第二集');
  });

  test('error envelope without data', () {
    final envelope = decodeEnvelope(Fixtures.notFound, VideoView.fromJson);
    expect(envelope.code, -404);
    expect(envelope.data, isNull);
  });

  test('play URL field spellings', () {
    final info = decodeEnvelope(Fixtures.playURL, PlayURLInfo.fromJson).data!;
    final dash = info.dash!;
    expect(dash.duration, 214);
    expect(dash.video.length, 4);
    final hevc = dash.video[0];
    expect(hevc.baseURL, 'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/3-1-100151.m4s?deadline=1760000000&os=cosbv');
    expect(hevc.backupURLs.length, 1);
    expect(hevc.initialization, ByteRange(0, 1104));
    expect(hevc.indexRange, ByteRange(1105, 1688));
    expect(hevc.frameRate, '29.412');
    final snake = dash.video[1];
    expect(snake.backupURLs, isEmpty);
    expect(snake.frameRate, isNull);
    expect(snake.indexRange, ByteRange(1001, 1600));
    expect(dash.audio.map((stream) => stream.id), [30216, 30280]);
    expect(info.hasDurl, isFalse);
    expect(info.qualityOptions.first, const QualityOption(id: 127, name: '超高清 8K'));
  });

  test('durl only has no dash', () {
    final info = decodeEnvelope(Fixtures.durlOnly, PlayURLInfo.fromJson).data!;
    expect(info.dash, isNull);
    expect(info.hasDurl, isTrue);
  });

  test('snake case only stream decodes every field', () {
    final snake = decodeEnvelope(Fixtures.playURL, PlayURLInfo.fromJson).data!.dash!.video[1];
    expect(snake.baseURL, 'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/3-1-100048.m4s?deadline=1760000000');
    expect(snake.mimeType, 'video/mp4');
    expect(snake.initialization, ByteRange(0, 1000));
  });

  test('camel case only stream decodes every field', () {
    final av1 = decodeEnvelope(Fixtures.playURL, PlayURLInfo.fromJson).data!.dash!.video[2];
    expect(av1.baseURL, 'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/3-1-100113.m4s?deadline=1760000000');
    expect(av1.mimeType, 'video/mp4');
    expect(av1.initialization, ByteRange(0, 900));
    expect(av1.indexRange, ByteRange(901, 1500));
    expect(av1.frameRate, '29.412');
  });

  test('null backupUrl decodes as empty', () {
    final dash = decodeEnvelope(Fixtures.playURL, PlayURLInfo.fromJson).data!.dash!;
    expect(dash.video[3].backupURLs, isEmpty);
    expect(dash.audio[0].backupURLs, isEmpty);
  });

  test('empty frame rate decodes as null', () {
    final dash = decodeEnvelope(Fixtures.playURL, PlayURLInfo.fromJson).data!.dash!;
    expect(dash.audio[0].frameRate, isNull);
  });

  test('unknown fields are ignored', () {
    // The playURL fixture already carries dolby, flac, minBufferTime and format beside the modelled fields.
    final info = decodeEnvelope(Fixtures.playURL, PlayURLInfo.fromJson).data!;
    expect(info.quality, 120);
    const extra = '{"code":0,"message":"0","brand_new":{"x":[1,2]},"data":{"bvid":"BV1GJ411x7h7","future_field":null,'
        '"pages":[{"cid":1,"page":1,"part":"p","duration":3,"dimension":{"width":1}}]}}';
    final view = decodeEnvelope(extra, VideoView.fromJson).data!;
    expect(view.pages.map((page) => page.cid), [1]);
  });

  test('dash null with durl decodes', () {
    const json = '{"code":0,"message":"0","data":{"quality":16,"accept_quality":[16],"accept_description":["流畅 360P"],'
        '"dash":null,"durl":[{"order":1,"url":"https://x/a.flv"}]}}';
    final info = decodeEnvelope(json, PlayURLInfo.fromJson).data!;
    expect(info.dash, isNull);
    expect(info.hasDurl, isTrue);
  });

  test('bare minimum play URL decodes', () {
    final info = decodeEnvelope('{"code":0,"data":{}}', PlayURLInfo.fromJson).data!;
    expect(info.dash, isNull);
    expect(info.hasDurl, isFalse);
    expect(info.qualityOptions, isEmpty);
  });

  test('stream without SegmentBase is dropped, not fatal', () {
    final json = playURL(
      [stream(id: 64, extra: goodBase), stream(id: 80, extra: '"width":1'), stream(id: 120, extra: goodBase)],
      audio: ['{"id":30280,"codecs":"mp4a.40.2"}', stream(id: 30216, extra: goodBase)],
    );
    final dash = decodeEnvelope(json, PlayURLInfo.fromJson).data!.dash!;
    expect(dash.video.map((stream) => stream.id), [64, 120]);
    expect(dash.audio.map((stream) => stream.id), [30216]);
  });

  test('stream without base URL is dropped', () {
    const noURL = '{"id":80,"codecs":"avc1","SegmentBase":{"Initialization":"0-9","indexRange":"10-19"}}';
    final dash = decodeEnvelope(playURL([noURL, stream(id: 64, extra: goodBase)]), PlayURLInfo.fromJson).data!.dash!;
    expect(dash.video.map((stream) => stream.id), [64]);
  });

  test('incomplete SegmentBase falls through to the other spelling', () {
    final both =
        stream(extra: '"SegmentBase":{"Initialization":"0-9"},"segment_base":{"initialization":"0-5","index_range":"6-11"}');
    final dash = decodeEnvelope(playURL([both]), PlayURLInfo.fromJson).data!.dash!;
    expect(dash.video.first.initialization, ByteRange(0, 5));
    expect(dash.video.first.indexRange, ByteRange(6, 11));
    final reverse =
        stream(extra: '"segment_base":{"index_range":"junk"},"SegmentBase":{"Initialization":"0-9","indexRange":"10-19"}');
    final other = decodeEnvelope(playURL([reverse]), PlayURLInfo.fromJson).data!.dash!;
    expect(other.video.first.indexRange, ByteRange(10, 19));
  });

  test('frame rate only in snake case', () {
    final dash =
        decodeEnvelope(playURL([stream(extra: '$goodBase,"frame_rate":"25"')]), PlayURLInfo.fromJson).data!.dash!;
    expect(dash.video.first.frameRate, '25');
  });

  test('backupUrl only in snake case', () {
    final dash = decodeEnvelope(playURL([stream(extra: '$goodBase,"backup_url":["https://h/b.m4s"]')]), PlayURLInfo.fromJson)
        .data!
        .dash!;
    expect(dash.video.first.backupURLs, ['https://h/b.m4s']);
  });

  test('hasDurl needs a non-empty array', () {
    for (final (extra, expected) in [
      (',"durl":null', false),
      (',"durl":[]', false),
      ('', false),
      (',"durl":[{"order":1,"url":"https://x/a.flv"}]', true),
    ]) {
      final info = decodeEnvelope(playURL([], extra: extra), PlayURLInfo.fromJson).data!;
      expect(info.hasDurl, expected, reason: extra);
    }
  });

  test('SPI', () {
    final spi = decodeEnvelope(Fixtures.spi, SPIInfo.fromJson).data!;
    expect(spi.b3, 'B3-VALUE-infoc');
    expect(spi.b4, 'B4-VALUE');
  });
}
