import 'dart:typed_data';

import '../shared/byte_range.dart';

final class MediaResource {
  const MediaResource({required this.totalSize, required this.prefix, required this.read});

  final int totalSize;

  /// Served from memory: the (patched) init segment and index.
  final Uint8List prefix;

  /// Cancelling the subscription must cancel the read underneath.
  final Stream<List<int>> Function(ByteRange range) read;
}

final class PlaybackAssets {
  const PlaybackAssets({required this.playlists, required this.media});

  final Map<String, String> playlists;
  final Map<String, MediaResource> media;
}

final class PlaybackRouter {
  static String makeToken() => throw UnimplementedError('port of PlaybackRouter.swift');

  String register(PlaybackAssets assets, {String? token}) => throw UnimplementedError('port of PlaybackRouter.swift');

  void unregister(String token) => throw UnimplementedError('port of PlaybackRouter.swift');
}
