import 'package:bili_core/engine.dart';
import 'package:flutter/widgets.dart';

import '../playback/overlay_stats.dart';
import '../shared/theme.dart';

/// The 显示统计 overlay (port of StatsOverlay.swift): how the playback is doing, and with BTR each node.
class StatsOverlay extends StatelessWidget {
  const StatsOverlay({super.key, required this.stats});

  final OverlayStats stats;

  static TextStyle get _style => TextStyle(
    color: BiliColors.onVideo,
    fontSize: BiliMetrics.statsFont,
    fontFamily: 'Menlo',
    fontFamilyFallback: ['Consolas', 'Courier New', ?BiliFonts.family, ...?BiliFonts.fallback],
    fontFeatures: [FontFeature.tabularFigures()],
  );

  @override
  Widget build(BuildContext context) {
    final engine = stats.engine;
    final mode = stats.mode?.label ?? '-';
    final transport = stats.transport;
    final lastSeek = stats.lastSeekMs;
    final firstFrame = stats.firstFrameMs;
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.all(BiliMetrics.statsPadding),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: BiliColors.statsFill,
            borderRadius: BorderRadius.circular(BiliMetrics.statsRadius),
            border: Border.all(color: BiliColors.statsBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(BiliMetrics.statsPadding),
            child: DefaultTextStyle(
              style: _style,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: BiliMetrics.statsLineGap,
                children: [
                  Text(transport == null || transport.isEmpty ? '模式 $mode' : '模式 $mode · $transport'),
                  Text('画质 ${stats.stream ?? '-'}'),
                  Text('首帧 ${firstFrame == null ? '-' : '${_seconds(firstFrame)} 秒'}'),
                  Text(
                    lastSeek == null
                        ? '跳转恢复 -'
                        : '跳转恢复 ${_seconds(lastSeek)} 秒  最慢 ${_seconds(stats.worstSeekMs ?? lastSeek)} 秒',
                  ),
                  Text('卡顿 ${stats.stalls} 次'),
                  Text('下载 ${_megabytes(stats.downloadBps)} MB/s'),
                  if (engine != null) ...[
                    Text(
                      '连接 ${engine.concurrency}  重复 ${(engine.duplicateShare * 100).toStringAsFixed(1)}%'
                      '  缓存命中 ${engine.cacheHits}',
                    ),
                    for (final node in engine.nodes)
                      _NodeLine(node: node, state: NodeStatus.best(node.node, engine.nodeStates)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _seconds(double ms) => (ms / 1000).toStringAsFixed(2);
}

String _megabytes(double bytesPerSecond) => (bytesPerSecond / 1048576).toStringAsFixed(1);

class _NodeLine extends StatelessWidget {
  const _NodeLine({required this.node, required this.state});

  final NodeTiming node;
  final NodeStatus? state;

  static Color colorOf(String? state) => switch (state) {
    'healthy' => BiliColors.nodeHealthy,
    'blocked' => BiliColors.nodeBlocked,
    'banned' => BiliColors.nodeBanned,
    _ => BiliColors.nodeOther,
  };

  @override
  Widget build(BuildContext context) {
    final name = node.node.replaceAll('.bilivideo.com', '').replaceAll('upos-sz-', '');
    final firstByte = node.firstByteMs.isFinite ? node.firstByteMs.toInt() : 0;
    final line = '$name ${firstByte}ms ${_megabytes(state?.bps ?? 0)}MB/s ${state?.state ?? ''}'.trimRight();
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: BiliMetrics.statsDotGap,
      children: [
        Container(
          key: ValueKey('stats-dot-${node.node}'),
          width: BiliMetrics.statsDot,
          height: BiliMetrics.statsDot,
          decoration: BoxDecoration(color: colorOf(state?.state), shape: BoxShape.circle),
        ),
        Text(line),
      ],
    );
  }
}
