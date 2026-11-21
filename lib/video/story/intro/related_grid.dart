import 'package:bili_core/api.dart' show VideoCard;
import 'package:bili_core/logic.dart' show CountFormat, TimeFormat;
import 'package:flutter/widgets.dart';

import '../../../shared/cover_placeholder.dart';
import '../../../shared/remote_image.dart';
import '../../../shared/theme.dart';

/// 相关视频's two columns of cards (265, 271), as a sliver: the cover with its counts and duration, a title of up to
/// two lines and the uploader. A tap gives the card's index in [cards].
class RelatedGrid extends StatelessWidget {
  const RelatedGrid({super.key, required this.cards, required this.onOpen});

  final List<VideoCard> cards;
  final ValueChanged<int> onOpen;

  /// A column's width on a list [width] wide: whole points, as the official grid's 203 on a 440 pt screen.
  static double cardWidth(double width) =>
      ((width - 2 * StoryIntroTheme.gridInset - StoryIntroTheme.gridGap) / 2).floorToDouble();

  @override
  Widget build(BuildContext context) {
    final pixels = MediaQuery.devicePixelRatioOf(context);
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = cardWidth(constraints.crossAxisExtent);
        final cover = Size(width, (width / StoryIntroTheme.coverAspect * pixels).roundToDouble() / pixels);
        return SliverFixedExtentList.builder(
          itemExtent: cover.height + StoryIntroTheme.cardBelowCover,
          itemCount: (cards.length + 1) ~/ 2,
          itemBuilder: (context, row) => Stack(
            children: [
              for (final column in const [0, 1])
                if (row * 2 + column < cards.length)
                  Positioned(
                    left: StoryIntroTheme.gridInset + column * (width + StoryIntroTheme.gridGap),
                    top: 0,
                    bottom: 0,
                    width: width,
                    child: _Card(
                      key: ValueKey(('story-related', row * 2 + column)),
                      card: cards[row * 2 + column],
                      cover: cover,
                      onTap: () => onOpen(row * 2 + column),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({super.key, required this.card, required this.cover, required this.onTap});

  final VideoCard card;
  final Size cover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = TextStyle(
      fontFamily: BiliFonts.family,
      fontFamilyFallback: BiliFonts.fallback,
      fontSize: StoryIntroTheme.cardTitleText,
      height: StoryIntroTheme.cardTitleLine / StoryIntroTheme.cardTitleText,
      leadingDistribution: TextLeadingDistribution.even,
      color: BiliColors.text,
    );
    final name = TextStyle(
      fontFamily: BiliFonts.family,
      fontFamilyFallback: BiliFonts.fallback,
      fontSize: StoryIntroTheme.upText,
      height: StoryIntroTheme.upLine / StoryIntroTheme.upText,
      leadingDistribution: TextLeadingDistribution.even,
      color: BiliColors.secondaryText,
    );
    return Semantics(
      button: true,
      label: card.title,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: cover.width,
              height: cover.height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(StoryIntroTheme.coverRadius),
                child: _Cover(card: card, size: cover),
              ),
            ),
            Positioned(
              left: StoryIntroTheme.cardTitleInset,
              right: StoryIntroTheme.cardTitleInset,
              top: cover.height + StoryIntroTheme.cardTitleTop,
              child: Text(
                card.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: title,
                strutStyle: BiliFonts.strut(title),
              ),
            ),
            Positioned(
              left: StoryIntroTheme.upLead,
              right: StoryIntroTheme.cardTitleInset,
              top: cover.height + StoryIntroTheme.upCentre - StoryIntroTheme.upLine / 2,
              height: StoryIntroTheme.upLine,
              child: Row(
                children: [
                  Image.asset(
                    'assets/images/card/up_badge.png',
                    width: StoryIntroTheme.upIconWidth,
                    height: StoryIntroTheme.upIconHeight,
                    color: BiliColors.secondaryText,
                    colorBlendMode: BlendMode.srcIn,
                    excludeFromSemantics: true,
                  ),
                  const SizedBox(width: StoryIntroTheme.upGap),
                  Flexible(
                    child: Text(
                      card.ownerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: name,
                      strutStyle: BiliFonts.strut(name),
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
}

/// The picture decoded at [size], its shade, and the counts and the duration over its foot.
class _Cover extends StatelessWidget {
  const _Cover({required this.card, required this.size});

  final VideoCard card;
  final Size size;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      RemoteImage(
        card.cover,
        cover: true,
        size: size,
        placeholder: const CoverPlaceholder(),
        fadeIn: false,
        overlay: const Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: StoryIntroTheme.shadeHeight,
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: StoryIntroTheme.shade,
                ),
              ),
            ),
          ),
        ),
      ),
      Positioned(
        left: StoryIntroTheme.statLead,
        right: StoryIntroTheme.statTrail,
        bottom: 0,
        height: StoryIntroTheme.statCentre * 2,
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: BiliFonts.family,
            fontFamilyFallback: BiliFonts.fallback,
            fontSize: StoryIntroTheme.statText,
            height: 1,
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
                    const _StatIcon('assets/images/card/stat_play.png'),
                    const SizedBox(width: StoryIntroTheme.statIconGap),
                    Flexible(child: _StatText(CountFormat.short(card.views))),
                    const SizedBox(width: StoryIntroTheme.statGap),
                    const _StatIcon('assets/images/card/stat_danmaku.png'),
                    const SizedBox(width: StoryIntroTheme.statIconGap),
                    Flexible(child: _StatText(CountFormat.short(card.danmaku))),
                  ],
                ),
              ),
              if (card.duration > 0) _StatText(TimeFormat.clock(card.duration.toDouble())),
            ],
          ),
        ),
      ),
    ],
  );
}

class _StatIcon extends StatelessWidget {
  const _StatIcon(this.asset);

  final String asset;

  @override
  Widget build(BuildContext context) => Image.asset(
    asset,
    width: StoryIntroTheme.statIconWidth,
    height: StoryIntroTheme.statIconHeight,
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
      Transform.translate(offset: const Offset(0, StoryIntroTheme.statTextDrop), child: Text(text));
}
