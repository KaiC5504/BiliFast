/// The phone's physical orientation, as UIDevice reports it.
enum PhoneOrientation {
  portrait,
  portraitUpsideDown,
  landscapeLeft,
  landscapeRight,
  faceUp,
  faceDown,
  unknown;

  bool get isLandscape => this == landscapeLeft || this == landscapeRight;
}

/// The side the interface is laid out for, as the scene reports it.
enum ScreenOrientation { portrait, landscapeLeft, landscapeRight, unknown }

/// The orientations the app allows.
enum OrientationMask { portrait, landscape, landscapeLeft, landscapeRight }

typedef OrientationRefusal = ({int request, String error});

/// A turn Flutter draws itself: the rotation in radians the system would have animated, and its length.
typedef TurnStart = ({double angle, Duration duration});

/// The native side of [OrientationController]: it applies masks and reports, and decides nothing.
abstract interface class OrientationHost {
  /// Starts or stops [deviceOrientations].
  Future<void> setOrientationEvents(bool enabled);

  Stream<PhoneOrientation> get deviceOrientations;

  Future<PhoneOrientation> deviceOrientation();

  Future<ScreenOrientation> interfaceOrientation();

  /// Makes [mask] the app's supported orientations and asks the scene to rotate to it. iOS answers only when it
  /// refuses, on [refusals] with this [request].
  Future<void> requestOrientations(int request, OrientationMask mask);

  Stream<OrientationRefusal> get refusals;

  /// While on, turns are not animated by the system: the screen takes its turned size at once and each turn is
  /// reported on [turns] for Flutter to draw, with a still picture covering the screen until [turnDrawn].
  Future<void> setTurnTakeover(bool enabled);

  Stream<TurnStart> get turns;

  Future<void> turnDrawn();
}
