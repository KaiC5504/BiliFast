import 'package:flutter/widgets.dart';

import '../landscape_chrome.dart';
import '../player_ui.dart';

/// The iPad's full-screen controls (ipad/08, 14, 15, 18, 24), in either orientation.
class PadFullScreenChrome extends StatelessWidget {
  const PadFullScreenChrome({super.key, required this.ui});

  final PlayerUi ui;

  @override
  Widget build(BuildContext context) => LandscapeChrome(ui: ui);
}
