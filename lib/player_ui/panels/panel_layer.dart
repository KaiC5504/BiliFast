import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../device/orientation.dart';
import '../../shared/theme.dart';
import '../../shared/toast.dart';
import '../player_ui.dart';
import 'episodes_panel.dart';
import 'more_panel.dart';
import 'panel_controller.dart';
import 'panel_parts.dart';
import 'quality_panel.dart';
import 'speed_panel.dart';

/// How a panel sits: its width as a share of the screen in landscape (or a column with no panel behind it), and its
/// height as a share of the screen in the portrait sheet. 清晰度 and 高级设置 share one frame, so moving between them
/// swaps the content without sliding again.
@immutable
final class PanelFrame {
  const PanelFrame({required this.width, required this.sheetHeight, this.column = false, this.light = false});

  final double width;
  final double sheetHeight;
  final bool column;

  /// The portrait 选集 list is the official app's light sheet, its top at the player's bottom.
  final bool light;

  static PanelFrame of(PlayerPanel panel) => switch (panel) {
    PlayerPanel.quality || PlayerPanel.codec => const PanelFrame(
      width: BiliMetrics.panelQualityWidth,
      sheetHeight: BiliMetrics.panelSheetHeight,
    ),
    PlayerPanel.speed => const PanelFrame(
      width: BiliMetrics.panelSpeedWidth,
      sheetHeight: BiliMetrics.panelSpeedSheetHeight,
      column: true,
    ),
    PlayerPanel.more => const PanelFrame(
      width: BiliMetrics.panelMoreWidth,
      sheetHeight: BiliMetrics.panelMoreSheetHeight,
    ),
    PlayerPanel.episodes => const PanelFrame(
      width: BiliMetrics.panelWidth,
      sheetHeight: BiliMetrics.panelSheetHeight,
      light: true,
    ),
  };

  @override
  bool operator ==(Object other) =>
      other is PanelFrame &&
      other.width == width &&
      other.sheetHeight == sheetHeight &&
      other.column == column &&
      other.light == light;

  @override
  int get hashCode => Object.hash(width, sheetHeight, column, light);
}

/// The open panel, if any (BiliNative `PanelLayer.swift` and `SidePanel.swift`): from the right in landscape, a
/// bottom sheet in portrait, closed by a tap outside it. The page puts it over everything, filling the page. It is
/// part of the page rather than a route, so rotation, swipe back and picture in picture never see it.
class PanelLayer extends StatefulWidget {
  const PanelLayer({super.key, required this.ui});

  final PlayerUi ui;

  @override
  State<PanelLayer> createState() => _PanelLayerState();
}

class _PanelLayerState extends State<PanelLayer> with TickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    reverseDuration: const Duration(milliseconds: 220),
  );
  late final CurvedAnimation _slide = CurvedAnimation(
    parent: _motion,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// A grabber drag pulling the sheet down, and the spring back when it lets go short of closing.
  final _drag = ValueNotifier<double>(0);
  late final AnimationController _dragBack = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  /// What shows: the open panel, or the one sliding out after a close.
  PlayerPanel? _shown;

  @override
  void initState() {
    super.initState();
    _listen(widget.ui);
    _dragBack.addListener(() => _drag.value = _dragFrom * (1 - Curves.easeOutCubic.transform(_dragBack.value)));
    _panelChanged();
  }

  double _dragFrom = 0;

  void _listen(PlayerUi ui) {
    ui.panels.addListener(_panelChanged);
    ui.orientation.addListener(_rebuild);
  }

  void _unlisten(PlayerUi ui) {
    ui.panels.removeListener(_panelChanged);
    ui.orientation.removeListener(_rebuild);
  }

  @override
  void didUpdateWidget(PanelLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.ui.panels, widget.ui.panels) &&
        identical(oldWidget.ui.orientation, widget.ui.orientation)) {
      return;
    }
    _unlisten(oldWidget.ui);
    _listen(widget.ui);
    _panelChanged();
  }

  @override
  void dispose() {
    _unlisten(widget.ui);
    _slide.dispose();
    _motion.dispose();
    _dragBack.dispose();
    _drag.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _panelChanged() {
    final next = widget.ui.panels.value;
    if (next == null) {
      if (_shown == null) return;
      setState(() {});
      _motion.reverse().whenCompleteOrCancel(() {
        if (mounted && _motion.isDismissed && widget.ui.panels.value == null) setState(() => _shown = null);
      });
      return;
    }
    final previous = _shown;
    final slideIn = previous == null || PanelFrame.of(previous) != PanelFrame.of(next);
    setState(() => _shown = next);
    if (slideIn) {
      _dragBack.stop();
      _drag.value = 0;
      _motion.forward(from: 0);
    } else {
      // Reopened while sliding out: it turns around where it is.
      _motion.forward();
    }
  }

  void _close() => widget.ui.panels.close();

  /// For what a panel does once a call comes back: by then the user may have closed it or opened another.
  void _closeIf(PlayerPanel panel) {
    if (widget.ui.panels.value == panel) _close();
  }

  void _toast(String message) {
    if (mounted) showToast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    if (shown == null) return const SizedBox.shrink();
    final landscape = widget.ui.presentation == Presentation.landscape;
    final frame = PanelFrame.of(shown);
    final light = frame.light && !landscape;
    return IgnorePointer(
      ignoring: widget.ui.panels.value == null,
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: BiliFonts.family,
          fontSize: BiliMetrics.panelTitleText,
          color: light ? BiliColors.text : BiliColors.panelText,
          decoration: TextDecoration.none,
        ),
        child: PanelScope(
          landscape: landscape,
          reveal: _motion,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              final insets = MediaQuery.paddingOf(context);
              final content = _content(shown, light: light);
              return Stack(
                children: [
                  Positioned.fill(
                    child: Semantics(
                      button: true,
                      label: '关闭',
                      child: GestureDetector(
                        key: const ValueKey('panel-dismiss'),
                        behavior: HitTestBehavior.opaque,
                        onTap: _close,
                      ),
                    ),
                  ),
                  if (!landscape && light)
                    _lightSheet(size, insets, content)
                  else if (!landscape)
                    _sheet(size, insets, frame, content)
                  else if (frame.column)
                    _column(size, insets, frame, content)
                  else
                    _side(size, insets, frame, content),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _content(PlayerPanel panel, {required bool light}) {
    final session = widget.ui.session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (current, previous) => Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
        transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
        child: KeyedSubtree(
          key: ValueKey(panel),
          child: switch (panel) {
            PlayerPanel.quality => QualityPanel(
              session: session,
              openCodec: () => widget.ui.panels.open(PlayerPanel.codec),
              toast: _toast,
              close: _close,
            ),
            PlayerPanel.codec => CodecPanel(
              session: session,
              back: () => widget.ui.panels.open(PlayerPanel.quality),
              toast: _toast,
              close: _close,
            ),
            PlayerPanel.speed => SpeedPanel(session: session, toast: _toast, close: _close),
            PlayerPanel.more => MorePanel(session: session, toast: _toast, close: () => _closeIf(PlayerPanel.more)),
            PlayerPanel.episodes => EpisodesPanel(session: session, close: _close, light: light),
          },
        ),
      ),
    );
  }

  /// Takes the touches that land on the panel itself, so only those outside it close it.
  Widget _body({required Widget child}) =>
      GestureDetector(key: const ValueKey('panel-frame'), behavior: HitTestBehavior.opaque, onTap: () {}, child: child);

  Widget _side(Size size, EdgeInsets insets, PanelFrame frame, Widget content) {
    final width = size.width * frame.width;
    final reach = size.width * BiliMetrics.panelFadeFraction;
    return Positioned(
      top: 0,
      bottom: 0,
      right: 0,
      width: width + reach,
      child: AnimatedBuilder(
        animation: _slide,
        builder: (context, child) =>
            Transform.translate(offset: Offset((1 - _slide.value) * (width + reach), 0), child: child),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: panelBackdrop(reach: reach, length: width + reach),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: width,
              child: _body(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    top: insets.top,
                    bottom: insets.bottom + BiliMetrics.panelBottom,
                    right: insets.right + BiliMetrics.panelTrailing,
                  ),
                  child: content,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 倍速: no panel, a column of values on a dark strip at the right edge.
  Widget _column(Size size, EdgeInsets insets, PanelFrame frame, Widget content) => Positioned(
    top: 0,
    bottom: 0,
    right: 0,
    width: size.width * frame.width,
    child: AnimatedBuilder(
      animation: _slide,
      builder: (context, child) => Opacity(
        opacity: _slide.value,
        child: Transform.translate(offset: Offset((1 - _slide.value) * BiliMetrics.panelRevealShift, 0), child: child),
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(child: ColoredBox(color: BiliColors.panelShade)),
          ),
          Positioned.fill(
            child: _body(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: BiliMetrics.panelSpeedLead,
                  right: insets.right + BiliMetrics.panelTrailing,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: size.height),
                  child: Center(child: content),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  double _sheetOffset(double hidden) => (1 - _slide.value) * hidden + _drag.value;

  Widget _slidingSheet({required double height, required double hidden, required Widget child}) => Positioned(
    left: 0,
    right: 0,
    bottom: 0,
    height: height,
    child: AnimatedBuilder(
      animation: Listenable.merge([_slide, _drag]),
      builder: (context, child) => Transform.translate(offset: Offset(0, _sheetOffset(hidden)), child: child),
      child: child,
    ),
  );

  Widget _grabber({required Widget child}) => GestureDetector(
    key: const ValueKey('panel-grabber'),
    behavior: HitTestBehavior.opaque,
    onVerticalDragStart: (_) => _dragBack.stop(),
    onVerticalDragUpdate: (details) => _drag.value = math.max(0, _drag.value + details.delta.dy),
    onVerticalDragEnd: (details) {
      if (_drag.value > BiliMetrics.panelDismissDrag ||
          (details.primaryVelocity ?? 0) > BiliMetrics.panelDismissVelocity) {
        _close();
      } else {
        _dragFrom = _drag.value;
        _dragBack.forward(from: 0);
      }
    },
    child: child,
  );

  Widget _sheet(Size size, EdgeInsets insets, PanelFrame frame, Widget content) {
    final height = size.height * frame.sheetHeight;
    const reach = BiliMetrics.panelFadeHeight;
    return _slidingSheet(
      height: height + reach,
      hidden: height + reach + insets.bottom,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: panelBackdrop(reach: reach, length: height + reach, vertical: true),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: height,
            child: _body(
              child: Column(
                children: [
                  _grabber(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: BiliMetrics.panelGrabberPad),
                      alignment: Alignment.center,
                      child: Container(
                        width: BiliMetrics.panelGrabberWidth,
                        height: BiliMetrics.panelGrabberHeight,
                        decoration: BoxDecoration(
                          color: BiliColors.panelGrabber,
                          borderRadius: BorderRadius.circular(BiliMetrics.panelGrabberHeight / 2),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.only(
                        left: insets.left + BiliMetrics.gutter,
                        right: insets.right + BiliMetrics.gutter,
                        bottom: insets.bottom + BiliMetrics.gutter,
                      ),
                      child: content,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The official 合集 list (19): white, rounded at the top, from the player's bottom down; [EpisodesPanel] fills it
  /// below the grabber.
  Widget _lightSheet(Size size, EdgeInsets insets, Widget content) {
    final height = widget.ui.presentation == Presentation.inline
        ? size.height - insets.top - size.width / BiliMetrics.videoAspect
        : size.height * BiliMetrics.panelSheetHeight;
    return _slidingSheet(
      height: height,
      hidden: height + insets.bottom,
      child: _body(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: BiliColors.card,
            borderRadius: BorderRadius.vertical(top: Radius.circular(BiliMetrics.sheetRadius)),
          ),
          child: Column(
            children: [
              _grabber(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(top: BiliMetrics.sheetGrabberTop),
                  alignment: Alignment.topCenter,
                  child: Container(
                    width: BiliMetrics.sheetGrabberWidth,
                    height: BiliMetrics.sheetGrabberHeight,
                    decoration: BoxDecoration(
                      color: BiliColors.sheetGrabber,
                      borderRadius: BorderRadius.circular(BiliMetrics.sheetGrabberHeight / 2),
                    ),
                  ),
                ),
              ),
              Expanded(child: content),
            ],
          ),
        ),
      ),
    );
  }
}

/// The dark layer behind a panel: a ramp from clear over [reach] towards the video, then the panel shade. The
/// portrait sheet ramps all the way to full shade before its content starts, since the light page behind it would
/// ghost through its heading at the landscape ramp's end.
Gradient panelBackdrop({required double reach, required double length, bool vertical = false}) {
  const shade = BiliColors.panelShade;
  if (reach <= 0 || length <= reach) return const LinearGradient(colors: [shade, shade]);
  final ramp = reach / length;
  final end = BiliColors.panelFade.last.$2;
  final scale = vertical ? BiliColors.panelShadeOpacity / end : 1.0;
  final colors = <Color>[], stops = <double>[];
  for (final (at, black) in BiliColors.panelFade) {
    colors.add(shade.withValues(alpha: black * scale));
    stops.add(at * ramp);
  }
  colors.addAll([shade, shade]);
  stops.addAll([ramp + (1 - ramp) * 0.2, 1]);
  return LinearGradient(
    begin: vertical ? Alignment.topCenter : Alignment.centerLeft,
    end: vertical ? Alignment.bottomCenter : Alignment.centerRight,
    colors: colors,
    stops: stops,
  );
}
