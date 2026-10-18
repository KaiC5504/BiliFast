import 'package:bili_core/api.dart' show UgcSeason;
import 'package:bili_core/logic.dart' show CountFormat, TimeFormat;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../shared/action_glyphs.dart';
import '../../shared/remote_image.dart';
import '../../shared/theme.dart';
import '../../video/actions/video_actions.dart';
import '../../video/page_details.dart';
import '../../video/player_session.dart';
import 'panel_glyphs.dart';
import 'panel_parts.dart';

/// 选集: the parts of a video in parts, or else the 合集 section holding it (port of BiliNative `EpisodesPanel.swift`).
/// Dark cards at the right in landscape; in portrait the official app's light sheet (19), which this fills below its
/// grabber, with the 合集's share circle and 收藏 once the page's actions exist.
class EpisodesPanel extends StatefulWidget {
  const EpisodesPanel({super.key, required this.session, required this.close, this.details, this.light = false});

  final PlayerSession session;
  final VoidCallback close;
  final bool light;

  /// The page's actions for the 合集's share and 收藏; null outside a video page.
  final PageDetails? details;

  /// The cover rows' date: month and day this year, with the year before that.
  static String date(int unix, {DateTime? now}) {
    final day = DateTime.fromMillisecondsSinceEpoch(unix * 1000);
    final year = (now ?? DateTime.now()).year == day.year ? '' : '${day.year}年';
    return '$year${day.month}月${day.day}日';
  }

  @override
  State<EpisodesPanel> createState() => _EpisodesPanelState();
}

class _EpisodesPanelState extends State<EpisodesPanel> {
  final _current = GlobalKey();
  var _reversed = false;
  var _introOpen = false;

  @override
  void initState() {
    super.initState();
    // A long list opens on the one playing rather than at P1.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_current.currentContext case final current? when mounted) {
        Scrollable.ensureVisible(current, alignment: 0.3);
      }
    });
  }

  void _choose(Episode episode) {
    if (!episode.current) widget.session.playEpisode(episode);
    widget.close();
  }

  @override
  Widget build(BuildContext context) => widget.light ? _light() : _dark();

  Widget _dark() => Padding(
    padding: const EdgeInsets.only(top: BiliMetrics.panelHeaderTop),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PanelHeader(title: '选集'),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: BiliMetrics.panelGap,
          children: [
            for (final (index, episode) in widget.session.episodes.indexed)
              PanelReveal(
                key: episode.current ? _current : null,
                order: index,
                child: PanelCardRow(
                  title: episode.title,
                  selected: episode.current,
                  trailing: switch (episode.duration) {
                    final seconds? when seconds > 0 => Text(
                      TimeFormat.clock(seconds.toDouble()),
                      style: const TextStyle(fontSize: BiliMetrics.panelDetailText, color: BiliColors.panelSecondary),
                    ),
                    _ => null,
                  },
                  onTap: () => _choose(episode),
                ),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _light() {
    final session = widget.session;
    final UgcSeason? season = session.episodesAreParts ? null : session.detail?.season;
    final episodes = _reversed ? session.episodes.reversed.toList() : session.episodes;
    final title = season == null || season.title.isEmpty ? '选集' : season.title;
    final header = EpisodesSheetHeader(title: title, close: widget.close);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (season == null)
          header
        else
          // The list starts a little into the header's empty bottom, so the share circle's top isn't clipped.
          SizedBox(
            height: BiliMetrics.sheetHeaderHeight - VerticalActionTheme.sheetLift,
            child: OverflowBox(alignment: Alignment.topCenter, maxHeight: BiliMetrics.sheetHeaderHeight, child: header),
          ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + BiliMetrics.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (season != null) ...[_seasonTop(season.intro), _section()],
                for (final (index, episode) in episodes.indexed)
                  PanelReveal(
                    key: episode.current ? _current : null,
                    order: index,
                    child: season == null
                        ? _PartRow(episode: episode, divider: index > 0, onTap: () => _choose(episode))
                        : _CoverRow(
                            episode: episode,
                            top: index == 0 ? BiliMetrics.sheetListTop : BiliMetrics.sheetRowPad,
                            divider: index > 0,
                            onTap: () => _choose(episode),
                          ),
                  ),
                if (season != null) ...[
                  const SizedBox(height: BiliMetrics.sheetFooterTop),
                  const Text('内容到底啦', textAlign: TextAlign.center, style: _footer),
                  const SizedBox(height: BiliMetrics.sheetFooterGap),
                  const Text('仅展示本App中可查看的稿件', textAlign: TextAlign.center, style: _footer),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  static const _footer = TextStyle(
    fontSize: BiliMetrics.sheetFooterText,
    height: BiliMetrics.sheetLineHeight,
    color: BiliColors.sheetHint,
  );

  static const _introStyle = TextStyle(
    fontSize: BiliMetrics.sheetIntroText,
    height: BiliMetrics.sheetLineHeight,
    color: BiliColors.secondaryText,
  );

  static const _more = TextStyle(color: BiliColors.text);

  /// The description with the share circle and 收藏 at the right of its first line, which keeps their height even
  /// with no description.
  Widget _seasonTop(String intro) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: VerticalActionTheme.sheetShare),
    child: Stack(
      children: [
        if (intro.isEmpty) const SizedBox(width: double.infinity) else _intro(intro),
        Positioned(
          top: 0,
          right: BiliMetrics.gutter,
          height: VerticalActionTheme.sheetShare,
          child: _SeasonActions(details: widget.details),
        ),
      ],
    ),
  );

  /// The 合集's description on one line ending in 展开, leaving the right for the share circle and 收藏.
  Widget _intro(String intro) => Padding(
    padding: const EdgeInsets.only(
      left: BiliMetrics.gutter,
      right: BiliMetrics.sheetIntroTrailing,
      top: BiliMetrics.sheetIntroTop + VerticalActionTheme.sheetLift,
    ),
    child: Semantics(
      button: true,
      child: GestureDetector(
        key: const ValueKey('sheet-intro'),
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _introOpen = !_introOpen),
        child: _introOpen
            ? Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '$intro '),
                    const TextSpan(text: '收起', style: _more),
                  ],
                ),
                style: _introStyle,
              )
            : Row(
                children: [
                  Flexible(
                    child: Text(intro, maxLines: 1, overflow: TextOverflow.ellipsis, style: _introStyle),
                  ),
                  Text('展开', style: _introStyle.merge(_more)),
                ],
              ),
      ),
    ),
  );

  Widget _section() => Padding(
    padding: const EdgeInsets.only(
      left: BiliMetrics.sheetSectionLead,
      right: BiliMetrics.sheetOrderTrailing,
      top: BiliMetrics.sheetSectionTop,
    ),
    child: SizedBox(
      height: BiliMetrics.sheetSectionHeight,
      child: Row(
        children: [
          const Text(
            '选集',
            style: TextStyle(
              fontSize: BiliMetrics.sheetSectionText,
              height: BiliMetrics.sheetLineHeight,
              color: BiliColors.text,
            ),
          ),
          const Spacer(),
          Semantics(
            button: true,
            child: GestureDetector(
              key: const ValueKey('sheet-order'),
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _reversed = !_reversed),
              child: SizedBox(
                height: BiliMetrics.sheetSectionHeight,
                child: Row(
                  spacing: BiliMetrics.sheetOrderGap,
                  children: [
                    const PanelGlyph(PanelGlyphKind.order, color: BiliColors.secondaryText),
                    Text(_reversed ? '倒序' : '正序', style: _introStyle),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// 19's grey share circle and pink 收藏 (★ 已收藏 once subscribed), once the actions exist. While the relation
/// hasn't answered, 收藏 is dimmed and does nothing.
class _SeasonActions extends StatelessWidget {
  const _SeasonActions({required this.details});

  final PageDetails? details;

  @override
  Widget build(BuildContext context) {
    final details = this.details;
    if (details == null) return const SizedBox.shrink();
    final still = MediaQuery.disableAnimationsOf(context);
    return ListenableBuilder(
      listenable: details,
      builder: (context, _) {
        final actions = details.actions;
        return AnimatedSwitcher(
          duration: still ? Duration.zero : const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          layoutBuilder: (current, previous) =>
              Stack(alignment: Alignment.centerRight, children: [...previous, ?current]),
          child: actions == null
              ? const SizedBox.shrink()
              : ListenableBuilder(
                  key: ObjectKey(actions),
                  listenable: actions,
                  builder: (context, _) => _row(actions, still: still),
                ),
        );
      },
    );
  }

  Widget _row(VideoActions actions, {required bool still}) {
    final subscribed = actions.seasonFavourited;
    final on = subscribed ?? false;
    final label = on ? '已收藏' : '收藏';
    final colour = on ? VerticalActionTheme.sheetSubscribedLabel : VerticalActionTheme.sheetPillLabel;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SheetTap(
          key: const ValueKey('sheet-share'),
          label: '分享',
          onTap: () => actions.ask(ActionPrompt.share),
          child: Container(
            width: VerticalActionTheme.sheetShare,
            height: VerticalActionTheme.sheetShare,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: BiliColors.pageGrey, shape: BoxShape.circle),
            child: const ActionIcon(
              ActionGlyph.share,
              solid: false,
              size: VerticalActionTheme.sheetShareGlyph,
              color: BiliColors.text,
            ),
          ),
        ),
        const SizedBox(width: VerticalActionTheme.sheetGap),
        _SheetTap(
          key: const ValueKey('sheet-favourite'),
          label: label,
          onTap: subscribed == null ? null : actions.toggleSeasonFavourite,
          child: AnimatedOpacity(
            opacity: subscribed == null ? VerticalActionTheme.sheetUnknownOpacity : 1,
            duration: still ? Duration.zero : const Duration(milliseconds: 200),
            child: AnimatedContainer(
              duration: still ? Duration.zero : const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              height: VerticalActionTheme.sheetPillHeight,
              padding: const EdgeInsets.symmetric(horizontal: VerticalActionTheme.sheetPillPad),
              decoration: ShapeDecoration(
                color: on ? VerticalActionTheme.sheetSubscribedFill : VerticalActionTheme.sheetPill,
                shape: const StadiumBorder(),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ActionIcon(ActionGlyph.favourite, solid: on, size: VerticalActionTheme.sheetStar, color: colour),
                  const SizedBox(width: VerticalActionTheme.sheetStarGap),
                  Transform.translate(
                    offset: Offset(0, VerticalActionTheme.sheetPillTextDrop),
                    child: Text(
                      label,
                      style: TextStyle(fontSize: VerticalActionTheme.sheetPillText, height: 1, color: colour),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A button in the light sheet: shrinks under the finger and answers accessibility presses; inert without [onTap].
class _SheetTap extends StatefulWidget {
  const _SheetTap({super.key, required this.label, required this.onTap, required this.child});

  final String label;
  final VoidCallback? onTap;
  final Widget child;

  @override
  State<_SheetTap> createState() => _SheetTapState();
}

class _SheetTapState extends State<_SheetTap> {
  var _pressed = false;

  void _press(bool pressed) {
    if (_pressed != pressed && widget.onTap != null) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: widget.onTap != null,
    label: widget.label,
    onTap: widget.onTap,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _press(true),
      onTapUp: (_) => _press(false),
      onTapCancel: () => _press(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? BiliMetrics.chromePressedScale : 1,
        duration: Duration(milliseconds: _pressed ? 90 : 260),
        curve: _pressed ? Curves.easeOut : Curves.elasticOut,
        child: widget.child,
      ),
    ),
  );
}

/// A 合集 episode as 19 draws it: the cover with its duration, then the title, the date and the counts.
class _CoverRow extends StatelessWidget {
  const _CoverRow({required this.episode, required this.top, required this.divider, required this.onTap});

  final Episode episode;
  final double top;
  final bool divider;
  final VoidCallback onTap;

  static TextStyle get _meta => TextStyle(
    fontSize: BiliMetrics.sheetMetaText,
    height: BiliMetrics.sheetLineHeight,
    letterSpacing: BiliMetrics.sheetMetaSpacing,
    color: BiliColors.secondaryText,
  );

  @override
  Widget build(BuildContext context) {
    final playing = episode.current;
    final duration = episode.duration;
    final pubdate = episode.pubdate;
    return Semantics(
      button: true,
      selected: playing,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(left: BiliMetrics.gutter),
          padding: EdgeInsets.only(top: top, bottom: BiliMetrics.sheetRowPad, right: BiliMetrics.gutter),
          decoration: divider ? const BoxDecoration(border: Border(top: _divider)) : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: BiliMetrics.sheetCoverGap,
            children: [
              SizedBox(
                width: BiliMetrics.sheetCoverWidth,
                height: BiliMetrics.sheetCoverHeight,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(BiliMetrics.cardRadius),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RemoteImage(
                        episode.cover,
                        size: const Size(BiliMetrics.sheetCoverWidth, BiliMetrics.sheetCoverHeight),
                      ),
                      if (duration != null && duration > 0)
                        Positioned(
                          right: BiliMetrics.sheetBadgeInsetX,
                          bottom: BiliMetrics.sheetBadgeInsetY,
                          height: BiliMetrics.sheetBadgeHeight,
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: BiliMetrics.sheetBadgePad),
                            decoration: BoxDecoration(
                              color: BiliColors.coverShade,
                              borderRadius: BorderRadius.circular(BiliMetrics.sheetBadgeRadius),
                            ),
                            child: Text(
                              TimeFormat.clock(duration.toDouble()),
                              style: const TextStyle(
                                fontSize: BiliMetrics.sheetBadgeText,
                                height: 1,
                                color: BiliColors.onCover,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: SizedBox(
                  height: BiliMetrics.sheetCoverHeight,
                  child: Stack(
                    children: [
                      Positioned(
                        top: BiliMetrics.sheetEpisodeTitleTop,
                        left: 0,
                        right: 0,
                        child: Text.rich(
                          TextSpan(
                            children: [
                              if (playing)
                                const WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      top: BiliMetrics.sheetPlayingDrop,
                                      left: BiliMetrics.sheetPlayingLead,
                                      right: BiliMetrics.sheetPlayingGap,
                                    ),
                                    child: PanelGlyph(PanelGlyphKind.playing, color: BiliColors.pink),
                                  ),
                                ),
                              TextSpan(text: episode.title),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: BiliMetrics.sheetEpisodeTitleText,
                            height: BiliMetrics.sheetEpisodeTitleLine / BiliMetrics.sheetEpisodeTitleText,
                            color: playing ? BiliColors.pink : BiliColors.text,
                          ),
                        ),
                      ),
                      if (pubdate != null && pubdate > 0)
                        _line(BiliMetrics.sheetDateCentre, Text(EpisodesPanel.date(pubdate), style: _meta)),
                      _line(
                        BiliMetrics.sheetCountsCentre,
                        Row(
                          children: [
                            const SizedBox(width: BiliMetrics.sheetCountLead),
                            const PanelGlyph(PanelGlyphKind.views, color: BiliColors.secondaryText),
                            const SizedBox(width: BiliMetrics.sheetCountGap),
                            _count(episode.views),
                            const SizedBox(width: BiliMetrics.sheetCountSpacing),
                            const PanelGlyph(PanelGlyphKind.danmaku, color: BiliColors.secondaryText),
                            const SizedBox(width: BiliMetrics.sheetCountGap),
                            _count(episode.danmaku),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _count(int? count) => Transform.translate(
    offset: Offset(0, BiliMetrics.sheetCountTextDrop),
    child: Text(CountFormat.short(count ?? 0), style: _meta),
  );

  /// A line of text centred [centre] below the cover's top.
  static Widget _line(double centre, Widget child) => Positioned(
    left: 0,
    right: 0,
    top: centre - BiliMetrics.sheetMetaLine / 2,
    height: BiliMetrics.sheetMetaLine,
    child: Align(alignment: Alignment.centerLeft, child: child),
  );
}

const _divider = BorderSide(color: BiliColors.divider, width: BiliMetrics.panelHairline);

/// A part: no cover, its title and duration.
class _PartRow extends StatelessWidget {
  const _PartRow({required this.episode, required this.divider, required this.onTap});

  final Episode episode;
  final bool divider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final playing = episode.current;
    final color = playing ? BiliColors.pink : BiliColors.text;
    final duration = episode.duration;
    return Semantics(
      button: true,
      selected: playing,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: BiliMetrics.sheetRowHeight),
          margin: const EdgeInsets.only(left: BiliMetrics.gutter),
          padding: const EdgeInsets.only(right: BiliMetrics.gutter),
          decoration: divider ? const BoxDecoration(border: Border(top: _divider)) : null,
          child: Row(
            children: [
              if (playing) ...[
                const PanelGlyph(PanelGlyphKind.playing, color: BiliColors.pink),
                const SizedBox(width: BiliMetrics.sheetPlayingGap),
              ],
              Expanded(
                child: Text(
                  episode.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: BiliMetrics.sheetEpisodeTitleText, color: color),
                ),
              ),
              if (duration != null && duration > 0) ...[
                const SizedBox(width: BiliMetrics.rowGap),
                Text(
                  TimeFormat.clock(duration.toDouble()),
                  style: const TextStyle(fontSize: BiliMetrics.sheetMetaText, color: BiliColors.secondaryText),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The light sheet's title row: the 合集's name (选集 for parts) and the grey round close button, its touch 44 square.
class EpisodesSheetHeader extends StatelessWidget {
  const EpisodesSheetHeader({super.key, required this.title, required this.close});

  final String title;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: BiliMetrics.sheetHeaderHeight,
    child: Padding(
      padding: const EdgeInsets.only(
        left: BiliMetrics.gutter,
        right: BiliMetrics.gutter - (BiliMetrics.panelHitBox - BiliMetrics.sheetClose) / 2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: BiliMetrics.sheetTitleText, color: BiliColors.text),
            ),
          ),
          Semantics(
            button: true,
            label: '关闭',
            child: GestureDetector(
              key: const ValueKey('sheet-close'),
              behavior: HitTestBehavior.opaque,
              onTap: close,
              child: SizedBox.square(
                dimension: BiliMetrics.panelHitBox,
                child: Center(
                  child: Container(
                    width: BiliMetrics.sheetClose,
                    height: BiliMetrics.sheetClose,
                    decoration: const BoxDecoration(color: BiliColors.pageGrey, shape: BoxShape.circle),
                    child: const Icon(
                      Icons.close,
                      size: BiliMetrics.sheetCloseGlyph,
                      color: BiliColors.sheetCloseGlyph,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
