import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/api.dart' show VideoCard, VideoOwner;
import 'package:bili_core/devlog.dart';
import 'package:bili_core/logic.dart';
import 'package:flutter/widgets.dart';

import '../../shared/action_glyphs.dart';
import '../../shared/remote_image.dart';
import '../../shared/theme.dart';
import '../../shared/toast.dart';
import '../../video/actions/video_actions.dart';
import '../end_screen_portrait.dart' show CountGlyph, CountPainter, ReplayPainter, ShareLink, SharePainter, shareThroughSystem;
import '../landscape_chrome.dart';
import '../player_ui.dart';
import '../portrait_controls.dart';
import '../uploader_source.dart';

/// The iPad's full-screen end screen (ipad/16), over the last frame under a heavy dim: ‹, the uploader with + 关注 and
/// 为TA充电, 重播 | 点赞 不喜欢 投币 收藏 分享 on the right, then 推荐视频 as four columns of cards that rise in one
/// after another, the whole page scrolling. The actions have their room kept until they arrive.
class PadEndFullScreen extends StatefulWidget {
  const PadEndFullScreen({super.key, required this.ui, this.share = shareThroughSystem});

  final PlayerUi ui;

  /// Where 分享 sends the link outside a video page (inside one, the page's overlays share it); tests pass their own
  /// so nothing reaches the platform.
  final ShareLink share;

  @override
  State<PadEndFullScreen> createState() => _PadEndFullScreenState();
}

class _PadEndFullScreenState extends State<PadEndFullScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  )..forward();
  late final CurvedAnimation _fadeIn = CurvedAnimation(parent: _entrance, curve: const Interval(0, 0.4));

  @override
  void dispose() {
    _fadeIn.dispose();
    _entrance.dispose();
    super.dispose();
  }

  /// How far in [index]'s card is: each starts a little after the one before.
  double _cardProgress(int index) {
    final start = math.min(0.2 + index * 0.05, 0.6);
    return Curves.easeOutCubic.transform(((_entrance.value - start) / (1 - start)).clamp(0.0, 1.0));
  }

  Future<void> _share(Uri link) async {
    try {
      await widget.share(link);
    } on Object catch (error) {
      Logger.shared.warn(LogCategory.ui, 'share failed', {'error': '$error'});
      if (mounted) showToast(context, '分享失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ui = widget.ui;
    return ListenableBuilder(
      listenable: Listenable.merge([ui.session, ui.details]),
      builder: (context, _) => ListenableBuilder(
        listenable: Listenable.merge([ui.details?.actions]),
        builder: (context, _) => _build(context, MediaQuery.paddingOf(context)),
      ),
    );
  }

  Widget _build(BuildContext context, EdgeInsets insets) {
    final ui = widget.ui;
    final session = ui.session;
    final related = session.related;
    final owner = uploaderOf(session.detail?.owner, ui.details?.uploader, session.video?.owner);
    return FadeTransition(
      key: const ValueKey('pad-end'),
      opacity: _fadeIn,
      child: DefaultTextStyle(
        style: fullScreenText,
        child: ColoredBox(
          color: PadFullScreenTheme.endDim,
          child: SingleChildScrollView(
            key: const ValueKey('pad-end-scroll'),
            padding: EdgeInsets.only(
              left: insets.left,
              right: insets.right,
              bottom: insets.bottom + PadFullScreenTheme.endInset,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: PadFullScreenTheme.endBackTop),
                ChromeTap(
                  key: const ValueKey('pad-end-back'),
                  label: '返回',
                  onTap: ui.onBack,
                  child: const BackGlyph(
                    width: PadFullScreenTheme.backWidth,
                    height: PadFullScreenTheme.backHeight + 0.7,
                    shadow: false,
                  ),
                ),
                const SizedBox(
                  height: PadFullScreenTheme.endHeadTop - PadFullScreenTheme.endBackTop - BiliMetrics.chromeButton,
                ),
                SizedBox(
                  height: PadFullScreenTheme.endAvatar,
                  child: Row(
                    children: [
                      Expanded(child: owner == null ? const SizedBox.shrink() : _Uploader(owner: owner, ui: ui)),
                      _actions(context),
                      const SizedBox(width: PadFullScreenTheme.endActionsRight),
                    ],
                  ),
                ),
                if (related.isNotEmpty) ...[
                  const SizedBox(
                    height:
                        PadFullScreenTheme.endHeaderCentre -
                        PadFullScreenTheme.endAvatar -
                        PadFullScreenTheme.endHeaderText / 2,
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: PadFullScreenTheme.endHeaderLeft),
                    child: Text(
                      '推荐视频',
                      key: ValueKey('pad-end-header'),
                      style: TextStyle(
                        color: BiliColors.onVideo,
                        fontSize: PadFullScreenTheme.endHeaderText,
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: PadFullScreenTheme.endGridTop - PadFullScreenTheme.endHeaderText / 2),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: PadFullScreenTheme.endInset),
                    child: AnimatedBuilder(
                      animation: _entrance,
                      builder: (context, _) => _grid(related),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _grid(List<VideoCard> related) {
    const columns = PadFullScreenTheme.endColumns;
    final session = widget.ui.session;
    return LayoutBuilder(
      key: const ValueKey('pad-end-related'),
      builder: (context, constraints) {
        final width = (constraints.maxWidth - PadFullScreenTheme.endCardGap * (columns - 1)) / columns;
        final rows = (related.length + columns - 1) ~/ columns;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var row = 0; row < rows; row++) ...[
              if (row > 0) const SizedBox(height: PadFullScreenTheme.endRowGap),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var column = 0; column < columns; column++) ...[
                    if (column > 0) const SizedBox(width: PadFullScreenTheme.endCardGap),
                    if (row * columns + column case final index when index < related.length)
                      Opacity(
                        opacity: _cardProgress(index),
                        child: Transform.translate(
                          offset: Offset(0, (1 - _cardProgress(index)) * BiliMetrics.landscapeEndRise),
                          child: _Card(
                            card: related[index],
                            width: width,
                            onTap: () => session.playRelated(related[index]),
                          ),
                        ),
                      )
                    else
                      SizedBox(width: width),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _actions(BuildContext context) {
    final ui = widget.ui;
    final session = ui.session;
    final actions = ui.details?.actions;
    final link = session.shareLink;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EndAction(
          key: const ValueKey('pad-end-replay'),
          title: '重播',
          glyph: const CustomPaint(
            size: Size(PadFullScreenTheme.endReplayWidth, PadFullScreenTheme.endReplayHeight),
            painter: ReplayPainter(),
          ),
          onTap: () => unawaited(session.replay()),
        ),
        const SizedBox(width: PadFullScreenTheme.endReplayToRule - PadFullScreenTheme.endActionSlot / 2),
        const Padding(
          padding: EdgeInsets.only(top: PadFullScreenTheme.endRuleTop),
          child: SizedBox(
            key: ValueKey('pad-end-rule'),
            width: BiliMetrics.landscapeEndRule,
            height: PadFullScreenTheme.endRuleHeight,
            child: ColoredBox(color: PadFullScreenTheme.endRule),
          ),
        ),
        const SizedBox(width: PadFullScreenTheme.endReplayToRule - PadFullScreenTheme.endActionSlot / 2),
        if (actions == null)
          const SizedBox(width: PadFullScreenTheme.endActionSlot * 4)
        else ...[
          _EndAction(
            key: const ValueKey('pad-end-like'),
            title: '点赞',
            label: actions.liked ? '取消点赞' : '点赞',
            glyph: _Glyph(ActionGlyph.like, active: actions.liked),
            onTap: () => unawaited(actions.toggleLike()),
          ),
          _EndAction(
            key: const ValueKey('pad-end-dislike'),
            title: '不喜欢',
            label: actions.disliked ? '取消不喜欢' : '不喜欢',
            glyph: _Glyph(ActionGlyph.dislike, active: actions.disliked),
            onTap: () => unawaited(actions.toggleDislike()),
          ),
          _EndAction(
            key: const ValueKey('pad-end-coin'),
            title: '投币',
            label: actions.coins > 0 ? '已投币' : '投币',
            glyph: _Glyph(ActionGlyph.coin, active: actions.coins > 0),
            onTap: () => actions.ask(ActionPrompt.coin),
          ),
          _EndAction(
            key: const ValueKey('pad-end-favourite'),
            title: '收藏',
            label: actions.favorited ? '已收藏' : '收藏',
            glyph: _Glyph(ActionGlyph.favourite, active: actions.favorited),
            onTap: () => actions.ask(ActionPrompt.favourites),
          ),
        ],
        if (link != null)
          _EndAction(
            key: const ValueKey('pad-end-share'),
            title: '分享',
            glyph: const CustomPaint(
              size: Size(BiliMetrics.shareGlyphWidth * 1.2, BiliMetrics.shareGlyphHeight * 1.2),
              painter: SharePainter(),
            ),
            // Through the actions the page counts the share once the sheet completes it.
            onTap: actions == null ? () => unawaited(_share(link)) : () => actions.ask(ActionPrompt.share),
          )
        else
          const SizedBox(width: PadFullScreenTheme.endActionSlot),
      ],
    );
  }
}

/// The ringed avatar, the name and under it + 关注 and 为TA充电.
class _Uploader extends StatelessWidget {
  const _Uploader({required this.owner, required this.ui});

  final VideoOwner owner;
  final PlayerUi ui;

  static const _nameStyle = TextStyle(color: BiliColors.onVideo, fontSize: PadFullScreenTheme.endNameText, height: 1);

  @override
  Widget build(BuildContext context) {
    final actions = ui.details?.actions;
    return Row(
      key: const ValueKey('pad-end-uploader'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(width: PadFullScreenTheme.endInset),
        Container(
          width: PadFullScreenTheme.endAvatar,
          height: PadFullScreenTheme.endAvatar,
          padding: const EdgeInsets.all(PadFullScreenTheme.endAvatarRing),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: BiliColors.onVideo, width: PadFullScreenTheme.endAvatarRing),
          ),
          child: ClipOval(
            child: RemoteImage.avatar(owner.face, size: const Size.square(PadFullScreenTheme.endAvatar)),
          ),
        ),
        const SizedBox(
          width: PadFullScreenTheme.endNameLeft - PadFullScreenTheme.endInset - PadFullScreenTheme.endAvatar,
        ),
        Expanded(
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: PadFullScreenTheme.endNameCentre - PadFullScreenTheme.endNameText / 2,
                child: Text(
                  owner.name,
                  key: const ValueKey('pad-end-name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _nameStyle,
                  strutStyle: fullScreenStrut(_nameStyle),
                ),
              ),
              Positioned(
                left: 0,
                top: PadFullScreenTheme.endPillTop,
                child: Row(
                  children: [
                    if (actions case final actions?) ...[
                      _FollowPill(actions: actions),
                      const SizedBox(width: PadFullScreenTheme.endPillGap),
                    ],
                    ChromeTap(
                      key: const ValueKey('pad-end-charge'),
                      label: '为TA充电',
                      square: false,
                      onTap: () => showToast(context, '暂不支持充电'),
                      child: Container(
                        width: PadFullScreenTheme.endChargeWidth,
                        height: PadFullScreenTheme.endPillHeight,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: BiliColors.pink, width: LandscapeActionTheme.pillBorder),
                          borderRadius: BorderRadius.circular(PadFullScreenTheme.endPillRadius),
                        ),
                        child: const Text(
                          '为TA充电',
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(color: BiliColors.pink, fontSize: PadFullScreenTheme.endPillText),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Pink with a white + 关注, or grey with 已关注 once followed.
class _FollowPill extends StatelessWidget {
  const _FollowPill({required this.actions});

  final VideoActions actions;

  @override
  Widget build(BuildContext context) {
    final following = actions.following;
    final motion = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 220);
    return ChromeTap(
      key: const ValueKey('pad-end-follow'),
      label: following ? '已关注' : '关注',
      square: false,
      onTap: actions.tapFollow,
      child: AnimatedContainer(
        duration: motion,
        curve: Curves.easeOut,
        width: PadFullScreenTheme.endFollowWidth,
        height: PadFullScreenTheme.endPillHeight,
        decoration: BoxDecoration(
          color: following ? LandscapeActionTheme.followedPill : BiliColors.pink,
          borderRadius: BorderRadius.circular(PadFullScreenTheme.endPillRadius),
        ),
        child: AnimatedSwitcher(
          duration: motion,
          child: Row(
            key: ValueKey(following),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!following) ...[
                const CustomPaint(
                  size: Size.square(PadFullScreenTheme.endPillPlus),
                  painter: FollowPlusPainter(color: BiliColors.onPink, stroke: PadFullScreenTheme.endPillPlusStroke),
                ),
                const SizedBox(width: PadFullScreenTheme.endPillPlusGap),
              ],
              Text(
                following ? '已关注' : '关注',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  color: following ? LandscapeActionTheme.followed : BiliColors.onPink,
                  fontSize: PadFullScreenTheme.endPillText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph(this.glyph, {required this.active});

  final ActionGlyph glyph;
  final bool active;

  @override
  Widget build(BuildContext context) => Transform.translate(
    offset: Offset(0, glyph == ActionGlyph.dislike ? -PadFullScreenTheme.dislikeLift : 0),
    child: ActionPop(glyph, active: active, size: PadFullScreenTheme.endActionIcon, stroke: PadFullScreenTheme.actionStroke),
  );
}

/// A 70 pt column: the glyph centred over its 15 pt label.
class _EndAction extends StatelessWidget {
  const _EndAction({super.key, required this.title, required this.glyph, required this.onTap, this.label});

  final String title;
  final Widget glyph;
  final VoidCallback onTap;

  /// What VoiceOver reads, when it says more than [title] (取消点赞, 已收藏).
  final String? label;

  @override
  Widget build(BuildContext context) => ChromeTap(
    label: label ?? title,
    square: false,
    onTap: onTap,
    child: SizedBox(
      width: PadFullScreenTheme.endActionSlot,
      height: PadFullScreenTheme.endAvatar,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: PadFullScreenTheme.endIconCentre - PadFullScreenTheme.endActionIcon / 2,
            height: PadFullScreenTheme.endActionIcon,
            child: Center(child: glyph),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: PadFullScreenTheme.endLabelCentre - PadFullScreenTheme.endLabelText / 2,
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(color: BiliColors.onVideo, fontSize: PadFullScreenTheme.endLabelText, height: 1),
            ),
          ),
        ],
      ),
    ),
  );
}

/// A related video: the 16:10 cover with its counts and duration on it, then the title in two lines (16).
class _Card extends StatelessWidget {
  const _Card({required this.card, required this.width, required this.onTap});

  final VideoCard card;
  final double width;
  final VoidCallback onTap;

  static const _titleStyle = TextStyle(
    color: PadFullScreenTheme.endTitleInk,
    fontSize: PadFullScreenTheme.endTitleText,
    height: PadFullScreenTheme.endTitleLeading,
  );

  static const _countStyle = TextStyle(
    color: BiliColors.onVideo,
    fontSize: PadFullScreenTheme.endCountText,
    height: 1,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  @override
  Widget build(BuildContext context) {
    final height = width / PadFullScreenTheme.endCoverAspect;
    return ChromeTap(
      label: card.title,
      square: false,
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(PadFullScreenTheme.endCoverRadius),
              child: SizedBox(
                width: width,
                height: height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    RemoteImage(
                      card.cover,
                      cover: true,
                      placeholder: const ColoredBox(color: BiliColors.landscapeEndPlaceholder),
                    ),
                    const Align(
                      alignment: Alignment.bottomCenter,
                      child: SizedBox(
                        height: BiliMetrics.endCoverShadeHeight,
                        width: double.infinity,
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
                    ),
                    Positioned(
                      left: PadFullScreenTheme.endCoverInset,
                      right: PadFullScreenTheme.endCoverTrailing,
                      bottom: PadFullScreenTheme.endCountCentre - PadFullScreenTheme.endCountText / 2,
                      height: PadFullScreenTheme.endCountText,
                      child: Row(
                        children: [
                          // On a cover too narrow for them all, the counts give way before the duration does.
                          Expanded(
                            child: ClipRect(
                              child: Row(
                                children: [
                                  const _CountIcon(CountGlyph.views),
                                  Flexible(
                                    child: Text(CountFormat.short(card.views), style: _countStyle, softWrap: false),
                                  ),
                                  const SizedBox(width: PadFullScreenTheme.endCountSpacing),
                                  const _CountIcon(CountGlyph.danmaku),
                                  Flexible(
                                    child: Text(CountFormat.short(card.danmaku), style: _countStyle, softWrap: false),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: BiliMetrics.landscapeEndCountGap),
                          Text(TimeFormat.clock(card.duration.toDouble()), style: _countStyle),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: PadFullScreenTheme.endTitleTop),
              child: SizedBox(
                height: PadFullScreenTheme.endTitleText * PadFullScreenTheme.endTitleLeading * 2,
                child: Text(
                  card.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _titleStyle,
                  strutStyle: fullScreenStrut(_titleStyle),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountIcon extends StatelessWidget {
  const _CountIcon(this.glyph);

  final CountGlyph glyph;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: PadFullScreenTheme.endCountIconGap),
    child: CustomPaint(
      size: const Size(BiliMetrics.landscapeEndCountIconWidth, BiliMetrics.landscapeEndCountIconHeight),
      painter: CountPainter(glyph, color: BiliColors.onVideo),
    ),
  );
}
