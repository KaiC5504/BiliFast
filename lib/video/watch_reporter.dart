import 'dart:async';
import 'dart:math';

import 'package:bili_core/api.dart';
import 'package:bili_core/devlog.dart';
import 'package:bili_core/logic.dart';

import '../app/app_environment.dart';
import '../playback/playback_controller.dart';
import '../player/bili_player.dart';
import 'history_outbox.dart';

/// Tells Bilibili how far the video page got, so it shows in the official app's 历史记录 and the next open resumes
/// there (VideoPageModel.swift's heartbeats): once playback starts, while playing whenever the position is 15 s on from
/// the last report, on pause, after a seek, at the end (-1) and when the playback closes, while [canReport] allows.
/// It belongs to the open made just before it: once a newer open (another part, 自动连播) moves the controller on, it
/// hears nothing more, and leaving reports its own video at the last position it saw. The speed test plays without
/// one, so it reports nothing. With an [outbox], a report that gets no answer waits there for the network.
///
/// Made while the install holds an iPhone-identity app token, it sends the official iPhone app's reports instead
/// (docs/reference/official-iphone-calls.md) and no web heartbeat: a start report as playback starts, and as the play
/// ends (the video finishing, the playback closing, a newer open) an end report with what was watched, then the
/// history report. The outbox keeps the running play's end report as it would be, every 15 s of play and on pause,
/// so a play the app is killed in still reaches Bilibili. While the client holds no iPhone token any more, the web
/// heartbeat goes out for that open after all. [onProgress] hears the same positions either way.
class WatchReporter {
  WatchReporter({
    required PlaybackController controller,
    required this._client,
    required this._loggedIn,
    this.onProgress,
    this._outbox,
    this._source,
    this._followed = false,
    this._now = DateTime.now,
    Logger? logger,
  }) : _controller = controller,
       _open = controller.opens,
       _official = _client.appToken?.identity == OfficialIdentity.iphone,
       _logger = logger ?? Logger.shared {
    // After the controller's own subscription, so its phase already reflects each event.
    _events = controller.player.events.listen(_onEvent);
    if (_official) controller.addListener(_controllerChanged);
  }

  /// Logged in, or still unknown with a session in the jar: a launch account check that failed (no network) must not
  /// cost the whole session its history, and Bilibili ignores the heartbeats of a session that turns out dead. Never
  /// in a `--fake-account` run.
  static bool canReport(AppEnvironment environment) => !environment.fake && switch (environment.account) {
    LoggedIn() => true,
    AccountUnknown() => environment.cookies.all.containsKey('SESSDATA'),
    LoggedOut() || LoginExpired() => false,
  };

  /// How the outbox sends a kept play as [client]'s account; null while it holds no iPhone token. Each report logs
  /// how it went.
  static PlaySender? playSender(BiliClient client, {Logger? logger}) {
    final token = client.appToken;
    if (token == null || token.identity != OfficialIdentity.iphone) return null;
    final log = logger ?? Logger.shared;
    return PlaySender(
      mid: token.mid,
      end: (play) => _reported(log, 'end', () {
        _checkToken(client, play.mid);
        return client.mobileHeartbeat(play.report);
      }, played: play.report.playedTime),
      history: (play) => _reported(log, 'history', () {
        _checkToken(client, play.mid);
        return client.historyReport(
          aid: play.report.aid,
          cid: play.report.cid,
          progress: play.finished ? HeartbeatSchedule.finished : play.report.lastProgress,
          duration: play.report.duration,
          startTs: play.report.startTs,
          source: play.report.source.historySource,
        );
      }),
    );
  }

  /// Throws, before anything is sent, unless the token held now is the iPhone one of account [mid]. The client signs
  /// a report with the token it holds as the call is made, so a report queued under one account's token would
  /// otherwise leave as the account whose token has replaced it since.
  static void _checkToken(BiliClient client, int mid) {
    final held = client.appToken;
    if (held == null || held.identity != OfficialIdentity.iphone) throw BiliError.noAppToken;
    if (held.mid != mid) throw const AnotherAccountsPlay();
  }

  /// Seconds of play between two saves of the running play.
  static const _keepEvery = 15;

  static final _random = Random.secure();

  final PlaybackController _controller;
  final BiliClient _client;
  final bool Function() _loggedIn;
  final HistoryOutbox? _outbox;

  /// Where the page was opened from. Asked as a play starts, not as the reporter is made: the page that takes
  /// 推荐's card over names it only when it attaches.
  final PlaySource Function()? _source;

  /// The open followed the video before it on its own (自动连播, 后台连播).
  final bool _followed;
  final DateTime Function() _now;

  /// The open was made under an iPhone token. Only such an open sends the official reports, and only while the
  /// client still holds one: see [_officialNow].
  final bool _official;
  bool _fellBack = false;

  /// Every position reported, logged in or not, in seconds; a finished video reports its whole length.
  final void Function(String bvid, int cid, int seconds)? onProgress;
  final Logger _logger;
  final int _open;
  late final StreamSubscription<PlayerEvent> _events;

  ({String bvid, int cid})? _item;
  HeartbeatSchedule _schedule = HeartbeatSchedule();
  bool _started = false;

  /// The finished heartbeat went out; a later mark at the end position would overwrite it.
  bool _finishedSent = false;
  PlayerStatus _status = PlayerStatus.idle;

  /// The position at this open's last event, for a leave after a newer open has moved the controller on.
  double _position = 0;
  Future<void> _sending = Future.value();
  bool _left = false;

  /// The play the official reports are adding up; null until it starts and once its end report is made. An open
  /// played again after its end (重播, a loop) is another play.
  _Play? _play;
  bool _played = false;

  /// Where the official plays are kept: the app's outbox, or one of its own when made without.
  late final HistoryOutbox _plays = _outbox ?? HistoryOutbox.memory(logger: _logger, now: _now);

  bool get _isCurrent => _controller.opens == _open;

  void _onEvent(PlayerEvent event) {
    if (!_isCurrent) return;
    final item = _playing();
    if (item == null) return;
    if (item != _item) {
      _item = item;
      _schedule = HeartbeatSchedule();
      _started = false;
      _finishedSent = false;
    }
    _position = _controller.currentSeconds;
    switch (event) {
      case StatusChanged(:final status):
        _status = status;
        // Statuses while a load starts or reloads are the player's, not the viewer's.
        if (_controller.phase != PlaybackPhase.playing) {
          if (_official && status == PlayerStatus.paused) _playPaused();
          return;
        }
        switch (status) {
          case PlayerStatus.playing when !_started:
            _started = true;
            _mark(item);
          case PlayerStatus.paused when _started && !_finishedSent:
            _mark(item);
          case PlayerStatus.ended when _started:
            _finishedSent = true;
            _send(item, HeartbeatSchedule.finished);
          default:
            break;
        }
        if (_official) _playStatus(status);
      case PositionChanged(:final seconds):
        if (!_started || _finishedSent) return;
        final played = _schedule.tick(position: seconds, playing: _status == PlayerStatus.playing);
        if (played != null) _send(item, played);
        if (_official) _playTick();
      default:
        break;
    }
  }

  /// A seek the user made on the page; reported at the position asked for.
  void seeked(double seconds) {
    final item = _item;
    if (!_isCurrent || item == null || item != _playing() || !_started) return;
    _position = seconds;
    _finishedSent = false;
    _send(item, _schedule.mark(position: seconds));
    _play?.watch.seeked(seconds);
  }

  /// The page is going: the last position goes out, and the reports sent so far are awaited.
  Future<void> leave() {
    if (_left) return _sending;
    _left = true;
    final item = _item;
    final position = _isCurrent ? _controller.currentSeconds : _position;
    if (item != null && _started && !_finishedSent) _send(item, _schedule.mark(position: position));
    if (_play case final play?) {
      play.watch.tick(position: position, playing: false);
      _endPlay(finished: false);
    }
    unawaited(_events.cancel());
    if (_official) _controller.removeListener(_controllerChanged);
    return _sending;
  }

  ({String bvid, int cid})? _playing() {
    final video = _controller.video;
    final page = _controller.page;
    return video == null || page == null ? null : (bvid: video.bvid, cid: page.cid);
  }

  void _mark(({String bvid, int cid}) item) => _send(item, _schedule.mark(position: _controller.currentSeconds));

  /// One after another, so a late answer never reorders the history Bilibili keeps.
  void _send(({String bvid, int cid}) item, int played) {
    final duration = _controller.page?.duration ?? 0;
    onProgress?.call(item.bvid, item.cid, played == HeartbeatSchedule.finished ? duration : played);
    if (!_loggedIn() || _officialNow()) return;
    Future<void> beat() => _client.heartbeat(bvid: item.bvid, cid: item.cid, playedTime: played);
    // Handed to the outbox at once, whose lane keeps the order: a page opening this part next must know a report of
    // it is on its way.
    final queued = _outbox
        ?.send(item.bvid, item.cid, played, beat)
        .then<Object?>((_) => null, onError: (Object error) => error);
    _sending = _sending.then((_) async {
      Object? failure = await queued;
      if (queued == null) {
        try {
          await beat();
        } catch (error) {
          failure = error;
        }
      }
      if (failure == null) return;
      // The Windows guard refuses every beat and logs the first itself.
      if (failure is BiliAPIError && failure.code == GuardedTransport.readOnlyCode) return;
      _logger.warn(LogCategory.api, 'heartbeat failed', {'played': played, 'error': '$failure'});
    });
  }

  /// Whether the official reports stand in for this web heartbeat. An official open whose iPhone token is gone
  /// (Bilibili rejected it and the new confirm was cancelled) starts no play, so the web heartbeat goes out for it,
  /// or the open would reach the account's history by neither path.
  bool _officialNow() {
    if (!_official) return false;
    if (_client.appToken?.identity == OfficialIdentity.iphone) return true;
    if (!_fellBack) {
      _fellBack = true;
      _logger.info(LogCategory.api, 'watch report', {'kind': 'fallback'});
    }
    return false;
  }

  void _playStatus(PlayerStatus status) {
    final play = _play;
    if (play == null) {
      if (status == PlayerStatus.playing) _beginPlay();
      return;
    }
    switch (status) {
      case PlayerStatus.playing:
        play.watch.resumed();
      case PlayerStatus.paused:
        _playPaused();
      case PlayerStatus.ended:
        play.watch
          ..tick(position: _position, playing: false)
          ..ended();
        _endPlay(finished: true);
      case PlayerStatus.buffering:
        play.watch.tick(position: _position, playing: false);
      case PlayerStatus.idle || PlayerStatus.loading:
        break;
    }
  }

  /// Paused, also while the controller is not playing: a pause made during a reload is still time paused.
  void _playPaused() {
    final play = _play;
    if (play == null) return;
    play.watch
      ..tick(position: _position, playing: false)
      ..paused();
    _keepPlay(play);
  }

  /// The controller stopped playing (a reload, a quality switch, an error screen) or moved on to a newer open, none
  /// of which the player's statuses tell this reporter: the play waits from here, as it does buffering, or the
  /// session would go on counting the clock as played. It goes on with the player's next status or position under
  /// a playing controller.
  void _controllerChanged() {
    if (_isCurrent && _controller.phase == PlaybackPhase.playing) return;
    _play?.watch.tick(position: _position, playing: false);
  }

  void _playTick() {
    final play = _play;
    final playing = _status == PlayerStatus.playing && _controller.phase == PlaybackPhase.playing;
    if (play == null) {
      // Already playing when reporting became allowed: the page took 推荐's card over, or the login came since.
      if (playing) _beginPlay();
      return;
    }
    play.watch.tick(position: _position, playing: playing);
    if (play.watch.totals.playedTime - play.keptAt >= _keepEvery) _keepPlay(play);
  }

  void _beginPlay() {
    final video = _controller.video;
    final page = _controller.page;
    final token = _client.appToken;
    if (video == null || page == null || token == null || token.identity != OfficialIdentity.iphone) return;
    if (!_loggedIn()) return;
    final play = _play = _Play(
      mid: token.mid,
      aid: video.aid,
      cid: page.cid,
      duration: page.duration,
      session: [for (var i = 0; i < 32; i++) _random.nextInt(16).toRadixString(16)].join(),
      source: _source?.call() ?? PlaySource.unknown,
      autoPlay: _followed && !_played ? 99 : 0,
      watch: WatchSession(now: _now)..started(_position),
    );
    _played = true;
    final report = _reportOf(play, null);
    _sending = _sending
        .then(
          (_) => _reported(_logger, 'start', () {
            _checkToken(_client, play.mid);
            return _client.mobileHeartbeat(report);
          }),
        )
        // Logged already, and a start report is not sent again.
        .then<void>((_) {}, onError: (Object _) {});
  }

  void _keepPlay(_Play play) {
    if (!_loggedIn()) return;
    final totals = play.watch.totals;
    play.keptAt = totals.playedTime;
    _plays.keepPlay(_pending(play, totals, finished: false));
  }

  /// The play is over: its end report and the history report go out through the outbox, after any older play still
  /// waiting there, and stay in it while they get no answer.
  void _endPlay({required bool finished}) {
    final play = _play;
    if (play == null) return;
    _play = null;
    final outbox = _plays;
    if (!_loggedIn()) {
      outbox.dropPlay(play.session);
      return;
    }
    // Kept at once with its last numbers, and over only once the start report has had its answer, so nothing sends
    // the end first.
    outbox.keepPlay(_pending(play, play.watch.totals, finished: finished));
    _sending = _sending.then((_) async {
      outbox.endPlay(play.session);
      // Without the token now, it waits in the outbox for a flush that has one.
      final sender = playSender(_client, logger: _logger);
      if (sender != null) await outbox.sendPlays(sender, recent: _client.history);
    });
  }

  PendingPlay _pending(_Play play, WatchTotals totals, {required bool finished}) =>
      PendingPlay(mid: play.mid, report: _reportOf(play, totals), finished: finished, at: _now());

  /// The start report without [totals], every time 0; with them the end report.
  WatchReport _reportOf(_Play play, WatchTotals? totals) {
    // A newer open's stream is not this play's.
    if (_isCurrent) play.quality = _controller.playing?.quality ?? play.quality;
    return WatchReport(
      aid: play.aid,
      cid: play.cid,
      duration: play.duration,
      session: play.session,
      source: play.source,
      spmid: play.source.spmid,
      startTs: totals?.startTs ?? 0,
      playedTime: totals?.playedTime ?? 0,
      actualPlayedTime: totals?.actualPlayedTime ?? 0,
      totalTime: totals?.totalTime ?? 0,
      pausedTime: totals?.pausedTime ?? 0,
      lastProgress: totals?.lastProgress ?? 0,
      maxProgress: totals?.maxProgress ?? 0,
      quality: play.quality,
      autoPlay: play.autoPlay,
    );
  }

  /// One line per report: its kind and how it went (the error's type and Bilibili's code, never its text), and an
  /// end report's seconds played. The error goes on to the caller.
  static Future<void> _reported(Logger logger, String kind, Future<void> Function() send, {int? played}) async {
    try {
      await send();
    } catch (error) {
      logger.warn(LogCategory.api, 'watch report', {
        'kind': kind,
        'error': '${error.runtimeType}',
        'code': ?switch (error) {
          BiliAPIError(:final code) => code,
          BiliHTTPError(:final status) => status,
          _ => null,
        },
        'played': ?played,
      });
      rethrow;
    }
    logger.info(LogCategory.api, 'watch report', {'kind': kind, 'ok': true, 'played': ?played});
  }
}

/// One play being added up for the official reports.
final class _Play {
  _Play({
    required this.mid,
    required this.aid,
    required this.cid,
    required this.duration,
    required this.session,
    required this.source,
    required this.autoPlay,
    required this.watch,
  });

  final int mid;
  final int aid;
  final int cid;
  final int duration;
  final String session;
  final PlaySource source;
  final int autoPlay;
  final WatchSession watch;

  /// The quality last seen playing, 0 before any.
  int quality = 0;

  /// The seconds played when the outbox last kept it.
  int keptAt = 0;
}
