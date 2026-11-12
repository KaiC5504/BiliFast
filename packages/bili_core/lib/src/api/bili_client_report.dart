part of 'bili_client.dart';

/// One of the official app's two heartbeats for a play (docs/reference/official-iphone-calls.md): the start, with
/// every time zero, or the end, with what was watched. Seconds throughout.
final class WatchReport {
  const WatchReport({
    required this.aid,
    required this.cid,
    required this.duration,
    required this.session,
    required this.source,
    required this.spmid,
    this.startTs = 0,
    this.playedTime = 0,
    this.actualPlayedTime = 0,
    this.totalTime = 0,
    this.pausedTime = 0,
    this.lastProgress = 0,
    this.maxProgress = 0,
    this.quality = 0,
    this.autoPlay = 0,
  });

  final int aid;
  final int cid;
  final int duration;

  /// One 32-character lower-case hex id per play, the same in its start and end.
  final String session;
  final PlaySource source;

  /// The page the video played on.
  final String spmid;

  /// Unix seconds when the play began; 0 in the start report.
  final int startTs;
  final int playedTime;
  final int actualPlayedTime;
  final int totalTime;
  final int pausedTime;

  /// Where playback was when the report was made, and the furthest it got.
  final int lastProgress;
  final int maxProgress;
  final int quality;
  final int autoPlay;
}

/// The official app's watch reports, sent with the app token. Only the iPhone identity's are known.
extension BiliClientReport on BiliClient {
  Future<void> mobileHeartbeat(WatchReport report) => throw UnimplementedError('mobileHeartbeat');

  /// [progress] in seconds, -1 for a video watched to its end.
  Future<void> historyReport({
    required int aid,
    required int cid,
    required int progress,
    required int duration,
    required int startTs,
  }) => throw UnimplementedError('historyReport');
}
