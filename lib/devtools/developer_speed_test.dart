import 'package:bili_core/logic.dart';
import 'package:flutter/material.dart';

import '../playback/playback_controller.dart';
import '../settings/settings_page.dart';
import '../shared/theme.dart';
import '../speedtest/speed_test_plan.dart';
import '../speedtest/speed_test_results.dart';
import '../speedtest/speed_test_runner.dart';
import 'developer_rows.dart';

/// The player the speed test drives, as the page draws it.
typedef StageBuilder = Widget Function(BuildContext context, PlaybackController controller);

/// 网络's 速度测试: the links to test, 开始 / 停止, the player only while a run plays, and the run's numbers.
class DeveloperSpeedTest extends StatelessWidget {
  const DeveloperSpeedTest({
    super.key,
    required this.runner,
    required this.controller,
    required this.links,
    required this.starting,
    required this.playerError,
    required this.stageBuilder,
    required this.onStart,
  });

  /// Null until the first run asks for a player.
  final SpeedTestRunner? runner;
  final PlaybackController? controller;
  final TextEditingController links;

  /// The player is starting for the first run.
  final bool starting;
  final String? playerError;
  final StageBuilder stageBuilder;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([?runner]),
    builder: (context, _) {
      final runner = this.runner;
      final controller = this.controller;
      final running = starting || (runner?.running ?? false);
      final lines = _lines(runner);
      return SettingsSection(
        children: [
          _LinksField(links: links, enabled: !running),
          if (runner != null && runner.running)
            DeveloperActionRow(
              key: const ValueKey('speedtest-stop'),
              title: runner.cancelled ? '正在停止…' : '停止速度测试',
              onTap: runner.cancelled ? null : runner.stop,
            )
          else
            DeveloperActionRow(
              key: const ValueKey('speedtest-start'),
              title: starting ? '播放器启动中…' : '开始速度测试',
              onTap: starting ? null : onStart,
            ),
          if (controller != null && runner != null && runner.running)
            AspectRatio(
              key: const ValueKey('speedtest-stage'),
              aspectRatio: 16 / 9,
              child: ColoredBox(color: BiliColors.videoBackground, child: _Stage(controller, stageBuilder)),
            ),
          if (lines.isNotEmpty || (runner != null && GroupSummary.of(runner.results).isNotEmpty))
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SettingsTheme.rowInset,
                DevToolsTheme.blockVertical,
                SettingsTheme.rowInset,
                DevToolsTheme.blockVertical,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: DevToolsTheme.noteLineGap,
                children: [...lines, if (runner != null) ..._results(runner)],
              ),
            ),
        ],
      );
    },
  );

  List<Widget> _lines(SpeedTestRunner? runner) {
    final error = runner?.error ?? playerError;
    final status = runner == null ? '' : _status(runner);
    return [
      if (status.isNotEmpty) _note(status, key: const ValueKey('speedtest-status')),
      if (error != null)
        _note(
          runner?.error == null ? '播放器启动失败：$error' : error,
          key: const ValueKey('speedtest-error'),
          color: BiliColors.failure,
        ),
      if (runner != null) ...[
        for (final note in runner.notes) _note(note),
        for (final failed in runner.results.where((pass) => pass.failed))
          _note('第 ${failed.pass} 次（${failed.variant}）失败：${failed.failure ?? ''}'),
      ],
    ];
  }

  List<Widget> _results(SpeedTestRunner runner) {
    final groups = GroupSummary.of(runner.results);
    if (groups.isEmpty) return const [];
    return [
      const SizedBox(height: DevToolsTheme.tableGap - DevToolsTheme.noteLineGap),
      _ResultsTable(groups: groups, label: (name) => _label(runner.plan?.plan.variant(name), name)),
      const SizedBox(height: DevToolsTheme.tableGap - DevToolsTheme.noteLineGap),
      _note(
        '单位为秒；跳转为中位数，超时按 15 秒计；卡顿为各次合计；内存为峰值 MB。'
        '冷 = 每个视频的第一次（CDN 还没缓存），热 = 之后各次。',
      ),
    ];
  }

  /// A PC plan's plain BTR variants all read BTR, so those keep their letters.
  static String _label(SpeedTestVariant? variant, String name) {
    final label = variant?.label;
    return label == null || label == 'BTR' ? name : label;
  }

  static String _status(SpeedTestRunner runner) {
    final plan = runner.plan;
    final pass = runner.pass;
    return [
      if (plan != null) '计划 ${plan.plan.id}（${plan.source == PlanSource.pc ? '电脑' : '内置，${plan.note}'}）',
      if (pass != null) ...['第 ${pass.index}/${runner.passCount} 次', _label(pass.variant, pass.variant.name), _quality(pass.quality)],
      if (runner.step.isNotEmpty) runner.step,
    ].join(' · ');
  }

  static Widget _note(String text, {Key? key, Color color = DevToolsTheme.note}) => Builder(
    builder: (context) {
      final style = TextStyle(fontFamily: BiliFonts.family, fontSize: DevToolsTheme.noteText, color: color);
      return Text(text, key: key, style: style, strutStyle: BiliFonts.strutOf(context, style));
    },
  );
}

String _quality(int qn) => QualityNames.short(qn: qn, serverText: null);

class _LinksField extends StatelessWidget {
  const _LinksField({required this.links, required this.enabled});

  final TextEditingController links;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontFamily: BiliFonts.family, fontSize: DevToolsTheme.fieldText, color: BiliColors.text);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SettingsTheme.rowInset,
        DevToolsTheme.fieldVertical,
        SettingsTheme.rowInset,
        DevToolsTheme.fieldVertical,
      ),
      child: TextField(
        key: const ValueKey('speedtest-links'),
        controller: links,
        enabled: enabled,
        minLines: 2,
        maxLines: 5,
        keyboardType: TextInputType.multiline,
        style: style,
        decoration: InputDecoration.collapsed(
          hintText: '速度测试的视频链接，每行一个；留空用电脑上的计划',
          hintStyle: style.copyWith(color: DevToolsTheme.fieldHint),
        ),
      ),
    );
  }
}

class _Stage extends StatelessWidget {
  const _Stage(this.controller, this.builder);

  final PlaybackController controller;
  final StageBuilder builder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, controller.danmaku]),
    builder: (context, _) {
      if (controller.video != null) return builder(context, controller);
      final note = switch (controller.phase) {
        PlaybackPhase.failed => controller.error ?? '播放失败',
        _ => '正在打开…',
      };
      return Center(
        child: Text(
          note,
          key: const ValueKey('speedtest-stage-note'),
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: BiliFonts.family, fontSize: DevToolsTheme.noteText, color: BiliColors.onVideo),
        ),
      );
    },
  );
}

/// A row per variant, quality and cold or warm, then each later variant's difference from the first, lower being
/// better in every column. It shrinks to the card's width rather than overflow it.
class _ResultsTable extends StatelessWidget {
  const _ResultsTable({required this.groups, required this.label});

  final List<GroupSummary> groups;

  /// A variant's letter as the plan names it (BTR·海外, 直连).
  final String Function(String variant) label;

  static const _columns = ['', '首帧', '跳转', 'P90', '最慢', '回跳', '卡顿', '内存'];

  static TextStyle _style(Color color) => TextStyle(
    fontFamily: BiliFonts.family,
    fontSize: DevToolsTheme.tableText,
    color: color,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Table(
        key: const ValueKey('speedtest-results'),
        defaultColumnWidth: const IntrinsicColumnWidth(),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          _row([for (final column in _columns) (column, DevToolsTheme.tableHeader)]),
          for (final group in groups)
            _row([
              (
                '${label(group.variant)} ${_quality(group.quality)} ${group.cold ? '冷' : '热'} ×${group.passes}',
                DevToolsTheme.tableInk,
              ),
              for (final ms in [
                group.firstFrameMs,
                group.seekMedianMs,
                group.seekP90Ms,
                group.seekMaxMs,
                group.backMedianMs,
              ])
                (_seconds(ms), DevToolsTheme.tableInk),
              ('${group.stalls}', DevToolsTheme.tableInk),
              ('${group.rssMaxMB}', DevToolsTheme.tableInk),
            ]),
          for (final delta in GroupDelta.of(groups))
            _row([
              (
                '${label(delta.other.variant)}−${label(delta.base.variant)} ${_quality(delta.base.quality)} '
                    '${delta.base.cold ? '冷' : '热'}',
                DevToolsTheme.tableInk,
              ),
              for (final ms in [
                delta.firstFrameMs,
                delta.seekMedianMs,
                delta.seekP90Ms,
                delta.seekMaxMs,
                delta.backMedianMs,
              ])
                (_signed(ms), _better(ms)),
              (_signedCount(delta.stalls), _better(delta.stalls.toDouble())),
              (_signedCount(delta.rssMaxMB), _better(delta.rssMaxMB.toDouble())),
            ]),
        ],
      ),
    ),
  );

  static TableRow _row(List<(String, Color)> cells) => TableRow(
    children: [
      for (final (index, (text, color)) in cells.indexed)
        Padding(
          padding: EdgeInsets.only(
            left: index == 0 ? 0 : DevToolsTheme.tableCellGap,
            bottom: DevToolsTheme.tableRowGap,
          ),
          child: Text(text, textAlign: index == 0 ? TextAlign.left : TextAlign.right, style: _style(color)),
        ),
    ],
  );

  static String _seconds(double? ms) => ms == null ? '–' : (ms / 1000).toStringAsFixed(2);

  static String _signed(double? ms) {
    if (ms == null) return '–';
    final text = (ms.abs() / 1000).toStringAsFixed(2);
    return ms < 0 ? '−$text' : '+$text';
  }

  static String _signedCount(int value) => value < 0 ? '−${-value}' : '+$value';

  static Color _better(double? difference) => difference == null || difference == 0
      ? DevToolsTheme.tableInk
      : (difference < 0 ? BiliColors.faster : BiliColors.slower);
}
