import 'dart:typed_data';

/// One top-level ISO BMFF box: its type and where it sits in the file.
final class Box {
  const Box(this.type, this.start, this.size);

  final String type;
  final int start;
  final int size;

  int get end => start + size;
}

final class Segment {
  const Segment(this.start, this.length, this.duration);

  final int start;
  final int length;
  final double duration;
}

/// What a Bilibili DASH file gives the playlists: ftyp+moov as the init range, then one segment per sidx
/// reference.
final class Track {
  const Track({required this.initLength, required this.segments, required this.totalSize});

  final int initLength;
  final List<Segment> segments;
  final int totalSize;

  double get duration => segments.fold(0, (sum, segment) => sum + segment.duration);

  int get averageBandwidth => (totalSize * 8 / duration).round();
}

List<Box> topLevelBoxes(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final boxes = <Box>[];
  var offset = 0;
  while (offset + 8 <= bytes.length) {
    var size = data.getUint32(offset);
    final type = String.fromCharCodes(bytes, offset + 4, offset + 8);
    if (size == 1) size = data.getUint64(offset + 8);
    if (size == 0) size = bytes.length - offset;
    if (size < 8 || offset + size > bytes.length) throw FormatException('bad $type box at $offset');
    boxes.add(Box(type, offset, size));
    offset += size;
  }
  return boxes;
}

/// The layout Bilibili serves and the playlists assume: ftyp, moov, sidx, then moof/mdat pairs.
Track readTrack(Uint8List bytes) {
  final boxes = topLevelBoxes(bytes);
  final types = boxes.map((box) => box.type).take(4).toList();
  if (types.length < 4 || types[0] != 'ftyp' || types[1] != 'moov' || types[2] != 'sidx' || types[3] != 'moof') {
    throw FormatException('expected ftyp, moov, sidx, moof; got $types');
  }
  final sidx = boxes[2];
  final data = ByteData.sublistView(bytes);
  var at = sidx.start + 8;
  final version = bytes[at];
  at += 4 + 4;
  final timescale = data.getUint32(at);
  at += 4;
  final int firstOffset;
  if (version == 0) {
    firstOffset = data.getUint32(at + 4);
    at += 8;
  } else {
    firstOffset = data.getUint64(at + 8);
    at += 16;
  }
  at += 2;
  final count = data.getUint16(at);
  at += 2;
  final segments = <Segment>[];
  var start = sidx.end + firstOffset;
  for (var index = 0; index < count; index++) {
    final reference = data.getUint32(at);
    if (reference & 0x80000000 != 0) throw const FormatException('hierarchical sidx');
    final size = reference & 0x7fffffff;
    final duration = data.getUint32(at + 4) / timescale;
    segments.add(Segment(start, size, duration));
    start += size;
    at += 12;
  }
  return Track(initLength: boxes[1].end, segments: segments, totalSize: bytes.length);
}

/// `avc1.PPCCLL` from the avcC box inside the init segment.
String avcCodec(Uint8List bytes) {
  for (var index = 0; index + 8 <= bytes.length; index++) {
    if (bytes[index] == 0x61 && bytes[index + 1] == 0x76 && bytes[index + 2] == 0x63 && bytes[index + 3] == 0x43) {
      final hex = [bytes[index + 5], bytes[index + 6], bytes[index + 7]]
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
      return 'avc1.$hex';
    }
  }
  throw const FormatException('no avcC box');
}

/// The same text `PlaylistBuilder.media` writes (BiliNative `DashHLS/PlaylistBuilder.swift`).
String mediaPlaylist(Track track, String uri) {
  final longest = track.segments.map((segment) => segment.duration).reduce((a, b) => a > b ? a : b);
  final lines = [
    '#EXTM3U',
    '#EXT-X-VERSION:7',
    '#EXT-X-TARGETDURATION:${longest.ceil().clamp(1, 1 << 30)}',
    '#EXT-X-MEDIA-SEQUENCE:0',
    '#EXT-X-PLAYLIST-TYPE:VOD',
    '#EXT-X-INDEPENDENT-SEGMENTS',
    '#EXT-X-MAP:URI="$uri",BYTERANGE="${track.initLength}@0"',
    for (final segment in track.segments) ...[
      '#EXTINF:${segment.duration.toStringAsFixed(3)},',
      '#EXT-X-BYTERANGE:${segment.length}@${segment.start}',
      uri,
    ],
    '#EXT-X-ENDLIST',
  ];
  return '${lines.join('\n')}\n';
}

/// The same text `PlaylistBuilder.master` writes, with an SDR AVC variant.
String masterPlaylist({
  required Track video,
  required Track audio,
  required String videoCodec,
  required String audioCodec,
  required int width,
  required int height,
  required double frameRate,
}) {
  final average = video.averageBandwidth + audio.averageBandwidth;
  final attributes = [
    'BANDWIDTH=${(average * 1.5).floor()}',
    'AVERAGE-BANDWIDTH=$average',
    'CODECS="$videoCodec,$audioCodec"',
    'RESOLUTION=${width}x$height',
    'FRAME-RATE=${frameRate.toStringAsFixed(3)}',
    'VIDEO-RANGE=SDR',
    'AUDIO="audio"',
  ];
  final lines = [
    '#EXTM3U',
    '#EXT-X-VERSION:7',
    '#EXT-X-INDEPENDENT-SEGMENTS',
    '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="default",DEFAULT=YES,AUTOSELECT=YES,URI="a.m3u8"',
    '#EXT-X-STREAM-INF:${attributes.join(',')}',
    'v.m3u8',
  ];
  return '${lines.join('\n')}\n';
}
