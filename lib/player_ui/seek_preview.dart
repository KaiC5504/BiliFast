import 'package:bili_core/api.dart' show BiliClient, VideoShot;
import 'package:bili_core/logic.dart' show TimeFormat;
import 'package:flutter/widgets.dart';

import '../shared/theme.dart';
import '../video/player_session.dart';

/// The frame and time over the middle of landscape while the bar is dragged (102). Before the frames arrive, or for a
/// part without them, the time shows alone in its place.
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
                      builder: (context, _) => _layout(context, shot, session.position, session.duration.value),
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
              child: Container(
                key: const ValueKey('seek-preview-frame'),
                width: size.width + border,
                height: size.height + border,
                decoration: BoxDecoration(
                  border: Border.all(color: SeekPreviewTheme.borderColor, width: SeekPreviewTheme.border),
                  borderRadius: BorderRadius.circular(SeekPreviewTheme.radius),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(SeekPreviewTheme.radius - SeekPreviewTheme.border),
                  child: _Cell(shot: shot, sheet: frame.sheet, column: frame.column, row: frame.row, size: size),
                ),
              ),
            ),
          ),
        Positioned(
          top: top + SeekPreviewTheme.frameHeight + border + SeekPreviewTheme.timeGap,
          left: 0,
          right: 0,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: TimeFormat.clock(position)),
                TextSpan(
                  text: '/${TimeFormat.clock(duration)}',
                  style: const TextStyle(color: SeekPreviewTheme.duration),
                ),
              ],
            ),
            key: const ValueKey('seek-preview-time'),
            textAlign: TextAlign.center,
            maxLines: 1,
            style: TextStyle(
              fontFamily: BiliFonts.family,
              fontSize: SeekPreviewTheme.timeFont,
              fontWeight: FontWeight.w600,
              height: 1,
              color: SeekPreviewTheme.time,
              decoration: TextDecoration.none,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  /// 102's frame for a wide video; a tall video's frames keep the same height at their own shape.
  static Size _frameSize(VideoShot shot) {
    if (shot.cellWidth <= 0 || shot.cellHeight <= 0 || shot.cellWidth >= shot.cellHeight) {
      return const Size(SeekPreviewTheme.frameWidth, SeekPreviewTheme.frameHeight);
    }
    return Size(SeekPreviewTheme.frameHeight * shot.cellWidth / shot.cellHeight, SeekPreviewTheme.frameHeight);
  }
}

/// One frame of a sheet: the whole sheet drawn at [size] per frame, shifted so the frame fills the box.
class _Cell extends StatelessWidget {
  const _Cell({required this.shot, required this.sheet, required this.column, required this.row, required this.size});

  final VideoShot shot;
  final String sheet;
  final int column;
  final int row;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final width = size.width * shot.columns;
    final height = size.height * shot.rows;
    return SizedBox.fromSize(
      size: size,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: width,
        maxWidth: width,
        minHeight: height,
        maxHeight: height,
        child: Transform.translate(
          offset: Offset(-column * size.width, -row * size.height),
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
