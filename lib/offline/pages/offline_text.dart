import 'package:flutter/widgets.dart';

import '../../shared/theme.dart';
import '../offline_models.dart';
import '../offline_size.dart';

/// The style every word on these pages draws with: the app's font, and with [line] an even line box, so a line can be
/// placed by its middle.
TextStyle offlineStyle(double size, Color color, {double? line, FontWeight weight = FontWeight.w400}) => TextStyle(
  fontFamily: BiliFonts.family,
  fontFamilyFallback: BiliFonts.fallback,
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: line == null ? null : line / size,
  leadingDistribution: line == null ? null : TextLeadingDistribution.even,
  letterSpacing: 0,
  decoration: TextDecoration.none,
);

/// One line of [text] in [style], cut with … where it runs out.
Widget offlineLine(String text, TextStyle style, {Key? key, TextAlign align = TextAlign.left, int maxLines = 1}) =>
    Text(
      text,
      key: key,
      style: style,
      strutStyle: BiliFonts.strut(style),
      maxLines: maxLines,
      softWrap: maxLines > 1,
      overflow: TextOverflow.ellipsis,
      textAlign: align,
    );

/// 06:23, or 1:02:03 past an hour.
String offlineClock(num seconds) {
  final total = seconds.isFinite && seconds > 0 ? seconds.floor() : 0;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final rest = total % 60;
  String two(int value) => value.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:${two(minutes)}:${two(rest)}' : '${two(minutes)}:${two(rest)}';
}

/// The cover's pill: watched / length once something was watched (145), else the length (156).
String coverTime(OfflineItem item) {
  final length = offlineClock(item.request.duration);
  return item.position > 0 ? '${offlineClock(item.position)} / $length' : length;
}

/// The row's state line (143, 146, 148); a failure says why, and whether a tap tries again.
String stateLabel(OfflineItem item) => switch (item.state) {
  OfflineState.downloading =>
    item.totalBytes > 0 ? '缓存中: ${formatBytes(item.bytes)}/${formatBytes(item.totalBytes)}' : '缓存中',
  OfflineState.waiting => '等待缓存',
  OfflineState.paused => '已暂停',
  OfflineState.done => '已缓存',
  OfflineState.failed => switch (item.failure) {
    OfflineFailure.disk => '空间不足，点击重试',
    OfflineFailure.unavailable => '视频已失效',
    OfflineFailure.network || OfflineFailure.unknown || null => '缓存失败，点击重试',
  },
};

/// 已使用59.7MB / 剩余74.4GB; 剩余- while the phone's free space is unknown.
String spaceLabel(int used, int? free) => '已使用${formatBytes(used)} / 剩余${free == null ? '-' : formatBytes(free)}';
