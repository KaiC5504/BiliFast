import 'package:bili_core/api.dart';
import 'package:bili_core/logic.dart';
import 'package:flutter/material.dart';

import '../shared/remote_image.dart';
import '../shared/theme.dart';

/// Card sizes that depend on the text size, so the grid can give every card the same height.
abstract final class FeedCardSize {
  static const _lineHeight = 1.3;

  static double titleHeight(TextScaler scaler) => scaler.scale(BiliMetrics.cardTitleText) * _lineHeight * 2;

  /// The whole card for a column [width] wide: 4:3 cover, two title lines, the footer and their gaps.
  static double height(double width, TextScaler scaler) =>
      width / BiliMetrics.coverAspect + 10 + titleHeight(scaler) + 9 + BiliMetrics.cardTagHeight + 9;
}

/// One 推荐 card (01, port of FeedCard.swift): the cover with counts and duration, a two-line title, and the tag,
/// uploader and ⋮ footer. It gives a little under the finger.
class FeedCardView extends StatefulWidget {
  const FeedCardView({super.key, required this.card, required this.onOpen, required this.onWatchLater});

  final FeedCard card;
  final VoidCallback onOpen;
  final VoidCallback onWatchLater;

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

  void _press(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final scaler = MediaQuery.textScalerOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _press(true),
      onTapUp: (_) => _press(false),
      onTapCancel: () => _press(false),
      onTap: widget.onOpen,
      child: AnimatedScale(
        scale: _pressed ? BiliMetrics.pressedScale : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(BiliMetrics.cardRadius),
          child: ColoredBox(
            color: BiliColors.card,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Cover(card: card),
                Padding(
                  padding: const EdgeInsets.only(left: BiliMetrics.cardInset, right: BiliMetrics.cardInset, top: 10),
                  child: SizedBox(
                    height: FeedCardSize.titleHeight(scaler),
                    child: Text(
                      card.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: BiliMetrics.cardTitleText, color: BiliColors.text, height: 1.3),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: BiliMetrics.cardInset, top: 9, bottom: 9),
                  child: SizedBox(
                    height: BiliMetrics.cardTagHeight,
                    child: Row(
                      children: [
                        _Badge(card: card),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            card.ownerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: BiliMetrics.cardFooterText,
                              color: BiliColors.secondaryText,
                            ),
                          ),
                        ),
                        _More(onWatchLater: widget.onWatchLater),
                      ],
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
        Hero(tag: 'cover-${card.bvid}', child: RemoteImage(card.cover)),
        const Align(
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
        Positioned(
          left: BiliMetrics.cardInset,
          right: BiliMetrics.cardInset,
          bottom: 6,
          child: DefaultTextStyle(
            style: const TextStyle(
              fontFamily: BiliFonts.family,
              fontSize: BiliMetrics.cardStatText,
              color: BiliColors.onCover,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
            maxLines: 1,
            child: Row(
              children: [
                const Icon(Icons.smart_display_outlined, size: BiliMetrics.cardStatIcon, color: BiliColors.onCover),
                const SizedBox(width: 3),
                Text(CountFormat.short(card.views)),
                const SizedBox(width: 10),
                const Icon(Icons.subtitles_outlined, size: BiliMetrics.cardStatIcon, color: BiliColors.onCover),
                const SizedBox(width: 3),
                Text(CountFormat.short(card.danmaku)),
                const Spacer(),
                Text(FeedCardView.duration(card.duration)),
              ],
            ),
          ),
        ),
      ],
    ),
  );
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

  @override
  Widget build(BuildContext context) => Container(
    height: BiliMetrics.cardTagHeight,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    alignment: Alignment.center,
    decoration: BoxDecoration(color: BiliColors.reasonTint, borderRadius: BorderRadius.circular(2)),
    child: Text(
      text,
      maxLines: 1,
      style: const TextStyle(fontSize: BiliMetrics.cardTagText, color: BiliColors.reason, height: 1),
    ),
  );
}

class UpBadge extends StatelessWidget {
  const UpBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
    height: 12,
    padding: const EdgeInsets.symmetric(horizontal: 2),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      border: Border.all(color: BiliColors.secondaryText),
      borderRadius: BorderRadius.circular(2.5),
    ),
    child: const Text(
      'UP',
      style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: BiliColors.secondaryText, height: 1),
    ),
  );
}

class _More extends StatelessWidget {
  const _More({required this.onWatchLater});

  final VoidCallback onWatchLater;

  @override
  Widget build(BuildContext context) => PopupMenuButton<void>(
    tooltip: '更多',
    padding: EdgeInsets.zero,
    iconSize: BiliMetrics.cardFooterText + 4,
    icon: const Icon(Icons.more_vert, color: BiliColors.secondaryText),
    constraints: const BoxConstraints(minWidth: 120),
    color: BiliColors.card,
    itemBuilder: (context) => [
      PopupMenuItem<void>(
        onTap: onWatchLater,
        child: const Row(
          children: [
            Icon(Icons.schedule, size: BiliMetrics.iconSize, color: BiliColors.text),
            SizedBox(width: BiliMetrics.rowGap),
            Text(
              '稍后再看',
              style: TextStyle(fontSize: BiliMetrics.bodyText, color: BiliColors.text),
            ),
          ],
        ),
      ),
    ],
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
                padding: const EdgeInsets.only(left: BiliMetrics.cardInset, right: BiliMetrics.cardInset * 3, top: 10),
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
              const Padding(
                padding: EdgeInsets.only(left: BiliMetrics.cardInset, top: 9, bottom: 9),
                child: SizedBox(
                  height: BiliMetrics.cardTagHeight,
                  child: FractionallySizedBox(widthFactor: 0.4, alignment: Alignment.centerLeft, child: _Bar()),
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

/// Sweeps a light band across [child] every 1.3 s.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))
    ..repeat();

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
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
