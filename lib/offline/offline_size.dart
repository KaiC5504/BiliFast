import 'package:bili_core/api.dart' show Dash, DashStream, TrackSelector, VideoCodec;

/// About how many bytes a part of [seconds] takes at [quality], from the bitrates in [dash] (the stream the download
/// would pick: [codecOrder] first, else any codec of that quality; the best audio). Null when [seconds] isn't above 0,
/// or [dash] has no stream of that quality or no bitrate.
int? estimateBytes(Dash dash, {required int quality, required int seconds, List<VideoCodec> codecOrder = const []}) {
  if (seconds <= 0) return null;
  final video = _video(dash, quality, codecOrder);
  if (video == null || video.bandwidth <= 0) return null;
  final audio = TrackSelector.bestAudio(dash.audio)?.bandwidth ?? 0;
  return ((video.bandwidth + audio) * seconds / 8).round();
}

DashStream? _video(Dash dash, int quality, List<VideoCodec> codecOrder) {
  final offered = [
    for (final stream in dash.video)
      if (stream.id == quality) stream,
  ];
  for (final codec in codecOrder) {
    for (final stream in offered) {
      if (stream.codecid == codec.codecid) return stream;
    }
  }
  return offered.firstOrNull;
}

/// 78.4MB, 1.2GB, 512KB, as 离线缓存 writes sizes (143, 145).
String formatBytes(int bytes) {
  const unit = 1024;
  if (bytes < unit) return '${bytes < 0 ? 0 : bytes}B';
  if (bytes < unit * unit) return '${(bytes / unit).round()}KB';
  if (bytes < unit * unit * unit) return '${(bytes / (unit * unit)).toStringAsFixed(1)}MB';
  return '${(bytes / (unit * unit * unit)).toStringAsFixed(1)}GB';
}
