import 'dart:async';

import 'package:bili_core/api.dart' as bili show VideoPage, VideoView;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_scope.dart';
import '../device/orientation.dart';
import '../playback/playback_controller.dart';
import '../player_ui/chrome_state.dart';
import '../player_ui/panels/panel_controller.dart';
import '../player_ui/panels/panel_layer.dart';
import '../player_ui/player_ui.dart';
import '../shared/remote_image.dart';
import '../shared/theme.dart';
import 'page_session.dart';
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

/// The video page: the player at 16:9 under a black status bar with the title, uploader and part below it, or the
/// player alone over the whole screen in full screen, which is this page laid out again rather than a route of its
/// own. It opens the route's video on the shared player, reports watch progress while logged in, and gives the player
/// back when it is popped. The intro, actions and comments come in later slices.
class VideoPage extends StatefulWidget {
  const VideoPage({super.key, required this.route, this.createSession = pageSession});

  final VideoRoute route;
  final PageSessionFactory createSession;

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
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
  /// route's own open starts at its position and uses its resolved view.
  late String _bvid = widget.route.bvid;
  late int? _cid = widget.route.cid;
  late double? _startAt = widget.route.start;
  late bili.VideoView? _view = widget.route.view;
  late String? _title = widget.route.title;

  /// The last video and part this page opened, so the title stays put while the page slides away.
  bili.VideoView? _video;
  bili.VideoPage? _part;

  PlayerSession? _session;
  PlayerUi? _ui;

  /// The native view: built once, so no layout switch or chrome change recreates it.
  Widget? _videoView;
  Listenable? _autoHideInputs;
  final _chrome = ChromeState();
  final _panels = PanelController();
  final _areaKey = GlobalKey();

  /// This page's begin is the orientation's latest, so the presentation is this page's.
  bool _owning = false;

  /// Whether this page's video is vertical; null until the video is known.
  bool? _vertical;
  bool? _current;
  bool? _immersive;

  OrientationController get _orientation => _services!.device.orientation;

  Presentation get _presentation => _owning && !_left ? _orientation.presentation : Presentation.inline;

  @override
  void initState() {
    super.initState();
    _panels.addListener(_panelChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services == null) {
      _services = AppScope.of(context);
      _orientation.addListener(_presentationChanged);
      _start();
    }
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (current == _current) return;
    final covered = _current == false;
    _current = current;
    if (!current) {
      _owning = false;
      _session?.active = false;
    } else if (covered) {
      // Shown again after the page above popped: this page takes the orientation back. Not during this build, since
      // the orientation's other listeners would rebuild inside it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _claimOrientation();
        final controller = _controller;
        if (controller != null && _isMine(controller)) _session?.active = true;
      });
    }
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
    unawaited(controller.openVideo(_bvid, cid: _cid, start: _startAt, view: _view));
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
    _ui = PlayerUi(
      session: session,
      chrome: _chrome,
      panels: _panels,
      orientation: _orientation,
      device: services.device.controls,
      onBack: _back,
    );
    _videoView = session.player.buildView();
    session.addListener(_sessionChanged);
    _autoHideInputs = Listenable.merge([session.readout.status, session.scrubbing, _panels])
      ..addListener(_syncAutoHide);
    _syncAutoHide();
    _sessionChanged();
  }

  /// Another part or video, from 选集, 自动连播 or the end screen: opened here, on the same page.
  void _openOnPage(String bvid, {int? cid}) {
    final controller = _controller;
    if (controller == null || !_isMine(controller)) return;
    if (bvid != _bvid) {
      _video = null;
      _part = null;
      _title = null;
    }
    _bvid = bvid;
    _cid = cid;
    _startAt = null;
    _view = null;
    _openVideo(controller);
  }

  bool _isMine(PlaybackController controller) => !_left && controller.opens == _open;

  void _follow() {
    final controller = _controller;
    if (controller == null) return;
    setState(() {
      if (!_isMine(controller)) return;
      if (controller.video case final video?) {
        _video = video;
        _part = controller.page;
      }
      if (controller.phase == PlaybackPhase.playing) _played = true;
    });
    _syncAutoHide();
  }

  void _sessionChanged() {
    final session = _session;
    final controller = _controller;
    // A covered page's session hears the newer page's video on the shared controller.
    if (session == null || controller == null || !_isMine(controller) || session.video == null) return;
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
    if (_left || vertical == null || _current == false) return;
    _owning = true;
    _orientation.begin(this, videoIsVertical: vertical);
  }

  void _presentationChanged() {
    if (!mounted) return;
    setState(() {});
    _applySystemUi();
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
        _panels.value == null;
  }

  /// Rebuilds the PopScope, which lets a pop through only with no panel open.
  void _panelChanged() {
    if (mounted) setState(() {});
  }

  /// Back closes an open panel first, in every presentation.
  void _back() {
    if (_panels.value != null) {
      _panels.close();
    } else if (_presentation.fullScreen) {
      _orientation.exitToInline();
    } else {
      unawaited(Navigator.of(context).maybePop());
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
    _session?.active = false;
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
    _services?.device.orientation.removeListener(_presentationChanged);
    _panels.removeListener(_panelChanged);
    _autoHideInputs?.removeListener(_syncAutoHide);
    final session = _session;
    session?.removeListener(_sessionChanged);
    // PlayerSession declares no dispose; the app's session is a ChangeNotifier that frees what it holds.
    if (session case final ChangeNotifier notifier) notifier.dispose();
    _chrome.dispose();
    _panels.dispose();
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
      canPop: !fullScreen && _panels.value == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          setState(_leave);
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
                        child: _Details(title: _title, video: _video, part: _part),
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
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (ui != null) Positioned.fill(key: const ValueKey('video-panels'), child: PanelLayer(ui: ui)),
                ],
              );
            },
          ),
        ),
      ),
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
    return IgnorePointer(
      key: const ValueKey('video-cover'),
      child: AnimatedOpacity(
        opacity: _played ? 0 : 1,
        duration: const Duration(milliseconds: 200),
        child: Hero(
          tag: route.heroTag,
          flightShuttleBuilder: _coverInFlight,
          child: RemoteImage(cover, size: _coverSize(context)),
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

/// The title, uploader and, for a video in parts, the part playing; the route's title until the video's own arrives.
class _Details extends StatelessWidget {
  const _Details({required this.title, required this.video, required this.part});

  final String? title;
  final bili.VideoView? video;
  final bili.VideoPage? part;

  @override
  Widget build(BuildContext context) {
    final video = this.video;
    final part = this.part;
    final title = video?.title ?? this.title ?? '';
    return ListView(
      padding: const EdgeInsets.all(BiliMetrics.gutter),
      children: [
        Text(
          title,
          key: const ValueKey('video-title'),
          style: const TextStyle(fontSize: BiliMetrics.titleText, color: BiliColors.text, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: BiliMetrics.rowGap),
        Text(
          [
            if (video?.owner case final owner? when owner.isNotEmpty) owner,
            if (video != null && video.pages.length > 1 && part != null) 'P${part.page} ${part.part}',
          ].join(' · '),
          key: const ValueKey('video-meta'),
          style: const TextStyle(fontSize: BiliMetrics.smallText, color: BiliColors.secondaryText),
        ),
      ],
    );
  }
}
