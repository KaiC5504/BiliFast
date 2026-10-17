import 'dart:math';

double smoothed(double old, double sample) => old > 0 ? old * 0.7 + sample * 0.3 : sample;

/// What one connection typically delivers and how long a piece typically takes (BTR `meter`).
final class Meter {
  /// Shorter transfers are mostly round trip and say nothing about speed.
  static const sampleMinBytes = 48 * 1024;

  double connectionBps = 0;
  double pieceMs = 0;

  void record({required int bytes, required double elapsedMs}) {
    if (bytes < sampleMinBytes || elapsedMs <= 0) return;
    connectionBps = smoothed(connectionBps, bytes * 1000 / elapsedMs);
    pieceMs = smoothed(pieceMs, elapsedMs);
  }

  /// A piece should keep its connection busy for a good part of a second; 64 KiB until the speed
  /// is known, never above 1 MiB, and small enough that a range still spreads over the nodes.
  int adaptiveMinChunk({required int base, required int rangeLength, required int pieceLimit, required int hostCount}) {
    if (connectionBps <= 0) return base;
    final target = (connectionBps * 0.6 / 65536).floor() * 65536;
    final ways = max(1, min(max(4, hostCount), pieceLimit));
    final spread = (rangeLength + ways - 1) ~/ ways;
    return max(base, min(1 << 20, min(target, spread)));
  }

  double hedgeDelayMs(double configured) =>
      pieceMs > 0 ? max(250, min(configured, (pieceMs * 1.5).roundToDouble())) : configured;
}
