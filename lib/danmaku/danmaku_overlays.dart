import 'package:flutter/widgets.dart';

import '../device/orientation.dart';
import 'danmaku_session.dart';

/// The send bar riding on the keyboard, with the style panel in the keyboard's place after A (22, 23, 36-39), as a
/// layer in the page's Stack. On the small player the page under the player dims (39).
// Contracts stub: slice 5's send agent writes it.
class DanmakuOverlays extends StatelessWidget {
  const DanmakuOverlays({
    super.key,
    required this.session,
    required this.presentation,
    required this.playerBottom,
    required this.toast,
  });

  final DanmakuSession session;
  final Presentation presentation;

  /// Where the small player ends on the page; the dim starts there.
  final double playerBottom;
  final ValueChanged<String> toast;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
