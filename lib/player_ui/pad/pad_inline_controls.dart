import 'package:flutter/widgets.dart';

import '../portrait_controls.dart';
import '../player_ui.dart';

/// The controls over the iPad page's player (ipad/03, 07).
class PadInlineControls extends StatelessWidget {
  const PadInlineControls({super.key, required this.ui});

  final PlayerUi ui;

  @override
  Widget build(BuildContext context) => PortraitControls(ui: ui);
}
