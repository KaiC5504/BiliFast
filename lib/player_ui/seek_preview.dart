import 'dart:math' as math;

import 'package:bili_core/api.dart' show BiliClient, VideoShot;
import 'package:bili_core/logic.dart' show TimeFormat;
import 'package:flutter/widgets.dart';

import '../shared/theme.dart';
import '../video/player_session.dart';

/// The frame and time over the middle of landscape while the bar is dragged (102), or above 竖屏's bar ([upright]).
/// Before the frames arrive, or for a part without them, the time shows alone in its place.
class SeekPreview extends StatefulWidget {
  const SeekPreview({super.key, required this.session, required this.shown, this.upright = false});

  final PlayerSession session;
  final bool shown;

  /// 竖屏's (19, 20): the frame in the video's orientation above the bar, the time under it.
  final bool upright;

  @override
  State<SeekPreview> createState() => _SeekPreviewState();
}

class _SeekPreviewState extends State<SeekPreview> {
  VideoShot? _warmed;

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
    for (final sheet in shot.sheets) {
      precacheImage(NetworkImage(sheet, headers: BiliClient.mediaHeaders), context, onError: (_, _) {});
    }
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
                      builder: (context, _) => widget.upright
                          ? _uprightLayout(context, shot, session.position, session.duration.value)
                          : _layout(context, shot, session.position, session.duration.value),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _layout(BuildContext context, VideoShot? shot, double position, double duration) {
    final top = MediaQuery.sizeOf(context).height / 2 - SeekPreviewTheme.aboveMiddle;
    final frame = shot?.frameAt(position);
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
    final frame = shot?.frameAt(position);
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
        child: _Cell(shot: shot, sheet: frame.sheet, column: frame.column, row: frame.row, box: box, cell: cell),
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

/// One frame of a sheet: the whole sheet drawn at [cell] per frame, shifted so the frame lands centred in [box].
class _Cell extends StatelessWidget {
  const _Cell({
    required this.shot,
    required this.sheet,
    required this.column,
    required this.row,
    required this.box,
    required this.cell,
  });

  final VideoShot shot;
  final String sheet;
  final int column;
  final int row;
  final Size box;
  final Size cell;

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
            errorBuilder: (context, error, stack) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
