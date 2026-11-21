import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';
import '../page_details.dart' show PageTab;

/// Where 竖屏's 简介/评论 sheet rests: closed (plain 竖屏), half (264) or full (266).
enum SheetStop { closed, half, full }

/// 竖屏's 简介/评论 sheet (264-271): where it is, which tab it shows, and the drags that move it. [position] runs from
/// 0 (closed) through 1 (half) to 2 (full), following the finger between the stops and animating to them.
class StorySheetController extends ChangeNotifier {
  StorySheetController({required TickerProvider vsync}) : _motion = AnimationController.unbounded(vsync: vsync) {
    _motion.addListener(_moved);
  }

  final AnimationController _motion;
  final _position = ValueNotifier<double>(0);
  SheetStop _stop = SheetStop.closed;
  PageTab _tab = PageTab.comments;

  /// What the running animation's value means as a position: a curve's progress, or a spring's top edge in points.
  double Function(double value) _map = (value) => value;

  bool _dragging = false;
  bool _raises = true;
  SheetStop _dragFrom = SheetStop.closed;
  bool _disposed = false;

  /// The height of the screen the sheet moves on; the view sets it as it lays out, and the drags pass it too.
  double? screenHeight;

  /// Reduce Motion: moves jump to their stop. The view sets it from the page's MediaQuery.
  bool still = false;

  /// Changes every frame the sheet moves; [topFor] turns it into the sheet's top edge. A snap's spring carries it a
  /// little past 2 for a few frames as it lands on full.
  ValueListenable<double> get position => _position;

  /// The stop the sheet rests at, or is heading for.
  SheetStop get stop => _stop;

  /// Open, moving or under the finger: 竖屏's own controls and swipe stand aside.
  bool get isOpen => _stop != SheetStop.closed || _position.value > 0 || _dragging;

  /// A finger is moving the sheet.
  bool get dragging => _dragging;

  PageTab get tab => _tab;

  void selectTab(PageTab tab) {
    if (tab == _tab) return;
    _tab = tab;
    notifyListeners();
  }

  /// From 竖屏: up to half on [tab] (评论 from the column's button, 简介 from the title).
  void open(PageTab tab) {
    final switched = tab != _tab;
    _tab = tab;
    _settle(SheetStop.half, changed: switched);
  }

  void close() => _settle(SheetStop.closed);

  /// The round expand / collapse button: half and full.
  void toggle() => _settle(_stop == SheetStop.full ? SheetStop.half : SheetStop.full);

  /// Up to full (the accessibility action 展开).
  void expand() => _settle(SheetStop.full);

  /// Down to half (收起).
  void collapse() => _settle(SheetStop.half);

  /// A finger takes the sheet. With [raises] false (a list pulled down at its top) it never lifts the sheet above the
  /// stop it found it at, nor flings it past.
  void dragStart({bool raises = true}) {
    _motion.stop();
    if (_dragging) return;
    _dragging = true;
    _raises = raises;
    _dragFrom = _stop;
    notifyListeners();
  }

  /// The finger moved [delta] points, down positive, on a screen [screenHeight] tall. Ignored outside a drag, as after
  /// [close] took the sheet from under the finger.
  void dragUpdate(double delta, double screenHeight) {
    this.screenHeight = screenHeight;
    if (!_dragging) return;
    final highest = _raises ? StorySheetTheme.fullTop : topFor(_dragFrom.index.toDouble(), screenHeight);
    final top = topFor(_position.value, screenHeight) + delta;
    _position.value = positionFor(math.max(highest, math.min(top, screenHeight)), screenHeight);
  }

  /// The finger lifted at [velocity] points a second, down positive.
  void dragEnd(double velocity, double screenHeight) {
    this.screenHeight = screenHeight;
    if (!_dragging) return;
    _dragging = false;
    final target = _landing(velocity);
    _stop = target;
    if (target == SheetStop.closed) {
      _animateTo(target);
    } else {
      _spring(target, velocity, screenHeight);
    }
    notifyListeners();
  }

  /// Where a let-go lands: a fling's next stop that way, else back to the stop the drag left unless the sheet was
  /// carried past another, and closed once little of the half sheet shows.
  SheetStop _target(double velocity) {
    const near = 0.02;
    final at = _position.value;
    if (velocity >= StorySheetTheme.flingVelocity) {
      return SheetStop.values.lastWhere((stop) => stop.index < at - near, orElse: () => SheetStop.closed);
    }
    if (velocity <= -StorySheetTheme.flingVelocity) {
      return SheetStop.values.firstWhere((stop) => stop.index > at + near, orElse: () => SheetStop.full);
    }
    final from = _dragFrom.index;
    var target = _dragFrom;
    for (final stop in SheetStop.values) {
      final passed = at < from ? stop.index < from && stop.index >= at : stop.index > from && stop.index <= at;
      if (passed && (stop.index - at).abs() < (target.index - at).abs()) target = stop;
    }
    if (target != SheetStop.closed && at < StorySheetTheme.closeShare) target = SheetStop.closed;
    return target;
  }

  /// [_target], no higher than the stop the drag found when it may not raise the sheet.
  SheetStop _landing(double velocity) {
    final target = _target(velocity);
    return !_raises && target.index > _dragFrom.index ? _dragFrom : target;
  }

  void _settle(SheetStop stop, {bool changed = false}) {
    if (_disposed) return;
    changed |= stop != _stop || _dragging;
    _stop = stop;
    _dragging = false;
    _animateTo(stop);
    if (changed) notifyListeners();
  }

  /// [stop] over [StorySheetTheme.move], evenly in points when the screen is known (closing from full crosses half,
  /// where a position's points change).
  void _animateTo(SheetStop stop) {
    _motion.stop();
    final end = stop.index.toDouble();
    final start = _position.value;
    if (start == end) return;
    if (still) {
      _position.value = end;
      return;
    }
    final height = screenHeight;
    if (height == null) {
      _map = (value) => lerpDouble(start, end, StorySheetTheme.moveCurve.transform(value))!;
    } else {
      final from = topFor(start, height);
      final to = topFor(end, height);
      _map = (value) => positionFor(lerpDouble(from, to, StorySheetTheme.moveCurve.transform(value))!, height);
    }
    _motion.value = 0;
    _land(_motion.animateTo(1, duration: StorySheetTheme.move, curve: Curves.linear), stop);
  }

  /// A let-go onto an open stop: the spring in points from where the finger left it, at its speed.
  void _spring(SheetStop stop, double velocity, double height) {
    _motion.stop();
    final end = stop.index.toDouble();
    if (still) {
      _position.value = end;
      return;
    }
    final from = topFor(_position.value, height);
    final to = topFor(end, height);
    final spring = SpringDescription.withDampingRatio(
      mass: 1,
      stiffness: StorySheetTheme.snapFrequency * StorySheetTheme.snapFrequency,
      ratio: StorySheetTheme.snapDampingRatio,
    );
    _map = (value) => positionFor(value, height);
    _motion.value = from;
    _land(_motion.animateWith(SpringSimulation(spring, from, to, velocity, tolerance: _landed)), stop);
  }

  /// Within a tenth of a point and barely moving, the spring has landed: the default waits for a thousandth of a
  /// point a second, 200 ms after the sheet looks still.
  static const _landed = Tolerance(distance: 0.1, velocity: 10);

  /// Lands exactly on [stop] once the move completes; an interrupted move leaves it where it is.
  void _land(TickerFuture move, SheetStop stop) {
    unawaited(
      move.then((_) {
        if (!_disposed && _stop == stop && !_dragging) _position.value = stop.index.toDouble();
      }),
    );
  }

  void _moved() => _position.value = math.max(0, _map(_motion.value));

  /// The sheet's top edge for [position] on a screen [screenHeight] tall. Past 2 it keeps rising at full's pace.
  static double topFor(double position, double screenHeight) => position <= 1
      ? lerpDouble(screenHeight, StorySheetTheme.halfTop, position.clamp(0, 1))!
      : StorySheetTheme.halfTop - (position - 1) * (StorySheetTheme.halfTop - StorySheetTheme.fullTop);

  /// The position whose top edge is [top] on a screen [screenHeight] tall: [topFor] turned around.
  static double positionFor(double top, double screenHeight) {
    if (top >= StorySheetTheme.halfTop) {
      final travel = screenHeight - StorySheetTheme.halfTop;
      return travel <= 0 ? (top >= screenHeight ? 0 : 1) : ((screenHeight - top) / travel).clamp(0.0, 1.0);
    }
    return 1 + (StorySheetTheme.halfTop - top) / (StorySheetTheme.halfTop - StorySheetTheme.fullTop);
  }

  @override
  void dispose() {
    _disposed = true;
    _motion.dispose();
    _position.dispose();
    super.dispose();
  }
}
