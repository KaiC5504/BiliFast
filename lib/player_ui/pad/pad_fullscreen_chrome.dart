import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/api.dart' show Chapter;
import 'package:bili_core/logic.dart';
import 'package:flutter/widgets.dart';

import '../../shared/action_glyphs.dart';
import '../../shared/remote_image.dart';
import '../../shared/theme.dart';
import '../../shared/toast.dart';
import '../../video/actions/video_actions.dart';
import '../../video/player_session.dart';
import '../landscape_chrome.dart';
import '../panels/panel_controller.dart';
import '../player_ui.dart';
import '../portrait_controls.dart';
import '../seek_preview.dart';
import '../uploader_source.dart';

/// The iPad's full-screen controls (ipad/08, 14, 18, recording 24), in either orientation, over the whole screen with
/// iOS's own status bar above: ‹, the title with N人正在看 and the uploader's chip under it, 点赞 不喜欢 投币 收藏 充电
/// 分享 and ⋮; 截图 and the lock in tiles on the right edge; the chapter line, the times either side of the bar, and the
/// bottom row. They slide in from their edges as the controls show and stand aside while a panel is open. Holding the
/// bar keeps them up (24) and shows the preview over the TV. Hidden, a video with chapters shows 09's strip under it.
/// Upright (no screenshot) the same bars are laid out at 834 wide.
class PadFullScreenChrome extends StatelessWidget {
  const PadFullScreenChrome({super.key, required this.ui});

  final PlayerUi ui;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([ui.chrome, ui.panels, ui.session, ui.orientation, ui.details, ui.overlay, ui.danmaku]),
      builder: (context, _) {
        final shown = ui.chrome.visible && ui.panels.value == null;
        final media = MediaQuery.of(context);
        final bar = _barRect(media.size, media.padding);
        return Stack(
          fit: StackFit.expand,
          children: [
            _ChapterStrip(
              ui: ui,
              shown: !ui.chrome.visible && ui.panels.value == null && ui.overlay?.value == null,
            ),
            _controls(context, media.padding, shown),
            SeekPreview(session: ui.session, shown: shown && ui.chrome.barHeld, padBar: bar),
          ],
        );
      },
    );
  }

  /// Where the bottom block puts the [FullScreenSeekBar], in the screen's space.
  static Rect _barRect(Size screen, EdgeInsets insets) {
    final bottom =
        screen.height -
        insets.bottom -
        PadFullScreenTheme.rowBottom -
        BiliMetrics.chromeButton -
        PadFullScreenTheme.rowToBar;
    return Rect.fromLTRB(
      insets.left + PadFullScreenTheme.barInset,
      bottom - BiliMetrics.barTouchHeight,
      screen.width - insets.right - PadFullScreenTheme.barInset,
      bottom,
    );
  }

  Widget _controls(BuildContext context, EdgeInsets insets, bool shown) {
    return IgnorePointer(
      key: const ValueKey('pad-chrome'),
      ignoring: !shown,
      child: DefaultTextStyle(
        style: fullScreenText,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ChromeSlide(
              shown: shown,
              from: Offset.zero,
              child: Column(
                children: [
                  _Shade(height: insets.top + PadFullScreenTheme.topShade, solid: insets.top, fromTop: true),
                  const Spacer(),
                  _Shade(
                    height: insets.bottom + PadFullScreenTheme.bottomShadeSolid + PadFullScreenTheme.bottomShade,
                    solid: insets.bottom + PadFullScreenTheme.bottomShadeSolid,
                    fromTop: false,
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: ChromeSlide(
                shown: shown,
                from: const Offset(0, -BiliMetrics.chromeSlide),
                child: _topRow(insets),
              ),
            ),
            Positioned(
              left: insets.left + PadFullScreenTheme.titleLeft,
              top: insets.top + PadFullScreenTheme.onlineCentre - PadFullScreenTheme.onlineHeight / 2,
              height: PadFullScreenTheme.onlineHeight,
              child: ChromeSlide(
                shown: shown,
                from: const Offset(0, -BiliMetrics.chromeSlide),
                child: switch (ui.details) {
                  final details? => LandscapeOnline(
                    key: const ValueKey('pad-online'),
                    online: details.online,
                    color: PadFullScreenTheme.online,
                    iconColor: PadFullScreenTheme.onlineIcon,
                  ),
                  null => const SizedBox.shrink(),
                },
              ),
            ),
            Positioned(
              left: insets.left + PadFullScreenTheme.chipLeft,
              top: insets.top + PadFullScreenTheme.chipCentre - PadFullScreenTheme.chipHeight / 2,
              child: ChromeSlide(
                shown: shown,
                from: const Offset(0, -BiliMetrics.chromeSlide),
                child: _UploaderChip(ui: ui, touch: _touch),
              ),
            ),
            Positioned(
              right: insets.right + PadFullScreenTheme.tileRight,
              top: 0,
              bottom: 0,
              child: Center(
                child: Transform.translate(
                  offset: const Offset(0, -PadFullScreenTheme.tilesLift),
                  child: ChromeSlide(
                    shown: shown,
                    from: const Offset(BiliMetrics.chromeSlide, 0),
                    child: _tiles(context),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ChromeSlide(
                shown: shown,
                from: const Offset(0, BiliMetrics.chromeSlide),
                child: _bottomBlock(context, insets),
              ),
            ),
          ],
        ),
      ),
    );
  }

  VoidCallback _touch(VoidCallback action) => () {
    ui.chrome.show();
    action();
  };

  Widget _topRow(EdgeInsets insets) {
    final titleStyle = TextStyle(
      color: BiliColors.onVideo,
      fontSize: PadFullScreenTheme.titleText,
      fontWeight: FontWeight.w500,
    );
    return Padding(
      padding: EdgeInsets.only(
        left: insets.left + PadFullScreenTheme.backLeft,
        right: insets.right + PadFullScreenTheme.moreRight,
        top: insets.top + PadFullScreenTheme.topRowTop,
      ),
      child: SizedBox(
        height: BiliMetrics.chromeButton,
        child: Row(
          children: [
            ChromeTap(
              key: const ValueKey('pad-back'),
              label: '返回',
              onTap: ui.onBack,
              child: const BackGlyph(
                width: PadFullScreenTheme.backWidth,
                height: PadFullScreenTheme.backHeight,
                shadow: false,
              ),
            ),
            const SizedBox(
              width: PadFullScreenTheme.titleLeft - PadFullScreenTheme.backLeft - BiliMetrics.chromeButton,
            ),
            Expanded(
              child: Transform.translate(
                offset: const Offset(0, PadFullScreenTheme.titleDrop),
                child: Text(
                  ui.session.title,
                  key: const ValueKey('pad-title'),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                  strutStyle: fullScreenStrut(titleStyle),
                ),
              ),
            ),
            const SizedBox(width: PadFullScreenTheme.titleGap),
            SizedBox(
              width: PadFullScreenTheme.actionSlot * 6,
              child: _TopActions(ui: ui, touch: _touch),
            ),
            const SizedBox(width: PadFullScreenTheme.actionsToMore),
            ChromeTap(
              key: const ValueKey('pad-more'),
              label: '更多',
              onTap: _touch(() => ui.panels.open(PlayerPanel.more)),
              child: const MoreDots(shadow: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tiles(BuildContext context) {
    final locked = ui.orientation.locked;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (ui.session.canCaptureFrame) ...[
          _Tile(
            key: const ValueKey('pad-capture'),
            label: '截图',
            onTap: _touch(() => unawaited(_capture(context))),
            child: const CustomPaint(
              size: Size(PadFullScreenTheme.cameraWidth, PadFullScreenTheme.cameraHeight),
              painter: CameraPainter(),
            ),
          ),
          const SizedBox(height: PadFullScreenTheme.tileGap),
        ],
        _Tile(
          key: const ValueKey('pad-lock'),
          label: locked ? '解锁屏幕方向' : '锁定屏幕方向',
          onTap: _touch(ui.orientation.toggleLock),
          child: AnimatedSwitcher(
            duration: _motion(context),
            transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
            child: CustomPaint(
              key: ValueKey(locked),
              size: const Size(PadFullScreenTheme.lockWidth, PadFullScreenTheme.lockHeight),
              painter: LockPainter(locked: locked),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _capture(BuildContext context) async {
    final message = (await ui.session.captureFrame()).message;
    if (context.mounted) showToast(context, message);
  }

  Future<void> _pictureInPicture(BuildContext context) async {
    final message = await ui.session.startPictureInPicture();
    if (message != null && context.mounted) showToast(context, message);
  }

  Widget _bottomBlock(BuildContext context, EdgeInsets insets) {
    final session = ui.session;
    final bar = FullScreenSeekBar.repaintOf(ui);
    const timeStyle = TextStyle(
      color: BiliColors.onVideo,
      fontSize: PadFullScreenTheme.timeText,
      height: 1,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    Widget dropped(Widget time) =>
        Transform.translate(offset: const Offset(0, PadFullScreenTheme.timeDrop), child: time);
    return Padding(
      padding: EdgeInsets.only(
        left: insets.left,
        right: insets.right,
        bottom: insets.bottom + PadFullScreenTheme.rowBottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: PadFullScreenTheme.chapterBox,
            child: session.chapters.isEmpty ? null : _ChapterLine(session: session, repaint: bar),
          ),
          const SizedBox(height: PadFullScreenTheme.barToChapter),
          SizedBox(
            height: BiliMetrics.barTouchHeight,
            child: Stack(
              children: [
                Positioned(
                  left: PadFullScreenTheme.timeInset,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: ListenableBuilder(
                      listenable: bar,
                      builder: (context, _) => dropped(
                        Text(
                          TimeFormat.clock(session.position),
                          key: const ValueKey('pad-time'),
                          maxLines: 1,
                          style: timeStyle,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: PadFullScreenTheme.barInset,
                  right: PadFullScreenTheme.barInset,
                  top: 0,
                  bottom: 0,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      FullScreenSeekBar(
                        key: const ValueKey('pad-bar'),
                        ui: ui,
                        repaint: bar,
                        preview: true,
                        chapters: false,
                      ),
                      if (session.chapters.isNotEmpty)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _TickPainter(
                                chapters: session.chapters,
                                duration: () => session.duration.value,
                                repaint: session.duration,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  right: PadFullScreenTheme.timeInset,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: ValueListenableBuilder(
                      valueListenable: session.duration,
                      builder: (context, duration, _) => dropped(
                        Text(
                          TimeFormat.clock(duration),
                          key: const ValueKey('pad-duration'),
                          maxLines: 1,
                          style: timeStyle,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: PadFullScreenTheme.rowToBar),
          SizedBox(height: BiliMetrics.chromeButton, child: _bottomRow(context)),
        ],
      ),
    );
  }

  Widget _bottomRow(BuildContext context) {
    final session = ui.session;
    final previous = previousEpisode(session);
    final danmaku = ui.danmaku;
    return Row(
      children: [
        const SizedBox(width: PadFullScreenTheme.prevLeft),
        _GlyphButton(
          key: const ValueKey('pad-prev'),
          label: '上一个',
          onTap: previous == null ? null : _touch(() => session.playEpisode(previous)),
          keepUp: ui.chrome.show,
          child: const CustomPaint(
            size: Size(PadFullScreenTheme.prevWidth, PadFullScreenTheme.prevHeight),
            painter: _PreviousPainter(),
          ),
        ),
        const SizedBox(width: PadFullScreenTheme.prevToPlay),
        PlayPauseButton(
          key: const ValueKey('pad-play'),
          session: session,
          onTap: _touch(session.togglePlay),
          glyphSize: const Size(PadFullScreenTheme.playWidth, PadFullScreenTheme.playHeight),
          glyphShift: PadFullScreenTheme.playShift,
          cornerRadius: PadFullScreenTheme.playCorner,
          pauseBar: PadFullScreenTheme.pauseBar,
          pauseGap: PadFullScreenTheme.pauseGap,
          pauseHeight: BiliMetrics.chromePauseShare,
        ),
        const SizedBox(width: PadFullScreenTheme.playToDanmaku),
        ChromeTap(
          key: const ValueKey('pad-danmaku'),
          label: session.danmakuOn ? '关闭弹幕' : '开启弹幕',
          onTap: _touch(() => session.setDanmakuOn(!session.danmakuOn)),
          child: _Fitted(child: DanmakuGlyph(on: session.danmakuOn)),
        ),
        // As on the phone (34), danmaku off closes the row up behind the toggle.
        if (danmaku != null && session.danmakuOn) ...[
          const SizedBox(width: PadFullScreenTheme.danmakuToSettings),
          ChromeTap(
            key: const ValueKey('pad-danmaku-settings'),
            label: '弹幕设置',
            onTap: _touch(() => ui.panels.open(PlayerPanel.danmakuSettings)),
            child: const _Fitted(child: DanmakuSettingsGlyph()),
          ),
          const SizedBox(width: PadFullScreenTheme.settingsToField),
          Expanded(
            child: _DanmakuField(
              closed: danmaku.closed,
              onTap: danmaku.closed ? ui.chrome.show : _touch(danmaku.openSend),
            ),
          ),
        ] else
          const Spacer(),
        const SizedBox(width: PadFullScreenTheme.fieldToSpeed),
        if (session.episodes.isNotEmpty) ...[
          _TextButton(
            key: const ValueKey('pad-episodes'),
            label: '选集',
            text: '选集',
            onTap: _touch(() => ui.panels.open(PlayerPanel.episodes)),
          ),
          const SizedBox(width: PadFullScreenTheme.speedToQuality),
        ],
        _TextButton(
          key: const ValueKey('pad-speed'),
          label: '倍速',
          text: speedLabel(session.rate),
          onTap: _touch(() => ui.panels.open(PlayerPanel.speed)),
        ),
        const SizedBox(width: PadFullScreenTheme.speedToQuality),
        _TextButton(
          key: const ValueKey('pad-quality'),
          label: '清晰度',
          text: QualityNames.short(qn: session.playingQuality, serverText: session.qualityName(session.playingQuality)),
          tag: QualityNames.tag(session.playingQuality),
          onTap: _touch(() => ui.panels.open(PlayerPanel.quality)),
        ),
        const SizedBox(width: PadFullScreenTheme.qualityToPip),
        _GlyphButton(
          key: const ValueKey('pad-pip'),
          label: '小窗播放',
          onTap: session.pictureInPictureSupported ? _touch(() => unawaited(_pictureInPicture(context))) : null,
          keepUp: ui.chrome.show,
          offInk: false,
          child: const CustomPaint(size: Size.square(PadFullScreenTheme.pipBox), painter: _PipPainter()),
        ),
        const SizedBox(width: PadFullScreenTheme.pipToExit),
        ChromeTap(
          key: const ValueKey('pad-exit'),
          label: '退出全屏',
          onTap: ui.onBack,
          child: const CustomPaint(size: Size.square(PadFullScreenTheme.exitBox), painter: _ExitPainter()),
        ),
        const SizedBox(width: PadFullScreenTheme.exitRight),
      ],
    );
  }
}

/// The part or 合集 episode before the one playing, for ⏮; null at the first or without any.
Episode? previousEpisode(PlayerSession session) {
  final episodes = session.episodes;
  final index = episodes.indexWhere((episode) => episode.current);
  return index > 0 ? episodes[index - 1] : null;
}

typedef _Touch = VoidCallback Function(VoidCallback action);

Duration _motion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 220);

/// Black at the safe area's edge, clearing to nothing over [height].
class _Shade extends StatelessWidget {
  const _Shade({required this.height, required this.solid, required this.fromTop});

  final double height;
  final double solid;
  final bool fromTop;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: fromTop ? Alignment.topCenter : Alignment.bottomCenter,
            end: fromTop ? Alignment.bottomCenter : Alignment.topCenter,
            colors: const [BiliColors.videoBackground, BiliColors.videoBackground, BiliColors.chromeShadeClear],
            stops: [0, height > 0 ? solid / height : 0, 1],
          ),
        ),
      ),
    ),
  );
}

/// The phone's 弹 TVs at the iPad's size.
class _Fitted extends StatelessWidget {
  const _Fitted({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: PadFullScreenTheme.danmakuWidth,
    height: PadFullScreenTheme.danmakuHeight,
    child: FittedBox(fit: BoxFit.fill, child: child),
  );
}

/// A glyph button that may have nothing to do: then it stays, half white unless [offInk] is off and it only fades,
/// and a tap on it only keeps the controls up.
class _GlyphButton extends StatelessWidget {
  const _GlyphButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.keepUp,
    required this.child,
    this.offInk = true,
  });

  final String label;
  final VoidCallback? onTap;
  final VoidCallback keepUp;
  final Widget child;
  final bool offInk;

  @override
  Widget build(BuildContext context) {
    final onTap = this.onTap;
    if (onTap != null) return ChromeTap(label: label, onTap: onTap, child: child);
    return Semantics(
      button: true,
      enabled: false,
      label: label,
      excludeSemantics: true,
      onTap: keepUp,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: keepUp,
        child: SizedBox.square(
          dimension: BiliMetrics.chromeButton,
          child: Center(
            child: offInk
                ? ColorFiltered(
                    colorFilter: const ColorFilter.mode(PadFullScreenTheme.prevOff, BlendMode.srcIn),
                    child: child,
                  )
                : Opacity(opacity: PadFullScreenTheme.offOpacity, child: child),
          ),
        ),
      ),
    );
  }
}

/// 08's dark field, opening the send bar; with the uploader's danmaku closed it reads UP主已关闭弹幕 and opens nothing.
class _DanmakuField extends StatelessWidget {
  const _DanmakuField({required this.closed, required this.onTap});

  final bool closed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = closed ? 'UP主已关闭弹幕' : '发个友善的弹幕见证当下';
    const style = TextStyle(color: PadFullScreenTheme.fieldInk, fontSize: PadFullScreenTheme.fieldText, height: 1);
    return Semantics(
      key: const ValueKey('pad-danmaku-field'),
      button: !closed,
      label: text,
      onTap: closed ? null : onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: BiliMetrics.chromeButton,
          child: Center(
            child: Container(
              height: PadFullScreenTheme.fieldHeight,
              padding: const EdgeInsets.only(left: PadFullScreenTheme.fieldInset),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: PadFullScreenTheme.fieldFill,
                borderRadius: BorderRadius.circular(PadFullScreenTheme.fieldRadius),
              ),
              child: Text(
                text,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: style,
                strutStyle: fullScreenStrut(style),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 15 pt label on the bottom row, as tall as the glyph buttons; [tag] sits over its top right (1080P's 高码率).
class _TextButton extends StatelessWidget {
  const _TextButton({super.key, required this.label, required this.text, required this.onTap, this.tag});

  final String label;
  final String text;
  final VoidCallback onTap;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final tag = this.tag;
    final button = SizedBox(
      height: BiliMetrics.chromeButton,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PadFullScreenTheme.textPad),
        child: Center(
          widthFactor: 1,
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(color: BiliColors.onVideo, fontSize: PadFullScreenTheme.labelText),
          ),
        ),
      ),
    );
    return ChromeTap(
      label: label,
      square: false,
      onTap: onTap,
      child: tag == null
          ? button
          : Stack(
              clipBehavior: Clip.none,
              children: [
                button,
                Positioned(
                  top: BiliMetrics.chromeButton / 2 - PadFullScreenTheme.tagRise - BiliMetrics.chromeTagHeight / 2,
                  right: PadFullScreenTheme.textPad - PadFullScreenTheme.tagOverhang,
                  child: QualityTag(tag, key: const ValueKey('pad-quality-tag')),
                ),
              ],
            ),
    );
  }
}

/// 截图 and the lock: a translucent tile, the whole of it the target.
class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.label, required this.onTap, required this.child});

  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => ChromeTap(
    label: label,
    square: false,
    onTap: onTap,
    child: Container(
      width: PadFullScreenTheme.tile,
      height: PadFullScreenTheme.tile,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: PadFullScreenTheme.tileFill,
        borderRadius: BorderRadius.circular(PadFullScreenTheme.tileRadius),
      ),
      child: child,
    ),
  );
}

/// 点赞 不喜欢 投币 收藏 充电 分享 in their 70 pt slots; nothing until the video's actions arrive.
class _TopActions extends StatelessWidget {
  const _TopActions({required this.ui, required this.touch});

  final PlayerUi ui;
  final _Touch touch;

  @override
  Widget build(BuildContext context) {
    final actions = ui.details?.actions;
    return AnimatedSwitcher(
      duration: _motion(context),
      layoutBuilder: (current, previous) => Stack(alignment: Alignment.centerRight, children: [...previous, ?current]),
      child: actions == null
          ? const SizedBox.shrink()
          : ListenableBuilder(
              key: ObjectKey(actions),
              listenable: actions,
              builder: (context, _) => Row(
                children: [
                  _TopAction(
                    key: const ValueKey('pad-like'),
                    label: actions.liked ? '取消点赞' : '点赞',
                    glyph: ActionGlyph.like,
                    active: actions.liked,
                    count: actions.likeCount,
                    onTap: touch(() => unawaited(actions.toggleLike())),
                  ),
                  _TopAction(
                    key: const ValueKey('pad-dislike'),
                    label: actions.disliked ? '取消不喜欢' : '不喜欢',
                    glyph: ActionGlyph.dislike,
                    active: actions.disliked,
                    lift: PadFullScreenTheme.dislikeLift,
                    onTap: touch(() => unawaited(actions.toggleDislike())),
                  ),
                  _TopAction(
                    key: const ValueKey('pad-coin'),
                    label: actions.coins > 0 ? '已投币' : '投币',
                    glyph: ActionGlyph.coin,
                    active: actions.coins > 0,
                    onTap: touch(() => actions.ask(ActionPrompt.coin)),
                  ),
                  _TopAction(
                    key: const ValueKey('pad-favourite'),
                    label: actions.favorited ? '已收藏' : '收藏',
                    glyph: ActionGlyph.favourite,
                    active: actions.favorited,
                    onTap: touch(() => actions.ask(ActionPrompt.favourites)),
                  ),
                  _TopAction(
                    key: const ValueKey('pad-charge'),
                    label: '充电',
                    glyph: ActionGlyph.charge,
                    onTap: touch(() => showToast(context, '暂不支持充电')),
                  ),
                  _TopAction(
                    key: const ValueKey('pad-share'),
                    label: '分享',
                    glyph: ActionGlyph.share,
                    onTap: touch(() => actions.ask(ActionPrompt.share)),
                  ),
                ],
              ),
            ),
    );
  }
}

/// A 44 pt action centred in its slot, with its count, when it has one, as a superscript at its top right (08).
class _TopAction extends StatelessWidget {
  const _TopAction({
    super.key,
    required this.label,
    required this.glyph,
    required this.onTap,
    this.active = false,
    this.count,
    this.lift = 0,
  });

  final String label;
  final ActionGlyph glyph;
  final VoidCallback onTap;
  final bool active;
  final int? count;
  final double lift;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: PadFullScreenTheme.actionSlot,
    child: Center(
      child: ChromeTap(
        label: label,
        square: false,
        onTap: onTap,
        child: SizedBox.square(
          dimension: BiliMetrics.chromeButton,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Transform.translate(
                  offset: Offset(0, -lift),
                  child: ActionPop(
                    glyph,
                    active: active,
                    size: PadFullScreenTheme.actionIcon,
                    stroke: PadFullScreenTheme.actionStroke,
                  ),
                ),
              ),
              if (count case final count? when count > 0)
                Positioned(
                  left: BiliMetrics.chromeButton / 2 + PadFullScreenTheme.countLead,
                  top: 0,
                  child: Baseline(
                    baseline: PadFullScreenTheme.countBaseline,
                    baselineType: TextBaseline.alphabetic,
                    child: Text(
                      CountFormat.short(count),
                      maxLines: 1,
                      softWrap: false,
                      textScaler: TextScaler.noScaling,
                      style: const TextStyle(
                        color: BiliColors.onVideo,
                        fontSize: PadFullScreenTheme.countText,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The avatar and + 关注 in their capsule (18, 24); 已关注 is grey in the same place. Nothing until the face arrives.
class _UploaderChip extends StatelessWidget {
  const _UploaderChip({required this.ui, required this.touch});

  final PlayerUi ui;
  final _Touch touch;

  @override
  Widget build(BuildContext context) {
    final owner = uploaderOf(ui.session.detail?.owner, ui.details?.uploader, ui.session.video?.owner);
    final face = owner?.face;
    if (face == null) return const SizedBox(height: PadFullScreenTheme.chipHeight);
    final actions = ui.details?.actions;
    return Container(
      key: const ValueKey('pad-uploader'),
      height: PadFullScreenTheme.chipHeight,
      decoration: BoxDecoration(
        color: PadFullScreenTheme.chipFill,
        borderRadius: BorderRadius.circular(PadFullScreenTheme.chipHeight / 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: PadFullScreenTheme.chipInset),
          ClipOval(
            key: const ValueKey('pad-avatar'),
            child: SizedBox.square(
              dimension: PadFullScreenTheme.avatar,
              child: RemoteImage.avatar(face, size: const Size.square(PadFullScreenTheme.avatar)),
            ),
          ),
          if (actions != null)
            _Follow(actions: actions, touch: touch)
          else
            const SizedBox(width: PadFullScreenTheme.followTrailing),
        ],
      ),
    );
  }
}

class _Follow extends StatelessWidget {
  const _Follow({required this.actions, required this.touch});

  final VideoActions actions;
  final _Touch touch;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: actions,
    builder: (context, _) {
      final following = actions.following;
      final style = TextStyle(
        color: following ? LandscapeActionTheme.followed : BiliColors.onVideo,
        fontSize: PadFullScreenTheme.followText,
        height: 1,
      );
      return ChromeTap(
        key: const ValueKey('pad-follow'),
        label: following ? '已关注' : '关注',
        square: false,
        onTap: touch(actions.tapFollow),
        child: SizedBox(
          height: PadFullScreenTheme.chipHeight,
          child: Padding(
            padding: const EdgeInsets.only(
              left: PadFullScreenTheme.plusLead,
              right: PadFullScreenTheme.followTrailing,
            ),
            child: AnimatedSwitcher(
              duration: _motion(context),
              layoutBuilder: (current, previous) =>
                  Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
              child: Row(
                key: ValueKey(following),
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!following) ...[
                    const CustomPaint(
                      size: Size.square(PadFullScreenTheme.plus),
                      painter: FollowPlusPainter(color: BiliColors.onVideo, stroke: PadFullScreenTheme.plusStroke),
                    ),
                    const SizedBox(width: PadFullScreenTheme.plusGap),
                  ],
                  Transform.translate(
                    offset: const Offset(0, PadFullScreenTheme.followDrop),
                    child: Text(
                      following ? '已关注' : '关注',
                      maxLines: 1,
                      softWrap: false,
                      style: style,
                      strutStyle: fullScreenStrut(style),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// 章节 · the chapter playing ›, above the bar's left end (08).
class _ChapterLine extends StatelessWidget {
  const _ChapterLine({required this.session, required this.repaint});

  final PlayerSession session;
  final Listenable repaint;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: BiliColors.onVideo, fontSize: PadFullScreenTheme.chapterText, height: 1);
    return Padding(
      padding: const EdgeInsets.only(left: PadFullScreenTheme.chapterLeft),
      child: ListenableBuilder(
        listenable: repaint,
        builder: (context, _) {
          final title = chapterAt(session.chapters, session.position);
          if (title == null) return const SizedBox.shrink();
          final line = Row(
            key: const ValueKey('pad-chapter'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  '章节 · $title',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                  strutStyle: fullScreenStrut(style),
                ),
              ),
              const SizedBox(width: PadFullScreenTheme.chapterChevronGap),
              const CustomPaint(
                size: Size(PadFullScreenTheme.chapterChevronWidth, PadFullScreenTheme.chapterChevronHeight),
                painter: _ChevronPainter(),
              ),
            ],
          );
          return Transform.translate(offset: const Offset(0, PadFullScreenTheme.chapterDrop), child: line);
        },
      ),
    );
  }
}

/// The title of the chapter holding [position], when it has one.
String? chapterAt(List<Chapter> chapters, double position) {
  final title = chapters.where((chapter) => chapter.from <= position).lastOrNull?.title;
  return title == null || title.isEmpty ? null : title;
}

/// 09's strip under the video while the controls are hidden, for a video with chapters: the played part, then each
/// chapter's title centred in its stretch with a rule where it begins. It takes no touches.
class _ChapterStrip extends StatelessWidget {
  const _ChapterStrip({required this.ui, required this.shown});

  final PlayerUi ui;
  final bool shown;

  @override
  Widget build(BuildContext context) {
    final session = ui.session;
    if (session.chapters.isEmpty) return const SizedBox.shrink();
    final media = MediaQuery.of(context);
    final screen = media.size;
    final shape = session.videoShape;
    final aspect = shape == null || shape.width <= 0 || shape.height <= 0
        ? BiliMetrics.videoAspect
        : shape.width / shape.height;
    final video = math.min(screen.height, screen.width / aspect);
    final top = math.min(
      (screen.height + video) / 2,
      screen.height - media.padding.bottom - PadFullScreenTheme.stripHeight,
    );
    return IgnorePointer(
      child: ExcludeSemantics(
        child: AnimatedOpacity(
          opacity: shown ? 1 : 0,
          duration: _motion(context),
          child: Stack(
            children: [
              Positioned(
                key: const ValueKey('pad-strip'),
                left: 0,
                right: 0,
                top: top,
                height: PadFullScreenTheme.stripHeight,
                child: ListenableBuilder(
                  listenable: FullScreenSeekBar.repaintOf(ui),
                  builder: (context, _) => _stripBody(session),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stripBody(PlayerSession session) {
    final duration = session.duration.value;
    double share(double seconds) => duration > 0 ? (seconds / duration).clamp(0.0, 1.0) : 0.0;
    const style = TextStyle(
      fontSize: PadFullScreenTheme.stripText,
      color: PadFullScreenTheme.stripInk,
      height: 1,
      decoration: TextDecoration.none,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final chapters = session.chapters;
        return Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: width * share(session.position),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [PadFullScreenTheme.stripPlayed, BiliColors.chromeShadeClear],
                  ),
                ),
              ),
            ),
            for (final (index, chapter) in chapters.indexed) ...[
              if (chapter.from > 0)
                Positioned(
                  left: width * share(chapter.from) - PadFullScreenTheme.stripRule / 2,
                  top: 0,
                  bottom: 0,
                  width: PadFullScreenTheme.stripRule,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          BiliColors.chromeShadeClear,
                          PadFullScreenTheme.stripRuleInk,
                          BiliColors.chromeShadeClear,
                        ],
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: width * share(chapter.from),
                width: math.max(
                  width * (share(index + 1 < chapters.length ? chapters[index + 1].from : duration) -
                          share(chapter.from)),
                  0,
                ),
                top: 0,
                bottom: 0,
                child: Center(
                  child: Text(
                    chapter.title,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: fullScreenText.merge(style),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// A dark tick where each chapter starts, at the bar's own places (the bar's own ticks are off on the iPad, with its
/// title over the thumb).
class _TickPainter extends CustomPainter {
  _TickPainter({required this.chapters, required this.duration, required Listenable repaint}) : super(repaint: repaint);

  final List<Chapter> chapters;
  final double Function() duration;

  @override
  void paint(Canvas canvas, Size size) {
    final duration = this.duration();
    if (duration <= 0) return;
    const thumb = BiliMetrics.thumbWidth;
    const bar = BiliMetrics.barHeight;
    final travel = math.max(size.width - thumb, 1.0);
    final paint = Paint()..color = BiliColors.chromeTick;
    for (final chapter in chapters) {
      if (chapter.from <= 0 || chapter.from >= duration) continue;
      final x = travel * chapter.from / duration + thumb / 2;
      canvas.drawRect(Rect.fromLTWH(x - bar / 2, (size.height - bar) / 2, bar, bar), paint);
    }
  }

  @override
  bool shouldRepaint(_TickPainter oldDelegate) =>
      oldDelegate.chapters != chapters || oldDelegate.duration != duration;
}

Paint _stroke(double width) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..color = BiliColors.onVideo;

/// The chapter line's ›.
class _ChevronPainter extends CustomPainter {
  const _ChevronPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const inset = PadFullScreenTheme.chapterChevronStroke / 2;
    canvas.drawPath(
      Path()
        ..moveTo(inset, inset)
        ..lineTo(size.width - inset, size.height / 2)
        ..lineTo(inset, size.height - inset),
      _stroke(PadFullScreenTheme.chapterChevronStroke),
    );
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) => false;
}

/// The APK's `bili_player_ctrl_play_previous`: a bar with round ends and a rounded triangle pointing left, its ink
/// (3.5-20.5 on a 24 grid) stretched to the box.
class _PreviousPainter extends CustomPainter {
  const _PreviousPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 17, sy = size.height / 17;
    Offset p(double x, double y) => Offset((x - 3.5) * sx, (y - 3.5) * sy);
    void cubic(Path path, double x1, double y1, double x2, double y2, double x3, double y3) {
      final a = p(x1, y1), b = p(x2, y2), c = p(x3, y3);
      path.cubicTo(a.dx, a.dy, b.dx, b.dy, c.dx, c.dy);
    }

    void line(Path path, double x, double y) {
      final to = p(x, y);
      path.lineTo(to.dx, to.dy);
    }

    final start = p(7.5, 18.5);
    final path = Path()..moveTo(start.dx, start.dy);
    cubic(path, 7.5, 19.605, 6.605, 20.5, 5.5, 20.5);
    cubic(path, 4.395, 20.5, 3.5, 19.605, 3.5, 18.5);
    line(path, 3.5, 5.5);
    cubic(path, 3.5, 4.395, 4.395, 3.5, 5.5, 3.5);
    cubic(path, 6.605, 3.5, 7.5, 4.395, 7.5, 5.5);
    line(path, 7.5, 9.979);
    line(path, 17.5, 4.206);
    cubic(path, 18.833, 3.436, 20.5, 4.398, 20.5, 5.938);
    line(path, 20.5, 18.062);
    cubic(path, 20.5, 19.602, 18.833, 20.564, 17.5, 19.794);
    line(path, 7.5, 14.021);
    path.close();
    canvas.drawPath(path, Paint()..color = BiliColors.onVideo);
  }

  @override
  bool shouldRepaint(_PreviousPainter oldDelegate) => false;
}

/// The APK's `biliplayer_ic_topbar_floatwindow` on its 22 grid: the screen open at its bottom right, an arrow into the
/// corner and the small window there, solid.
class _PipPainter extends CustomPainter {
  const _PipPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 22;
    Offset p(double x, double y) => Offset(x * s, y * s);
    final screen = Path()
      ..moveTo(p(9.596, 18).dx, p(9.596, 18).dy)
      ..lineTo(p(4.5245, 18).dx, p(4.5245, 18).dy)
      ..arcToPoint(p(1.5245, 15), radius: Radius.circular(3 * s))
      ..lineTo(p(1.5245, 6.551).dx, p(1.5245, 6.551).dy)
      ..arcToPoint(p(4.5245, 3.551), radius: Radius.circular(3 * s))
      ..lineTo(p(17, 3.551).dx, p(17, 3.551).dy)
      ..arcToPoint(p(20, 6.551), radius: Radius.circular(3 * s))
      ..lineTo(p(20, 11.5666).dx, p(20, 11.5666).dy)
      ..moveTo(p(5.5065, 7.5085).dx, p(5.5065, 7.5085).dy)
      ..lineTo(p(9.9328, 11.9511).dx, p(9.9328, 11.9511).dy)
      ..moveTo(p(10.5215, 7.5085).dx, p(10.5215, 7.5085).dy)
      ..lineTo(p(10.5215, 12.515).dx, p(10.5215, 12.515).dy)
      ..lineTo(p(5.5065, 12.515).dx, p(5.5065, 12.515).dy);
    canvas
      ..drawPath(screen, _stroke(s))
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromPoints(p(12, 14), p(22, 20)), Radius.circular(2 * s)), Paint()
        ..color = BiliColors.onVideo);
  }

  @override
  bool shouldRepaint(_PipPainter oldDelegate) => false;
}

/// 08's 退出全屏: a bracket at the top left with its elbow pointing in, and one at the bottom right.
class _ExitPainter extends CustomPainter {
  const _ExitPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const e = PadFullScreenTheme.exitElbow;
    final w = size.width, h = size.height;
    canvas.drawPath(
      Path()
        ..moveTo(0, e)
        ..lineTo(e, e)
        ..lineTo(e, 0)
        ..moveTo(w - e, h)
        ..lineTo(w - e, h - e)
        ..lineTo(w, h - e),
      _stroke(PadFullScreenTheme.glyphStroke),
    );
  }

  @override
  bool shouldRepaint(_ExitPainter oldDelegate) => false;
}
