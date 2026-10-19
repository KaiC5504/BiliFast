import 'package:flutter/widgets.dart';

import 'swipe_back_route.dart';

/// The global rect of the card a page was opened from, or null while that card is off screen or gone.
typedef ZoomSource = Rect? Function();

/// A video page opened from a 推荐 card (03, 04 in local/differences): a swipe from the left edge shrinks the page
/// into a floating card that follows the finger over the dimmed home; let go and it springs back, or flies into
/// [source]. Opening is the plain push.
class ZoomBackPageRoute<T> extends SwipeBackPageRoute<T> {
  ZoomBackPageRoute({required super.builder, required this.source, super.settings});

  final ZoomSource source;
}
