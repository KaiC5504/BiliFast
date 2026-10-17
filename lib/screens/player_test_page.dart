import 'dart:async';

import 'package:bili_core/engine.dart';
import 'package:flutter/material.dart';

import '../app/app_environment.dart';
import '../devtools/log_forwarder.dart';
import '../devtools/log_server_discovery.dart';
import '../playback/playback_controller.dart';
import '../player_ui/player_stage.dart';
import '../shared/theme.dart';

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
    );

/// Slice 1's whole app: the account the keychain login gave, a BV field, the player and its switches. KaiC checks
/// HDR, PiP, danmaku and seeking over the native player with it.
class PlayerTestPage extends StatefulWidget {
  const PlayerTestPage({
    super.key,
    required this.environment,
    required this.startPlayback,
    this.logs,
    this.stageBuilder = playerStage,
  });

  final AppEnvironment environment;
  final Future<PlaybackController> Function() startPlayback;

  /// Null when the build has no dev tools.
  final LogForwarder? logs;
  final StageBuilder stageBuilder;

  @override
  State<PlayerTestPage> createState() => _PlayerTestPageState();
}

class _PlayerTestPageState extends State<PlayerTestPage> {
  final _link = TextEditingController();
  late final TextEditingController _logAddress = TextEditingController(text: widget.logs?.manual ?? '');
  late final AppLifecycleListener _lifecycle;
  PlaybackController? _controller;
  String? _startError;
  bool _showStats = true;
  bool _danmakuEnabled = true;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_controller?.appResumed()));
    widget.startPlayback().then((controller) {
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    }, onError: (Object error) {
      if (mounted) setState(() => _startError = '$error');
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _controller?.dispose();
    _link.dispose();
    _logAddress.dispose();
    super.dispose();
  }

  void _play() {
    final controller = _controller;
    if (controller == null || _link.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    unawaited(controller.open(_link.text));
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
