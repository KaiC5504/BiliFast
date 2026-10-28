import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/api.dart' show BiliClient, Chapter, VideoShot;
import 'package:bili_core/devlog.dart' show LogCategory, Logger;
import 'package:bili_core/logic.dart' show TimeFormat;
import 'package:flutter/widgets.dart';

import '../shared/theme.dart';
import '../video/player_session.dart';
import 'player_hud.dart' show SpeedArrows;

/// The frame and time over the middle of landscape while the bar is dragged (102), above 竖屏's bar ([upright]), or
/// over the iPad's thumb ([padBar]). Before the frames arrive, for a part without them, or where a frame's sheet failed
/// to load, the time shows alone in its place.
class SeekPreview extends StatefulWidget {
  const SeekPreview({super.key, required this.session, required this.shown, this.upright = false, this.padBar});

  final PlayerSession session;
  final bool shown;

  /// 竖屏's (19, 20): the frame in the video's orientation above the bar, the time under it.
  final bool upright;

  /// The iPad's full screen (recording 24): the [SeekBar]'s box in this preview's own space. The frame follows the TV
  /// above it, with the arrows and the time inside it and the chapter's title over it.
  final Rect? padBar;

  @override
  State<SeekPreview> createState() => _SeekPreviewState();
}

class _SeekPreviewState extends State<SeekPreview> {
  VideoShot? _warmed;

  /// [_warmed]'s sheets that failed to load.
  final _failed = <String>{};

  /// Frames whose failure was logged: one set per part, so a part logs once whichever presentation's preview finds it.
  static final _logged = Expando<bool>();

  /// Built only while shown or fading out, so it doesn't rebuild with every tick of the playhead behind the controls.
  late bool _built = widget.shown;

  @override
  void didUpdateWidget(SeekPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shown) _built = true;
  }

  /// Every sheet is fetched as the frames arrive, so dragging across them never waits on one.
  void _warm(VideoShot? shot) {
    if (shot == null || identical(shot, _warmed)) return;
    _warmed = shot;
    _failed.clear();
    for (final sheet in shot.sheets) {
      precacheImage(
        NetworkImage(sheet, headers: BiliClient.mediaHeaders),
        context,
        onError: (_, _) => _sheetFailed(shot, sheet),
      );
    }
  }

  // The error's text carries the sheet's address, so only the part is logged.
  void _sheetFailed(VideoShot shot, String sheet) {
    if (!identical(shot, _warmed) || !_failed.add(sheet)) return;
    if (_logged[shot] == null) {
      _logged[shot] = true;
      Logger.shared.warn(LogCategory.ui, 'seek sheet failed', {'cid': ?widget.session.part?.cid});
    }
    // The frame's errorBuilder reports while building.
    scheduleMicrotask(() {
      if (mounted) setState(() {});
    });
  }

  ({String sheet, int column, int row})? _frameAt(VideoShot? shot, double position) {
    final frame = shot?.frameAt(position);
    return frame == null || _failed.contains(frame.sheet) ? null : frame;
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: AnimatedOpacity(
          key: const ValueKey('seek-preview'),
          opacity: widget.shown ? 1 : 0,
          duration: SeekPreviewTheme.fade,
          curve: Curves.easeOut,
          onEnd: () {
            if (!widget.shown && _built) setState(() => _built = false);
          },
          child: !_built
              ? const SizedBox.shrink()
              : ValueListenableBuilder<VideoShot?>(
                  valueListenable: session.seekFrames,
                  builder: (context, shot, _) {
                    _warm(shot);
                    return ListenableBuilder(
                      listenable: Listenable.merge([session.scrubbing, session.readout.seconds, session.duration]),
                      builder: (context, _) => switch (widget.padBar) {
                        final bar? => _padLayout(context, bar, shot, session.position, session.duration.value),
                        null when widget.upright => _uprightLayout(
                          context,
                          shot,
                          session.position,
                          session.duration.value,
                        ),
                        null => _layout(context, shot, session.position, session.duration.value),
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _layout(BuildContext context, VideoShot? shot, double position, double duration) {
    final top = MediaQuery.sizeOf(context).height / 2 - SeekPreviewTheme.aboveMiddle;
    final frame = _frameAt(shot, position);
    const border = SeekPreviewTheme.border * 2;
    final size = shot == null ? null : _frameSize(shot);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (shot != null && frame != null && size != null)
          Positioned(
            top: top,
            left: 0,
            right: 0,
            child: Center(
              child: _frame(shot, frame, box: size, cell: size),
            ),
          ),
        Positioned(
          top: top + SeekPreviewTheme.frameHeight + border + SeekPreviewTheme.timeGap,
          left: 0,
          right: 0,
          child: _time(position, duration, upright: false),
        ),
      ],
    );
  }

  /// 竖屏's: the frame and the time over its bottom rows, the time kept in its place with or without the frame.
  Widget _uprightLayout(BuildContext context, VideoShot? shot, double position, double duration) {
    final frame = _frameAt(shot, position);
    const border = SeekPreviewTheme.border * 2;
    final outer = widget.session.isVertical
        ? const Size(SeekPreviewTheme.uprightShort, SeekPreviewTheme.uprightLong)
        : const Size(SeekPreviewTheme.uprightLong, SeekPreviewTheme.uprightShort);
    final box = Size(outer.width - border, outer.height - border);
    // Where VerticalChrome sets its bottom rows, so the frame keeps its distance from the bar.
    final rows = math.max(MediaQuery.paddingOf(context).bottom - BiliMetrics.verticalBottomDrop, 0.0);
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: rows + SeekPreviewTheme.uprightTimeLift,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (shot != null && frame != null) ...[
                _frame(shot, frame, box: box, cell: _cover(shot, box)),
                const SizedBox(height: SeekPreviewTheme.uprightTimeGap),
              ],
              _time(position, duration, upright: true),
            ],
          ),
        ),
      ],
    );
  }

  /// The iPad's: everything centred a little left of the TV, kept on the screen.
  Widget _padLayout(BuildContext context, Rect bar, VideoShot? shot, double position, double duration) {
    final width = MediaQuery.sizeOf(context).width;
    const thumbWidth = BiliMetrics.thumbWidth;
    final travel = math.max(bar.width - thumbWidth, 1.0);
    final fraction = duration > 0 && position.isFinite ? (position / duration).clamp(0.0, 1.0) : 0.0;
    final thumb = bar.left + thumbWidth / 2 + travel * fraction;
    final frame = _frameAt(shot, position);
    final size = shot == null ? null : _padFrameSize(shot);
    final boxWidth = size?.width ?? PadFullScreenTheme.previewWidth;
    final boxHeight = size?.height ?? PadFullScreenTheme.previewHeight;
    final half = boxWidth / 2;
    const edge = PadFullScreenTheme.previewEdge;
    final centre = (thumb - PadFullScreenTheme.previewShift)
        .clamp(edge + half, math.max(width - edge - half, edge + half))
        .toDouble();
    final bottom = bar.center.dy - PadFullScreenTheme.previewAboveBar;
    final title = _chapterAt(widget.session.chapters, position);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (shot != null && frame != null && size != null)
          Positioned(
            left: centre - half,
            top: bottom - boxHeight,
            child: Container(
              key: const ValueKey('seek-preview-frame'),
              width: size.width,
              height: size.height,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(PadFullScreenTheme.previewRadius)),
              child: _Cell(
                shot: shot,
                sheet: frame.sheet,
                column: frame.column,
                row: frame.row,
                box: size,
                cell: size,
                onFailed: () => _sheetFailed(shot, frame.sheet),
              ),
            ),
          ),
        // Inside the frame, or where the frame would be.
        Positioned(
          left: centre - half,
          width: boxWidth,
          top: bottom - PadFullScreenTheme.previewTimeRise - PadFullScreenTheme.previewTimeText,
          height: PadFullScreenTheme.previewTimeText * 2,
          child: Center(child: _padTime(position, duration)),
        ),
        if (title != null)
          Positioned(
            left: 0,
            right: 0,
            top: bottom - boxHeight - PadFullScreenTheme.previewTitleGap - PadFullScreenTheme.previewTitleHeight,
            height: PadFullScreenTheme.previewTitleHeight,
            child: CustomSingleChildLayout(
              delegate: _Centred(centre, edge: edge),
              child: _PadChapterTitle(key: const ValueKey('seek-preview-chapter'), title: title),
            ),
          ),
      ],
    );
  }

  /// 24 runs the time into the duration after the hold's arrows, all white.
  Widget _padTime(double position, double duration) => Row(
    key: const ValueKey('seek-preview-time'),
    mainAxisSize: MainAxisSize.min,
    children: [
      const SpeedArrows(
        width: PadFullScreenTheme.hudArrowWidth,
        height: PadFullScreenTheme.hudArrowHeight,
        step: PadFullScreenTheme.hudArrowStep,
        slide: false,
      ),
      const SizedBox(width: PadFullScreenTheme.previewArrowGap),
      Text(
        '${TimeFormat.clock(position)}/${TimeFormat.clock(duration)}',
        maxLines: 1,
        style: TextStyle(
          fontFamily: BiliFonts.family,
          fontFamilyFallback: BiliFonts.fallback,
          fontSize: PadFullScreenTheme.previewTimeText,
          height: 1,
          color: SeekPreviewTheme.time,
          decoration: TextDecoration.none,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );

  static String? _chapterAt(List<Chapter> chapters, double position) {
    final title = chapters.where((chapter) => chapter.from <= position).lastOrNull?.title;
    return title == null || title.isEmpty ? null : title;
  }

  /// Recording 24's 144 × 81 for a wide video; a tall video's frames keep the height at their own shape.
  static Size _padFrameSize(VideoShot shot) {
    if (shot.cellWidth <= 0 || shot.cellHeight <= 0 || shot.cellWidth >= shot.cellHeight) {
      return const Size(PadFullScreenTheme.previewWidth, PadFullScreenTheme.previewHeight);
    }
    return Size(PadFullScreenTheme.previewHeight * shot.cellWidth / shot.cellHeight, PadFullScreenTheme.previewHeight);
  }

  Widget _frame(VideoShot shot, ({String sheet, int column, int row}) frame, {required Size box, required Size cell}) {
    const border = SeekPreviewTheme.border * 2;
    return Container(
      key: const ValueKey('seek-preview-frame'),
      width: box.width + border,
      height: box.height + border,
      decoration: BoxDecoration(
        border: Border.all(color: SeekPreviewTheme.borderColor, width: SeekPreviewTheme.border),
        borderRadius: BorderRadius.circular(SeekPreviewTheme.radius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SeekPreviewTheme.radius - SeekPreviewTheme.border),
        child: _Cell(
          shot: shot,
          sheet: frame.sheet,
          column: frame.column,
          row: frame.row,
          box: box,
          cell: cell,
          onFailed: () => _sheetFailed(shot, frame.sheet),
        ),
      ),
    );
  }

  /// 102 runs the time into the duration; 竖屏 (19, 20) sets them apart with a spaced slash, a point larger.
  Widget _time(double position, double duration, {required bool upright}) {
    final total = TimeFormat.clock(duration);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: TimeFormat.clock(position)),
          TextSpan(
            text: upright ? ' / $total' : '/$total',
            style: const TextStyle(color: SeekPreviewTheme.duration),
          ),
        ],
      ),
      key: const ValueKey('seek-preview-time'),
      textAlign: TextAlign.center,
      maxLines: 1,
      style: TextStyle(
        fontFamily: BiliFonts.family,
        fontSize: upright ? SeekPreviewTheme.uprightTimeFont : SeekPreviewTheme.timeFont,
        fontWeight: FontWeight.w600,
        height: 1,
        color: SeekPreviewTheme.time,
        decoration: TextDecoration.none,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  /// 102's frame for a wide video; a tall video's frames keep the same height at their own shape.
  static Size _frameSize(VideoShot shot) {
    if (shot.cellWidth <= 0 || shot.cellHeight <= 0 || shot.cellWidth >= shot.cellHeight) {
      return const Size(SeekPreviewTheme.frameWidth, SeekPreviewTheme.frameHeight);
    }
    return Size(SeekPreviewTheme.frameHeight * shot.cellWidth / shot.cellHeight, SeekPreviewTheme.frameHeight);
  }

  /// A cell at its own shape, just covering [box]: 19 cuts a 3:4 frame's sides to fill its 9:16 box.
  static Size _cover(VideoShot shot, Size box) {
    if (shot.cellWidth <= 0 || shot.cellHeight <= 0) return box;
    final scale = math.max(box.width / shot.cellWidth, box.height / shot.cellHeight);
    return Size(shot.cellWidth * scale, shot.cellHeight * scale);
  }
}

/// The chapter's title over the iPad's frame.
class _PadChapterTitle extends StatelessWidget {
  const _PadChapterTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: BiliFonts.family,
      fontFamilyFallback: BiliFonts.fallback,
      fontSize: PadFullScreenTheme.previewTitleText,
      color: SeekPreviewTheme.time,
      decoration: TextDecoration.none,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: PadFullScreenTheme.previewTitlePad),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: PadFullScreenTheme.previewTitleFill,
        borderRadius: BorderRadius.circular(PadFullScreenTheme.previewTitleRadius),
      ),
      child: Text(
        title,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: style,
        strutStyle: BiliFonts.strutOf(context, style),
      ),
    );
  }
}

/// Centres its child on [centre], kept [edge] inside the box.
class _Centred extends SingleChildLayoutDelegate {
  const _Centred(this.centre, {required this.edge});

  final double centre;
  final double edge;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints(
    maxWidth: math.max(constraints.maxWidth - edge * 2, 0),
    minHeight: constraints.maxHeight,
    maxHeight: constraints.maxHeight,
  );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = (centre - childSize.width / 2).clamp(edge, math.max(size.width - edge - childSize.width, edge));
    return Offset(left.toDouble(), 0);
  }

  @override
  bool shouldRelayout(_Centred oldDelegate) => oldDelegate.centre != centre || oldDelegate.edge != edge;
}

/// One frame of a sheet: the whole sheet drawn at [cell] per frame, shifted so the frame lands centred in [box].
class _Cell extends StatelessWidget {
  const _Cell({
    required this.shot,
    required this.sheet,
    required this.column,
    required this.row,
    required this.box,
    required this.cell,
    required this.onFailed,
  });

  final VideoShot shot;
  final String sheet;
  final int column;
  final int row;
  final Size box;
  final Size cell;

  /// The sheet failed after all, such as on a reload once the image cache let it go.
  final VoidCallback onFailed;

  @override
  Widget build(BuildContext context) {
    final width = cell.width * shot.columns;
    final height = cell.height * shot.rows;
    return SizedBox.fromSize(
      size: box,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: width,
        maxWidth: width,
        minHeight: height,
        maxHeight: height,
        child: Transform.translate(
          offset: Offset(
            (box.width - cell.width) / 2 - column * cell.width,
            (box.height - cell.height) / 2 - row * cell.height,
          ),
          child: Image.network(
            sheet,
            key: ValueKey(sheet),
            headers: BiliClient.mediaHeaders,
            width: width,
            height: height,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stack) {
              onFailed();
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }
}
