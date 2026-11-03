import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart' show canLaunchUrl;

import '../app/route_observer.dart';
import '../settings/settings_confirm.dart';
import '../shared/theme.dart';
import 'sideload_links.dart';
import 'sideload_model.dart';
import 'sideload_section.dart';

/// Models whose launch has had its one alert, or found none due. Kept on the model, one per launch, so a shell built
/// again doesn't ask again.
final _prompted = Expando<bool>('sideload prompted');

enum SideloadPrompt { expiry, release, reminder }

/// A sideloaded install's launch alert over the shell, 设置's alert (51): the signature running out, else a newer
/// release, else whether to remind before the signature runs out. At most one a launch; the release and the question
/// wait for the launch's release check to end ([SideloadModel.settled]). Only while the shell is the route showing: a
/// page or a popup over it holds the alert until it leaves.
class SideloadPrompts extends StatefulWidget {
  const SideloadPrompts({
    super.key,
    required this.model,
    @visibleForTesting this.openLink = launchOutside,
    @visibleForTesting this.canOpenLink = canLaunchUrl,
  });

  final SideloadModel model;
  final Future<bool> Function(Uri link) openLink;
  final Future<bool> Function(Uri link) canOpenLink;

  @override
  State<SideloadPrompts> createState() => _SideloadPromptsState();
}

class _Alert {
  const _Alert(
    this.prompt, {
    required this.title,
    required this.message,
    required this.action,
    required this.cancel,
    this.link,
  });

  final SideloadPrompt prompt;
  final String title;
  final String message;
  final String? action;
  final String cancel;

  /// Opened by [action].
  final Uri? link;
}

class _SideloadPromptsState extends State<SideloadPrompts> with RouteAware, SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: SettingsTheme.confirmIn,
    reverseDuration: SettingsTheme.confirmOut,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _motion,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  PageRoute<dynamic>? _route;
  bool _covered = false;
  Timer? _decision;

  /// The alert up and unanswered, or null once answered (it may still be fading out as [_shown]).
  _Alert? _asked;
  _Alert? _shown;

  SideloadModel get _model => widget.model;

  bool get _done => _prompted[_model] ?? false;

  @override
  void initState() {
    super.initState();
    _model.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    _motion
      ..duration = still ? Duration.zero : SettingsTheme.confirmIn
      ..reverseDuration = still ? Duration.zero : SettingsTheme.confirmOut;
    if (ModalRoute.of(context) case final PageRoute<dynamic> route when route != _route) {
      pageRoutes.unsubscribe(this);
      _route = route;
      pageRoutes.subscribe(this, route);
    }
    // ModalRoute.of runs this again whenever the route's isCurrent flips, so a popup leaving the shell (a sheet, the
    // app-auth prompt), which pageRoutes never reports, decides again too.
    _changed();
  }

  @override
  void didUpdateWidget(SideloadPrompts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model == widget.model) return;
    oldWidget.model.removeListener(_changed);
    _model.addListener(_changed);
    _changed();
  }

  @override
  void dispose() {
    _decision?.cancel();
    pageRoutes.unsubscribe(this);
    _model.removeListener(_changed);
    _curve.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  void didPushNext() => _covered = true;

  @override
  void didPopNext() {
    _covered = false;
    _changed();
  }

  /// Changes in a row make one decision, after the frame that brought them; nothing is armed for an install that
  /// isn't sideloaded.
  void _changed() {
    if (_done || !_model.sideloaded) return;
    _decision ??= Timer(Duration.zero, () {
      _decision = null;
      unawaited(_decide());
    });
  }

  Future<void> _decide() async {
    final model = _model;
    if (!mounted || _done || !model.sideloaded) return;
    // Covered by a page or a popup: its leaving decides again, through didPopNext or didChangeDependencies.
    if (_covered || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final SideloadPrompt? prompt;
    if (model.shouldWarnExpiry) {
      prompt = SideloadPrompt.expiry;
    } else if (!model.settled || model.checking) {
      // The check's end notifies, and a release beats the reminder question.
      return;
    } else if (model.shouldAnnounceRelease) {
      prompt = SideloadPrompt.release;
    } else if (model.shouldAskReminder) {
      prompt = SideloadPrompt.reminder;
    } else {
      prompt = null;
    }
    _prompted[model] = true;
    if (prompt == null) return;
    final alert = await _alert(prompt);
    if (!mounted || alert == null) return;
    Logger.shared.info(LogCategory.ui, 'sideload prompt', {'prompt': prompt.name});
    setState(() => _asked = _shown = alert);
    unawaited(_motion.forward());
  }

  Future<_Alert?> _alert(SideloadPrompt prompt) async {
    switch (prompt) {
      case SideloadPrompt.expiry:
        final days = _model.daysLeft ?? 0;
        final sideStore = await tryLink(sideStoreOpen, widget.canOpenLink);
        return _Alert(
          prompt,
          title: '签名快过期了',
          message: '${days == 0 ? '今天到期' : '还剩 $days 天'}，过期后 BiliFast 会打不开，记得在 SideStore 或电脑上重新签名。',
          action: sideStore ? '打开 SideStore' : null,
          cancel: '知道了',
          link: sideStore ? sideStoreOpen : null,
        );
      case SideloadPrompt.release:
        final newer = _model.newer;
        if (newer == null) return null;
        return _Alert(
          prompt,
          title: '有新版本 ${releaseLabel(newer)}',
          message: '在 SideStore、AltStore 或 Feather 里更新，或者下载新的 IPA 覆盖安装。',
          action: '下载',
          cancel: '稍后',
          link: newer.page,
        );
      case SideloadPrompt.reminder:
        return _Alert(
          prompt,
          title: '签名到期前提醒你？',
          message: '免费 Apple ID 签名 7 天后过期，到期前一天发通知提醒你重新签名。',
          action: '好',
          cancel: '不用',
        );
    }
  }

  /// The pink button when [yes], else the other, the dim or back.
  void _answer(_Alert alert, bool yes) {
    if (_asked != alert) return;
    Logger.shared.info(LogCategory.ui, 'sideload prompt answered', {'prompt': alert.prompt.name, 'yes': yes});
    switch (alert.prompt) {
      case SideloadPrompt.expiry:
        _model.expiryWarned();
      case SideloadPrompt.release:
        _model.releaseAnnounced();
      case SideloadPrompt.reminder:
        unawaited(_model.answerReminder(yes));
    }
    if (alert.link case final link? when yes) unawaited(openOrToast(context, link, widget.openLink));
    setState(() => _asked = null);
    unawaited(
      _motion.reverse().then((_) {
        if (mounted && _asked == null) setState(() => _shown = null);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    if (shown == null) return const SizedBox.shrink();
    final up = _asked != null;
    return PopScope(
      canPop: !up,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_asked case final asked?) _answer(asked, false);
      },
      child: IgnorePointer(
        ignoring: !up,
        child: ExcludeSemantics(
          excluding: !up,
          // Up, it is modal: VoiceOver reads only it, not the page under it.
          child: BlockSemantics(
            blocking: up,
            child: SettingsConfirm(
              key: ValueKey('sideload-prompt-${shown.prompt.name}'),
              title: shown.title,
              message: shown.message,
              action: shown.action,
              onConfirm: shown.action == null ? null : () => _answer(shown, true),
              cancel: shown.cancel,
              onCancel: () => _answer(shown, false),
              motion: _curve,
            ),
          ),
        ),
      ),
    );
  }
}
