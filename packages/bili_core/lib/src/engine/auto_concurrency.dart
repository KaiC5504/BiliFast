// Port of Bilibili-thread-ripper (see LICENSE-BTR.txt), by way of BiliNative's AutoConcurrency.swift.

import '../shared/clock.dart';

final class AutoConcurrencyStatus {
  const AutoConcurrencyStatus({
    required this.threads,
    required this.reason,
    required this.throughputBps,
    required this.saturation,
    required this.inStartup,
  });

  final int threads;
  final String reason;
  final double throughputBps;
  final double saturation;
  final bool inStartup;
}

typedef ConcurrencyChange = void Function(int threads, int previous, String reason);

/// BTR `createAutoConcurrency`: the connection count climbs a ladder whenever downloading is not keeping up,
/// every step up is a trial, and 412/429 step down. App-wide: one per engine, shared by its sessions.
// Wave-0 placeholder: the public surface only; the behaviour is ported with AutoConcurrencyTests.
final class AutoConcurrency {
  AutoConcurrency({MonotonicClock? clock}) : _clock = clock ?? MonotonicClock.system;

  static const ladder = [8, 12, 16, 24, 32, 48, 64];

  // ignore: unused_field
  final MonotonicClock _clock;

  /// Called once per step, after the state changed. Read [threads] for the current value.
  ConcurrencyChange? onChange;

  int get threads => ladder[2];

  AutoConcurrencyStatus status() =>
      AutoConcurrencyStatus(threads: threads, reason: '起步', throughputBps: 0, saturation: 0, inStartup: false);

  /// A piece arrived whole. Hedge copies that lost are not delivery.
  void delivered(int bytes) {}

  void activity() {}

  void demand({required int active, required int limit, required int queued}) {}

  bool stall([String reason = '播放卡了一下']) => false;

  /// The buffer ahead of the playhead, a few times a second while playing.
  bool buffer({required double ahead, required bool playing}) => false;

  /// A connection waited too long for its first byte while every slot was busy.
  bool slow() => false;

  bool pushback({required int status}) => false;

  void newSession() {}
}
