import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../shared/theme.dart';
import 'session_row.dart' show messageLine, messageStyle;

/// A button a chat row's swipe shows (259).
class SwipeAction {
  const SwipeAction({required this.key, required this.label, required this.fill, required this.onTap});

  final Key key;
  final String label;
  final Color fill;
  final VoidCallback onTap;
}

/// Which row of 消息 has its buttons out (259): one at a time. A touch on the page outside that row puts them away,
/// and a tap it makes on a row or an entry does nothing more ([takesTap]).
class SessionSwipes extends ChangeNotifier {
  Object? _open;
  Object? _touched;
  bool _swallowing = false;

  /// The row whose buttons are out or moving, if any.
  Object? get open => _open;

  void opened(Object row) {
    if (_open == row) return;
    _open = row;
    notifyListeners();
  }

  void closed(Object row) {
    if (_open != row) return;
    _open = null;
    notifyListeners();
  }

  void closeAll() {
    if (_open == null) return;
    _open = null;
    notifyListeners();
  }

  /// A pointer went down on [row]; the page's [pointerDown] for the same pointer comes next.
  void touchedRow(Object row) => _touched = row;

  void pointerDown() {
    final open = _open;
    final touched = _touched;
    _touched = null;
    _swallowing = open != null && touched != open;
    if (_swallowing) closeAll();
  }

  /// A tap is told during its pointer up, after the page hears that up, so the flag lasts until the event is done.
  void pointerUp() {
    if (_swallowing) scheduleMicrotask(() => _swallowing = false);
  }

  /// The touch that started this tap put a row's buttons away.
  bool takesTap() => _swallowing;
}

/// A row of 消息 that a swipe left slides over its [actions] (259): it follows the finger, opens past half or on a
/// fling left, closes on a fling back, on a tap, when another row opens, on a touch elsewhere and on a scroll. A drag
/// from the screen's left edge is left to the swipe back while the row is closed. With no actions it doesn't swipe.
class SessionSwipe extends StatefulWidget {
  const SessionSwipe({
    super.key,
    required this.id,
    required this.swipes,
    required this.actions,
    required this.onTap,
    required this.builder,
  });

  final Object id;
  final SessionSwipes swipes;

  /// Left to right.
  final List<SwipeAction> actions;

  /// A tap on the row while it is closed and the touch didn't put another row's buttons away.
  final VoidCallback onTap;

  /// The row, given what its tap does.
  final Widget Function(BuildContext context, VoidCallback onTap) builder;

  @override
  State<SessionSwipe> createState() => _SessionSwipeState();
}

class _SessionSwipeState extends State<SessionSwipe> with SingleTickerProviderStateMixin {
  /// 0 closed, 1 with every button out.
  late final AnimationController _reveal = AnimationController(vsync: this)..addListener(_moved);
  bool _dragging = false;

  double get _width => widget.actions.length * MessageTabTheme.actionWidth;

  @override
  void initState() {
    super.initState();
    widget.swipes.addListener(_othersChanged);
  }

  @override
  void didUpdateWidget(SessionSwipe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.swipes, widget.swipes)) {
      oldWidget.swipes
        ..removeListener(_othersChanged)
        ..closed(oldWidget.id);
      widget.swipes.addListener(_othersChanged);
    }
    if (widget.actions.isEmpty && _reveal.value > 0) {
      _reveal.value = 0;
    }
  }

  @override
  void dispose() {
    widget.swipes
      ..removeListener(_othersChanged)
      ..closed(widget.id);
    _reveal.dispose();
    super.dispose();
  }

  void _moved() {
    if (_reveal.value == 0 && !_dragging) widget.swipes.closed(widget.id);
  }

  void _othersChanged() {
    if (widget.swipes.open != widget.id && _reveal.value > 0 && !_dragging) _settle(0);
  }

  void _settle(double target) {
    if (target > 0) widget.swipes.opened(widget.id);
    if (_reveal.value == target) {
      _moved();
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _reveal.value = target;
    } else {
      final distance = (_reveal.value - target).abs();
      unawaited(_reveal.animateTo(target, duration: MessageTabTheme.swipeSettle * distance, curve: Curves.easeOut));
    }
  }

  void _tapped() {
    if (_reveal.value > 0) {
      _settle(0);
    } else if (!widget.swipes.takesTap()) {
      widget.onTap();
    }
  }

  /// A closed row leaves a drag from the left edge to the swipe back.
  bool _accepts(PointerEvent event) {
    if (_reveal.value > 0) return true;
    final edge = math.max(BiliMetrics.swipeBackEdge, MediaQuery.paddingOf(context).left);
    return event.localPosition.dx >= edge;
  }

  void _dragStart(DragStartDetails details) {
    _dragging = true;
    _reveal.stop();
    widget.swipes.opened(widget.id);
  }

  void _dragUpdate(DragUpdateDetails details) {
    _reveal.value = (_reveal.value - details.primaryDelta! / _width).clamp(0.0, 1.0);
  }

  void _dragEnd(DragEndDetails details) {
    _dragging = false;
    final velocity = details.primaryVelocity ?? 0;
    final open = velocity < -MessageTabTheme.swipeFling
        ? true
        : velocity > MessageTabTheme.swipeFling
        ? false
        : _reveal.value > 0.5;
    _settle(open ? 1 : 0);
  }

  void _dragCancel() {
    _dragging = false;
    _settle(_reveal.value > 0.5 ? 1 : 0);
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.builder(context, _tapped);
    if (widget.actions.isEmpty) return row;
    return Listener(
      onPointerDown: (_) => widget.swipes.touchedRow(widget.id),
      child: RawGestureDetector(
        gestures: {
          _RowDrag: GestureRecognizerFactoryWithHandlers<_RowDrag>(
            () => _RowDrag(accepts: _accepts, debugOwner: this),
            (drag) => drag
              ..onStart = _dragStart
              ..onUpdate = _dragUpdate
              ..onEnd = _dragEnd
              ..onCancel = _dragCancel,
          ),
        },
        child: ClipRect(
          child: AnimatedBuilder(
            animation: _reveal,
            child: row,
            builder: (context, row) {
              final width = _width;
              final shown = _reveal.value * width;
              return Stack(
                children: [
                  Transform.translate(offset: Offset(-shown, 0), child: row),
                  if (shown > 0)
                    Positioned(
                      top: 0,
                      bottom: 0,
                      right: shown - width,
                      width: width,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [for (final action in widget.actions) _ActionButton(action)],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RowDrag extends HorizontalDragGestureRecognizer {
  _RowDrag({required this.accepts, super.debugOwner});

  final bool Function(PointerEvent event) accepts;

  @override
  bool isPointerAllowed(PointerEvent event) => accepts(event) && super.isPointerAllowed(event);
}

class _ActionButton extends StatelessWidget {
  const _ActionButton(this.action);

  final SwipeAction action;

  @override
  Widget build(BuildContext context) {
    final style = messageStyle(MessageTabTheme.actionText, MessageTabTheme.actionInk, line: MessageTabTheme.actionLine);
    return SizedBox(
      width: MessageTabTheme.actionWidth,
      child: Semantics(
        button: true,
        label: action.label,
        onTap: action.onTap,
        excludeSemantics: true,
        child: GestureDetector(
          key: action.key,
          behavior: HitTestBehavior.opaque,
          onTap: action.onTap,
          child: ColoredBox(
            color: action.fill,
            child: Center(child: messageLine(action.label, style, align: TextAlign.center)),
          ),
        ),
      ),
    );
  }
}
