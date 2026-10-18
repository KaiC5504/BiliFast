import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';
import '../../video/player_session.dart';
import 'panel_parts.dart';

/// 选集: the parts of a video in parts, or else the 合集 section holding it (port of BiliNative `EpisodesPanel.swift`).
/// Dark cards at the right in landscape; in portrait the official app's light list (19).
class EpisodesPanel extends StatefulWidget {
  const EpisodesPanel({super.key, required this.session, required this.close, this.light = false});

  final PlayerSession session;
  final VoidCallback close;
  final bool light;

  @override
  State<EpisodesPanel> createState() => _EpisodesPanelState();
}

class _EpisodesPanelState extends State<EpisodesPanel> {
  final _current = GlobalKey();

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
    padding: const EdgeInsets.only(top: BiliMetrics.panelTop),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: BiliMetrics.panelGap,
      children: [
        const PanelHeader(title: '选集'),
        for (final (index, episode) in widget.session.episodes.indexed)
          PanelReveal(
            key: episode.current ? _current : null,
            order: index,
            child: PanelCardRow(title: episode.title, selected: episode.current, onTap: () => _choose(episode)),
          ),
      ],
    ),
  );

  Widget _light() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (index, episode) in widget.session.episodes.indexed)
        PanelReveal(
          key: episode.current ? _current : null,
          order: index,
          child: _LightRow(episode: episode, divider: index > 0, onTap: () => _choose(episode)),
        ),
    ],
  );
}

class _LightRow extends StatelessWidget {
  const _LightRow({required this.episode, required this.divider, required this.onTap});

  final Episode episode;
  final bool divider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = episode.current ? BiliColors.pink : BiliColors.text;
    return Semantics(
      button: true,
      selected: episode.current,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: BiliMetrics.sheetRowHeight),
          margin: const EdgeInsets.only(left: BiliMetrics.gutter),
          padding: const EdgeInsets.only(right: BiliMetrics.gutter),
          decoration: divider
              ? const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: BiliColors.divider, width: BiliMetrics.panelHairline),
                  ),
                )
              : null,
          child: Row(
            children: [
              if (episode.current) ...[
                Icon(Icons.equalizer, size: BiliMetrics.sheetPlayingIcon, color: color),
                const SizedBox(width: BiliMetrics.rowGap),
              ],
              Expanded(
                child: Text(
                  episode.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontWeight: episode.current ? FontWeight.w600 : FontWeight.w400),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The light sheet's title row: 选集 and the grey round close button.
class EpisodesSheetHeader extends StatelessWidget {
  const EpisodesSheetHeader({super.key, required this.close});

  final VoidCallback close;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: BiliMetrics.sheetHeaderHeight,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: BiliMetrics.gutter),
      child: Row(
        children: [
          const Text(
            '选集',
            style: TextStyle(fontSize: BiliMetrics.sheetTitleText, color: BiliColors.text),
          ),
          const Spacer(),
          Semantics(
            button: true,
            label: '关闭',
            child: GestureDetector(
              key: const ValueKey('sheet-close'),
              behavior: HitTestBehavior.opaque,
              onTap: close,
              child: Container(
                width: BiliMetrics.sheetClose,
                height: BiliMetrics.sheetClose,
                decoration: const BoxDecoration(color: BiliColors.pageGrey, shape: BoxShape.circle),
                child: const Icon(Icons.close, size: BiliMetrics.sheetCloseGlyph, color: BiliColors.sheetCloseGlyph),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
