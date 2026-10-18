import 'package:flutter/foundation.dart';

import 'device_controls.dart';

enum Presentation {
  inline,
  landscape,

  /// 竖屏: a vertical video full screen, the phone upright.
  vertical;

  bool get fullScreen => this != inline;
}

/// Full screen is the same page laid out again, never a new route (port of BiliNative `OrientationController.swift`).
/// The rules live here; the host only applies masks and reports the phone's orientation.
///
/// Pages stack: the latest [begin] wins, and a covered page's late [end] does nothing.
class OrientationController extends ChangeNotifier {
  OrientationController({DeviceControls? controls}) : controls = controls ?? NoDeviceControls();

  final DeviceControls controls;

  Presentation get presentation => _presentation;
  Presentation _presentation = Presentation.inline;

  /// The rotation lock: turning the phone does nothing until it is lifted; it lasts until the page ends.
  bool get locked => _locked;
  bool _locked = false;

  bool get videoIsVertical => _videoIsVertical;
  bool _videoIsVertical = false;

  Object? _owner;

  void begin(Object owner, {required bool videoIsVertical}) {
    _owner = owner;
    _videoIsVertical = videoIsVertical;
    notifyListeners();
  }

  void setVideoIsVertical(bool vertical, {required Object owner}) {
    if (!identical(_owner, owner)) return;
    _videoIsVertical = vertical;
    notifyListeners();
  }

  void end(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _locked = false;
    _videoIsVertical = false;
    _move(Presentation.inline);
  }

  void toggleLock() {
    _locked = !_locked;
    notifyListeners();
  }

  void enterLandscape() => _move(Presentation.landscape);

  void enterVertical() => _move(Presentation.vertical);

  void exitToInline() => _move(Presentation.inline);

  void _move(Presentation next) {
    _presentation = next;
    notifyListeners();
  }
}
