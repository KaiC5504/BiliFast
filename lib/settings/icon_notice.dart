import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_core/devlog.dart';
import 'package:flutter/widgets.dart';

import '../app/swipe_back_route.dart';
import '../shared/theme.dart';
import 'app_icon.dart';
import 'app_icon_page.dart';
import 'settings_confirm.dart';

/// 1.5.0 made the cat the primary icon, so an install from before that showed the TV shows the cat after updating.
/// It is told once, with the way back (`icon_notice.json`). A fresh install, or one that had picked the cat, isn't.
final class IconNotice {
  IconNotice._(this._path, this._due);

  IconNotice.memory({bool due = false}) : this._(null, due);

  /// [earlierInstall]: the support folder held files before this launch wrote any.
  static Future<IconNotice> load(String? path, {required bool earlierInstall}) async {
    if (path == null) return IconNotice.memory();
    // Written once told, and at a fresh install's first launch.
    if (await File(path).exists()) return IconNotice._(path, false);
    final notice = IconNotice._(path, earlierInstall);
    if (!earlierInstall) await notice._write();
    return notice;
  }

  final String? _path;
  bool _due;

  bool get due => _due;

  Future<void> done() async {
    _due = false;
    await _write();
  }

  Future<void> _write() async {
    final path = _path;
    if (path == null) return;
    try {
      await File(path).writeAsString(jsonEncode({'told': true}));
    } catch (error) {
      // Unwritten, it is told again next launch.
      Logger.shared.warn(LogCategory.app, 'icon notice not saved', {'error': '${error.runtimeType}'});
    }
  }
}

/// The notice over the shell at launch, 设置's alert (51): 换回小电视 opens 应用图标. Only while the shell is the route
/// showing; a launch that opens a page first leaves it for the next.
class IconNoticePrompt extends StatefulWidget {
  const IconNoticePrompt({super.key, required this.notice, required this.host});

  final IconNotice notice;
  final AppIconHost host;

  @override
  State<IconNoticePrompt> createState() => _IconNoticePromptState();
}

class _IconNoticePromptState extends State<IconNoticePrompt> {
  @override
  void initState() {
    super.initState();
    if (widget.notice.due) WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_show()));
  }

  Future<void> _show() async {
    final notice = widget.notice;
    final String? iconSet;
    try {
      iconSet = await widget.host.iconSet();
    } catch (error) {
      Logger.shared.warn(LogCategory.app, 'app icon not read', {'error': '${error.runtimeType}'});
      return;
    }
    // An alternate icon was chosen before the update, so the home screen didn't change.
    if (iconSet != null) return notice.done();
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
    Logger.shared.info(LogCategory.ui, 'icon notice');
    final still = MediaQuery.disableAnimationsOf(context);
    final navigator = Navigator.of(context);
    final yes = await navigator.push<bool>(
      RawDialogRoute<bool>(
        barrierDismissible: false,
        barrierColor: null,
        transitionDuration: still ? Duration.zero : SettingsTheme.confirmIn,
        transitionBuilder: (context, animation, secondary, child) => child,
        pageBuilder: (context, animation, secondary) => SettingsConfirm(
          key: const ValueKey('icon-notice'),
          title: '图标换新了',
          message: '默认图标换成了猫猫。想用回小电视，可以在「设置 - 应用图标」里换。',
          action: '换回小电视',
          onConfirm: () => Navigator.of(context).pop(true),
          cancel: '知道了',
          onCancel: () => Navigator.of(context).pop(false),
          motion: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic),
        ),
      ),
    );
    Logger.shared.info(LogCategory.ui, 'icon notice answered', {'yes': yes == true});
    await notice.done();
    if (yes == true && mounted) {
      unawaited(navigator.push(SwipeBackPageRoute<void>(builder: (_) => AppIconPage(host: widget.host))));
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
