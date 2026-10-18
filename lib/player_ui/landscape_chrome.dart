import 'package:flutter/widgets.dart';

import 'player_ui.dart';

/// The landscape full-screen controls, filling the screen (BiliNative `LandscapeChrome.swift`).
class LandscapeChrome extends StatelessWidget {
  const LandscapeChrome({super.key, required this.ui});

  final PlayerUi ui;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
