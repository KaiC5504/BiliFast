import '../local_http/playback_router.dart';
import 'offline_types.dart';
import 'playback_builder.dart';

/// A finished offline part played from its files through the local server: the same playlists and init fixes as a
/// BTR playback, every byte read from the phone.
abstract final class LocalSource {
  /// Reads both files' headers (init and index) and builds the playback. Throws [PlaybackError] when a file is
  /// missing, short or unreadable.
  static Future<PreparedPlayback> prepare(LocalPlaybackRequest request) =>
      throw UnimplementedError('LocalSource.prepare');

  /// `master.m3u8`, `v.m3u8`, `a.m3u8`, and `v.mp4` / `a.mp4` read from the files.
  static PlaybackAssets assets(PreparedPlayback prepared, LocalPlaybackRequest request) =>
      throw UnimplementedError('LocalSource.assets');
}
