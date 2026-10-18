import 'package:flutter/widgets.dart';

import 'player_ui.dart';

/// The full-screen end screen (BiliNative `EndScreens.swift`): 重播, 分享 and a row of related videos. It fills the
/// screen.
class EndScreenLandscape extends StatelessWidget {
  const EndScreenLandscape({super.key, required this.ui});

  final PlayerUi ui;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
