import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'bili_player.dart';
import 'ios/ios_player_events.dart';
import 'ios/player_api.g.dart';

/// AVPlayer in a native view (`bilifast/player`), driven over Pigeon (pigeons/player_api.dart). The native player
/// lives in ios/Runner/PlayerRegistry.swift until [dispose], whatever happens to the views built here.
final class IosPlayer implements BiliPlayer {
  IosPlayer._(this._host, this._hub, this.nativeId, this.capabilities) {
    _hub.attach(nativeId, _receive);
  }

  static const viewType = 'bilifast/player';

  static Future<IosPlayer> create() => connect(PlayerHostApi(), IosPlayerEvents.shared);

  /// [create] over a given native side; tests pass fakes.
  static Future<IosPlayer> connect(PlayerHostApi host, IosPlayerEvents events) async {
    final id = await host.create();
    final pictureInPicture = await host.pictureInPictureSupported();
    return IosPlayer._(host, events, id, PlayerCapabilities(pictureInPicture: pictureInPicture, frameCapture: true));
  }

  final PlayerHostApi _host;
  final IosPlayerEvents _hub;

  /// The PlayerRegistry's id for this player.
  final int nativeId;

  final _events = StreamController<PlayerEvent>.broadcast();
  PlayerStatus? _status;
  int _loadsInFlight = 0;
  bool _muted = false;
  bool _disposed = false;

  @override
  final PlayerCapabilities capabilities;

  @override
  Stream<PlayerEvent> get events => _events.stream;

  /// Transparent to hit tests and without gesture recognizers, so every touch goes to the Flutter widgets above
  /// at once.
  @override
  Widget buildView() => UiKitView(
        viewType: viewType,
        creationParams: <String, Object?>{'id': nativeId},
        creationParamsCodec: const StandardMessageCodec(),
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      );

  /// Announces `loading` on every call, before any event of the new item. Until the native side has the new item,
  /// whatever it still reports belongs to the old one and is dropped.
  @override
  Future<void> load(PlayerSource source) async {
    _check();
    _status = PlayerStatus.loading;
    _events.add(const StatusChanged(PlayerStatus.loading));
    _loadsInFlight++;
    try {
      await _host.load(nativeId, source.master.toString(), source.headers, source.startSeconds, source.autoplay);
    } finally {
      _loadsInFlight--;
    }
  }

  @override
  Future<void> unload() async {
    _check();
    await _host.unload(nativeId);
  }

  @override
  Future<void> play() async {
    _check();
    await _host.play(nativeId);
  }

  @override
  Future<void> pause() async {
    _check();
    await _host.pause(nativeId);
  }

  @override
  Future<void> seek(double seconds, {bool precise = false}) async {
    _check();
    await _host.seek(nativeId, seconds, precise);
  }

  @override
  Future<void> setRate(double rate) async {
    _check();
    await _host.setRate(nativeId, rate);
  }

  @override
  Future<void> setMuted(bool muted) async {
    _check();
    _muted = muted;
    await _host.setMuted(nativeId, muted);
  }

  @override
  bool get muted => _muted;

  @override
  Future<void> setKeepAwake(bool on) async {
    _check();
    await _host.setKeepAwake(on);
  }

  @override
  Future<void> setFit(FitMode fit) async {
    _check();
    await _host.setFit(nativeId, switch (fit) {
      FitMode.fit => NativeFit.fit,
      FitMode.fill => NativeFit.fill,
      FitMode.stretch => NativeFit.stretch,
      FitMode.ratio16x9 => NativeFit.ratio16x9,
      FitMode.ratio4x3 => NativeFit.ratio4x3,
    });
  }

  @override
  Future<void> setMirrored(bool mirrored) async {
    _check();
    await _host.setMirrored(nativeId, mirrored);
  }

  @override
  Future<void> startPictureInPicture() async {
    _check();
    if (capabilities.pictureInPicture) await _host.startPiP(nativeId);
  }

  @override
  Future<void> stopPictureInPicture() async {
    _check();
    if (capabilities.pictureInPicture) await _host.stopPiP(nativeId);
  }

  @override
  Future<void> setAutoPictureInPicture(bool enabled) async {
    _check();
    if (capabilities.pictureInPicture) await _host.setAutoPiP(nativeId, enabled);
  }

  @override
  Future<bool> captureFrame() async {
    _check();
    if (!capabilities.frameCapture) return false;
    return _host.captureFrame(nativeId);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _hub.detach(nativeId);
    try {
      await _host.dispose(nativeId);
    } finally {
      await _events.close();
    }
  }

  /// The native side reports a status only when it changes, but [load] already announced `loading` itself.
  void _receive(PlayerEvent event) {
    if (_disposed) return;
    if (_loadsInFlight > 0 && _belongsToItem(event)) return;
    if (event is StatusChanged) {
      if (event.status == _status) return;
      _status = event.status;
    }
    _events.add(event);
  }

  static bool _belongsToItem(PlayerEvent event) => switch (event) {
        PositionChanged() || DurationChanged() || BufferedChanged() || StatusChanged() || SizeChanged() ||
        PlayerFailed() =>
          true,
        _ => false,
      };

  void _check() {
    if (_disposed) throw StateError('player disposed');
  }
}
