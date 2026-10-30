import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../api/track_selector.dart';
import '../devlog/log_event.dart';
import '../devlog/logger.dart';
import '../local_http/playback_router.dart';
import '../shared/byte_range.dart';
import 'offline_types.dart';
import 'playback_builder.dart';
import 'playback_engine.dart';

/// A finished offline part played from its files through the local server: the same playlists and init fixes as a
/// BTR playback, every byte read from the phone.
abstract final class LocalSource {
  /// The most a media read takes from the file at once. The local server asks for the next chunk only once the
  /// socket has taken the last, so a read holds about this much however big the range.
  static const readChunk = 256 * 1024;

  static int _openFiles = 0;

  /// Files [prepare] and the media reads hold open right now; for tests.
  static int get openFiles => _openFiles;

  /// Reads both files' headers (init and index) and builds the playback. Throws [PlaybackError] when a file is
  /// missing, short or unreadable.
  static Future<PreparedPlayback> prepare(LocalPlaybackRequest request) async {
    final prepared = await PlaybackBuilder.prepare(
      TrackChoice(video: request.video, audio: request.audio),
      fetchHeaders: (kind, stream) => _headers(kind, _path(request, kind), through: stream.indexRange.end),
    );
    _requireMedia(TrackKind.video, request.videoPath, prepared.video);
    _requireMedia(TrackKind.audio, request.audioPath, prepared.audio);
    Logger.shared.info(LogCategory.player, 'local source', {
      'videoBytes': prepared.video.totalSize,
      'audioBytes': prepared.audio.totalSize,
      'segments': prepared.video.segments.length,
      'rewroteHEV1': prepared.rewroteHEV1,
    });
    return prepared;
  }

  /// `master.m3u8`, `v.m3u8`, `a.m3u8`, and `v.mp4` / `a.mp4` read from the files.
  static PlaybackAssets assets(PreparedPlayback prepared, LocalPlaybackRequest request) => PlaybackBuilder.ripperAssets(
    prepared,
    read: (kind, range) => _read(_path(request, kind), range),
    // The app's engine declares the peak too (engine B): AVPlayer complained of segments over 1.5x the average.
    peakBandwidth: true,
  );

  static String _path(LocalPlaybackRequest request, TrackKind kind) =>
      kind == TrackKind.video ? request.videoPath : request.audioPath;

  static Future<({Uint8List bytes, int total})> _headers(TrackKind kind, String path, {required int through}) async {
    final RandomAccessFile file;
    try {
      file = await _open(path);
    } on PathNotFoundException {
      throw _unusable(kind, path, 'missing');
    } on FileSystemException catch (error) {
      throw _unusable(kind, path, _reason(error));
    }
    try {
      final total = await file.length();
      final wanted = through + 1;
      final builder = BytesBuilder(copy: false);
      while (builder.length < wanted) {
        final chunk = await file.read(wanted - builder.length);
        if (chunk.isEmpty) break;
        builder.add(chunk);
      }
      if (builder.length < wanted) throw _unusable(kind, path, 'short', {'size': total, 'needed': wanted});
      return (bytes: builder.takeBytes(), total: total);
    } on FileSystemException catch (error) {
      throw _unusable(kind, path, _reason(error));
    } finally {
      await _close(file);
    }
  }

  /// The SIDX's last segment has to be in the file, or the player would be cut off mid-play.
  static void _requireMedia(TrackKind kind, String path, PreparedTrack track) {
    final end = track.segments.last.range.end;
    if (end >= track.totalSize) throw _unusable(kind, path, 'short', {'size': track.totalSize, 'needed': end + 1});
  }

  /// Reads [range] a chunk at a time, and only while the listener isn't paused. Cancelling stops the reads, and the
  /// cancel's future completes once the file is closed.
  static Stream<List<int>> _read(String path, ByteRange range) {
    final controller = StreamController<List<int>>();
    var cancelled = false;
    Completer<void>? resumed;
    void wake() {
      final waiting = resumed;
      if (waiting != null && !waiting.isCompleted) waiting.complete();
    }

    Future<void> pump() async {
      RandomAccessFile? file;
      try {
        final opened = file = await _open(path);
        await opened.setPosition(range.start);
        var position = range.start;
        while (!cancelled && position <= range.end) {
          if (controller.isPaused) {
            await (resumed = Completer<void>()).future;
            continue;
          }
          final chunk = await opened.read(min(readChunk, range.end - position + 1));
          // A file cut short since prepare: the router fails the body as shorter than it said.
          if (chunk.isEmpty) break;
          position += chunk.length;
          if (!cancelled) controller.add(chunk);
        }
      } catch (error, stack) {
        final reason = error is FileSystemException ? _reason(error) : error.runtimeType.toString();
        if (!cancelled) controller.addError(_LocalReadError(_name(path), reason), stack);
      } finally {
        if (file != null) await _close(file);
        // Not awaited: its future waits on the cancel, and the cancel waits on this.
        unawaited(controller.close());
      }
    }

    Future<void>? running;
    controller
      ..onListen = () {
        running = pump();
      }
      ..onResume = wake
      ..onCancel = () {
        cancelled = true;
        wake();
        return running;
      };
    return controller.stream;
  }

  /// Counted from the moment it is asked for, so [openFiles] never misses one still opening.
  static Future<RandomAccessFile> _open(String path) async {
    _openFiles++;
    try {
      return await File(path).open();
    } catch (_) {
      _openFiles--;
      rethrow;
    }
  }

  static Future<void> _close(RandomAccessFile file) async {
    try {
      await file.close();
    } on FileSystemException {
      // Only reached once the reads are over: nothing they returned depends on it.
    } finally {
      _openFiles--;
    }
  }

  static PlaybackError _unusable(TrackKind kind, String path, String reason, [Map<String, Object> more = const {}]) {
    Logger.shared.error(LogCategory.player, 'local file unusable', {
      'track': kind.name,
      'file': _name(path),
      'reason': reason,
      ...more,
    });
    return const PlaybackError(PlaybackErrorKind.noSource);
  }

  /// The OS's words: [FileSystemException]'s own text carries the whole path, which names the app's container.
  static String _reason(FileSystemException error) {
    final os = error.osError?.message ?? '';
    return os.isEmpty ? error.message : os;
  }

  static String _name(String path) => path.split(RegExp(r'[/\\]')).last;
}

/// What a media read fails with, by file name only.
final class _LocalReadError implements Exception {
  const _LocalReadError(this.file, this.reason);

  final String file;
  final String reason;

  @override
  String toString() => 'LocalReadError($file: $reason)';
}
