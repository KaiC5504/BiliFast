import 'package:bili_core/api.dart' show Chapter;
import 'package:bili_core/logic.dart' show TimeFormat;
import 'package:flutter/widgets.dart';

import '../../shared/cover_placeholder.dart';
import '../../shared/remote_image.dart';
import '../../shared/theme.dart';
import '../../video/intro/collection_row.dart' show PlayingBars;
import '../../video/player_session.dart';
import 'panel_parts.dart';

/// 章节 (273): 章节进度条's switch over a row per chapter, its frame, title and range, the one playing pink after the
/// moving bars. A tap seeks to the chapter's start and closes. Landscape only; it fills the strip to the screen's edge
/// ([PanelFrame.edge]), its rows ending at the safe area.
class ChaptersPanel extends StatefulWidget {
  const ChaptersPanel({super.key, required this.session, required this.close});

  final PlayerSession session;
  final VoidCallback close;

  /// The chapter holding [seconds]: the last one starting at or before it, so the last holds the end too.
  static int? playingIndex(List<Chapter> chapters, double seconds) {
    int? index;
    for (final (i, chapter) in chapters.indexed) {
      if (chapter.from > seconds) break;
      index = i;
    }
    return index;
  }

  static String range(Chapter chapter) => '${TimeFormat.clock(chapter.from)} - ${TimeFormat.clock(chapter.to)}';

  @override
  State<ChaptersPanel> createState() => _ChaptersPanelState();
}

class _ChaptersPanelState extends State<ChaptersPanel> {
  final _playingRow = GlobalKey();
  int? _shownPlaying;

  @override
  void initState() {
    super.initState();
    _listen(widget.session);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_playingRow.currentContext case final row? when mounted) {
        Scrollable.ensureVisible(row, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
      }
    });
  }

  @override
  void didUpdateWidget(ChaptersPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.session, widget.session)) return;
    _unlisten(oldWidget.session);
    _listen(widget.session);
  }

  @override
  void dispose() {
    _unlisten(widget.session);
    super.dispose();
  }

  // The playhead moves ten times a second; only a chapter change redraws.
  void _listen(PlayerSession session) {
    session.readout.seconds.addListener(_moved);
    session.scrubbing.addListener(_moved);
  }

  void _unlisten(PlayerSession session) {
    session.readout.seconds.removeListener(_moved);
    session.scrubbing.removeListener(_moved);
  }

  int? get _playing => ChaptersPanel.playingIndex(widget.session.chapters, widget.session.position);

  void _moved() {
    if (mounted && _playing != _shownPlaying) setState(() {});
  }

  void _choose(Chapter chapter) {
    widget.session.commitSeek(chapter.from);
    widget.close();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final chapters = session.chapters;
    final playing = _shownPlaying = _playing;
    final safeRight = MediaQuery.paddingOf(context).right;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(on: session.chapterBar, toggle: () => session.setChapterBar(!session.chapterBar)),
        for (final (index, chapter) in chapters.indexed)
          PanelReveal(
            key: index == playing ? _playingRow : null,
            order: index,
            child: _ChapterRow(
              chapter: chapter,
              playing: index == playing,
              divider: index > 0,
              trailing: safeRight,
              onTap: () => _choose(chapter),
            ),
          ),
      ],
    );
  }
}

/// 章节 at the left; 章节进度条 and its switch at the right, the two one control.
class _Header extends StatelessWidget {
  const _Header({required this.on, required this.toggle});

  final bool on;
  final VoidCallback toggle;

  static Widget _label(String text, double size, Color color) => SizedBox(
    height: ChapterPanelTheme.labelBox,
    child: Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(fontSize: size, color: color),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => SizedBox(
    height: ChapterPanelTheme.listTop,
    child: Stack(
      children: [
        Positioned(
          left: ChapterPanelTheme.lead,
          top: ChapterPanelTheme.headerCentre - ChapterPanelTheme.labelBox / 2,
          child: _label(ChapterPanelTheme.title, ChapterPanelTheme.titleText, BiliColors.panelText),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          right: ChapterPanelTheme.switchRight,
          child: Semantics(
            toggled: on,
            label: '章节进度条',
            onTap: toggle,
            excludeSemantics: true,
            child: GestureDetector(
              key: const ValueKey('chapter-bar-switch'),
              behavior: HitTestBehavior.opaque,
              onTap: toggle,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      top: ChapterPanelTheme.headerCentre - ChapterPanelTheme.labelBox / 2,
                    ),
                    child: _label('章节进度条', ChapterPanelTheme.barLabelText, BiliColors.panelSecondary),
                  ),
                  const SizedBox(width: ChapterPanelTheme.switchGap),
                  Padding(
                    padding: const EdgeInsets.only(
                      top: ChapterPanelTheme.switchCentre - ChapterPanelTheme.switchHeight / 2,
                    ),
                    child: _ChapterSwitch(on: on),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// 273's switch: larger than ⋮'s [PanelSwitch], its knob a pill.
class _ChapterSwitch extends StatelessWidget {
  const _ChapterSwitch({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    const knobHeight = ChapterPanelTheme.switchHeight - 2 * ChapterPanelTheme.switchInset;
    final motion = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 200);
    return AnimatedContainer(
      duration: motion,
      curve: Curves.easeOutCubic,
      width: ChapterPanelTheme.switchWidth,
      height: ChapterPanelTheme.switchHeight,
      padding: const EdgeInsets.all(ChapterPanelTheme.switchInset),
      decoration: BoxDecoration(
        color: on ? ChapterPanelTheme.switchOn : ChapterPanelTheme.switchOff,
        borderRadius: BorderRadius.circular(ChapterPanelTheme.switchHeight / 2),
      ),
      child: AnimatedAlign(
        duration: motion,
        curve: Curves.easeOutCubic,
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: ChapterPanelTheme.switchKnobWidth,
          height: knobHeight,
          decoration: BoxDecoration(
            color: ChapterPanelTheme.switchKnob,
            borderRadius: BorderRadius.circular(knobHeight / 2),
          ),
        ),
      ),
    );
  }
}

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({
    required this.chapter,
    required this.playing,
    required this.divider,
    required this.trailing,
    required this.onTap,
  });

  final Chapter chapter;
  final bool playing;
  final bool divider;

  /// The safe area the row ends at.
  final double trailing;
  final VoidCallback onTap;

  static Widget _line(double centre, Widget child) => Positioned(
    left: 0,
    right: 0,
    top: centre - ChapterPanelTheme.lineBox / 2,
    height: ChapterPanelTheme.lineBox,
    child: Align(alignment: Alignment.centerLeft, child: child),
  );

  @override
  Widget build(BuildContext context) {
    final range = ChaptersPanel.range(chapter);
    final title = Text(
      chapter.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: ChapterPanelTheme.rowTitleText,
        color: playing ? ChapterPanelTheme.playing : BiliColors.panelText,
      ),
    );
    return Semantics(
      button: true,
      selected: playing,
      label: chapter.title,
      value: range,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          margin: EdgeInsets.only(left: ChapterPanelTheme.lead, right: trailing),
          padding: const EdgeInsets.only(top: ChapterPanelTheme.rowTop, bottom: ChapterPanelTheme.rowBottom),
          decoration: divider
              ? const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: BiliColors.panelHairline, width: BiliMetrics.panelHairline),
                  ),
                )
              : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: ChapterPanelTheme.frameWidth,
                height: ChapterPanelTheme.frameHeight,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(ChapterPanelTheme.frameRadius),
                  child: RemoteImage(
                    chapter.image,
                    size: const Size(ChapterPanelTheme.frameWidth, ChapterPanelTheme.frameHeight),
                    placeholder: const CoverPlaceholder(),
                  ),
                ),
              ),
              const SizedBox(width: ChapterPanelTheme.textGap),
              Expanded(
                child: SizedBox(
                  height: ChapterPanelTheme.frameHeight,
                  child: Stack(
                    children: [
                      _line(
                        ChapterPanelTheme.rowTitleCentre,
                        playing
                            ? Row(
                                children: [
                                  const SizedBox(width: ChapterPanelTheme.barsLead),
                                  Transform.translate(
                                    offset: const Offset(
                                      0,
                                      ChapterPanelTheme.barsCentre - ChapterPanelTheme.rowTitleCentre,
                                    ),
                                    child: const PlayingBars(
                                      color: ChapterPanelTheme.barsInk,
                                      height: ChapterPanelTheme.barsHeight,
                                    ),
                                  ),
                                  const SizedBox(width: ChapterPanelTheme.barsGap),
                                  Flexible(child: title),
                                ],
                              )
                            : title,
                      ),
                      _line(
                        ChapterPanelTheme.rangeCentre,
                        Text(
                          range,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: ChapterPanelTheme.rangeText,
                            color: BiliColors.panelSecondary,
                          ),
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
}
