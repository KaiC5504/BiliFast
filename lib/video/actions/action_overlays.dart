import 'package:flutter/widgets.dart';

import '../../player_ui/end_screen_portrait.dart' show ShareLink, shareThroughSystem;
import 'video_actions.dart';

/// Puts up what the actions ask for, over the whole page in every presentation: the coin dialog, the favourites sheet,
/// the unfollow confirm, or the system share sheet (counted once it closes). Lets touches through when nothing is up.
class ActionOverlays extends StatelessWidget {
  const ActionOverlays({
    super.key,
    required this.actions,
    required this.landscape,
    required this.shareLink,
    this.share = shareThroughSystem,
  });

  /// Null until the video's detail arrives.
  final VideoActions? actions;
  final bool landscape;
  final Uri? shareLink;
  final ShareLink share;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
