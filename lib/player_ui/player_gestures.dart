import 'dart:async';
import 'dart:math' as math;

import 'package:bili_core/devlog.dart';
import 'package:bili_core/logic.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../device/orientation.dart';
import '../shared/theme.dart';
import 'chrome_state.dart';
import 'player_ui.dart';
import 'seek_bar.dart';

/// The touch layer over the video, filling the player (port of BiliNative `PlayerGestureView.swift` and
/// `ChromeState.swift`'s gestures): tap, double tap, hold for 2×, a sideways drag to seek, and in full screen
/// up and down for brightness (left half) and volume (right half), with the screen edges left to the system. In 竖屏
/// the controls stay up, as in the official app: a tap plays or pauses at once and a double tap is two taps, and a
/// swipe right from the left edge is its ‹.
class PlayerGestureLayer extends StatefulWidget {
  const PlayerGestureLayer({super.key, required this.ui});

  final PlayerUi ui;

  /// Shorter than Flutter's 300 ms double-tap timeout, so a single tap toggles the controls sooner.
  static const doubleTapWindow = Duration(milliseconds: 250);

  static const holdDelay = Duration(milliseconds: 350);

  /// How long the level stays up after a hardware volume button.
  static const hardwareVolumeShown = Duration(seconds: 1);

  /// 竖屏's edge swipe goes back once released past this share of the screen's width, or flung faster than
  /// [edgeFlingWidths] screen widths a second (rightward goes back, leftward doesn't): CupertinoPageRoute's swipe back.
  static const edgeBackShare = 0.5;
  static const edgeFlingWidths = 1.0;

  @override
  State<PlayerGestureLayer> createState() => _PlayerGestureLayerState();
}

class _Seek {
  _Seek({required this.start, required this.width}) : target = start;

  final double start;
  final double width;
  double target;
  double? anchor;
  Timer? rest;
}

class _Level {
  _Level(this.kind, {required this.height});

  final LevelKind kind;
  final double height;

  /// Read from the device when the drag starts; updates before it arrives wait for it.
  double? start;
  double dy = 0;
  double? value;

  /// The device refused a read or a set: the rest of the drag does nothing.
  bool failed = false;
}

class _PlayerGestureLayerState extends State<PlayerGestureLayer> {
  Size _screen = Size.zero;
  EdgeInsets _padding = EdgeInsets.zero;
  ModalRoute<Object?>? _route;

  Timer? _tapTimer;
  Offset? _firstTap;
  bool _secondTapDown = false;

  bool _holding = false;
  _Seek? _seek;
  _Level? _level;

  StreamSubscription<double>? _hardwareVolume;
  Timer? _hardwareTimer;

  PlayerUi get _ui => widget.ui;

  @override
  void initState() {
    super.initState();
    _hardwareVolume = _ui.device.hardwareVolume.listen(_hardwareVolumeChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _screen = MediaQuery.sizeOf(context);
    _padding = MediaQuery.paddingOf(context);
    _route = ModalRoute.of(context);
  }

  @override
  void didUpdateWidget(PlayerGestureLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.ui;
    if (old.session != _ui.session || old.chrome != _ui.chrome) _abandon(old);
    if (old.device != _ui.device) {
      unawaited(_hardwareVolume?.cancel());
      _hardwareVolume = _ui.device.hardwareVolume.listen(_hardwareVolumeChanged);
    }
  }

  @override
  void dispose() {
    _abandon(_ui);
    _tapTimer?.cancel();
    _hardwareTimer?.cancel();
    unawaited(_hardwareVolume?.cancel());
    super.dispose();
  }

  /// Ends whatever a finger is doing, as if it had been cancelled.
  void _abandon(PlayerUi ui) {
    final seek = _seek;
    if (seek != null) {
      _seek = null;
      seek.rest?.cancel();
      ui.session.cancelScrub();
      _clearHud<SeekHud>(ui.chrome);
    }
    if (_holding) {
      _holding = false;
      ui.session.speedUp(false);
      _clearHud<SpeedUpHud>(ui.chrome);
    }
    if (_level != null) {
      _level = null;
      _clearHud<LevelHud>(ui.chrome);
    }
  }

  void _clearHud<T extends Hud>(ChromeState chrome) {
    if (chrome.hud.value is T) chrome.showHud(null);
  }

  bool _inSystemEdge(Offset global) =>
      _ui.presentation.fullScreen && !(Offset.zero & _screen).deflate(GestureMath.edgeInset).contains(global);

  double get _backEdge => math.max(BiliMetrics.swipeBackEdge, _padding.left);

  bool _inBackSwipeEdge(Offset global) {
    if (_ui.presentation.fullScreen) return false;
    final route = _route;
    final edgeSwipes = (_ui.edgeTaken?.value ?? false) || (route is PageRoute<Object?> && route.popGestureEnabled);
    return edgeSwipes && global.dx < _backEdge;
  }

  /// In 竖屏 the left edge is the edge swipe's alone; the page's held PopScope keeps the route's own swipe off there.
  bool _inVerticalBackEdge(Offset global) => _vertical && global.dx < _backEdge;

  bool _allowsTouch(PointerDownEvent event) =>
      !_inSystemEdge(event.position) && !_inVerticalBackEdge(event.position);

  bool _allowsDrag(PointerDownEvent event) => _allowsTouch(event) && !_inBackSwipeEdge(event.position);

  bool _allowsEdgeSwipe(PointerDownEvent event) => _inVerticalBackEdge(event.position);

  bool get _vertical => _ui.presentation == Presentation.vertical;

  void _edgeSwipeEnded(Offset delta, double velocity) {
    final width = _screen.width;
    if (!_vertical || !(width > 0) || delta.dx.abs() < delta.dy.abs()) return;
    final speed = velocity / width;
    final back = speed.abs() >= PlayerGestureLayer.edgeFlingWidths
        ? speed > 0
        : delta.dx / width > PlayerGestureLayer.edgeBackShare;
    if (back) _ui.onBack();
  }

  void _singleTap() {
    if (_vertical) {
      _ui.session.togglePlay();
      _ui.chrome.show();
    } else {
      _ui.chrome.toggle();
    }
  }

  void _doubleTap() {
    _ui.session.togglePlay();
    _ui.chrome.show();
  }

  void _tapPointerDown(PointerDownEvent event) {
    final first = _firstTap;
    final timer = _tapTimer;
    if (first == null || timer == null || !timer.isActive) return;
    timer.cancel();
    if ((event.position - first).distance <= kDoubleTapSlop) {
      _secondTapDown = true;
    } else {
      _firstTap = null;
      _singleTap();
    }
  }

  void _tapUp(TapUpDetails details) {
    if (_vertical && !_secondTapDown) {
      _singleTap();
      return;
    }
    if (_secondTapDown) {
      _secondTapDown = false;
      _firstTap = null;
      _doubleTap();
      return;
    }
    _firstTap = details.globalPosition;
    _tapTimer = Timer(PlayerGestureLayer.doubleTapWindow, () {
      _firstTap = null;
      if (mounted) _singleTap();
    });
  }

  /// The second touch of a double tap became a hold or a drag: the first tap stands alone.
  void _tapRejected() {
    if (!_secondTapDown) return;
    _secondTapDown = false;
    _firstTap = null;
    _singleTap();
  }

  void _holdBegan() {
    // A paused player would start playing at 2×.
    if (!_ui.session.readout.wantsPlay) return;
    _holding = true;
    _ui.session.speedUp(true);
    unawaited(HapticFeedback.mediumImpact());
    if (!_vertical) _ui.chrome.hide();
    _ui.chrome.showHud(const SpeedUpHud());
  }

  void _holdEnded() {
    if (!_holding) return;
    _holding = false;
    _ui.session.speedUp(false);
    unawaited(HapticFeedback.mediumImpact());
    _clearHud<SpeedUpHud>(_ui.chrome);
  }

  void _dragStart(GestureAxis axis, Offset local) {
    final size = context.size ?? Size.zero;
    if (axis == GestureAxis.horizontal) {
      if (!(_ui.session.duration.value > 0)) return;
      _seek = _Seek(start: _ui.session.position, width: size.width);
      return;
    }
    final kind = local.dx < size.width / 2 ? LevelKind.brightness : LevelKind.volume;
    final level = _level = _Level(kind, height: size.height);
    _hardwareTimer?.cancel();
    final device = _ui.device;
    unawaited(
      (kind == LevelKind.brightness ? device.brightness() : device.volume()).then(
        (value) {
          if (!identical(_level, level)) return;
          level.start = value;
          _applyLevel(level);
        },
        onError: (Object error) => _levelFailed(level, error),
      ),
    );
  }

  void _dragUpdate(Offset delta, Offset local) {
    if (_seek case final seek?) {
      final duration = _ui.session.duration.value;
      final target = seek.target = GestureMath.seekTarget(
        start: seek.start,
        dx: delta.dx,
        width: seek.width,
        duration: duration,
      );
      _ui.session.scrub(target);
      _ui.chrome.showHud(SeekHud(target: target, duration: duration));
      _followRest(seek, local.dx);
    } else if (_level case final level?) {
      level.dy = delta.dy;
      _applyLevel(level);
    }
  }

  void _dragEnd(Offset delta) {
    final seek = _seek;
    if (seek == null) {
      _endLevel();
      return;
    }
    _seek = null;
    seek.rest?.cancel();
    final target = GestureMath.seekTarget(
      start: seek.start,
      dx: delta.dx,
      width: seek.width,
      duration: _ui.session.duration.value,
    );
    _clearHud<SeekHud>(_ui.chrome);
    unawaited(_ui.session.commitSeek(target));
  }

  void _dragCancel() {
    final seek = _seek;
    if (seek == null) {
      _endLevel();
      return;
    }
    _seek = null;
    seek.rest?.cancel();
    _clearHud<SeekHud>(_ui.chrome);
    _ui.session.cancelScrub();
  }

  /// As the seek bar does: a finger resting mid-drag is where it is likely to let go.
  void _followRest(_Seek seek, double x) {
    final anchor = seek.anchor;
    if (anchor != null && (x - anchor).abs() <= SeekBar.restSlop) return;
    seek.anchor = x;
    seek.rest?.cancel();
    seek.rest = Timer(SeekBar.restDelay, () {
      if (identical(_seek, seek)) _ui.session.hint(seek.target);
    });
  }

  void _applyLevel(_Level level) {
    final start = level.start;
    if (start == null || level.failed) return;
    final value = GestureMath.level(start: start, dy: level.dy, height: level.height);
    _ui.chrome.showHud(LevelHud(level.kind, value));
    if (value == level.value) return;
    level.value = value;
    final device = _ui.device;
    unawaited(
      (level.kind == LevelKind.brightness ? device.setBrightness(value) : device.setVolume(value))
          .catchError((Object error) => _levelFailed(level, error)),
    );
  }

  void _levelFailed(_Level level, Object error) {
    if (level.failed) return;
    level.failed = true;
    Logger.shared.warn(LogCategory.ui, '${level.kind.name} gesture failed', {'error': '$error'});
    if (mounted && identical(_level, level)) _clearHud<LevelHud>(_ui.chrome);
  }

  void _endLevel() {
    if (_level == null) return;
    _level = null;
    _clearHud<LevelHud>(_ui.chrome);
  }

  void _hardwareVolumeChanged(double value) {
    if (!_ui.presentation.fullScreen || _level != null) return;
    final chrome = _ui.chrome;
    chrome.showHud(LevelHud(LevelKind.volume, value));
    _hardwareTimer?.cancel();
    _hardwareTimer = Timer(PlayerGestureLayer.hardwareVolumeShown, () {
      final hud = chrome.hud.value;
      if (mounted && _level == null && hud is LevelHud && hud.kind == LevelKind.volume) chrome.showHud(null);
    });
  }

  @override
  Widget build(BuildContext context) {
    // RawGestureDetector gives the private recognisers no semantics, so VoiceOver and the Windows test driver need
    // this node to show or hide the controls (in 竖屏, to play or pause).
    return Semantics(
      container: true,
      button: true,
      label: '视频画面',
      onTap: _singleTap,
      child: _gestures(),
    );
  }

  Widget _gestures() {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        _TapRecognizer: GestureRecognizerFactoryWithHandlers<_TapRecognizer>(
          () => _TapRecognizer(debugOwner: this),
          (recognizer) => recognizer
            ..allow = _allowsTouch
            ..onPointerDown = _tapPointerDown
            ..onRejected = _tapRejected
            ..onTapUp = _tapUp,
        ),
        _HoldRecognizer: GestureRecognizerFactoryWithHandlers<_HoldRecognizer>(
          () => _HoldRecognizer(debugOwner: this),
          (recognizer) => recognizer
            ..allow = _allowsTouch
            ..onLongPressStart = ((_) => _holdBegan())
            ..onLongPressEnd = ((_) => _holdEnded())
            ..onStopped = _holdEnded,
        ),
        _DragRecognizer: GestureRecognizerFactoryWithHandlers<_DragRecognizer>(
          () => _DragRecognizer(debugOwner: this),
          (recognizer) => recognizer
            ..allow = _allowsDrag
            ..levels = (() => _ui.presentation.fullScreen)
            ..onStart = _dragStart
            ..onUpdate = _dragUpdate
            ..onEnd = _dragEnd
            ..onCancel = _dragCancel,
        ),
        _EdgeSwipeRecognizer: GestureRecognizerFactoryWithHandlers<_EdgeSwipeRecognizer>(
          () => _EdgeSwipeRecognizer(debugOwner: this),
          (recognizer) => recognizer
            ..allow = _allowsEdgeSwipe
            ..onEnd = _edgeSwipeEnded,
        ),
      },
      child: const SizedBox.expand(),
    );
  }
}

bool _anyTouch(PointerDownEvent event) => true;

bool _never() => false;

class _TapRecognizer extends TapGestureRecognizer {
  _TapRecognizer({super.debugOwner});

  bool Function(PointerDownEvent event) allow = _anyTouch;

  /// Every touch this recogniser takes, as it lands: tap down only comes 100 ms later or at the lift.
  ValueChanged<PointerDownEvent>? onPointerDown;
  VoidCallback? onRejected;

  @override
  bool isPointerAllowed(PointerDownEvent event) => allow(event) && super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    onPointerDown?.call(event);
    super.addAllowedPointer(event);
  }

  @override
  void rejectGesture(int pointer) {
    super.rejectGesture(pointer);
    onRejected?.call();
  }
}

class _HoldRecognizer extends LongPressGestureRecognizer {
  _HoldRecognizer({super.debugOwner}) : super(duration: PlayerGestureLayer.holdDelay);

  bool Function(PointerDownEvent event) allow = _anyTouch;

  /// The finger is gone however it went: a cancelled touch after the hold began reports no end.
  VoidCallback? onStopped;

  @override
  bool isPointerAllowed(PointerDownEvent event) => allow(event) && super.isPointerAllowed(event);

  @override
  void didStopTrackingLastPointer(int pointer) {
    super.didStopTrackingLastPointer(pointer);
    onStopped?.call();
  }
}

/// One finger's drag, claimed once it has moved [GestureMath.axisLockDistance] and its axis is known, well inside
/// the 18 px slop of Flutter's own drags and taps. A vertical drag is turned down unless [levels] allows it, so a
/// scroller under the player gets it.
class _DragRecognizer extends OneSequenceGestureRecognizer {
  _DragRecognizer({super.debugOwner});

  bool Function(PointerDownEvent event) allow = _anyTouch;
  bool Function() levels = _never;
  void Function(GestureAxis axis, Offset localDown)? onStart;

  /// The travel since the finger landed, and where it is.
  void Function(Offset delta, Offset local)? onUpdate;
  ValueChanged<Offset>? onEnd;
  VoidCallback? onCancel;

  int? _pointer;
  Offset _down = Offset.zero;
  Offset _local = Offset.zero;
  GestureAxis? _axis;

  /// Won the arena, which can happen before the axis is known when every other recogniser gave up.
  bool _won = false;
  bool _started = false;

  @override
  String get debugDescription => 'player drag';

  @override
  bool isPointerAllowed(PointerDownEvent event) => _pointer == null && allow(event) && super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _pointer = event.pointer;
    _down = event.localPosition;
    _local = event.localPosition;
  }

  @override
  void handleEvent(PointerEvent event) {
    final pointer = _pointer;
    if (pointer == null || event.pointer != pointer) return;
    switch (event) {
      case PointerMoveEvent():
        _local = event.localPosition;
        if (_started) {
          onUpdate?.call(_local - _down, _local);
          return;
        }
        final delta = _local - _down;
        final axis = GestureMath.axis(dx: delta.dx, dy: delta.dy);
        if (axis == null) return;
        if (axis == GestureAxis.vertical && !levels()) {
          if (!_won) resolve(GestureDisposition.rejected);
          stopTrackingPointer(pointer);
          return;
        }
        _axis = axis;
        if (_won) {
          _start();
        } else {
          resolve(GestureDisposition.accepted);
        }
      case PointerUpEvent():
        if (_started) {
          onEnd?.call(event.localPosition - _down);
        } else if (!_won) {
          resolve(GestureDisposition.rejected);
        }
        stopTrackingPointer(pointer);
      case PointerCancelEvent():
        if (_started) {
          onCancel?.call();
        } else if (!_won) {
          resolve(GestureDisposition.rejected);
        }
        stopTrackingPointer(pointer);
      default:
        break;
    }
  }

  @override
  void acceptGesture(int pointer) {
    if (pointer != _pointer || _won) return;
    _won = true;
    if (_axis != null) _start();
  }

  @override
  void rejectGesture(int pointer) => stopTrackingPointer(pointer);

  void _start() {
    _started = true;
    onStart?.call(_axis!, _down);
    onUpdate?.call(_local - _down, _local);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _pointer = null;
    _axis = null;
    _won = false;
    _started = false;
  }
}

/// 竖屏's swipe from the left edge: claimed once the finger has moved [GestureMath.axisLockDistance] rightward and
/// sideways, turned down on any other way. Nothing follows the finger; [onEnd] judges the lift.
class _EdgeSwipeRecognizer extends OneSequenceGestureRecognizer {
  _EdgeSwipeRecognizer({super.debugOwner});

  bool Function(PointerDownEvent event) allow = _anyTouch;

  /// The travel since the finger landed, and the lift's sideways fling speed (0 when it wasn't a fling).
  void Function(Offset delta, double velocity)? onEnd;

  int? _pointer;
  PointerDeviceKind _kind = PointerDeviceKind.touch;
  Offset _down = Offset.zero;
  VelocityTracker? _tracker;
  bool _won = false;
  bool _swiping = false;

  @override
  String get debugDescription => 'player edge swipe';

  @override
  bool isPointerAllowed(PointerDownEvent event) => _pointer == null && allow(event) && super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _pointer = event.pointer;
    _kind = event.kind;
    _down = event.localPosition;
    _tracker = VelocityTracker.withKind(event.kind)..addPosition(event.timeStamp, event.localPosition);
  }

  @override
  void handleEvent(PointerEvent event) {
    final pointer = _pointer;
    if (pointer == null || event.pointer != pointer) return;
    switch (event) {
      case PointerMoveEvent():
        if (!event.synthesized) _tracker?.addPosition(event.timeStamp, event.localPosition);
        if (_swiping) return;
        final delta = event.localPosition - _down;
        final axis = GestureMath.axis(dx: delta.dx, dy: delta.dy);
        if (axis == null) return;
        if (axis == GestureAxis.vertical || delta.dx < 0) {
          if (!_won) resolve(GestureDisposition.rejected);
          stopTrackingPointer(pointer);
          return;
        }
        _swiping = true;
        if (!_won) resolve(GestureDisposition.accepted);
      case PointerUpEvent():
        if (_swiping && _won) {
          onEnd?.call(event.localPosition - _down, _flingVelocity());
        } else if (!_won) {
          resolve(GestureDisposition.rejected);
        }
        stopTrackingPointer(pointer);
      case PointerCancelEvent():
        if (!_won) resolve(GestureDisposition.rejected);
        stopTrackingPointer(pointer);
      default:
        break;
    }
  }

  /// As DragGestureRecognizer reports a fling: anything slower or shorter counts as no speed at all.
  double _flingVelocity() {
    final estimate = _tracker?.getVelocityEstimate();
    if (estimate == null) return 0;
    final speed = estimate.pixelsPerSecond.dx;
    final fling = speed.abs() > kMinFlingVelocity && estimate.offset.dx.abs() > computeHitSlop(_kind, gestureSettings);
    return fling ? speed : 0;
  }

  @override
  void acceptGesture(int pointer) {
    if (pointer == _pointer) _won = true;
  }

  @override
  void rejectGesture(int pointer) => stopTrackingPointer(pointer);

  @override
  void didStopTrackingLastPointer(int pointer) {
    _pointer = null;
    _tracker = null;
    _won = false;
    _swiping = false;
  }
}
