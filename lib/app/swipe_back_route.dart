import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';

/// Flutter's own Cupertino page route (its 20 pt edge swipe included) plus iOS 26's swipe back from anywhere in the
/// content, which CupertinoPageRoute does not have.
class SwipeBackPageRoute<T> extends PageRoute<T> with CupertinoRouteTransitionMixin<T> {
  SwipeBackPageRoute({required this.builder, super.settings});

  final WidgetBuilder builder;

  @override
  Widget buildContent(BuildContext context) => builder(context);

  @override
  String? get title => null;

  @override
  bool get maintainState => true;

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    return CupertinoRouteTransitionMixin.buildPageTransitions<T>(
      this,
      context,
      animation,
      secondaryAnimation,
      _ContentSwipe(enabled: () => popGestureEnabled, route: this, child: child),
    );
  }

  void _dragStart() => navigator!.didStartUserGesture();

  void _dragUpdate(double fraction) => controller!.value -= fraction;

  /// Same release rule as Flutter's edge swipe: a fling decides, otherwise past half way pops.
  void _dragEnd(double velocity) {
    final c = controller!;
    final bool forward;
    if (!isCurrent) {
      forward = isActive;
    } else if (velocity.abs() >= 1.0) {
      forward = velocity <= 0;
    } else {
      forward = c.value > 0.5;
    }
    if (forward) {
      c.animateTo(1.0, duration: const Duration(milliseconds: 350), curve: Curves.fastEaseInToSlowEaseOut);
    } else {
      if (isCurrent) navigator!.pop();
      if (c.isAnimating) c.animateBack(0.0, duration: const Duration(milliseconds: 350), curve: Curves.fastEaseInToSlowEaseOut);
    }
    if (c.isAnimating) {
      late AnimationStatusListener listener;
      listener = (status) {
        navigator?.didStopUserGesture();
        c.removeStatusListener(listener);
      };
      c.addStatusListener(listener);
    } else {
      navigator?.didStopUserGesture();
    }
  }
}

class _ContentSwipe extends StatefulWidget {
  const _ContentSwipe({required this.enabled, required this.route, required this.child});

  final bool Function() enabled;
  final SwipeBackPageRoute<dynamic> route;
  final Widget child;

  @override
  State<_ContentSwipe> createState() => _ContentSwipeState();
}

class _ContentSwipeState extends State<_ContentSwipe> {
  late final _RightwardDragRecognizer _recognizer;
  bool _active = false;

  @override
  void initState() {
    super.initState();
    _recognizer = _RightwardDragRecognizer(debugOwner: this)
      ..onStart = (_) {
        _active = true;
        widget.route._dragStart();
      }
      ..onUpdate = (d) {
        if (_active) widget.route._dragUpdate(d.primaryDelta! / context.size!.width);
      }
      ..onEnd = (d) {
        if (!_active) return;
        _active = false;
        widget.route._dragEnd(d.velocity.pixelsPerSecond.dx / context.size!.width);
      }
      ..onCancel = () {
        if (!_active) return;
        _active = false;
        widget.route._dragEnd(0);
      };
  }

  @override
  void dispose() {
    _recognizer.dispose();
    if (_active) widget.route.navigator?.didStopUserGesture();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        if (widget.enabled()) _recognizer.addPointer(e);
      },
      child: widget.child,
    );
  }
}

/// A horizontal drag that only claims the gesture when it heads right, so leftward drags stay with the page.
///
/// Where nothing else under the finger takes drags (a page too short to scroll, or the player once its taps give
/// up), it is alone in the arena and wins on touch-down, so it waits for the slop before starting and turns down a
/// drag that is more vertical than horizontal by then.
class _RightwardDragRecognizer extends HorizontalDragGestureRecognizer {
  _RightwardDragRecognizer({super.debugOwner}) {
    onlyAcceptDragOnThreshold = true;
  }

  double _dx = 0;
  double _dy = 0;
  bool _tooVertical = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _dx = 0;
    _dy = 0;
    _tooVertical = false;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      _dx += event.delta.dx;
      _dy += event.delta.dy;
      if (_dx < -kTouchSlop / 2) {
        _giveUp(event.pointer);
        return;
      }
    }
    super.handleEvent(event);
    if (_tooVertical) {
      _tooVertical = false;
      _giveUp(event.pointer);
    }
  }

  // Not resolve + stopTrackingPointer: once the arena has closed in our favour, only rejectGesture drops the pointer
  // from the accepted ones, and a stale one there stops the next drag tracking its moves until it wins.
  void _giveUp(int pointer) => rejectGesture(pointer);

  @override
  bool hasSufficientGlobalDistanceToAccept(PointerDeviceKind pointerDeviceKind, double? deviceTouchSlop) {
    if (!super.hasSufficientGlobalDistanceToAccept(pointerDeviceKind, deviceTouchSlop)) return false;
    // Judged at the exact moment the drag would start; giving up from in here would leave super mid-event.
    _tooVertical = _dy.abs() > _dx.abs();
    return !_tooVertical && _dx > 0;
  }

  @override
  String get debugDescription => 'rightward drag';
}
