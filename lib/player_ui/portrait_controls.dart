import 'dart:async';

import 'package:bili_core/logic.dart' show TimeFormat;
import 'package:flutter/widgets.dart';

import '../shared/theme.dart';
import '../video/player_session.dart';
import 'panels/panel_controller.dart';
import 'player_ui.dart';
import 'seek_bar.dart';

/// The small player's controls, filling the player (BiliNative `PortraitControls.swift`, laid out as the official
/// app's 15): back and ⋮ at the top; play, the bar with the TV face, the time, 竖屏 and full screen at the bottom. An
/// upright video's row ends at 竖屏, in full screen's place, the bar taking the room (17). While they are hidden the
/// thin line runs along the bottom edge instead.
class PortraitControls extends StatefulWidget {
  const PortraitControls({super.key, required this.ui});

  final PlayerUi ui;

  @override
  State<PortraitControls> createState() => _PortraitControlsState();
}

class _PortraitControlsState extends State<PortraitControls> {
  static const _fade = Duration(milliseconds: 220);
  static const _timeStyle = TextStyle(
    color: BiliColors.onVideo,
    fontSize: BiliMetrics.chromeTimeFont,
    fontFeatures: [FontFeature.tabularFigures()],
  );

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
  void didUpdateWidget(PortraitControls oldWidget) {
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _shown,
      builder: (context, _) {
        final visible = _ui.chrome.visible && !_session.ended;
        return Stack(
          fit: StackFit.expand,
          children: [
            Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedOpacity(
                key: const ValueKey('portrait-hidden-line'),
                opacity: visible ? 0 : 1,
                duration: _fade,
                child: HiddenProgressLine(position: () => _session.position, duration: _duration, repaint: _bar),
              ),
            ),
            IgnorePointer(
              ignoring: !visible,
              child: AnimatedOpacity(
                key: const ValueKey('portrait-controls'),
                opacity: visible ? 1 : 0,
                duration: _fade,
                curve: Curves.easeInOut,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const _Shade(top: true),
                    const _Shade(top: false),
                    Positioned(
                      left: BiliMetrics.chromeEdge,
                      right: BiliMetrics.chromeEdge,
                      top: 0,
                      child: _Rise(visible: visible, from: -BiliMetrics.chromeRise, child: _topRow()),
                    ),
                    Positioned(
                      left: BiliMetrics.chromeEdge,
                      right: BiliMetrics.chromeEdge,
                      bottom: 0,
                      child: _Rise(visible: visible, from: BiliMetrics.chromeRise, child: _bottomRow()),
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

  Widget _topRow() {
    return Row(
      children: [
        ChromeTap(
          key: const ValueKey('video-back'),
          label: '返回',
          onTap: _tap(_ui.onBack),
          child: const BackGlyph(),
        ),
        const Spacer(),
        ChromeTap(
          key: const ValueKey('portrait-more'),
          label: '更多',
          onTap: _tap(() => _ui.panels.open(PlayerPanel.more)),
          child: const MoreDots(),
        ),
      ],
    );
  }

  Widget _bottomRow() {
    final upright = _session.isVertical;
    return Row(
      children: [
        PlayPauseButton(key: const ValueKey('portrait-play'), session: _session, onTap: _tap(_session.togglePlay)),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: BiliMetrics.chromeEdge),
            child: SeekBar(
              key: const ValueKey('portrait-bar'),
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
        ),
        IgnorePointer(
          child: Padding(
            padding: const EdgeInsets.only(left: BiliMetrics.chromeTimeLeading, right: BiliMetrics.chromeTimeTrailing),
            child: ListenableBuilder(
              listenable: _bar,
              builder: (context, _) => Text(
                TimeFormat.pair(_session.position, _duration()),
                key: const ValueKey('portrait-time'),
                style: _timeStyle,
                maxLines: 1,
              ),
            ),
          ),
        ),
        ChromeTap(
          key: const ValueKey('portrait-vertical'),
          label: '竖屏',
          onTap: _tap(_ui.orientation.enterVertical),
          child: _VerticalGlyph(badgeX: upright ? BiliMetrics.badgeEdgeOffsetX : BiliMetrics.badgeOffsetX),
        ),
        if (!upright)
          Padding(
            padding: const EdgeInsets.only(left: BiliMetrics.fullScreenGap),
            child: ChromeTap(
              key: const ValueKey('portrait-fullscreen'),
              label: '全屏',
              onTap: _tap(_ui.orientation.enterLandscape),
              child: const CustomPaint(
                size: Size.square(BiliMetrics.fullScreenGlyph),
                painter: FullScreenPainter(),
              ),
            ),
          ),
      ],
    );
  }
}

/// Slides a row in from [from] (a share of its height) as it fades.
class _Rise extends StatelessWidget {
  const _Rise({required this.visible, required this.from, required this.child});

  final bool visible;
  final double from;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSlide(
    offset: visible ? Offset.zero : Offset(0, from),
    duration: _PortraitControlsState._fade,
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
    height: BiliMetrics.chromeShadeHeight,
    child: IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: top
                ? const [BiliColors.chromeShade, BiliColors.chromeShadeClear]
                : const [BiliColors.chromeShadeClear, BiliColors.chromeShade],
          ),
        ),
      ),
    ),
  );
}

/// A control over the video: a 44-point target that dips under the finger and springs back.
class ChromeTap extends StatefulWidget {
  const ChromeTap({super.key, required this.label, required this.onTap, required this.child, this.square = true});

  final String label;
  final VoidCallback onTap;
  final Widget child;

  /// Centres [child] in a [BiliMetrics.chromeButton] square; off, the child sizes itself.
  final bool square;

  @override
  State<ChromeTap> createState() => _ChromeTapState();
}

class _ChromeTapState extends State<ChromeTap> {
  bool _pressed = false;

  void _press(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.square
        ? SizedBox.square(dimension: BiliMetrics.chromeButton, child: Center(child: widget.child))
        : widget.child;
    // excludeSemantics drops the detector's own tap action, so the node carries it: VoiceOver, Voice Control and
    // the Windows test driver press buttons through it.
    return Semantics(
      button: true,
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
          child: child,
        ),
      ),
    );
  }
}

/// The thin back chevron, shadowed so it holds over bright frames.
class BackGlyph extends StatelessWidget {
  const BackGlyph({
    super.key,
    this.width = BiliMetrics.backGlyphWidth,
    this.height = BiliMetrics.backGlyphHeight,
    this.color = BiliColors.onVideo,
    this.shadow = true,
  });

  final double width;
  final double height;
  final Color color;
  final bool shadow;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(width, height),
    painter: _BackPainter(color: color, shadow: shadow),
  );
}

class _BackPainter extends CustomPainter {
  const _BackPainter({required this.color, required this.shadow});

  final Color color;
  final bool shadow;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = BiliMetrics.backGlyphStroke / 2;
    final path = Path()
      ..moveTo(size.width - inset, inset)
      ..lineTo(inset, size.height / 2)
      ..lineTo(size.width - inset, size.height - inset);
    Paint stroke(Color color) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = BiliMetrics.backGlyphStroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    if (shadow) {
      canvas.drawPath(
        path,
        stroke(BiliColors.chromeShade)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, BiliMetrics.videoBackShadow / 2),
      );
    }
    canvas.drawPath(path, stroke(color));
  }

  @override
  bool shouldRepaint(_BackPainter oldDelegate) => oldDelegate.color != color || oldDelegate.shadow != shadow;
}

class MoreDots extends StatelessWidget {
  const MoreDots({super.key, this.color = BiliColors.onVideo, this.shadow = true});

  final Color color;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final dot = DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: shadow
            ? const [BoxShadow(color: BiliColors.chromeShade, blurRadius: BiliMetrics.videoBackShadow / 2)]
            : null,
      ),
      child: const SizedBox.square(dimension: BiliMetrics.moreDot),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: BiliMetrics.moreDotGap,
      children: [dot, dot, dot],
    );
  }
}

/// Play and pause, the triangle folding into the two bars and back.
class PlayPauseButton extends StatefulWidget {
  const PlayPauseButton({
    super.key,
    required this.session,
    required this.onTap,
    this.glyphSize = const Size(BiliMetrics.playGlyphWidth, BiliMetrics.playGlyphHeight),
    this.glyphShift = 0,
    this.cornerRadius,
    this.pauseBar,
    this.pauseGap,
    this.pauseHeight = 1,
  });

  final PlayerSession session;
  final VoidCallback onTap;
  final Size glyphSize;

  /// Moves the glyph right of the button's centre without moving the button.
  final double glyphShift;

  /// See [PlayPausePainter].
  final double? cornerRadius;
  final double? pauseBar;
  final double? pauseGap;
  final double pauseHeight;

  @override
  State<PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<PlayPauseButton> with SingleTickerProviderStateMixin {
  late final _morph = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  late final _curve = CurvedAnimation(parent: _morph, curve: Curves.easeInOutCubic);
  late Listenable _source;

  bool get _playing => widget.session.readout.wantsPlay && !widget.session.ended;

  @override
  void initState() {
    super.initState();
    _morph.value = _playing ? 1 : 0;
    _subscribe();
  }

  @override
  void didUpdateWidget(PlayPauseButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      _source.removeListener(_changed);
      _subscribe();
      _changed();
    }
  }

  @override
  void dispose() {
    _source.removeListener(_changed);
    _curve.dispose();
    _morph.dispose();
    super.dispose();
  }

  void _subscribe() {
    _source = Listenable.merge([widget.session.readout.status, widget.session]);
    _source.addListener(_changed);
  }

  void _changed() {
    final target = _playing ? 1.0 : 0.0;
    if (_morph.value == target && !_morph.isAnimating) return;
    _morph.animateTo(target);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ChromeTap(
      label: _playing ? '暂停' : '播放',
      onTap: widget.onTap,
      child: Transform.translate(
        offset: Offset(widget.glyphShift, 0),
        child: CustomPaint(
          size: widget.glyphSize,
          painter: PlayPausePainter(
            _curve,
            cornerRadius: widget.cornerRadius,
            pauseBar: widget.pauseBar,
            pauseGap: widget.pauseGap,
            pauseHeight: widget.pauseHeight,
          ),
        ),
      ),
    );
  }
}

/// A play triangle at 0 and pause bars at 1: each half of the triangle becomes one bar.
///
/// Without [cornerRadius], a thin stroke of the same colour rounds the corners outside the outline, as SF Symbols'
/// play.fill has them on the small player. With it, the corners are rounded inside the outline, as 04's larger glyph
/// has them. [pauseBar] and [pauseGap] default to the small player's, scaled to the glyph's width; [pauseHeight] is the
/// bars' share of its height.
class PlayPausePainter extends CustomPainter {
  PlayPausePainter(
    this.progress, {
    this.color = BiliColors.onVideo,
    this.cornerRadius,
    this.pauseBar,
    this.pauseGap,
    this.pauseHeight = 1,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;
  final double? cornerRadius;
  final double? pauseBar;
  final double? pauseGap;
  final double pauseHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    final w = size.width, h = size.height;
    final r = cornerRadius;
    final bar = pauseBar ?? BiliMetrics.pauseBarWidth * w / BiliMetrics.playGlyphWidth;
    final gap = pauseGap ?? BiliMetrics.pauseBarGap * w / BiliMetrics.playGlyphWidth;
    final left = (w - bar * 2 - gap) / 2;
    final right = left + bar + gap;
    final top = h * (1 - pauseHeight) / 2, bottom = h - top;
    List<Offset> pause(double x) {
      final rect = Rect.fromLTRB(x, top, x + bar, bottom).deflate(r ?? 0);
      return [rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft];
    }

    var playLeft = [Offset.zero, Offset(w / 2, h / 4), Offset(w / 2, h * 3 / 4), Offset(0, h)];
    var playRight = [Offset(w / 2, h / 4), Offset(w, h / 2), Offset(w, h / 2), Offset(w / 2, h * 3 / 4)];
    if (r != null) {
      // Shrinking the triangle towards its incentre moves every edge in by r; a stroke of 2r then gives back the
      // full outline with corners of radius r.
      final inward = _towardIncentre(size, r);
      playLeft = playLeft.map(inward).toList();
      playRight = playRight.map(inward).toList();
    }
    final fill = Paint()..color = color;
    final round = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = r == null ? BiliMetrics.playGlyphRounding : r * 2
      ..strokeJoin = StrokeJoin.round;
    for (final (from, to) in [(playLeft, pause(left)), (playRight, pause(right))]) {
      final points = [for (var i = 0; i < 4; i++) Offset.lerp(from[i], to[i], t)!];
      final path = Path()..addPolygon(r == null ? _inset(points, size) : points, true);
      canvas
        ..drawPath(path, fill)
        ..drawPath(path, round);
    }
  }

  static Offset Function(Offset) _towardIncentre(Size size, double r) {
    final a = Offset.zero, b = Offset(0, size.height), c = Offset(size.width, size.height / 2);
    final ab = (a - b).distance, bc = (b - c).distance, ca = (c - a).distance;
    final perimeter = ab + bc + ca;
    final centre = (a * bc + b * ca + c * ab) / perimeter;
    final inradius = size.width * size.height / perimeter;
    return (p) => centre + (p - centre) * ((inradius - r) / inradius);
  }

  /// Pulls the outline in by half the rounding stroke so the glyph keeps its measured size.
  static List<Offset> _inset(List<Offset> points, Size size) {
    const half = BiliMetrics.playGlyphRounding / 2;
    return [
      for (final p in points)
        Offset(p.dx.clamp(half, size.width - half), p.dy.clamp(half, size.height - half)),
    ];
  }

  @override
  bool shouldRepaint(PlayPausePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.cornerRadius != cornerRadius ||
      oldDelegate.pauseBar != pauseBar ||
      oldDelegate.pauseGap != pauseGap ||
      oldDelegate.pauseHeight != pauseHeight;
}

/// The 竖屏 button: four corner brackets with a small 竖屏 pill above to the right, its centre [badgeX] right of theirs.
class _VerticalGlyph extends StatelessWidget {
  const _VerticalGlyph({required this.badgeX});

  final double badgeX;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: BiliMetrics.chromeButton,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          const CustomPaint(
            size: Size(BiliMetrics.cornersGlyphWidth, BiliMetrics.cornersGlyphHeight),
            painter: CornersPainter(),
          ),
          Transform.translate(
            offset: Offset(badgeX, BiliMetrics.badgeOffsetY),
            child: Container(
              height: BiliMetrics.badgeHeight,
              padding: const EdgeInsets.symmetric(horizontal: BiliMetrics.badgePadding),
              decoration: BoxDecoration(
                color: BiliColors.badgeFill,
                borderRadius: BorderRadius.circular(BiliMetrics.badgeHeight / 2),
                border: Border.all(color: BiliColors.badgeBorder, width: BiliMetrics.badgeBorderWidth),
              ),
              child: const Center(
                widthFactor: 1,
                child: Text(
                  '竖屏',
                  maxLines: 1,
                  softWrap: false,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(color: BiliColors.badgeText, fontSize: BiliMetrics.badgeFont, height: 1),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Paint _glyphStroke() => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = BiliMetrics.chromeGlyphStroke
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..color = BiliColors.onVideo;

/// Four corner brackets; [inward] puts their elbows in from the corners with the arms pointing back to the edges.
class CornersPainter extends CustomPainter {
  const CornersPainter({this.inward = false});

  final bool inward;

  @override
  void paint(Canvas canvas, Size size) {
    final arm = size.shortestSide * 0.3;
    final path = Path();
    for (final (x, y, sx, sy) in [
      (0.0, 0.0, 1.0, 1.0),
      (size.width, 0.0, -1.0, 1.0),
      (0.0, size.height, 1.0, -1.0),
      (size.width, size.height, -1.0, -1.0),
    ]) {
      final ex = x + sx * arm, ey = y + sy * arm;
      final elbow = inward ? Offset(ex, ey) : Offset(x, y);
      path
        ..moveTo(x, ey)
        ..lineTo(elbow.dx, elbow.dy)
        ..lineTo(ex, y);
    }
    canvas.drawPath(path, _glyphStroke());
  }

  @override
  bool shouldRepaint(CornersPainter oldDelegate) => oldDelegate.inward != inward;
}

/// A top-left and a bottom-right bracket.
class FullScreenPainter extends CustomPainter {
  const FullScreenPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final arm = size.width * 0.56;
    final path = Path()
      ..moveTo(0, arm)
      ..lineTo(0, 0)
      ..lineTo(arm, 0)
      ..moveTo(size.width, size.height - arm)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width - arm, size.height);
    canvas.drawPath(path, _glyphStroke());
  }

  @override
  bool shouldRepaint(FullScreenPainter oldDelegate) => false;
}
