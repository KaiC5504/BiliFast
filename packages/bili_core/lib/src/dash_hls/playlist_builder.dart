import '../shared/byte_range.dart';
import '../shared/media_segment.dart';
import 'c_format.dart';
import 'codec_mapper.dart';

final class HLSTrack {
  const HLSTrack({required this.uri, required this.initRange, required this.segments});

  final String uri;

  /// ftyp + moov.
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

  /// Video plus audio, bits per second.
  final int averageBandwidth;
  final int width;
  final int height;
  final String frameRate;
}

abstract final class PlaylistBuilder {
  static String media(HLSTrack track) {
    final longest = track.segments.isEmpty
        ? 1.0
        : track.segments.map((segment) => segment.duration).reduce((longest, each) => longest < each ? each : longest);
    final target = longest.ceil();
    final lines = [
      '#EXTM3U',
      '#EXT-X-VERSION:7',
      '#EXT-X-TARGETDURATION:${target > 1 ? target : 1}',
      '#EXT-X-MEDIA-SEQUENCE:0',
      '#EXT-X-PLAYLIST-TYPE:VOD',
      '#EXT-X-INDEPENDENT-SEGMENTS',
      '#EXT-X-MAP:URI="${track.uri}",BYTERANGE="${track.initRange.length}@${track.initRange.start}"',
    ];
    for (final segment in track.segments) {
      lines
        ..add('#EXTINF:${formatFixed(segment.duration, 3)},')
        ..add('#EXT-X-BYTERANGE:${segment.range.length}@${segment.range.start}')
        ..add(track.uri);
    }
    lines.add('#EXT-X-ENDLIST');
    return '${lines.join('\n')}\n';
  }

  static String master(HLSVariant variant, {required String videoPlaylist, required String audioPlaylist}) {
    final attributes = [
      'BANDWIDTH=${(variant.averageBandwidth.toDouble() * 1.5).toInt()}',
      'AVERAGE-BANDWIDTH=${variant.averageBandwidth}',
      'CODECS="${variant.codec.codecs},${variant.audioCodecs}"',
      if (variant.codec.supplemental case final supplemental?) 'SUPPLEMENTAL-CODECS="$supplemental"',
      'RESOLUTION=${variant.width}x${variant.height}',
      'FRAME-RATE=${variant.frameRate}',
      'VIDEO-RANGE=${variant.codec.videoRange}',
      'AUDIO="audio"',
    ];
    final lines = [
      '#EXTM3U',
      '#EXT-X-VERSION:7',
      '#EXT-X-INDEPENDENT-SEGMENTS',
      '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="default",DEFAULT=YES,AUTOSELECT=YES,URI="$audioPlaylist"',
      '#EXT-X-STREAM-INF:${attributes.join(',')}',
      videoPlaylist,
    ];
    return '${lines.join('\n')}\n';
  }
}
