import 'dart:async';

import 'package:bili_core/api.dart' show VideoDetail, VideoView;
import 'package:bili_core/devlog.dart';
import 'package:flutter/widgets.dart';

import '../app/app_scope.dart';
import '../app/swipe_back_route.dart';
import '../playback/playback_controller.dart';
import 'page_session.dart';
import 'pip_keeper.dart';
import 'player_session.dart';
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

/// The app's session for a video page. [onSeeked] reaches the watch reporter: every seek the session commits.
/// [willPlay] runs before the session plays, so another page's small window closes first.
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
/// over. What needs a page (the login) goes through the page attached, and does nothing without one.
class PagePlayback extends ChangeNotifier implements KeptPlayback {
  PagePlayback({
    required this._services,
    required VideoRoute route,
    required this._createSession,
    required this.restorePage,
  }) : _bvid = route.bvid,
       _cid = route.cid,
       _startAt = route.start,
       _view = route.view,
       _detail = route.detail,
       _title = route.title;

  final AppServices _services;
  final PageSessionFactory _createSession;

  /// Builds the page the small window's restore button pushes around this playback.
  final Widget Function(VideoRoute route) restorePage;

  /// What it plays: the route's video at first, then whatever the session opens on the page. Only the route's own
  /// open starts at its position; another part of the same video reuses the view and detail it has.
  String _bvid;
  int? _cid;
  double? _startAt;
  VideoView? _view;
  VideoDetail? _detail;
  final String? _title;

  PlaybackController? _controller;
  PlayerSession? _session;
  WatchReporter? _reporter;
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

  /// Made once the controller is in and the first open went out.
  PlayerSession? get session => _session;

  /// The controller failed to start; [retry] starts it again.
  String? get startError => _startError;

  @override
  String get bvid => _bvid;

  bool get closed => _closed;

  @override
  bool get pipActive => _controller?.pictureInPicture ?? false;

  /// A page brought back after this playback was released (a restore that lost to ✕ or to the wait) starts over
  /// where it stopped.
  VideoRoute get restartRoute =>
      VideoRoute(bvid: _bvid, cid: _cid, start: _closedAt, title: _title, view: _view, detail: _detail);

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
    _restores = controller.restoreRequests.listen((_) => _services.pipKeeper.restore(this));
    _open();
    _session = _createSession(
      controller: controller,
      services: _services,
      open: openOnPage,
      onSeeked: (seconds) => _reporter?.seeked(seconds),
      requestLogin: () => _requestLogin?.call(),
      willPlay: willPlay,
    );
    if (_covered) _hold();
    notifyListeners();
  }

  void _open() {
    final controller = _controller!;
    final services = _services;
    unawaited(_reporter?.leave());
    unawaited(controller.openVideo(_bvid, cid: _cid, start: _startAt, view: _view, detail: _detail));
    _reporter = WatchReporter(
      controller: controller,
      client: services.environment.client,
      loggedIn: () => WatchReporter.canReport(services.environment),
      onProgress: (bvid, cid, seconds) => services.recents.recordProgress(bvid: bvid, cid: cid, seconds: seconds),
    );
  }

  /// Another part or video, from 选集, 自动连播 or the end screen: opened on the same controller, with or without a
  /// page.
  void openOnPage(String bvid, {int? cid}) {
    final controller = _controller;
    if (controller == null || _closed) return;
    final sameVideo = bvid == _bvid;
    // Another part of this video needs no second signed view.
    _view = sameVideo ? controller.video : null;
    _detail = sameVideo ? controller.detail : null;
    _bvid = bvid;
    _cid = cid;
    _startAt = null;
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

  /// [page] shows this playback and takes its login asks.
  void attach(Object page, {required VoidCallback requestLogin}) {
    _holders.add(page);
    _page = page;
    _requestLogin = requestLogin;
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
    _resumeOnShow =
        controller == null || controller.phase == PlaybackPhase.loading || (session?.readout.wantsPlay ?? false);
    if (controller == null) return;
    _quietly(controller.stopPictureInPicture, 'pip stop');
    controller.dropPrefetch();
    _hold();
  }

  /// Paused while covered, and kept so: a load under way would otherwise start playing by itself.
  void _hold() {
    _quietly(_controller!.player.pause, 'pause');
    _setAutoPictureInPicture(false);
    _session?.readout.status.addListener(_stillCovered);
  }

  void _stillCovered() {
    if (!_covered || !(_session?.readout.wantsPlay ?? false)) return;
    _resumeOnShow = true;
    _quietly(_controller!.player.pause, 'pause');
    // The controller turns auto picture in picture on at its first play.
    _setAutoPictureInPicture(false);
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
    _setAutoPictureInPicture(true);
    if (resume && resuming) {
      willPlay();
      _quietly(controller.player.play, 'play');
    }
  }

  void _setAutoPictureInPicture(bool on) {
    final player = _controller?.player;
    if (player == null || !player.capabilities.pictureInPicture) return;
    _quietly(() => player.setAutoPictureInPicture(on), 'auto pip');
  }

  void _controllerChanged() {
    final controller = _controller;
    if (controller == null || _closed) return;
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
    final route = VideoRoute(bvid: _bvid, cid: _cid, title: _title, playback: this);
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
    unawaited(_reporter?.leave());
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
