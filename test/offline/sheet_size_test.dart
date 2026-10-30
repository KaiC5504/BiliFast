import 'package:bili_core/api.dart' show Dash, VideoCodec;
import 'package:bilifast/offline/download_sheet.dart';
import 'package:bilifast/offline/offline_size.dart';
import 'package:flutter_test/flutter_test.dart';

import '../player_ui/panels/sheet_rig.dart';

void main() {
  group('estimateBytes', () {
    test('video and best audio bitrates over the seconds, in bytes', () {
      expect(estimateBytes(dash, quality: 80, seconds: 383), ((1500000 + 200000) * 383 / 8).round());
    });

    test('the codec asked for first, else the first stream of that quality', () {
      expect(
        estimateBytes(dash, quality: 80, seconds: 10, codecOrder: const [VideoCodec.avc, VideoCodec.hevc]),
        ((1700000 + 200000) * 10 / 8).round(),
      );
      expect(
        estimateBytes(dash, quality: 80, seconds: 10, codecOrder: const [VideoCodec.av1]),
        ((1500000 + 200000) * 10 / 8).round(),
      );
    });

    test('null without a stream of that quality, a bitrate or a length', () {
      expect(estimateBytes(dash, quality: 16, seconds: 10), isNull);
      expect(estimateBytes(dash, quality: 80, seconds: 0), isNull);
      final silent = Dash(duration: 1, video: [stream(80, 0)], audio: const []);
      expect(estimateBytes(silent, quality: 80, seconds: 10), isNull);
    });

    test('video alone when there is no audio', () {
      final mute = Dash(duration: 1, video: [stream(80, 800000)], audio: const []);
      expect(estimateBytes(mute, quality: 80, seconds: 10), 1000000);
    });
  });

  test('formatBytes writes KB whole, MB and GB to one decimal, in 1024s', () {
    expect(formatBytes(82208358), '78.4MB');
    expect(formatBytes(15728640), '15.0MB');
    expect(formatBytes(134846054), '128.6MB');
    expect(formatBytes(1288490189), '1.2GB');
    expect(formatBytes(524288), '512KB');
    expect(formatBytes(100), '100B');
  });

  test("the sheet's space line drops the B and writes - for nothing or unknown", () {
    expect(DownloadSheet.space(82418074), '78.6M');
    expect(DownloadSheet.space(79886391705), '74.4G');
    expect(DownloadSheet.space(0), '-');
    expect(DownloadSheet.space(null), '-');
  });
}
