import 'package:flutter/widgets.dart';

import '../end_screen_portrait.dart';
import '../player_ui.dart';

/// The end screen over the iPad page's player (ipad/17).
class PadEndInline extends StatelessWidget {
  const PadEndInline({super.key, required this.ui});

  final PlayerUi ui;

  @override
  Widget build(BuildContext context) => EndScreenPortrait(ui: ui);
}
