import 'package:flutter/widgets.dart';

import '../end_screen_landscape.dart';
import '../player_ui.dart';

/// The iPad's full-screen end screen (ipad/16).
class PadEndFullScreen extends StatelessWidget {
  const PadEndFullScreen({super.key, required this.ui});

  final PlayerUi ui;

  @override
  Widget build(BuildContext context) => EndScreenLandscape(ui: ui);
}
