import '../shared/byte_range.dart';
import '../shared/media_segment.dart';
import 'codec_mapper.dart';

final class HLSTrack {
  const HLSTrack({required this.uri, required this.initRange, required this.segments});

  final String uri;
  final ByteRange initRange;
  final List<MediaSegment> segments;
}

final class HLSVariant {
  const HLSVariant({
    required this.codec,
    required this.audioCodecs,
    required this.averageBandwidth,
    required this.width,
    required this.height,
    required this.frameRate,
  });

  final HLSVideoCodec codec;
  final String audioCodecs;
  final int averageBandwidth;
  final int width;
  final int height;
  final String frameRate;
}

abstract final class PlaylistBuilder {
  static String media(HLSTrack track) => throw UnimplementedError('port of PlaylistBuilder.swift');

  static String master(HLSVariant variant, {required String videoPlaylist, required String audioPlaylist}) =>
      throw UnimplementedError('port of PlaylistBuilder.swift');
}
