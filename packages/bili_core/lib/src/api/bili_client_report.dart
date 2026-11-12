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

/// The common fields' own `statistics`, named so the reports keep it whatever that default becomes.
const _reportStatistics = '{"appId":1,"version":"${IphoneLabels.version}","abtest":"","platform":1}';

/// The official app's watch reports, sent with the app token. Only the iPhone identity's are known: under another
/// token they throw a [StateError], and without one [BiliError.noAppToken], with nothing sent.
extension BiliClientReport on BiliClient {
  Future<void> mobileHeartbeat(WatchReport report) async {
    final token = _reportToken();
    final source = report.source;
    await _officialPostVoid('/x/report/heartbeat/mobile', {
      'aid': '${report.aid}',
      'cid': '${report.cid}',
      'mid': '${token.mid}',
      'type': '3',
      'sub_type': '0',
      'epid': '0',
      'sid': '0',
      'epid_status': '0',
      'session': report.session,
      'sessionID': report.session,
      'start_ts': '${report.startTs}',
      'played_time': '${report.playedTime}',
      'actual_played_time': '${report.actualPlayedTime}',
      'total_time': '${report.totalTime}',
      'paused_time': '${report.pausedTime}',
      'last_play_progress_time': '${report.lastProgress}',
      'max_play_progress_time': '${report.maxProgress}',
      'list_play_time': '0',
      'miniplayer_play_time': '0',
      'video_duration': '${report.duration}',
      'quality': '${report.quality}',
      'play_type': '1',
      'play_mode': '1',
      'play_status': '0',
      'user_status': '0',
      'auto_play': '${report.autoPlay}',
      'network_type': '1',
      'is_audio_play': '2',
      'is_auto_qn': '0',
      'cur_language': '',
      'perfer_type': '',
      'from': source.from,
      'from_spmid': source.fromSpmid,
      'spmid': report.spmid,
      'track_id': source.trackId ?? '',
      'report_flow_data': ?source.flowData,
      'extra': '{"player_report_json":"","material_no":""}',
      // Tracking not allowed, as the official app reports it.
      'idfa': '00000000-0000-0000-0000-000000000000',
      'idfv': ?appIdfv,
      'teenagers_age': '16',
      'polaris_action_id': [for (var i = 0; i < 8; i++) BiliClient._random.nextInt(16).toRadixString(16)]
          .join()
          .toUpperCase(),
      'statistics': _reportStatistics,
    }, host: BiliClient.api);
  }

  /// [progress] in seconds, -1 for a video watched to its end. `source` is left out: the video page's value is not
  /// known.
  Future<void> historyReport({
    required int aid,
    required int cid,
    required int progress,
    required int duration,
    required int startTs,
  }) async {
    _reportToken();
    await _officialPostVoid('/x/v2/history/report', {
      'aid': '$aid',
      'cid': '$cid',
      'type': '3',
      'sub_type': '0',
      'epid': '0',
      'sid': '0',
      'progress': '$progress',
      'duration': '$duration',
      'start_ts': '$startTs',
      'device_ts': '$_unixSeconds',
      'scene': 'front',
      'teenagers_age': '16',
      'statistics': _reportStatistics,
    }, host: BiliClient.api);
  }

  AppToken _reportToken() {
    final token = appToken ?? (throw BiliError.noAppToken);
    if (token.identity != OfficialIdentity.iphone) {
      throw StateError('watch reports are only known for the iPhone identity');
    }
    return token;
  }
}
