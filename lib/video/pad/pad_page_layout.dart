/// The iPad's video page frame (ipad/03, 05, 06, 20, 23): the player and the body in the left column with the related
/// videos on the right while the screen is wide, one column with 简介 / 评论 while it is upright. `video_page.dart`
/// chooses these pieces when [FormFactor.of] is the iPad and places them in its Stack.
library;

import 'dart:math' as math;

import 'package:bili_core/api.dart' show VideoCard, VideoDetail;
import 'package:flutter/widgets.dart';

import '../../app/form_factor.dart';
import '../../player_ui/portrait_controls.dart' show BackGlyph, ChromeTap, MoreDots;
import '../../shared/remote_image.dart';
import '../../shared/theme.dart';
import '../collapsing_player.dart';
import '../intro/action_row.dart';
import '../intro/intro_tab.dart';
import '../intro/related_list.dart';
import '../page_details.dart';
import '../player_session.dart';
import 'pad_body.dart';

/// The iPad's page laid out in two columns: the screen is wide. Sideways on the iPhone is always full screen.
bool padSideways(BuildContext context) {
  if (!FormFactor.of(context).isPad) return false;
  final size = MediaQuery.sizeOf(context);
  return size.width > size.height;
}

/// The player's column sideways: what the related column and its rule leave of [screenWidth] (03).
double padPlayerColumnWidth(double screenWidth) =>
    math.max(0, screenWidth - PadPageTheme.relatedWidth - PadPageTheme.rule);

/// The page's top on the iPad: below the status bar, and never above the official 32 pt band.
double padPageTop(double inset) => math.max(inset, PadPageTheme.statusBand);

/// Over the shrinking player (20, 05): the pink deepens as the player goes, ▶ 立即播放 fading in where the bar will
/// be, ‹ and ⋮ joining it once it is the bar. Any other tap on it brings the player back and plays.
class PadPlayerBar extends StatelessWidget {
  const PadPlayerBar({
    super.key,
    required this.progress,
    required this.onResume,
    required this.onBack,
    required this.onMore,
  });

  /// 0 where the pause's shrink started, 1 once it is the bar.
  final double progress;
  final VoidCallback onResume;
  final VoidCallback onBack;
  final VoidCallback onMore;

  static const _rowHeight = PadPageTheme.barRowCentre * 2;

  @override
  Widget build(BuildContext context) {
    final barred = progress >= 1;
    final fade = MediaQuery.disableAnimationsOf(context) ? Duration.zero : CollapseTheme.controlsFade;
    return Stack(
      fit: StackFit.expand,
      children: [
        Semantics(
          key: const ValueKey('collapse-resume'),
          button: true,
          label: '立即播放',
          onTap: onResume,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onResume,
            child: ColoredBox(color: PadPageTheme.barFill.withValues(alpha: progress.clamp(0.0, 1.0))),
          ),
        ),
        Positioned(
          key: const ValueKey('collapse-label'),
          left: 0,
          right: 0,
          top: 0,
          height: _rowHeight,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Opacity(
                opacity: math.min(1, progress * CollapseTheme.labelFade),
                child: const Center(child: _Label()),
              ),
            ),
          ),
        ),
        Positioned(
          left: PadPageTheme.backLeft + CollapseTheme.backGlyphWidth / 2 - BiliMetrics.chromeButton / 2,
          top: 0,
          height: _rowHeight,
          child: _Corner(
            shown: barred,
            fade: fade,
            child: ChromeTap(
              key: const ValueKey('collapse-back'),
              label: '返回',
              onTap: onBack,
              child: const BackGlyph(
                width: CollapseTheme.backGlyphWidth,
                height: CollapseTheme.backGlyphHeight,
                shadow: false,
              ),
            ),
          ),
        ),
        Positioned(
          right: PadPageTheme.moreRight + BiliMetrics.moreDot / 2 - BiliMetrics.chromeButton / 2,
          top: 0,
          height: _rowHeight,
          child: _Corner(
            shown: barred,
            fade: fade,
            child: ChromeTap(
              key: const ValueKey('collapse-more'),
              label: '更多',
              onTap: onMore,
              child: const MoreDots(shadow: false),
            ),
          ),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label();

  /// The APK's `ic_upper_tv_play`, already in the app for 动态's TV mark.
  static const _playMark = 'assets/images/dynamic/ic_upper_tv_play.png';

  /// The APK's mark is 70% white; the bar draws it solid.
  static const _opaque = ColorFilter.matrix([
    0, 0, 0, 0, 255, //
    0, 0, 0, 0, 255, //
    0, 0, 0, 0, 255, //
    0, 0, 0, 1 / 0.7, 0,
  ]);

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const ColorFiltered(
        colorFilter: _opaque,
        child: Image(
          image: AssetImage(_playMark),
          width: PadPageTheme.playGlyphWidth,
          height: PadPageTheme.playGlyphHeight,
          fit: BoxFit.fill,
        ),
      ),
      const SizedBox(width: PadPageTheme.labelGap),
      Text(
        '立即播放',
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          fontFamily: BiliFonts.family,
          fontSize: PadPageTheme.labelText,
          color: PadPageTheme.label,
          height: 1.2,
          letterSpacing: 0,
        ),
      ),
    ],
  );
}

class _Corner extends StatelessWidget {
  const _Corner({required this.shown, required this.fade, required this.child});

  final bool shown;
  final Duration fade;
  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: AnimatedOpacity(
      opacity: shown ? 1 : 0,
      duration: fade,
      curve: Curves.easeOut,
      child: IgnorePointer(
        ignoring: !shown,
        child: ExcludeSemantics(excluding: !shown, child: child),
      ),
    ),
  );
}

/// 简介 upright (06): [PadIntroHead] over the related videos, below the player's reserve, scrolling with the page's
/// primary scroll controller as the phone's 简介 does.
class PadIntroTab extends StatelessWidget {
  const PadIntroTab({
    super.key,
    required this.content,
    required this.details,
    required this.onSeek,
    required this.onOpenVideo,
    required this.onPlayEpisode,
    required this.onOpenEpisodes,
    required this.onOpenRelated,
    required this.onWatchLater,
  });

  final IntroContent content;
  final PageDetails details;
  final ValueChanged<double> onSeek;
  final ValueChanged<String> onOpenVideo;
  final ValueChanged<Episode> onPlayEpisode;
  final VoidCallback onOpenEpisodes;
  final ValueChanged<VideoCard> onOpenRelated;
  final ValueChanged<VideoCard> onWatchLater;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom + PageTheme.introBottom;
    return ListenableBuilder(
      listenable: details,
      builder: (context, _) => CustomScrollView(
        key: const PageStorageKey('pad-intro-scroll'),
        primary: true,
        slivers: [
          SliverToBoxAdapter(
            child: Builder(builder: (context) => SizedBox(height: PlayerReserve.of(context))),
          ),
          if (content.detail != null) ...[
            SliverToBoxAdapter(
              child: PadIntroHead(
                content: content,
                details: details,
                onSeek: onSeek,
                onOpenVideo: onOpenVideo,
                onPlayEpisode: onPlayEpisode,
                onOpenEpisodes: onOpenEpisodes,
              ),
            ),
            RelatedSliver(cards: content.related, onOpen: onOpenRelated, onWatchLater: onWatchLater),
          ],
          SliverToBoxAdapter(child: SizedBox(height: bottom)),
        ],
      ),
    );
  }
}

/// The player's column sideways (03, 05): the player's reserve, [head] (简介 without the related videos) with
/// [capsule] on its uploader row, then [comments], all in one scroll view on [controller], which the shrinking player
/// follows. [headKey] measures the head for the pinned strip.
class PadPlayerColumn extends StatelessWidget {
  const PadPlayerColumn({
    super.key,
    required this.controller,
    required this.headKey,
    required this.head,
    required this.capsule,
    required this.comments,
    required this.bottom,
  });

  final ScrollController controller;
  final GlobalKey headKey;
  final Widget? head;
  final Widget capsule;
  final Widget? comments;

  /// Below the last row: room for the 发条评论 bar and the home indicator.
  final double bottom;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: BiliColors.card,
    child: CustomScrollView(
      key: const ValueKey('pad-player-column'),
      controller: controller,
      slivers: [
        SliverToBoxAdapter(
          child: Builder(
            builder: (context) => SizedBox(key: const ValueKey('pad-reserve'), height: PlayerReserve.of(context)),
          ),
        ),
        if (head case final head?)
          SliverToBoxAdapter(
            child: Stack(
              key: headKey,
              children: [
                // Never shorter than the uploader row the capsule sits on.
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: PadPageTheme.capsuleCentreSideways * 2),
                  child: head,
                ),
                Positioned(
                  right: PadPageTheme.capsuleRight,
                  top: PadPageTheme.capsuleCentreSideways - PadPageTheme.capsuleHeight / 2,
                  child: capsule,
                ),
              ],
            ),
          ),
        ?comments,
        SliverToBoxAdapter(child: SizedBox(height: bottom)),
      ],
    ),
  );
}

/// Pinned under the bar once 简介's actions have scrolled under it (05): the uploader's face, the actions, and
/// 点我发弹幕, over a rule.
class PadPinnedStrip extends StatelessWidget {
  const PadPinnedStrip({super.key, required this.detail, required this.details, required this.capsule, this.onFace});

  final VideoDetail detail;
  final PageDetails details;
  final Widget capsule;
  final VoidCallback? onFace;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    key: const ValueKey('pad-pinned-strip'),
    decoration: const BoxDecoration(
      color: BiliColors.card,
      border: Border(
        bottom: BorderSide(color: PadPageTheme.ruleColour, width: PadPageTheme.rule),
      ),
    ),
    child: SizedBox(
      height: PadPageTheme.stripHeight,
      child: Stack(
        children: [
          Positioned(
            left: PadPageTheme.stripFaceLeft,
            top: (PadPageTheme.stripHeight - PadPageTheme.stripFace) / 2,
            child: Semantics(
              button: onFace != null,
              label: detail.owner.name,
              onTap: onFace,
              excludeSemantics: true,
              child: GestureDetector(
                onTap: onFace,
                child: SizedBox.square(
                  dimension: PadPageTheme.stripFace,
                  child: ClipOval(child: RemoteImage.avatar(detail.owner.face)),
                ),
              ),
            ),
          ),
          if (details.actions case final actions?)
            Positioned(
              left: PadPageTheme.stripActionsLeft,
              width: PadPageTheme.stripActionPitch * 5,
              top: 0,
              bottom: 0,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  maxHeight: ActionTheme.rowHeight + IntroListTheme.actionsBottom,
                  child: Transform.translate(
                    offset: const Offset(0, PadPageTheme.stripIconTop - ActionTheme.topGap),
                    child: ActionRow(actions: actions),
                  ),
                ),
              ),
            ),
          Positioned(
            right: PadPageTheme.capsuleRight,
            top: (PadPageTheme.stripHeight - PadPageTheme.capsuleHeight) / 2,
            child: capsule,
          ),
        ],
      ),
    ),
  );
}
