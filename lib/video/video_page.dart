import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_environment.dart';
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

/// The video page's shell (slice 3): the player at 16:9 under a black status bar, the title and part below it.
/// It opens the route's video on the shared player, reports watch progress while logged in, and gives the player
/// back when it goes. The intro, actions and comments come in later slices.
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
  bool _disposed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    final services = AppScope.of(context);
    _services = services;
    services.playback.obtain().then(
      (controller) {
        if (_disposed) return;
        setState(() => _controller = controller);
        _reporter = WatchReporter(
          controller: controller,
          client: services.environment.client,
          loggedIn: () => services.environment.account is LoggedIn,
        );
        _openVideo(controller);
      },
      onError: (Object error) {
        if (!_disposed) setState(() => _startError = '$error');
      },
    );
  }

  void _openVideo(PlaybackController controller) {
    final route = widget.route;
    unawaited(controller.openVideo(route.bvid, cid: route.cid, start: route.start, view: route.view));
    _open = controller.opens;
  }

  void _seeked(double seconds, {required bool precise}) {
    _controller?.userSeeked(seconds, precise: precise);
    _reporter?.seeked(seconds);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_reporter?.leave());
    final controller = _controller;
    if (controller != null && controller.opens == _open) controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: BiliColors.card,
        body: controller == null
            ? Column(
                children: [
                  _box(context, null),
                  const Expanded(child: SizedBox()),
                ],
              )
            : ListenableBuilder(
                listenable: controller,
                builder: (context, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _box(context, controller),
                    Expanded(
                      child: _Details(route: widget.route, controller: controller),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  /// Black from the top of the screen down to the bottom of the 16:9 player.
  Widget _box(BuildContext context, PlaybackController? controller) {
    final route = widget.route;
    final phase = controller?.phase ?? PlaybackPhase.loading;
    final showsVideo = controller != null && controller.video != null && phase != PlaybackPhase.failed;
    return ColoredBox(
      color: BiliColors.videoBackground,
      child: SafeArea(
        bottom: false,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (showsVideo) widget.stageBuilder(context, controller, _seeked),
              // The card's cover flies in and stays until the first frame, as the official app's page opens.
              if (route.cover != null)
                IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: phase == PlaybackPhase.playing ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: Hero(tag: route.heroTag, child: RemoteImage(route.cover)),
                  ),
                ),
              if (_startError != null || phase == PlaybackPhase.failed)
                _Failure(
                  message: _startError == null ? controller?.error ?? '播放失败' : '播放器启动失败：$_startError',
                  onRetry: controller == null ? null : () => _openVideo(controller),
                )
              else if (phase == PlaybackPhase.loading)
                const Center(
                  child: SizedBox.square(
                    dimension: BiliMetrics.chromeIcon,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: BiliColors.onVideo),
                  ),
                ),
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  key: const ValueKey('video-back'),
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: BiliColors.onVideo, size: 20),
                  tooltip: '返回',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.message, required this.onRetry});

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

/// The title and, for a video in parts, the part playing; the card's title until the video's own arrives.
class _Details extends StatelessWidget {
  const _Details({required this.route, required this.controller});

  final VideoRoute route;
  final PlaybackController controller;

  @override
  Widget build(BuildContext context) {
    final video = controller.video;
    final page = controller.page;
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
            if (video != null && video.pages.length > 1 && page != null) 'P${page.page} ${page.part}',
          ].join(' · '),
          key: const ValueKey('video-meta'),
          style: const TextStyle(fontSize: BiliMetrics.smallText, color: BiliColors.secondaryText),
        ),
      ],
    );
  }
}
