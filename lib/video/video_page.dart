import 'dart:async';
import 'dart:math' show pi;

import 'package:bili_core/api.dart' as bili
    show AidLink, BvidLink, LinkParser, VideoCard, VideoView;
import 'package:bili_core/devlog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../app/app_environment.dart';
import '../app/app_scope.dart';
import '../app/route_observer.dart';
import '../comments/comment_callbacks.dart';
import '../comments/comment_overlays.dart';
import '../danmaku/danmaku_overlays.dart';
import '../danmaku/danmaku_session.dart';
import '../comments/comments_model.dart';
import '../comments/comments_tab.dart';
import '../device/orientation.dart';
import '../device/orientation_host.dart' show TurnStart;
import '../home/feed_model.dart' show requestFailureMessage;
import '../playback/playback_controller.dart';
import '../player/bili_player.dart' show PlayerStatus;
import '../player_ui/chrome_state.dart';
import '../player_ui/panels/panel_controller.dart';
import '../player_ui/panels/panel_layer.dart';
import '../player_ui/player_ui.dart';
import '../shared/remote_image.dart';
import '../shared/theme.dart';
import '../shared/toast.dart';
import 'actions/action_overlays.dart';
import 'collapsing_player.dart';
import 'intro/intro_tab.dart';
import 'page_details.dart';
import 'page_details_model.dart';
import 'page_playback.dart';
import 'page_session.dart';
import 'page_tabs.dart';
import 'player_prefs.dart';
import 'player_session.dart';
import 'video_player_area.dart';
import 'video_route.dart';

typedef PageDetailsFactory = PageDetails Function({
  required PlayerSession session,
  required AppServices services,
  required void Function(String message) toast,
  required VoidCallback requestLogin,
  required Listenable logins,
});

/// The app's page details. An action that needs the account goes to [requestLogin], and [logins] fires for each login
/// made from the page.
PageDetails pageDetails({
  required PlayerSession session,
  required AppServices services,
  required void Function(String message) toast,
  required VoidCallback requestLogin,
  required Listenable logins,
}) {
  final environment = services.environment;
  return VideoPageDetailsModel(
    session: session,
    api: services.pageApi,
    isLoggedIn: () => environment.account is LoggedIn,
    accountMid: () => environment.mid,
    requestLogin: requestLogin,
    toast: toast,
    accountChanges: environment,
    logins: logins,
  );
}

typedef VideoPageOpener = Future<void> Function(BuildContext context, VideoRoute route);

/// The video page: the player at 16:9 under a black status bar with the tab row and 简介 | 评论 below it, or the
/// player alone over the whole screen in full screen, which is this page laid out again rather than a route of its
/// own. Paused, the small player shrinks to the 继续播放 bar as the shown tab scrolls, the tab row riding under it.
/// It plays the route's video on a controller of its own ([PagePlayback]), reports watch progress while logged in, and
/// hands the playback to the [PipKeeper] when popped, which frees it unless the small window plays it. Covered by
/// another page it pauses, and shown again it resumes where it was, without a reload.
class VideoPage extends StatefulWidget {
  const VideoPage({
    super.key,
    required this.route,
    this.createSession = pageSession,
    this.createDetails = pageDetails,
    this.openPage = openVideoPage,
  });

  final VideoRoute route;
  final PageSessionFactory createSession;
  final PageDetailsFactory createDetails;

  /// A related video, or a video id in the description, opens a page on top through this.
  final VideoPageOpener openPage;

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> with RouteAware, TickerProviderStateMixin {
  AppServices? _services;

  /// What the page plays: the route's, or the one the small window's restore button brought back.
  PagePlayback? _playback;

  PlaybackController? get _controller => _playback?.controller;

  /// Popped, or disposed without a pop: the playback went to the keeper, and the page acts on it no more.
  bool _left = false;

  /// This page's video has played, so a fallback, reload or replay shows the player rather than the cover again.
  bool _played = false;

  /// The playback's session, once the page has built its player around it.
  PlayerSession? _session;
  PageDetails? _details;
  PlayerUi? _ui;

  /// 简介's video, taken from the session until the page leaves.
  IntroContent _intro = const IntroContent();

  /// The native view: built once, so no layout switch or chrome change recreates it.
  Widget? _videoView;
  Listenable? _autoHideInputs;
  final _chrome = ChromeState();
  final _panels = PanelController();
  final _overlays = ActionOverlayController();
  final _tabs = PageTabsController();

  /// The page's danmaku, made with the session.
  DanmakuSession? _danmaku;

  /// Attached to nothing: the status bar's tap scrolls nothing while 评论详情 is up.
  final _noScroll = ScrollController();
  final _areaKey = GlobalKey();
  late final _collapse = CollapsingPlayer(tabs: _tabs, vsync: this);

  /// What the page last laid out, which follows the screen's shape rather than the presentation: iOS hands Flutter
  /// the turned size only halfway through the rotation, so until then the upright page turns as one piece. The
  /// player's panels and gestures follow it too.
  final _laidOut = ValueNotifier<Presentation>(Presentation.inline);

  /// From the upright end of the turn (0) to landscape full screen (1). It runs over the whole turn, from the
  /// presentation's change, while the layout waits for the screen's new shape.
  late final _grow = AnimationController(vsync: this, duration: RotationTheme.grow);
  bool _turnedFull = false;

  /// The upright end of a turn to or from landscape full screen: the small player, or 竖屏.
  Presentation _upright = Presentation.inline;

  /// While the page draws the turns itself (旋转动画, iOS): the screen's shape a change of presentation was made on.
  /// The player waits for the system's turn to start, or for [RotationTheme.takeoverWait] to run out.
  bool? _turnFrom;
  Timer? _turnTimeout;
  StreamSubscription<TurnStart>? _turns;

  /// The last change of presentation's wait ran out with no turn started: the screen never turned for it.
  bool _turnMissed = false;

  /// The turn being waited for, started by the system and waiting for a build at its new shape [wide]: iOS hands
  /// over the size first, but the order isn't relied on.
  ({TurnStart start, bool wide})? _pendingTurn;

  /// The page turns from [_spinFrom] back to upright as it runs.
  late final _spin = AnimationController(vsync: this);
  double _spinFrom = 0;

  /// Turns the host hasn't heard were drawn: its still picture covers the screen until it does.
  int _drawnOwed = 0;

  /// The screen's shape at the last build.
  bool? _drawnWide;

  /// Whether the player's chrome is put away for a turn, a grow or a shrink.
  final _turningPlayer = ValueNotifier<bool>(false);

  /// How far a turn between 竖屏 and landscape full screen has got, for the player's video band; null otherwise.
  final _verticalTurn = ValueNotifier<double?>(null);

  /// The page's size and top inset when last laid out upright: the body keeps them while the player grows over it.
  ({Size size, double top})? _uprightFrame;

  /// What the player area lays out at while its box grows or shrinks: its size at rest in the current layout, below
  /// the box's top inset.
  final _pin = ValueNotifier<Size?>(null);

  /// The small player has shrunk from its full height, and [_barred] once it is the bar.
  bool _shrunk = false;
  bool _barred = false;

  /// Whether the controls showed when the player began to shrink, for when it is full again.
  bool _chromeBeforeShrink = false;

  /// The comments of the video the page shows, replaced when another video opens on it; the drafts stay with the page.
  CommentsModel? _comments;
  final _drafts = CommentDrafts();
  final _commentOverlays = CommentOverlayController();
  bool _threadOpen = false;

  /// 评论详情 holds the left edge, over the small player too, so the player's drag leaves it alone.
  final _threadEdge = ValueNotifier<bool>(false);

  /// The list's count once its first page is in, for 评论 N to follow a post or a delete; null before.
  final _listCount = ValueNotifier<int?>(null);
  late final _commentCallbacks = CommentCallbacks(
    reply: (target, emotes) {
      if (_comments?.requireLogin() ?? false) _commentOverlays.compose(target, emotes: emotes);
    },
    openThread: (root) => unawaited(_comments?.openThread(root)),
    viewPictures: _commentOverlays.viewPictures,
    confirmDelete: _commentOverlays.confirmDelete,
    seek: (seconds) => unawaited(_session?.seekAndPlay(seconds.toDouble())),
    openVideo: (id) => unawaited(_openVideoId(id)),
  );

  /// This page's begin is the orientation's latest, so the presentation is this page's.
  bool _owning = false;

  /// Whether this page's video is vertical; null until the video is known.
  bool? _vertical;

  /// Another page is on top of this one; a menu, sheet or dialog doesn't count.
  bool _covered = false;
  PageRoute<dynamic>? _route;
  bool? _immersive;

  /// An av id from the description is being looked up.
  bool _resolvingId = false;

  /// An action overlay is up in full screen, and whether the chrome showed when it went up.
  bool _overlayAside = false;
  bool _chromeShownBefore = false;

  /// The login page is being asked for or is up; another ask meanwhile is the same one.
  bool _askingLogin = false;

  /// Counts the logins made from this page, for what holds the account's state to ask again.
  final _logins = ValueNotifier<int>(0);
  Timer? _turnWait;

  OrientationController get _orientation => _services!.device.orientation;

  Presentation get _presentation => _owning && !_left ? _orientation.presentation : Presentation.inline;

  /// Landscape full screen is laid out once the screen is landscape, and stays until it is upright again; 竖屏 stays
  /// until the screen is landscape.
  Presentation _layoutFor(Size size) {
    final wide = size.width > size.height;
    final was = _laidOut.value;
    return switch (_presentation) {
      Presentation.vertical => wide && was == Presentation.landscape ? Presentation.landscape : Presentation.vertical,
      Presentation.landscape => wide
          ? Presentation.landscape
          : (was == Presentation.vertical ? Presentation.vertical : Presentation.inline),
      Presentation.inline => wide && was == Presentation.landscape ? Presentation.landscape : Presentation.inline,
    };
  }

  /// A turn between an upright layout (the small player or 竖屏) and landscape full screen grows the player box, or
  /// shrinks it back, from wherever it is; a turn reversed midway goes back from there. While the page draws the
  /// turns, the box holds still until the system's turn starts, made on the screen's shape [wide]. Turned by the
  /// system, 竖屏 doesn't grow: the whole page turns.
  void _followTurn(Presentation presentation, bool wide) {
    final full = presentation == Presentation.landscape;
    if (!full) _upright = presentation;
    if (full == _turnedFull) return;
    _turnedFull = full;
    // A turn this change overtook is not drawn, but leaves the screen its shape, and stays owed: the next drawn turn
    // covers its picture.
    final overtaken = _pendingTurn;
    _pendingTurn = null;
    // Back before its turn started (a refusal), or after the last change's turn never came: the screen is already
    // where this one goes, and no turn will come. The box goes back from where it is.
    final settled = overtaken == null &&
        !_spin.isAnimating &&
        ((_turnMissed && wide == full) || (!_grow.isAnimating && _grow.value == (full ? 1 : 0)));
    _turnMissed = false;
    _turnTimeout?.cancel();
    _turnTimeout = null;
    // Under Reduce Motion the turn jumps, so there is nothing to wait for.
    final still = MediaQuery.disableAnimationsOf(context);
    _turnFrom = _orientation.turnTakeover && _owning && !_left && !settled && !still ? overtaken?.wide ?? wide : null;
    if (_turnFrom != null) {
      _turnTimeout = Timer(RotationTheme.takeoverWait, _turnLate);
    } else if (overtaken != null) {
      _reportDrawn();
    }
    if (still || (_turnFrom == null && _upright == Presentation.vertical)) {
      _grow.value = full ? 1 : 0;
    } else if (_turnFrom != null) {
      _grow.stop();
    } else if (full) {
      _grow.forward();
    } else {
      _grow.reverse();
    }
  }

  /// The turned size is already in (or about to be). The turn being waited for is drawn from the first build at its
  /// new shape, whichever comes first; any other, one the page didn't ask for or a stale one the other way, is only
  /// reported drawn, at once.
  void _turnStarted(TurnStart start) {
    if (!mounted || !_owning || _left || _covered) return;
    _drawnOwed += 1;
    _turnMissed = false;
    final from = _turnFrom;
    final quarter = (start.angle.abs() % pi - pi / 2).abs() < pi / 4;
    final target = _presentation == Presentation.landscape;
    _turnTimeout?.cancel();
    _turnTimeout = null;
    if (from != null && quarter && from != target) {
      _pendingTurn = (start: start, wide: target);
      _turnTimeout = Timer(RotationTheme.takeoverWait, _turnLate);
    } else {
      if (from != null) {
        // A stale turn leaves the screen the other shape, which the one being waited for will start from.
        if (quarter) _turnFrom = !from;
        _turnTimeout = Timer(RotationTheme.takeoverWait, _turnLate);
      }
      _reportDrawn();
    }
    setState(() {});
  }

  /// From the build that has the turn's new shape: the page drawn turned by −angle, so it sits where it was before
  /// the turn, and back to upright as the box grows or shrinks, both over the system's duration. A turn that reverses
  /// one under way starts from the angle the page is drawn at.
  void _beginTurn(({TurnStart start, bool wide}) turn) {
    _pendingTurn = null;
    _turnFrom = null;
    _turnTimeout?.cancel();
    _turnTimeout = null;
    if (!MediaQuery.disableAnimationsOf(context)) {
      final duration = turn.start.duration;
      _spinFrom = _rotation - turn.start.angle;
      _spin
        ..duration = duration
        ..forward(from: 0);
      if (_turnedFull && _grow.value != 1) {
        _grow.animateTo(1, duration: duration);
      } else if (!_turnedFull && _grow.value != 0) {
        _grow.animateBack(0, duration: duration);
      }
    }
    _reportDrawn();
  }

  /// No turn came, or not its new shape: the player grows as it does when the system turns the screen itself.
  void _turnLate() {
    _turnTimeout = null;
    if (!mounted) return;
    _turnMissed = _pendingTurn == null;
    _turnFrom = null;
    _pendingTurn = null;
    if (!_grow.isAnimating) {
      if (_upright == Presentation.vertical) {
        _grow.value = _turnedFull ? 1 : 0;
      } else if (_turnedFull) {
        _grow.forward();
      } else {
        _grow.reverse();
      }
    }
    _flushDrawn();
    setState(() {});
  }

  /// Rebuilds the PopScope, which holds the page while it turns.
  void _spinStatus(AnimationStatus status) {
    if (!status.isCompleted || !mounted) return;
    // A turn of no length ends in the build that starts it, which reads it already.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) return;
    setState(() {});
  }

  double get _rotation => _spinFrom * (1 - RotationTheme.curve.transform(_spin.value));

  /// The host's still picture goes once the turn's first frame, the one being built, is on the screen: after it and
  /// the next.
  void _reportDrawn() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      SchedulerBinding.instance
        ..addPostFrameCallback((_) => _flushDrawn())
        ..scheduleFrame();
    });
  }

  void _flushDrawn() {
    for (; _drawnOwed > 0; _drawnOwed--) {
      _services?.device.orientation.turnDrawn();
    }
  }

  /// Mid-turn, the player box with its top inset, where the upright body sits (竖屏 has none) and how far the turn has
  /// got, or null at rest. The box goes from its upright place about the upright screen's centre, the small player or
  /// 竖屏's whole screen, to the whole landscape screen about its centre, and is placed about the centre of the screen
  /// as it is now: iOS keeps the view's centre as it hands over the turned size halfway through, so nothing moves
  /// then. Before that the box grows past the upright page's sides.
  ({Rect box, double inset, Offset? body, double t})? _turning(Size screen, Presentation layout, double uprightTop) {
    if (MediaQuery.disableAnimationsOf(context)) return null;
    final value = _grow.value;
    final vertical = _upright == Presentation.vertical;
    if (vertical) {
      // The system's 竖屏 turns jump; only one the page draws moves the box, from the change of presentation.
      if (!_grow.isAnimating && !_spin.isAnimating && _turnFrom == null && _pendingTurn == null) return null;
    } else if (layout == Presentation.vertical ||
        !_grow.isAnimating && value == (layout == Presentation.landscape ? 1 : 0)) {
      return null;
    }
    final short = screen.shortestSide;
    final long = screen.longestSide;
    final small = uprightTop + _collapse.height;
    final t = RotationTheme.curve.transform(value);
    final centre = screen.center(Offset.zero);
    final box = Rect.lerp(
      vertical
          ? Rect.fromCenter(center: Offset.zero, width: short, height: long)
          : Rect.fromLTWH(-short / 2, -long / 2, short, small),
      Rect.fromCenter(center: Offset.zero, width: long, height: short),
      t,
    )!.shift(centre);
    if (vertical) return (box: box, inset: 0, body: null, t: t);
    return (box: box, inset: uprightTop * (1 - t), body: Offset(centre.dx - short / 2, box.bottom - small), t: t);
  }

  @override
  void initState() {
    super.initState();
    _panels.addListener(_panelChanged);
    _overlays
      ..addListener(_panelChanged)
      ..addListener(_standAside);
    _commentOverlays.addListener(_panelChanged);
    _collapse.addListener(_collapseChanged);
    _spin.addStatusListener(_spinStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services == null) {
      _services = AppScope.of(context);
      _orientation.addListener(_presentationChanged);
      _turns = _orientation.turns.listen(_turnStarted);
      _takePlayback();
    }
    // Only another page covers this one. A popup on top (the ⋮ menu, a dialog) makes the route not current as well,
    // so ModalRoute.isCurrentOf would stop the end rules and the background pause under a menu.
    if (ModalRoute.of(context) case final PageRoute<dynamic> route when route != _route) {
      pageRoutes.unsubscribe(this);
      _route = route;
      pageRoutes.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    if (_covered) return;
    _covered = true;
    _owning = false;
    // The page above claims the orientation only once its video is known; until then a turn must not be taken over
    // with no page to draw it. A newer begin first makes this a no-op.
    final orientation = _orientation;
    scheduleMicrotask(() => orientation.end(this));
    if (!_left) {
      _playback?.cover();
      _details?.active = false;
    }
    if (mounted) setState(() {});
  }

  @override
  void didPopNext() {
    if (!_covered) return;
    _covered = false;
    // Shown again after the page above popped: this page takes the orientation back after the frame, once the pop
    // and the page above's leaving are done.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _left || _covered) return;
      _claimOrientation();
      final playback = _playback;
      if (playback == null) return;
      playback.show(resuming: _services!.pipKeeper.pageShown(playback, opened: false));
      _details?.active = true;
    });
  }

  /// The route's playback, or the one the restore button brought back (started over if it was released meanwhile).
  /// Its first show releases a playback the small window kept, before this page's video loads.
  void _takePlayback() {
    final services = _services!;
    final route = widget.route;
    final createSession = widget.createSession;
    final createDetails = widget.createDetails;
    final openPage = widget.openPage;
    final brought = route.playback;
    final playback = brought != null && !brought.closed
        ? brought
        : PagePlayback(
            services: services,
            route: brought?.restartRoute ?? route,
            createSession: createSession,
            restorePage: (route) => VideoPage(
              route: route,
              createSession: createSession,
              createDetails: createDetails,
              openPage: openPage,
            ),
          );
    _playback = playback;
    playback
      ..attach(this, requestLogin: _askLogin)
      ..addListener(_playbackChanged);
    services.pipKeeper.pageShown(playback, opened: true);
    if (playback.session == null) {
      playback.start();
    } else {
      _attachSession(playback);
    }
  }

  void _playbackChanged() {
    final playback = _playback;
    if (!mounted || _left || playback == null) return;
    if (_session == null && playback.session != null) _attachSession(playback);
    setState(() {});
  }

  /// The page's player, panels, details and danmaku, around the playback's session.
  void _attachSession(PagePlayback playback) {
    final services = _services!;
    final controller = playback.controller!;
    final session = playback.session!;
    _session = session;
    controller.addListener(_follow);
    final details = widget.createDetails(
      session: session,
      services: services,
      toast: _toast,
      requestLogin: _askLogin,
      logins: _logins,
    );
    _details = details;
    final environment = services.environment;
    final danmaku = DanmakuSession(
      feed: controller.danmaku,
      settings: services.danmakuSettings,
      rules: services.blockRules,
      api: services.pageApi,
      target: () {
        final video = controller.video;
        final part = controller.page;
        if (_left || video == null || part == null) return null;
        return (bvid: video.bvid, cid: part.cid);
      },
      position: () => session.position,
      isLoggedIn: () => environment.account is LoggedIn,
      isVip: () => switch (environment.account) {
        LoggedIn(:final vip) => vip,
        _ => false,
      },
      accountMid: () => environment.mid ?? 0,
      accountChanges: environment,
      requestLogin: _askLogin,
    );
    _danmaku = danmaku;
    danmaku.sendOpen.addListener(_panelChanged);
    _ui = PlayerUi(
      session: session,
      chrome: _chrome,
      panels: _panels,
      orientation: _orientation,
      device: services.device.controls,
      onBack: _back,
      details: details,
      onComments: _showComments,
      overlay: _overlays,
      edgeTaken: _threadEdge,
      danmaku: danmaku,
      layout: _laidOut,
    );
    _videoView = session.player.buildView();
    session.addListener(_sessionChanged);
    session.readout.status.addListener(_syncCollapse);
    _autoHideInputs = Listenable.merge([session.readout.status, session.scrubbing, _panels, _overlays, danmaku.sendOpen])
      ..addListener(_syncAutoHide);
    _syncAutoHide();
    _sessionChanged();
  }

  /// The page has built its player around the playback and hasn't left.
  bool get _mine => !_left && _session != null;

  void _follow() {
    final controller = _controller;
    if (controller == null) return;
    setState(() {
      if (!_mine) return;
      if (_session case final session?) _intro = IntroContent.of(session);
      if (controller.phase == PlaybackPhase.playing) _played = true;
    });
    _syncComments();
    _syncAutoHide();
    _syncCollapse();
  }

  void _sessionChanged() {
    _syncCollapse();
    final session = _session;
    if (session == null || !_mine) return;
    final intro = IntroContent.of(session);
    if (intro != _intro && mounted) setState(() => _intro = intro);
    _syncComments();
    if (session.video == null) return;
    final vertical = session.isVertical;
    final changed = vertical != _vertical;
    _vertical = vertical;
    if (!_owning) {
      _claimOrientation();
    } else if (changed) {
      _orientation.setVideoIsVertical(vertical, owner: this);
    }
  }

  /// A new model for each video the page shows, once its aid is known: from the detail, or from the view for a video
  /// opened without a signed detail (an av id, an unsigned link), whose uploader mark waits for the detail. Nothing
  /// loads until 评论 first shows.
  void _syncComments() {
    if (_left || !mounted) return;
    final detail = _intro.detail;
    final view = _mine ? _controller?.video : null;
    final aid = detail?.aid ?? (view?.bvid == _playback?.bvid ? view?.aid : null);
    if (aid == null) return;
    if (_comments case final comments? when comments.aid == aid) {
      if (detail != null) comments.upMid = detail.owner.mid;
      return;
    }
    // A post still out keeps its composer and model until it lands, so a failure is still shown.
    if (_drafts.anyPosting) {
      _drafts
        ..removeListener(_postLanded)
        ..addListener(_postLanded);
      return;
    }
    final services = _services!;
    final environment = services.environment;
    final old = _comments;
    _commentOverlays.close();
    final comments = CommentsModel(
      aid: aid,
      upMid: detail?.owner.mid ?? 0,
      api: services.pageApi,
      drafts: _drafts,
      isLoggedIn: () => environment.account is LoggedIn,
      accountMid: () => environment.mid,
      requestLogin: _askLogin,
      toast: _toast,
    )..addListener(_commentsChanged);
    setState(() {
      _comments = comments;
      _setThreadOpen(false);
    });
    _listCount.value = null;
    old
      ?..removeListener(_commentsChanged)
      ..dispose();
  }

  void _postLanded() {
    if (_drafts.anyPosting) return;
    _drafts.removeListener(_postLanded);
    if (mounted && !_left) _syncComments();
  }

  /// Rebuilds the PopScope when the thread opens or closes, which back then closes first.
  void _commentsChanged() {
    final open = _comments?.thread != null;
    if (open != _threadOpen && mounted) setState(() => _setThreadOpen(open));
    _syncListCount();
  }

  void _syncListCount() {
    final comments = _comments;
    final loaded = comments != null && (comments.comments.isNotEmpty || comments.pinned != null || comments.isEnd);
    // A reload (another sort) keeps the last count until its first page is in; a new video's model starts at null.
    if (!loaded) return;
    final count = comments.total;
    if (count == _listCount.value || !mounted) return;
    // The tab asks for its first page while it builds, where the row can't rebuild yet.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _syncListCount());
    } else {
      _listCount.value = count;
    }
  }

  void _setThreadOpen(bool open) {
    _threadOpen = open;
    _threadEdge.value = open;
  }

  /// Closes the composer, the picture viewer or the delete confirm, else 评论详情. False when none is up. A composer
  /// that is posting stays: closed, a failed post would never show and its text would be lost with the page.
  bool _closeComments() {
    if (_commentOverlays.value case final overlay?) {
      if (overlay is! ComposeOverlay || !_drafts.anyPosting) _commentOverlays.close();
      return true;
    }
    if (_comments case final comments? when comments.thread != null) {
      comments.closeThread();
      return true;
    }
    return false;
  }

  /// Once the video is known, and again each time the page is shown after one above it: the latest begin wins.
  void _claimOrientation() {
    final vertical = _vertical;
    if (_left || vertical == null || _covered) return;
    _owning = true;
    _orientation.begin(this, videoIsVertical: vertical);
  }

  void _presentationChanged() {
    if (!mounted) return;
    // As BiliNative's page: full screen puts the composer away (its draft is kept), or the keyboard would cover the
    // video and type into a field out of sight.
    if (_presentation.fullScreen && _commentOverlays.value is ComposeOverlay && !_drafts.anyPosting) {
      _commentOverlays.close();
    }
    setState(() {});
    _applySystemUi();
    _standAside();
  }

  /// In full screen an action overlay puts the chrome away, as an open panel does, and gives it back as it was once
  /// the overlay closes: the dark favourites sheet would otherwise show the chrome's action row through it.
  void _standAside() {
    final aside = _overlays.value != null && _presentation.fullScreen;
    if (aside == _overlayAside) return;
    _overlayAside = aside;
    if (aside) {
      _chromeShownBefore = _chrome.visible;
      _chrome.hide();
    } else if (_chromeShownBefore) {
      _chrome.show();
    }
  }

  /// Full screen keeps the status bar, light on black as in 04 and 09, and hides the home indicator.
  void _applySystemUi() {
    final immersive = _presentation.fullScreen;
    if (immersive == (_immersive ?? false)) return;
    _immersive = immersive;
    unawaited(
      immersive
          ? SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: const [SystemUiOverlay.top])
          : SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge),
    );
  }

  void _syncAutoHide() {
    final session = _session;
    final controller = _controller;
    if (session == null || controller == null) return;
    // Another part opening on the page keeps the last one's status until its own load starts, so the phase counts.
    _chrome.autoHide = _mine &&
        controller.phase == PlaybackPhase.playing &&
        session.readout.wantsPlay &&
        session.scrubbing.value == null &&
        _panels.value == null &&
        _overlays.value == null &&
        !(_danmaku?.sendOpen.value ?? false);
  }

  /// Only the page's own video, loaded, paused and not at its end, lets the tabs' scrolling shrink the player: the end
  /// screen (26) is in the player and must stay seen.
  void _syncCollapse() {
    final controller = _controller;
    final session = _session;
    _collapse.paused =
        controller != null &&
        session != null &&
        _mine &&
        controller.phase == PlaybackPhase.playing &&
        session.readout.status.value == PlayerStatus.paused &&
        !session.ended;
  }

  /// The controls go as the player starts to shrink, leaving the thin line as on 11, and come back as they were once
  /// it is full again.
  void _collapseChanged() {
    final progress = _collapse.progress;
    final shrunk = progress > 0;
    final barred = progress >= 1;
    if (shrunk == _shrunk && barred == _barred) return;
    if (shrunk && !_shrunk) {
      _chromeBeforeShrink = _chrome.visible;
      _chrome.hide();
    } else if (!shrunk && _shrunk && _chromeBeforeShrink) {
      _chrome.show();
    }
    _shrunk = shrunk;
    _barred = barred;
    if (mounted) setState(() {});
  }

  /// 继续播放: the shown tab back to its top, where the player has its full height again, and play.
  void _resume() {
    _tabs.scrollToTop(animate: !MediaQuery.disableAnimationsOf(context));
    final session = _session;
    if (session == null || session.readout.status.value != PlayerStatus.paused) return;
    _playback?.willPlay();
    session.togglePlay();
  }

  /// Rebuilds the PopScope, which lets a pop through only with no overlay or panel open.
  void _panelChanged() {
    if (mounted) setState(() {});
  }

  /// Back closes the comments' overlays and thread first on the small player, then an action overlay, then a panel.
  void _back() {
    if (_closeDanmakuSend()) return;
    if (!_presentation.fullScreen && _closeComments()) return;
    if (_overlays.value != null) {
      _overlays.close();
    } else if (_panels.value != null) {
      _panels.close();
    } else if (_presentation.fullScreen) {
      _orientation.exitToInline();
    } else if (!_laidOut.value.fullScreen) {
      unawaited(Navigator.of(context).maybePop());
    }
  }

  void _toast(String message) {
    if (mounted) showToast(context, message);
  }

  void _askLogin() => unawaited(_requestLogin());

  /// Every logged-out action and every answer of Bilibili's that wants a login comes here (BiliNative's presentLogin
  /// and InlineFirst): the send bar, the composer and the action overlays go, full screen turns back to the upright
  /// small player, and the login page goes up once the turn is over, with the phone's turning off until it closes.
  /// Nothing pressed is sent afterwards; a login made there has what holds the account's state ask again.
  Future<void> _requestLogin() async {
    final services = _services;
    if (_askingLogin || services == null || _left || _covered || !mounted) return;
    _askingLogin = true;
    try {
      // A model can ask while a widget builds, and what closes here rebuilds the page.
      await Future<void>.value();
      if (!mounted || _left) return;
      // An account still being checked (or whose check failed) may well be logged in: the login page would invite a
      // second login, so it is asked again first and the page shows only for a verdict of logged out.
      final environment = services.environment;
      if (environment.account is AccountUnknown) {
        await environment.refreshAccount();
        if (!mounted || _left) return;
        switch (environment.account) {
          case LoggedIn():
            return;
          case AccountUnknown():
            _toast('账号确认失败，请稍后重试');
            return;
          case LoggedOut() || LoginExpired():
            break;
        }
      }
      _danmaku?.closeSend();
      if (_commentOverlays.value is ComposeOverlay && !_drafts.anyPosting) _commentOverlays.close();
      _overlays.close();
      await _inlineFirst();
      if (!mounted || _left || _covered) return;
      _owning = false;
      _orientation.end(this);
      final before = environment.account;
      final bool answer;
      try {
        answer = await services.loginGate.request(context);
      } finally {
        if (mounted) _claimOrientation();
      }
      if (!mounted || _left) return;
      // Closing the login page while it signs in still logs in, after the page has answered false. A -101 asked
      // from a stale login and closed leaves that same LoggedIn, which isn't a new login.
      final account = environment.account;
      if (account is AccountUnknown) {
        _followSignIn(environment);
      } else if (account is LoggedIn && (answer || !identical(account, before))) {
        _loggedIn();
      }
    } catch (error) {
      Logger.shared.warn(LogCategory.ui, 'login failed', {'error': '$error'});
      _toast('无法打开登录');
    } finally {
      _askingLogin = false;
    }
  }

  void _loggedIn() {
    _logins.value += 1;
    _comments?.refreshAccount();
    _danmaku?.refreshAccount();
  }

  VoidCallback? _signInWatch;

  /// Waits out the account check of a sign-in the login page left running.
  void _followSignIn(AppEnvironment environment) {
    _stopFollowingSignIn();
    void check() {
      final account = environment.account;
      if (account is AccountUnknown) return;
      _stopFollowingSignIn();
      if (account is LoggedIn && mounted && !_left) _loggedIn();
    }

    environment.addListener(check);
    _signInWatch = () => environment.removeListener(check);
  }

  void _stopFollowingSignIn() {
    _signInWatch?.call();
    _signInWatch = null;
  }

  /// How long the turn back upright may take before the login page goes up anyway, as in BiliNative's InlineFirst.
  static const _turnLimit = Duration(seconds: 3);
  static const _turnPoll = Duration(milliseconds: 20);

  /// The rotation's animation, which runs on after the screen has its upright size.
  static const _turnSettle = Duration(milliseconds: 400);

  /// Back to the small player from full screen. From landscape it waits for the screen to turn upright and the turn
  /// to end: a page pushed mid-turn would be laid out sideways. That holds for a turn back already under way, whose
  /// landscape layout stays until the screen is upright. 竖屏 is upright already.
  Future<void> _inlineFirst() async {
    if (_presentation.fullScreen) {
      _orientation.exitToInline();
    } else if (_laidOutUpright) {
      return;
    }
    final turning = !_laidOutUpright;
    var waited = Duration.zero;
    while (mounted && !_laidOutUpright && waited < _turnLimit) {
      await _wait(_turnPoll);
      waited += _turnPoll;
    }
    if (turning && mounted) await _wait(_turnSettle);
    if (mounted) await SchedulerBinding.instance.endOfFrame;
  }

  bool get _laidOutUpright {
    final size = MediaQuery.sizeOf(context);
    return size.width <= size.height && _laidOut.value != Presentation.landscape;
  }

  Future<void> _wait(Duration duration) {
    final done = Completer<void>();
    _turnWait = Timer(duration, done.complete);
    return done.future;
  }

  /// On back, the send bar closes before anything under it.
  bool _closeDanmakuSend() {
    final danmaku = _danmaku;
    if (danmaku == null || !danmaku.sendOpen.value) return false;
    danmaku.closeSend();
    return true;
  }

  /// 评论 in full screen: back to the small player on the 评论 tab.
  void _showComments() {
    _tabs.select(PageTab.comments, animate: false);
    _orientation.exitToInline();
  }

  void _openRelated(bili.VideoCard card) =>
      unawaited(widget.openPage(context, VideoRoute(bvid: card.bvid, title: card.title, cover: card.cover)));

  Future<void> _watchLater(bili.VideoCard card) async {
    final details = _details;
    if (details == null) return;
    final result = await details.watchLater(card);
    if (result.message.isNotEmpty) _toast(result.message);
  }

  /// A BV id opens at once; an av id asks Bilibili for its video first. The page's own video opens nothing.
  Future<void> _openVideoId(String id) async {
    switch (bili.LinkParser.parse(id)) {
      case bili.BvidLink(id: final bvid):
        if (bvid == _playback?.bvid) return;
        await widget.openPage(context, VideoRoute(bvid: bvid));
      case final bili.AidLink link:
        if (_resolvingId || link.id == _intro.detail?.aid) return;
        _resolvingId = true;
        final bili.VideoView view;
        try {
          view = (await resolveVideoLink(_services!.environment.client, link)).$1;
        } catch (error) {
          Logger.shared.warn(LogCategory.ui, 'open video id failed', {'error': '$error'});
          _toast(requestFailureMessage(error, fallback: '打开视频失败，请稍后重试'));
          return;
        } finally {
          _resolvingId = false;
        }
        // The lookup may answer after a related page or a menu went up over this one.
        if (!mounted || _left || !(ModalRoute.isCurrentOf(context) ?? false) || view.bvid == _playback?.bvid) return;
        await widget.openPage(context, VideoRoute(bvid: view.bvid, title: view.title, view: view));
      default:
        break;
    }
  }

  VoidCallback? get _retry {
    final playback = _playback;
    if (playback == null || (playback.startError == null && playback.controller == null)) return null;
    return playback.retry;
  }

  /// Runs at the pop, not at dispose 500 ms later: the sound stops with the swipe, and the page below, shown at once,
  /// finds the small window kept.
  void _leave({bool fromDispose = false}) {
    if (_left) return;
    _left = true;
    _owning = false;
    _details?.active = false;
    _controller?.removeListener(_follow);
    // The session outlives the page when the small window keeps it.
    final session = _session;
    session?.removeListener(_sessionChanged);
    session?.readout.status.removeListener(_syncCollapse);
    _autoHideInputs?.removeListener(_syncAutoHide);
    final playback = _playback;
    if (playback != null) {
      playback
        ..removeListener(_playbackChanged)
        ..detach(this);
      _services!.pipKeeper.pageRemoved(playback);
    }
    if (_services != null) {
      _applySystemUi();
      // A newer page's begin makes this a no-op. Disposal runs while the tree is locked, and end() notifies the
      // newer page.
      if (fromDispose) {
        final orientation = _orientation;
        scheduleMicrotask(() => orientation.end(this));
      } else {
        _orientation.end(this);
      }
    }
  }

  @override
  void dispose() {
    _leave(fromDispose: true);
    _playback?.letGo(this);
    _stopFollowingSignIn();
    pageRoutes.unsubscribe(this);
    _services?.device.orientation.removeListener(_presentationChanged);
    _panels.removeListener(_panelChanged);
    _overlays
      ..removeListener(_panelChanged)
      ..removeListener(_standAside);
    _commentOverlays
      ..removeListener(_panelChanged)
      ..dispose();
    _threadEdge.dispose();
    _listCount.dispose();
    _comments
      ?..removeListener(_commentsChanged)
      ..dispose();
    _autoHideInputs?.removeListener(_syncAutoHide);
    _collapse
      ..removeListener(_collapseChanged)
      ..dispose();
    _grow.dispose();
    unawaited(_turns?.cancel());
    _turnTimeout?.cancel();
    _flushDrawn();
    _spin.dispose();
    _turningPlayer.dispose();
    _verticalTurn.dispose();
    _pin.dispose();
    _laidOut.dispose();
    _details?.dispose();
    _turnWait?.cancel();
    _logins.dispose();
    _danmaku
      ?..sendOpen.removeListener(_panelChanged)
      ..dispose();
    _chrome.dispose();
    _panels.dispose();
    _overlays.dispose();
    _tabs.dispose();
    _noScroll.dispose();
    _drafts.removeListener(_postLanded);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final presentation = _presentation;
    final size = MediaQuery.sizeOf(context);
    final wide = size.width > size.height;
    final layout = _layoutFor(size);
    _followTurn(presentation, _drawnWide ?? wide);
    if (_pendingTurn case final turn? when turn.wide == wide) _beginTurn(turn);
    _drawnWide = wide;
    _laidOut.value = layout;
    final fullScreen = layout.fullScreen;
    final controller = _controller;
    final mine = controller != null && _mine;
    final ui = mine ? _ui : null;
    _collapse.still = MediaQuery.disableAnimationsOf(context);
    return PopScope<Object?>(
      canPop:
          !presentation.fullScreen &&
          // Turning back, the landscape chrome is still drawn; its 〈 must not take the page with it.
          !fullScreen &&
          // Nor a swipe back while the page draws the turn: the upright size is in from its start.
          _turnFrom == null &&
          _pendingTurn == null &&
          !_spin.isAnimating &&
          !(_danmaku?.sendOpen.value ?? false) &&
          _panels.value == null &&
          _overlays.value == null &&
          _commentOverlays.value == null &&
          !_threadOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          setState(_leave);
        } else if (_closeDanmakuSend()) {
          return;
        } else if (!presentation.fullScreen && _closeComments()) {
          return;
        } else if (_overlays.value != null) {
          _overlays.close();
        } else if (_panels.value != null) {
          _panels.close();
        } else if (_presentation.fullScreen) {
          _orientation.exitToInline();
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        // A tap on the status bar scrolls the Scaffold's primary controller to the top: the shown tab's. Each tab hands
        // its list its own, and nothing else in the body takes one, so the composer's lists and the panels stay off it.
        child: ListenableBuilder(
          listenable: _tabs,
          // 评论详情 covers the tabs and scrolls on its own: a tap then reaches nothing rather than the list under it.
          builder: (context, scaffold) => PrimaryScrollController(
            controller: _threadOpen ? _noScroll : _tabs.scrollOf(_tabs.selected),
            child: scaffold!,
          ),
          child: Scaffold(
            backgroundColor: fullScreen ? BiliColors.videoBackground : BiliColors.card,
            // The comment composer rides on the keyboard by itself, and the full-screen player keeps its size under it.
            resizeToAvoidBottomInset: false,
            body: PrimaryScrollController.none(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final media = MediaQuery.of(context);
                  final top = media.padding.top;
                  if (!fullScreen) {
                    _collapse.full = constraints.maxWidth / BiliMetrics.videoAspect;
                    _uprightFrame = (size: constraints.biggest, top: top);
                  }
                  final upright = _uprightFrame ?? (size: constraints.biggest, top: top);
                  // 评论详情 covers the tab row and the list, for VoiceOver too.
                  Widget belowPlayer(Widget child) => ExcludeSemantics(
                    excluding: _threadOpen,
                    child: MediaQuery.removePadding(context: context, removeTop: true, child: child),
                  );
                  // Out of sight in full screen, except while the player grows over it or shrinks back.
                  Widget hideable(bool hidden, Widget child) =>
                      Offstage(offstage: hidden, child: TickerMode(enabled: !hidden, child: child));
                  // Laid out as if the player were already the bar; each tab leaves the rest of the full height free.
                  final pager = belowPlayer(PlayerReserve(height: _collapse.reserve, child: _pager(context)));
                  final tabRow = belowPlayer(_tabRow(context));
                  // Full screen runs under the notch and the home indicator, so its chrome keeps clear of them itself;
                  // the small player sits below the status bar with no insets of its own.
                  final area = MediaQuery(
                    data: media.removePadding(removeTop: !fullScreen, removeBottom: !fullScreen),
                    // An open panel covers the player for VoiceOver too, as landscape's panel does.
                    child: ExcludeSemantics(
                      excluding: _panels.value != null,
                      child: VideoPlayerArea(
                        key: _areaKey,
                        presentation: layout,
                        onBack: _back,
                        ui: ui,
                        video: mine ? _videoView : null,
                        danmaku: mine ? controller.danmaku : null,
                        cover: _cover(context),
                        loading: _loading(controller, mine),
                        failure: _failure(controller, mine),
                        onRetry: _retry,
                        endScreenAside: _overlayAside,
                        shrunk: _shrunk && !fullScreen,
                        barred: _barred && !fullScreen,
                        danmakuHeight: fullScreen ? null : _collapse.full,
                        pin: _pin,
                        turning: _turningPlayer,
                        verticalTurn: _verticalTurn,
                      ),
                    ),
                  );
                  final actionOverlays = switch ((ui, _details)) {
                    (final ui?, final details?) => ListenableBuilder(
                      listenable: details,
                      builder: (context, _) => ActionOverlays(
                        actions: details.actions,
                        controller: _overlays,
                        landscape: layout == Presentation.landscape,
                        shareLink: ui.session.shareLink,
                      ),
                    ),
                    _ => null,
                  };
                  // Only the player's box follows the scrolling, the grow and the turn; everything else is built once
                  // per page build.
                  return ListenableBuilder(
                    listenable: Listenable.merge([_collapse, _grow, _spin]),
                    builder: (context, _) {
                      final height = fullScreen ? constraints.maxHeight : _collapse.height;
                      final box = fullScreen ? height : top + height;
                      final progress = fullScreen ? 0.0 : _collapse.progress;
                      final turn = _turning(constraints.biggest, layout, upright.top);
                      final spinning = _spin.isAnimating;
                      final hidden = fullScreen && turn?.body == null;
                      final player = turn?.box ?? Rect.fromLTWH(0, 0, constraints.maxWidth, box);
                      _pin.value = turn == null ? null : Size(constraints.maxWidth, height);
                      _verticalTurn.value = turn != null && _upright == Presentation.vertical ? turn.t : null;
                      // The chrome goes from the change of presentation, so the host's still picture has none either.
                      _turningPlayer.value = turn != null || spinning || _turnFrom != null || _pendingTurn != null;
                      // The tab row and the list ride on the player's bottom edge, at their upright size.
                      final body = turn?.body ?? Offset.zero;
                      final uprightBox = upright.top + _collapse.height;
                      final tabsTop = upright.top + CollapseTheme.barHeight + PageTheme.tabRowHeight;
                      final screen = Offset.zero & constraints.biggest;
                      // Turned, a backdrop the screen's size would bare its corners.
                      final reach = constraints.biggest.bottomRight(Offset.zero).distance;
                      final backdrop = spinning
                          ? Rect.fromCenter(center: screen.center, width: reach, height: reach)
                          : screen;
                      final page = Stack(
                        // The growing box overflows the upright page; a clip here would also mask the native view.
                        clipBehavior: Clip.none,
                        children: [
                          if (turn != null || spinning)
                            Positioned.fromRect(
                              key: const ValueKey('page-turn-backdrop'),
                              rect: backdrop,
                              child: const ColoredBox(color: BiliColors.videoBackground),
                            ),
                          Positioned(
                            key: const ValueKey('page-tabs-area'),
                            left: body.dx,
                            top: body.dy + tabsTop,
                            width: upright.size.width,
                            height: upright.size.height - tabsTop,
                            child: hideable(hidden, pager),
                          ),
                          Positioned(
                            key: const ValueKey('page-tab-row'),
                            left: body.dx,
                            top: body.dy + uprightBox,
                            width: upright.size.width,
                            height: PageTheme.tabRowHeight,
                            child: hideable(hidden, tabRow),
                          ),
                          Positioned(
                            key: const ValueKey('page-player'),
                            left: player.left,
                            top: player.top,
                            width: player.width,
                            height: player.height,
                            child: ColoredBox(
                              color: BiliColors.videoBackground,
                              child: Padding(
                                padding: EdgeInsets.only(top: turn?.inset ?? (fullScreen ? 0 : top)),
                                child: area,
                              ),
                            ),
                          ),
                          if (progress > 0 && turn == null)
                            Positioned(
                              key: const ValueKey('collapse-bar'),
                              left: 0,
                              right: 0,
                              top: top,
                              height: height,
                              child: ExcludeSemantics(
                                excluding: _panels.value != null,
                                child: CollapsedPlayerBar(
                                  progress: progress,
                                  onResume: _resume,
                                  onBack: _back,
                                  onMore: () => _panels.open(PlayerPanel.more),
                                ),
                              ),
                            ),
                          Positioned(
                            key: const ValueKey('comment-overlays'),
                            left: body.dx,
                            top: body.dy,
                            width: upright.size.width,
                            height: upright.size.height,
                            child: Offstage(
                              offstage: hidden,
                              child: TickerMode(
                                enabled: !hidden,
                                child: ExcludeFocus(
                                  excluding: hidden,
                                  child: CommentOverlays(
                                    model: _comments,
                                    controller: _commentOverlays,
                                    callbacks: _commentCallbacks,
                                    threadTop: uprightBox,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (ui != null)
                            Positioned.fill(
                              key: const ValueKey('video-panels'),
                              child: PanelLayer(ui: ui, playerBottom: fullScreen ? null : box),
                            ),
                          if (actionOverlays != null)
                            Positioned.fill(key: const ValueKey('video-overlays'), child: actionOverlays),
                          if (ui != null && _danmaku != null)
                            Positioned.fill(
                              key: const ValueKey('danmaku-overlays'),
                              child: DanmakuOverlays(
                                session: _danmaku!,
                                presentation: layout,
                                playerBottom: box,
                                toast: _toast,
                              ),
                            ),
                        ],
                      );
                      // The whole page turns about the screen's centre; nothing clips it but the screen.
                      return IgnorePointer(
                        ignoring: spinning,
                        child: Transform.rotate(key: const ValueKey('page-turn'), angle: _rotation, child: page),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The tab row under the small player. Before the session exists it shows the saved danmaku switch.
  Widget _tabRow(BuildContext context) {
    final session = _session;
    final danmaku = _danmaku;
    return ListenableBuilder(
      listenable: Listenable.merge([session ?? _tabs, _listCount, ?danmaku, ?danmaku?.sendOpen]),
      builder: (context, _) => PageTabRow(
        controller: _tabs,
        replyCount: _listCount.value ?? _intro.detail?.stat.reply,
        danmakuOn: session?.danmakuOn ?? PlayerPrefs.shared.danmakuOn,
        onToggleDanmaku: session == null ? null : () => session.setDanmakuOn(!session.danmakuOn),
        onSendDanmaku: () => danmaku?.openSend(),
        danmakuInputOpen: danmaku?.sendOpen.value ?? false,
        danmakuClosed: danmaku?.closed ?? false,
      ),
    );
  }

  /// 简介 | 评论. Before the session exists 简介 stays empty.
  Widget _pager(BuildContext context) {
    final session = _session;
    final details = _details;
    // Leaving, a related row's cover would otherwise fly back to a feed card showing the same video.
    return HeroMode(
      enabled: !_left,
      child: PageTabs(
        controller: _tabs,
        intro: session == null || details == null
            ? const SizedBox.expand()
            : IntroTab(
                content: _intro,
                details: details,
                onSeek: (seconds) => unawaited(session.seekAndPlay(seconds)),
                onOpenVideo: (id) => unawaited(_openVideoId(id)),
                onPlayEpisode: session.playEpisode,
                onOpenEpisodes: () => _panels.open(PlayerPanel.episodes),
                onOpenRelated: _openRelated,
                onWatchLater: (card) => unawaited(_watchLater(card)),
              ),
        comments: switch (_comments) {
          final comments? => CommentsTab(
            key: ObjectKey(comments),
            model: comments,
            callbacks: _commentCallbacks,
          ),
          null => const CommentsSlot(),
        },
      ),
    );
  }

  bool _loading(PlaybackController? controller, bool mine) {
    if (_playback?.startError != null) return false;
    if (mine) return controller!.phase == PlaybackPhase.loading;
    return !_left;
  }

  String? _failure(PlaybackController? controller, bool mine) {
    if (_playback?.startError case final error?) return '播放器启动失败：$error';
    if (mine && controller!.phase == PlaybackPhase.failed) return controller.error ?? '播放失败';
    return null;
  }

  /// The card's cover flies in and stays until this page's video first plays, then goes for good, as the official
  /// app's page opens.
  Widget? _cover(BuildContext context) {
    final route = widget.route;
    final cover = route.cover;
    if (cover == null) return null;
    // Two Heroes with one tag in a page throw at the next push or pop, and after another video opened on the page its
    // related videos can hold this one. HeroMode rather than no Hero, so the cover keeps its element.
    final flies = !_played && !_intro.related.any((card) => card.bvid == route.bvid);
    return IgnorePointer(
      key: const ValueKey('video-cover'),
      child: AnimatedOpacity(
        opacity: _played ? 0 : 1,
        duration: const Duration(milliseconds: 200),
        child: HeroMode(
          enabled: flies,
          child: Hero(
            tag: route.heroTag,
            flightShuttleBuilder: _coverInFlight,
            child: RemoteImage(cover, size: _coverSize(context)),
          ),
        ),
      ),
    );
  }

  /// The player box's final size: the cover is asked for once at it, however the box grows during the flight.
  static Size _coverSize(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Size(width, width / BiliMetrics.videoAspect);
  }

  /// The card's image, already loaded at the card's size, flies; the page's cover, the same download as the page's
  /// own, fades in over it once it arrives.
  Widget _coverInFlight(
    BuildContext flight,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext from,
    BuildContext to,
  ) {
    final cover = widget.route.cover;
    final card = (direction == HeroFlightDirection.push ? from : to).findRenderObject();
    final cardSize = card is RenderBox && card.hasSize ? card.size : null;
    return RemoteImage(
      cover,
      size: _coverSize(flight),
      placeholder: cardSize == null ? null : RemoteImage(cover, size: cardSize),
    );
  }
}
