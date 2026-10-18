import 'dart:async';

import 'package:bili_core/api.dart' as bili
    show AidLink, BvidLink, LinkParser, VideoCard, VideoDetail, VideoPage, VideoView;
import 'package:bili_core/devlog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_environment.dart';
import '../app/app_scope.dart';
import '../app/route_observer.dart';
import '../device/orientation.dart';
import '../home/feed_model.dart' show requestFailureMessage;
import '../playback/playback_controller.dart';
import '../player_ui/chrome_state.dart';
import '../player_ui/panels/panel_controller.dart';
import '../player_ui/panels/panel_layer.dart';
import '../player_ui/player_ui.dart';
import '../shared/remote_image.dart';
import '../shared/theme.dart';
import '../shared/toast.dart';
import 'actions/action_overlays.dart';
import 'intro/intro_tab.dart';
import 'page_details.dart';
import 'page_details_model.dart';
import 'page_session.dart';
import 'page_tabs.dart';
import 'player_prefs.dart';
import 'player_session.dart';
import 'video_player_area.dart';
import 'video_route.dart';
import 'watch_reporter.dart';

typedef PageSessionFactory = PlayerSession Function({
  required PlaybackController controller,
  required AppServices services,
  required SessionOpen open,
  required void Function(double seconds) onSeeked,
});

/// The app's session for a video page. [onSeeked] reaches the watch reporter: every seek the session commits.
PlayerSession pageSession({
  required PlaybackController controller,
  required AppServices services,
  required SessionOpen open,
  required void Function(double seconds) onSeeked,
}) => createPageSession(controller: controller, services: services, open: open, onSeeked: onSeeked);

typedef PageDetailsFactory = PageDetails Function({
  required PlayerSession session,
  required AppServices services,
  required void Function(String message) toast,
});

/// The app's page details. Logging in comes in slice 8; until then an action that needs it says so.
PageDetails pageDetails({
  required PlayerSession session,
  required AppServices services,
  required void Function(String message) toast,
}) {
  final environment = services.environment;
  return VideoPageDetailsModel(
    session: session,
    api: services.pageApi,
    isLoggedIn: () => environment.account is LoggedIn,
    accountMid: () => environment.mid,
    requestLogin: () => toast('请先登录'),
    toast: toast,
    accountChanges: environment,
  );
}

typedef VideoPageOpener = Future<void> Function(BuildContext context, VideoRoute route);

/// The video page: the player at 16:9 under a black status bar with the tab row and 简介 | 评论 below it, or the
/// player alone over the whole screen in full screen, which is this page laid out again rather than a route of its
/// own. It opens the route's video on the shared player, reports watch progress while logged in, and gives the player
/// back when it is popped. A page shown again after a newer video page took the player opens its video again where
/// it was covered. The comments come in slice 7.
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

class _VideoPageState extends State<VideoPage> with RouteAware {
  AppServices? _services;
  PlaybackController? _controller;
  WatchReporter? _reporter;
  String? _startError;

  /// The controller's open count once this page opened its video; a later one means a newer page has the player.
  int? _open;

  /// Popped, or disposed without a pop: the last position went out and the player was given back.
  bool _left = false;

  /// This page's video has played, so a fallback, reload or replay shows the player rather than the cover again.
  bool _played = false;

  /// What this page plays: the route's video at first, then whatever the session opens on the page. Only the
  /// route's own open starts at its position; another part of the same video reuses the view and detail it has.
  late String _bvid = widget.route.bvid;
  late int? _cid = widget.route.cid;
  late double? _startAt = widget.route.start;
  late bili.VideoView? _view = widget.route.view;
  late bili.VideoDetail? _detail = widget.route.detail;

  PlayerSession? _session;
  PageDetails? _details;
  PlayerUi? _ui;

  /// 简介's video, taken from the session only while the player is this page's.
  IntroContent _intro = const IntroContent();

  /// Where this page's video stood when another page covered it, for opening it again once shown.
  ({double seconds, bili.VideoView? view, bili.VideoPage? part, bili.VideoDetail? detail})? _coveredAt;

  /// The native view: built once, so no layout switch or chrome change recreates it.
  Widget? _videoView;
  Listenable? _autoHideInputs;
  final _chrome = ChromeState();
  final _panels = PanelController();
  final _overlays = ActionOverlayController();
  final _tabs = PageTabsController();
  final _areaKey = GlobalKey();

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

  OrientationController get _orientation => _services!.device.orientation;

  Presentation get _presentation => _owning && !_left ? _orientation.presentation : Presentation.inline;

  @override
  void initState() {
    super.initState();
    _panels.addListener(_panelChanged);
    _overlays
      ..addListener(_panelChanged)
      ..addListener(_standAside);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services == null) {
      _services = AppScope.of(context);
      _orientation.addListener(_presentationChanged);
      _start();
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
    final controller = _controller;
    if (controller != null && _isMine(controller)) {
      _coveredAt = (
        seconds: controller.currentSeconds,
        view: controller.video,
        part: controller.page,
        detail: controller.detail,
      );
    }
    _setActive(false);
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
      final controller = _controller;
      if (controller == null) return;
      if (_isMine(controller)) {
        _coveredAt = null;
        _setActive(true);
      } else if (_session != null) {
        _reopen(controller);
      }
    });
  }

  void _setActive(bool active) {
    _session?.active = active;
    _details?.active = active;
  }

  /// The page above had the player and gave it back closed: this page plays its own video again from where it was
  /// covered. A stopgap until slice 9 resumes without a reload.
  void _reopen(PlaybackController controller) {
    if (_coveredAt case final covered?) {
      _coveredAt = null;
      _startAt = covered.seconds;
      if (covered.part case final part?) _cid = part.cid;
      if (covered.view case final view? when view.bvid == _bvid) _view = view;
      if (covered.detail case final detail? when detail.bvid == _bvid) _detail = detail;
    }
    _openVideo(controller);
    _setActive(true);
  }

  void _start() {
    _services!.playback.obtain().then(
      _begin,
      onError: (Object error) {
        if (mounted && !_left) setState(() => _startError = '$error');
      },
    );
  }

  void _begin(PlaybackController controller) {
    if (!mounted || _left) return;
    _controller = controller;
    _startError = null;
    controller.addListener(_follow);
    _openVideo(controller);
  }

  void _openVideo(PlaybackController controller) {
    final services = _services!;
    unawaited(_reporter?.leave());
    unawaited(controller.openVideo(_bvid, cid: _cid, start: _startAt, view: _view, detail: _detail));
    _reporter = WatchReporter(
      controller: controller,
      client: services.environment.client,
      loggedIn: () => WatchReporter.canReport(services.environment),
    );
    setState(() => _open = controller.opens);
    if (_session == null) _makeSession(controller);
  }

  void _makeSession(PlaybackController controller) {
    final services = _services!;
    final session = widget.createSession(
      controller: controller,
      services: services,
      open: _openOnPage,
      onSeeked: (seconds) => _reporter?.seeked(seconds),
    );
    _session = session;
    final details = widget.createDetails(session: session, services: services, toast: _toast);
    _details = details;
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
    );
    _videoView = session.player.buildView();
    session.addListener(_sessionChanged);
    _autoHideInputs = Listenable.merge([session.readout.status, session.scrubbing, _panels, _overlays])
      ..addListener(_syncAutoHide);
    _syncAutoHide();
    _sessionChanged();
  }

  /// Another part or video, from 选集, 自动连播 or the end screen: opened here, on the same page.
  void _openOnPage(String bvid, {int? cid}) {
    final controller = _controller;
    if (controller == null || !_isMine(controller)) return;
    final samePart = bvid == _bvid;
    // Another part of this video needs no second signed view.
    _view = samePart ? controller.video : null;
    _detail = samePart ? controller.detail : null;
    _bvid = bvid;
    _cid = cid;
    _startAt = null;
    _openVideo(controller);
  }

  bool _isMine(PlaybackController controller) => !_left && controller.opens == _open;

  void _follow() {
    final controller = _controller;
    if (controller == null) return;
    setState(() {
      if (!_isMine(controller)) return;
      if (_session case final session?) _intro = IntroContent.of(session);
      if (controller.phase == PlaybackPhase.playing) _played = true;
    });
    _syncAutoHide();
  }

  void _sessionChanged() {
    final session = _session;
    final controller = _controller;
    // A covered page's session hears the newer page's video on the shared controller.
    if (session == null || controller == null || !_isMine(controller)) return;
    final intro = IntroContent.of(session);
    if (intro != _intro && mounted) setState(() => _intro = intro);
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

  /// Once the video is known, and again each time the page is shown after one above it: the latest begin wins.
  void _claimOrientation() {
    final vertical = _vertical;
    if (_left || vertical == null || _covered) return;
    _owning = true;
    _orientation.begin(this, videoIsVertical: vertical);
  }

  void _presentationChanged() {
    if (!mounted) return;
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
    _chrome.autoHide = _isMine(controller) &&
        controller.phase == PlaybackPhase.playing &&
        session.readout.wantsPlay &&
        session.scrubbing.value == null &&
        _panels.value == null &&
        _overlays.value == null;
  }

  /// Rebuilds the PopScope, which lets a pop through only with no overlay or panel open.
  void _panelChanged() {
    if (mounted) setState(() {});
  }

  /// Back closes an open overlay first, then a panel, in every presentation.
  void _back() {
    if (_overlays.value != null) {
      _overlays.close();
    } else if (_panels.value != null) {
      _panels.close();
    } else if (_presentation.fullScreen) {
      _orientation.exitToInline();
    } else {
      unawaited(Navigator.of(context).maybePop());
    }
  }

  void _toast(String message) {
    if (mounted) showToast(context, message);
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
        if (bvid == _bvid) return;
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
        if (!mounted || _left || !(ModalRoute.isCurrentOf(context) ?? false) || view.bvid == _bvid) return;
        await widget.openPage(context, VideoRoute(bvid: view.bvid, title: view.title, view: view));
      default:
        break;
    }
  }

  VoidCallback? get _retry {
    if (_startError != null) {
      return () {
        setState(() => _startError = null);
        _start();
      };
    }
    final controller = _controller;
    return controller == null ? null : () => _openVideo(controller);
  }

  /// Runs at the pop, not at dispose 500 ms later: a card opened during the transition would by then have the
  /// player, and this page would report and close the newer page's video.
  void _leave({bool fromDispose = false}) {
    if (_left) return;
    _left = true;
    _owning = false;
    _setActive(false);
    final controller = _controller;
    controller?.removeListener(_follow);
    unawaited(_reporter?.leave());
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
    if (controller == null || controller.opens != _open) return;
    // close() notifies the other pages listening to the player as well.
    if (fromDispose) {
      final open = _open;
      scheduleMicrotask(() {
        if (controller.opens == open) controller.close();
      });
    } else {
      controller.close();
    }
  }

  @override
  void dispose() {
    _leave(fromDispose: true);
    pageRoutes.unsubscribe(this);
    _services?.device.orientation.removeListener(_presentationChanged);
    _panels.removeListener(_panelChanged);
    _overlays
      ..removeListener(_panelChanged)
      ..removeListener(_standAside);
    _autoHideInputs?.removeListener(_syncAutoHide);
    final session = _session;
    session?.removeListener(_sessionChanged);
    _details?.dispose();
    // PlayerSession declares no dispose; the app's session is a ChangeNotifier that frees what it holds.
    if (session case final ChangeNotifier notifier) notifier.dispose();
    _chrome.dispose();
    _panels.dispose();
    _overlays.dispose();
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final presentation = _presentation;
    final fullScreen = presentation.fullScreen;
    final controller = _controller;
    final mine = controller != null && _isMine(controller);
    final ui = mine ? _ui : null;
    return PopScope<Object?>(
      canPop: !fullScreen && _panels.value == null && _overlays.value == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          setState(_leave);
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
        child: Scaffold(
          backgroundColor: fullScreen ? BiliColors.videoBackground : BiliColors.card,
          body: LayoutBuilder(
            builder: (context, constraints) {
              final media = MediaQuery.of(context);
              final top = media.padding.top;
              final box = fullScreen ? constraints.maxHeight : top + constraints.maxWidth / BiliMetrics.videoAspect;
              return Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: box,
                    bottom: 0,
                    child: Offstage(
                      offstage: fullScreen,
                      child: TickerMode(
                        enabled: !fullScreen,
                        child: MediaQuery.removePadding(context: context, removeTop: true, child: _body(context)),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: box,
                    child: ColoredBox(
                      color: BiliColors.videoBackground,
                      child: Padding(
                        padding: EdgeInsets.only(top: fullScreen ? 0 : top),
                        // Full screen runs under the notch and the home indicator, so its chrome keeps clear of
                        // them itself; the small player sits below the status bar with no insets of its own.
                        child: MediaQuery(
                          data: media.removePadding(removeTop: !fullScreen, removeBottom: !fullScreen),
                          // An open panel covers the player for VoiceOver too, as landscape's panel already does.
                          child: ExcludeSemantics(
                            excluding: _panels.value != null,
                            child: VideoPlayerArea(
                              key: _areaKey,
                              presentation: presentation,
                              onBack: _back,
                              ui: ui,
                              video: mine ? _videoView : null,
                              danmaku: mine ? controller.danmaku : null,
                              cover: _cover(context),
                              loading: _loading(controller, mine),
                              failure: _failure(controller, mine),
                              onRetry: _retry,
                              endScreenAside: _overlayAside,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (ui != null) Positioned.fill(key: const ValueKey('video-panels'), child: PanelLayer(ui: ui)),
                  if ((ui, _details) case (final ui?, final details?))
                    Positioned.fill(
                      key: const ValueKey('video-overlays'),
                      child: ListenableBuilder(
                        listenable: details,
                        builder: (context, _) => ActionOverlays(
                          actions: details.actions,
                          controller: _overlays,
                          landscape: presentation == Presentation.landscape,
                          shareLink: ui.session.shareLink,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// The tab row and the pager under the small player. Before the session exists the row shows the saved danmaku
  /// switch and 简介 stays empty.
  Widget _body(BuildContext context) {
    final session = _session;
    final details = _details;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListenableBuilder(
          listenable: session ?? _tabs,
          builder: (context, _) => PageTabRow(
            controller: _tabs,
            replyCount: _intro.detail?.stat.reply,
            danmakuOn: session?.danmakuOn ?? PlayerPrefs.shared.danmakuOn,
            onToggleDanmaku: session == null ? null : () => session.setDanmakuOn(!session.danmakuOn),
            onSendDanmaku: () => _toast('发弹幕将在下个版本推出'),
          ),
        ),
        Expanded(
          // Leaving, a related row's cover would otherwise fly back to a feed card showing the same video.
          child: HeroMode(
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
              comments: const CommentsPlaceholder(),
            ),
          ),
        ),
      ],
    );
  }

  bool _loading(PlaybackController? controller, bool mine) {
    if (_startError != null) return false;
    if (mine) return controller!.phase == PlaybackPhase.loading;
    return !_left;
  }

  String? _failure(PlaybackController? controller, bool mine) {
    if (_startError case final error?) return '播放器启动失败：$error';
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
