import 'package:flutter/widgets.dart';

import '../player_ui.dart';

/// 弹幕设置: a right-side panel in landscape (07, 08, 24, 29), the light sheet in portrait (40, 41).
// Contracts stub: slice 5's settings-panel agent writes it.
class DanmakuSettingsPanel extends StatelessWidget {
  const DanmakuSettingsPanel({
    super.key,
    required this.ui,
    required this.light,
    required this.toast,
    required this.close,
  });

  final PlayerUi ui;

  /// Portrait's light sheet.
  final bool light;
  final ValueChanged<String> toast;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
