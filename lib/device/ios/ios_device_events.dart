import 'dart:async';

import 'package:flutter/services.dart';

import '../orientation_host.dart';
import 'device_api.g.dart';

/// What DeviceChannel.swift reports, as streams.
final class IosDeviceEvents implements DeviceEventApi {
  IosDeviceEvents();

  static IosDeviceEvents? _shared;

  /// The hub the native side calls, registered on first use.
  static IosDeviceEvents get shared => _shared ??= IosDeviceEvents()..connect();

  final _orientations = StreamController<NativeDeviceOrientation>.broadcast();
  final _refusals = StreamController<OrientationRefusal>.broadcast();
  final _volumes = StreamController<double>.broadcast();
  final _turns = StreamController<TurnStart>.broadcast();

  void connect({BinaryMessenger? binaryMessenger}) => DeviceEventApi.setUp(this, binaryMessenger: binaryMessenger);

  Stream<NativeDeviceOrientation> get deviceOrientations => _orientations.stream;

  Stream<OrientationRefusal> get refusals => _refusals.stream;

  Stream<double> get hardwareVolume => _volumes.stream;

  Stream<TurnStart> get turns => _turns.stream;

  @override
  void onDeviceOrientation(NativeDeviceOrientation orientation) => _orientations.add(orientation);

  @override
  void onOrientationRefused(int request, String error) => _refusals.add((request: request, error: error));

  @override
  void onHardwareVolume(double volume) => _volumes.add(volume);

  @override
  void onTurn(double angle, double seconds) =>
      _turns.add((angle: angle, duration: Duration(microseconds: (seconds * Duration.microsecondsPerSecond).round())));
}
