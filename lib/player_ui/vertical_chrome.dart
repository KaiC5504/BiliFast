import 'package:flutter/widgets.dart';

import 'player_ui.dart';

/// 竖屏's controls, filling the screen (BiliNative `VerticalChrome.swift`).
class VerticalChrome extends StatelessWidget {
  const VerticalChrome({super.key, required this.ui});

  final PlayerUi ui;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
