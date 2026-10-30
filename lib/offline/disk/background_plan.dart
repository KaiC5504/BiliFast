import 'package:bili_core/api.dart' show BiliClient, DashStream, TrackChoice;
import 'package:bili_core/engine.dart' show DownloadGaps, DownloadRanges;
import 'package:bili_core/shared.dart' show ByteRange;

import '../offline_host.dart';

/// The largest range one background transfer fetches: a transfer cancelled on the app's return loses at most this
/// much, and iOS spreads the rest over its own connections.
const backgroundRangeBytes = 16 << 20;

/// [gaps] cut into pieces of at most [maxBytes], in order, cut on multiples of [maxBytes] so they sit on the
/// engine's 2 MiB piece grid.
List<ByteRange> backgroundPieces(List<ByteRange> gaps, {int maxBytes = backgroundRangeBytes}) {
  final pieces = <ByteRange>[];
  for (final gap in gaps) {
    var start = gap.start;
    while (start <= gap.end) {
      final boundary = (start ~/ maxBytes + 1) * maxBytes - 1;
      final end = boundary < gap.end ? boundary : gap.end;
      pieces.add(ByteRange(start, end));
      start = end + 1;
    }
  }
  return pieces;
}

/// The background transfers that fill [gaps]: each track's missing bytes from its primary address, written into its
/// part file at [videoPath] / [audioPath] (absolute, as the engine names them). A track whose total is 0 isn't known
/// yet (stopped during its first request), so it has nothing to hand off; the engine resumes it on the return.
List<BackgroundRange> backgroundRanges({
  required String id,
  required DownloadGaps gaps,
  required TrackChoice choice,
  required String videoPath,
  required String audioPath,
}) {
  List<BackgroundRange> track(bool video, List<ByteRange> missing, DashStream stream, String path) => [
    for (final piece in backgroundPieces(missing))
      BackgroundRange(
        id: id,
        video: video,
        url: stream.baseURL,
        headers: BiliClient.mediaHeaders,
        partPath: DownloadRanges.partPath(path),
        backgroundRangesPath: DownloadRanges.backgroundRangesPath(path),
        start: piece.start,
        end: piece.end,
      ),
  ];

  return [
    if (gaps.videoTotal > 0) ...track(true, gaps.video, choice.video, videoPath),
    if (gaps.audioTotal > 0) ...track(false, gaps.audio, choice.audio, audioPath),
  ];
}
