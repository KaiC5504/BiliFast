import 'dart:typed_data';

import '../api/models.dart';
import '../api/track_selector.dart';
import '../local_http/playback_router.dart';
import '../shared/byte_range.dart';
import '../shared/media_segment.dart';
import 'playback_engine.dart';
import 'transport.dart';

final class PreparedTrack {
  const PreparedTrack({
    required this.stream,
    required this.mediaUrl,
    required this.headers,
    required this.totalSize,
    required this.segments,
  });

  final DashStream stream;

  /// Direct mode only: the address that answered the header request, used as the player's media URI.
  final String mediaUrl;

  /// Bytes 0 through the end of the SIDX, with the init segment already patched when needed.
  final Uint8List headers;
  final int totalSize;
  final List<MediaSegment> segments;

  ByteRange get initRange => stream.initialization;
}

final class PreparedPlayback {
  const PreparedPlayback({
    required this.video,
    required this.audio,
    required this.rewroteHEV1,
    required this.sourceEntry,
  });

  final PreparedTrack video;
  final PreparedTrack audio;

  /// The served init segment was renamed from hev1 to hvc1.
  final bool rewroteHEV1;

  /// The video sample entry in Bilibili's own bytes, which can be hvc1 under a hev1 label.
  final String? sourceEntry;
}

/// Port of the app's PlaybackBuilder.swift. The playlists name each other relatively (`v.m3u8`, `a.m3u8`),
/// so they resolve against the master's URL on the local server.
abstract final class PlaybackBuilder {
  /// Both tracks' headers are fetched at once. Throws [PlaybackError].
  static Future<PreparedPlayback> prepare(
    TrackChoice choice, {
    required Future<({Uint8List bytes, int total})> Function(TrackKind kind, DashStream stream) fetchHeaders,
  }) =>
      throw UnimplementedError('port of PlaybackBuilder.swift');

  /// Direct mode: each track plays from whichever of its addresses answered the header request first;
  /// each address gets [candidateSeconds]. Throws [PlaybackError].
  static Future<PreparedPlayback> prepareDirect(
    TrackChoice choice, {
    required RangeTransport transport,
    double candidateSeconds = 6,
  }) =>
      throw UnimplementedError('port of PlaybackBuilder.swift');

  /// BTR mode: `master.m3u8`, `v.m3u8`, `a.m3u8` and the media `v.mp4` / `a.mp4`, read through [read].
  static PlaybackAssets ripperAssets(
    PreparedPlayback prepared, {
    required Stream<List<int>> Function(TrackKind kind, ByteRange range) read,
  }) =>
      throw UnimplementedError('port of PlaybackBuilder.swift');

  /// Direct mode: the playlists only; the media playlists point at the CDN addresses that answered.
  static PlaybackAssets directAssets(PreparedPlayback prepared) =>
      throw UnimplementedError('port of PlaybackBuilder.swift');
}
