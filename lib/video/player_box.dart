import 'dart:math' as math;

import '../shared/theme.dart';

/// The small player's full height for [width]: 16:9, or an upright video's own shape (17) up to [limit] times the width
/// unless it has [ended], when the end screen takes the 16:9 box (18).
double inlinePlayerHeight(
  double width, {
  ({int width, int height})? video,
  bool ended = false,
  double limit = CollapseTheme.uprightLimit,
}) {
  final widescreen = width / BiliMetrics.videoAspect;
  if (ended || video == null || video.width <= 0 || video.height <= video.width) return widescreen;
  return width * math.min(video.height / video.width, limit);
}
