import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:flutter/widgets.dart';

import '../../app/app_scope.dart';
import '../../player_ui/landscape_chrome.dart' show fullScreenText, fullScreenStrut;
import '../../player_ui/player_loading.dart';
import '../../player_ui/portrait_controls.dart' show ChromeTap;
import '../../shared/remote_image.dart';
import '../../shared/theme.dart';
import '../danmaku/live_danmaku_layer.dart';
import '../room/live_overlays.dart';
import '../room/live_room_model.dart';
import 'live_full_screen.dart';
import 'live_player_controller.dart';

/// The picture with its controls: the 16:9 box with 弹 and the full-screen button in portrait (207, 208), the whole
/// screen with 209's controls when [fullScreen]. The danmaku over the video sit inside it. Opens [overlays]' layers
/// (⋮, 画质, 高能榜, the 弹幕 input); [onBack] is 209's ‹.
///
/// In portrait it fills the box the page gives it ([LivePlayerTheme.boxTop] to [LivePlayerTheme.boxBottom]); 208's
/// note hangs under the box in the app's overlay. In full screen it fills the screen, and the picture shrinks left of
/// a side panel ([LiveOverlay.more], [LiveOverlay.quality], [LiveOverlay.rank]) as 210, 222 and 232 show.
class LivePlayerView extends StatelessWidget {
  const LivePlayerView({
    super.key,
    required this.controller,
    required this.room,
    required this.overlays,
    required this.fullScreen,
    required this.onBack,
  });

  final LivePlayerController controller;
  final LiveRoomModel room;
  final LiveOverlays overlays;
  final bool fullScreen;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => fullScreen
      ? LiveFullScreen(controller: controller, room: room, overlays: overlays, onBack: onBack)
      : _Box(controller: controller, room: room);
}

/// The picture, the danmaku over it and what shows while it can't play (the loading TV, 直播已结束, 重试).
class LivePicture extends StatelessWidget {
  const LivePicture({super.key, required this.controller, required this.room, this.danmaku = true});

  final LivePlayerController controller;
  final LiveRoomModel room;

  /// Full screen keeps the danmaku over the whole screen while the picture shrinks beside a panel, so it draws them
  /// itself.
  final bool danmaku;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: BiliColors.videoBackground,
    child: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final player = controller.player;
        final phase = controller.phase;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (player != null && phase != LivePlayerPhase.ended && phase != LivePlayerPhase.failed)
              _NativeView(key: ObjectKey(player), build: player.buildView),
            if (danmaku)
              IgnorePointer(
                child: LiveDanmakuLayer(room: room, on: controller.danmakuOn),
              ),
            LivePhaseLayer(controller: controller, room: room),
          ],
        );
      },
    ),
  );
}

/// The player's surface, built once per player so no rebuild makes a new platform view.
class _NativeView extends StatefulWidget {
  const _NativeView({super.key, required this.build});

  final Widget Function() build;

  @override
  State<_NativeView> createState() => _NativeViewState();
}

class _NativeViewState extends State<_NativeView> {
  late final Widget _view = widget.build();

  @override
  Widget build(BuildContext context) => _view;
}

/// The loading TV while waiting, the cover dimmed with 直播已结束, or 重试 after a failure.
class LivePhaseLayer extends StatelessWidget {
  const LivePhaseLayer({super.key, required this.controller, required this.room});

  final LivePlayerController controller;
  final LiveRoomModel room;

  @override
  Widget build(BuildContext context) {
    switch (controller.phase) {
      case LivePlayerPhase.waiting || LivePlayerPhase.loading:
        return const PlayerLoading(key: ValueKey('live-loading'));
      case LivePlayerPhase.ended:
        final cover = room.info?.cover ?? '';
        return Stack(
          key: const ValueKey('live-ended'),
          fit: StackFit.expand,
          children: [
            RemoteImage(cover.isEmpty ? room.entry.cover : cover, cover: true),
            const ColoredBox(color: LivePlayerTheme.endedDim),
            Center(child: _text('直播已结束', LivePlayerTheme.endedText)),
          ],
        );
      case LivePlayerPhase.failed:
        return Center(
          key: const ValueKey('live-failed'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: BiliMetrics.rowGap,
            children: [
              _text('直播加载失败', LivePlayerTheme.endedText),
              ChromeTap(
                key: const ValueKey('live-retry'),
                label: '重试',
                square: false,
                onTap: () => unawaited(controller.retry()),
                child: Container(
                  width: LivePlayerTheme.retryWidth,
                  height: LivePlayerTheme.retryHeight,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: BiliColors.pink),
                    borderRadius: BorderRadius.circular(LivePlayerTheme.retryHeight / 2),
                  ),
                  child: _text('重试', LivePlayerTheme.retryText, color: BiliColors.pink),
                ),
              ),
            ],
          ),
        );
      case LivePlayerPhase.playing || LivePlayerPhase.paused:
        return const SizedBox.shrink();
    }
  }

  static Widget _text(String text, double size, {Color color = BiliColors.onVideo}) {
    final style = fullScreenText.merge(TextStyle(fontSize: size, color: color));
    return Text(text, style: style, strutStyle: fullScreenStrut(style), maxLines: 1);
  }
}

/// A double tap's 点赞, through the login page when logged out.
void likeRoom(BuildContext context, LiveRoomModel room) {
  if (!room.loggedIn()) {
    unawaited(AppScope.of(context).loginGate.request(context));
    return;
  }
  try {
    room.like();
  } catch (error) {
    // The model refuses a logged-out 点赞; the account may have gone between the check and the call.
    Logger.shared.info(LogCategory.ui, 'live like refused', {'error': '${error.runtimeType}'});
    if (!room.loggedIn()) unawaited(AppScope.of(context).loginGate.request(context));
  }
}

/// 207's box: the picture, a double tap's 点赞, and 弹 and the full-screen button at its bottom right; 208's note under
/// it.
class _Box extends StatefulWidget {
  const _Box({required this.controller, required this.room});

  final LivePlayerController controller;
  final LiveRoomModel room;

  @override
  State<_Box> createState() => _BoxState();
}

class _BoxState extends State<_Box> {
  final _link = LayerLink();
  final _portal = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    widget.controller.notices.addListener(_noticesChanged);
    _noticesChanged();
  }

  @override
  void didUpdateWidget(_Box oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    oldWidget.controller.notices.removeListener(_noticesChanged);
    widget.controller.notices.addListener(_noticesChanged);
  }

  @override
  void dispose() {
    widget.controller.notices.removeListener(_noticesChanged);
    super.dispose();
  }

  void _noticesChanged() {
    final any = widget.controller.notices.shown.isNotEmpty;
    if (any == _portal.isShowing) return;
    if (any) {
      _portal.show();
    } else {
      _portal.hide();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => _BoxNote(link: _link, notices: controller.notices),
        child: Stack(
          fit: StackFit.expand,
          children: [
            LivePicture(controller: controller, room: widget.room),
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('live-box-gestures'),
                behavior: HitTestBehavior.translucent,
                onDoubleTap: () => likeRoom(context, widget.room),
              ),
            ),
            Positioned(
              right: LivePlayerTheme.boxButtonRight,
              bottom: LivePlayerTheme.boxButtonBottom,
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: LivePlayerTheme.boxButtonGap,
                  children: [
                    _BoxButton(
                      key: const ValueKey('live-box-danmaku'),
                      label: controller.danmakuOn ? '关闭弹幕' : '开启弹幕',
                      asset: controller.danmakuOn ? LivePlayerAssets.danmakuOn : LivePlayerAssets.danmakuOff,
                      onTap: () => controller.setDanmakuOn(!controller.danmakuOn),
                    ),
                    _BoxButton(
                      key: const ValueKey('live-box-full-screen'),
                      label: '全屏',
                      asset: LivePlayerAssets.fullScreen,
                      onTap: () => unawaited(controller.setFullScreen(true)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoxButton extends StatelessWidget {
  const _BoxButton({super.key, required this.label, required this.asset, required this.onTap});

  final String label;
  final String asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChromeTap(
    label: label,
    square: false,
    onTap: onTap,
    child: Container(
      width: LivePlayerTheme.boxButton,
      height: LivePlayerTheme.boxButton,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: LivePlayerTheme.boxButtonFill, shape: BoxShape.circle),
      child: Image.asset(asset, width: LivePlayerTheme.boxButtonIcon, height: LivePlayerTheme.boxButtonIcon),
    ),
  );
}

/// 208's note, centred under the box: the newest one only.
class _BoxNote extends StatelessWidget {
  const _BoxNote({required this.link, required this.notices});

  final LayerLink link;
  final LivePlayerNotices notices;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: CompositedTransformFollower(
      link: link,
      showWhenUnlinked: false,
      targetAnchor: Alignment.bottomCenter,
      followerAnchor: Alignment.topCenter,
      offset: const Offset(0, LivePlayerTheme.boxToastTop),
      child: IgnorePointer(
        child: ListenableBuilder(
          listenable: notices,
          builder: (context, _) {
            final last = notices.shown.lastOrNull;
            if (last == null) return const SizedBox.shrink();
            final style = fullScreenText.merge(const TextStyle(fontSize: LivePlayerTheme.boxToastText));
            return Container(
              key: const ValueKey('live-box-note'),
              height: LivePlayerTheme.boxToastHeight,
              padding: const EdgeInsets.symmetric(horizontal: LivePlayerTheme.boxToastInset),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: LivePlayerTheme.toastFill,
                borderRadius: BorderRadius.circular(LivePlayerTheme.boxToastRadius),
              ),
              child: Text(last.text, style: style, strutStyle: fullScreenStrut(style), maxLines: 1),
            );
          },
        ),
      ),
    ),
  );
}

/// The art taken from the official APK (assets/README.md credits each).
abstract final class LivePlayerAssets {
  static const _folder = 'assets/images/live';
  static const pause = '$_folder/player_pause.png';
  static const play = '$_folder/player_play.png';
  static const refresh = '$_folder/player_refresh.png';
  static const danmakuOn = '$_folder/player_danmaku_on.png';
  static const danmakuOff = '$_folder/player_danmaku_off.png';
  static const watchMovies = '$_folder/player_watch_movies.png';
  static const fullScreen = '$_folder/player_full_screen.png';
  static const share = '$_folder/player_share.png';
  static const gift = '$_folder/player_gift.png';
  static const moreShare = '$_folder/player_more_share.png';
  static const morePip = '$_folder/player_more_pip.png';
  static const moreSettings = '$_folder/player_more_settings.png';
  static const moreDanmaku = '$_folder/player_more_danmaku.png';
  static const moreEffects = '$_folder/player_more_effects.png';
  static const moreCast = '$_folder/player_more_cast.png';
  static const moreReport = '$_folder/player_more_report.png';
  static const moreFeedback = '$_folder/player_more_feedback.png';
  static const moreAudio = '$_folder/player_more_audio.png';
  static const moreColour = '$_folder/player_more_colour.png';
  static const moreDesktop = '$_folder/player_more_desktop.png';
}
