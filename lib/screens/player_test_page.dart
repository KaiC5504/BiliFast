import 'dart:async';

import 'package:bili_core/engine.dart';
import 'package:bili_core/logic.dart';
import 'package:flutter/material.dart';

import '../app/app_environment.dart';
import '../devtools/log_forwarder.dart';
import '../devtools/log_server_discovery.dart';
import '../playback/playback_controller.dart';
import '../playback/playback_setup.dart';
import '../player_ui/player_stage.dart';
import '../shared/theme.dart';
import '../speedtest/speed_test_plan.dart';
import '../speedtest/speed_test_results.dart';
import '../speedtest/speed_test_runner.dart';

typedef StageBuilder = Widget Function(BuildContext context, PlaybackController controller,
    {required bool showStats, required bool danmakuEnabled});

Widget playerStage(BuildContext context, PlaybackController controller,
        {required bool showStats, required bool danmakuEnabled}) =>
    PlayerStage(
      player: controller.player,
      clock: controller.clock,
      stats: controller.stats,
      showStats: showStats,
      duration: controller.duration,
      danmaku: controller.danmaku.timeline,
      danmakuEnabled: danmakuEnabled,
      onSeek: controller.userSeeked,
      onHint: controller.seekHint,
    );

/// The real plan fetch and engines.
const appSpeedTestHooks =
    SpeedTestHooks(choosePlan: choosePlan, startEngine: _startVariantEngine, appEngine: startPlatformEngine);

Future<PlaybackEngine> _startVariantEngine(SpeedTestVariant variant) =>
    startPlatformEngine(config: variant.config, connectionsPerHost: variant.connectionsPerHost);

/// Slice 1's whole app: the account the keychain login gave, a BV field, the player and its switches. KaiC checks
/// HDR, PiP, danmaku and seeking over the native player with it.
class PlayerTestPage extends StatefulWidget {
  const PlayerTestPage({
    super.key,
    required this.environment,
    required this.startPlayback,
    this.logs,
    this.stageBuilder = playerStage,
    this.initialLink,
    this.speedTestHooks = appSpeedTestHooks,
  });

  final AppEnvironment environment;
  final Future<PlaybackController> Function() startPlayback;

  /// Null when the build has no dev tools.
  final LogForwarder? logs;
  final StageBuilder stageBuilder;

  /// Played as soon as the player is up (`--play=<BV or link>` on the PC, for test runs).
  final String? initialLink;
  final SpeedTestHooks speedTestHooks;

  @override
  State<PlayerTestPage> createState() => _PlayerTestPageState();
}

class _PlayerTestPageState extends State<PlayerTestPage> with WidgetsBindingObserver {
  final _link = TextEditingController();
  final _testLinks = TextEditingController();
  late final TextEditingController _logAddress = TextEditingController(text: widget.logs?.manual ?? '');
  late final AppLifecycleListener _lifecycle;
  PlaybackController? _controller;

  /// Dev builds only, like the log section.
  SpeedTestRunner? _speedTest;
  String? _startError;
  bool _showStats = true;
  bool _danmakuEnabled = true;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_controller?.appResumed()));
    WidgetsBinding.instance.addObserver(this);
    widget.startPlayback().then((controller) {
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        if (widget.logs != null) {
          _speedTest = SpeedTestRunner(target: ControllerTarget(controller), hooks: widget.speedTestHooks);
        }
      });
      final link = widget.initialLink;
      if (link != null) {
        _link.text = link;
        unawaited(controller.open(link));
      }
    }, onError: (Object error) {
      if (mounted) setState(() => _startError = '$error');
    });
  }

  @override
  void didHaveMemoryPressure() => _controller?.memoryPressure();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lifecycle.dispose();
    // Before the controller, so sound and screen are put back while the player is still there.
    _speedTest?.dispose();
    _controller?.dispose();
    _link.dispose();
    _testLinks.dispose();
    _logAddress.dispose();
    super.dispose();
  }

  void _play() {
    final controller = _controller;
    if (controller == null || _link.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    unawaited(controller.open(_link.text));
  }

  void _startSpeedTest() {
    final runner = _speedTest;
    if (runner == null || runner.running) return;
    FocusScope.of(context).unfocus();
    final links = [
      for (final line in _testLinks.text.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
    unawaited(runner.start(links: links, server: widget.logs?.target));
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: BiliColors.pageGrey,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([widget.environment, ?controller, ?controller?.danmaku]),
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(BiliMetrics.gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AccountBar(environment: widget.environment),
                    const SizedBox(height: BiliMetrics.rowGap),
                    _LinkBar(link: _link, ready: controller != null, onPlay: _play),
                  ],
                ),
              ),
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ColoredBox(color: BiliColors.videoBackground, child: _stage(context, controller)),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(BiliMetrics.gutter),
                  children: [
                    if (controller != null) ..._playbackSection(controller),
                    if (widget.logs case final logs?) _LogSection(logs: logs, address: _logAddress),
                    if (_speedTest case final runner?) ...[
                      const SizedBox(height: BiliMetrics.sectionGap),
                      _SpeedTestSection(runner: runner, links: _testLinks, onStart: _startSpeedTest),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stage(BuildContext context, PlaybackController? controller) {
    if (controller == null) {
      return _VideoNote(_startError == null ? '播放器启动中…' : '播放器启动失败：$_startError');
    }
    if (controller.video == null) {
      return _VideoNote(switch (controller.phase) {
        PlaybackPhase.loading => '正在打开…',
        PlaybackPhase.failed => controller.error ?? '播放失败',
        _ => '粘贴链接或 BV 号，点播放',
      });
    }
    return widget.stageBuilder(context, controller, showStats: _showStats, danmakuEnabled: _danmakuEnabled);
  }

  List<Widget> _playbackSection(PlaybackController controller) {
    final video = controller.video;
    final page = controller.page;
    final playing = controller.playing;
    return [
      if (video != null)
        Text(
          (video.pages.length > 1 && page != null) ? '${video.title} · P${page.page} ${page.part}' : video.title,
          style: const TextStyle(fontSize: BiliMetrics.bodyText, color: BiliColors.text, fontWeight: FontWeight.w600),
        ),
      if (controller.phase == PlaybackPhase.failed && controller.video != null) ...[
        const SizedBox(height: BiliMetrics.rowGap),
        Text(controller.error ?? '播放失败',
            key: const ValueKey('playback-error'),
            style: const TextStyle(fontSize: BiliMetrics.bodyText, color: BiliColors.failure)),
      ],
      if (controller.phase == PlaybackPhase.failed && controller.playerFailure != null)
        Text('播放器：${controller.playerFailure}',
            style: const TextStyle(fontSize: BiliMetrics.smallText, color: BiliColors.secondaryText)),
      const SizedBox(height: BiliMetrics.rowGap),
      Text(
        [
          controller.modeLabel,
          if (playing != null) playing.line(qualityName: controller.qualityName(playing.quality)),
          if (controller.pictureInPicture) '小窗中',
        ].join(' · '),
        style: const TextStyle(fontSize: BiliMetrics.smallText, color: BiliColors.secondaryText),
      ),
      const SizedBox(height: BiliMetrics.sectionGap),
      _Card(children: [
        _Row(
          label: '加速',
          trailing: SegmentedButton<PlaybackMode>(
            key: const ValueKey('mode'),
            showSelectedIcon: false,
            segments: [
              for (final mode in PlaybackMode.values) ButtonSegment(value: mode, label: Text(mode.label)),
            ],
            selected: {controller.mode},
            onSelectionChanged: (selected) => unawaited(controller.setMode(selected.first)),
          ),
        ),
        _Row(
          label: '显示统计',
          trailing: Switch.adaptive(
            key: const ValueKey('stats-switch'),
            activeTrackColor: BiliColors.pink,
            value: _showStats,
            onChanged: (on) => setState(() => _showStats = on),
          ),
        ),
        _Row(
          label: controller.danmaku.closed ? '弹幕（UP 主已关闭）' : '弹幕',
          trailing: Switch.adaptive(
            key: const ValueKey('danmaku-switch'),
            activeTrackColor: BiliColors.pink,
            value: _danmakuEnabled,
            onChanged: (on) => setState(() => _danmakuEnabled = on),
          ),
        ),
        if (controller.player.capabilities.pictureInPicture)
          _Row(
            label: '小窗播放',
            trailing: OutlinedButton(
              key: const ValueKey('pip-button'),
              onPressed: controller.video == null ? null : () => unawaited(controller.startPictureInPicture()),
              child: const Text('小窗'),
            ),
          ),
      ]),
      if (controller.qualities.isNotEmpty) ...[
        const SizedBox(height: BiliMetrics.sectionGap),
        _Card(children: [
          const Text('清晰度', style: TextStyle(fontSize: BiliMetrics.bodyText, color: BiliColors.text)),
          const SizedBox(height: BiliMetrics.rowGap),
          Wrap(
            spacing: BiliMetrics.rowGap,
            runSpacing: BiliMetrics.rowGap,
            children: [
              for (final option in controller.qualities)
                ChoiceChip(
                  key: ValueKey('quality-${option.id}'),
                  label: Text(controller.qualityName(option.id)),
                  selected: option.id == (playing?.quality ?? controller.selectedQuality),
                  onSelected: (_) => unawaited(controller.setQuality(option.id)),
                ),
            ],
          ),
        ]),
      ],
      const SizedBox(height: BiliMetrics.sectionGap),
    ];
  }
}

class _AccountBar extends StatelessWidget {
  const _AccountBar({required this.environment});

  final AppEnvironment environment;

  @override
  Widget build(BuildContext context) {
    final label = environment.accountLabel;
    final account = environment.account;
    return Row(
      children: [
        Container(
          width: BiliMetrics.avatarSize,
          height: BiliMetrics.avatarSize,
          decoration: const BoxDecoration(color: BiliColors.pinkTint, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(
            account is LoggedIn && label.isNotEmpty ? label.characters.first : '?',
            style: const TextStyle(fontSize: BiliMetrics.bodyText, color: BiliColors.pink, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: BiliMetrics.rowGap),
        Flexible(
          child: Text(
            label,
            key: const ValueKey('account-name'),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: BiliMetrics.titleText, color: BiliColors.text, fontWeight: FontWeight.w600),
          ),
        ),
        if (account is LoggedIn && account.vip) ...[
          const SizedBox(width: BiliMetrics.rowGap),
          const _Tag('大会员'),
        ],
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
            color: BiliColors.pinkTint, borderRadius: BorderRadius.circular(BiliMetrics.cardRadius)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: BiliMetrics.tagPadding, vertical: BiliMetrics.tagVerticalPadding),
          child: Text(text, style: const TextStyle(fontSize: BiliMetrics.smallText, color: BiliColors.pink)),
        ),
      );
}

class _LinkBar extends StatelessWidget {
  const _LinkBar({required this.link, required this.ready, required this.onPlay});

  final TextEditingController link;
  final bool ready;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: BiliMetrics.fieldHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('link-field'),
                controller: link,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => onPlay(),
                style: const TextStyle(fontSize: BiliMetrics.bodyText, color: BiliColors.text),
                decoration: InputDecoration(
                  hintText: '粘贴链接或BV号',
                  hintStyle: const TextStyle(fontSize: BiliMetrics.bodyText, color: BiliColors.secondaryText),
                  filled: true,
                  fillColor: BiliColors.card,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: BiliMetrics.gutter),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(BiliMetrics.cardRadius),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: BiliMetrics.rowGap),
            FilledButton(
              key: const ValueKey('play-button'),
              onPressed: ready ? onPlay : null,
              style: FilledButton.styleFrom(
                backgroundColor: BiliColors.pink,
                foregroundColor: BiliColors.onPink,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BiliMetrics.cardRadius)),
              ),
              child: const Text('播放', style: TextStyle(fontSize: BiliMetrics.bodyText)),
            ),
          ],
        ),
      );
}

class _VideoNote extends StatelessWidget {
  const _VideoNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(BiliMetrics.gutter),
          child: Text(
            text,
            key: const ValueKey('video-note'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: BiliMetrics.bodyText, color: BiliColors.onVideo),
          ),
        ),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: BiliColors.card, borderRadius: BorderRadius.circular(BiliMetrics.cardRadius)),
        child: Padding(
          padding: const EdgeInsets.all(BiliMetrics.gutter),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.trailing});

  final String label;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: BiliMetrics.rowGap / 2),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: BiliMetrics.bodyText, color: BiliColors.text)),
            ),
            trailing,
          ],
        ),
      );
}

class _LogSection extends StatelessWidget {
  const _LogSection({required this.logs, required this.address});

  final LogForwarder logs;
  final TextEditingController address;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: logs,
        builder: (context, _) => _Card(children: [
          _Row(
            label: '发送日志到电脑',
            trailing: Switch.adaptive(
              key: const ValueKey('log-switch'),
              activeTrackColor: BiliColors.pink,
              value: logs.enabled,
              onChanged: logs.setEnabled,
            ),
          ),
          if (logs.enabled) ...[
            for (final server in logs.discovered) _ServerTile(server: server, logs: logs),
            const SizedBox(height: BiliMetrics.rowGap),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('log-address'),
                    controller: address,
                    keyboardType: TextInputType.url,
                    onSubmitted: logs.setManual,
                    style: const TextStyle(fontSize: BiliMetrics.bodyText, color: BiliColors.text),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '或手动输入 IP:端口（默认 ${LogServerEndpoint.defaultPort}）',
                      hintStyle: TextStyle(fontSize: BiliMetrics.smallText, color: BiliColors.secondaryText),
                    ),
                  ),
                ),
                TextButton(
                  key: const ValueKey('log-connect'),
                  onPressed: () => logs.setManual(address.text),
                  child: const Text('连接'),
                ),
              ],
            ),
          ],
          const SizedBox(height: BiliMetrics.rowGap),
          Text(logs.status,
              key: const ValueKey('log-status'),
              style: const TextStyle(fontSize: BiliMetrics.smallText, color: BiliColors.secondaryText)),
        ]),
      );
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({required this.server, required this.logs});

  final LogServerEndpoint server;
  final LogForwarder logs;

  @override
  Widget build(BuildContext context) {
    final selected = logs.service?.host == server.host && logs.service?.port == server.port;
    return InkWell(
      onTap: () => logs.selectService(selected ? null : server),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: BiliMetrics.rowGap),
        child: Row(
          children: [
            Expanded(
              child: Text(server.name, style: const TextStyle(fontSize: BiliMetrics.bodyText, color: BiliColors.text)),
            ),
            if (selected) const Icon(Icons.check, color: BiliColors.pink, size: BiliMetrics.iconSize),
          ],
        ),
      ),
    );
  }
}

class _SpeedTestSection extends StatelessWidget {
  const _SpeedTestSection({required this.runner, required this.links, required this.onStart});

  final SpeedTestRunner runner;
  final TextEditingController links;
  final VoidCallback onStart;

  static const _secondary = TextStyle(fontSize: BiliMetrics.smallText, color: BiliColors.secondaryText);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: runner,
        builder: (context, _) {
          final groups = GroupSummary.of(runner.results);
          final error = runner.error;
          final status = _status;
          return _Card(children: [
            _Row(
              label: '速度测试',
              trailing: runner.running
                  ? OutlinedButton(
                      key: const ValueKey('speedtest-stop'),
                      onPressed: runner.cancelled ? null : runner.stop,
                      child: const Text('停止'),
                    )
                  : FilledButton(
                      key: const ValueKey('speedtest-start'),
                      onPressed: onStart,
                      style: FilledButton.styleFrom(
                          backgroundColor: BiliColors.pink, foregroundColor: BiliColors.onPink),
                      child: const Text('开始测试'),
                    ),
            ),
            TextField(
              key: const ValueKey('speedtest-links'),
              controller: links,
              enabled: !runner.running,
              minLines: 2,
              maxLines: 5,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(fontSize: BiliMetrics.smallText, color: BiliColors.text),
              decoration: const InputDecoration(
                isDense: true,
                hintText: '每行一个链接，留空则用电脑上的计划或当前视频',
                hintStyle: _secondary,
              ),
            ),
            const SizedBox(height: BiliMetrics.rowGap),
            if (status.isNotEmpty) Text(status, key: const ValueKey('speedtest-status'), style: _secondary),
            if (error != null)
              Text(error,
                  key: const ValueKey('speedtest-error'),
                  style: const TextStyle(fontSize: BiliMetrics.smallText, color: BiliColors.failure)),
            for (final note in runner.notes) Text(note, style: _secondary),
            for (final failed in runner.results.where((pass) => pass.failed))
              Text('第 ${failed.pass} 次（${failed.variant}）失败：${failed.failure ?? ''}', style: _secondary),
            if (groups.isNotEmpty) ...[
              const SizedBox(height: BiliMetrics.rowGap),
              _SpeedTestTable(groups: groups),
              const SizedBox(height: BiliMetrics.rowGap),
              const Text('时间为秒（中位数），跳转超时按 15 秒计；卡顿为各次合计；内存为峰值 MB', style: _secondary),
            ],
          ]);
        },
      );

  String get _status {
    final plan = runner.plan;
    final pass = runner.pass;
    return [
      if (plan != null) '计划 ${plan.plan.id}（${plan.source == PlanSource.pc ? '电脑' : '内置，${plan.note}'}）',
      if (pass != null) ...['第 ${pass.index}/${runner.passCount} 次', pass.variant.name, _quality(pass.quality)],
      if (runner.step.isNotEmpty) runner.step,
    ].join(' · ');
  }
}

String _quality(int qn) => QualityNames.short(qn: qn, serverText: null);

/// One row per variant and quality, then each later variant's difference from the first.
class _SpeedTestTable extends StatelessWidget {
  const _SpeedTestTable({required this.groups});

  final List<GroupSummary> groups;

  static const _style = TextStyle(fontSize: BiliMetrics.smallText, color: BiliColors.text);
  static const _header = TextStyle(fontSize: BiliMetrics.smallText, color: BiliColors.secondaryText);

  @override
  Widget build(BuildContext context) => Table(
        key: const ValueKey('speedtest-results'),
        defaultColumnWidth: const IntrinsicColumnWidth(),
        columnWidths: const {2: FlexColumnWidth()},
        children: [
          _row(const ['', '首帧', '跳转 中位/P90/最慢', '回跳', '卡顿', '内存'], _header),
          for (final group in groups)
            _row([
              '${group.variant} ${_quality(group.quality)} ×${group.passes}',
              _seconds(group.firstFrameMs),
              [group.seekMedianMs, group.seekP90Ms, group.seekMaxMs].map(_seconds).join('/'),
              _seconds(group.backMedianMs),
              '${group.stalls}',
              '${group.rssMaxMB}',
            ], _style),
          for (final delta in GroupDelta.of(groups))
            TableRow(children: [
              _cell('${delta.other.variant}−${delta.base.variant} ${_quality(delta.base.quality)}', _style),
              _cell(_signed(delta.firstFrameMs), _better(delta.firstFrameMs)),
              _cell([delta.seekMedianMs, delta.seekP90Ms, delta.seekMaxMs].map(_signed).join('/'),
                  _better(delta.seekMedianMs)),
              _cell(_signed(delta.backMedianMs), _better(delta.backMedianMs)),
              _cell(_signedCount(delta.stalls), _better(delta.stalls.toDouble())),
              _cell(_signedCount(delta.rssMaxMB), _better(delta.rssMaxMB.toDouble())),
            ]),
        ],
      );

  static TableRow _row(List<String> cells, TextStyle style) =>
      TableRow(children: [for (final text in cells) _cell(text, style)]);

  static Widget _cell(String text, TextStyle style) => Padding(
        padding: const EdgeInsets.only(right: BiliMetrics.rowGap, bottom: BiliMetrics.rowGap / 2),
        child: Text(text, style: style),
      );

  static String _seconds(double? ms) => ms == null ? '–' : (ms / 1000).toStringAsFixed(2);

  static String _signed(double? ms) {
    if (ms == null) return '–';
    final text = (ms.abs() / 1000).toStringAsFixed(2);
    return ms < 0 ? '−$text' : '+$text';
  }

  static String _signedCount(int value) => value < 0 ? '−${-value}' : '+$value';

  /// Lower is better in every column.
  static TextStyle _better(double? difference) => TextStyle(
        fontSize: BiliMetrics.smallText,
        color: difference == null || difference == 0
            ? BiliColors.text
            : (difference < 0 ? BiliColors.faster : BiliColors.slower),
      );
}
