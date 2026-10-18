import 'dart:async';

import 'package:flutter/foundation.dart';

enum LevelKind { brightness, volume }

/// What shows in the middle of the player while a gesture runs (BiliNative `PlayerHUD.swift`).
sealed class Hud {
  const Hud();
}

/// 倍速中, while a long press plays at 2×.
final class SpeedUpHud extends Hud {
  const SpeedUpHud();
}

/// The time a sideways drag will seek to.
final class SeekHud extends Hud {
  const SeekHud({required this.target, required this.duration});

  final double target;
  final double duration;

  @override
  bool operator ==(Object other) => other is SeekHud && other.target == target && other.duration == duration;

  @override
  int get hashCode => Object.hash(target, duration);
}

final class LevelHud extends Hud {
  const LevelHud(this.kind, this.value);

  final LevelKind kind;

  /// 0 to 1.
  final double value;

  @override
  bool operator ==(Object other) => other is LevelHud && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);
}

/// Whether the player's controls show, and the gesture HUD (port of BiliNative `ChromeState.swift`). Shown controls
/// hide after [hideDelay] while [autoHide] is on; the page turns it off while paused, scrubbing or a panel is open.
class ChromeState extends ChangeNotifier {
  ChromeState({this.hideDelay = const Duration(seconds: 3)});

  final Duration hideDelay;

  bool get visible => _visible;
  bool _visible = true;

  bool get autoHide => _autoHide;
  bool _autoHide = false;
  set autoHide(bool on) {
    if (on == _autoHide) return;
    _autoHide = on;
    _schedule();
  }

  final ValueNotifier<Hud?> _hud = ValueNotifier(null);
  ValueListenable<Hud?> get hud => _hud;

  Timer? _timer;

  /// Shows the controls and starts the hide timer again.
  void show() {
    _set(true);
    _schedule();
  }

  void hide() {
    _timer?.cancel();
    _set(false);
  }

  void toggle() => _visible ? hide() : show();

  void showHud(Hud? hud) => _hud.value = hud;

  void _set(bool visible) {
    if (visible == _visible) return;
    _visible = visible;
    notifyListeners();
  }

  void _schedule() {
    _timer?.cancel();
    if (!_autoHide || !_visible) return;
    _timer = Timer(hideDelay, hide);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _hud.dispose();
    super.dispose();
  }
}
