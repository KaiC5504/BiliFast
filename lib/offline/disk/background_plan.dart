import 'package:bili_core/api.dart' show BiliClient, DashStream, TrackChoice;
import 'package:bili_core/engine.dart' show DownloadGaps, DownloadRanges;
import 'package:bili_core/shared.dart' show ByteRange;

import '../offline_host.dart';

/// The first background transfers of a track are small: they start while the app is still leaving, so iOS runs them
/// at once, and one cancelled on an early return loses little. Each later one doubles, up to [backgroundRangeMaxBytes],
/// so a track of gigabytes is a few dozen tasks (each costs iOS ~8 ms to queue; 848 took 7 s, by then in the
/// background, where iOS defers new transfers).
const backgroundRangeBytes = 16 << 20;
const backgroundRangeMaxBytes = 256 << 20;

/// The size of a track's next piece once [queued] bytes of it are queued: 16, 16, 32, 64, 128, then 256 MiB along one
/// long gap. Grown by bytes rather than by count, so the engine's small holes before the tail leave its first pieces
/// small.
int backgroundPieceBytes(int queued) {
  var size = backgroundRangeBytes;
  while (size < backgroundRangeMaxBytes && size * 2 <= queued) {
    size *= 2;
  }
  return size;
}

/// [gaps] cut into pieces, in order, growing as [backgroundPieceBytes] says; each is cut on a multiple of its size, so
/// they sit on the engine's 2 MiB piece grid.
List<ByteRange> backgroundPieces(List<ByteRange> gaps) {
  final pieces = <ByteRange>[];
  var queued = 0;
  for (final gap in gaps) {
    var start = gap.start;
    while (start <= gap.end) {
      final size = backgroundPieceBytes(queued);
      final boundary = (start ~/ size + 1) * size - 1;
      final end = boundary < gap.end ? boundary : gap.end;
      pieces.add(ByteRange(start, end));
      queued += end - start + 1;
      start = end + 1;
    }
  }
  return pieces;
}

/// The first of each list, then the second of each, and so on: every track's small first pieces are queued before
/// anyone's large ones.
List<T> roundRobin<T>(List<List<T>> lists) => [
  for (var i = 0; lists.any((list) => i < list.length); i++)
    for (final list in lists)
      if (i < list.length) list[i],
];

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
  List<BackgroundRange> track(bool video, List<ByteRange> missing, int total, DashStream stream, String path) => [
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
        total: total,
      ),
  ];

  return roundRobin([
    if (gaps.videoTotal > 0) track(true, gaps.video, gaps.videoTotal, choice.video, videoPath),
    if (gaps.audioTotal > 0) track(false, gaps.audio, gaps.audioTotal, choice.audio, audioPath),
  ]);
}
