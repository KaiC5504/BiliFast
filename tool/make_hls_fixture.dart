import 'dart:io';

import 'hls_fixture.dart';

/// Writes integration_test/fixtures/hls: a 3 s test pattern and a silent audio track (tests make no sound), split
/// into Bilibili-shaped DASH files (separate fragmented MP4 video and audio, a sidx right after moov, 1 s fragments),
/// and the HLS playlists the app's local server would build for them.
///
///     fvm dart run tool/make_hls_fixture.dart
///
/// Needs ffmpeg on PATH.
Future<void> main() async {
  const width = 320, height = 180, frameRate = 25;
  final out = Directory('integration_test/fixtures/hls')..createSync(recursive: true);
  const fragmented = ['-movflags', '+empty_moov+default_base_moof+frag_keyframe+global_sidx', '-f', 'mp4'];
  await _ffmpeg([
    '-f', 'lavfi', '-i', 'testsrc=size=${width}x$height:rate=$frameRate:duration=3',
    '-c:v', 'libx264', '-profile:v', 'main', '-preset', 'veryfast', '-crf', '26', '-pix_fmt', 'yuv420p',
    '-g', '$frameRate', '-keyint_min', '$frameRate', '-sc_threshold', '0', '-an',
    ...fragmented, '${out.path}/v.mp4',
  ]);
  await _ffmpeg([
    '-f', 'lavfi', '-i', 'anullsrc=sample_rate=48000:channel_layout=mono', '-t', '3',
    '-c:a', 'aac', '-b:a', '48k', '-ac', '1', '-vn', '-frag_duration', '1000000',
    ...fragmented, '${out.path}/a.mp4',
  ]);

  final videoBytes = File('${out.path}/v.mp4').readAsBytesSync();
  final video = readTrack(videoBytes);
  final audio = readTrack(File('${out.path}/a.mp4').readAsBytesSync());
  File('${out.path}/v.m3u8').writeAsStringSync(mediaPlaylist(video, 'v.mp4'));
  File('${out.path}/a.m3u8').writeAsStringSync(mediaPlaylist(audio, 'a.mp4'));
  File('${out.path}/master.m3u8').writeAsStringSync(masterPlaylist(
    video: video,
    audio: audio,
    videoCodec: avcCodec(videoBytes.sublist(0, video.initLength)),
    audioCodec: 'mp4a.40.2',
    width: width,
    height: height,
    frameRate: frameRate.toDouble(),
  ));
  stdout.writeln('video ${video.totalSize} B in ${video.segments.length} segments, '
      'audio ${audio.totalSize} B in ${audio.segments.length} segments');
}

Future<void> _ffmpeg(List<String> arguments) async {
  final result =
      await Process.run('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-fflags', '+bitexact', ...arguments]);
  if (result.exitCode != 0) throw ProcessException('ffmpeg', arguments, '${result.stderr}', result.exitCode);
}
