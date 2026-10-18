import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/api.dart' show VideoCard, VideoOwner;
import 'package:bili_core/devlog.dart';
import 'package:bili_core/logic.dart';
import 'package:flutter/widgets.dart';

import '../shared/action_glyphs.dart';
import '../shared/remote_image.dart';
import '../shared/theme.dart';
import '../shared/toast.dart';
import '../video/actions/video_actions.dart';
import 'end_screen_portrait.dart'
    show CountGlyph, CountPainter, ReplayPainter, ShareLink, SharePainter, shareThroughSystem;
import 'landscape_chrome.dart';
import 'player_ui.dart';
import 'portrait_controls.dart';

/// The full-screen end screen (BiliNative `EndScreens.swift`, measured on 27): back, the uploader with 充电 and 关注,
/// 重播 | 点赞 投币 收藏 分享, and a row of related videos that rise in one after another. It fills the screen. The
/// actions have their room kept until they arrive, so nothing else moves when they come.
class EndScreenLandscape extends StatefulWidget {
  const EndScreenLandscape({super.key, required this.ui, this.share = shareThroughSystem});

  final PlayerUi ui;

  /// Where 分享 sends the link outside a video page (inside one, the page's overlays share it); tests pass their own
  /// so nothing reaches the platform.
  final ShareLink share;

  @override
  State<EndScreenLandscape> createState() => _EndScreenLandscapeState();
}

class _EndScreenLandscapeState extends State<EndScreenLandscape> with SingleTickerProviderStateMixin {
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
    final start = math.min(0.2 + index * 0.08, 0.6);
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
    final insets = MediaQuery.paddingOf(context);
    return Stack(
      key: const ValueKey('end-landscape-layers'),
      fit: StackFit.expand,
      children: [
        // Under the dim, as on 27.
        LandscapeCornerOnline(ui: ui, shown: true),
        ListenableBuilder(
          listenable: Listenable.merge([ui.session, ui.details]),
          builder: (context, _) => ListenableBuilder(
            listenable: Listenable.merge([ui.details?.actions]),
            builder: (context, _) => _build(context, insets),
          ),
        ),
      ],
    );
  }

  Widget _build(BuildContext context, EdgeInsets insets) {
    final ui = widget.ui;
    final session = ui.session;
    final actions = ui.details?.actions;
    final link = session.shareLink;
    final related = session.related;
    final owner = switch ((session.detail?.owner, ui.details?.uploader)) {
      (final owner?, _) => owner,
      (null, final uploader?) => VideoOwner(mid: uploader.mid, name: uploader.name, face: uploader.face),
      (null, null) => null,
    };
    final rule = Padding(
      padding: EdgeInsets.only(left: insets.left, right: insets.right),
      child: const SizedBox(
        height: BiliMetrics.landscapeEndRule,
        width: double.infinity,
        child: ColoredBox(color: BiliColors.landscapeEndRule),
      ),
    );
    return FadeTransition(
      key: const ValueKey('end-landscape'),
      opacity: _fadeIn,
      child: DefaultTextStyle(
        style: fullScreenText,
        child: ColoredBox(
          color: BiliColors.landscapeEndDim,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(top: insets.top, bottom: insets.bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(left: insets.left),
                  child: ChromeTap(
                    key: const ValueKey('end-back'),
                    label: '返回',
                    onTap: ui.onBack,
                    child: const BackGlyph(),
                  ),
                ),
                rule,
                SizedBox(
                  height: BiliMetrics.landscapeEndRow,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: insets.left,
                      right: math.max(insets.right - BiliMetrics.landscapeEndActionsOutset, 0),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: owner == null ? const SizedBox.shrink() : _Uploader(owner: owner, actions: actions),
                        ),
                        _EndAction(
                          key: const ValueKey('end-replay'),
                          title: '重播',
                          glyph: const CustomPaint(
                            size: Size(BiliMetrics.replayGlyphWidth, BiliMetrics.replayGlyphHeight),
                            painter: ReplayPainter(),
                          ),
                          onTap: () => unawaited(session.replay()),
                        ),
                        const SizedBox(width: BiliMetrics.landscapeEndDividerGap),
                        const SizedBox(
                          key: ValueKey('end-divider'),
                          width: BiliMetrics.landscapeEndRule,
                          height: BiliMetrics.landscapeEndDividerHeight,
                          child: ColoredBox(color: BiliColors.landscapeEndRule),
                        ),
                        const SizedBox(width: BiliMetrics.landscapeEndDividerGap),
                        if (actions == null)
                          const SizedBox(width: BiliMetrics.landscapeEndActionWidth * 3)
                        else ...[
                          _EndAction(
                            key: const ValueKey('end-like'),
                            title: '点赞',
                            label: actions.liked ? '取消点赞' : '点赞',
                            glyph: _ActionGlyph(ActionGlyph.like, active: actions.liked),
                            onTap: () => unawaited(actions.toggleLike()),
                          ),
                          _EndAction(
                            key: const ValueKey('end-coin'),
                            title: '投币',
                            label: actions.coins > 0 ? '已投币' : '投币',
                            glyph: _ActionGlyph(ActionGlyph.coin, active: actions.coins > 0),
                            onTap: () => actions.ask(ActionPrompt.coin),
                          ),
                          _EndAction(
                            key: const ValueKey('end-favourite'),
                            title: '收藏',
                            label: actions.favorited ? '已收藏' : '收藏',
                            glyph: _ActionGlyph(ActionGlyph.favourite, active: actions.favorited),
                            onTap: () => actions.ask(ActionPrompt.favourites),
                          ),
                        ],
                        if (link != null)
                          _EndAction(
                            key: const ValueKey('end-share'),
                            title: '分享',
                            glyph: const CustomPaint(
                              size: Size(BiliMetrics.shareGlyphWidth, BiliMetrics.shareGlyphHeight),
                              painter: SharePainter(),
                            ),
                            // Through the actions the page counts the share once the sheet completes it.
                            onTap: actions == null
                                ? () => unawaited(_share(link))
                                : () => actions.ask(ActionPrompt.share),
                          )
                        else
                          const SizedBox(width: BiliMetrics.landscapeEndActionWidth),
                      ],
                    ),
                  ),
                ),
                rule,
                if (related.isNotEmpty) ...[
                  Padding(
                    padding: EdgeInsets.only(
                      left: insets.left + BiliMetrics.landscapeEndInset,
                      top: BiliMetrics.landscapeEndHeaderTop,
                    ),
                    child: const Text(
                      '推荐视频',
                      style: TextStyle(color: BiliColors.onVideo, fontSize: BiliMetrics.landscapeEndHeaderText),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(
                      left: insets.left,
                      right: insets.right,
                      top: BiliMetrics.landscapeEndRowTop,
                    ),
                    child: ClipRect(
                      child: SingleChildScrollView(
                        key: const ValueKey('end-related'),
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: BiliMetrics.landscapeEndInset),
                        child: AnimatedBuilder(
                          animation: _entrance,
                          builder: (context, _) => Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final (index, card) in related.indexed) ...[
                                if (index > 0) const SizedBox(width: BiliMetrics.landscapeEndCardGap),
                                Opacity(
                                  opacity: _cardProgress(index),
                                  child: Transform.translate(
                                    offset: Offset(0, (1 - _cardProgress(index)) * BiliMetrics.landscapeEndRise),
                                    child: _RelatedCard(card: card, onTap: () => session.playRelated(card)),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
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
}

/// The uploader's ringed avatar and name, with 充电 and 关注 under the name, level with the avatar's bottom.
class _Uploader extends StatelessWidget {
  const _Uploader({required this.owner, required this.actions});

  final VideoOwner owner;
  final VideoActions? actions;

  @override
  Widget build(BuildContext context) => Row(
    key: const ValueKey('end-uploader'),
    children: [
      const SizedBox(width: BiliMetrics.landscapeEndAvatarInset),
      Container(
        width: BiliMetrics.landscapeEndAvatar,
        height: BiliMetrics.landscapeEndAvatar,
        padding: const EdgeInsets.all(BiliMetrics.landscapeEndAvatarRing),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: BiliColors.onVideo, width: BiliMetrics.landscapeEndAvatarRing),
        ),
        child: ClipOval(
          child: RemoteImage(
            owner.face,
            size: const Size.square(BiliMetrics.landscapeEndAvatar),
            placeholder: const ColoredBox(color: BiliColors.landscapeEndPlaceholder),
          ),
        ),
      ),
      const SizedBox(width: BiliMetrics.landscapeEndAvatarGap),
      Expanded(
        child: SizedBox(
          height: BiliMetrics.landscapeEndAvatar,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                owner.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: BiliColors.onVideo, fontSize: BiliMetrics.landscapeEndNameText),
              ),
              const Spacer(),
              Row(
                children: [
                  ChromeTap(
                    key: const ValueKey('end-charge'),
                    label: '充电',
                    square: false,
                    onTap: () => showToast(context, '暂不支持充电'),
                    child: Container(
                      width: LandscapeActionTheme.pillWidth,
                      height: LandscapeActionTheme.pillHeight,
                      decoration: BoxDecoration(
                        border: Border.all(color: BiliColors.pink, width: LandscapeActionTheme.pillBorder),
                        borderRadius: BorderRadius.circular(LandscapeActionTheme.pillHeight / 2),
                      ),
                      padding: const EdgeInsets.only(left: LandscapeActionTheme.chargeShift),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CustomPaint(
                            size: Size(LandscapeActionTheme.boltWidth, LandscapeActionTheme.boltHeight),
                            painter: _BoltPainter(),
                          ),
                          SizedBox(width: LandscapeActionTheme.boltGap),
                          Text(
                            '充电',
                            style: TextStyle(color: BiliColors.pink, fontSize: LandscapeActionTheme.pillText),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (actions case final actions?) ...[
                    const SizedBox(width: LandscapeActionTheme.pillGap),
                    _FollowPill(actions: actions),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    ],
  );
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
      key: const ValueKey('end-follow'),
      label: following ? '已关注' : '关注',
      square: false,
      onTap: actions.tapFollow,
      child: AnimatedContainer(
        duration: motion,
        curve: Curves.easeOut,
        width: LandscapeActionTheme.pillWidth,
        height: LandscapeActionTheme.pillHeight,
        decoration: BoxDecoration(
          color: following ? LandscapeActionTheme.followedPill : BiliColors.pink,
          borderRadius: BorderRadius.circular(LandscapeActionTheme.pillHeight / 2),
        ),
        child: AnimatedSwitcher(
          duration: motion,
          child: Row(
            key: ValueKey(following),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!following) ...[
                const CustomPaint(
                  size: Size.square(LandscapeActionTheme.pillPlus),
                  painter: FollowPlusPainter(color: BiliColors.onPink, stroke: LandscapeActionTheme.pillPlusStroke),
                ),
                const SizedBox(width: LandscapeActionTheme.pillPlusGap),
              ],
              Text(
                following ? '已关注' : '关注',
                style: TextStyle(
                  color: following ? LandscapeActionTheme.followed : BiliColors.onPink,
                  fontSize: LandscapeActionTheme.pillText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 27's 充电 bolt, traced as shares of its box.
class _BoltPainter extends CustomPainter {
  const _BoltPainter();

  static const _shape = [
    (0.338, 0.0),
    (1.0, 0.0),
    (0.68, 0.334),
    (0.981, 0.381),
    (0.075, 1.0),
    (0.318, 0.579),
    (0.016, 0.579),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final points = [for (final (x, y) in _shape) Offset(x * size.width, y * size.height)];
    canvas.drawPath(Path()..addPolygon(points, true), Paint()..color = BiliColors.pink);
  }

  @override
  bool shouldRepaint(_BoltPainter oldDelegate) => false;
}

/// An action's glyph in the 22 pt row the end screen's cells keep for it; the glyph's own box is a little taller.
class _ActionGlyph extends StatelessWidget {
  const _ActionGlyph(this.glyph, {required this.active});

  final ActionGlyph glyph;
  final bool active;

  @override
  Widget build(BuildContext context) => OverflowBox(
    maxWidth: LandscapeActionTheme.iconSize,
    maxHeight: LandscapeActionTheme.iconSize,
    child: ActionPop(glyph, active: active),
  );
}

/// The portrait end screen's count icon, white and smaller; 27 sets it further in and a little higher than the
/// counts' text box would.
class _CountIcon extends StatelessWidget {
  const _CountIcon(this.glyph);

  final CountGlyph glyph;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      left: BiliMetrics.landscapeEndCountIconLead,
      right: BiliMetrics.landscapeEndCountIconGap,
      bottom: BiliMetrics.landscapeEndCountIconRise * 2,
    ),
    child: CustomPaint(
      size: const Size(BiliMetrics.landscapeEndCountIconWidth, BiliMetrics.landscapeEndCountIconHeight),
      painter: CountPainter(glyph, color: BiliColors.onVideo),
    ),
  );
}

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
      width: BiliMetrics.landscapeEndActionWidth,
      height: BiliMetrics.landscapeEndRow,
      child: Column(
        children: [
          const SizedBox(height: BiliMetrics.landscapeEndActionTop),
          SizedBox(
            height: BiliMetrics.landscapeEndActionIcon,
            child: Center(child: glyph),
          ),
          const SizedBox(height: BiliMetrics.landscapeEndActionGap),
          Text(
            title,
            style: const TextStyle(color: BiliColors.onVideo, fontSize: BiliMetrics.landscapeEndActionText),
          ),
        ],
      ),
    ),
  );
}

/// A related video's cover with its counts and duration on it, the title and the uploader, as in 27's row.
class _RelatedCard extends StatelessWidget {
  const _RelatedCard({required this.card, required this.onTap});

  final VideoCard card;
  final VoidCallback onTap;

  static const _countStyle = TextStyle(
    color: BiliColors.onVideo,
    fontSize: BiliMetrics.landscapeEndCountText,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Covers say 0:48, not 00:48.
  static String _duration(int seconds) {
    final text = TimeFormat.clock(seconds.toDouble());
    return text.length == 5 && text.startsWith('0') ? text.substring(1) : text;
  }

  @override
  Widget build(BuildContext context) => ChromeTap(
    label: card.title,
    square: false,
    onTap: onTap,
    child: SizedBox(
      width: BiliMetrics.landscapeEndCardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(BiliMetrics.endCoverRadius),
            child: SizedBox(
              width: BiliMetrics.landscapeEndCardWidth,
              height: BiliMetrics.landscapeEndCoverHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RemoteImage(card.cover, placeholder: const ColoredBox(color: BiliColors.landscapeEndPlaceholder)),
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
                    left: BiliMetrics.landscapeEndCoverInset,
                    right: BiliMetrics.landscapeEndCoverInset,
                    bottom: BiliMetrics.landscapeEndCoverBottom,
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
                                const SizedBox(width: BiliMetrics.landscapeEndCountSpacing),
                                const _CountIcon(CountGlyph.danmaku),
                                Flexible(
                                  child: Text(CountFormat.short(card.danmaku), style: _countStyle, softWrap: false),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: BiliMetrics.landscapeEndCountGap),
                        Text(_duration(card.duration), style: _countStyle),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: BiliMetrics.landscapeEndCardTitleTop),
            child: Text(
              card.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: BiliColors.onVideo,
                fontSize: BiliMetrics.landscapeEndCardTitle,
                height: BiliMetrics.landscapeEndCardTitleLeading,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: BiliMetrics.landscapeEndUploaderTop),
            child: Row(
              children: [
                Container(
                  width: BiliMetrics.endUpWidth,
                  height: BiliMetrics.endUpHeight,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: BiliColors.endMeta, width: BiliMetrics.endUpBorder),
                    borderRadius: BorderRadius.circular(BiliMetrics.endUpRadius),
                  ),
                  child: const Text(
                    'UP',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      color: BiliColors.endMeta,
                      fontSize: BiliMetrics.endUpFont,
                      fontWeight: FontWeight.bold,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(width: BiliMetrics.endMetaGap),
                Expanded(
                  child: Text(
                    card.ownerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: BiliColors.endMeta, fontSize: BiliMetrics.landscapeEndUploaderText),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
