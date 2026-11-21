import 'dart:async';

import 'package:bili_core/api.dart' show VideoDetail;
import 'package:bili_core/logic.dart' show CountFormat, TimeFormat;
import 'package:flutter/widgets.dart';

import '../../player_ui/end_screen_portrait.dart' show CountGlyph, CountPainter;
import '../../shared/theme.dart';
import '../intro/desc_text.dart';
import '../intro/intro_tab.dart' show IntroContent, IntroRetryLine;
import '../intro/title_block.dart' show IntroDescription, openDescriptionLink;
import 'intro/related_grid.dart';

/// The 竖屏 sheet's 简介 (265, 269, 271): the title, the stats line, the description as the page's 简介 draws it, then
/// 相关视频 as a two-column grid of at most [StoryIntroTheme.relatedLimit] cards under a heading that stays pinned
/// under the tab row, ending with 已经到底了…. Nothing shows until the detail arrives; a detail that never came leaves
/// 加载失败，点击重试, as the page's 简介 does. It scrolls with the sheet's primary scroll controller.
class StoryIntro extends StatelessWidget {
  const StoryIntro({
    super.key,
    required this.content,
    required this.onOpenRelated,
    required this.onSeek,
    required this.onOpenVideo,
  });

  final IntroContent content;

  /// A related card's tap: its index in [IntroContent.related].
  final ValueChanged<int> onOpenRelated;

  /// A timestamp in the description.
  final ValueChanged<double> onSeek;

  /// A video id in the description.
  final ValueChanged<String> onOpenVideo;

  @override
  Widget build(BuildContext context) {
    final detail = content.detail;
    final related = content.related.take(StoryIntroTheme.relatedLimit).toList();
    return CustomScrollView(
      key: const PageStorageKey('story-intro-scroll'),
      primary: true,
      slivers: [
        if (detail != null) ...[
          SliverToBoxAdapter(
            child: _Head(detail: detail, onSeek: onSeek, onOpenVideo: onOpenVideo),
          ),
          if (related.isNotEmpty) ...[
            const SliverPersistentHeader(pinned: true, delegate: _HeadingDelegate()),
            RelatedGrid(cards: related, onOpen: onOpenRelated),
            const SliverToBoxAdapter(child: _EndLine()),
          ],
          SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom)),
        ] else if (content.detailFailed && content.onRetryDetail != null)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: IntroRetryLine(onRetry: content.onRetryDetail!)),
          ),
      ],
    );
  }
}

TextStyle _style(double size, Color color, {double? line, FontWeight? weight}) => TextStyle(
  fontFamily: BiliFonts.family,
  fontFamilyFallback: BiliFonts.fallback,
  fontSize: size,
  height: (line ?? size) / size,
  leadingDistribution: TextLeadingDistribution.even,
  fontWeight: weight,
  color: color,
);

/// The title, the stats line and the description.
class _Head extends StatelessWidget {
  const _Head({required this.detail, required this.onSeek, required this.onOpenVideo});

  final VideoDetail detail;
  final ValueChanged<double> onSeek;
  final ValueChanged<String> onOpenVideo;

  @override
  Widget build(BuildContext context) {
    final title = _style(
      StoryIntroTheme.titleText,
      BiliColors.text,
      line: StoryIntroTheme.titleLine,
      weight: StoryIntroTheme.titleWeight,
    );
    final runs = descriptionRuns(detail.descParts);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BiliMetrics.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: StoryIntroTheme.titleTop),
          Padding(
            padding: const EdgeInsets.only(right: StoryIntroTheme.titleTrailing - BiliMetrics.gutter),
            child: Text(
              detail.title,
              key: const ValueKey('story-intro-title'),
              style: title,
              strutStyle: BiliFonts.strut(title),
            ),
          ),
          const SizedBox(height: StoryIntroTheme.statsGap),
          _StatsLine(detail: detail),
          if (runs.isNotEmpty) ...[
            const SizedBox(height: StoryIntroTheme.descTop),
            IntroDescription(
              runs: runs,
              onSeek: onSeek,
              onOpenVideo: onOpenVideo,
              onOpenLink: (link) => unawaited(openDescriptionLink(context, link)),
            ),
            const SizedBox(height: StoryIntroTheme.descBottom),
          ],
          const SizedBox(height: StoryIntroTheme.headingGap),
        ],
      ),
    );
  }
}

/// ▷ 6万  ☰ 109  2026年10月31日 12:06  BV1jzxz6gEYu, in the page's meta grey and glyphs; a line too long for the width
/// shrinks a little rather than cut, as the page's does.
class _StatsLine extends StatelessWidget {
  const _StatsLine({required this.detail});

  final VideoDetail detail;

  @override
  Widget build(BuildContext context) {
    final text = _style(IntroTheme.metaText, BiliColors.secondaryText, line: IntroTheme.metaLine);
    final strut = BiliFonts.strut(text);
    const icon = Size(IntroTheme.metaIconWidth, IntroTheme.metaIconHeight);
    return SizedBox(
      key: const ValueKey('story-intro-stats'),
      height: IntroTheme.metaLine,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            const SizedBox(width: IntroTheme.metaLead),
            CustomPaint(
              size: icon,
              painter: CountPainter(CountGlyph.views, color: BiliColors.secondaryText),
            ),
            const SizedBox(width: IntroTheme.metaIconGap),
            Text(CountFormat.short(detail.stat.view), style: text, strutStyle: strut),
            const SizedBox(width: StoryIntroTheme.statsIconGap),
            CustomPaint(
              size: icon,
              painter: CountPainter(CountGlyph.danmaku, color: BiliColors.secondaryText),
            ),
            const SizedBox(width: IntroTheme.metaIconGap),
            Text(CountFormat.short(detail.stat.danmaku), style: text, strutStyle: strut),
            const SizedBox(width: StoryIntroTheme.statsDateGap),
            Text(TimeFormat.publish(detail.pubdate), style: text, strutStyle: strut),
            const SizedBox(width: StoryIntroTheme.statsBvGap),
            Text(detail.bvid, style: text, strutStyle: strut),
          ],
        ),
      ),
    );
  }
}

/// 相关视频 on the sheet's ground, so the grid scrolls away under it once it reaches the tab row (271).
class _HeadingDelegate extends SliverPersistentHeaderDelegate {
  const _HeadingDelegate();

  @override
  double get minExtent => StoryIntroTheme.headingExtent;

  @override
  double get maxExtent => StoryIntroTheme.headingExtent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final style = _style(StoryIntroTheme.headingText, BiliColors.text, weight: StoryIntroTheme.headingWeight);
    return ColoredBox(
      key: const ValueKey('story-intro-heading'),
      color: BiliColors.card,
      child: Stack(
        children: [
          Positioned(
            left: BiliMetrics.gutter,
            right: BiliMetrics.gutter,
            top: StoryIntroTheme.headingCentre - StoryIntroTheme.headingText / 2,
            height: StoryIntroTheme.headingText,
            child: Text('相关视频', maxLines: 1, style: style, strutStyle: BiliFonts.strut(style)),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_HeadingDelegate oldDelegate) => false;
}

class _EndLine extends StatelessWidget {
  const _EndLine();

  @override
  Widget build(BuildContext context) {
    final style = _style(StoryIntroTheme.endText, BiliColors.secondaryText);
    return SizedBox(
      height: StoryIntroTheme.endHeight,
      child: Padding(
        padding: const EdgeInsets.only(top: StoryIntroTheme.endCentre - StoryIntroTheme.endText / 2),
        child: Align(
          alignment: Alignment.topCenter,
          child: Text(
            '已经到底了…',
            key: const ValueKey('story-intro-end'),
            style: style,
            strutStyle: BiliFonts.strut(style),
          ),
        ),
      ),
    );
  }
}
