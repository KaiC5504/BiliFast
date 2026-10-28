import 'dart:async';

import 'package:bili_core/api.dart' show VideoCard;
import 'package:bili_core/logic.dart' show CountFormat, TimeFormat;
import 'package:flutter/widgets.dart';

import '../../shared/action_glyphs.dart';
import '../../shared/remote_image.dart';
import '../../shared/theme.dart';
import '../../video/player_session.dart';
import '../end_screen_portrait.dart';
import '../panels/panel_controller.dart';
import '../player_ui.dart';
import '../portrait_controls.dart';
import 'pad_inline_controls.dart' show PadChapterStrip;

/// The end screen over the iPad page's player (ipad/17): the last frame dimmed over the chapters, back and ⋮, then
/// 推荐视频 with the first related video's cover, title, uploader and counts on the left and 重播 and 分享 on the
/// right. The block keeps 17's place about the player's middle; its parts rise in one after another as the phone's.
class PadEndInline extends StatefulWidget {
  const PadEndInline({super.key, required this.ui, this.share = shareThroughSystem});

  final PlayerUi ui;

  /// Tests pass their own so nothing reaches the platform.
  final ShareLink share;

  @override
  State<PadEndInline> createState() => _PadEndInlineState();
}

class _PadEndInlineState extends State<PadEndInline> with SingleTickerProviderStateMixin {
  late final _entrance = AnimationController(vsync: this, duration: const Duration(milliseconds: 650))..forward();

  static const _button = BiliMetrics.chromeButton;
  static const _actionStyle = TextStyle(
    color: BiliColors.onVideo,
    fontSize: PadInlineControlsTheme.endActionFont,
    height: 1,
  );

  PlayerUi get _ui => widget.ui;
  PlayerSession get _session => widget.ui.session;

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  Animation<double> _stage(double from, double to) =>
      CurvedAnimation(parent: _entrance, curve: Interval(from, to, curve: Curves.easeOutCubic));

  VoidCallback _tap(VoidCallback action) => () {
    _ui.chrome.show();
    action();
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        final card = _session.related.firstOrNull;
        final chapters = _session.chapters;
        return LayoutBuilder(
          builder: (context, constraints) {
            final middle = constraints.maxHeight / 2;
            return Stack(
              fit: StackFit.expand,
              children: [
                if (chapters.isNotEmpty) PadChapterStrip(chapters: chapters, duration: _session.duration),
                FadeTransition(opacity: _stage(0, 0.45), child: const ColoredBox(color: BiliColors.endDim)),
                Positioned(
                  left: 0,
                  right: 0,
                  top: PadInlineControlsTheme.endTopCentre - _button / 2,
                  height: _button,
                  child: EndRise(animation: _stage(0.1, 0.6), child: _topRow()),
                ),
                if (card != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: middle + PadInlineControlsTheme.endCaptionCentre - _button / 2,
                    bottom: 0,
                    child: EndRise(
                      animation: _stage(0.2, 0.8),
                      child: _Recommended(card: card, onPlay: _tap(() => _session.playRelated(card))),
                    ),
                  ),
                Positioned(
                  right: PadInlineControlsTheme.endActionsRight,
                  top: middle + PadInlineControlsTheme.endActionsCentre - _button / 2,
                  height: _button,
                  child: EndRise(animation: _stage(0.35, 1), child: _actions()),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _topRow() {
    const edge = PadInlineControlsTheme.endEdgeCentre - _button / 2;
    return Stack(
      children: [
        Positioned(
          left: edge,
          width: _button,
          height: _button,
          child: ChromeTap(
            key: const ValueKey('end-back'),
            label: '返回',
            onTap: _tap(_ui.onBack),
            child: const BackGlyph(
              width: PadInlineControlsTheme.endBackWidth,
              height: PadInlineControlsTheme.backHeight,
              shadow: false,
            ),
          ),
        ),
        Positioned(
          right: edge,
          width: _button,
          height: _button,
          child: ChromeTap(
            key: const ValueKey('end-more'),
            label: '更多',
            onTap: _tap(() => _ui.panels.open(PlayerPanel.more)),
            child: const MoreDots(
              dot: PadInlineControlsTheme.moreDot,
              gap: PadInlineControlsTheme.moreDotGap,
              shadow: false,
            ),
          ),
        ),
      ],
    );
  }

  Widget _actions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _action(
          key: const ValueKey('end-replay'),
          title: '重播',
          gap: PadInlineControlsTheme.endReplayGap,
          glyph: Image.asset(
            'assets/images/player/pad_end_replay.png',
            width: PadInlineControlsTheme.endReplayWidth,
            height: PadInlineControlsTheme.endReplayHeight,
            color: BiliColors.onVideo,
            filterQuality: FilterQuality.medium,
          ),
          onTap: _tap(() => unawaited(_session.replay())),
        ),
        if (_session.shareLink != null) ...[
          const SizedBox(width: PadInlineControlsTheme.endActionSpacing),
          _action(
            key: const ValueKey('end-share'),
            title: '分享',
            gap: PadInlineControlsTheme.endShareGap,
            glyph: const ActionIcon(
              ActionGlyph.share,
              solid: true,
              size: PadInlineControlsTheme.endShareInk / ActionIcon.inkShare,
              color: BiliColors.onVideo,
            ),
            onTap: _tap(() => unawaited(shareFromEndScreen(context, _ui, widget.share))),
          ),
        ],
      ],
    );
  }

  Widget _action({
    required Key key,
    required String title,
    required double gap,
    required Widget glyph,
    required VoidCallback onTap,
  }) => ChromeTap(
    key: key,
    label: title,
    square: false,
    onTap: onTap,
    child: SizedBox(
      height: _button,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: gap,
        children: [
          glyph,
          Text(title, style: _actionStyle, strutStyle: BiliFonts.strutOf(context, _actionStyle)),
        ],
      ),
    ),
  );
}

/// 推荐视频 over the cover, with the title, the uploader and the counts beside it. Its top is a 44 pt line centred
/// on the caption.
class _Recommended extends StatelessWidget {
  const _Recommended({required this.card, required this.onPlay});

  final VideoCard card;
  final VoidCallback onPlay;

  static const _caption = TextStyle(
    color: BiliColors.endCaption,
    fontSize: PadInlineControlsTheme.endCaptionFont,
    height: 1,
  );
  static const _title = TextStyle(color: BiliColors.onVideo, fontSize: PadInlineControlsTheme.endTitleFont, height: 1);
  static const _meta = TextStyle(color: BiliColors.endMeta, fontSize: PadInlineControlsTheme.endMetaFont, height: 1);
  static const _count = TextStyle(
    color: BiliColors.endMeta,
    fontSize: PadInlineControlsTheme.endCountFont,
    fontFeatures: [FontFeature.tabularFigures()],
    height: 1,
  );

  /// The caption's line centre is the block's origin.
  static const _origin = BiliMetrics.chromeButton / 2 - PadInlineControlsTheme.endCaptionCentre;

  static double _y(double fromMiddle) => _origin + fromMiddle;

  @override
  Widget build(BuildContext context) {
    const coverTop = PadInlineControlsTheme.endCoverTop;
    const infoLeft =
        PadInlineControlsTheme.endCoverLeft + PadInlineControlsTheme.endCoverWidth + PadInlineControlsTheme.endInfoGap;
    Widget line(double centre, Widget child) => Positioned(
      left: infoLeft,
      right: PadInlineControlsTheme.endInfoRight,
      top: _y(centre) - PadInlineControlsTheme.endMetaRow / 2,
      height: PadInlineControlsTheme.endMetaRow,
      child: child,
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: PadInlineControlsTheme.endCaptionLeft,
          top: 0,
          height: BiliMetrics.chromeButton,
          child: Center(
            widthFactor: 1,
            child: Text('推荐视频', style: _caption, strutStyle: BiliFonts.strutOf(context, _caption)),
          ),
        ),
        Positioned(
          left: PadInlineControlsTheme.endCoverLeft,
          top: _y(coverTop),
          width: PadInlineControlsTheme.endCoverWidth,
          height: PadInlineControlsTheme.endCoverHeight,
          child: ChromeTap(
            key: const ValueKey('end-cover'),
            label: '播放：${card.title}',
            square: false,
            onTap: onPlay,
            child: _Cover(card: card),
          ),
        ),
        Positioned(
          left: infoLeft,
          right: PadInlineControlsTheme.endInfoRight,
          top: _y(PadInlineControlsTheme.endTitleCentre) - PadInlineControlsTheme.endTitleFont,
          height: PadInlineControlsTheme.endTitleFont * 2,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              card.title,
              key: const ValueKey('end-title'),
              style: _title,
              strutStyle: BiliFonts.strutOf(context, _title),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        line(
          PadInlineControlsTheme.endUploaderCentre,
          Row(
            spacing: PadInlineControlsTheme.endMetaGap,
            children: [
              const EndUpBadge(),
              Flexible(
                child: Text(
                  card.ownerName,
                  style: _meta,
                  strutStyle: BiliFonts.strutOf(context, _meta),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        line(
          PadInlineControlsTheme.endCountsCentre,
          Row(
            children: [
              const EndCountIcon(CountGlyph.views),
              const SizedBox(width: PadInlineControlsTheme.endMetaGap),
              Text(CountFormat.short(card.views), style: _count, strutStyle: BiliFonts.strutOf(context, _count)),
              const SizedBox(width: PadInlineControlsTheme.endMetaSpacing),
              const EndCountIcon(CountGlyph.danmaku),
              const SizedBox(width: PadInlineControlsTheme.endMetaGap),
              Text(CountFormat.short(card.danmaku), style: _count, strutStyle: BiliFonts.strutOf(context, _count)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.card});

  final VideoCard card;

  static const _time = TextStyle(
    color: BiliColors.onVideo,
    fontSize: PadInlineControlsTheme.endCoverTimeFont,
    fontFeatures: [FontFeature.tabularFigures()],
    height: 1,
  );

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(PadInlineControlsTheme.endCoverRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          RemoteImage(
            card.cover,
            size: const Size(PadInlineControlsTheme.endCoverWidth, PadInlineControlsTheme.endCoverHeight),
            cover: true,
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: PadInlineControlsTheme.endCoverShadeHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [BiliColors.chromeShadeClear, BiliColors.endCoverShade],
                ),
              ),
            ),
          ),
          // 17 writes 04:15 where the phone's cover writes 4:15.
          Positioned(
            right: PadInlineControlsTheme.endCoverTextInset,
            bottom: PadInlineControlsTheme.endCoverTextInset,
            child: Text(TimeFormat.clock(card.duration.toDouble()), style: _time),
          ),
          Center(
            child: CustomPaint(
              size: const Size(PadInlineControlsTheme.endPlayWidth, PadInlineControlsTheme.endPlayHeight),
              painter: PlayPausePainter(const AlwaysStoppedAnimation(0), color: BiliColors.endPlayGlyph),
            ),
          ),
        ],
      ),
    );
  }
}
