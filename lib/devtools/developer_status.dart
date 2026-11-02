import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../offline/disk/background_trials.dart';
import '../playback/shared_engine.dart';
import '../settings/settings_page.dart';
import '../shared/theme.dart';

/// 开发者's 状态: what the app runs on and has found this run, read when the page is built.
class DeveloperStatus extends StatelessWidget {
  const DeveloperStatus({super.key, required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final nodes = services.playback.engine?.seenNodes ?? const {};
    final trials = services.offline.trials;
    final waiting = services.historyOutbox.reports.length;
    return SettingsSection(
      children: [
        SettingsRow(key: const ValueKey('status-version'), title: '版本', value: version),
        _Item(
          key: const ValueKey('status-nodes'),
          title: '节点',
          value: _nodesSummary(nodes),
          lines: [for (final entry in _bySpeed(nodes)) _NodeLine(node: entry.key, seen: entry.value)],
        ),
        _Item(
          key: const ValueKey('status-background'),
          title: '后台下载',
          value: trials == null ? '无' : '${_verdict(trials)} · 共 ${trials.trips.length} 次',
          lines: [
            if (trials != null)
              for (final arm in BackgroundTrials.arms) _ArmLine(arm: arm, trials: trials),
          ],
        ),
        SettingsRow(key: const ValueKey('status-outbox'), title: '待发送进度', value: waiting == 0 ? '无' : '$waiting 条'),
        SettingsRow(key: const ValueKey('status-font'), title: '系统字体', value: _systemFont()),
      ],
    );
  }

  static String _nodesSummary(Map<String, SeenNode> nodes) {
    if (nodes.isEmpty) return '暂无';
    final banned = nodes.values.where((node) => node.state == 'banned').length;
    return banned == 0 ? '${nodes.length} 个' : '${nodes.length} 个 · 封禁 $banned';
  }

  static List<MapEntry<String, SeenNode>> _bySpeed(Map<String, SeenNode> nodes) =>
      nodes.entries.toList()..sort((a, b) => b.value.bps.compareTo(a.value.bps));

  static String _verdict(BackgroundTrials trials) => switch (trials.best) {
    final best? => armLabel(best),
    null => '还在试',
  };

  /// What launch's `BiliFonts.settleSystemFallback` named after the system font; it runs only on iOS.
  static String _systemFont() {
    if (defaultTargetPlatform != TargetPlatform.iOS) return '仅 iOS';
    final fallback = BiliFonts.systemFallback;
    if (fallback == null) return '未指定';
    return fallback.map((family) => family == BiliFonts.appleSystem ? 'SF' : family).join(' + ');
  }
}

/// A way of downloading away, as 状态 names it.
String armLabel(BackgroundArm arm) => arm.continued ? '持续处理' : '后台会话 ${arm.connections}×${arm.maxPieceBytes >> 20}M';

String _megabytes(double bytesPerSecond) => (bytesPerSecond / (1 << 20)).toStringAsFixed(1);

/// A row with lines under it, level with its title.
class _Item extends StatelessWidget {
  const _Item({super.key, required this.title, required this.value, required this.lines});

  final String title;
  final String value;
  final List<Widget> lines;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SettingsRow(title: title, value: value),
      if (lines.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SettingsTheme.rowInset,
            0,
            SettingsTheme.chevronRight,
            DevToolsTheme.subBottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DevToolsTheme.subLineGap,
            children: lines,
          ),
        ),
    ],
  );
}

/// Tabular figures only for the numbers: they widen a host's hyphens too (cn-hk-eq-01-13).
TextStyle _subStyle({Color color = DevToolsTheme.sub, bool figures = false}) => TextStyle(
  fontFamily: BiliFonts.family,
  fontSize: DevToolsTheme.subText,
  color: color,
  fontFeatures: figures ? const [FontFeature.tabularFigures()] : null,
);

/// A host, its state's dot (the stats overlay's colours), its last speed and first byte, and 封禁 or 暂避 when so.
class _NodeLine extends StatelessWidget {
  const _NodeLine({required this.node, required this.seen});

  final String node;
  final SeenNode seen;

  static Color _color(String? state) => switch (state) {
    'healthy' => BiliColors.nodeHealthy,
    'blocked' => BiliColors.nodeBlocked,
    'banned' => BiliColors.nodeBanned,
    _ => BiliColors.nodeOther,
  };

  @override
  Widget build(BuildContext context) {
    final name = node.replaceAll('.bilivideo.com', '').replaceAll('upos-sz-', '');
    final measured = seen.bps > 0 || seen.firstByteMs > 0;
    final figures = measured ? '${_megabytes(seen.bps)} MB/s · ${seen.firstByteMs.round()} ms' : '未测';
    final mark = switch (seen.state) {
      'banned' => '封禁',
      'blocked' => '暂避',
      _ => null,
    };
    return Row(
      key: ValueKey('status-node-$node'),
      children: [
        Container(
          width: DevToolsTheme.dot,
          height: DevToolsTheme.dot,
          decoration: BoxDecoration(color: _color(seen.state), shape: BoxShape.circle),
        ),
        const SizedBox(width: DevToolsTheme.dotGap),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _subStyle(color: DevToolsTheme.subValue),
          ),
        ),
        const SizedBox(width: DevToolsTheme.subColumnGap),
        Text(figures, style: _subStyle(figures: true)),
        if (mark != null) ...[
          const SizedBox(width: DevToolsTheme.subColumnGap),
          Text(mark, style: _subStyle(color: _color(seen.state))),
        ],
      ],
    );
  }
}

/// One way of downloading away: its trips that counted, and their recent mean.
class _ArmLine extends StatelessWidget {
  const _ArmLine({required this.arm, required this.trials});

  final BackgroundArm arm;
  final BackgroundTrials trials;

  @override
  Widget build(BuildContext context) {
    final (:scored, :mbps) = trials.stats(arm);
    return Row(
      key: ValueKey('status-arm-${arm.name}'),
      children: [
        Expanded(
          child: Text(armLabel(arm), style: _subStyle(color: DevToolsTheme.subValue)),
        ),
        Text(scored == 0 ? '暂无结果' : '$scored 次 · ${mbps!.toStringAsFixed(1)} MB/s', style: _subStyle(figures: true)),
      ],
    );
  }
}
