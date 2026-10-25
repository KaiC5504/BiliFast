import '../shared/theme.dart';

/// The small player's full height for [width]: 16:9, or an upright video's own shape (17) unless it has [ended], when
/// the end screen takes the 16:9 box (18).
double inlinePlayerHeight(double width, {({int width, int height})? video, bool ended = false}) =>
    width / BiliMetrics.videoAspect;
