import 'package:bili_core/engine.dart';

/// What the 显示统计 overlay shows (port of OverlayStats.swift). The playback controller fills it in.
final class OverlayStats {
  const OverlayStats({
    this.mode,
    this.stream,
    this.transport,
    this.firstFrameMs,
    this.lastSeekMs,
    this.worstSeekMs,
    this.stalls = 0,
    this.downloadBps = 0,
    this.engine,
  });

  final PlaybackMode? mode;

  /// The stream handed to the player, e.g. `1080P 高清 · HEVC · 3.2 Mbps` (`PlayingStream.line`).
  final String? stream;

  /// `URLSession` or `dart:io`.
  final String? transport;
  final double? firstFrameMs;
  final double? lastSeekMs;
  final double? worstSeekMs;
  final int stalls;
  final double downloadBps;

  /// BTR only.
  final EngineSnapshot? engine;

  OverlayStats copyWith({
    PlaybackMode? mode,
    String? stream,
    String? transport,
    double? firstFrameMs,
    double? lastSeekMs,
    double? worstSeekMs,
    int? stalls,
    double? downloadBps,
    EngineSnapshot? engine,
  }) =>
      OverlayStats(
        mode: mode ?? this.mode,
        stream: stream ?? this.stream,
        transport: transport ?? this.transport,
        firstFrameMs: firstFrameMs ?? this.firstFrameMs,
        lastSeekMs: lastSeekMs ?? this.lastSeekMs,
        worstSeekMs: worstSeekMs ?? this.worstSeekMs,
        stalls: stalls ?? this.stalls,
        downloadBps: downloadBps ?? this.downloadBps,
        engine: engine ?? this.engine,
      );
}
