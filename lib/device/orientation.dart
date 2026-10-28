import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../app/form_factor.dart';
import 'device_controls.dart';
import 'orientation_host.dart';

enum Presentation {
  inline,
  landscape,

  /// 竖屏: a vertical video full screen, the phone upright.
  vertical;

  bool get fullScreen => this != inline;
}

/// Full screen is the same page laid out again, never a new route (port of BiliNative `OrientationController.swift`).
/// The rules live here; the host only applies masks and reports the phone's orientation. Without a host (Windows)
/// every move applies at once.
///
/// Pages stack: the latest [begin] wins, and a covered page's late [end] does nothing.
///
/// The iPad (read from [FormFactor.device] at each move) turns freely on every screen and is never asked to rotate:
/// full screen is entered and left only by the controls, in whichever way the iPad is held, and has no 竖屏 (an
/// upright video's full screen is [Presentation.landscape]). Its lock only shows as on.
class OrientationController extends ChangeNotifier {
  OrientationController({DeviceControls? controls, OrientationHost? host, Logger? logger})
      : controls = controls ?? NoDeviceControls(),
        _host = host,
        _logger = logger ?? Logger.shared {
    if (host != null) {
      _subscriptions = [
        host.deviceOrientations.listen(_deviceOrientationChanged),
        host.refusals.listen((refusal) => _refused(refusal.request, refusal.error)),
      ];
    }
  }

  final DeviceControls controls;
  final OrientationHost? _host;
  final Logger _logger;
  List<StreamSubscription<Object?>> _subscriptions = const [];

  Presentation get presentation => _presentation;
  Presentation _presentation = Presentation.inline;

  /// The rotation lock: turning the phone does nothing while it is on; it ends with the page, or when another page
  /// begins. The iPad's turns never change the presentation, so there it changes nothing.
  bool get locked => _locked;
  bool _locked = false;

  bool get videoIsVertical => _videoIsVertical;
  bool _videoIsVertical = false;

  /// Whether turns are drawn by Flutter rather than animated by the system: the 开发者 choice 旋转动画, armed only
  /// while a page owns the orientation, since only that page draws them. Always off without a host.
  bool get turnTakeover => _turnTakeover;
  bool _turnTakeover = false;
  int _takeoverSends = 0;

  /// The 开发者 choice (自绘 when true), armed or not.
  bool get turnTakeoverChosen => _takeoverChosen;
  bool _takeoverChosen = false;

  /// What the host was last sent.
  bool _sent = false;

  /// A send failed, so the host may be in either state: the next sync goes out whatever it carries.
  bool _sentUnknown = false;

  /// The taken-over turns as the system starts them; empty without a host or while [turnTakeover] is off.
  Stream<TurnStart> get turns => _host?.turns ?? const Stream.empty();

  /// The 开发者 choice; the host has it while a page owns the orientation.
  Future<void> setTurnTakeover(bool enabled) {
    _takeoverChosen = enabled;
    return _syncTakeover();
  }

  /// Queued with the requests, so a request made after a change goes out after it: an exit with no page to draw it
  /// gets the system's turn rather than a still picture.
  Future<void> _syncTakeover() {
    final host = _host;
    final armed = _takeoverChosen && _owner != null && !_pad;
    if (host == null || (armed == _sent && !_sentUnknown)) return Future.value();
    _turnTakeover = armed;
    _sent = armed;
    _sentUnknown = false;
    final send = ++_takeoverSends;
    return _hostQueue = _hostQueue.then((_) async {
      try {
        await host.setTurnTakeover(armed);
      } catch (error) {
        if (send == _takeoverSends) {
          _turnTakeover = false;
          _sentUnknown = true;
        }
        _hostFailed(error);
      }
    });
  }

  /// The first frame of taken-over [turn] is drawn, so the host can drop its still picture.
  void turnDrawn(int turn) => _host?.turnDrawn(turn).catchError(_hostFailed);

  Object? _owner;
  bool _observing = false;
  PhoneOrientation? _lastDeviceOrientation;

  /// Landscape was entered by the button with the phone flat or upright. Lifting it off the table reports portrait
  /// before anyone has turned it, so portrait only exits once the phone has really been landscape.
  bool _awaitingLandscape = false;

  /// Bumped by every move, so a late refusal cannot undo a newer one.
  int _requests = 0;
  ({int request, Presentation previous, Presentation next})? _lastMove;
  Future<void> _hostQueue = Future.value();

  /// The most recent begin wins. A page shown again calls it too, so its own vertical flag comes back.
  void begin(Object owner, {required bool videoIsVertical}) {
    var exited = false;
    if (!identical(_owner, owner)) {
      if (_owner != null) {
        // The previous page is covered or being popped: its lock and full screen are not this page's. Neither page
        // draws that exit, so it goes out unowned.
        _locked = false;
        _owner = null;
        if (_presentation != Presentation.inline) {
          exitToInline();
          exited = true;
        }
      }
      _owner = owner;
    }
    // After such an exit the takeover waits for this page's first move: armed now, it could reach the host before
    // the exit's turn has started.
    if (!exited) unawaited(_syncTakeover());
    _videoIsVertical = videoIsVertical;
    if (!_observing) {
      _observing = true;
      if (!_pad) _host?.setOrientationEvents(true).catchError(_hostFailed);
    }
    notifyListeners();
  }

  void setVideoIsVertical(bool vertical, {required Object owner}) {
    if (!identical(_owner, owner)) return;
    _videoIsVertical = vertical;
    notifyListeners();
  }

  /// Does nothing unless [owner] began last.
  void end(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    unawaited(_syncTakeover());
    if (_observing) {
      _observing = false;
      _lastDeviceOrientation = null;
      if (!_pad) _host?.setOrientationEvents(false).catchError(_hostFailed);
    }
    _locked = false;
    _videoIsVertical = false;
    if (_presentation != Presentation.inline) exitToInline();
    notifyListeners();
  }

  void toggleLock() {
    _locked = !_locked;
    notifyListeners();
    // Locked landscape keeps the side it is on, so the mask changes with the lock.
    if (_presentation == Presentation.landscape) _apply(_requests);
  }

  void enterLandscape() {
    _awaitingLandscape = !(_lastDeviceOrientation?.isLandscape ?? false);
    _move(Presentation.landscape);
    final host = _host;
    if (host == null || !_awaitingLandscape || _pad) return;
    // The last event may be older than the phone's turn; ask, as Swift read UIDevice at once.
    final request = _requests;
    host.deviceOrientation().then((orientation) {
      if (request == _requests && orientation.isLandscape) _awaitingLandscape = false;
    }, onError: _hostFailed);
  }

  void enterVertical() => _move(_pad ? Presentation.landscape : Presentation.vertical);

  void exitToInline() => _move(Presentation.inline);

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  void _deviceOrientationChanged(PhoneOrientation orientation) {
    // Events still in flight after end belong to no page.
    if (!_observing) return;
    _lastDeviceOrientation = orientation;
    if (orientation.isLandscape) _awaitingLandscape = false;
    if (_locked || _videoIsVertical || _pad) return;
    switch (_presentation) {
      case Presentation.inline when orientation.isLandscape:
        _move(Presentation.landscape);
      case Presentation.landscape when orientation == PhoneOrientation.portrait && !_awaitingLandscape:
        exitToInline();
      default:
        break;
    }
  }

  /// Asks the host again even when the presentation is unchanged, so a refused rotation can be retried.
  void _move(Presentation next) {
    unawaited(_syncTakeover());
    final previous = _presentation;
    if (next != previous) {
      _logger.info(LogCategory.ui, 'presentation', {'from': previous.name, 'to': next.name});
      _present(next);
    }
    if (next == Presentation.inline) _awaitingLandscape = false;
    final request = ++_requests;
    _lastMove = (request: request, previous: previous, next: next);
    _apply(request);
  }

  void _refused(int request, String error) {
    _logger.warn(LogCategory.ui, 'orientation request refused', {'error': error});
    _revert(request, 'rotation refused');
  }

  /// A failed request leaves the screen as it was, so the presentation goes back to match it.
  void _revert(int request, String reason) {
    final move = _lastMove;
    if (move == null || request != _requests || move.request != request) return;
    // Going back inline is never undone: the page may be closing, and portrait is the safe state.
    if (_presentation != move.next || move.next == Presentation.inline || move.previous == move.next) return;
    _logger.info(
      LogCategory.ui,
      'presentation',
      {'from': move.next.name, 'to': move.previous.name, 'reason': reason},
    );
    _present(move.previous);
    if (move.previous == Presentation.inline) _awaitingLandscape = false;
    _apply(request);
  }

  void _present(Presentation next) {
    final wasFullScreen = _presentation.fullScreen;
    _presentation = next;
    if (next.fullScreen != wasFullScreen) {
      (next.fullScreen ? controls.enterFullScreen() : controls.leaveFullScreen()).catchError(_controlsFailed);
    }
    notifyListeners();
  }

  /// Requests go out in order, so the last one sent is always the latest presentation's.
  void _apply(int request) {
    final host = _host;
    if (host == null || _pad) return;
    final presentation = _presentation;
    final locked = _locked;
    _hostQueue = _hostQueue.then((_) async {
      try {
        await host.requestOrientations(request, await _mask(host, presentation, locked: locked));
      } catch (error) {
        _hostFailed(error);
        _revert(request, 'request failed');
      }
    });
  }

  static Future<OrientationMask> _mask(OrientationHost host, Presentation presentation, {required bool locked}) async {
    switch (presentation) {
      case Presentation.inline || Presentation.vertical:
        return OrientationMask.portrait;
      case Presentation.landscape:
        // Locked in landscape keeps the side it is on rather than flipping with the phone.
        if (!locked) return OrientationMask.landscape;
        return switch (await host.interfaceOrientation()) {
          ScreenOrientation.landscapeLeft => OrientationMask.landscapeLeft,
          ScreenOrientation.landscapeRight => OrientationMask.landscapeRight,
          _ => OrientationMask.landscape,
        };
    }
  }

  static bool get _pad => FormFactor.device.isPad;

  void _hostFailed(Object error) => _logger.warn(LogCategory.ui, 'orientation host failed', {'error': '$error'});

  void _controlsFailed(Object error) =>
      _logger.warn(LogCategory.ui, 'full screen device controls failed', {'error': '$error'});
}
