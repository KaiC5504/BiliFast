import 'dart:async';

import 'package:bili_core/api.dart' show OfficialIdentity;
import 'package:bili_core/devlog.dart';
import 'package:bili_core/engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../account/app_auth.dart';
import '../app/app_scope.dart';
import '../app/form_factor.dart';
import '../app/swipe_back_route.dart';
import '../home/feed_model.dart' show requestFailureMessage;
import '../playback/playback_controller.dart';
import '../playback/playback_setup.dart';
import '../playback/shared_engine.dart';
import '../player_ui/player_stage.dart';
import '../settings/settings_confirm.dart';
import '../settings/settings_page.dart';
import '../shared/toast.dart';
import '../shared/theme.dart';
import '../speedtest/speed_test_plan.dart';
import '../speedtest/speed_test_runner.dart';
import '../video/player_prefs.dart';
import 'crash_log.dart';
import 'developer_logs.dart';
import 'developer_rows.dart';
import 'developer_speed_test.dart';
import 'developer_status.dart';
import 'log_forwarder.dart';
import 'node_probe_section.dart';

export 'developer_speed_test.dart' show StageBuilder;

/// The speed test's player, with its stats on.
Widget playerStage(BuildContext context, PlaybackController controller) => PlayerStage(
  player: controller.player,
  clock: controller.clock,
  stats: controller.stats,
  showStats: true,
  duration: controller.duration,
  danmaku: controller.danmaku.timeline,
  danmakuEnabled: true,
  onSeek: controller.userSeeked,
  onHint: controller.seekHint,
);

/// The real plan fetch and engines.
const appSpeedTestHooks = SpeedTestHooks(
  choosePlan: choosePlan,
  startEngine: _startVariantEngine,
  appEngine: startPlatformEngine,
);

Future<PlaybackEngine> _startVariantEngine(SpeedTestVariant variant) =>
    startPlatformEngine(config: variant.config, connectionsPerHost: variant.connectionsPerHost);

/// The app's: each variant runs on an engine of its own, so the pages' [shared] engine is never swapped, and a run
/// ends back on a lease of [shared].
SpeedTestHooks appSpeedTestHooksOn(SharedEngine? shared) => shared == null
    ? appSpeedTestHooks
    : SpeedTestHooks(choosePlan: choosePlan, startEngine: _startVariantEngine, appEngine: shared.lease);

/// Hands a file to the share sheet, which on an iPad points at [origin].
typedef ShareFile = Future<void> Function(String path, Rect? origin);

Future<void> shareFileThroughSystem(String path, Rect? origin) async {
  await SharePlus.instance.share(ShareParams(files: [XFile(path)], sharePositionOrigin: origin));
}

/// 设置 → 开发者 (dev builds), in 设置's look: 网络 (节点测速, 速度测试), 状态, 调试 (旋转动画, 官方接口) and 日志 (the
/// forwarder, 导出日志, 测试崩溃).
class DeveloperPage extends StatefulWidget {
  const DeveloperPage({
    super.key,
    required this.startPlayback,
    this.releasePlayback,
    this.logs,
    this.speedTestHooks = appSpeedTestHooks,
    this.stageBuilder = playerStage,
    this.shareFile = shareFileThroughSystem,
    this.prefs,
    this.appAuth,
    this.version,
  });

  /// The speed test's player, asked for when the first run starts.
  final Future<PlaybackController> Function() startPlayback;

  /// Takes the player back when the page leaves (the app's AppPlayback.release); without it the page disposes it.
  final void Function(PlaybackController controller)? releasePlayback;

  /// Null leaves the forwarder out.
  final LogForwarder? logs;
  final SpeedTestHooks speedTestHooks;
  final StageBuilder stageBuilder;

  /// Tests pass their own so nothing reaches the platform.
  final ShareFile shareFile;

  /// [PlayerPrefs.shared] unless a test passes its own.
  final PlayerPrefs? prefs;

  /// The official API's token, for the 官方接口 rows; without it they are left out.
  final AppAuth? appAuth;

  /// The build's own unless a test passes one.
  final String? version;

  @override
  State<DeveloperPage> createState() => _DeveloperPageState();
}

class _DeveloperPageState extends State<DeveloperPage> with SingleTickerProviderStateMixin {
  final _links = TextEditingController();
  late final TextEditingController _logAddress = TextEditingController(text: widget.logs?.manual ?? '');
  PlaybackController? _controller;
  SpeedTestRunner? _speedTest;
  bool _playerStarting = false;
  String? _playerError;
  bool _left = false;
  bool _exporting = false;

  late final AnimationController _confirmMotion = AnimationController(
    vsync: this,
    duration: SettingsTheme.confirmIn,
    reverseDuration: SettingsTheme.confirmOut,
  );
  late final CurvedAnimation _confirmCurve = CurvedAnimation(
    parent: _confirmMotion,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// 测试崩溃's confirm is up; [_confirmShown] stays while it fades out.
  bool _confirming = false;
  bool _confirmShown = false;

  PlayerPrefs get _prefs => widget.prefs ?? PlayerPrefs.shared;

  /// Only the iPhone draws its own turns: the iPad and the PC leave them to the system.
  static bool get _canTakeOverTurns =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS && !FormFactor.device.isPad;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    _confirmMotion
      ..duration = still ? Duration.zero : SettingsTheme.confirmIn
      ..reverseDuration = still ? Duration.zero : SettingsTheme.confirmOut;
  }

  @override
  void dispose() {
    // Before the player goes, so sound and screen are put back while it is still there.
    _leave();
    if (_controller case final controller?) _giveBack(controller, widget.releasePlayback);
    _links.dispose();
    _logAddress.dispose();
    _confirmCurve.dispose();
    _confirmMotion.dispose();
    super.dispose();
  }

  /// At the pop, not at dispose half a second later, so a run stops with the swipe.
  void _leave() {
    if (_left) return;
    _left = true;
    _speedTest?.dispose();
  }

  static void _giveBack(PlaybackController controller, void Function(PlaybackController)? release) {
    if (release != null) {
      release(controller);
    } else {
      controller.dispose();
    }
  }

  Future<void> _startSpeedTest() async {
    if (_left || _playerStarting || (_speedTest?.running ?? false)) return;
    FocusScope.of(context).unfocus();
    final runner = _speedTest ?? await _startPlayer();
    if (runner == null || _left) return;
    final links = [
      for (final line in _links.text.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
    final logs = widget.logs;
    unawaited(runner.start(links: links, server: logs != null && logs.enabled ? logs.target : null));
  }

  /// The player comes with the first run, so the page holds none until a test is asked for.
  Future<SpeedTestRunner?> _startPlayer() async {
    final release = widget.releasePlayback;
    setState(() {
      _playerStarting = true;
      _playerError = null;
    });
    final PlaybackController controller;
    try {
      controller = await widget.startPlayback();
    } catch (error) {
      if (mounted) {
        setState(() {
          _playerStarting = false;
          _playerError = requestFailureMessage(error, fallback: '${error.runtimeType}');
        });
      }
      return null;
    }
    if (!mounted || _left) {
      _giveBack(controller, release);
      return null;
    }
    final runner = SpeedTestRunner(target: ControllerTarget(controller), hooks: widget.speedTestHooks);
    setState(() {
      _controller = controller;
      _speedTest = runner;
      _playerStarting = false;
    });
    return runner;
  }

  void _pickTurn() {
    unawaited(
      Navigator.of(context).push(
        SwipeBackPageRoute<void>(
          builder: (_) => DeveloperChoicePage<bool>(
            title: '旋转动画',
            choices: const [(true, '自绘'), (false, '系统')],
            value: _prefs.turnTakeover,
            footer: '自绘照官方的转屏动画来画，系统用 iOS 自带的。下次转屏起生效。',
            onChanged: _setTurnTakeover,
          ),
        ),
      ),
    );
  }

  /// From the next turn on.
  void _setTurnTakeover(bool drawn) {
    setState(() => _prefs.turnTakeover = drawn);
    unawaited(AppScope.of(context).device.orientation.setTurnTakeover(drawn));
  }

  Future<void> _exportLogs(Rect? origin) async {
    if (_exporting) return;
    final files = AppScope.of(context).logFiles;
    setState(() => _exporting = true);
    String? path;
    var failed = false;
    try {
      path = await files.export();
    } catch (_) {
      // The export logged why.
      failed = true;
    }
    if (!mounted) return;
    setState(() => _exporting = false);
    if (path == null) {
      showToast(context, failed ? '导出日志失败' : '没有可导出的日志');
      return;
    }
    try {
      await widget.shareFile(path, origin);
    } catch (error) {
      Logger.shared.warn(LogCategory.ui, 'log share failed', {'error': '${error.runtimeType}'});
      if (mounted) showToast(context, '无法打开分享');
    }
  }

  void _askCrash() {
    setState(() => _confirming = _confirmShown = true);
    unawaited(_confirmMotion.forward());
  }

  void _dismiss() {
    if (!_confirming) return;
    setState(() => _confirming = false);
    unawaited(
      _confirmMotion.reverse().then((_) {
        if (mounted && !_confirming) setState(() => _confirmShown = false);
      }),
    );
  }

  /// A Dart error the app doesn't catch, thrown from the next frame's callbacks, so the framework hands it to
  /// CrashLog as it would any other. Native crashes aren't captured yet, so the app carries on.
  void _crash() {
    if (!_confirming) return;
    _dismiss();
    Logger.shared.warn(LogCategory.ui, 'test crash');
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => throw DeveloperTestCrash())
      ..scheduleFrame();
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: !_confirming,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) {
        _leave();
      } else {
        _dismiss();
      }
    },
    child: Stack(
      children: [
        SettingsScaffold(
          title: '开发者',
          children: [
            DeveloperGroup(
              title: '网络',
              children: [
                const NodeProbeSection(),
                DeveloperSpeedTest(
                  runner: _left ? null : _speedTest,
                  controller: _controller,
                  links: _links,
                  starting: _playerStarting,
                  playerError: _playerError,
                  stageBuilder: widget.stageBuilder,
                  onStart: () => unawaited(_startSpeedTest()),
                ),
              ],
            ),
            DeveloperGroup(
              title: '状态',
              children: [DeveloperStatus(version: widget.version ?? buildVersionLabel())],
            ),
            DeveloperGroup(title: '调试', children: [_debugSection()]),
            DeveloperGroup(
              title: '日志',
              children: [
                DeveloperLogs(
                  logs: widget.logs,
                  address: _logAddress,
                  exporting: _exporting,
                  onExport: (origin) => unawaited(_exportLogs(origin)),
                  onCrash: _askCrash,
                ),
              ],
            ),
            const SizedBox(height: DevToolsTheme.pageBottom),
          ],
        ),
        if (_confirmShown)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_confirming,
              child: ExcludeSemantics(
                excluding: !_confirming,
                child: BlockSemantics(
                  blocking: _confirming,
                  child: SettingsConfirm(
                    title: '让应用立即崩溃？',
                    message: '会抛出一个未捕获的 Dart 错误，崩溃报告作为 crash 事件发送到电脑。',
                    action: '崩溃',
                    motion: _confirmCurve,
                    onConfirm: _crash,
                    onCancel: _dismiss,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _debugSection() {
    final turn = _prefs.turnTakeover ? '自绘' : '系统';
    final appAuth = widget.appAuth;
    return ListenableBuilder(
      listenable: Listenable.merge([?appAuth]),
      builder: (context, _) => SettingsSection(
        children: [
          if (_canTakeOverTurns)
            SettingsRow(key: const ValueKey('dev-turn'), title: '旋转动画', value: turn, onTap: _pickTurn)
          else
            SettingsRow(key: const ValueKey('dev-turn'), title: '旋转动画', value: '$turn（仅 iPhone）', enabled: false),
          if (appAuth != null) ...[
            SettingsRow(key: const ValueKey('app-auth-state'), title: '官方接口', value: _authState(appAuth)),
            DeveloperActionRow(
              key: const ValueKey('app-auth-button'),
              title: appAuth.authorized ? '重新授权' : '授权',
              onTap: () => unawaited(appAuth.authorized ? appAuth.reauthorize(context) : appAuth.request(context)),
            ),
          ],
        ],
      ),
    );
  }

  static String _authState(AppAuth appAuth) {
    final expiresAt = appAuth.expiresAt;
    final identity = appAuth.identity;
    if (!appAuth.authorized || expiresAt == null || identity == null) return '未授权';
    final app = switch (identity) {
      OfficialIdentity.iphone => 'iPhone',
      OfficialIdentity.android => 'Android',
    };
    return '已授权 · $app · 剩 ${expiresAt.difference(DateTime.now()).inDays} 天';
  }
}
