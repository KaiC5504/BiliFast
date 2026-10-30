import 'package:bili_core/api.dart' show Dash, VideoCodec;

/// About how many bytes a part of [seconds] takes at [quality], from the bitrates in [dash] (the stream the download
/// would pick: [codecOrder] first, else any codec of that quality; the best audio). Null when [dash] has no stream
/// of that quality or no bitrate.
int? estimateBytes(Dash dash, {required int quality, required int seconds, List<VideoCodec> codecOrder = const []}) =>
    null;

/// 78.4MB, 1.2GB, 512KB, as 离线缓存 writes sizes (143, 145).
String formatBytes(int bytes) => '';
