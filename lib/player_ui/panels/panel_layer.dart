import 'package:flutter/widgets.dart';

import '../player_ui.dart';

/// The open panel, if any (BiliNative `PanelLayer.swift` and `SidePanel.swift`): from the right in landscape, a
/// bottom sheet in portrait, closed by a tap outside it. The page puts it over everything, filling the page.
class PanelLayer extends StatelessWidget {
  const PanelLayer({super.key, required this.ui});

  final PlayerUi ui;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
