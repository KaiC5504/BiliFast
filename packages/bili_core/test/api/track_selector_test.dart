import 'package:bili_core/api.dart';
import 'package:test/test.dart';

import 'fake_http.dart';
import 'fixtures.dart';

void main() {
  late Dash dash;

  setUp(() {
    dash = decodeEnvelope(Fixtures.playURL, PlayURLInfo.fromJson).data!.dash!;
  });

  test('prefers requested codec at requested quality', () {
    expect(TrackSelector.choose(dash, quality: 120, codecOrder: [VideoCodec.hevc, VideoCodec.avc])?.video.codecs,
        'hev1.1.6.L153.90');
    expect(TrackSelector.choose(dash, quality: 120, codecOrder: [VideoCodec.avc])?.video.codecs, 'avc1.640034');
  });

  test('falls to next lower quality and any codec', () {
    final choice = TrackSelector.choose(dash, quality: 116, codecOrder: [VideoCodec.hevc]);
    expect(choice?.video.id, 80);
    expect(choice?.video.codecid, 13);
  });

  test('Dolby Vision is chosen when it is the requested quality', () {
    expect(TrackSelector.choose(dash, quality: 127, codecOrder: [VideoCodec.hevc])?.video.id, 126);
  });

  test('quality below everything picks lowest', () {
    expect(TrackSelector.choose(dash, quality: 16, codecOrder: [VideoCodec.hevc])?.video.id, 80);
  });

  test('best audio and kinds', () {
    expect(TrackSelector.bestAudio(dash.audio)?.id, 30280);
    expect(TrackSelector.codecKind(dash.video[3]), 'dolby');
    expect(TrackSelector.codecKind(dash.video[0]), 'hevc');
    expect(TrackSelector.codecKind(dash.video[2]), 'av1');
    expect(TrackSelector.codecKind(dash.video[1]), 'avc');
  });

  test('requested codec at lower quality', () {
    final choice = TrackSelector.choose(dash, quality: 80, codecOrder: [VideoCodec.av1]);
    expect(choice?.video.codecid, 13);
    expect(choice?.video.id, 80);
  });

  test('best audio ignores order and non-AAC', () {
    final template = dash.audio.first;
    DashStream audio(int id, {required int bandwidth, String codecs = 'mp4a.40.2'}) => DashStream(
          id: id,
          baseURL: template.baseURL,
          backupURLs: const [],
          bandwidth: bandwidth,
          mimeType: 'audio/mp4',
          codecs: codecs,
          codecid: 0,
          width: 0,
          height: 0,
          frameRate: null,
          initialization: template.initialization,
          indexRange: template.indexRange,
        );
    final flac = audio(30251, bandwidth: 999999, codecs: 'fLaC');
    final streams = [
      audio(30232, bandwidth: 132000),
      flac,
      audio(30216, bandwidth: 67000),
      audio(30280, bandwidth: 192000),
    ];
    expect(TrackSelector.bestAudio(streams)?.id, 30280);
    expect(TrackSelector.bestAudio(streams.where((s) => s.id != 30280).toList())?.id, 30232);
    expect(TrackSelector.bestAudio(streams.reversed.where((s) => s.id == 30216 || s.id == 30251).toList())?.id, 30216);
    expect(TrackSelector.bestAudio([flac]), isNull);
  });

  test('no usable audio means no choice', () {
    final silent = Dash(duration: dash.duration, video: dash.video, audio: const []);
    expect(TrackSelector.choose(silent, quality: 120, codecOrder: [VideoCodec.hevc]), isNull);
  });
}
