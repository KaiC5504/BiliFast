import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:flutter/foundation.dart';

import '../device/orientation.dart';
import '../device/turn_style.dart';
import '../shared/theme.dart';
import '../video/player_prefs.dart';

/// 开发者 → 轮换测试: walks [TurnStyle.cycle] while the phone is turned on a screen recording, moving on after every
/// [roundTripsPerStyle] round trips, so one recording covers every style. Off at every launch; one per app. Switching
/// it off, or reaching the end, puts back the style chosen before it started.
///
/// A round trip is landscape full screen, then upright again (inline or 竖屏), each held for [settle]. The presentation
/// changes before its turn is even requested, so counting the return at the change would draw that return with the
/// next style; after [settle] upright, the return's turn is over and the next hasn't begun. Anything held for less (a
/// refused rotation, a quick flip back) isn't counted. 竖屏 is upright too: landscape → 竖屏 → landscape is one round
/// trip and the start of the next, never two.
class TurnCycle extends ChangeNotifier {
  TurnCycle({required this._orientation, PlayerPrefs? prefs, Logger? logger})
      : _ownPrefs = prefs,
        _logger = logger ?? Logger.shared;

  static const styles = TurnStyle.cycle;
  static const roundTripsPerStyle = 2;

  /// Longer than any turn, including a drawn one held up to [RotationTheme.pictureWait] for its still picture.
  static const settle = Duration(milliseconds: 1500);

  final OrientationController _orientation;
  final PlayerPrefs? _ownPrefs;
  final Logger _logger;

  PlayerPrefs get _prefs => _ownPrefs ?? PlayerPrefs.shared;

  bool get on => _on;
  bool _on = false;

  /// 1-based, in [styles].
  int get position => _index + 1;
  int _index = 0;

  TurnStyle get style => styles[_index];

  /// Counted under [style] so far.
  int get roundTrips => _roundTrips;
  int _roundTrips = 0;

  Presentation _seen = Presentation.inline;
  Timer? _settling;

  /// Landscape has settled since the last counted return.
  bool _out = false;

  /// What 方式, 截图 and 起转 were set to when it switched on. Not saved: the saved style is the cycle's while it runs, so
  /// a phone killed mid-cycle keeps that one.
  TurnStyle _chosen = const TurnStyle();

  /// Switches on at the first style, or goes back to it (重置).
  void start() {
    _settling?.cancel();
    _settling = null;
    _seen = _orientation.presentation;
    _out = false;
    if (!_on) {
      _on = true;
      _chosen = _prefs.turnStyle;
      _orientation.addListener(_presentationChanged);
    }
    _go(0);
  }

  /// Puts back the style chosen before it started.
  void stop() {
    if (!_on) return;
    _halt();
    _apply(_chosen);
    _logger.info(
      LogCategory.ui,
      'turn cycle off',
      {'index': position, 'of': styles.length, 'label': _chosen.label, 'wUs': _wallUs()},
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _halt();
    super.dispose();
  }

  void _halt() {
    _on = false;
    _settling?.cancel();
    _settling = null;
    _orientation.removeListener(_presentationChanged);
  }

  void _presentationChanged() {
    final now = _orientation.presentation;
    if (now == _seen) return;
    _seen = now;
    _settling?.cancel();
    _settling = Timer(settle, _settled);
  }

  void _settled() {
    _settling = null;
    if (_seen == Presentation.landscape) {
      _out = true;
      return;
    }
    if (!_out) return;
    _out = false;
    _roundTrips += 1;
    if (_roundTrips < roundTripsPerStyle) {
      notifyListeners();
    } else if (position < styles.length) {
      _go(_index + 1);
    } else {
      _finish();
    }
  }

  void _go(int index) {
    _index = index;
    _roundTrips = 0;
    _apply(style);
    _logger.info(
      LogCategory.ui,
      'turn cycle',
      {'index': position, 'of': styles.length, 'label': style.label, 'wUs': _wallUs()},
    );
    notifyListeners();
  }

  void _finish() {
    _halt();
    _apply(_chosen);
    _logger.info(LogCategory.ui, 'turn cycle done', {'of': styles.length, 'label': _chosen.label, 'wUs': _wallUs()});
    notifyListeners();
  }

  /// The controller logs a host that fails.
  void _apply(TurnStyle style) {
    _prefs.turnStyle = style;
    unawaited(_orientation.setTurnStyle(style));
  }

  static int _wallUs() => DateTime.now().microsecondsSinceEpoch;
}
