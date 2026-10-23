import 'dart:async';

import 'package:bili_core/api.dart';
import 'package:bili_core/logic.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import '../app/zoom_back_route.dart';
import '../shared/cover_placeholder.dart';
import '../shared/remote_image.dart';
import '../shared/theme.dart';
import '../video/video_route.dart';
import 'feed_dislike.dart';
import 'feed_model.dart' show CardDislike;
import 'feed_more_sheet.dart';

/// Card sizes that depend on the text size, so the grid can give every card the same height.
abstract final class FeedCardSize {
  static const _lineHeight = BiliMetrics.cardTitleLine / BiliMetrics.cardTitleText;

  static double titleHeight(TextScaler scaler) => scaler.scale(BiliMetrics.cardTitleText) * _lineHeight * 2;

  /// The tag, uploader and ⋮ row with its gaps. Its text keeps one size, as Swift's fixed `.system(size:)` did.
  static const footerHeight = BiliMetrics.cardFooterInset * 2 + BiliMetrics.cardTagHeight;

  /// The whole card for a column [width] wide: 4:3 cover, two title lines, the footer and their gaps.
  static double height(double width, TextScaler scaler) =>
      width / BiliMetrics.coverAspect + BiliMetrics.cardTitleTop + titleHeight(scaler) + footerHeight;

  /// The cover's box on a card [width] wide: the size its picture is asked for at.
  static Size cover(double width) => Size(width, width / BiliMetrics.coverAspect);
}

/// One 推荐 card (01, port of FeedCard.swift): the cover with counts and duration, a two-line title, and the tag,
/// uploader and ⋮ footer. It gives a little under the finger. [onOpen] gets the card's [ZoomSource], for the swipe
/// back into it. ⋮ opens its sheet (90); after 不感兴趣 ([dislike] set) the card shows [FeedDislikedCard] (91) instead.
class FeedCardView extends StatefulWidget {
  const FeedCardView({
    super.key,
    required this.card,
    required this.onOpen,
    required this.onWatchLater,
    this.dislike,
    this.onDislike,
    this.onUndo,
    this.onReason,
  });

  final FeedCard card;
  final ValueChanged<ZoomSource> onOpen;
  final VoidCallback onWatchLater;

  /// The card's 不感兴趣 while it stands.
  final CardDislike? dislike;

  /// 不感兴趣 with one of the card's reasons (the video's or the uploader's).
  final ValueChanged<FeedReason>? onDislike;
  final VoidCallback? onUndo;

  /// The reasons sheet's pick.
  final ValueChanged<FeedReason>? onReason;

  /// Gets [url] ready as a card with a [size] cover box asks for it, so the card draws it the frame it comes.
  static Future<bool> precacheCover(BuildContext context, String? url, Size size) =>
      RemoteImage.precache(context, url, size: size, cover: true);

  /// Covers say 0:18, not 00:18 (01).
  static String duration(int seconds) {
    final clock = TimeFormat.clock(seconds.toDouble());
    return clock.startsWith('0') && clock.length == 5 ? clock.substring(1) : clock;
  }

  @override
  State<FeedCardView> createState() => _FeedCardViewState();
}

class _FeedCardViewState extends State<FeedCardView> {
  bool _pressed = false;

  static const _title = TextStyle(
    fontSize: BiliMetrics.cardTitleText,
    color: BiliColors.text,
    height: FeedCardSize._lineHeight,
  );
  static const _owner = TextStyle(fontSize: BiliMetrics.cardFooterText, color: BiliColors.secondaryText, height: 1);

  void _press(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  Future<void> _more() async {
    final card = widget.card;
    final choice = await showFeedMoreSheet(context, card);
    final dislike = card.dislike;
    switch (choice) {
      case null:
        return;
      case FeedMoreChoice.watchLater:
        widget.onWatchLater();
      case FeedMoreChoice.dislikeVideo:
        if (dislike?.video case final reason?) widget.onDislike?.call(reason);
      case FeedMoreChoice.dislikeUploader:
        if (dislike?.uploader case final reason?) widget.onDislike?.call(reason);
    }
  }

  Future<void> _reasons() async {
    final dislike = widget.card.dislike;
    if (dislike == null) return;
    final picked = await showFeedReasonsSheet(context, dislike);
    if (picked != null) widget.onReason?.call(picked);
  }

  @override
  Widget build(BuildContext context) {
    final dislike = widget.dislike;
    final data = widget.card.dislike;
    final offersReasons = data != null && (data.tiles.isNotEmpty || data.repeated != null);
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : FeedDislikeTheme.fadeIn,
      child: dislike == null
          ? ZoomSourceBox(key: const ValueKey('feed-card-live'), builder: _card)
          : FeedDislikedCard(
              key: const ValueKey('feed-card-disliked'),
              card: widget.card,
              onUndo: () => widget.onUndo?.call(),
              onReasons: offersReasons ? () => unawaited(_reasons()) : null,
            ),
    );
  }

  Widget _card(BuildContext context, ZoomSource source) {
    final card = widget.card;
    final scaler = MediaQuery.textScalerOf(context);
    // Passthrough keeps the grid's tight size on the card.
    return Stack(
      fit: StackFit.passthrough,
      children: [
        _body(context, card, scaler, source),
        // ⋮'s own element, over the footer's ⋮: inside the card's excluded subtree it could only be a custom action,
        // which Windows UIA (and so ghosthand) doesn't offer. Touches pass through it to the ⋮ under it.
        Positioned(
          right: 0,
          bottom: (FeedCardSize.footerHeight - BiliMetrics.cardMoreTarget) / 2,
          width: BiliMetrics.cardMoreTarget,
          height: BiliMetrics.cardMoreTarget,
          child: Semantics(
            key: const ValueKey('card-more-semantics'),
            container: true,
            button: true,
            label: '更多',
            onTap: () => unawaited(_more()),
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, FeedCard card, TextScaler scaler, ZoomSource source) {
    // One element for VoiceOver, named by the title, with 稍后再看 as its action.
    return Semantics(
      button: true,
      label: card.title,
      onTap: () => widget.onOpen(source),
      customSemanticsActions: {
        const CustomSemanticsAction(label: '稍后再看'): widget.onWatchLater,
      },
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _press(true),
        onTapUp: (_) => _press(false),
        onTapCancel: () => _press(false),
        onTap: () => widget.onOpen(source),
        child: AnimatedScale(
          scale: _pressed ? BiliMetrics.pressedScale : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(BiliMetrics.cardRadius),
            child: ColoredBox(
              color: BiliColors.card,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Cover(card: card),
                  Padding(
                    padding: const EdgeInsets.only(
                      left: BiliMetrics.cardInset,
                      right: BiliMetrics.cardInset,
                      top: BiliMetrics.cardTitleTop,
                    ),
                    child: SizedBox(
                      height: FeedCardSize.titleHeight(scaler),
                      child: Text(
                        card.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _title,
                        strutStyle: BiliFonts.strutOf(context, _title),
                      ),
                    ),
                  ),
                  MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1,
                    child: SizedBox(
                      height: FeedCardSize.footerHeight,
                      child: Padding(
                        padding: const EdgeInsets.only(left: BiliMetrics.cardInset),
                        child: Row(
                          children: [
                            _Badge(card: card),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                card.ownerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _owner,
                                strutStyle: BiliFonts.strutOf(context, _owner),
                              ),
                            ),
                            GestureDetector(
                              key: const ValueKey('card-more'),
                              behavior: HitTestBehavior.opaque,
                              onTap: () => unawaited(_more()),
                              child: SizedBox.square(
                                dimension: BiliMetrics.cardMoreTarget,
                                child: Transform.translate(
                                  offset: const Offset(0, BiliMetrics.cardMoreDrop),
                                  child: const Icon(
                                    Icons.more_vert,
                                    size: BiliMetrics.cardFooterText + 4,
                                    color: BiliColors.secondaryText,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.card});

  final FeedCard card;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: BiliMetrics.coverAspect,
    child: Stack(
      fit: StackFit.expand,
      children: [
        Hero(
          tag: VideoRoute.coverTag(card.bvid),
          // A cover still loading is the official flat grey with no shade, and a late one pops in (14).
          child: RemoteImage(
            card.cover,
            cover: true,
            placeholder: const CoverPlaceholder(),
            fadeIn: false,
            overlay: const Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: BiliMetrics.coverShadeHeight,
                width: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [BiliColors.chromeShadeClear, BiliColors.coverShade],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: BiliMetrics.cardStatLead,
          right: BiliMetrics.cardStatTrail,
          bottom: 0,
          height: BiliMetrics.cardStatCentre * 2,
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1,
            child: DefaultTextStyle(
              style: TextStyle(
                fontFamily: BiliFonts.family,
                fontFamilyFallback: BiliFonts.fallback,
                fontSize: BiliMetrics.cardStatText,
                color: BiliColors.onCover,
              ),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              // On a card too narrow for them all, the counts give way before the duration does.
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const _StatIcon(_StatIcon.play),
                        const SizedBox(width: BiliMetrics.cardStatIconGap),
                        Flexible(child: _StatText(card.viewsText ?? CountFormat.short(card.views))),
                        const SizedBox(width: BiliMetrics.cardStatGap),
                        const _StatIcon(_StatIcon.danmaku),
                        const SizedBox(width: BiliMetrics.cardStatIconGap),
                        Flexible(child: _StatText(card.danmakuText ?? CountFormat.short(card.danmaku))),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  _StatText(FeedCardView.duration(card.duration)),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// The official play or danmaku count icon, drawn white.
class _StatIcon extends StatelessWidget {
  const _StatIcon(this.asset);

  static const play = 'assets/images/card/stat_play.png';
  static const danmaku = 'assets/images/card/stat_danmaku.png';

  final String asset;

  @override
  Widget build(BuildContext context) => Image.asset(
    asset,
    width: BiliMetrics.cardStatIconWidth,
    height: BiliMetrics.cardStatIconHeight,
    color: BiliColors.onCover,
    colorBlendMode: BlendMode.srcIn,
    excludeFromSemantics: true,
  );
}

class _StatText extends StatelessWidget {
  const _StatText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Transform.translate(offset: const Offset(0, BiliMetrics.cardStatTextDrop), child: Text(text));
}

class _Badge extends StatelessWidget {
  const _Badge({required this.card});

  final FeedCard card;

  @override
  Widget build(BuildContext context) {
    final reason = card.reason;
    if (reason != null && reason.isNotEmpty) return _Tag(reason);
    if (card.isVertical) return const _Tag('竖屏');
    return const UpBadge();
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  static const _style = TextStyle(fontSize: BiliMetrics.cardTagText, color: BiliColors.reason, height: 1);

  @override
  Widget build(BuildContext context) => Container(
    height: BiliMetrics.cardTagHeight,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    alignment: Alignment.center,
    decoration: BoxDecoration(color: BiliColors.reasonTint, borderRadius: BorderRadius.circular(2)),
    child: Text(text, maxLines: 1, style: _style, strutStyle: BiliFonts.strutOf(context, _style)),
  );
}

class UpBadge extends StatelessWidget {
  const UpBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
    height: BiliMetrics.upBadgeHeight,
    padding: const EdgeInsets.symmetric(horizontal: 2),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      border: Border.all(color: BiliColors.secondaryText),
      borderRadius: BorderRadius.circular(2.5),
    ),
    child: const Text(
      'UP',
      style: TextStyle(
        fontSize: BiliMetrics.upBadgeText,
        fontWeight: FontWeight.bold,
        color: BiliColors.secondaryText,
        height: 1,
      ),
    ),
  );
}

/// A card's outline while the first page loads, a light band sweeping across it.
class FeedCardSkeleton extends StatelessWidget {
  const FeedCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(BiliMetrics.cardRadius),
      child: ColoredBox(
        color: BiliColors.card,
        // Inside the card, so the sweep lights only the grey shapes and not the white around them.
        child: Shimmer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AspectRatio(
                aspectRatio: BiliMetrics.coverAspect,
                child: ColoredBox(color: BiliColors.shimmerBase),
              ),
              Padding(
                padding: const EdgeInsets.only(
                  left: BiliMetrics.cardInset,
                  right: BiliMetrics.cardInset * 3,
                  top: BiliMetrics.cardTitleTop,
                ),
                child: SizedBox(
                  height: FeedCardSize.titleHeight(scaler),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _Bar(),
                      FractionallySizedBox(widthFactor: 0.6, child: _Bar()),
                    ],
                  ),
                ),
              ),
              const SizedBox(
                height: FeedCardSize.footerHeight,
                child: Padding(
                  padding: EdgeInsets.only(left: BiliMetrics.cardInset),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(widthFactor: 0.4, child: _Bar()),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar();

  @override
  Widget build(BuildContext context) => Container(
    height: 12,
    decoration: BoxDecoration(color: BiliColors.shimmerBase, borderRadius: BorderRadius.circular(3)),
  );
}

/// Sweeps a light band across [child] every 1.3 s; still when the system asks for less motion.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _sweep.stop();
    } else if (!_sweep.isAnimating) {
      unawaited(_sweep.repeat());
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_sweep.isAnimating) return widget.child;
    return AnimatedBuilder(
      animation: _sweep,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) {
          final at = -1.0 + _sweep.value * 3;
          return LinearGradient(
            begin: Alignment(at - 1, -0.3),
            end: Alignment(at + 1, 0.3),
            colors: const [BiliColors.shimmerBase, BiliColors.shimmerHighlight, BiliColors.shimmerBase],
            stops: const [0.35, 0.5, 0.65],
          ).createShader(bounds);
        },
        child: child,
      ),
    );
  }
}
