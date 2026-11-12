import 'dart:async';

import 'package:bili_core/api.dart' show BiliClientVideo, PlaySource, VideoDetail, VideoView;
import 'package:bili_core/devlog.dart';
import 'package:flutter/widgets.dart';

import '../app/app_environment.dart';
import '../app/app_scope.dart';
import '../app/swipe_back_route.dart';
import '../offline/offline_models.dart';
import '../offline/page/offline_playback.dart';
import '../playback/playback_controller.dart';
import 'page_session.dart';
import 'pip_keeper.dart';
import 'player_session.dart';
import 'story/page_story_feed.dart';
import 'story/story_feed.dart';
import 'video_route.dart';
import 'watch_reporter.dart';

typedef PageSessionFactory = PlayerSession Function({
  required PlaybackController controller,
  required AppServices services,
  required SessionOpen open,
  required void Function(double seconds) onSeeked,
  required VoidCallback requestLogin,
  required VoidCallback willPlay,
});

/// The app's session for a video page.
PlayerSession pageSession({
  required PlaybackController controller,
  required AppServices services,
  required SessionOpen open,
  required void Function(double seconds) onSeeked,
  required VoidCallback requestLogin,
  required VoidCallback willPlay,
}) => createPageSession(
  controller: controller,
  services: services,
  open: open,
  onSeeked: onSeeked,
  requestLogin: requestLogin,
  willPlay: willPlay,
);

/// What a video page plays, apart from the page (the playback half of BiliNative's VideoPageModel): a controller of
/// its own, the session over it (the end rules, 定时关闭), the watch reports, and which video and part it opened. It
/// outlives its page while the small window plays it ([PipKeeper]), and the page the restore button pushes takes it
/// over. What needs a page (the login) goes through the page attached, and does nothing without one. An [inline] one
/// (推荐's big card) plays muted with its session's rules, watch reports and auto picture in picture off, until a page
/// attaches and takes it over as it stands. An [offline] one plays 离线缓存 parts from the phone: no 最近打开, its
/// position kept in the library as well as reported, and Bilibili asked for nothing else but where the part was left.
/// Without [autoplay] the route's video loads paused (详情页直接播放 off); whatever opens on the page after it plays.
/// The route's source goes with the watch reports of its video, not of another video opened on the page after it.
class PagePlayback extends ChangeNotifier implements KeptPlayback {
  PagePlayback({
    required this._services,
    required VideoRoute route,
    required this._createSession,
    required this.restorePage,
    this._inline = false,
    this._autoplay = true,
    this._storyFeed = pageStoryFeed,
  }) : _bvid = route.bvid,
       _cid = route.cid,
       _startAt = route.start,
       _view = route.view,
       _detail = route.detail,
       _title = route.title,
       _source = route.source,
       offline = route.offline;

  final AppServices _services;
  final PageSessionFactory _createSession;

  /// Builds the page the small window's restore button pushes around this playback.
  final Widget Function(VideoRoute route) restorePage;

  final StoryFeedFactory _storyFeed;
  StoryFeed? _story;

  /// The video 竖屏 was entered on and the source it had before; null outside 竖屏.
  ({String bvid, PlaySource source})? _storyEntered;
  bool _storyHalted = false;

  bool _inline;

  /// Whether the next open plays once loaded; a 重试 opens as the open it retries did, or playing once the video has
  /// played or the user asked it to.
  bool _autoplay;

  /// What it plays: the route's video at first, then whatever the session opens on the page. Only the route's own
  /// open starts at its position; another part of the same video reuses the view and detail it has.
  String _bvid;
  int? _cid;
  double? _startAt;
  VideoView? _view;
  VideoDetail? _detail;
  final String? _title;
  PlaySource _source;

  /// The open under way followed the video before it on its own.
  bool _followed = false;

  final bool offline;

  PlaybackController? _controller;
  PlayerSession? _session;
  WatchReporter? _reporter;
  OfflineProgress? _progress;
  StreamSubscription<void>? _restores;
  bool _starting = false;
  String? _startError;
  bool _closed = false;
  bool _tornDown = false;

  /// The pages built around it: what they hold is freed once it is closed and the last of them is gone.
  final Set<Object> _holders = {};
  Object? _page;
  VoidCallback? _requestLogin;

  /// Another page is on top of its page.
  bool _covered = false;

  /// It was playing, or about to, when covered.
  bool _resumeOnShow = false;
  bool _pictureInPicture = false;
  bool _kept = false;

  /// Where it stood when closed, for a page brought back after it was released.
  double? _closedAt;

  PlaybackController? get controller => _controller;

  /// The app's account and client, for what the page plays next (竖屏's feed).
  AppEnvironment get environment => _services.environment;

  /// Made once the controller is in and the first open went out.
  PlayerSession? get session => _session;

  /// The controller failed to start; [retry] starts it again.
  String? get startError => _startError;

  @override
  String get bvid => _bvid;

  /// The part asked for last: the route's, then each one opened on the page.
  int? get cid => _cid;

  bool get closed => _closed;

  /// Still the card's, before any page took it.
  bool get inline => _inline;

  /// 竖屏's feed while 竖屏 is up; null otherwise.
  StoryFeed? get story => _story;

  /// 竖屏 began: a feed from the video playing now, the same one until [endStory]. From here on that video's plays
  /// (its loop, a reload) report as 竖屏's entered video, as the official app's do; the play under way keeps how it
  /// began.
  StoryFeed beginStory() {
    if (_story case final story?) return story;
    final source = _source;
    _storyEntered = (bvid: _bvid, source: source);
    _source = PlaySource.story(entry: source, entered: true, trackId: source.trackId, flowData: source.flowData);
    return _story = _storyFeed(this);
  }

  /// 竖屏 ended: the feed goes, and the video swiped to stays on the page, its next plays reporting as the video
  /// page's (a part from 选集, the page brought back by [restartRoute]): the entered video's source as it was before
  /// 竖屏, a video swiped to keeping where 竖屏 was entered from and its own track data.
  void endStory() {
    final story = _story;
    _story = null;
    story?.dispose();
    final entered = _storyEntered;
    _storyEntered = null;
    if (entered == null) return;
    final source = _source;
    if (entered.bvid == _bvid) {
      _source = entered.source;
    } else if (source.spmid == PlaySource.verticalPage) {
      _source = PlaySource(
        fromSpmid: source.fromSpmid,
        from: entered.source.from,
        trackId: source.trackId,
        flowData: source.flowData,
      );
    }
  }

  /// Risk control answered 竖屏's feed: no feed of this playback asks anything again, re-entering 竖屏 included.
  bool get storyHalted => _storyHalted;
  void haltStory() => _storyHalted = true;

  /// 竖屏's next video loaded ahead on this playback's player ([PlaybackController.warm]), for its [openOnPage]: the
  /// warm, which throws the playurl call's error, or null when none starts (covered, before the controller is in,
  /// closed, for a cached part, on 推荐's card). Shown again, or its controller in, it notifies, so the feed asks again.
  Future<void>? warmNext(String bvid, {int? cid, VideoDetail? detail}) {
    final controller = _controller;
    if (controller == null || _closed || _covered || _inline || offline) return null;
    return controller.warm(bvid, cid: cid, detail: detail);
  }

  /// Lets go of what [warmNext] loaded.
  void dropWarm() => _controller?.dropWarm();

  /// The video playing now as 竖屏's first entry; null before its details are in. The entered video names the source
  /// it had before 竖屏, where 竖屏 was entered from.
  StoryEntry? get storyEntry {
    final controller = _controller;
    final detail = controller?.detail;
    if (controller == null || detail == null || detail.bvid != _bvid) return null;
    final entered = _storyEntered;
    final source = entered != null && entered.bvid == _bvid ? entered.source : _source;
    return StoryEntry.fromDetail(detail, cid: controller.page?.cid ?? _cid, source: source);
  }

  @override
  bool get pipActive => _controller?.pictureInPicture ?? false;

  /// A page brought back after this playback was released (a restore that lost to ✕ or to the wait) starts over
  /// where it stopped.
  VideoRoute get restartRoute => VideoRoute(
    bvid: _bvid,
    cid: _cid,
    start: _closedAt,
    title: _title,
    view: _view,
    detail: _detail,
    offline: offline,
    source: _source,
  );

  /// Gets a controller of its own and opens the video on it; again after a failed start.
  void start() {
    if (_closed || _starting || _controller != null) return;
    _starting = true;
    if (_startError != null) {
      _startError = null;
      notifyListeners();
    }
    unawaited(
      _services.playback.create().then(
        _began,
        onError: (Object error) {
          _starting = false;
          if (_closed) return;
          _startError = '$error';
          notifyListeners();
        },
      ),
    );
  }

  void _began(PlaybackController controller) {
    _starting = false;
    if (_closed) {
      _services.playback.release(controller);
      return;
    }
    _controller = controller;
    controller.addListener(_controllerChanged);
    _restores = controller.restoreRequests.listen((_) => _restore());
    if (_covered) controller.holdAutoplay(true);
    if (_inline) {
      _quietly(() => controller.player.setMuted(true), 'mute');
      controller.setAutoPictureInPicture(false);
    }
    _open();
    final session = _session = _createSession(
      controller: controller,
      services: _services,
      open: openOnPage,
      onSeeked: (seconds) {
        _reporter?.seeked(seconds);
        _progress?.seeked(seconds);
      },
      requestLogin: () => _requestLogin?.call(),
      willPlay: _userPlays,
    );
    if (_covered) {
      session.active = false;
      _hold();
    } else if (_inline) {
      session.active = false;
    }
    notifyListeners();
  }

  /// The small window's restore button. Refused, the window ends at once rather than waiting on a page that won't
  /// come.
  void _restore() {
    final keeper = _services.pipKeeper;
    if (keeper.restore(this)) return;
    final reason = !identical(keeper.kept, this) ? 'not kept' : (_closed ? 'closed' : 'no navigator');
    Logger.shared.warn(LogCategory.ui, 'restore refused', {'bvid': _bvid, 'reason': reason});
    final controller = _controller;
    if (controller != null) _quietly(() => controller.setRestorable(false), 'restorable');
  }

  void _open() {
    final controller = _controller!;
    final services = _services;
    if (offline) {
      _openOffline(controller);
      return;
    }
    unawaited(_reporter?.leave());
    unawaited(
      controller.openVideo(_bvid, cid: _cid, start: _startAt, view: _view, detail: _detail, autoplay: _autoplay),
    );
    _reporter = WatchReporter(
      controller: controller,
      client: services.environment.client,
      // Inline play reports nothing; taken over mid-play, the reports go on from the schedule it kept.
      loggedIn: () => !_inline && WatchReporter.canReport(services.environment),
      onProgress: (bvid, cid, seconds) {
        if (!_inline) services.recents.recordProgress(bvid: bvid, cid: cid, seconds: seconds);
      },
      outbox: services.historyOutbox,
      source: () => _source,
      followed: _followed,
    );
  }

  /// The library's part [_cid] from the phone, from the route's start, else where the account or the library saw it
  /// stop ([offlineResume]).
  void _openOffline(PlaybackController controller) {
    final services = _services;
    final library = services.offline;
    final environment = services.environment;
    final cid = _cid;
    final item = cid == null ? null : library.item(cid);
    _progress?.leave();
    unawaited(_reporter?.leave());
    final FutureOr<double> start = _startAt ?? (item == null ? 0 : _offlineStart(item));
    unawaited(
      controller.openLocal(
        () async {
          if (cid == null) return null;
          final files = await library.playback(cid);
          return files == null ? null : localVideoOf(files);
        },
        start: start,
        autoplay: _autoplay,
      ),
    );
    _progress = OfflineProgress(controller: controller, library: library);
    _reporter = WatchReporter(
      controller: controller,
      client: environment.client,
      loggedIn: () => WatchReporter.canReport(environment),
      outbox: services.historyOutbox,
      followed: _followed,
    );
  }

  /// Where the account left [item] when it may be asked, else where the library saw it stop.
  FutureOr<double> _offlineStart(OfflineItem item) {
    final services = _services;
    final environment = services.environment;
    if (!WatchReporter.canReport(environment)) return offlineStart(item);
    return offlineResume(
      item,
      ask: () => environment.client.playerInfo(bvid: item.request.bvid, cid: item.cid),
      unsent: services.historyOutbox.holds(item.request.bvid, item.cid),
    );
  }

  /// Another part or video, from 选集, 自动连播, the end screen or 竖屏's feed: opened on the same controller, with or
  /// without a page. [followed] when nobody asked for it (自动连播, 后台连播), which its watch reports say. Another
  /// video reports [source], else nothing of where it came from. Another video's [detail], asked ahead (竖屏's next
  /// video), saves the open its own ask.
  void openOnPage(String bvid, {int? cid, bool followed = false, PlaySource? source, VideoDetail? detail}) {
    final controller = _controller;
    if (controller == null || _closed) return;
    // A second tap while the first one's load is still out (⏭ keeps its target until the part arrives) would load
    // it again, and ask for another video's view again.
    if (bvid == _bvid && cid == _cid && controller.phase == PlaybackPhase.loading) return;
    final sameVideo = bvid == _bvid;
    // Another part of this video needs no second signed view.
    _view = sameVideo ? controller.video : null;
    _detail = sameVideo ? controller.detail : (detail?.bvid == bvid ? detail : null);
    if (!sameVideo) _source = source ?? PlaySource.unknown;
    _followed = followed;
    _bvid = bvid;
    _cid = cid;
    _startAt = null;
    _autoplay = true;
    willPlay();
    _open();
    notifyListeners();
  }

  /// 重试: the start after it failed, or the open.
  void retry() {
    if (_closed) return;
    willPlay();
    if (_controller == null) {
      start();
    } else {
      _open();
      notifyListeners();
    }
  }

  /// Before it plays: another page's small window closes, one video at a time.
  void willPlay() => _services.pipKeeper.willPlay(this);

  /// The session's ▶ (or a seek that plays): from now on a 重试 opens playing.
  void _userPlays() {
    _autoplay = true;
    willPlay();
  }

  /// Still the card's, and its rule had paused it when it was handed over.
  bool get heldOnCard => _inline && (_controller?.autoplayHeld ?? false);

  /// [page] shows this playback and takes its login asks. A card's playback its rule had paused plays on only if
  /// [resumeHeld]. A [source] the page's route names is the playback's from then on: the page that takes 推荐's card
  /// over was opened from the card.
  void attach(
    Object page, {
    required VoidCallback requestLogin,
    bool resumeHeld = true,
    PlaySource source = PlaySource.unknown,
  }) {
    _holders.add(page);
    _page = page;
    _requestLogin = requestLogin;
    if (source.fromSpmid.isNotEmpty) _source = source;
    if (_inline) _takeOver(play: resumeHeld || !heldOnCard);
  }

  /// A page took the card's playback: it goes on where it is, with sound and the page's rules.
  void _takeOver({required bool play}) {
    _inline = false;
    _session?.active = true;
    final controller = _controller;
    if (controller == null) return;
    // A card that was playing comes lifted and playing; one its rule paused comes still held and paused.
    if (controller.autoplayHeld) {
      controller.holdAutoplay(false, play: play);
      if (play) {
        willPlay();
        if (controller.phase == PlaybackPhase.playing) _quietly(controller.player.play, 'play');
      }
    }
    controller.setAutoPictureInPicture(true, now: play && controller.phase == PlaybackPhase.playing);
    _quietly(() => controller.player.setMuted(_services.playback.muted), 'unmute');
  }

  /// [page] left: the asks go nowhere until another page attaches.
  void detach(Object page) {
    if (!identical(_page, page)) return;
    _page = null;
    _requestLogin = null;
  }

  /// [page] is gone and builds nothing with this playback any more.
  void letGo(Object page) {
    detach(page);
    _holders.remove(page);
    if (_closed && _holders.isEmpty) scheduleMicrotask(_tearDown);
  }

  /// Another page went on top: the small window closes (one video at a time), playback pauses and drops its
  /// prefetch, and auto picture in picture is the page on top's. [show] resumes it if it was playing or about to.
  void cover() {
    if (_covered || _closed) return;
    _covered = true;
    final controller = _controller;
    final session = _session;
    session?.active = false;
    // A start or a load still under way reports nothing playing, though it is about to.
    _resumeOnShow = controller == null ? _autoplay : controller.loadWillPlay || (session?.readout.wantsPlay ?? false);
    if (controller == null) return;
    _quietly(controller.stopPictureInPicture, 'pip stop');
    controller.dropPrefetch();
    _hold();
  }

  /// Paused while covered, and kept so: every load starts paused until shown.
  void _hold() {
    final controller = _controller!;
    controller.holdAutoplay(true);
    _quietly(controller.player.pause, 'pause');
    _setAutoPictureInPicture(false);
    _session?.readout.status.addListener(_stillCovered);
  }

  void _stillCovered() {
    if (!_covered || !(_session?.readout.wantsPlay ?? false)) return;
    _resumeOnShow = true;
    _quietly(_controller!.player.pause, 'pause');
  }

  /// Shown again after the page above left. [resuming] is the keeper's answer: false while another page's video is
  /// in the small window, and then a page that was playing stays paused until it is played.
  void show({required bool resuming}) {
    if (!_covered || _closed) return;
    _covered = false;
    final session = _session;
    session?.readout.status.removeListener(_stillCovered);
    session?.active = true;
    final resume = _resumeOnShow;
    _resumeOnShow = false;
    final controller = _controller;
    if (controller == null) return;
    final play = resume && resuming;
    controller.holdAutoplay(false, play: play);
    _setAutoPictureInPicture(true);
    if (play) {
      willPlay();
      _quietly(controller.player.play, 'play');
    }
    notifyListeners();
  }

  void _setAutoPictureInPicture(bool on) => _controller?.setAutoPictureInPicture(on);

  void _controllerChanged() {
    final controller = _controller;
    if (controller == null || _closed) return;
    // Played by any way (the lock screen's ▶ too), a 重试 opens playing.
    if (controller.hasPlayed) _autoplay = true;
    final active = controller.pictureInPicture;
    if (active == _pictureInPicture) return;
    _pictureInPicture = active;
    final keeper = _services.pipKeeper;
    if (active) {
      keeper.pipStarted(this);
    } else {
      keeper.pipStopped(this);
    }
  }

  @override
  void keep() {
    final controller = _controller;
    if (_closed || controller == null) return;
    _kept = true;
    _quietly(() => controller.setRestorable(true), 'restorable');
  }

  @override
  void returned() {
    final controller = _controller;
    if (!_kept || controller == null) return;
    _kept = false;
    _quietly(() => controller.setRestorable(false), 'restorable');
  }

  @override
  bool pushPage() {
    final navigator = _services.navigator.currentState;
    if (navigator == null || _closed) return false;
    final route = VideoRoute(bvid: _bvid, cid: _cid, title: _title, playback: this, offline: offline);
    unawaited(navigator.push(RestoredPageRoute<void>(builder: (_) => restorePage(route))));
    return true;
  }

  /// Playback stops at once; what the pages built around it hold is freed once the last of them is gone.
  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _covered = false;
    _resumeOnShow = false;
    _page = null;
    _requestLogin = null;
    final controller = _controller;
    final session = _session;
    session?.readout.status.removeListener(_stillCovered);
    session?.active = false;
    endStory();
    unawaited(_reporter?.leave());
    _progress?.leave();
    unawaited(_restores?.cancel());
    if (controller != null) {
      _closedAt = controller.currentSeconds;
      _cid = controller.page?.cid ?? _cid;
      if (controller.video case final video? when video.bvid == _bvid) _view = video;
      if (controller.detail case final detail? when detail.bvid == _bvid) _detail = detail;
      controller.removeListener(_controllerChanged);
      if (_kept) _quietly(() => controller.setRestorable(false), 'restorable');
      _quietly(controller.stopPictureInPicture, 'pip stop');
    }
    _kept = false;
    // Just after: this can run inside the controller's own notification (the small window closing) or while the
    // tree is locked (a page disposed).
    scheduleMicrotask(() {
      controller?.close();
      if (_holders.isEmpty) _tearDown();
    });
  }

  void _tearDown() {
    if (_tornDown) return;
    _tornDown = true;
    // PlayerSession declares no dispose; the app's session is a ChangeNotifier that frees what it holds.
    if (_session case final ChangeNotifier notifier) notifier.dispose();
    final controller = _controller;
    if (controller != null) _services.playback.release(controller);
  }

  static void _quietly(Future<void> Function() action, String what) {
    unawaited(
      Future.sync(action).catchError((Object error) {
        Logger.shared.warn(LogCategory.player, '$what failed', {'error': '$error'});
      }),
    );
  }
}

/// The page the small window's restore button brings back: in place at once, with the swipe back as any page's.
/// AVKit flies the window to where the player view is when it attaches, so a slide in would send it off screen.
class RestoredPageRoute<T> extends SwipeBackPageRoute<T> {
  RestoredPageRoute({required super.builder});

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => super.transitionDuration;
}
