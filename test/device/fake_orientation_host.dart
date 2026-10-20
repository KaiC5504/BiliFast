import 'dart:async';

import 'package:bilifast/device/device_controls.dart';
import 'package:bilifast/device/orientation_host.dart';
import 'package:bilifast/device/turn_style.dart';

/// DeviceChannel.swift's stand-in: records requests, and the test turns the phone and refuses rotations.
final class FakeOrientationHost implements OrientationHost {
  PhoneOrientation phone = PhoneOrientation.portrait;
  ScreenOrientation screen = ScreenOrientation.landscapeRight;
  final events = <bool>[];
  final requests = <(int, OrientationMask)>[];

  /// Requests that throw rather than reach the screen, as a channel that fails.
  final failing = <int>{};

  /// Thrown by [interfaceOrientation] while set.
  Object? interfaceError;

  final _orientations = StreamController<PhoneOrientation>.broadcast(sync: true);
  final _refusals = StreamController<OrientationRefusal>.broadcast(sync: true);
  final _turns = StreamController<TurnStart>.broadcast(sync: true);
  final _picturesGone = StreamController<int>.broadcast(sync: true);

  /// Every [setTurnTakeover] call, and how many times Flutter said a taken-over turn was drawn.
  final takeovers = <bool>[];
  int drawn = 0;

  /// The turns Flutter said were drawn, in order, and the method and picture of every [setTurnTakeover].
  final drawnTurns = <int>[];
  final styles = <(TurnMethod, TurnPicture)>[];
  int _turnIds = 0;

  /// Takeover changes and requests in the order they reached the host.
  final sent = <String>[];

  /// Thrown by [setTurnTakeover] while set.
  Object? takeoverError;

  /// Thrown by [turnDrawn] while set.
  Object? drawnError;

  /// The system starting a taken-over turn of [angle] radians; returns its id.
  int startTurn(double angle, {Duration duration = const Duration(milliseconds: 280)}) {
    final id = ++_turnIds;
    _turns.add((id: id, angle: angle, duration: duration));
    return id;
  }

  /// [turn]'s still picture went.
  void pictureGone(int turn) => _picturesGone.add(turn);

  void turn(PhoneOrientation orientation) {
    phone = orientation;
    _orientations.add(orientation);
  }

  void refuse(int request) => _refusals.add((request: request, error: 'UISceneErrorDomain 101'));

  int get lastRequest => requests.last.$1;

  OrientationMask get lastMask => requests.last.$2;

  @override
  Future<void> setOrientationEvents(bool enabled) async => events.add(enabled);

  @override
  Stream<PhoneOrientation> get deviceOrientations => _orientations.stream;

  @override
  Future<PhoneOrientation> deviceOrientation() async => phone;

  @override
  Future<ScreenOrientation> interfaceOrientation() async {
    if (interfaceError case final error?) throw error;
    return screen;
  }

  @override
  Future<void> requestOrientations(int request, OrientationMask mask) async {
    if (failing.contains(request)) throw StateError('channel closed');
    requests.add((request, mask));
    sent.add(mask.name);
  }

  @override
  Stream<OrientationRefusal> get refusals => _refusals.stream;

  @override
  Future<void> setTurnTakeover(bool enabled, {required TurnMethod method, required TurnPicture picture}) async {
    if (takeoverError case final error?) throw error;
    takeovers.add(enabled);
    styles.add((method, picture));
    sent.add(enabled ? 'takeover on' : 'takeover off');
  }

  @override
  Stream<TurnStart> get turns => _turns.stream;

  @override
  Future<void> turnDrawn(int turn) async {
    if (drawnError case final error?) throw error;
    drawn += 1;
    drawnTurns.add(turn);
  }

  @override
  Stream<int> get picturesGone => _picturesGone.stream;
}

/// Records full screen entered and left; levels as [NoDeviceControls].
final class RecordingDeviceControls implements DeviceControls {
  final _levels = NoDeviceControls();
  final calls = <String>[];

  @override
  Future<double> brightness() => _levels.brightness();

  @override
  Future<void> setBrightness(double value) => _levels.setBrightness(value);

  @override
  Future<double> volume() => _levels.volume();

  @override
  Future<void> setVolume(double value) => _levels.setVolume(value);

  @override
  Stream<double> get hardwareVolume => const Stream.empty();

  @override
  Future<void> enterFullScreen() async => calls.add('enter');

  @override
  Future<void> leaveFullScreen() async => calls.add('leave');
}

/// Lets queued host calls and their replies run.
Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
