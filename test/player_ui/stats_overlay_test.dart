import 'package:bili_core/engine.dart';
import 'package:bilifast/playback/overlay_stats.dart';
import 'package:bilifast/player_ui/stats_overlay.dart';
import 'package:bilifast/shared/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/system_font.dart';

const _sample = OverlayStats(
  mode: PlaybackMode.btr,
  stream: '1080P 高清 · HEVC · 3.2 Mbps',
  transport: 'URLSession',
  firstFrameMs: 1234,
  lastSeekMs: 450,
  worstSeekMs: 800,
  stalls: 2,
  downloadBps: 3.5 * 1048576,
  engine: EngineSnapshot(
    deliveredBytes: 700,
    duplicateBytes: 100,
    cacheHits: 3,
    concurrency: 6,
    nodes: [
      NodeTiming(node: 'upos-sz-mirrorcos.bilivideo.com', firstByteMs: 120.7),
      NodeTiming(node: 'upos-sz-mirrorali.bilivideo.com', firstByteMs: 300),
      NodeTiming(node: 'upos-sz-mirrorhw.bilivideo.com', firstByteMs: 90),
      NodeTiming(node: 'upos-hz-mirrorakam.akamaized.net', firstByteMs: 1000),
    ],
    nodeStates: [
      NodeStatus(node: 'upos-sz-mirrorcos.bilivideo.com', state: 'untested', bps: 0),
      NodeStatus(node: 'upos-sz-mirrorcos.bilivideo.com', state: 'healthy', bps: 2 * 1048576),
      NodeStatus(node: 'upos-sz-mirrorali.bilivideo.com', state: 'blocked', bps: 0),
      NodeStatus(node: 'upos-sz-mirrorhw.bilivideo.com', state: 'banned', bps: 0.5 * 1048576),
    ],
  ),
);

Future<void> _show(WidgetTester tester, OverlayStats stats) => tester.pumpWidget(
  Directionality(
    textDirection: TextDirection.ltr,
    child: Align(alignment: Alignment.topLeft, child: StatsOverlay(stats: stats)),
  ),
);

Color _dot(WidgetTester tester, String node) {
  final box = tester.widget<Container>(find.byKey(ValueKey('stats-dot-$node')));
  return (box.decoration! as BoxDecoration).color!;
}

void main() {
  testWidgets('shows every line, then one per node with its state', (tester) async {
    await _show(tester, _sample);
    for (final line in [
      '模式 BTR · URLSession',
      '画质 1080P 高清 · HEVC · 3.2 Mbps',
      '首帧 1.23 秒',
      '跳转恢复 0.45 秒  最慢 0.80 秒',
      '卡顿 2 次',
      '下载 3.5 MB/s',
      '连接 6  重复 12.5%  缓存命中 3',
      'mirrorcos 120ms 2.0MB/s healthy',
      'mirrorali 300ms 0.0MB/s blocked',
      'mirrorhw 90ms 0.5MB/s banned',
      'upos-hz-mirrorakam.akamaized.net 1000ms 0.0MB/s',
    ]) {
      expect(find.text(line), findsOneWidget, reason: line);
    }
  });

  testWidgets('colours each node\'s dot by its state', (tester) async {
    await _show(tester, _sample);
    expect(_dot(tester, 'upos-sz-mirrorcos.bilivideo.com'), BiliColors.nodeHealthy);
    expect(_dot(tester, 'upos-sz-mirrorali.bilivideo.com'), BiliColors.nodeBlocked);
    expect(_dot(tester, 'upos-sz-mirrorhw.bilivideo.com'), BiliColors.nodeBanned);
    expect(_dot(tester, 'upos-hz-mirrorakam.akamaized.net'), BiliColors.nodeOther);
  });

  testWidgets('before anything is known, and without BTR, shows dashes and no connection lines', (tester) async {
    await _show(tester, const OverlayStats(mode: PlaybackMode.direct));
    for (final line in ['模式 直连', '画质 -', '首帧 -', '跳转恢复 -', '卡顿 0 次', '下载 0.0 MB/s']) {
      expect(find.text(line), findsOneWidget, reason: line);
    }
    expect(find.textContaining('连接'), findsNothing);
  });

  testWidgets('the worst seek falls back to the last one', (tester) async {
    await _show(tester, const OverlayStats(lastSeekMs: 1500));
    expect(find.text('跳转恢复 1.50 秒  最慢 1.50 秒'), findsOneWidget);
  });

  testWidgets('takes no touches', (tester) async {
    await _show(tester, _sample);
    final ignoring = find.byWidgetPredicate((widget) => widget is IgnorePointer && widget.ignoring);
    expect(find.ancestor(of: find.text('卡顿 2 次'), matching: ignoring), findsOneWidget);
  });

  testWidgets('past the monospace fonts it falls back to the app font, or to PingFang SC', (tester) async {
    final saved = BiliFonts.family;
    addTearDown(() => BiliFonts.family = saved);
    BiliFonts.family = BiliFonts.system;
    await _show(tester, _sample);
    expect(fallbackOf(tester, find.text('卡顿 2 次')), ['Consolas', 'Courier New', BiliFonts.system, ...systemFallback]);
    await tester.pumpWidget(const SizedBox.shrink());
    BiliFonts.family = BiliFonts.miSans;
    await _show(tester, _sample);
    expect(fallbackOf(tester, find.text('卡顿 2 次')), ['Consolas', 'Courier New', BiliFonts.miSans]);
  });
}
