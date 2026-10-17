import 'dart:io';

import 'package:bilifast/player/bili_player.dart';
import 'package:bilifast/player/windows/mpv.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/hls_fixture.dart';

void main() {
  test('the EDL counts URL bytes, as mpv expects', () {
    final url = edlUrl(Uri.parse('http://127.0.0.1:5/t/v.mp4'), Uri.parse('https://cdn.example/a.m4s?x=1'));
    expect(url,
        'edl://!no_chapters;%26%http://127.0.0.1:5/t/v.mp4;!new_stream;!no_chapters;%29%https://cdn.example/a.m4s?x=1');
  });

  test('User-Agent and Referer are split from other headers, whatever their case', () {
    final split = splitHeaders({'user-agent': 'UA', 'REFERER': 'R', 'Origin': 'O'});
    expect((split.userAgent, split.referer), ('UA', 'R'));
    expect(split.others, {'Origin': 'O'});
    expect(splitHeaders(const {}).userAgent, isNull);
  });

  test('seconds and seekable ranges come from mpv strings', () {
    expect(parseSeconds('1.250000'), 1.25);
    expect(parseSeconds(''), isNull);
    expect(parseSeconds('nan'), isNull);
    const state = '{"cache-end":3.008,"seekable-ranges":[{"start":0.000000,"end":3.040000},{"start":5,"end":5}]}';
    expect(parseSeekableRanges(state), [(start: 0.0, end: 3.04)]);
    expect(parseSeekableRanges(''), isEmpty);
    expect(parseSeekableRanges('not json'), isEmpty);
    expect(sameRanges([(start: 0.0, end: 1.0)], [(start: 0.01, end: 1.02)]), isTrue);
    expect(sameRanges([(start: 0.0, end: 1.0)], [(start: 0.0, end: 1.5)]), isFalse);
  });

  test('status follows load, readiness, the end, pause and buffering', () {
    PlayerStatus status({bool loaded = true, bool ready = true, bool completed = false, bool playing = true, bool buffering = false}) =>
        deriveStatus(loaded: loaded, ready: ready, completed: completed, playing: playing, buffering: buffering);
    expect(status(loaded: false), PlayerStatus.idle);
    expect(status(ready: false), PlayerStatus.loading);
    expect(status(completed: true), PlayerStatus.ended);
    expect(status(playing: false, buffering: true), PlayerStatus.paused);
    expect(status(buffering: true), PlayerStatus.buffering);
    expect(status(), PlayerStatus.playing);
  });

  test('queries are cut from URLs in mpv messages', () {
    expect(withoutQueries('Failed to open https://upos.example/x.m4s?deadline=1&upsig=abc.'),
        'Failed to open https://upos.example/x.m4s');
    expect(withoutQueries('no url here'), 'no url here');
    expect(looksLikeFormatError("Failed to initialize a decoder for codec 'hevc'."), isTrue);
    expect(looksLikeFormatError('Failed to open http://127.0.0.1/gone/master.m3u8.'), isFalse);
  });

  test('fit modes map to the Video widget', () {
    expect(videoFit(FitMode.fill), (fit: BoxFit.cover, aspectRatio: null));
    expect(videoFit(FitMode.ratio4x3), (fit: BoxFit.contain, aspectRatio: 4 / 3));
  });

  test('the committed HLS fixture matches its media files', () {
    const directory = 'integration_test/fixtures/hls';
    final videoBytes = File('$directory/v.mp4').readAsBytesSync();
    final video = readTrack(videoBytes);
    final audio = readTrack(File('$directory/a.mp4').readAsBytesSync());
    expect(File('$directory/v.m3u8').readAsStringSync(), mediaPlaylist(video, 'v.mp4'));
    expect(File('$directory/a.m3u8').readAsStringSync(), mediaPlaylist(audio, 'a.mp4'));
    expect(
      File('$directory/master.m3u8').readAsStringSync(),
      masterPlaylist(
        video: video,
        audio: audio,
        videoCodec: avcCodec(videoBytes.sublist(0, video.initLength)),
        audioCodec: 'mp4a.40.2',
        width: 320,
        height: 180,
        frameRate: 25,
      ),
    );
    final boxes = topLevelBoxes(videoBytes);
    for (final segment in video.segments) {
      expect(boxes.where((box) => box.start == segment.start).single.type, 'moof');
    }
    final sizes = [for (final file in Directory(directory).listSync().whereType<File>()) file.lengthSync()];
    expect(sizes.fold(0, (a, b) => a + b), lessThan(300 * 1024));
  });
}
