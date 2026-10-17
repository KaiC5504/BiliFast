import 'package:bili_core/dash_hls.dart';
import 'package:bili_core/shared.dart';
import 'package:bili_core/src/dash_hls/c_format.dart';
import 'package:test/test.dart';

void main() {
  test('codec mapping', () {
    expect(CodecMapper.video(codecs: 'hev1.1.6.L153.90', qualityId: 120, sampleEntry: 'hvc1'),
        const HLSVideoCodec(codecs: 'hvc1.1.6.L153.90', supplemental: null, videoRange: 'SDR'));
    expect(CodecMapper.video(codecs: 'hev1.1.6.L153.90', qualityId: 120, sampleEntry: 'hev1').codecs, 'hev1.1.6.L153.90');
    expect(CodecMapper.video(codecs: 'hev1.1.6.L153.90', qualityId: 120, sampleEntry: null).codecs, 'hev1.1.6.L153.90');
    expect(CodecMapper.video(codecs: 'hev1.2.4.L153.90', qualityId: 125, sampleEntry: 'hvc1').videoRange, 'PQ');
    expect(CodecMapper.video(codecs: 'dvh1.08.07', qualityId: 126, sampleEntry: 'hvc1'),
        const HLSVideoCodec(codecs: 'hvc1.2.4.L153.b0', supplemental: 'dvh1.08.07/db4h', videoRange: 'HLG'));
    expect(CodecMapper.video(codecs: 'dvh1.08.06', qualityId: 126, sampleEntry: 'hvc1'),
        const HLSVideoCodec(codecs: 'hvc1.2.4.L150', supplemental: 'dvh1.08.06/db1p', videoRange: 'PQ'));
    expect(CodecMapper.video(codecs: 'dvh1.05.06', qualityId: 126, sampleEntry: 'dvh1').videoRange, 'PQ');
    expect(CodecMapper.video(codecs: 'avc1.640034', qualityId: 80, sampleEntry: 'avc1').codecs, 'avc1.640034');
  });

  test('frame rate formatting', () {
    expect(CodecMapper.frameRate('29.412'), '29.412');
    expect(CodecMapper.frameRate('60'), '60.000');
    expect(CodecMapper.frameRate(null), '30.000');
    expect(CodecMapper.frameRate('abc'), '30.000');
    expect(CodecMapper.frameRate('inf'), '30.000');
    expect(CodecMapper.frameRate('0'), '30.000');
    expect(CodecMapper.frameRate('-24'), '30.000');
  });

  test('frame rate text is read the way Swift Double(String) reads it', () {
    // Expected values printed by Swift 6.4 (Double(text) and String(format: "%.3f")).
    expect(CodecMapper.frameRate(' 60'), '30.000');
    expect(CodecMapper.frameRate('60 '), '30.000');
    expect(CodecMapper.frameRate('Infinity'), '30.000');
    expect(CodecMapper.frameRate('nan'), '30.000');
    expect(CodecMapper.frameRate('1e400'), '30.000');
    expect(CodecMapper.frameRate('1e-400'), '30.000');
    expect(CodecMapper.frameRate('16000/672'), '30.000');
    expect(CodecMapper.frameRate(''), '30.000');
    expect(CodecMapper.frameRate('30,0'), '30.000');
    expect(CodecMapper.frameRate('1_0'), '30.000');
    expect(CodecMapper.frameRate('+30'), '30.000');
    expect(CodecMapper.frameRate('+25'), '25.000');
    expect(CodecMapper.frameRate('.5'), '0.500');
    expect(CodecMapper.frameRate('5.'), '5.000');
    expect(CodecMapper.frameRate('1.e1'), '10.000');
    expect(CodecMapper.frameRate('+.5e1'), '5.000');
    expect(CodecMapper.frameRate('29.4115'), '29.412');
    expect(CodecMapper.frameRate('29.4125'), '29.413');
  });

  test('%.3f matches C printf, ties to even included', () {
    // Expected values printed by Swift 6.4's String(format: "%.3f"). Dart's toStringAsFixed rounds an exact
    // tie up (0.0625 -> 0.063) and switches to exponent notation from 1e21.
    const cases = [
      (4.0005, '4.000'),
      (2.9995, '2.999'),
      (0.0625, '0.062'),
      (4.0625, '4.062'),
      (4.9375, '4.938'),
      (2.5625, '2.562'),
      (0.1875, '0.188'),
      (0.0005, '0.001'),
      (0.0015, '0.002'),
      (1.0005, '1.000'),
      (0.9995, '1.000'),
      (9.9995, '9.999'),
      (99.9995, '99.999'),
      (1.9999995, '2.000'),
      (4.004, '4.004'),
      (3.5, '3.500'),
      (0.0, '0.000'),
      (5e-324, '0.000'),
      (123456789.0625, '123456789.062'),
      (2000000000.0625, '2000000000.062'),
      (4294967295.0, '4294967295.000'),
      (9007199254740993.0, '9007199254740992.000'),
      (1e21, '1000000000000000000000.000'),
      (1e22, '10000000000000000000000.000'),
      (-1.0625, '-1.062'),
    ];
    for (final (value, expected) in cases) {
      expect(formatFixed(value, 3), expected, reason: '$value');
    }
    expect(formatFixed(79000 / 16000, 3), '4.938');
    expect(formatFixed(65000 / 16000, 3), '4.062');
    expect(formatFixed(1001 / 30000 * 120, 3), '4.004');
    expect(formatFixed(-0.0, 3), '-0.000');
    expect(formatFixed(double.nan, 3), 'nan');
    expect(formatFixed(double.infinity, 3), 'inf');
    expect(formatFixed(double.negativeInfinity, 3), '-inf');
  });

  test('media playlist', () {
    final segments = [
      MediaSegment(index: 0, range: ByteRange(1689, 50000), startTime: 0, duration: 4.004),
      MediaSegment(index: 1, range: ByteRange(50001, 90000), startTime: 4.004, duration: 3.5),
    ];
    final text = PlaylistBuilder.media(HLSTrack(uri: 'v.mp4', initRange: ByteRange(0, 1104), segments: segments));
    expect(text, '''
#EXTM3U
#EXT-X-VERSION:7
#EXT-X-TARGETDURATION:5
#EXT-X-MEDIA-SEQUENCE:0
#EXT-X-PLAYLIST-TYPE:VOD
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-MAP:URI="v.mp4",BYTERANGE="1105@0"
#EXTINF:4.004,
#EXT-X-BYTERANGE:48312@1689
v.mp4
#EXTINF:3.500,
#EXT-X-BYTERANGE:40000@50001
v.mp4
#EXT-X-ENDLIST
''');
  });

  test('media playlist durations at an exact tie round to even', () {
    final segments = [
      MediaSegment(index: 0, range: ByteRange(100, 199), startTime: 0, duration: 65000 / 16000),
      MediaSegment(index: 1, range: ByteRange(200, 299), startTime: 4.0625, duration: 79000 / 16000),
    ];
    final text = PlaylistBuilder.media(HLSTrack(uri: 'a.mp4', initRange: ByteRange(0, 99), segments: segments));
    expect(text, contains('#EXTINF:4.062,\n'));
    expect(text, contains('#EXTINF:4.938,\n'));
  });

  test('media playlist target duration is the ceiling of the longest segment', () {
    String target(List<double> durations) {
      final segments = [
        for (final (index, duration) in durations.indexed)
          MediaSegment(index: index, range: ByteRange(index * 100, index * 100 + 99), startTime: 0, duration: duration),
      ];
      final text = PlaylistBuilder.media(HLSTrack(uri: 'v.mp4', initRange: ByteRange(0, 9), segments: segments));
      return text.split('\n').firstWhere((line) => line.startsWith('#EXT-X-TARGETDURATION'), orElse: () => '');
    }

    expect(target([4.0]), '#EXT-X-TARGETDURATION:4');
    expect(target([4.0, 4.01]), '#EXT-X-TARGETDURATION:5');
    expect(target([0.4]), '#EXT-X-TARGETDURATION:1');
    expect(target([]), '#EXT-X-TARGETDURATION:1');
  });

  test('master playlist', () {
    const variant = HLSVariant(
      codec: HLSVideoCodec(codecs: 'hvc1.2.4.L153.b0', supplemental: 'dvh1.08.07/db4h', videoRange: 'HLG'),
      audioCodecs: 'mp4a.40.2',
      averageBandwidth: 12320000,
      width: 3840,
      height: 2160,
      frameRate: '29.412',
    );
    expect(PlaylistBuilder.master(variant, videoPlaylist: 'v.m3u8', audioPlaylist: 'a.m3u8'), '''
#EXTM3U
#EXT-X-VERSION:7
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="default",DEFAULT=YES,AUTOSELECT=YES,URI="a.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=18480000,AVERAGE-BANDWIDTH=12320000,CODECS="hvc1.2.4.L153.b0,mp4a.40.2",SUPPLEMENTAL-CODECS="dvh1.08.07/db4h",RESOLUTION=3840x2160,FRAME-RATE=29.412,VIDEO-RANGE=HLG,AUDIO="audio"
v.m3u8
''');
  });

  test('master playlist omits SUPPLEMENTAL-CODECS when absent', () {
    const variant = HLSVariant(
      codec: HLSVideoCodec(codecs: 'avc1.640034', supplemental: null, videoRange: 'SDR'),
      audioCodecs: 'mp4a.40.2',
      averageBandwidth: 1000000,
      width: 1920,
      height: 1080,
      frameRate: '30.000',
    );
    final text = PlaylistBuilder.master(variant, videoPlaylist: 'v.m3u8', audioPlaylist: 'a.m3u8');
    expect(text, isNot(contains('SUPPLEMENTAL-CODECS')));
    expect(text,
        contains('BANDWIDTH=1500000,AVERAGE-BANDWIDTH=1000000,CODECS="avc1.640034,mp4a.40.2",RESOLUTION=1920x1080'));
  });

  test('master playlist BANDWIDTH truncates like Swift Int(Double * 1.5)', () {
    for (final (average, peak) in [(12320001, 18480001), (1, 1), (3, 4)]) {
      final variant = HLSVariant(
        codec: const HLSVideoCodec(codecs: 'avc1.640034', supplemental: null, videoRange: 'SDR'),
        audioCodecs: 'mp4a.40.2',
        averageBandwidth: average,
        width: 1920,
        height: 1080,
        frameRate: '30.000',
      );
      expect(PlaylistBuilder.master(variant, videoPlaylist: 'v.m3u8', audioPlaylist: 'a.m3u8'),
          contains('BANDWIDTH=$peak,AVERAGE-BANDWIDTH=$average,'));
    }
  });
}
