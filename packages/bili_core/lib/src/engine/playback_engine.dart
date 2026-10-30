import '../api/track_selector.dart';
import 'engine_isolate.dart';
import 'node_catalog.dart';
import 'offline_types.dart';
import 'transport.dart';

enum TrackKind { video, audio }

enum PlaybackMode {
  btr('BTR'),
  direct('直连'),

  /// A finished 离线缓存 part, read from the phone ([PlaybackEngine.prepareLocal]).
  local('本地');

  const PlaybackMode(this.label);

  final String label;
}

enum PlaybackErrorKind {
  noSidx('视频索引无法解析'),
  codecUnplayable('这个编码无法播放，正在换一种'),
  noTrack('没有可播放的清晰度'),
  serverDown('本地加速服务不可用'),
  noSource('视频服务器暂时无法访问');

  const PlaybackErrorKind(this.userMessage);

  final String userMessage;
}

/// Port of PlaybackBuilder.swift's `PlaybackError`.
final class PlaybackError implements Exception {
  const PlaybackError(this.kind, [this.detail]);

  final PlaybackErrorKind kind;

  /// For [PlaybackErrorKind.codecUnplayable]: why the init segment can't play.
  final String? detail;

  String get userMessage => kind.userMessage;

  @override
  String toString() => detail == null ? 'PlaybackError(${kind.name})' : 'PlaybackError(${kind.name}: $detail)';
}

final class PlaybackRequest {
  const PlaybackRequest({required this.choice, required this.mode, required this.mediaHeaders, this.startSeconds = 0});

  final TrackChoice choice;
  final PlaybackMode mode;

  /// The Safari User-Agent and Bilibili's Referer, sent with every media request.
  final Map<String, String> mediaHeaders;

  /// Where the player will start, for `RipperConfig.primeStart`.
  final double startSeconds;
}

/// What the player loads. The playlists always come from the local server.
final class PreparedSource {
  const PreparedSource({
    required this.token,
    required this.master,
    required this.video,
    required this.audio,
    required this.mode,
    required this.rewroteHEV1,
    required this.sourceEntry,
    required this.mediaHeaders,
  });

  final String token;
  final Uri master;

  /// BTR: the local server's `v.mp4` / `a.mp4`. Direct: the CDN address that answered the header request,
  /// which the media playlists point at too.
  final Uri video;
  final Uri audio;
  final PlaybackMode mode;

  /// The served init segment was renamed from hev1 to hvc1.
  final bool rewroteHEV1;

  /// The video sample entry in Bilibili's own bytes, which can be hvc1 under a hev1 label.
  final String? sourceEntry;

  /// Direct mode: the player must send these with its CDN requests.
  final Map<String, String> mediaHeaders;
}

final class NodeTiming {
  const NodeTiming({required this.node, this.requests = 0, this.failures = 0, this.firstByteMs = 0});

  final String node;
  final int requests;
  final int failures;

  /// Smoothed time to response headers.
  final double firstByteMs;
}

final class NodeStatus {
  const NodeStatus({required this.node, required this.state, required this.bps});

  final String node;

  /// healthy, untested, blocked or banned.
  final String state;
  final double bps;

  /// A node has one status per address it serves; this is the best of them.
  static NodeStatus? best(String node, List<NodeStatus> states) {
    const rank = {'healthy': 0, 'untested': 1, 'blocked': 2, 'banned': 3};
    NodeStatus? best;
    for (final status in states.where((status) => status.node == node)) {
      if (best == null) {
        best = status;
        continue;
      }
      final byRank = (rank[status.state] ?? 9).compareTo(rank[best.state] ?? 9);
      if (byRank < 0 || (byRank == 0 && status.bps > best.bps)) best = status;
    }
    return best;
  }
}

/// Port of EngineStats.swift's `RipperStats`, plus what the overlay needs from the isolate.
final class EngineSnapshot {
  const EngineSnapshot({
    this.deliveredBytes = 0,
    this.duplicateBytes = 0,
    this.requests = 0,
    this.failures = 0,
    this.cacheHits = 0,
    this.cacheMisses = 0,
    this.concurrency = 0,
    this.nodes = const [],
    this.nodeStates = const [],
    this.downloadBps = 0,
    this.transport = '',
    this.token,
  });

  /// The playback the session figures describe, so a controller sharing the engine shows only its own; null from
  /// engines that don't say.
  final String? token;

  final int deliveredBytes;

  /// Bytes from copies that lost a race or failed.
  final int duplicateBytes;
  final int requests;
  final int failures;
  final int cacheHits;
  final int cacheMisses;
  final int concurrency;
  final List<NodeTiming> nodes;
  final List<NodeStatus> nodeStates;

  /// Bytes per second over the last second or so.
  final double downloadBps;
  final String transport;

  double get duplicateShare {
    final total = deliveredBytes + duplicateBytes;
    return total > 0 ? duplicateBytes / total : 0;
  }
}

/// A BTR playback's media request failed after every retry (`RipperSession.onFatal`): the app refreshes the URLs
/// or falls back to direct mode. Requests that fail together are reported once.
final class FatalReport {
  const FatalReport({required this.token, required this.message});

  final String token;

  /// The error, as text: it crosses the isolate boundary.
  final String message;

  @override
  String toString() => 'FatalReport($token: $message)';
}

/// The engine and the local server, running in their own isolate so piece handling never touches the
/// UI thread that draws danmaku.
abstract interface class PlaybackEngine {
  /// Spawns the engine isolate. [transportFactory] runs inside that isolate, so it must be a top-level or
  /// static function.
  static Future<PlaybackEngine> start({
    required RangeTransport Function() transportFactory,
    EngineOptions options = const EngineOptions(),
  }) => IsolatePlaybackEngine.start(transportFactory: transportFactory, options: options);

  /// Fetches both tracks' headers, builds the playlists and registers them with the local server.
  /// Throws [PlaybackError].
  Future<PreparedSource> prepare(PlaybackRequest request);

  /// Stops the playback's reads and forgets its playlists.
  Future<void> release(String token);

  /// Signed media URLs expire: the caller refreshes them before their deadline.
  Future<void> replaceUrls(String token, TrackKind track, {required String primary, required List<String> backups});

  Future<void> networkChanged({required bool interfaceChanged});

  // These are fire and forget, so four updates a second cost no round trip; after dispose they are dropped.

  /// The playhead and the player's rate (0 while paused), about four times a second while a BTR source plays and
  /// after every jump. Deadlines, hurry and prefetch follow it, and cached segments it left behind are dropped.
  void updatePlayhead(String token, {required double seconds, required double rate});

  /// Seconds buffered ahead of the playhead and whether the player is playing, for the automatic connection count.
  void reportBuffer(String token, {required double aheadSeconds, required bool playing});

  /// The player stalled while playing.
  void reportStall(String token);

  /// Memory pressure: every BTR playback drops its cached and still-downloading prefetched segments.
  void dropCache();

  /// The page playing [token] was covered: that playback drops everything it cached or is still prefetching, kept
  /// back buffer included (Swift's `session.dropCache()` on cover). Its reads go on; the others are untouched.
  void dropPrefetch(String token);

  /// The user is about to seek to [seconds] (a finger resting on the seek bar): the playback starts the segments
  /// there, and the seek's reads take them over. A newer hint replaces the last; null cancels it.
  void hint(String token, double? seconds);

  /// Opens a connection to every node a playurl's [urls] can be fetched from, before the header requests need
  /// one: on the phone the headers arrived 0.78 s after the open. Errors only lose the head start.
  void preconnect(List<String> urls);

  /// The nodes for the sessions prepared after this (设置's CDN 节点); playbacks already running keep theirs.
  void setNodeMode(NodeMode mode);

  /// Ends when the engine does.
  Stream<FatalReport> get fatals;

  /// Probes the local server and binds it again if it stopped answering. True when it had to restart:
  /// every source prepared before then must be prepared again.
  Future<bool> ensureServing();

  /// About once a second while a BTR playback is registered.
  Stream<EngineSnapshot> get stats;

  /// Registers a finished offline part's files with the local server. Throws [PlaybackError].
  Future<PreparedSource> prepareLocal(LocalPlaybackRequest request);

  /// Starts or resumes an offline download; its progress comes on [downloads].
  Future<void> startDownload(DownloadRequest request);

  /// Stops a download and reports what it still lacks, for a background transfer to fetch.
  Future<DownloadGaps> stopDownload(String id);

  /// Fresh signed addresses for a running download, after [DownloadFailure.expired] or before the deadline.
  Future<void> replaceDownloadUrls(
    String id,
    TrackKind track, {
    required String primary,
    required List<String> backups,
  });

  /// Every download's events. Ends when the engine does.
  Stream<DownloadEvent> get downloads;

  Future<void> dispose();
}
