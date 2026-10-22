import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'loading_tv.dart';
import 'theme.dart';

/// The pull to refresh every list uses: arms once pulled past [refreshTriggerPullDistance] but refreshes only when the
/// finger lets go, as everywhere in the official app (107). Drawn by [loadingTvRefreshIndicator] by default.
///
/// The first sliver of a downward scroll view whose physics overscroll at the top ([BouncingScrollPhysics]). While
/// [onRefresh] runs the gap holds at [refreshIndicatorExtent]; a pull meanwhile starts nothing.
class ReleaseRefreshControl extends StatefulWidget {
  const ReleaseRefreshControl({
    super.key,
    required this.onRefresh,
    this.builder = loadingTvRefreshIndicator,
    this.refreshTriggerPullDistance = 100,
    this.refreshIndicatorExtent = LoadingTvTheme.size,
  }) : assert(refreshTriggerPullDistance > 0),
       assert(refreshIndicatorExtent >= 0),
       assert(refreshTriggerPullDistance >= refreshIndicatorExtent);

  final RefreshCallback? onRefresh;
  final RefreshControlIndicatorBuilder? builder;
  final double refreshTriggerPullDistance;
  final double refreshIndicatorExtent;

  @override
  State<ReleaseRefreshControl> createState() => _ReleaseRefreshControlState();
}

class _ReleaseRefreshControlState extends State<ReleaseRefreshControl> {
  /// How little of the closing gap may be left, as a fraction of the trigger, for a finger to start a new pull in it.
  static const _caughtFraction = 0.1;

  RefreshIndicatorMode _mode = RefreshIndicatorMode.inactive;
  ScrollableState? _scrollable;
  bool _ticking = true;

  /// The pointers that went down on this list and haven't lifted.
  final _fingers = <int>{};

  @override
  void initState() {
    super.initState();
    // Scroll notifications bubble up from the Scrollable, which is above this sliver, and the position's drag
    // activity is protected, so the fingers are followed on the global route instead. It hears an up after the
    // scroll's own recognizer has ended the drag, while the position still holds where the finger left it.
    GestureBinding.instance.pointerRouter.addGlobalRoute(_pointer);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scrollable = Scrollable.maybeOf(context);
    // Off for a page kept alive out of sight, as 首页 under 我的 is.
    _ticking = TickerMode.valuesOf(context).enabled;
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_pointer);
    super.dispose();
  }

  void _pointer(PointerEvent event) {
    switch (event) {
      case PointerDownEvent() || PointerPanZoomStartEvent():
        if (_touches(event)) _fingers.add(event.pointer);
      case PointerUpEvent() || PointerPanZoomEndEvent():
        if (_fingers.remove(event.pointer) && _fingers.isEmpty) _letGo(refresh: true);
      case PointerCancelEvent():
        // The system took the touch: no release.
        if (_fingers.remove(event.pointer) && _fingers.isEmpty) _letGo(refresh: false);
      default:
    }
  }

  /// Whether [event] went down on this list itself. Its rectangle isn't enough: a page hidden in an [IndexedStack],
  /// one under a route or a list under an in-page sheet has the same rectangle but takes no touch.
  bool _touches(PointerEvent event) {
    if (!mounted || !_ticking) return false;
    final box = _scrollable?.context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    return _hitPath(event).any((entry) => identical(entry.target, box));
  }

  static PointerEvent? _hitEvent;
  static Iterable<HitTestEntry> _hitEntries = const [];

  /// What's under [event], hit tested once for all the lists on screen.
  static Iterable<HitTestEntry> _hitPath(PointerEvent event) {
    if (!identical(event, _hitEvent)) {
      final result = HitTestResult();
      RendererBinding.instance.hitTestInView(result, event.position, event.viewId);
      _hitEvent = event;
      _hitEntries = result.path;
    }
    return _hitEntries;
  }

  /// How far the list is pulled past its top now. The last layout can be a frame behind the finger, as when the pull
  /// goes back under the trigger and lifts within one frame.
  double _pulled() {
    final position = _scrollable?.position;
    if (position == null || !position.hasPixels || !position.hasContentDimensions) return 0;
    return position.minScrollExtent - position.pixels;
  }

  void _letGo({required bool refresh}) {
    if (!mounted) return;
    final idle = _mode != RefreshIndicatorMode.refresh && _mode != RefreshIndicatorMode.done;
    if (refresh && idle && _pulled() >= widget.refreshTriggerPullDistance) {
      _refresh();
    } else if (_mode == RefreshIndicatorMode.armed) {
      setState(() => _mode = RefreshIndicatorMode.drag);
    }
  }

  void _refresh() {
    final onRefresh = widget.onRefresh;
    if (onRefresh == null) {
      setState(() => _mode = RefreshIndicatorMode.done);
      return;
    }
    final task = onRefresh();
    setState(() => _mode = RefreshIndicatorMode.refresh);
    unawaited(
      task.whenComplete(() {
        if (mounted) setState(() => _mode = RefreshIndicatorMode.done);
      }),
    );
  }

  /// The mode for the space the sliver now gives the indicator. Refreshing begins and ends outside layout, in
  /// [_letGo] and when [ReleaseRefreshControl.onRefresh] completes. It buzzes once as the pull arms.
  RefreshIndicatorMode _settle(double extent) {
    final trigger = widget.refreshTriggerPullDistance;
    if (_mode == RefreshIndicatorMode.refresh) return RefreshIndicatorMode.refresh;
    // The closing gap plays on until it's shut, unless a finger catches its last bit for a new pull.
    final caught = _fingers.isNotEmpty && extent <= trigger * _caughtFraction;
    if (_mode == RefreshIndicatorMode.done && extent > 0 && !caught) return RefreshIndicatorMode.done;
    if (extent <= 0) return RefreshIndicatorMode.inactive;
    // A bounce past the trigger with no finger on the list arms nothing.
    if (extent < trigger || _fingers.isEmpty) return RefreshIndicatorMode.drag;
    if (_mode != RefreshIndicatorMode.armed) unawaited(HapticFeedback.mediumImpact());
    return RefreshIndicatorMode.armed;
  }

  @override
  Widget build(BuildContext context) => _PullSliver(
    gap: _mode == RefreshIndicatorMode.refresh ? widget.refreshIndicatorExtent : 0,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final extent = constraints.maxHeight;
        _mode = _settle(extent);
        final builder = widget.builder;
        if (builder == null || extent <= 0) return const SizedBox.shrink();
        return builder(context, _mode, extent, widget.refreshTriggerPullDistance, widget.refreshIndicatorExtent);
      },
    ),
  );
}

class _PullSliver extends SingleChildRenderObjectWidget {
  const _PullSliver({required this.gap, required Widget super.child});

  final double gap;

  @override
  _RenderPullSliver createRenderObject(BuildContext context) => _RenderPullSliver(gap);

  @override
  void updateRenderObject(BuildContext context, _RenderPullSliver renderObject) => renderObject.gap = gap;
}

/// Lays its box over the overscroll, from the top of the viewport down to the first row, and while [gap] is set also
/// takes that much scroll extent, so the box stays open with the finger gone.
class _RenderPullSliver extends RenderSliver with RenderObjectWithChildMixin<RenderBox> {
  _RenderPullSliver(this._gap);

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  /// The gap the scroll offset already accounts for. Opening or closing it first corrects the offset by the change, so
  /// nothing moves on screen; the scroll physics then settle the overscroll that's left.
  double _accounted = 0;

  @override
  void performLayout() {
    assert(constraints.axisDirection == AxisDirection.down, 'a pull to refresh comes from the top');
    assert(constraints.growthDirection == GrowthDirection.forward);
    if (_gap != _accounted) {
      geometry = SliverGeometry(scrollOffsetCorrection: _gap - _accounted);
      _accounted = _gap;
      return;
    }
    final pulled = math.max(-constraints.overlap, 0.0);
    final box = child!..layout(constraints.asBoxConstraints(maxExtent: _gap + pulled), parentUsesSize: true);
    if (pulled == 0 && _gap == 0) {
      geometry = SliverGeometry.zero;
      return;
    }
    final scrolled = constraints.scrollOffset;
    final painted = math.max(math.max(box.size.height, _gap) - scrolled, 0.0);
    geometry = SliverGeometry(
      scrollExtent: _gap,
      paintOrigin: -pulled - scrolled,
      paintExtent: painted,
      maxPaintExtent: painted,
      layoutExtent: math.max(_gap - scrolled, 0.0),
      hasVisualOverflow: scrolled > 0,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (geometry!.visible) context.paintChild(child!, offset);
  }

  // The box is painted at the sliver's own paint offset.
  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) {}
}
