import 'dart:async';

import 'package:bili_core/api.dart' as bili show VideoPage, VideoView;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_scope.dart';
import '../playback/playback_controller.dart';
import '../player_ui/player_stage.dart';
import '../shared/remote_image.dart';
import '../shared/theme.dart';
import 'video_route.dart';
import 'watch_reporter.dart';

typedef VideoStageBuilder = Widget Function(
  BuildContext context,
  PlaybackController controller,
  void Function(double seconds, {required bool precise}) onSeek,
);

Widget videoStage(
  BuildContext context,
  PlaybackController controller,
  void Function(double seconds, {required bool precise}) onSeek,
) => PlayerStage(
  player: controller.player,
  clock: controller.clock,
  stats: controller.stats,
  showStats: false,
  duration: controller.duration,
  danmaku: controller.danmaku.timeline,
  danmakuEnabled: true,
  onSeek: onSeek,
  onHint: controller.seekHint,
);

/// The video page's shell (slice 3): the player at 16:9 under a black status bar, the title, uploader and part below
/// it. It opens the route's video on the shared player, reports watch progress while logged in, and gives the player
/// back when it is popped. The intro, actions and comments come in later slices.
class VideoPage extends StatefulWidget {
  const VideoPage({super.key, required this.route, this.stageBuilder = videoStage});

  final VideoRoute route;
  final VideoStageBuilder stageBuilder;

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

  /// The last video and part this page opened, so the title stays put while the page slides away.
  bili.VideoView? _video;
  bili.VideoPage? _part;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = AppScope.of(context);
    _start();
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
    final route = widget.route;
    final services = _services!;
    unawaited(_reporter?.leave());
    unawaited(controller.openVideo(route.bvid, cid: route.cid, start: route.start, view: route.view));
    _reporter = WatchReporter(
      controller: controller,
      client: services.environment.client,
      loggedIn: () => WatchReporter.canReport(services.environment),
    );
    setState(() => _open = controller.opens);
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

  void _seeked(double seconds, {required bool precise}) {
    _controller?.userSeeked(seconds, precise: precise);
    _reporter?.seeked(seconds);
  }

  /// Runs at the pop, not at dispose 500 ms later: a card opened during the transition would by then have the
  /// player, and this page would report and close the newer page's video.
  void _leave({bool fromDispose = false}) {
    if (_left) return;
    _left = true;
    final controller = _controller;
    controller?.removeListener(_follow);
    unawaited(_reporter?.leave());
    if (controller == null || controller.opens != _open) return;
    // Disposal runs while the tree is locked, and close() notifies the other pages listening to the player.
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) setState(_leave);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: BiliColors.card,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _box(context),
              Expanded(child: _Details(route: widget.route, video: _video, part: _part)),
            ],
          ),
        ),
      ),
    );
  }

  /// Black from the top of the screen down to the bottom of the 16:9 player. The layers are keyed so the cover's Hero
  /// keeps its element while the stage, spinner and failure come and go, even mid-flight.
  Widget _box(BuildContext context) {
    final route = widget.route;
    final cover = route.cover;
    final controller = _controller;
    final mine = controller != null && _isMine(controller);
    final phase = mine ? controller.phase : (_left ? PlaybackPhase.idle : PlaybackPhase.loading);
    final failed = _startError != null || phase == PlaybackPhase.failed;
    return ColoredBox(
      color: BiliColors.videoBackground,
      child: SafeArea(
        bottom: false,
        child: AspectRatio(
          aspectRatio: BiliMetrics.videoAspect,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (mine && controller.video != null && !failed)
                KeyedSubtree(
                  key: const ValueKey('video-stage'),
                  child: widget.stageBuilder(context, controller, _seeked),
                ),
              // The card's cover flies in and stays until this page's video first plays, then goes for good, as the
              // official app's page opens.
              if (cover != null)
                IgnorePointer(
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
                ),
              if (failed)
                _Failure(
                  key: const ValueKey('video-failure'),
                  message: _startError == null ? controller?.error ?? '播放失败' : '播放器启动失败：$_startError',
                  onRetry: _retry,
                )
              else if (phase == PlaybackPhase.loading)
                const Center(
                  key: ValueKey('video-loading'),
                  child: CupertinoActivityIndicator(color: BiliColors.onVideo, radius: BiliMetrics.videoSpinnerRadius),
                ),
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  key: const ValueKey('video-back'),
                  onPressed: () => Navigator.of(context).maybePop(),
                  // Sits on the picture itself, over danmaku and white frames.
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: BiliColors.onVideo,
                    size: BiliMetrics.videoBackIcon,
                    shadows: [Shadow(color: BiliColors.chromeShade, blurRadius: BiliMetrics.videoBackShadow)],
                  ),
                  tooltip: '返回',
                ),
              ),
            ],
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

class _Failure extends StatelessWidget {
  const _Failure({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: BiliColors.videoBackground,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(BiliMetrics.sectionGap),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              key: const ValueKey('video-error'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: BiliMetrics.bodyText, color: BiliColors.onVideo),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: BiliMetrics.rowGap),
              OutlinedButton(
                key: const ValueKey('video-retry'),
                onPressed: onRetry,
                style: OutlinedButton.styleFrom(
                  foregroundColor: BiliColors.onVideo,
                  side: const BorderSide(color: BiliColors.onVideo),
                ),
                child: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// The title, uploader and, for a video in parts, the part playing; the route's title until the video's own arrives.
class _Details extends StatelessWidget {
  const _Details({required this.route, required this.video, required this.part});

  final VideoRoute route;
  final bili.VideoView? video;
  final bili.VideoPage? part;

  @override
  Widget build(BuildContext context) {
    final video = this.video;
    final part = this.part;
    final title = video?.title ?? route.title ?? '';
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
