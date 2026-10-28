import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/api.dart' show Chapter;
import 'package:bili_core/logic.dart' show TimeFormat;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';
import '../../shared/toast.dart';
import '../../video/player_session.dart';
import '../landscape_chrome.dart' show speedLabel;
import '../panels/panel_controller.dart';
import '../panels/panel_parts.dart' show toastFailure;
import '../player_ui.dart';
import '../portrait_controls.dart';
import '../seek_bar.dart';

/// The controls over the iPad page's player (ipad/03 sideways, 07 upright, the same rows at both widths): back, 小窗,
/// 投屏 and ⋮ at the top; ⏮, play, the bar with the TV, the time, 倍速 and 全屏 at the bottom, with 章节 · (chapter) ›
/// above them while the video has chapters. Hidden, the chapters run along the bottom edge (06) over the thin line.
/// The taps and the hide timer are the phone's small player's.
class PadInlineControls extends StatefulWidget {
  const PadInlineControls({super.key, required this.ui});

  final PlayerUi ui;

  @override
  State<PadInlineControls> createState() => _PadInlineControlsState();
}

class _PadInlineControlsState extends State<PadInlineControls> {
  static const _fade = Duration(milliseconds: 220);
  static const _rise = 0.3;
  static const _button = BiliMetrics.chromeButton;

  /// The bottom group reaches up past the chapter line.
  static const _bottomHeight =
      PadInlineControlsTheme.chapterCentre + PadInlineControlsTheme.chapterHeight / 2 + BiliMetrics.chromeEdge * 2;
  static const _topHeight = PadInlineControlsTheme.topCentre * 2;

  static const _timeStyle = TextStyle(
    color: BiliColors.onVideo,
    fontSize: PadInlineControlsTheme.timeFont,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const _speedStyle = TextStyle(color: BiliColors.onVideo, fontSize: PadInlineControlsTheme.speedFont);

  late Listenable _bar;
  late Listenable _shown;

  PlayerUi get _ui => widget.ui;
  PlayerSession get _session => widget.ui.session;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(PadInlineControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ui.session != _session || oldWidget.ui.chrome != _ui.chrome) _listen();
  }

  void _listen() {
    final session = _session;
    _bar = Listenable.merge([session.readout.seconds, session.readout.buffered, session.scrubbing, session.duration]);
    _shown = Listenable.merge([_ui.chrome, session]);
  }

  double _duration() => _session.duration.value;

  VoidCallback _tap(VoidCallback action) => () {
    _ui.chrome.show();
    action();
  };

  void _scrub(double seconds) {
    if (_duration() <= 0) return;
    _ui.chrome.show();
    _session.scrub(seconds);
  }

  void _hint(double seconds) {
    if (_duration() <= 0) return;
    _session.hint(seconds);
  }

  void _cancel() {
    _session.cancelScrub();
    _ui.chrome.show();
  }

  void _commit(double seconds) {
    _ui.chrome.show();
    if (_duration() <= 0) return;
    unawaited(_session.commitSeek(seconds));
  }

  /// The part or 合集 episode before the one playing, if any.
  Episode? _previous() {
    final episodes = _session.episodes;
    final index = episodes.indexWhere((episode) => episode.current);
    return index > 0 ? episodes[index - 1] : null;
  }

  void _pictureInPicture() => toastFailure(_session.startPictureInPicture(), (message) {
    if (mounted) showToast(context, message);
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _shown,
      builder: (context, _) {
        final visible = _ui.chrome.visible && !_session.ended;
        final chapters = _session.chapters;
        return Stack(
          fit: StackFit.expand,
          children: [
            AnimatedOpacity(
              key: const ValueKey('pad-inline-hidden'),
              opacity: visible ? 0 : 1,
              duration: _fade,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (chapters.isNotEmpty) PadChapterStrip(chapters: chapters, duration: _session.duration),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: HiddenProgressLine(position: () => _session.position, duration: _duration, repaint: _bar),
                  ),
                ],
              ),
            ),
            IgnorePointer(
              ignoring: !visible,
              child: AnimatedOpacity(
                key: const ValueKey('pad-inline-controls'),
                opacity: visible ? 1 : 0,
                duration: _fade,
                curve: Curves.easeInOut,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const _Shade(top: true),
                    const _Shade(top: false),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: _topHeight,
                      child: _Rise(visible: visible, from: -_rise, child: _topRow()),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: _bottomHeight,
                      child: _Rise(visible: visible, from: _rise, child: _bottomRow()),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// A 44-point target centred [fromLeft] or [fromRight] of the player's sides and [centre] down the group.
  static Widget _at({
    double? fromLeft,
    double? fromRight,
    required double centre,
    double width = _button,
    required Widget child,
  }) =>
      Positioned(
        left: fromLeft == null ? null : fromLeft - width / 2,
        right: fromRight == null ? null : fromRight - width / 2,
        top: centre - _button / 2,
        width: width,
        height: _button,
        child: child,
      );

  Widget _topRow() {
    const centre = PadInlineControlsTheme.topCentre;
    final pip = _session.pictureInPictureSupported;
    return Stack(
      children: [
        _at(
          fromLeft: PadInlineControlsTheme.edgeCentre,
          centre: centre,
          child: ChromeTap(
            key: const ValueKey('video-back'),
            label: '返回',
            onTap: _tap(_ui.onBack),
            child: const BackGlyph(width: PadInlineControlsTheme.backWidth, height: PadInlineControlsTheme.backHeight),
          ),
        ),
        _at(
          fromRight: PadInlineControlsTheme.floatCentre,
          centre: centre,
          child: _PadButton(
            key: const ValueKey('pad-inline-float'),
            label: '小窗播放',
            onTap: pip ? _tap(_pictureInPicture) : null,
            keepUp: _ui.chrome.show,
            child: const CustomPaint(
              size: Size(PadInlineControlsTheme.floatWidth, PadInlineControlsTheme.floatHeight),
              painter: FloatWindowPainter(),
            ),
          ),
        ),
        _at(
          fromRight: PadInlineControlsTheme.castCentre,
          centre: centre,
          child: ChromeTap(
            key: const ValueKey('pad-inline-cast'),
            label: '投屏',
            onTap: _tap(() => showToast(context, '暂未开放')),
            child: Image.asset(
              'assets/images/player/pad_cast_tv.png',
              width: PadInlineControlsTheme.castWidth,
              height: PadInlineControlsTheme.castHeight,
              color: BiliColors.onVideo,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
        _at(
          fromRight: PadInlineControlsTheme.edgeCentre,
          centre: centre,
          child: ChromeTap(
            key: const ValueKey('pad-inline-more'),
            label: '更多',
            onTap: _tap(() => _ui.panels.open(PlayerPanel.more)),
            child: const MoreDots(dot: PadInlineControlsTheme.moreDot, gap: PadInlineControlsTheme.moreDotGap),
          ),
        ),
      ],
    );
  }

  Widget _bottomRow() {
    const centre = _bottomHeight - PadInlineControlsTheme.bottomCentre;
    final previous = _previous();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: PadInlineControlsTheme.chapterLeft,
          right: PadInlineControlsTheme.edgeCentre,
          top: _bottomHeight - PadInlineControlsTheme.chapterCentre - PadInlineControlsTheme.chapterHeight / 2,
          height: PadInlineControlsTheme.chapterHeight,
          child: IgnorePointer(
            child: ListenableBuilder(
              listenable: _bar,
              builder: (context, _) {
                // While the bar is held its own label names the chapter under the thumb.
                if (_session.scrubbing.value != null) return const SizedBox.shrink();
                final title = SeekBar.chapterTitle(_session.chapters, _session.position);
                return title == null ? const SizedBox.shrink() : _ChapterLine(title: title);
              },
            ),
          ),
        ),
        _at(
          fromLeft: PadInlineControlsTheme.previousCentre,
          centre: centre,
          child: _PadButton(
            key: const ValueKey('pad-inline-previous'),
            label: '上一集',
            onTap: previous == null ? null : _tap(() => _session.playEpisode(previous)),
            keepUp: _ui.chrome.show,
            child: Image.asset(
              'assets/images/player/pad_previous.png',
              width: PadInlineControlsTheme.previousWidth,
              height: PadInlineControlsTheme.previousHeight,
              color: BiliColors.onVideo,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
        _at(
          fromLeft: PadInlineControlsTheme.playCentre,
          centre: centre,
          child: PlayPauseButton(
            key: const ValueKey('pad-inline-play'),
            session: _session,
            onTap: _tap(_session.togglePlay),
            glyphSize: const Size(PadInlineControlsTheme.playWidth, PadInlineControlsTheme.playHeight),
          ),
        ),
        Positioned(
          left: PadInlineControlsTheme.barLeft,
          right: PadInlineControlsTheme.timeRight,
          top: centre - BiliMetrics.barTouchHeight / 2,
          height: BiliMetrics.barTouchHeight,
          child: Row(
            children: [
              Expanded(
                child: SeekBar(
                  key: const ValueKey('pad-inline-bar'),
                  position: () => _session.position,
                  duration: _duration,
                  buffered: () => _session.readout.bufferedEnd(_session.position),
                  repaint: _bar,
                  chapters: _session.chapters,
                  onScrub: _scrub,
                  onCommit: _commit,
                  onCancel: _cancel,
                  onRest: _hint,
                ),
              ),
              const SizedBox(width: PadInlineControlsTheme.timeGap),
              IgnorePointer(
                child: ListenableBuilder(
                  listenable: _bar,
                  builder: (context, _) => Text(
                    TimeFormat.pair(_session.position, _duration()),
                    key: const ValueKey('pad-inline-time'),
                    style: _timeStyle,
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
              ),
            ],
          ),
        ),
        _at(
          fromRight: PadInlineControlsTheme.castCentre,
          centre: centre,
          width: PadInlineControlsTheme.speedWidth,
          child: ChromeTap(
            key: const ValueKey('pad-inline-speed'),
            label: '倍速',
            square: false,
            onTap: _tap(() => _ui.panels.open(PlayerPanel.speed)),
            child: Center(
              child: Text(
                speedLabel(_session.rate),
                maxLines: 1,
                softWrap: false,
                style: _speedStyle,
                strutStyle: BiliFonts.strutOf(context, _speedStyle),
              ),
            ),
          ),
        ),
        _at(
          fromRight: PadInlineControlsTheme.edgeCentre,
          centre: centre,
          child: ChromeTap(
            key: const ValueKey('pad-inline-fullscreen'),
            label: '全屏',
            onTap: _tap(_ui.orientation.enterLandscape),
            child: const CustomPaint(
              size: Size.square(PadInlineControlsTheme.fullScreenGlyph),
              painter: FullScreenPainter(),
            ),
          ),
        ),
      ],
    );
  }
}

/// A control that may have nothing to do: then it shows at half white and a tap only keeps the controls up.
class _PadButton extends StatelessWidget {
  const _PadButton({super.key, required this.label, required this.onTap, required this.keepUp, required this.child});

  final String label;
  final VoidCallback? onTap;
  final VoidCallback keepUp;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final onTap = this.onTap;
    if (onTap != null) return ChromeTap(label: label, onTap: onTap, child: child);
    return Semantics(
      button: true,
      enabled: false,
      label: label,
      onTap: keepUp,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: keepUp,
        child: Center(
          child: Opacity(opacity: PadInlineControlsTheme.previousOffOpacity, child: child),
        ),
      ),
    );
  }
}

class _Rise extends StatelessWidget {
  const _Rise({required this.visible, required this.from, required this.child});

  final bool visible;
  final double from;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSlide(
    offset: visible ? Offset.zero : Offset(0, from),
    duration: _PadInlineControlsState._fade,
    curve: visible ? Curves.easeOutCubic : Curves.easeIn,
    child: child,
  );
}

class _Shade extends StatelessWidget {
  const _Shade({required this.top});

  final bool top;

  @override
  Widget build(BuildContext context) => Positioned(
    left: 0,
    right: 0,
    top: top ? 0 : null,
    bottom: top ? null : 0,
    height: PadInlineControlsTheme.shadeHeight,
    child: IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: top ? Alignment.topCenter : Alignment.bottomCenter,
            end: top ? Alignment.bottomCenter : Alignment.topCenter,
            colors: PadInlineControlsTheme.shade,
            stops: PadInlineControlsTheme.shadeStops,
          ),
        ),
      ),
    ),
  );
}

/// 章节 · (chapter) ›, as the iPhone writes it (KaiC's iPad, set to English, shows "Chapter · …").
class _ChapterLine extends StatelessWidget {
  const _ChapterLine({required this.title});

  final String title;

  static const _style = TextStyle(
    color: BiliColors.onVideo,
    fontSize: PadInlineControlsTheme.chapterFont,
    fontWeight: FontWeight.w500,
    shadows: [Shadow(color: BiliColors.chromeShade, blurRadius: PadInlineControlsTheme.chapterShadow)],
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            '章节 · $title',
            key: const ValueKey('pad-inline-chapter'),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: _style,
            strutStyle: BiliFonts.strutOf(context, _style),
          ),
        ),
        const SizedBox(width: PadInlineControlsTheme.chevronGap),
        const CustomPaint(
          size: Size(PadInlineControlsTheme.chevronWidth, PadInlineControlsTheme.chevronHeight),
          painter: _ChevronPainter(),
        ),
      ],
    );
  }
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const inset = PadInlineControlsTheme.chevronStroke / 2;
    final path = Path()
      ..moveTo(inset, inset)
      ..lineTo(size.width - inset, size.height / 2)
      ..lineTo(inset, size.height - inset);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = PadInlineControlsTheme.chevronStroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = BiliColors.onVideo,
    );
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) => false;
}

/// The APK's `biliplayer_ic_topbar_floatwindow` (a 22-unit vector): a screen open at its lower right, an arrow into
/// it and the small window filled. Drawn rather than taken as a bitmap: the extractor fills its stroked paths.
class FloatWindowPainter extends CustomPainter {
  const FloatWindowPainter({this.color = BiliColors.onVideo});

  final Color color;

  /// The ink's box in the viewport, strokes included.
  static const _ink = Rect.fromLTRB(1.0245, 3.051, 22, 20);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / _ink.width, size.height / _ink.height);
    canvas
      ..save()
      ..translate(
        (size.width - _ink.width * scale) / 2 - _ink.left * scale,
        (size.height - _ink.height * scale) / 2 - _ink.top * scale,
      )
      ..scale(scale);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final screen = Path()
      ..moveTo(9.596, 18)
      ..lineTo(4.5245, 18)
      ..cubicTo(2.8677, 18, 1.5245, 16.6569, 1.5245, 15)
      ..lineTo(1.5245, 6.551)
      ..cubicTo(1.5245, 4.8942, 2.8677, 3.551, 4.5245, 3.551)
      ..lineTo(17, 3.551)
      ..cubicTo(18.6569, 3.551, 20, 4.8942, 20, 6.551)
      ..lineTo(20, 11.5666);
    final arrow = Path()
      ..moveTo(5.5065, 7.5085)
      ..lineTo(9.9328, 11.9511)
      ..moveTo(10.5215, 7.5085)
      ..lineTo(10.5215, 12.515)
      ..lineTo(5.5065, 12.515);
    canvas
      ..drawPath(screen, line)
      ..drawPath(arrow, line)
      ..drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTRB(12, 14, 22, 20), const Radius.circular(2)),
        Paint()..color = color,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(FloatWindowPainter oldDelegate) => oldDelegate.color != color;
}

/// The chapters along the player's bottom edge while the controls are hidden (06): each title centred on its stretch
/// of the video, hairlines where one ends, over a shade.
class PadChapterStrip extends StatelessWidget {
  const PadChapterStrip({super.key, required this.chapters, required this.duration});

  final List<Chapter> chapters;
  final ValueListenable<double> duration;

  static const _style = TextStyle(color: BiliColors.onVideo, fontSize: PadInlineControlsTheme.stripFont, height: 1);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder(
        valueListenable: duration,
        builder: (context, total, _) {
          if (total <= 0) return const SizedBox.shrink();
          return LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;
              double x(double seconds) => width * (seconds / total).clamp(0.0, 1.0);
              return Stack(
                key: const ValueKey('pad-chapter-strip'),
                children: [
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: PadInlineControlsTheme.stripShadeHeight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [BiliColors.chromeShadeClear, PadInlineControlsTheme.stripShade],
                        ),
                      ),
                    ),
                  ),
                  for (final chapter in chapters) ...[
                    if (chapter.from > 0 && chapter.from < total)
                      Positioned(
                        left: x(chapter.from) - PadInlineControlsTheme.stripLine / 2,
                        width: PadInlineControlsTheme.stripLine,
                        bottom: 0,
                        height: PadInlineControlsTheme.stripLineHeight,
                        child: const ColoredBox(color: PadInlineControlsTheme.stripLineInk),
                      ),
                    if (chapter.title.isNotEmpty &&
                        x(chapter.to) - x(chapter.from) > PadInlineControlsTheme.stripPad * 2)
                      Positioned(
                        left: x(chapter.from) + PadInlineControlsTheme.stripPad,
                        width: x(chapter.to) - x(chapter.from) - PadInlineControlsTheme.stripPad * 2,
                        top: height - PadInlineControlsTheme.stripCentre - PadInlineControlsTheme.stripFont,
                        height: PadInlineControlsTheme.stripFont * 2,
                        child: Center(
                          child: Text(
                            chapter.title,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: _style,
                          ),
                        ),
                      ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}
