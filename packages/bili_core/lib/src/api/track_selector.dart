import 'models.dart';

enum VideoCodec {
  hevc(12, 'HEVC'),
  av1(13, 'AV1'),
  avc(7, 'H.264');

  const VideoCodec(this.codecid, this.label);

  final int codecid;
  final String label;
}

final class TrackChoice {
  const TrackChoice({required this.video, required this.audio});

  final DashStream video;
  final DashStream audio;

  @override
  bool operator ==(Object other) => other is TrackChoice && other.video == video && other.audio == audio;

  @override
  int get hashCode => Object.hash(video, audio);
}

abstract final class TrackSelector {
  /// The highest quality not above `quality` (or the lowest offered), then the first codec of
  /// `codecOrder` that quality has, else whatever it has.
  static TrackChoice? choose(Dash dash, {required int quality, required List<VideoCodec> codecOrder}) {
    final audio = bestAudio(dash.audio);
    if (audio == null) return null;
    final qualities = dash.video.map((stream) => stream.id).toSet().toList()..sort((a, b) => b.compareTo(a));
    final picked = qualities.where((id) => id <= quality).firstOrNull ?? qualities.lastOrNull;
    if (picked == null) return null;
    final candidates = dash.video.where((stream) => stream.id == picked).toList();
    for (final codec in codecOrder) {
      final video = candidates.where((stream) => stream.codecid == codec.codecid).firstOrNull;
      if (video != null) return TrackChoice(video: video, audio: audio);
    }
    final first = candidates.firstOrNull;
    return first == null ? null : TrackChoice(video: first, audio: audio);
  }

  /// AAC only: 30280 (192K) > 30232 (132K) > 30216 (64K). Dolby and Hi-Res are later milestones.
  static DashStream? bestAudio(List<DashStream> audio) {
    const rank = {30280: 3, 30232: 2, 30216: 1};
    DashStream? best;
    for (final stream in audio.where((stream) => stream.codecs.startsWith('mp4a'))) {
      if (best == null) {
        best = stream;
        continue;
      }
      final byRank = (rank[stream.id] ?? 0).compareTo(rank[best.id] ?? 0);
      if (byRank > 0 || (byRank == 0 && stream.bandwidth > best.bandwidth)) best = stream;
    }
    return best;
  }

  static String codecKind(DashStream stream) {
    if (stream.codecs.startsWith('dvh1') || stream.codecs.startsWith('dvhe') || stream.id == 126) return 'dolby';
    return switch (stream.codecid) {
      12 => 'hevc',
      13 => 'av1',
      7 => 'avc',
      _ => 'other',
    };
  }
}
