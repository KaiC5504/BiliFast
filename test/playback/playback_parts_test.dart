import 'package:bili_core/api.dart';
import 'package:bili_core/shared.dart';
import 'package:bilifast/playback/codec_memory.dart';
import 'package:bilifast/playback/playing_stream.dart';
import 'package:bilifast/playback/seek_timer.dart';
import 'package:flutter_test/flutter_test.dart';

DashStream stream({int id = 80, String codecs = 'avc1.640032', int codecid = 7, int bandwidth = 2000000}) => DashStream(
      id: id,
      baseURL: 'https://upos-sz-mirrorcos.bilivideo.com/v.m4s',
      backupURLs: const [],
      bandwidth: bandwidth,
      mimeType: 'video/mp4',
      codecs: codecs,
      codecid: codecid,
      width: 1920,
      height: 1080,
      frameRate: null,
      initialization: ByteRange(0, 900),
      indexRange: ByteRange(901, 1500),
    );

void main() {
  group('CodecMemory', () {
    test('the preferred codec first, then HEVC, AV1, AVC, without the failed ones', () {
      final memory = CodecMemory();
      expect(memory.order(preferred: VideoCodec.av1), [VideoCodec.av1, VideoCodec.hevc, VideoCodec.avc]);
      memory.markFailed('hevc');
      expect(memory.order(preferred: VideoCodec.hevc), [VideoCodec.av1, VideoCodec.avc]);
      expect(memory.failedKinds, {'hevc'});
    });

    test('reset forgets the failures and the hev1 finding', () {
      final memory = CodecMemory()
        ..markFailed('av1')
        ..noteHEV1Entry();
      expect(memory.hev1LabelsHoldHEV1, isTrue);
      memory.reset();
      expect(memory.failedKinds, isEmpty);
      expect(memory.hev1LabelsHoldHEV1, isFalse);
    });
  });

  group('SeekTimer', () {
    test('times a seek from the jump to playing', () {
      final timer = SeekTimer();
      expect(timer.jumped(position: 10, atMs: 1000, rate: 1), isTrue);
      expect(timer.isRunning, isTrue);
      expect(timer.playing(atMs: 1450), 450);
      expect(timer.isRunning, isFalse);
    });

    test('a jump while paused is not timed', () {
      final timer = SeekTimer();
      expect(timer.jumped(position: 10, atMs: 1000, rate: 0), isFalse);
      expect(timer.playing(atMs: 9000), isNull);
    });

    test('a reload is not the user seeking, until it plays', () {
      final timer = SeekTimer()..reloadBegan();
      expect(timer.jumped(position: 10, atMs: 1000, rate: 1), isFalse);
      expect(timer.playing(atMs: 1200), isNull);
      expect(timer.jumped(position: 20, atMs: 2000, rate: 1), isTrue);
    });

    test('a seek inside the buffer resumed advanced / rate ago', () {
      final timer = SeekTimer()..jumped(position: 10, atMs: 1000, rate: 2);
      expect(timer.ticked(position: 10.1, rate: 2, playing: true, atMs: 1300), isNull, reason: 'under 0.2 s moved');
      expect(timer.ticked(position: 11, rate: 2, playing: true, atMs: 2000), 500);
    });

    test('pausing before playback resumed drops the timing', () {
      final timer = SeekTimer()
        ..jumped(position: 10, atMs: 1000, rate: 1)
        ..paused();
      expect(timer.playing(atMs: 5000), isNull);
    });
  });

  group('StallFilter', () {
    test('a jump from a second before to 0.75 s after makes the wait a seek wait', () {
      final filter = StallFilter();
      expect(filter.isSeekWait(5000), isFalse);
      filter.jumped(4000);
      expect(filter.isSeekWait(5000), isTrue);
      filter.jumped(5750);
      expect(filter.isSeekWait(5000), isTrue);
      filter.jumped(3999);
      expect(filter.isSeekWait(5000), isFalse);
      filter.jumped(5751);
      expect(filter.isSeekWait(5000), isFalse);
    });

    test('a seek slower than a second is lag', () {
      expect(StallFilter.isLag(1000), isFalse);
      expect(StallFilter.isLag(1001), isTrue);
    });
  });

  group('PlayingStream', () {
    test('quality, codec and rate in one line', () {
      expect(PlayingStream(stream(id: 120, codecs: 'hev1.1.6.L153.90', codecid: 12, bandwidth: 12345678))
          .line(qualityName: '4K 超高清'), '4K 超高清 · HEVC · 12.3 Mbps');
      expect(PlayingStream(stream(bandwidth: 800000)).line(), '80 · H.264 · 800 kbps');
    });

    test('Dolby Vision and unknown codecs get their own names', () {
      expect(PlayingStream.codecName(stream(id: 126, codecs: 'dvh1.08.07', codecid: 12)), '杜比视界');
      expect(PlayingStream.codecName(stream(codecs: 'vp09.00.40.08', codecid: 0)), 'vp09');
    });
  });
}
