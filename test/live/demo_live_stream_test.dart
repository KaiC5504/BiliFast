import 'dart:io';
import 'dart:typed_data';

import 'package:bilifast/live/demo_live_stream.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixtures = 'integration_test/fixtures/hls';

/// The first moof's mfhd sequence number and its tfdt decode time.
(int, int) _fragment(Uint8List segment) {
  final data = ByteData.sublistView(segment);
  int? sequence, time;
  void walk(int start, int end) {
    var at = start;
    while (at + 8 <= end) {
      final size = data.getUint32(at);
      final type = String.fromCharCodes(segment.sublist(at + 4, at + 8));
      if (type == 'mfhd') sequence = data.getUint32(at + 12);
      if (type == 'tfdt') time = data.getUint64(at + 12);
      if (type == 'moof' || type == 'traf') walk(at + 8, at + size);
      at += size;
    }
  }

  walk(0, segment.length);
  return (sequence!, time!);
}

void main() {
  late DemoLiveClip clip;

  setUpAll(() {
    clip = DemoLiveClip(
      playlist: File('$_fixtures/v.m3u8').readAsStringSync(),
      media: File('$_fixtures/v.mp4').readAsBytesSync(),
    );
  });

  test('the playlist is live: no end, a sliding window that moves with the clock', () {
    final start = clip.playlist(Duration.zero);
    expect(start, isNot(contains('#EXT-X-ENDLIST')));
    expect(start, contains('#EXT-X-MEDIA-SEQUENCE:0\n'));
    expect(RegExp(r'seg/(\d+)\.m4s').allMatches(start).map((match) => match.group(1)), ['0', '1', '2']);

    final later = clip.playlist(const Duration(seconds: 10, milliseconds: 500));
    expect(later, contains('#EXT-X-MEDIA-SEQUENCE:9\n'));
    expect(RegExp(r'seg/(\d+)\.m4s').allMatches(later).map((match) => match.group(1)), ['9', '10', '11', '12']);
    expect(later, contains('#EXT-X-MAP:URI="init.mp4"'));
  });

  test("segments repeat the clip with each loop's decode times carried on", () {
    // 12800 ticks a second, 1 s segments, 3 to a loop.
    expect(_fragment(clip.segment(0)), (1, 0));
    expect(_fragment(clip.segment(1)), (2, 12800));
    expect(_fragment(clip.segment(3)), (4, 38400));
    expect(_fragment(clip.segment(7)), (8, 7 * 12800));
    expect(clip.segment(4).length, clip.segment(1).length);
    expect(clip.init.sublist(4, 8), 'ftyp'.codeUnits);
  });
}
