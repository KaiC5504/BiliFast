import 'package:bili_core/api.dart';

/// The video stream handed to the player. Direct mode can play another codec than BTR mode, so the overlay
/// shows it (port of OverlayStats.swift's `PlayingStream`).
final class PlayingStream {
  PlayingStream(DashStream stream)
      : quality = stream.id,
        codec = codecName(stream),
        bandwidth = stream.bandwidth;

  final int quality;
  final String codec;

  /// Bits per second, as Bilibili declares the stream.
  final int bandwidth;

  static String codecName(DashStream stream) {
    final kind = TrackSelector.codecKind(stream);
    if (kind == 'dolby') return '杜比视界';
    final known = VideoCodec.values.asNameMap()[kind];
    if (known != null) return known.label;
    final dot = stream.codecs.indexOf('.');
    return dot < 0 ? stream.codecs : stream.codecs.substring(0, dot);
  }

  String line({String? qualityName}) {
    final rate =
        bandwidth >= 1000000 ? '${(bandwidth / 1000000).toStringAsFixed(1)} Mbps' : '${bandwidth ~/ 1000} kbps';
    return '${qualityName ?? quality} · $codec · $rate';
  }

  @override
  bool operator ==(Object other) =>
      other is PlayingStream && other.quality == quality && other.codec == codec && other.bandwidth == bandwidth;

  @override
  int get hashCode => Object.hash(quality, codec, bandwidth);
}
