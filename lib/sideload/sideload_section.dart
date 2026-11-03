import 'dart:async';

import 'package:bili_core/devlog.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../settings/settings_page.dart';
import '../shared/theme.dart';
import '../shared/toast.dart';
import 'sideload_links.dart';
import 'sideload_model.dart';

Future<bool> launchOutside(Uri link) => launchUrl(link, mode: LaunchMode.externalApplication);

/// Runs [open] on [link], false when it throws: launchUrl throws where nothing takes the scheme.
Future<bool> tryLink(Uri link, Future<bool> Function(Uri link) open) async {
  try {
    return await open(link);
  } catch (error) {
    Logger.shared.warn(LogCategory.ui, 'link not opened', {'scheme': link.scheme, 'error': '${error.runtimeType}'});
    return false;
  }
}

/// The signers that read the update source, by their add-source links.
enum SourceApp {
  sideStore('SideStore'),
  altStore('AltStore'),
  feather('Feather');

  const SourceApp(this.label);

  final String label;

  Uri get addSource => switch (this) {
    SourceApp.sideStore => sideStoreAddSource,
    SourceApp.altStore => altStoreAddSource,
    SourceApp.feather => featherAddSource,
  };
}

/// The signers on this device, as [canOpen] answers for their schemes (iOS only for those its Info.plist lists).
Future<List<SourceApp>> installedSourceApps(Future<bool> Function(Uri link) canOpen) async {
  final there = await Future.wait([for (final app in SourceApp.values) tryLink(app.addSource, canOpen)]);
  return [
    for (final (index, app) in SourceApp.values.indexed)
      if (there[index]) app,
  ];
}

/// 签名到期's value: "11月10日 · 还剩 3 天", or "11月10日 · 今天到期".
String expiryLabel(DateTime expires, int daysLeft) {
  final day = expires.toLocal();
  return '${day.month}月${day.day}日 · ${daysLeft == 0 ? '今天到期' : '还剩 $daysLeft 天'}';
}

/// A release as 设置 and the alert name it: "1.3.0 (9)".
String releaseLabel(ReleaseInfo release) => '${release.version} (${release.build})';

/// 设置's 签名 section for a sideloaded install: when the signature lapses, the reminder the day before, updates,
/// and the signers' update source. Nothing while the install isn't sideloaded.
class SideloadSection extends StatelessWidget {
  const SideloadSection({
    super.key,
    required this.model,
    required this.sources,
    required this.openLink,
    required this.canOpenLink,
  });

  /// From this many days left, 签名到期's value turns red.
  static const warnDays = 2;

  final SideloadModel model;
  final SourceChoiceController sources;
  final Future<bool> Function(Uri link) openLink;
  final Future<bool> Function(Uri link) canOpenLink;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) {
      final signature = model.signature;
      if (signature == null) return const SizedBox.shrink();
      final daysLeft = model.daysLeft ?? 0;
      final newer = model.newer;
      return SettingsSection(
        footer: '免费 Apple ID 签名 7 天后过期，到期前在 SideStore 或电脑上重新签名。',
        children: [
          SettingsRow(
            key: const ValueKey('settings-signature'),
            title: '签名到期',
            value: expiryLabel(signature.expires, daysLeft),
            valueColor: daysLeft <= warnDays ? BiliColors.failure : SettingsTheme.value,
          ),
          SettingsSwitchRow(
            key: const ValueKey('settings-reminder'),
            title: '到期提醒',
            value: model.reminderOn,
            onChanged: (on) => unawaited(model.setReminder(on)),
          ),
          SettingsRow(
            key: const ValueKey('settings-update'),
            title: '检查更新',
            value: model.checking
                ? '检查中…'
                : newer == null
                ? '已是最新'
                : '有新版本 ${releaseLabel(newer)}',
            onTap: () {
              if (model.newer != null) {
                unawaited(tryLink(Uri.parse(releasesPage), openLink));
              } else {
                unawaited(model.checkNow());
              }
            },
          ),
          SettingsRow(
            key: const ValueKey('settings-add-source'),
            title: '添加更新源',
            onTap: () => unawaited(sources.ask(canOpenLink)),
          ),
        ],
      );
    },
  );
}

/// Whether 添加更新源's choice is up, and the signers it lists.
class SourceChoiceController extends ChangeNotifier {
  /// The installed signers while the choice is up, else null.
  List<SourceApp>? get apps => _apps;
  List<SourceApp>? _apps;

  bool _asking = false;
  bool _disposed = false;

  /// Finds the installed signers, then puts the choice up.
  Future<void> ask(Future<bool> Function(Uri link) canOpen) async {
    if (_asking || _apps != null) return;
    _asking = true;
    try {
      final apps = await installedSourceApps(canOpen);
      if (_disposed) return;
      _apps = apps;
      notifyListeners();
    } finally {
      _asking = false;
    }
  }

  void close() {
    if (_apps == null) return;
    _apps = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// 添加更新源's choice over the page, in 51's alert: each installed signer, 复制源地址 and 取消, one under another.
/// Back and the dim close it.
class SourceChoiceLayer extends StatefulWidget {
  const SourceChoiceLayer({super.key, required this.controller, required this.openLink});

  final SourceChoiceController controller;
  final Future<bool> Function(Uri link) openLink;

  @override
  State<SourceChoiceLayer> createState() => _SourceChoiceLayerState();
}

class _SourceChoiceLayerState extends State<SourceChoiceLayer> with SingleTickerProviderStateMixin {
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

  /// What is drawn, still while it fades out.
  List<SourceApp>? _shown;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    _motion
      ..duration = still ? Duration.zero : SettingsTheme.confirmIn
      ..reverseDuration = still ? Duration.zero : SettingsTheme.confirmOut;
  }

  @override
  void didUpdateWidget(SourceChoiceLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_changed);
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _curve.dispose();
    _motion.dispose();
    super.dispose();
  }

  void _changed() {
    final apps = widget.controller.apps;
    if (apps != null) {
      setState(() => _shown = apps);
      unawaited(_motion.forward());
      return;
    }
    setState(() {});
    unawaited(
      _motion.reverse().then((_) {
        if (mounted && widget.controller.apps == null) setState(() => _shown = null);
      }),
    );
  }

  void _pick(SourceApp app) {
    if (widget.controller.apps == null) return;
    Logger.shared.info(LogCategory.ui, 'settings add source', {'app': app.name});
    widget.controller.close();
    unawaited(tryLink(app.addSource, widget.openLink));
  }

  Future<void> _copy() async {
    if (widget.controller.apps == null) return;
    widget.controller.close();
    await Clipboard.setData(const ClipboardData(text: sourceUrl));
    if (mounted) showToast(context, '已复制');
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    if (shown == null) return const SizedBox.shrink();
    final open = widget.controller.apps != null;
    return PopScope(
      canPop: !open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.controller.close();
      },
      child: IgnorePointer(
        ignoring: !open,
        child: ExcludeSemantics(
          excluding: !open,
          // Up, it is modal: VoiceOver reads only it, not the rows under it.
          child: BlockSemantics(
            blocking: open,
            child: _SourceChoice(
              apps: shown,
              motion: _curve,
              onPick: _pick,
              onCopy: () => unawaited(_copy()),
              onCancel: widget.controller.close,
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceChoice extends StatelessWidget {
  const _SourceChoice({
    required this.apps,
    required this.motion,
    required this.onPick,
    required this.onCopy,
    required this.onCancel,
  });

  final List<SourceApp> apps;
  final Animation<double> motion;
  final ValueChanged<SourceApp> onPick;
  final VoidCallback onCopy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    const rule = SizedBox(
      height: SettingsTheme.confirmRule,
      child: ColoredBox(color: SettingsTheme.confirmRuleColor),
    );
    return DefaultTextStyle(
      style: TextStyle(
        fontFamily: BiliFonts.family,
        fontFamilyFallback: BiliFonts.fallback,
        color: SettingsTheme.confirmTitle,
        decoration: TextDecoration.none,
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: FadeTransition(
              opacity: motion,
              child: Semantics(
                button: true,
                label: '取消',
                onTap: onCancel,
                excludeSemantics: true,
                child: GestureDetector(
                  key: const ValueKey('source-choice-dim'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onCancel,
                  child: const ColoredBox(color: SettingsTheme.confirmDim),
                ),
              ),
            ),
          ),
          Center(
            child: AnimatedBuilder(
              animation: motion,
              builder: (context, child) => Opacity(
                opacity: motion.value.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: SettingsTheme.confirmStartScale - (SettingsTheme.confirmStartScale - 1) * motion.value,
                  child: child,
                ),
              ),
              child: Container(
                key: const ValueKey('source-choice'),
                width: SettingsTheme.confirmWidth,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: SettingsTheme.confirm,
                  borderRadius: BorderRadius.circular(SettingsTheme.confirmRadius),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        SettingsTheme.confirmSide,
                        SettingsTheme.confirmTitleTop,
                        SettingsTheme.confirmSide,
                        SettingsTheme.confirmTitleTop,
                      ),
                      child: Text(
                        '添加更新源',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: BiliFonts.family,
                          fontSize: SettingsTheme.confirmTitleText,
                          height: SettingsTheme.confirmTitleLine / SettingsTheme.confirmTitleText,
                          fontWeight: SettingsTheme.confirmTitleWeight,
                          color: SettingsTheme.confirmTitle,
                        ),
                      ),
                    ),
                    for (final app in apps) ...[
                      rule,
                      _ChoiceButton(label: app.label, color: SettingsTheme.confirmAction, onTap: () => onPick(app)),
                    ],
                    rule,
                    _ChoiceButton(label: '复制源地址', color: SettingsTheme.confirmAction, onTap: onCopy),
                    rule,
                    _ChoiceButton(label: '取消', color: SettingsTheme.confirmCancel, onTap: onCancel),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceButton extends StatefulWidget {
  const _ChoiceButton({required this.label, required this.color, required this.onTap});

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_ChoiceButton> createState() => _ChoiceButtonState();
}

class _ChoiceButtonState extends State<_ChoiceButton> {
  var _down = false;

  void _press(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.label,
    onTap: widget.onTap,
    excludeSemantics: true,
    child: GestureDetector(
      key: ValueKey('source-choice-${widget.label}'),
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _press(true),
      onTapUp: (_) => _press(false),
      onTapCancel: () => _press(false),
      child: AnimatedContainer(
        duration: SettingsTheme.confirmPressMotion,
        height: SettingsTheme.confirmButtonHeight,
        color: _down ? SettingsTheme.confirmPressed : SettingsTheme.confirm,
        alignment: Alignment.center,
        child: Text(
          widget.label,
          style: TextStyle(
            fontFamily: BiliFonts.family,
            fontSize: SettingsTheme.confirmButtonText,
            color: widget.color,
          ),
        ),
      ),
    ),
  );
}
