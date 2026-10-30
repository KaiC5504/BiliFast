import '../api/models.dart';
import '../shared/byte_range.dart';
import 'playback_engine.dart';

/// One track of an offline download (离线缓存). The engine fills `[path].part`, keeps what it has in
/// `[path].ranges` ([DownloadRanges]), and renames the part to [path] once every byte is in. [totalSize] is 0 until
/// a response's Content-Range tells it.
final class DownloadTrack {
  const DownloadTrack({required this.primary, required this.backups, required this.path, this.totalSize = 0});

  final String primary;
  final List<String> backups;

  /// Absolute, as the app found its support folder this launch.
  final String path;
  final int totalSize;
}

/// [id] is the app's key for the part (its cid as text); events carry it back.
final class DownloadRequest {
  const DownloadRequest({required this.id, required this.video, required this.audio, required this.mediaHeaders});

  final String id;
  final DownloadTrack video;
  final DownloadTrack audio;

  /// The Safari User-Agent and Bilibili's Referer, as for playback.
  final Map<String, String> mediaHeaders;

  DownloadTrack track(TrackKind kind) => kind == TrackKind.video ? video : audio;
}

/// What [PlaybackEngine.stopDownload] left undone, per track, once its writes are flushed: what a background
/// transfer has to fetch.
final class DownloadGaps {
  const DownloadGaps({
    required this.id,
    required this.video,
    required this.audio,
    required this.videoTotal,
    required this.audioTotal,
  });

  final String id;
  final List<ByteRange> video;
  final List<ByteRange> audio;
  final int videoTotal;
  final int audioTotal;

  bool get isEmpty => video.isEmpty && audio.isEmpty;
}

enum DownloadFailure {
  /// The CDN refused the signed address (403 or 404), or the policy takes none of the addresses (no nodes, an
  /// invalid URL): the app asks Bilibili for fresh ones.
  expired,

  /// A response's total differs from the one the download started with: that track starts over.
  sizeChanged,

  /// Every node failed for longer than the engine waits.
  network,

  /// The phone is full: ENOSPC, or ERROR_DISK_FULL / ERROR_HANDLE_DISK_FULL on Windows.
  disk,

  /// A file could not be read or written for any other reason ([DownloadFailed.osError] says which).
  file,
}

sealed class DownloadEvent {
  const DownloadEvent(this.id);

  final String id;
}

/// About once a second while a download runs, and once when it starts.
final class DownloadProgress extends DownloadEvent {
  const DownloadProgress(
    super.id, {
    required this.videoBytes,
    required this.audioBytes,
    required this.videoTotal,
    required this.audioTotal,
    required this.bps,
  });

  final int videoBytes;
  final int audioBytes;
  final int videoTotal;
  final int audioTotal;
  final double bps;

  int get bytes => videoBytes + audioBytes;
  int get total => videoTotal + audioTotal;
}

/// Both files are complete at their paths.
final class DownloadFinished extends DownloadEvent {
  const DownloadFinished(super.id, {required this.videoTotal, required this.audioTotal});

  final int videoTotal;
  final int audioTotal;
}

/// The download stopped; what it had is kept for the next start.
final class DownloadFailed extends DownloadEvent {
  const DownloadFailed(super.id, {required this.failure, this.track, this.detail = '', this.osError});

  final DownloadFailure failure;
  final TrackKind? track;

  /// The OS's error code behind a [DownloadFailure.disk] or [DownloadFailure.file], when it gave one.
  final int? osError;

  /// For the log; never a URL.
  final String detail;
}

/// `[path].ranges`: the bytes a part file holds, as `{"total": N, "done": [[start, end], ...]}` (inclusive, sorted,
/// merged). A background transfer that finishes a range while the engine isn't running adds it to
/// `[path].bg-ranges` in the same format (written by the host, `OfflineHost.swift`); the engine folds that file into
/// its own when the download starts again and deletes it.
abstract final class DownloadRanges {
  static String partPath(String path) => '$path.part';
  static String rangesPath(String path) => '$path.ranges';
  static String backgroundRangesPath(String path) => '$path.bg-ranges';
}

/// A finished part played from the phone: its two files and the streams they were downloaded as (addresses blank).
final class LocalPlaybackRequest {
  const LocalPlaybackRequest({required this.video, required this.audio, required this.videoPath, required this.audioPath});

  final DashStream video;
  final DashStream audio;
  final String videoPath;
  final String audioPath;
}
