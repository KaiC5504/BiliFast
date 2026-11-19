import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Lets the tickers under it run only while part of it lies inside every scrollable around it, as [TickerMode] does
/// for a covered route: a mark that loops forever then draws no frames once scrolled away. It looks again when one of
/// those scrollables moves and when it is painted (the content around it moved), so nothing polls.
class TickingInSight extends StatefulWidget {
  const TickingInSight({super.key, required this.child});

  final Widget child;

  @override
  State<TickingInSight> createState() => _TickingInSightState();
}

class _TickingInSightState extends State<TickingInSight> {
  List<ScrollableState> _scrollables = const [];
  List<ScrollPosition> _positions = const [];
  bool _inSight = true;
  bool _lookPending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _follow();
  }

  @override
  void dispose() {
    for (final position in _positions) {
      position.removeListener(_lookSoon);
    }
    super.dispose();
  }

  void _follow() {
    final scrollables = <ScrollableState>[];
    // The nearest through its scope, so a new position there reaches here; the outer ones by walking up.
    for (
      var scrollable = Scrollable.maybeOf(context);
      scrollable != null;
      scrollable = scrollable.context.findAncestorStateOfType<ScrollableState>()
    ) {
      scrollables.add(scrollable);
    }
    final positions = [for (final scrollable in scrollables) scrollable.position];
    if (!listEquals(positions, _positions)) {
      for (final position in _positions) {
        position.removeListener(_lookSoon);
      }
      for (final position in positions) {
        position.addListener(_lookSoon);
      }
    }
    _scrollables = scrollables;
    _positions = positions;
    _lookSoon();
  }

  /// Once the frame's layout is done.
  void _lookSoon() {
    if (_lookPending) return;
    _lookPending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _lookPending = false;
      if (!mounted) return;
      final inSight = _measure();
      if (inSight != _inSight) setState(() => _inSight = inSight);
    }, debugLabel: 'TickingInSight');
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  bool _measure() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return _inSight;
    final area = Offset.zero & box.size;
    for (final scrollable in _scrollables) {
      final viewport = scrollable.context.findRenderObject();
      if (viewport is! RenderBox || !viewport.attached || !viewport.hasSize) continue;
      final rect = MatrixUtils.transformRect(box.getTransformTo(viewport), area);
      if (!rect.overlaps(Offset.zero & viewport.size)) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => TickerMode(
    enabled: _inSight,
    child: _PaintHook(onPaint: _lookSoon, child: widget.child),
  );
}

class _PaintHook extends SingleChildRenderObjectWidget {
  const _PaintHook({required this.onPaint, super.child});

  final VoidCallback onPaint;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderPaintHook(onPaint);

  @override
  void updateRenderObject(BuildContext context, _RenderPaintHook renderObject) => renderObject.onPaint = onPaint;
}

class _RenderPaintHook extends RenderProxyBox {
  _RenderPaintHook(this.onPaint);

  VoidCallback onPaint;

  @override
  void paint(PaintingContext context, Offset offset) {
    onPaint();
    super.paint(context, offset);
  }
}
