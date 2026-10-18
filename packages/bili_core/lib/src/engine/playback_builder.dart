import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../api/models.dart';
import '../api/track_selector.dart';
import '../dash_hls/box_reader.dart';
import '../dash_hls/codec_mapper.dart';
import '../dash_hls/init_segment_fixer.dart';
import '../dash_hls/playlist_builder.dart';
import '../dash_hls/sidx_parser.dart';
import '../devlog/log_event.dart';
import '../devlog/logger.dart';
import '../local_http/playback_router.dart';
import '../shared/byte_range.dart';
import '../shared/media_segment.dart';
import 'cancel.dart';
import 'playback_engine.dart';
import 'transport.dart';

final class PreparedTrack {
  const PreparedTrack({
    required this.stream,
    required this.mediaUrl,
    required this.headers,
    required this.totalSize,
    required this.segments,
  });

  final DashStream stream;

  /// Direct mode only: the address that answered the header request, used as the player's media URI.
  /// BTR mode fills in the stream's baseURL and never reads it; the engine picks its own nodes.
  final String mediaUrl;

  /// Bytes 0 through the end of the SIDX, with the init segment already patched when needed.
  final Uint8List headers;
  final int totalSize;
  final List<MediaSegment> segments;

  ByteRange get initRange => stream.initialization;
}

final class PreparedPlayback {
  const PreparedPlayback({
    required this.video,
    required this.audio,
    required this.rewroteHEV1,
    required this.sourceEntry,
  });

  final PreparedTrack video;
  final PreparedTrack audio;

  /// The served init segment was renamed from hev1 to hvc1.
  final bool rewroteHEV1;

  /// The video sample entry in Bilibili's own bytes, which can be hvc1 under a hev1 label.
  final String? sourceEntry;
}

/// Thrown by [PlaybackBuilder.within] when its deadline passes first.
final class CandidateTimeout implements Exception {
  const CandidateTimeout();

  @override
  String toString() => 'CandidateTimeout()';
}

typedef _Fetched = ({Uint8List bytes, int total, String url});

/// Port of the app's PlaybackBuilder.swift. The playlists name each other relatively (`v.m3u8`, `a.m3u8`),
/// so they resolve against the master's URL on the local server.
abstract final class PlaybackBuilder {
  /// Both tracks' headers are fetched at once, as in direct mode, so the modes start on equal terms.
  /// Throws [PlaybackError], or what [fetchHeaders] throws.
  static Future<PreparedPlayback> prepare(
    TrackChoice choice, {
    required Future<({Uint8List bytes, int total})> Function(TrackKind kind, DashStream stream) fetchHeaders,
  }) async {
    final (video, audio) = await _both(
      Future.sync(() => fetchHeaders(TrackKind.video, choice.video)),
      Future.sync(() => fetchHeaders(TrackKind.audio, choice.audio)),
    );
    return _assemble(choice, (kind, stream) {
      final headers = kind == TrackKind.video ? video : audio;
      return (bytes: headers.bytes, total: headers.total, url: stream.baseURL);
    });
  }

  /// Direct mode: each track plays from whichever of its addresses answered the header request first;
  /// each address gets [candidateSeconds] before the next is tried. Throws [PlaybackError], or
  /// [CancelledException] once [cancel] is cancelled.
  static Future<PreparedPlayback> prepareDirect(
    TrackChoice choice, {
    required RangeTransport transport,
    double candidateSeconds = 6,
    CancelToken? cancel,
  }) async {
    final group = CancelToken(cancel);
    try {
      final (video, audio) = await _both(
        _directHeaders(choice.video, transport, candidateSeconds, group),
        _directHeaders(choice.audio, transport, candidateSeconds, group),
        onVideoError: group.cancel,
      );
      return _assemble(choice, (kind, _) => kind == TrackKind.video ? video : audio);
    } finally {
      group.dispose();
    }
  }

  /// BTR mode: `master.m3u8`, `v.m3u8`, `a.m3u8` and the media `v.mp4` / `a.mp4`, read through [read].
  static PlaybackAssets ripperAssets(
    PreparedPlayback prepared, {
    required Stream<List<int>> Function(TrackKind kind, ByteRange range) read,
    bool peakBandwidth = false,
  }) {
    final playlists = _playlists(
      prepared,
      videoUri: 'v.mp4',
      audioUri: 'a.mp4',
      sampleEntry: prepared.rewroteHEV1 ? 'hvc1' : prepared.sourceEntry,
      peakBandwidth: peakBandwidth,
    );
    MediaResource resource(TrackKind kind, PreparedTrack track) =>
        MediaResource(totalSize: track.totalSize, prefix: track.headers, read: (range) => read(kind, range));
    return PlaybackAssets(
      playlists: playlists,
      media: {'v.mp4': resource(TrackKind.video, prepared.video), 'a.mp4': resource(TrackKind.audio, prepared.audio)},
    );
  }

  /// Direct mode: the playlists only; the media playlists point at the CDN addresses that answered.
  /// The player reads Bilibili's original bytes here, so the codec declared is the one in them.
  static PlaybackAssets directAssets(PreparedPlayback prepared) => PlaybackAssets(
    playlists: _playlists(
      prepared,
      videoUri: prepared.video.mediaUrl,
      audioUri: prepared.audio.mediaUrl,
      sampleEntry: prepared.sourceEntry,
    ),
    media: const {},
  );

  /// Runs [body] with a deadline: when it passes first, [body]'s token is cancelled and [CandidateTimeout]
  /// thrown. Cancelling [cancel] cancels [body] too and throws [CancelledException].
  static Future<T> within<T>(double seconds, Future<T> Function(CancelToken cancel) body, {CancelToken? cancel}) async {
    final token = CancelToken(cancel);
    var timedOut = false;
    final timer = Timer(Duration(microseconds: (seconds * 1e6).round()), () {
      timedOut = true;
      token.cancel();
    });
    try {
      token.throwIfCancelled();
      // guard throws at the deadline even when the body ignores its token.
      return await token.guard(Future.sync(() => body(token)));
    } on CancelledException {
      if (timedOut && !(cancel?.isCancelled ?? false)) throw const CandidateTimeout();
      rethrow;
    } finally {
      timer.cancel();
      token.dispose();
    }
  }

  /// Like Swift's `try await (video, audio)` over two `async let`s: a video error wins, and an audio error
  /// counts once the video is in. The video error is thrown at once, since Dart cannot cancel the audio
  /// future the way leaving an `async let` scope cancels its task; [onVideoError] can.
  static Future<(A, B)> _both<A, B>(Future<A> video, Future<B> audio, {void Function()? onVideoError}) async {
    // Handled here so an early audio failure isn't reported as uncaught while the video is awaited.
    unawaited(audio.then<void>((_) {}, onError: (Object _) {}));
    final A first;
    try {
      first = await video;
    } catch (_) {
      onVideoError?.call();
      rethrow;
    }
    return (first, await audio);
  }

  static PreparedPlayback _assemble(TrackChoice choice, _Fetched Function(TrackKind kind, DashStream stream) fetch) {
    (PreparedTrack, bool) track(TrackKind kind, DashStream stream) {
      final fetched = fetch(kind, stream);
      final segments = SidxParser.parse(fetched.bytes, absoluteStart: 0);
      if (segments == null) {
        _unusable(kind, 'sidx missing or not flat');
        throw const PlaybackError(PlaybackErrorKind.noSidx);
      }
      // InitSegmentFixer reports a buffer without moov as unchanged, and the playlist's
      // EXT-X-MAP must be served whole from these bytes.
      if (!_hasCompleteMoov(fetched.bytes, initRange: stream.initialization)) {
        _unusable(kind, 'no complete moov in init range');
        throw const PlaybackError(PlaybackErrorKind.noSidx);
      }
      var headers = fetched.bytes;
      var rewrote = false;
      if (kind == TrackKind.video) {
        switch (InitSegmentFixer.fixHEV1(headers)) {
          case InitUnchanged():
            break;
          case InitRewritten(:final bytes):
            headers = bytes;
            rewrote = true;
          case InitUnplayable(:final reason):
            throw PlaybackError(PlaybackErrorKind.codecUnplayable, reason);
        }
      }
      final prepared = PreparedTrack(
        stream: stream,
        mediaUrl: fetched.url,
        headers: headers,
        totalSize: fetched.total,
        segments: segments,
      );
      return (prepared, rewrote);
    }

    final (video, rewrote) = track(TrackKind.video, choice.video);
    final (audio, _) = track(TrackKind.audio, choice.audio);
    final sourceEntry = rewrote ? 'hev1' : InitSegmentFixer.sampleEntry(video.headers);
    return PreparedPlayback(video: video, audio: audio, rewroteHEV1: rewrote, sourceEntry: sourceEntry);
  }

  /// The largest video segment's bitrate plus the largest audio segment's, never under [average]; null without
  /// segments.
  static int? _peak(PreparedPlayback prepared, {required int average}) {
    double peakOf(List<MediaSegment> segments) => segments
        .where((segment) => segment.duration > 0)
        .fold(0.0, (peak, segment) => max(peak, segment.range.length * 8 / segment.duration));
    final video = peakOf(prepared.video.segments);
    if (video <= 0) return null;
    return max(average, (video + peakOf(prepared.audio.segments)).ceil());
  }

  static void _unusable(TrackKind kind, String reason) =>
      Logger.shared.warn(LogCategory.player, 'headers unusable', {'track': kind.name, 'reason': reason});

  static bool _hasCompleteMoov(Uint8List bytes, {required ByteRange initRange}) {
    if (initRange.end >= bytes.length) return false;
    return BoxReader.boxes(bytes, from: 0, to: initRange.end + 1).any((box) => box.type == 'moov');
  }

  static Map<String, String> _playlists(
    PreparedPlayback prepared, {
    required String videoUri,
    required String audioUri,
    required String? sampleEntry,
    bool peakBandwidth = false,
  }) {
    final video = prepared.video.stream;
    final audio = prepared.audio.stream;
    final variant = HLSVariant(
      codec: CodecMapper.video(codecs: video.codecs, qualityId: video.id, sampleEntry: sampleEntry),
      audioCodecs: audio.codecs.isEmpty ? 'mp4a.40.2' : audio.codecs,
      averageBandwidth: video.bandwidth + audio.bandwidth,
      width: video.width,
      height: video.height,
      frameRate: CodecMapper.frameRate(video.frameRate),
      peakBandwidth: peakBandwidth ? _peak(prepared, average: video.bandwidth + audio.bandwidth) : null,
    );
    return {
      'master.m3u8': PlaylistBuilder.master(variant, videoPlaylist: 'v.m3u8', audioPlaylist: 'a.m3u8'),
      'v.m3u8': PlaylistBuilder.media(
        HLSTrack(uri: videoUri, initRange: prepared.video.initRange, segments: prepared.video.segments),
      ),
      'a.m3u8': PlaylistBuilder.media(
        HLSTrack(uri: audioUri, initRange: prepared.audio.initRange, segments: prepared.audio.segments),
      ),
    };
  }

  /// One plain request per address, Bilibili's own first, then its backups; the first that answers
  /// with the whole range wins. Some accounts get a primary that refuses everything (403) next to
  /// working backups on the same host.
  static Future<_Fetched> _directHeaders(
    DashStream stream,
    RangeTransport transport,
    double candidateSeconds,
    CancelToken cancel,
  ) async {
    final range = ByteRange.of(0, stream.indexRange.end);
    if (range == null) throw const PlaybackError(PlaybackErrorKind.noSidx);
    final candidates = [stream.baseURL, ...stream.backupURLs];
    var refused = 0;
    for (final address in candidates) {
      try {
        final url = Uri.tryParse(address);
        if (url == null) throw const RipperError(RipperErrorKind.invalidURL);
        final fetched = await within(
          candidateSeconds,
          (token) => _wholeRange(url, range, transport, token),
          cancel: cancel,
        );
        Logger.shared.info(LogCategory.player, 'direct source', {
          'url': address,
          'refused': refused,
          'candidates': candidates.length,
        });
        return (bytes: fetched.bytes, total: fetched.total, url: address);
      } catch (error) {
        if (cancel.isCancelled) throw const CancelledException();
        refused += 1;
        // The logger shortens the signed URL to host, path and deadline.
        Logger.shared.warn(LogCategory.player, 'direct headers failed', {'url': address, 'error': '$error'});
      }
    }
    Logger.shared.error(LogCategory.player, 'no direct source', {'refused': refused, 'candidates': candidates.length});
    throw const PlaybackError(PlaybackErrorKind.noSource);
  }

  static Future<({Uint8List bytes, int total})> _wholeRange(
    Uri url,
    ByteRange range,
    RangeTransport transport,
    CancelToken cancel,
  ) async {
    final response = await transport.fetch(url, range, cancel: cancel);
    final contentRange = ContentRange.parse(response.headers['content-range']);
    final total = contentRange?.total;
    if (cancel.isCancelled || response.status != 206 || contentRange?.range != range || total == null) {
      // A body nobody reads keeps its connection busy.
      response.body.listen(null).cancel().ignore();
      cancel.throwIfCancelled();
      throw RipperError.badResponse(response.status);
    }
    final bytes = await _collect(response.body, cancel);
    if (bytes.length != range.length) throw RipperError.lengthMismatch(got: bytes.length, expected: range.length);
    return (bytes: bytes, total: total);
  }

  /// Reads [body] to the end. Cancelling [cancel] cancels the subscription, which cancels the request.
  static Future<Uint8List> _collect(Stream<List<int>> body, CancelToken cancel) {
    final builder = BytesBuilder();
    final completer = Completer<Uint8List>();
    void Function() removeCancel = () {};
    final subscription = body.listen(
      builder.add,
      onError: (Object error, StackTrace stack) {
        removeCancel();
        if (!completer.isCompleted) completer.completeError(error, stack);
      },
      onDone: () {
        removeCancel();
        if (!completer.isCompleted) completer.complete(builder.takeBytes());
      },
      cancelOnError: true,
    );
    removeCancel = cancel.onCancel(() {
      subscription.cancel().ignore();
      if (!completer.isCompleted) completer.completeError(const CancelledException());
    });
    return completer.future;
  }
}
